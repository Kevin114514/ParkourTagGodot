extends "res://scripts/tagger.gd"

const POLICY_PATH := "res://rl/trained_policy.json"
const VERTICAL_FALLBACK_GAP := 0.8
const CATCH_ATTEMPT_DISTANCE := 2.5
const ACTION_STEPS = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
	Vector2i(0, 0),
]

var rl_policy: Dictionary = {}
var rl_cell_size := 2.0
var rl_min_x := -27.0
var rl_min_z := -27.0
var rl_width := 28
var rl_height := 28
var rl_max_relative_cells := 14
var rl_catch_action_index := 8
var rl_version := 1
var rl_move_action_count := 9
var wants_catch_attempt := false
var rl_catch_ready := true
var rl_hit_progress := 0
var rl_hits_to_win := 10
var rl_time_remaining := 300.0
var rl_round_seconds := 300.0
var vertical_fallback_active := false
var rl_stuck_timer := 0.0

func _ready() -> void:
	super._ready()
	_load_policy()

func _physics_process(delta: float) -> void:
	if rl_policy.is_empty() or target == null:
		super._physics_process(delta)
		return
	if global_position.y < VOID_Y:
		_respawn()

	jump_cooldown = maxf(jump_cooldown - delta, 0.0)
	if velocity.y > MAX_UPWARD_VELOCITY:
		velocity.y = MAX_UPWARD_VELOCITY
	if not is_active:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		last_position = global_position
		return

	var vertical_gap := target.global_position.y - global_position.y
	if _should_use_vertical_fallback(vertical_gap):
		vertical_fallback_active = true
		wants_catch_attempt = _is_close_enough_for_catch()
		if wants_catch_attempt:
			_hold_and_face_for_catch(delta)
			return
		super._physics_process(delta)
		return
	vertical_fallback_active = false

	var move_dir := _policy_move_dir()
	# 若正沿策略方向移动却几乎没有位移，说明被卡住了：交给基类的硬性脱困逻辑处理。
	var frame_move := Vector2(global_position.x - last_position.x, global_position.z - last_position.z).length()
	if not wants_catch_attempt and move_dir.length_squared() > 0.01 and frame_move < 0.02 and is_on_floor():
		rl_stuck_timer += delta
	else:
		rl_stuck_timer = maxf(rl_stuck_timer - delta * 1.5, 0.0)
	if wants_catch_attempt and not is_catch_disabled_by_slow():
		move_dir = _direction_to_target()
	elif rl_stuck_timer > 0.7:
		rl_stuck_timer = 0.0
		super._physics_process(delta)
		return
	elif move_dir.length_squared() < 0.01:
		super._physics_process(delta)
		return

	if not wants_catch_attempt and _front_blocked(move_dir):
		_request_jump(jump_velocity)

	_apply_gravity(delta)
	if velocity.y > MAX_UPWARD_VELOCITY:
		velocity.y = MAX_UPWARD_VELOCITY
	var target_speed: float = 0.0 if wants_catch_attempt else chase_speed * move_speed_multiplier
	velocity.x = move_toward(velocity.x, move_dir.x * target_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, move_dir.z * target_speed, acceleration * delta)

	if move_dir.length_squared() > 0.01:
		look_at(global_position + move_dir, Vector3.UP)
	_move_with_step_climbing(delta)
	last_position = global_position

func _should_use_vertical_fallback(vertical_gap: float) -> bool:
	if absf(vertical_gap) < VERTICAL_FALLBACK_GAP:
		return false
	return true

func _is_close_enough_for_catch() -> bool:
	if target == null:
		return false
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > CATCH_ATTEMPT_DISTANCE or to_target.length_squared() < 0.01:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return false
	return forward.normalized().dot(to_target.normalized()) >= -0.05

func _hold_and_face_for_catch(delta: float) -> void:
	var move_dir := _direction_to_target()
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	_apply_gravity(delta)
	if velocity.y > MAX_UPWARD_VELOCITY:
		velocity.y = MAX_UPWARD_VELOCITY
	if move_dir.length_squared() > 0.01:
		look_at(global_position + move_dir, Vector3.UP)
	move_and_slide()
	last_position = global_position

func _load_policy() -> void:
	if not FileAccess.file_exists(POLICY_PATH):
		return
	var file := FileAccess.open(POLICY_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var metadata: Dictionary = data.get("metadata", {})
	var bounds: Dictionary = metadata.get("bounds", {})
	rl_version = int(metadata.get("version", 1))
	rl_move_action_count = int(metadata.get("move_action_count", 9))
	rl_cell_size = float(metadata.get("cell_size", rl_cell_size))
	rl_max_relative_cells = int(metadata.get("max_relative_cells", rl_max_relative_cells))
	rl_catch_action_index = int(metadata.get("catch_action_index", rl_catch_action_index))
	rl_round_seconds = float(metadata.get("round_seconds", rl_round_seconds))
	rl_min_x = float(bounds.get("min_x", rl_min_x))
	rl_min_z = float(bounds.get("min_z", rl_min_z))
	rl_width = int(bounds.get("width", rl_width))
	rl_height = int(bounds.get("height", rl_height))
	rl_policy = data.get("policy", {})

func _policy_move_dir() -> Vector3:
	wants_catch_attempt = false
	if rl_version < 2:
		return _legacy_policy_move_dir()
	var directions := _relative_directions()
	var gap_cells := global_position.distance_to(target.global_position) / maxf(rl_cell_size, 0.1)
	var dist_bucket := _distance_bucket(gap_cells)
	var line_clear := int(_policy_line_clear())
	var skill_ready := int(rl_catch_ready and not is_catch_disabled_by_slow())
	var affected := int(is_catch_disabled_by_slow())
	var progress_bucket := mini(3, int(float(rl_hit_progress) / maxf(float(rl_hits_to_win), 1.0) * 4.0))
	var elapsed_ratio := 1.0 - clampf(rl_time_remaining / maxf(rl_round_seconds, 1.0), 0.0, 1.0)
	var time_bucket := mini(3, int(elapsed_ratio * 4.0))
	var key := "%d,%d,%d,%d,%d,%d,%d" % [dist_bucket, _blocked_mask(directions), line_clear, skill_ready, affected, progress_bucket, time_bucket]
	if not rl_policy.has(key):
		return Vector3.ZERO
	var action_index := int(rl_policy[key])
	var move_index := posmod(action_index, rl_move_action_count)
	wants_catch_attempt = action_index >= rl_move_action_count and skill_ready == 1
	if move_index < 0 or move_index >= directions.size():
		return Vector3.ZERO
	return directions[move_index]

func _legacy_policy_move_dir() -> Vector3:
	var offset := target.global_position - global_position
	var dx := clampi(int(round(offset.x / rl_cell_size)), -rl_max_relative_cells, rl_max_relative_cells)
	var dz := clampi(int(round(offset.z / rl_cell_size)), -rl_max_relative_cells, rl_max_relative_cells)
	var key := "%d,%d,%d" % [dx, dz, _legacy_blocked_mask()]
	if not rl_policy.has(key):
		return Vector3.ZERO
	var action_index := int(rl_policy[key])
	if action_index == rl_catch_action_index:
		wants_catch_attempt = rl_catch_ready and not is_catch_disabled_by_slow()
		return _direction_to_target()
	if action_index < 0 or action_index >= ACTION_STEPS.size():
		return Vector3.ZERO
	var step: Vector2i = ACTION_STEPS[action_index]
	return Vector3(float(step.x), 0.0, float(step.y)).normalized()

func _relative_directions() -> Array[Vector3]:
	var toward := _direction_to_target()
	var left := Vector3(-toward.z, 0.0, toward.x)
	return [toward, -toward, left, -left, (toward + left).normalized(), (toward - left).normalized(), (-toward + left).normalized(), (-toward - left).normalized(), Vector3.ZERO]

func _distance_bucket(gap_cells: float) -> int:
	var limits := [1.3, 2.5, 4.0, 6.0, 9.0, 13.0]
	for i in range(limits.size()):
		if gap_cells <= float(limits[i]):
			return i
	return 6

func _blocked_mask(directions: Array[Vector3]) -> int:
	var mask := 0
	var from := global_position + Vector3.UP * 0.65
	var space := get_world_3d().direct_space_state
	for i in range(mini(8, directions.size())):
		var query := PhysicsRayQueryParameters3D.create(from, from + directions[i] * rl_cell_size * 0.85)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			mask |= 1 << i
	return mask

func _legacy_blocked_mask() -> int:
	var mask := 0
	var from := global_position + Vector3.UP * 0.65
	var space := get_world_3d().direct_space_state
	for i in range(mini(rl_catch_action_index, ACTION_STEPS.size())):
		var step: Vector2i = ACTION_STEPS[i]
		var dir := Vector3(float(step.x), 0.0, float(step.y)).normalized()
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * rl_cell_size * 0.85)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			mask |= 1 << i
	return mask

func _policy_line_clear() -> bool:
	if target == null or get_world_3d() == null:
		return false
	var from := global_position + Vector3.UP * 0.8
	var to := target.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid(), target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func set_rl_match_context(catch_ready: bool, hit_progress: int, hit_target: int, time_remaining: float, round_seconds: float) -> void:
	rl_catch_ready = catch_ready
	rl_hit_progress = hit_progress
	rl_hits_to_win = maxi(1, hit_target)
	rl_time_remaining = maxf(time_remaining, 0.0)
	rl_round_seconds = maxf(round_seconds, 1.0)

func _world_to_policy_cell(pos: Vector3) -> Vector2i:
	var gx := clampi(int(floor((pos.x - rl_min_x) / rl_cell_size)), 0, rl_width - 1)
	var gz := clampi(int(floor((pos.z - rl_min_z) / rl_cell_size)), 0, rl_height - 1)
	return Vector2i(gx, gz)

func _direction_to_target() -> Vector3:
	if target == null:
		return -global_transform.basis.z.normalized()
	var dir: Vector3 = target.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return -global_transform.basis.z.normalized()
	return dir.normalized()

func should_consume_ai_catch_attempt() -> bool:
	var requested := wants_catch_attempt and not is_catch_disabled_by_slow()
	wants_catch_attempt = false
	return requested

func get_catch_origin() -> Vector3:
	return global_position + Vector3.UP * 1.0

func get_catch_direction() -> Vector3:
	if target != null:
		var target_point: Vector3 = target.global_position + Vector3.UP * 0.85
		var dir: Vector3 = target_point - get_catch_origin()
		if dir.length_squared() > 0.001:
			return dir.normalized()
	return -global_transform.basis.z.normalized()
