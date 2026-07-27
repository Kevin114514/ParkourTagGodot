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
var wants_catch_attempt := false
var vertical_fallback_active := false

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
	if _is_close_enough_for_catch():
		wants_catch_attempt = true
		move_dir = _direction_to_target()
	elif wants_catch_attempt:
		move_dir = _direction_to_target()
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
	move_and_slide()
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
	rl_cell_size = float(metadata.get("cell_size", rl_cell_size))
	rl_max_relative_cells = int(metadata.get("max_relative_cells", rl_max_relative_cells))
	rl_catch_action_index = int(metadata.get("catch_action_index", rl_catch_action_index))
	rl_min_x = float(bounds.get("min_x", rl_min_x))
	rl_min_z = float(bounds.get("min_z", rl_min_z))
	rl_width = int(bounds.get("width", rl_width))
	rl_height = int(bounds.get("height", rl_height))
	rl_policy = data.get("policy", {})

func _policy_move_dir() -> Vector3:
	wants_catch_attempt = false
	var agent_cell := _world_to_policy_cell(global_position)
	var target_cell := _world_to_policy_cell(target.global_position)
	var dx := clampi(target_cell.x - agent_cell.x, -rl_max_relative_cells, rl_max_relative_cells)
	var dz := clampi(target_cell.y - agent_cell.y, -rl_max_relative_cells, rl_max_relative_cells)
	var key := "%d,%d,%d" % [dx, dz, _blocked_mask()]
	if not rl_policy.has(key):
		return Vector3.ZERO
	var action_index := int(rl_policy[key])
	if action_index == rl_catch_action_index:
		wants_catch_attempt = true
		return _direction_to_target()
	if action_index < 0 or action_index >= ACTION_STEPS.size():
		return Vector3.ZERO
	var step: Vector2i = ACTION_STEPS[action_index]
	return Vector3(float(step.x), 0.0, float(step.y)).normalized()

func _blocked_mask() -> int:
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
	var requested := wants_catch_attempt
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
