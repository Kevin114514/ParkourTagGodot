extends "res://scripts/runner_ai.gd"

# 躲藏者训练策略驱动层：
# 加载 rl/train_runner.py 产出的策略文件，用训练结果决定逃跑方向；
# 当策略未加载 / 查不到当前状态 / 训练方向前方危险（无落脚点）时，
# 回落到父类 runner_ai.gd 的手写逃跑逻辑作为兜底。

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
]

var rl_policy: Dictionary = {}
var rl_cell_size := 2.0
var rl_min_x := -27.0
var rl_min_z := -27.0
var rl_width := 28
var rl_height := 28
var rl_max_relative_cells := 14

func _ready() -> void:
	super._ready()
	_load_policy()

func _physics_process(delta: float) -> void:
	# 策略缺失 / 无目标 / 被锁定，直接交回手写逻辑
	if rl_policy.is_empty() or target == null or not is_instance_valid(target):
		super._physics_process(delta)
		return
	if is_control_locked or not is_active:
		super._physics_process(delta)
		return

	survival_timer += delta
	target_last_position = target.global_position

	var move_dir := _policy_escape_dir()
	# 查不到状态 -> 兜底
	if move_dir.length_squared() < 0.01:
		super._physics_process(delta)
		return
	# 训练是在无高度差的平面网格上进行的，这里加一层安全检查：
	# 若训练方向前方没有落脚点且无法跨越间隙，交给手写逻辑避免摔进虚空
	if not _has_ground_ahead(move_dir, 1.1) and not _has_landing_across_gap(move_dir):
		super._physics_process(delta)
		return

	desired_dir = move_dir

	if is_on_floor():
		coyote_timer = 0.12
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if _should_jump():
		velocity.y = maxf(velocity.y, jump_velocity)
		coyote_timer = 0.0

	_apply_gravity(delta)

	var accel := acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, move_dir.x * walk_speed, accel * delta)
	velocity.z = move_toward(velocity.z, move_dir.z * walk_speed, accel * delta)

	var face_dir := move_dir.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(face_dir.x, face_dir.z), clampf(delta * 10.0, 0.0, 1.0))

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
	rl_min_x = float(bounds.get("min_x", rl_min_x))
	rl_min_z = float(bounds.get("min_z", rl_min_z))
	rl_width = int(bounds.get("width", rl_width))
	rl_height = int(bounds.get("height", rl_height))
	rl_policy = data.get("policy", {})

func _policy_escape_dir() -> Vector3:
	var agent_cell := _world_to_policy_cell(global_position)
	var target_cell := _world_to_policy_cell(target.global_position)
	var dx := clampi(target_cell.x - agent_cell.x, -rl_max_relative_cells, rl_max_relative_cells)
	var dz := clampi(target_cell.y - agent_cell.y, -rl_max_relative_cells, rl_max_relative_cells)
	var key := "%d,%d,%d" % [dx, dz, _blocked_mask()]
	if not rl_policy.has(key):
		return Vector3.ZERO
	var action_index := int(rl_policy[key])
	if action_index < 0 or action_index >= ACTION_STEPS.size():
		return Vector3.ZERO
	var step: Vector2i = ACTION_STEPS[action_index]
	return Vector3(float(step.x), 0.0, float(step.y)).normalized()

func _blocked_mask() -> int:
	var mask := 0
	var from := global_position + Vector3.UP * 0.65
	var space := get_world_3d().direct_space_state
	for i in range(ACTION_STEPS.size()):
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
