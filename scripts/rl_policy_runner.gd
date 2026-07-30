extends "res://scripts/runner_ai.gd"

const POLICY_PATH := "res://rl/trained_runner_policy.json"
const ACTION_STEPS = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(0, 0),
]

var rl_policy: Dictionary = {}
var rl_version := 1
var rl_cell_size := 2.0
var rl_max_relative_cells := 14
var rl_catch_action_index := 8
var rl_move_action_count := 9
var rl_time_remaining := 300.0
var rl_round_seconds := 300.0
var wants_throw_attempt := false

func _ready() -> void:
	super._ready()
	_load_policy()

func _compute_escape_dir(target_velocity: Vector3) -> Vector3:
	wants_throw_attempt = false
	# 未持有减速弹时保留成熟的拾取和安全导航逻辑。
	if not has_throwable and _nearest_throwable_position() != null:
		return super._compute_escape_dir(target_velocity)
	var policy_dir := _policy_escape_dir()
	if policy_dir.length_squared() < 0.01:
		return super._compute_escape_dir(target_velocity)
	var safe := _probe_dir(policy_dir)
	if safe.length_squared() > 0.01:
		return safe.normalized()
	return super._compute_escape_dir(target_velocity)

func _policy_escape_dir() -> Vector3:
	if rl_policy.is_empty() or target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if rl_version < 2:
		return _legacy_policy_escape_dir()
	var directions := _relative_directions()
	var gap_cells := global_position.distance_to(target.global_position) / maxf(rl_cell_size, 0.1)
	var dist_bucket := _distance_bucket(gap_cells)
	var skill_ready := int(has_throwable)
	var progress_bucket := mini(3, int(float(hit_progress) / maxf(float(hits_to_win), 1.0) * 4.0))
	var elapsed_ratio := 1.0 - clampf(rl_time_remaining / maxf(rl_round_seconds, 1.0), 0.0, 1.0)
	var time_bucket := mini(3, int(elapsed_ratio * 4.0))
	var key := "%d,%d,%d,%d,0,%d,%d" % [dist_bucket, _blocked_mask(directions), int(_policy_line_clear()), skill_ready, progress_bucket, time_bucket]
	if not rl_policy.has(key):
		return Vector3.ZERO
	var action_index := int(rl_policy[key])
	var move_index := posmod(action_index, rl_move_action_count)
	wants_throw_attempt = action_index >= rl_move_action_count and has_throwable
	if move_index < 0 or move_index >= directions.size():
		return Vector3.ZERO
	return directions[move_index]

func _legacy_policy_escape_dir() -> Vector3:
	var offset := target.global_position - global_position
	var dx := clampi(int(round(offset.x / rl_cell_size)), -rl_max_relative_cells, rl_max_relative_cells)
	var dz := clampi(int(round(offset.z / rl_cell_size)), -rl_max_relative_cells, rl_max_relative_cells)
	var key := "%d,%d,%d" % [dx, dz, _legacy_blocked_mask()]
	if not rl_policy.has(key):
		return Vector3.ZERO
	var action_index := int(rl_policy[key])
	if action_index == rl_catch_action_index or action_index < 0 or action_index >= ACTION_STEPS.size():
		return Vector3.ZERO
	var step: Vector2i = ACTION_STEPS[action_index]
	return Vector3(float(step.x), 0.0, float(step.y)).normalized()

func _relative_directions() -> Array[Vector3]:
	var toward := target.global_position - global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		toward = -global_transform.basis.z
	toward = toward.normalized()
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
		var direction := Vector3(float(step.x), 0.0, float(step.y)).normalized()
		var query := PhysicsRayQueryParameters3D.create(from, from + direction * rl_cell_size * 0.85)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			mask |= 1 << i
	return mask

func _policy_line_clear() -> bool:
	if target == null or get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, target.global_position + Vector3.UP * 0.8)
	query.collision_mask = 1
	query.exclude = [get_rid(), target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func set_rl_match_context(time_remaining: float, round_seconds: float) -> void:
	rl_time_remaining = maxf(time_remaining, 0.0)
	rl_round_seconds = maxf(round_seconds, 1.0)

func should_consume_ai_throw_attempt() -> bool:
	var requested := wants_throw_attempt and has_throwable
	wants_throw_attempt = false
	return requested

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
	rl_version = int(metadata.get("version", 1))
	rl_cell_size = float(metadata.get("cell_size", rl_cell_size))
	rl_max_relative_cells = int(metadata.get("max_relative_cells", rl_max_relative_cells))
	rl_catch_action_index = int(metadata.get("catch_action_index", rl_catch_action_index))
	rl_move_action_count = int(metadata.get("move_action_count", 9))
	rl_round_seconds = float(metadata.get("round_seconds", rl_round_seconds))
	rl_policy = data.get("policy", {})
