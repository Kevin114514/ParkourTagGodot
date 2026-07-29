extends "res://scripts/runner_ai.gd"

# Runner AI that follows a self-play trained escape policy. The policy was
# learned in rl/train_selfplay.py against the tagger policy, using the exact
# same relative-offset + 8-neighbour blocked-mask state convention as the
# tagger side. When the table has no entry for the current state (or advises
# the "hold" action) we fall back to the hand-authored escape steering so the
# runner never freezes.

const POLICY_PATH := "res://rl/trained_runner_policy.json"
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
var rl_max_relative_cells := 14
var rl_catch_action_index := 8
var rl_repath_timer := 0.0

func _ready() -> void:
	super._ready()
	_load_policy()

func _compute_escape_dir(target_velocity: Vector3) -> Vector3:
	# The self-play policy learns chase/throw spacing, while the original runner
	# planner already knows how to detour toward throwable pickups. For AI-vs-AI
	# demos, keep that pickup behaviour so the runner can actually score hits.
	if not has_throwable and _nearest_throwable_position() != null:
		return super._compute_escape_dir(target_velocity)

	# Prefer the learned policy; fall back to the scripted escape planner when
	# the state is unseen or the policy chose to hold position.
	var policy_dir := _policy_escape_dir()
	if policy_dir.length_squared() < 0.01:
		return super._compute_escape_dir(target_velocity)
	# Keep the scripted safety probes so RL never walks off a ledge or into a
	# wall it could not perceive from the coarse grid state.
	var safe := _probe_dir(policy_dir)
	if safe.length_squared() > 0.01:
		return safe.normalized()
	return super._compute_escape_dir(target_velocity)

func _policy_escape_dir() -> Vector3:
	if rl_policy.is_empty() or target == null or not is_instance_valid(target):
		return Vector3.ZERO
	# State is relative to the *tagger* (the threat), matching training where
	# the runner observed target = tagger.
	var offset := target.global_position - global_position
	var dx := clampi(int(round(offset.x / rl_cell_size)), -rl_max_relative_cells, rl_max_relative_cells)
	var dz := clampi(int(round(offset.z / rl_cell_size)), -rl_max_relative_cells, rl_max_relative_cells)
	var key := "%d,%d,%d" % [dx, dz, _blocked_mask()]
	if not rl_policy.has(key):
		return Vector3.ZERO
	var action_index := int(rl_policy[key])
	if action_index == rl_catch_action_index:
		return Vector3.ZERO
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
	rl_cell_size = float(metadata.get("cell_size", rl_cell_size))
	rl_max_relative_cells = int(metadata.get("max_relative_cells", rl_max_relative_cells))
	rl_catch_action_index = int(metadata.get("catch_action_index", rl_catch_action_index))
	rl_policy = data.get("policy", {})
