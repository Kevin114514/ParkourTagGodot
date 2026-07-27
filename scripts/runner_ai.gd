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
const VOID_Y := -12.0
const CENTER_PULL_TIME := 4.0
const IDEAL_ESCAPE_DISTANCE := 12.0

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
	if global_position.y < VOID_Y:
		_respawn()

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
		coyote_timer = 0.0

	_apply_gravity(delta)

	var accel := acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, desired_dir.x * walk_speed, accel * delta)
	velocity.z = move_toward(velocity.z, desired_dir.z * walk_speed, accel * delta)

	if desired_dir.length_squared() > 0.01:
		var face_dir := desired_dir.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(face_dir.x, face_dir.z), clampf(delta * 10.0, 0.0, 1.0))

	move_and_slide()
	last_position = global_position

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
		score -= 9.0
	if not _has_ground_ahead(dir, 2.2):
		score -= 2.6
	if current_distance < 4.0 and dir.dot(away) < 0.2:
		score -= 4.0
	return score

func _probe_dir(dir: Vector3) -> Vector3:
	if dir.length_squared() < 0.01:
		return Vector3.ZERO
	dir = dir.normalized()
	if _front_blocked(dir) or _wall_too_close(dir) or not _has_ground_ahead(dir, 0.9):
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
	for height in PackedFloat32Array([0.45, 0.9]):
		var from := global_position + Vector3.UP * height
		var to := from + dir.normalized() * 1.05
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			return true
	return false

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
	last_position = global_position

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
	if String(skin.get("collision_shape", "capsule")) == "box":
		var box := BoxShape3D.new()
		box.size = skin.get("collision_size", Vector3(0.7, 1.2, 0.5)) as Vector3
		collision.shape = box
	else:
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
