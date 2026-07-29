extends CharacterBody3D

const SkinAPI = preload("res://scripts/skin_api.gd")

var target: Node3D
var chase_speed := 7.8
var acceleration := 22.0
var jump_velocity := 7.4
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var is_active := true
const MAX_UPWARD_VELOCITY := 7.4
const JUMP_COOLDOWN := 0.42

var avoid_sign := 1.0
var avoid_timer := 0.0
var stuck_timer := 0.0
var hard_stuck_timer := 0.0
var escape_dir := Vector3.ZERO
var escape_timer := 0.0
var last_position := Vector3.ZERO
var jump_cooldown := 0.0
var descent_dir := Vector3.ZERO
var descent_repath_timer := 0.0
var wall_follow_dir := Vector3.ZERO
var wall_follow_timer := 0.0
var repath_timer := 0.0
var skin_id := "default"
var spawn_position := Vector3.ZERO
var move_speed_multiplier := 1.0
var move_speed_effect_time := 0.0
const VOID_Y := -12.0
const STEP_MAX_HEIGHT := 0.55
const STEP_FORWARD_DISTANCE := 0.45
var _step_inward_dir := Vector3.ZERO  # 上一次台阶检测的内侧方向（法线反向）
# 跨缺口跳跃锁定：起跳后在空中锁定水平方向与速度，防止滞空中被重新规划/减速导致跳半路坠落。
var gap_jump_dir := Vector3.ZERO
var gap_jump_timer := 0.0
const GAP_JUMP_LOCK_TIME := 1.2
const GAP_JUMP_SPEED := 9.2

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	spawn_position = global_position
	floor_snap_length = 0.45
	avoid_sign = 1.0 if randf() > 0.5 else -1.0
	last_position = global_position
	_build_body()

func _physics_process(delta: float) -> void:
	_update_speed_effect(delta)
	if global_position.y < VOID_Y:
		_respawn()

	jump_cooldown = maxf(jump_cooldown - delta, 0.0)
	if velocity.y > MAX_UPWARD_VELOCITY:
		velocity.y = MAX_UPWARD_VELOCITY

	# 跨缺口跳跃锁定：起跳后在空中沿固定方向全速前冲，直到落地或超时。
	# 这样跳跃轨迹不会被后续重规划/减速打断，避免"跳一半掉进缺口自刎"。
	gap_jump_timer = maxf(gap_jump_timer - delta, 0.0)
	if gap_jump_timer > 0.0 and gap_jump_dir.length_squared() > 0.01:
		if is_on_floor() and velocity.y <= 0.05:
			gap_jump_timer = 0.0
		else:
			velocity.x = gap_jump_dir.x * GAP_JUMP_SPEED
			velocity.z = gap_jump_dir.z * GAP_JUMP_SPEED
			_apply_gravity(delta)
			if velocity.y > MAX_UPWARD_VELOCITY:
				velocity.y = MAX_UPWARD_VELOCITY
			look_at(global_position + gap_jump_dir, Vector3.UP)
			move_and_slide()
			last_position = global_position
			return

	if not is_active or target == null:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		last_position = global_position
		return

	avoid_timer -= delta
	if avoid_timer <= 0.0:
		avoid_timer = randf_range(0.6, 1.1)
	wall_follow_timer = maxf(wall_follow_timer - delta, 0.0)
	repath_timer = maxf(repath_timer - delta, 0.0)

	var target_pos: Vector3 = target.global_position
	var to_target: Vector3 = target_pos - global_position
	var vertical_gap: float = to_target.y
	to_target.y = 0.0
	var flat_distance: float = to_target.length()
	var elevated_target: bool = vertical_gap > 0.85
	var target_below: bool = vertical_gap < -0.85
	var move_dir := Vector3.ZERO
	if flat_distance > 0.05:
		move_dir = to_target.normalized()
	elif elevated_target:
		move_dir = -global_transform.basis.z.normalized()

	var frame_move: float = Vector2(global_position.x - last_position.x, global_position.z - last_position.z).length()
	if move_dir.length_squared() > 0.01 and frame_move < 0.015 and is_on_floor():
		stuck_timer += delta
	else:
		stuck_timer = maxf(stuck_timer - delta * 2.0, 0.0)

	# 硬性脱困：长时间几乎无位移（被卡在墙角/夹缝）时，强制朝最空旷方向冲刺 + 跳跃，
	# 保证 AI 绝不会永久卡在墙里。
	if move_dir.length_squared() > 0.01 and frame_move < 0.02:
		hard_stuck_timer += delta
	else:
		hard_stuck_timer = maxf(hard_stuck_timer - delta * 1.5, 0.0)

	escape_timer = maxf(escape_timer - delta, 0.0)
	if hard_stuck_timer > 1.0 and escape_timer <= 0.0:
		escape_dir = _best_escape_dir(move_dir)
		escape_timer = 0.75
		hard_stuck_timer = 0.0
		_request_jump(jump_velocity)

	if escape_timer > 0.0 and escape_dir.length_squared() > 0.01:
		var burst_speed: float = chase_speed * move_speed_multiplier * 1.15
		_apply_gravity(delta)
		if velocity.y > MAX_UPWARD_VELOCITY:
			velocity.y = MAX_UPWARD_VELOCITY
		velocity.x = move_toward(velocity.x, escape_dir.x * burst_speed, acceleration * 1.6 * delta)
		velocity.z = move_toward(velocity.z, escape_dir.z * burst_speed, acceleration * 1.6 * delta)
		look_at(global_position + escape_dir, Vector3.UP)
		move_and_slide()
		last_position = global_position
		return

	if move_dir.length_squared() > 0.01 and (repath_timer <= 0.0 or stuck_timer > 0.22):
		var planned_dir := _plan_local_navigation_dir(move_dir, target_pos)
		if planned_dir.length_squared() > 0.01:
			move_dir = planned_dir
		repath_timer = 0.12 if stuck_timer > 0.22 else 0.22

	var blocked := _front_blocked(move_dir)
	var target_line_blocked := target_below and _line_to_target_blocked()
	if target_below:
		if target_line_blocked or blocked or stuck_timer > 0.18 or flat_distance < 3.0:
			move_dir = _get_stable_descent_dir(move_dir, delta)
			if is_on_floor():
				velocity.y = minf(velocity.y, 0.0)
			stuck_timer = 0.0
		else:
			descent_repath_timer = 0.0
	elif elevated_target:
		if flat_distance < 0.75 and vertical_gap > 1.2:
			move_dir = _escape_from_under_dir()
		elif blocked or stuck_timer > 0.28 or flat_distance < 2.2:
			if _try_climb_ledge(move_dir, vertical_gap):
				stuck_timer = 0.0
			elif _request_jump(jump_velocity):
				stuck_timer = 0.0
		else:
			stuck_timer = 0.0
	elif blocked or stuck_timer > 0.45:
		_request_jump(jump_velocity)
		var side := Vector3(-move_dir.z, 0.0, move_dir.x) * avoid_sign
		if side.length_squared() < 0.01:
			side = Vector3(avoid_sign, 0.0, 0.0)
		move_dir = (move_dir + side * 0.55).normalized()
		wall_follow_dir = move_dir
		wall_follow_timer = 0.55
		avoid_sign = -avoid_sign
		stuck_timer = 0.0

	if wall_follow_timer > 0.0 and wall_follow_dir.length_squared() > 0.01 and not _front_blocked(wall_follow_dir):
		move_dir = (move_dir * 0.68 + wall_follow_dir.normalized() * 0.32).normalized()

	# 跨越断桥间隙：前方近处出现缺口时的处理
	if not target_below and not elevated_target and _gap_edge_ahead(move_dir):
		if _has_landing_across_gap(move_dir) and is_on_floor() and jump_cooldown <= 0.0:
			# 对面有落脚平台 -> 助跑起跳并锁定跳跃方向/速度，确保稳稳落到对岸
			if _request_jump(jump_velocity):
				gap_jump_dir = move_dir.normalized()
				gap_jump_timer = GAP_JUMP_LOCK_TIME
				velocity.x = gap_jump_dir.x * GAP_JUMP_SPEED
				velocity.z = gap_jump_dir.z * GAP_JUMP_SPEED
				look_at(global_position + gap_jump_dir, Vector3.UP)
				move_and_slide()
				last_position = global_position
				return
		else:
			# 前方是缺口但对面无处落脚 -> 立即刹车并侧向绕行，绝不走进虚空坠落
			var brake_side := Vector3(-move_dir.z, 0.0, move_dir.x) * avoid_sign
			if brake_side.length_squared() < 0.01:
				brake_side = Vector3(avoid_sign, 0.0, 0.0)
			var safe_dir := brake_side.normalized()
			if _has_ground_ahead(safe_dir, 1.2) and not _front_blocked(safe_dir):
				move_dir = safe_dir
			else:
				move_dir = Vector3.ZERO
				velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.5 * delta)
				velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.5 * delta)
			avoid_sign = -avoid_sign

	_apply_gravity(delta)
	if velocity.y > MAX_UPWARD_VELOCITY:
		velocity.y = MAX_UPWARD_VELOCITY
	var current_chase_speed := chase_speed * move_speed_multiplier
	velocity.x = move_toward(velocity.x, move_dir.x * current_chase_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, move_dir.z * current_chase_speed, acceleration * delta)

	if move_dir.length_squared() > 0.01:
		look_at(global_position + move_dir, Vector3.UP)
	_move_with_step_climbing(delta)
	last_position = global_position

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	stuck_timer = 0.0
	hard_stuck_timer = 0.0
	escape_dir = Vector3.ZERO
	escape_timer = 0.0
	jump_cooldown = 0.0
	gap_jump_dir = Vector3.ZERO
	gap_jump_timer = 0.0
	descent_dir = Vector3.ZERO
	descent_repath_timer = 0.0
	wall_follow_dir = Vector3.ZERO
	wall_follow_timer = 0.0
	repath_timer = 0.0
	move_speed_multiplier = 1.0
	move_speed_effect_time = 0.0
	last_position = global_position

func _update_speed_effect(delta: float) -> void:
	if move_speed_effect_time > 0.0:
		move_speed_effect_time = maxf(move_speed_effect_time - delta, 0.0)
		if move_speed_effect_time <= 0.0:
			move_speed_multiplier = 1.0

func apply_speed_multiplier(multiplier: float, duration: float) -> void:
	move_speed_multiplier = clampf(multiplier, 0.25, 2.5)
	move_speed_effect_time = maxf(duration, 0.0)

func is_catch_disabled_by_slow() -> bool:
	return move_speed_effect_time > 0.0 and move_speed_multiplier < 1.0

func _line_to_target_blocked() -> bool:
	var from: Vector3 = global_position + Vector3.UP * 0.9
	var to: Vector3 = target.global_position + Vector3.UP * 0.75
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()

func _plan_local_navigation_dir(raw_dir: Vector3, target_pos: Vector3) -> Vector3:
	if raw_dir.length_squared() < 0.01:
		return raw_dir

	var desired: Vector3 = raw_dir.normalized()
	var side: Vector3 = Vector3(-desired.z, 0.0, desired.x).normalized()
	if side.length_squared() < 0.01:
		side = global_transform.basis.x.normalized()

	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		to_target = desired
	else:
		to_target = to_target.normalized()

	var candidates: Array[Vector3] = [
		desired,
		(desired + side * 0.45).normalized(),
		(desired - side * 0.45).normalized(),
		side,
		-side
	]

	if wall_follow_timer > 0.0 and wall_follow_dir.length_squared() > 0.01:
		candidates.append(wall_follow_dir.normalized())

	var best_dir: Vector3 = desired
	var best_score := -100000.0
	for candidate in candidates:
		if candidate.length_squared() < 0.01:
			continue
		var clearance := _sample_forward_clearance(candidate)
		var align_to_target: float = candidate.dot(to_target)
		var align_to_current: float = candidate.dot(desired)
		var score: float = clearance * 1.75 + align_to_target * 1.2 + align_to_current * 0.6
		if _front_blocked(candidate):
			score -= 2.2
		if score > best_score:
			best_score = score
			best_dir = candidate

	if best_dir.dot(desired) < 0.18 and _front_blocked(desired):
		wall_follow_dir = best_dir
		wall_follow_timer = 0.62
	elif _front_blocked(best_dir):
		var fallback := side if _sample_forward_clearance(side) > _sample_forward_clearance(-side) else -side
		if not _front_blocked(fallback):
			best_dir = fallback
			wall_follow_dir = fallback
			wall_follow_timer = 0.55

	return best_dir.normalized()

func _best_escape_dir(current: Vector3) -> Vector3:
	var dirs: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 1.0).normalized(),
		Vector3(1.0, 0.0, -1.0).normalized(),
		Vector3(-1.0, 0.0, 1.0).normalized(),
		Vector3(-1.0, 0.0, -1.0).normalized(),
	]
	var best: Vector3 = (-current).normalized() if current.length_squared() > 0.01 else Vector3(1.0, 0.0, 0.0)
	var best_score := -1.0
	var toward := Vector3.ZERO
	if target != null and is_instance_valid(target):
		toward = target.global_position - global_position
		toward.y = 0.0
		if toward.length_squared() > 0.01:
			toward = toward.normalized()
		else:
			toward = Vector3.ZERO
	for d in dirs:
		var clearance := _sample_forward_clearance(d)
		var score: float = clearance + d.dot(toward) * 0.4
		if score > best_score:
			best_score = score
			best = d
	return best.normalized()

func _sample_forward_clearance(dir: Vector3) -> float:
	if dir.length_squared() < 0.01:
		return 0.0
	var probes := PackedFloat32Array([0.9, 1.4, 2.0])
	var score := 0.0
	var normalized_dir := dir.normalized()
	var from := global_position + Vector3.UP * 0.65
	var space := get_world_3d().direct_space_state
	for d in probes:
		var to := from + normalized_dir * d
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			score += d
		else:
			break
	return score

func _get_stable_descent_dir(preferred_dir: Vector3, delta: float) -> Vector3:
	descent_repath_timer -= delta
	var downhill: Vector3 = _get_downhill_dir()
	if downhill.length_squared() > 0.01:
		if descent_dir.length_squared() < 0.01 or descent_repath_timer <= 0.0 or descent_dir.dot(downhill) < 0.35:
			var target_pull: Vector3 = preferred_dir.normalized() if preferred_dir.length_squared() > 0.01 else Vector3.ZERO
			descent_dir = (downhill * 1.45 + target_pull * 0.35).normalized()
			descent_repath_timer = 0.8
		return descent_dir

	if descent_dir.length_squared() < 0.01 or descent_repath_timer <= 0.0:
		descent_dir = _find_descent_dir(preferred_dir)
		descent_repath_timer = 0.9
	return descent_dir

func _get_downhill_dir() -> Vector3:
	if not is_on_floor():
		return Vector3.ZERO
	var floor_normal: Vector3 = get_floor_normal()
	if floor_normal.y > 0.98 or floor_normal.y < 0.25:
		return Vector3.ZERO
	var downhill: Vector3 = Vector3.DOWN.slide(floor_normal)
	downhill.y = 0.0
	return downhill.normalized() if downhill.length_squared() > 0.01 else Vector3.ZERO

func _find_descent_dir(preferred_dir: Vector3) -> Vector3:
	var base_dir: Vector3 = preferred_dir
	if base_dir.length_squared() < 0.01:
		base_dir = _escape_from_under_dir()
	base_dir = base_dir.normalized()

	var left: Vector3 = Vector3(-base_dir.z, 0.0, base_dir.x).normalized()
	var candidates: Array[Vector3] = [
		base_dir,
		(base_dir + left * 0.8).normalized(),
		(base_dir - left * 0.8).normalized(),
		left,
		-left,
		-base_dir
	]

	var space := get_world_3d().direct_space_state
	var best_dir: Vector3 = base_dir
	var best_score := -100000.0
	for candidate in candidates:
		for probe_distance in PackedFloat32Array([1.2, 2.0, 3.0, 4.2]):
			var ray_xz: Vector3 = global_position + candidate * probe_distance
			var from: Vector3 = ray_xz + Vector3.UP * 0.8
			var to: Vector3 = ray_xz + Vector3.DOWN * 5.5
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collision_mask = 1
			query.exclude = [get_rid()]
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue

			var hit_position: Vector3 = hit["position"]
			var hit_normal: Vector3 = hit["normal"]
			var drop: float = global_position.y - hit_position.y
			if hit_normal.y < 0.45 or drop < 0.18:
				continue

			var target_flat: Vector3 = target.global_position
			target_flat.y = hit_position.y
			var target_gain: float = global_position.distance_to(target.global_position) - hit_position.distance_to(target_flat)
			var score: float = drop * 2.2 + target_gain * 0.8 - probe_distance * 0.12
			if score > best_score:
				best_score = score
				best_dir = candidate

	return best_dir.normalized()

func _escape_from_under_dir() -> Vector3:
	var away: Vector3 = global_position - target.global_position
	away.y = 0.0
	if away.length_squared() < 0.05:
		away = global_transform.basis.z
	return away.normalized()

func _request_jump(strength: float) -> bool:
	if not is_on_floor() or jump_cooldown > 0.0:
		return false
	velocity.y = clampf(maxf(velocity.y, strength), 0.0, MAX_UPWARD_VELOCITY)
	jump_cooldown = JUMP_COOLDOWN
	return true

func _try_climb_ledge(dir: Vector3, vertical_gap: float) -> bool:
	if dir.length_squared() < 0.01 or not is_on_floor() or jump_cooldown > 0.0:
		return false

	dir = dir.normalized()
	var space := get_world_3d().direct_space_state
	var highest_allowed: float = target.global_position.y + 0.45
	var probe_distances := PackedFloat32Array([0.65, 1.05, 1.45, 1.85, 2.25])
	for probe_distance in probe_distances:
		var ray_xz: Vector3 = global_position + dir * probe_distance
		var from: Vector3 = ray_xz + Vector3.UP * minf(maxf(vertical_gap + 1.4, 2.2), 4.4)
		var to: Vector3 = ray_xz + Vector3.UP * 0.15
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]
		var height_delta: float = hit_position.y - global_position.y
		if hit_normal.y < 0.72 or height_delta < 0.35 or height_delta > 1.85 or hit_position.y > highest_allowed:
			continue

		if not _request_jump(jump_velocity):
			return false
		velocity.x = dir.x * chase_speed * 1.03
		velocity.z = dir.z * chase_speed * 1.03
		return true

	return false

func _ray_blocked(dir: Vector3, distance: float, height: float = 0.65) -> bool:
	if dir.length_squared() < 0.01:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * height
	var to := from + dir.normalized() * distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()

func _move_with_step_climbing(delta: float) -> void:
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_vel.length_squared() < 0.01 or not is_on_floor():
		move_and_slide()
		return

	var move_dir_sc := horizontal_vel.normalized()
	# 用当前实际水平速度推进台阶，保留 move_toward 的结果
	var current_speed := horizontal_vel.length()
	var space := get_world_3d().direct_space_state

	# 子步进检测：将一帧拆成多次小步，更快捕捉台阶避免漂移
	var sub_steps := 3
	var sub_delta := delta / float(sub_steps)
	for i in sub_steps:
		var foot_origin := _get_step_foot_position()
		var step_result := _detect_step_ahead(space, foot_origin, move_dir_sc)
		if step_result != Vector3.ZERO:
			global_position.y += step_result.y - foot_origin.y + 0.01
			global_position.x += move_dir_sc.x * current_speed * sub_delta
			global_position.z += move_dir_sc.z * current_speed * sub_delta
			# 沿楼梯正交方向（内侧）补偿，防止漂移到楼梯侧面掉下去
			if _step_inward_dir.length_squared() > 0.01:
				global_position.x += _step_inward_dir.x * 0.04
				global_position.z += _step_inward_dir.z * 0.04
		else:
			# 本子步没有台阶，正常移动（不覆盖 velocity）
			move_and_slide()
			return

	# 所有子步都在爬台阶：保留水平速度供下一帧衔接，仅清零 Y
	velocity.y = 0.0

func _get_step_foot_position() -> Vector3:
	var collision := get_node_or_null("Collision") as CollisionShape3D
	if collision == null or collision.shape == null:
		return global_position
	var half_height := 0.0
	if collision.shape is CapsuleShape3D:
		half_height = (collision.shape as CapsuleShape3D).height * 0.5
	elif collision.shape is BoxShape3D:
		half_height = (collision.shape as BoxShape3D).size.y * 0.5
	elif collision.shape is CylinderShape3D:
		half_height = (collision.shape as CylinderShape3D).height * 0.5
	else:
		return global_position
	var foot_position := collision.global_position
	foot_position.y -= half_height * collision.global_transform.basis.y.length()
	return foot_position

func _detect_step_ahead(space: PhysicsDirectSpaceState3D, origin: Vector3, move_dir: Vector3) -> Vector3:
	# 横向平行射线 + 扇形角度射线，覆盖角色整个身宽，
	# 解决斜向接近台阶时角色侧边先撞棱角、中心射线没命中导致被卡住的问题
	var angles := [0.0, 22.0, -22.0, 45.0, -45.0]
	var side := move_dir.cross(Vector3.UP).normalized()
	var lateral_offsets := [0.0, 0.32, -0.32]
	var rid := get_rid()
	var mask := collision_mask
	var best_result := Vector3.ZERO
	var best_height := -1.0

	for lo in lateral_offsets:
		var ray_origin: Vector3 = origin + side * lo
		for angle in angles:
			var dir := move_dir.rotated(Vector3.UP, deg_to_rad(angle))
			var result := _try_step_ray(space, ray_origin, dir, rid, mask)
			if result != Vector3.ZERO:
				var h := result.y - origin.y
				if h > best_height:
					best_height = h
					best_result = result

	return best_result

func _try_step_ray(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, rid: RID, mask: int) -> Vector3:
	var foot_height := 0.05
	var low_ray_origin := origin + Vector3.UP * foot_height
	var low_ray_end := low_ray_origin + dir * STEP_FORWARD_DISTANCE

	var low_params := PhysicsRayQueryParameters3D.create(low_ray_origin, low_ray_end)
	low_params.collision_mask = mask
	low_params.exclude = [rid]
	var low_hit := space.intersect_ray(low_params)
	if low_hit.is_empty():
		return Vector3.ZERO

	# 高位射线检测是否为墙壁
	var high_ray_origin := origin + Vector3.UP * (STEP_MAX_HEIGHT + 0.05)
	var high_ray_end := high_ray_origin + dir * STEP_FORWARD_DISTANCE

	var high_params := PhysicsRayQueryParameters3D.create(high_ray_origin, high_ray_end)
	high_params.collision_mask = mask
	high_params.exclude = [rid]
	var high_hit := space.intersect_ray(high_params)
	if not high_hit.is_empty():
		return Vector3.ZERO

	# 使用碰撞法线方向来确定台阶内侧偏移方向
	var hit_point: Vector3 = low_hit["position"]
	var hit_normal: Vector3 = low_hit["normal"]
	var inward := -Vector3(hit_normal.x, 0.0, hit_normal.z).normalized()
	if inward.length_squared() < 0.01:
		inward = dir

	# 从碰撞点沿法线向内偏移后，从上方向下射线找台阶顶面
	var offset := inward * 0.08
	var down_origin := Vector3(hit_point.x + offset.x, origin.y + STEP_MAX_HEIGHT + 0.05, hit_point.z + offset.z)
	var down_end := Vector3(hit_point.x + offset.x, origin.y - 0.05, hit_point.z + offset.z)

	var down_params := PhysicsRayQueryParameters3D.create(down_origin, down_end)
	down_params.collision_mask = mask
	down_params.exclude = [rid]
	var down_hit := space.intersect_ray(down_params)
	if down_hit.is_empty():
		return Vector3.ZERO

	var step_top: Vector3 = down_hit["position"]
	var step_normal: Vector3 = down_hit["normal"]

	if step_normal.angle_to(Vector3.UP) > floor_max_angle:
		return Vector3.ZERO

	var step_height := step_top.y - origin.y
	if step_height < 0.02 or step_height > STEP_MAX_HEIGHT:
		return Vector3.ZERO

	# 记录台阶内侧方向，供传送补偿使用
	_step_inward_dir = inward
	return step_top

func _has_ground_ahead(dir: Vector3, distance: float) -> bool:
	if dir.length_squared() < 0.01:
		return true
	var probe := global_position + dir.normalized() * distance
	var from := probe + Vector3.UP * 1.0
	var to := probe + Vector3.DOWN * 3.3
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit["position"]
	return global_position.y - hit_pos.y < 2.1

func _gap_edge_ahead(dir: Vector3) -> bool:
	# 检测前方近处（断桥边缘）是否出现无落脚点的缺口
	if dir.length_squared() < 0.01:
		return false
	var d := dir.normalized()
	for dist in PackedFloat32Array([0.7, 1.1, 1.6]):
		if not _has_ground_ahead(d, dist):
			return true
	return false

func _has_landing_across_gap(dir: Vector3) -> bool:
	# 间隙对面是否有一段跳跃即可到达的落脚平台（覆盖到约 7.4m，可识别 5.6m 真断桥）。
	# 要求：先经过一段真正的缺口（无地），缺口之后再出现可落脚平台，才算"对面有落脚"，
	# 避免把脚下自身平台误当成落脚点而在缺口边缘犹豫。
	if dir.length_squared() < 0.01:
		return false
	var d := dir.normalized()
	var space := get_world_3d().direct_space_state
	var seen_gap := false
	for dist in PackedFloat32Array([1.6, 2.2, 2.9, 3.6, 4.3, 5.0, 5.8, 6.6, 7.4]):
		var probe := global_position + d * dist
		var from := probe + Vector3.UP * 2.4
		var to := probe + Vector3.DOWN * 4.5
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			seen_gap = true
			continue
		var hit_y: float = hit["position"].y
		var reachable := hit_y - global_position.y <= 2.3 and global_position.y - hit_y <= 3.6
		if seen_gap and reachable:
			return true
	return false

func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.2
	elif not is_on_floor():
		velocity.y -= gravity * delta

func _front_blocked(dir: Vector3) -> bool:
	return _ray_blocked(dir, 1.25)

func get_catch_origin() -> Vector3:
	return global_position + Vector3.UP * 1.0

func get_catch_direction() -> Vector3:
	if target != null and is_instance_valid(target):
		var target_point: Vector3 = target.global_position + Vector3.UP * 0.85
		var to_target: Vector3 = target_point - get_catch_origin()
		if to_target.length_squared() > 0.001:
			return to_target.normalized()
	return -global_transform.basis.z.normalized()

func _build_body() -> void:
	var skin := SkinAPI.load_role_skin("tagger", skin_id)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(skin.get("radius", 0.38))
	capsule.height = float(skin.get("height", 1.82))
	if String(skin.get("collision_shape", "capsule")) == "box":
		var box := BoxShape3D.new()
		box.size = skin.get("collision_size", Vector3(0.7, 1.2, 0.5)) as Vector3
		collision.shape = box
	else:
		collision.shape = capsule
	collision.position.y = float(skin.get("collision_y", 0.96))
	add_child(collision)

	var custom_model := SkinAPI.create_skin_visual_model(skin_id, skin)
	if custom_model != null:
		custom_model.name = "TaggerCustomModel"
		add_child(custom_model)
	else:
		var model_node := SkinAPI.instantiate_skin_model(skin_id, String(skin.get("model_scene", "")))
		if model_node != null:
			model_node.name = "TaggerModel"
			model_node.position.y = float(skin.get("mesh_y", collision.position.y))
			var model_scale := maxf(0.01, float(skin.get("model_scale", 1.0)))
			model_node.scale = Vector3.ONE * model_scale
			add_child(model_node)
		else:
			var mesh := MeshInstance3D.new()
			mesh.name = "TaggerMesh"
			var capsule_mesh := CapsuleMesh.new()
			capsule_mesh.radius = capsule.radius
			capsule_mesh.height = capsule.height
			mesh.mesh = capsule_mesh
			mesh.position.y = float(skin.get("mesh_y", collision.position.y))
			mesh.material_override = _material(
				skin.get("body_color", Color(1.0, 0.24, 0.18)) as Color,
				float(skin.get("roughness", 0.68)),
				SkinAPI.load_skin_texture(skin_id, String(skin.get("body_texture", "")))
			)
			add_child(mesh)

	if not bool(skin.get("hide_marker", false)):
		var marker := MeshInstance3D.new()
		marker.name = "ForwardMarker"
		var marker_mesh := BoxMesh.new()
		marker_mesh.size = Vector3(0.5, 0.12, 0.1)
		marker.mesh = marker_mesh
		marker.position = Vector3(0.0, float(skin.get("marker_y", 1.42)), float(skin.get("marker_z", -0.37)))
		marker.material_override = _material(
			skin.get("marker_color", Color(1.0, 0.9, 0.15)) as Color,
			float(skin.get("marker_roughness", skin.get("roughness", 0.68))),
			SkinAPI.load_skin_texture(skin_id, String(skin.get("marker_texture", "")))
		)
		add_child(marker)

func _material(color: Color, roughness: float = 0.68, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = clampf(roughness, 0.0, 1.0)
	if texture != null:
		mat.albedo_texture = texture
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(1.4, 1.4, 1.4)
	return mat
