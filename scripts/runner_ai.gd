extends CharacterBody3D

const SkinAPI = preload("res://scripts/skin_api.gd")

var walk_speed := 7.25
var acceleration := 28.0
var air_acceleration := 10.0
var jump_velocity := 7.4
var vault_velocity := 6.2
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var is_control_locked := false
var is_active := true
var skin_id := "default"
var target: Node3D

var spawn_position := Vector3.ZERO
var coyote_timer := 0.0
var repath_timer := 0.0
var desired_dir := Vector3.ZERO
var last_position := Vector3.ZERO
var target_last_position := Vector3.ZERO
var stuck_timer := 0.0
var dodge_sign := 1.0
var survival_timer := 0.0
var _gap_jump := false
var throwable_targets: Array[Vector3] = []
var has_throwable := false
var hit_progress := 0
var hits_to_win := 10
var move_speed_multiplier := 1.0
var move_speed_effect_time := 0.0
const VOID_Y := -12.0
const CENTER_PULL_TIME := 4.0
const IDEAL_ESCAPE_DISTANCE := 12.0
const STEP_MAX_HEIGHT := 0.55
const STEP_FORWARD_DISTANCE := 0.45
var _step_inward_dir := Vector3.ZERO  # 上一次台阶检测的内侧方向（法线反向）

func _ready() -> void:
	spawn_position = global_position
	last_position = global_position
	if target != null and is_instance_valid(target):
		target_last_position = target.global_position
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	dodge_sign = 1.0 if randf() > 0.5 else -1.0
	_build_body()

func _physics_process(delta: float) -> void:
	# 躲藏者触碰虚空即死：不在此复活，交由 game.gd 的 _on_runner_fell() 判定本局结束
	if move_speed_effect_time > 0.0:
		move_speed_effect_time = maxf(move_speed_effect_time - delta, 0.0)
		if move_speed_effect_time <= 0.0:
			move_speed_multiplier = 1.0

	if is_control_locked or not is_active:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		last_position = global_position
		return

	survival_timer += delta
	var target_velocity := Vector3.ZERO
	if target != null and is_instance_valid(target):
		target_velocity = (target.global_position - target_last_position) / maxf(delta, 0.001)
		target_last_position = target.global_position
		repath_timer -= delta
		if repath_timer <= 0.0:
			repath_timer = randf_range(0.08, 0.16)
			desired_dir = _compute_escape_dir(target_velocity)
	else:
		desired_dir = -global_transform.basis.z

	var frame_move := Vector2(global_position.x - last_position.x, global_position.z - last_position.z).length()
	if desired_dir.length_squared() > 0.01 and frame_move < 0.012 and is_on_floor():
		stuck_timer += delta
	else:
		stuck_timer = maxf(stuck_timer - delta * 2.0, 0.0)

	if stuck_timer > 0.28:
		dodge_sign = -dodge_sign
		desired_dir = _unstuck_dir(desired_dir)
		repath_timer = 0.0
		if is_on_floor():
			velocity.y = maxf(velocity.y, jump_velocity * 0.85)
		stuck_timer = 0.0

	if is_on_floor():
		coyote_timer = 0.12
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if _should_jump():
		velocity.y = maxf(velocity.y, jump_velocity)
		# 跨越断桥间隙时给一个朝逃跑方向的水平助推，确保能稳稳越过缺口
		if _gap_jump and desired_dir.length_squared() > 0.01:
			var jdir := desired_dir.normalized()
			velocity.x = jdir.x * walk_speed
			velocity.z = jdir.z * walk_speed
		coyote_timer = 0.0

	_apply_gravity(delta)

	var accel := acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, desired_dir.x * walk_speed, accel * delta)
	velocity.z = move_toward(velocity.z, desired_dir.z * walk_speed, accel * delta)

	if desired_dir.length_squared() > 0.01:
		var face_dir := desired_dir.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(face_dir.x, face_dir.z), clampf(delta * 10.0, 0.0, 1.0))

	_move_with_step_climbing(delta)
	last_position = global_position

func set_throwable_context(new_targets: Array[Vector3], new_has_throwable: bool, new_hit_progress: int, new_hits_to_win: int) -> void:
	throwable_targets = new_targets
	has_throwable = new_has_throwable
	hit_progress = new_hit_progress
	hits_to_win = max(1, new_hits_to_win)

func apply_speed_multiplier(multiplier: float, duration: float) -> void:
	move_speed_multiplier = clampf(multiplier, 0.25, 2.5)
	move_speed_effect_time = maxf(duration, 0.0)

func _nearest_throwable_position():
	if throwable_targets.is_empty():
		return null
	var best_position := throwable_targets[0]
	var best_distance := global_position.distance_squared_to(best_position)
	for position in throwable_targets:
		var distance := global_position.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best_position = position
	return best_position

func _compute_escape_dir(target_velocity: Vector3) -> Vector3:
	var away := global_position - target.global_position
	away.y = 0.0
	var flat_distance := away.length()
	if away.length_squared() < 0.01:
		away = -global_transform.basis.z
	away = away.normalized()

	var center_dir := -Vector3(global_position.x, 0.0, global_position.z)
	if center_dir.length_squared() > 0.01:
		center_dir = center_dir.normalized()
	var edge_pressure := clampf((Vector2(global_position.x, global_position.z).length() - 18.0) / 10.0, 0.0, 1.0)
	var opening_pressure := clampf(1.0 - survival_timer / CENTER_PULL_TIME, 0.0, 1.0)
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	var target_move := target_velocity
	target_move.y = 0.0
	if target_move.length_squared() > 0.05:
		target_move = target_move.normalized()
	else:
		target_move = Vector3.ZERO

	var nearest_throwable: Variant = _nearest_throwable_position()
	var item_dir := Vector3.ZERO
	if not has_throwable and nearest_throwable != null:
		item_dir = (nearest_throwable as Vector3) - global_position
		item_dir.y = 0.0

	var candidates: Array[Vector3] = [
		away,
		away.rotated(Vector3.UP, deg_to_rad(28.0)),
		away.rotated(Vector3.UP, deg_to_rad(-28.0)),
		away.rotated(Vector3.UP, deg_to_rad(58.0)),
		away.rotated(Vector3.UP, deg_to_rad(-58.0)),
		side,
		-side,
		(away + side * dodge_sign * 0.9).normalized()
	]
	if center_dir.length_squared() > 0.01:
		candidates.append(center_dir)
		candidates.append((center_dir + side * 0.65).normalized())
		candidates.append((center_dir - side * 0.65).normalized())
		candidates.append((center_dir + away * 0.45).normalized())
	if target_move.length_squared() > 0.01:
		var cut_left := Vector3(-target_move.z, 0.0, target_move.x).normalized()
		candidates.append((-target_move + cut_left * 0.75).normalized())
		candidates.append((-target_move - cut_left * 0.75).normalized())
	if item_dir.length_squared() > 0.01:
		var item_forward := item_dir.normalized()
		var item_side := Vector3(-item_forward.z, 0.0, item_forward.x).normalized()
		candidates.append(item_forward)
		candidates.append((item_forward + away * 0.55).normalized())
		candidates.append((item_forward + item_side * 0.45).normalized())
		candidates.append((item_forward - item_side * 0.45).normalized())

	var best_dir := away
	var best_score := -100000.0
	for candidate in candidates:
		if candidate.length_squared() < 0.01:
			continue
		candidate = candidate.normalized()
		var score := _score_escape_candidate(candidate, away, target_velocity, center_dir, edge_pressure, opening_pressure, flat_distance)
		if score > best_score:
			best_score = score
			best_dir = candidate

	var safe_probe := _probe_dir(best_dir)
	if safe_probe.length_squared() > 0.01:
		return safe_probe.normalized()
	return _unstuck_dir(away)

func _score_escape_candidate(dir: Vector3, away: Vector3, target_velocity: Vector3, center_dir: Vector3, edge_pressure: float, opening_pressure: float, flat_distance: float) -> float:
	var current_target := target.global_position
	var current_distance := global_position.distance_to(current_target)
	var lookahead := clampf(current_distance / 8.0, 0.35, 0.95)
	var future_self := global_position + dir * walk_speed * lookahead
	var future_target := current_target + target_velocity * lookahead
	var future_radius := Vector2(future_self.x, future_self.z).length()
	var current_radius := Vector2(global_position.x, global_position.z).length()
	var score := (future_self.distance_to(future_target) - current_distance) * 2.2
	score += _sample_forward_clearance(dir) * 1.8
	score += dir.dot(away) * (2.0 if current_distance < 7.0 else 0.55)
	score += desired_dir.normalized().dot(dir) * 0.35 if desired_dir.length_squared() > 0.01 else 0.0

	if center_dir.length_squared() > 0.01:
		var center_dot := dir.dot(center_dir)
		score += center_dot * (3.8 * edge_pressure + 3.2 * opening_pressure)
		if future_radius < current_radius:
			score += (current_radius - future_radius) * (0.26 + 0.38 * edge_pressure + 0.22 * opening_pressure)
		if future_radius > current_radius + 1.0 and (edge_pressure > 0.15 or opening_pressure > 0.1):
			score -= (future_radius - current_radius) * 0.9

	var distance_error := absf(flat_distance - IDEAL_ESCAPE_DISTANCE)
	var future_distance := future_self.distance_to(future_target)
	var future_distance_error := absf(future_distance - IDEAL_ESCAPE_DISTANCE)
	if future_distance_error < distance_error:
		score += (distance_error - future_distance_error) * 0.65
	elif future_distance > IDEAL_ESCAPE_DISTANCE + 7.0:
		score -= minf(future_distance_error - distance_error, 8.0) * 0.4

	if _line_to_target_blocked_from(future_self + Vector3.UP * 0.75):
		score += 0.8
	if _front_blocked(dir):
		score -= 4.5
	if _wall_too_close(dir):
		score -= 3.0 + edge_pressure * 2.5
	if not _has_ground_ahead(dir, 1.1):
		# 间隙对面若有可落脚平台，视为可跳跃间隙，轻度惩罚而非直接回避
		if _has_landing_across_gap(dir):
			score -= 1.2
		else:
			score -= 9.0
	elif not _has_ground_ahead(dir, 2.2):
		score -= 2.6
	if current_distance < 4.0 and dir.dot(away) < 0.2:
		score -= 4.0

	var nearest_item: Variant = _nearest_throwable_position()
	if not has_throwable and nearest_item != null:
		var item_position := nearest_item as Vector3
		var to_item := item_position - global_position
		to_item.y = 0.0
		if to_item.length_squared() > 0.01:
			var item_distance := to_item.length()
			var future_item_distance := future_self.distance_to(item_position)
			var item_urgency := clampf(float(hits_to_win - hit_progress) / maxf(float(hits_to_win), 1.0), 0.25, 1.0)
			if current_distance > 4.8:
				score += dir.dot(to_item.normalized()) * (3.8 + 2.2 * item_urgency)
				score += clampf(item_distance - future_item_distance, -3.0, 4.0) * (1.1 + item_urgency)
			if future_item_distance < 2.4:
				score += 5.5
			if current_distance < 5.0 and dir.dot(away) < 0.35:
				score -= 5.0
	elif has_throwable:
		var ideal_throw_distance := 10.5
		var future_throw_error := absf(future_distance - ideal_throw_distance)
		score += maxf(0.0, 5.5 - future_throw_error) * 0.9
		if future_distance < 5.0:
			score -= (5.0 - future_distance) * 2.4
		if future_distance > 16.0:
			score -= (future_distance - 16.0) * 0.7
		if not _line_to_target_blocked_from(future_self + Vector3.UP * 1.05):
			score += 2.2
	return score

func _probe_dir(dir: Vector3) -> Vector3:
	if dir.length_squared() < 0.01:
		return Vector3.ZERO
	dir = dir.normalized()
	if _front_blocked(dir) or _wall_too_close(dir):
		return Vector3.ZERO
	if not _has_ground_ahead(dir, 0.9):
		# 若前方是可跳跃的断桥间隙（对面有落脚点），允许继续，交由起跳逻辑处理
		if not _has_landing_across_gap(dir):
			return Vector3.ZERO
	return dir

func _unstuck_dir(preferred_dir: Vector3) -> Vector3:
	var base := preferred_dir.normalized() if preferred_dir.length_squared() > 0.01 else -global_transform.basis.z.normalized()
	var left := Vector3(-base.z, 0.0, base.x).normalized()
	var candidates: Array[Vector3] = [left * dodge_sign, -left * dodge_sign, base.rotated(Vector3.UP, deg_to_rad(95.0)), base.rotated(Vector3.UP, deg_to_rad(-95.0)), -base]
	for candidate in candidates:
		if candidate.length_squared() > 0.01 and _probe_dir(candidate).length_squared() > 0.01:
			return candidate.normalized()
	return base

func _should_jump() -> bool:
	_gap_jump = false
	if target == null or not is_instance_valid(target):
		return false
	if not (is_on_floor() or coyote_timer > 0.0):
		return false

	var forward := desired_dir
	if forward.length_squared() < 0.01:
		forward = -global_transform.basis.z
	forward = forward.normalized()

	var to_target := target.global_position - global_position
	var flat_distance := Vector2(to_target.x, to_target.z).length()
	if flat_distance < 4.0 and _front_blocked(forward):
		return true

	# 跨越断桥间隙：前方近处出现缺口，且间隙对面有可达平台 -> 起跳
	if _gap_edge_ahead(forward) and _has_landing_across_gap(forward):
		_gap_jump = true
		return true

	var low_from := global_position + Vector3.UP * 0.72
	var low_to := low_from + forward * 1.05
	var low_query := PhysicsRayQueryParameters3D.create(low_from, low_to)
	low_query.collision_mask = 1
	low_query.exclude = [get_rid()]
	var low_hit := get_world_3d().direct_space_state.intersect_ray(low_query)
	if low_hit.is_empty():
		return false

	var high_from := global_position + Vector3.UP * 1.55
	var high_to := high_from + forward * 1.05
	var high_query := PhysicsRayQueryParameters3D.create(high_from, high_to)
	high_query.collision_mask = 1
	high_query.exclude = [get_rid()]
	var high_hit := get_world_3d().direct_space_state.intersect_ray(high_query)
	return high_hit.is_empty()

func _sample_forward_clearance(dir: Vector3) -> float:
	if dir.length_squared() < 0.01:
		return 0.0
	var score := 0.0
	var space := get_world_3d().direct_space_state
	for distance in PackedFloat32Array([0.9, 1.5, 2.3, 3.2]):
		var from := global_position + Vector3.UP * 0.75
		var to := from + dir.normalized() * distance
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if space.intersect_ray(query).is_empty() and _has_ground_ahead(dir, distance):
			score += distance
		else:
			break
	return score

func _front_blocked(dir: Vector3) -> bool:
	if dir.length_squared() < 0.01:
		return false
	var space := get_world_3d().direct_space_state
	var forward := dir.normalized()
	var low_from := global_position + Vector3.UP * 0.45
	var low_to := low_from + forward * 1.05
	var low_query := PhysicsRayQueryParameters3D.create(low_from, low_to)
	low_query.collision_mask = 1
	low_query.exclude = [get_rid()]
	var low_hit := space.intersect_ray(low_query)
	if low_hit.is_empty():
		return false
	var high_from := global_position + Vector3.UP * 1.55
	var high_to := high_from + forward * 1.25
	var high_query := PhysicsRayQueryParameters3D.create(high_from, high_to)
	high_query.collision_mask = 1
	high_query.exclude = [get_rid()]
	var high_hit := space.intersect_ray(high_query)
	if high_hit.is_empty() and _has_walkable_step_ahead(forward):
		return false
	return true

func _has_walkable_step_ahead(dir: Vector3) -> bool:
	if dir.length_squared() < 0.01 or get_world_3d() == null:
		return false
	var probe := global_position + dir.normalized() * 1.25
	var from := probe + Vector3.UP * 1.8
	var to := probe + Vector3.DOWN * 2.4
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit["position"]
	var step_delta := hit_pos.y - global_position.y
	return step_delta > -0.35 and step_delta < 1.15

func _wall_too_close(dir: Vector3) -> bool:
	if dir.length_squared() < 0.01:
		return false
	var from := global_position + Vector3.UP * 0.85
	var to := from + dir.normalized() * 2.4
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

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
	# 前方存在间隙时，检查间隙对面是否有一段跳跃即可到达的落脚平台
	# 探测距离覆盖到约 7.4m，才能识别较宽的真断桥（间隙约 5.6m + 助跑余量）
	if dir.length_squared() < 0.01:
		return false
	var d := dir.normalized()
	var space := get_world_3d().direct_space_state
	for dist in PackedFloat32Array([2.2, 2.9, 3.6, 4.3, 5.0, 5.8, 6.6, 7.4]):
		var probe := global_position + d * dist
		var from := probe + Vector3.UP * 2.4
		var to := probe + Vector3.DOWN * 4.5
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_y: float = hit["position"].y
		# 落点不能太高（跳得上）也不能太低（不至于摔死）
		if hit_y - global_position.y <= 2.3 and global_position.y - hit_y <= 3.6:
			return true
	return false

func _line_to_target_blocked_from(from: Vector3) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var to := target.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	coyote_timer = 0.0
	repath_timer = 0.0
	desired_dir = Vector3.ZERO
	stuck_timer = 0.0
	survival_timer = 0.0
	move_speed_multiplier = 1.0
	move_speed_effect_time = 0.0
	last_position = global_position

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

func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.2
	elif not is_on_floor():
		velocity.y -= gravity * delta

func _build_body() -> void:
	var skin := SkinAPI.load_role_skin("runner", skin_id)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(skin.get("radius", 0.35))
	capsule.height = float(skin.get("height", 1.72))
	collision.shape = capsule
	collision.position.y = float(skin.get("collision_y", 0.92))
	add_child(collision)

	var custom_model := SkinAPI.create_skin_visual_model(skin_id, skin)
	if custom_model != null:
		custom_model.name = "RunnerAICustomModel"
		add_child(custom_model)
	else:
		var model_node := SkinAPI.instantiate_skin_model(skin_id, String(skin.get("model_scene", "")))
		if model_node != null:
			model_node.name = "RunnerAIModel"
			model_node.position.y = float(skin.get("mesh_y", collision.position.y))
			var model_scale := maxf(0.01, float(skin.get("model_scale", 1.0)))
			model_node.scale = Vector3.ONE * model_scale
			add_child(model_node)
		else:
			var mesh := MeshInstance3D.new()
			mesh.name = "RunnerAIMesh"
			var capsule_mesh := CapsuleMesh.new()
			capsule_mesh.radius = capsule.radius
			capsule_mesh.height = capsule.height
			mesh.mesh = capsule_mesh
			mesh.position.y = float(skin.get("mesh_y", collision.position.y))
			mesh.material_override = _material(
				skin.get("body_color", Color(0.15, 0.5, 1.0)) as Color,
				float(skin.get("roughness", 0.74)),
				SkinAPI.load_skin_texture(skin_id, String(skin.get("body_texture", "")))
			)
			add_child(mesh)

	if not bool(skin.get("hide_marker", false)):
		var visor := MeshInstance3D.new()
		visor.name = "ForwardVisor"
		var visor_mesh := BoxMesh.new()
		visor_mesh.size = Vector3(0.44, 0.1, 0.08)
		visor.mesh = visor_mesh
		visor.position = Vector3(0.0, float(skin.get("marker_y", 1.34)), float(skin.get("marker_z", -0.34)))
		visor.material_override = _material(
			skin.get("marker_color", Color(0.95, 0.98, 1.0)) as Color,
			float(skin.get("marker_roughness", skin.get("roughness", 0.74))),
			SkinAPI.load_skin_texture(skin_id, String(skin.get("marker_texture", "")))
		)
		add_child(visor)

func _material(color: Color, roughness: float = 0.74, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = clampf(roughness, 0.0, 1.0)
	if texture != null:
		mat.albedo_texture = texture
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(1.4, 1.4, 1.4)
	return mat
