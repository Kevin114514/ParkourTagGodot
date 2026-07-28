extends CharacterBody3D

const SkinAPI = preload("res://scripts/skin_api.gd")

var role := "runner"
var owner_peer_id := 1
var move_speed := 7.0
var acceleration := 26.0
var air_acceleration := 9.0
var jump_velocity := 7.4
var vault_velocity := 6.2
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var mouse_sensitivity := 0.0024
var is_control_locked := false
var is_active := true
var camera_mode := "third_person"

var camera_pivot: Node3D
var camera: Camera3D
var coyote_timer := 0.0
var skin_id := "default"
var local_control := false
var remote_position := Vector3.ZERO
var remote_rotation_y := 0.0
var remote_velocity := Vector3.ZERO
var sync_timer := 0.0
var spawn_position := Vector3.ZERO
var move_speed_multiplier := 1.0
var move_speed_effect_time := 0.0
const VOID_Y := -12.0
const STEP_MAX_HEIGHT := 0.52
const STEP_FORWARD_DISTANCE := 0.45
var _step_inward_dir := Vector3.ZERO  # 上一次台阶检测的内侧方向（法线反向）

func configure(new_role: String, peer_id: int, new_skin_id: String = "default") -> void:
	role = new_role
	owner_peer_id = peer_id
	skin_id = new_skin_id
	set_multiplayer_authority(owner_peer_id)

func _ready() -> void:
	spawn_position = global_position
	set_multiplayer_authority(owner_peer_id)
	local_control = multiplayer.multiplayer_peer == null or owner_peer_id == multiplayer.get_unique_id()
	collision_layer = 4 if role == "tagger" else 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	if role == "tagger":
		move_speed = 7.8
		jump_velocity = 7.4
		acceleration = 24.0
	else:
		move_speed = 7.0
		jump_velocity = 7.4
		acceleration = 26.0
	remote_position = global_position
	remote_rotation_y = rotation.y
	_build_body()
	if local_control:
		_add_camera()

func _unhandled_input(event: InputEvent) -> void:
	if not local_control or is_control_locked or not is_active:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and camera_pivot != null:
		rotate_y(-event.relative.x * mouse_sensitivity)
		var min_pitch := deg_to_rad(-80.0) if camera_mode == "first_person" else deg_to_rad(-38.0)
		var max_pitch := deg_to_rad(80.0) if camera_mode == "first_person" else deg_to_rad(24.0)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)

func _physics_process(delta: float) -> void:
	if move_speed_effect_time > 0.0:
		move_speed_effect_time = maxf(move_speed_effect_time - delta, 0.0)
		if move_speed_effect_time <= 0.0:
			move_speed_multiplier = 1.0
	if local_control and role == "tagger" and global_position.y < VOID_Y:
		_respawn()
		_send_state(999.0)

	if not local_control:
		global_position = global_position.lerp(remote_position, clampf(delta * 14.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, remote_rotation_y, clampf(delta * 14.0, 0.0, 1.0))
		velocity = remote_velocity
		return

	if is_control_locked or not is_active:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		_update_camera_collision()
		_send_state(delta)
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if is_on_floor():
		coyote_timer = 0.12
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		if _try_vault(wish_dir):
			pass
		elif is_on_floor() or coyote_timer > 0.0:
			velocity.y = jump_velocity
			coyote_timer = 0.0

	_apply_gravity(delta)
	var accel := acceleration if is_on_floor() else air_acceleration
	var current_move_speed := move_speed * move_speed_multiplier
	velocity.x = move_toward(velocity.x, wish_dir.x * current_move_speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish_dir.z * current_move_speed, accel * delta)
	_move_with_step_climbing(delta)
	_update_camera_collision()
	_send_state(delta)

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	coyote_timer = 0.0
	remote_position = spawn_position
	remote_velocity = Vector3.ZERO
	move_speed_multiplier = 1.0
	move_speed_effect_time = 0.0

func apply_speed_multiplier(multiplier: float, duration: float) -> void:
	move_speed_multiplier = clampf(multiplier, 0.25, 2.5)
	move_speed_effect_time = maxf(duration, 0.0)

func _send_state(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	sync_timer -= delta
	if sync_timer > 0.0:
		return
	sync_timer = 0.04
	rpc("_receive_state", global_position, rotation.y, velocity)

@rpc("any_peer", "unreliable")
func _receive_state(new_position: Vector3, new_rotation_y: float, new_velocity: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	if local_control:
		return
	remote_position = new_position
	remote_rotation_y = new_rotation_y
	remote_velocity = new_velocity

func _move_with_step_climbing(delta: float) -> void:
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_vel.length_squared() < 0.01 or not is_on_floor():
		move_and_slide()
		return

	var move_dir := horizontal_vel.normalized()
	# 用当前实际水平速度推进台阶，保留 move_toward 的结果（松键会自然减速）
	var current_speed := horizontal_vel.length()
	var space := get_world_3d().direct_space_state

	# 子步进检测：将一帧拆成多次小步，更快捕捉台阶避免漂移
	var sub_steps := 3
	var sub_delta := delta / float(sub_steps)
	for i in sub_steps:
		var step_result := _detect_step_ahead(space, global_position, move_dir)
		if step_result != Vector3.ZERO:
			global_position.y = step_result.y + 0.01
			global_position.x += move_dir.x * current_speed * sub_delta
			global_position.z += move_dir.z * current_speed * sub_delta
			# 沿楼梯正交方向（内侧）补偿，防止漂移到楼梯侧面掉下去
			if _step_inward_dir.length_squared() > 0.01:
				global_position.x += _step_inward_dir.x * 0.04
				global_position.z += _step_inward_dir.z * 0.04
		else:
			# 本子步没有台阶，正常移动（不覆盖 velocity，保留按键对应的速度）
			move_and_slide()
			return

	# 所有子步都在爬台阶：保留水平速度供下一帧衔接，仅清零 Y
	velocity.y = 0.0

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

func _try_vault(wish_dir: Vector3) -> bool:
	var dir := wish_dir
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z
	dir = dir.normalized()

	var space := get_world_3d().direct_space_state
	var low_from := global_position + Vector3.UP * 0.78
	var low_to := low_from + dir * 1.25
	var high_from := global_position + Vector3.UP * 1.55
	var high_to := high_from + dir * 1.25

	var low_query := PhysicsRayQueryParameters3D.create(low_from, low_to)
	low_query.collision_mask = 1
	low_query.exclude = [get_rid()]
	var low_hit := space.intersect_ray(low_query)
	if low_hit.is_empty():
		return false

	var high_query := PhysicsRayQueryParameters3D.create(high_from, high_to)
	high_query.collision_mask = 1
	high_query.exclude = [get_rid()]
	var high_hit := space.intersect_ray(high_query)
	if not high_hit.is_empty():
		return false

	velocity.y = maxf(velocity.y, vault_velocity)
	velocity.x = dir.x * move_speed * 1.18
	velocity.z = dir.z * move_speed * 1.18
	return true

func _build_body() -> void:
	var skin := SkinAPI.load_role_skin(role, skin_id)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(skin.get("radius", 0.38 if role == "tagger" else 0.35))
	capsule.height = float(skin.get("height", 1.82 if role == "tagger" else 1.72))
	if String(skin.get("collision_shape", "capsule")) == "box":
		var box := BoxShape3D.new()
		box.size = skin.get("collision_size", Vector3(0.7, 1.2, 0.5)) as Vector3
		collision.shape = box
	else:
		collision.shape = capsule
	collision.position.y = float(skin.get("collision_y", 0.96 if role == "tagger" else 0.92))
	add_child(collision)

	var custom_model := SkinAPI.create_skin_visual_model(skin_id, skin)
	if custom_model != null:
		custom_model.name = "NetworkCustomModel"
		add_child(custom_model)
	else:
		var model_node := SkinAPI.instantiate_skin_model(skin_id, String(skin.get("model_scene", "")))
		if model_node != null:
			model_node.name = "NetworkModel"
			model_node.position.y = float(skin.get("mesh_y", collision.position.y))
			var model_scale := maxf(0.01, float(skin.get("model_scale", 1.0)))
			model_node.scale = Vector3.ONE * model_scale
			add_child(model_node)
		else:
			var mesh := MeshInstance3D.new()
			mesh.name = "TaggerMesh" if role == "tagger" else "RunnerMesh"
			var capsule_mesh := CapsuleMesh.new()
			capsule_mesh.radius = capsule.radius
			capsule_mesh.height = capsule.height
			mesh.mesh = capsule_mesh
			mesh.position.y = float(skin.get("mesh_y", collision.position.y))
			mesh.material_override = _material(
				skin.get("body_color", Color(1.0, 0.24, 0.18) if role == "tagger" else Color(0.15, 0.5, 1.0)) as Color,
				float(skin.get("roughness", 0.68 if role == "tagger" else 0.74)),
				SkinAPI.load_skin_texture(skin_id, String(skin.get("body_texture", "")))
			)
			add_child(mesh)

	if not bool(skin.get("hide_marker", false)):
		var marker := MeshInstance3D.new()
		marker.name = "ForwardMarker"
		var marker_mesh := BoxMesh.new()
		marker_mesh.size = Vector3(0.5, 0.12, 0.1)
		marker.mesh = marker_mesh
		marker.position = Vector3(0.0, float(skin.get("marker_y", 1.42 if role == "tagger" else 1.34)), float(skin.get("marker_z", -0.37 if role == "tagger" else -0.34)))
		marker.material_override = _material(
			skin.get("marker_color", Color(1.0, 0.9, 0.15) if role == "tagger" else Color(0.95, 0.98, 1.0)) as Color,
			float(skin.get("marker_roughness", skin.get("roughness", 0.7))),
			SkinAPI.load_skin_texture(skin_id, String(skin.get("marker_texture", "")))
		)
		add_child(marker)

func _add_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0.0, 1.55, 0.0)
	camera_pivot.rotation.x = deg_to_rad(-11.0)
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 72.0
	camera_pivot.add_child(camera)
	_apply_camera_mode()

func set_camera_mode(new_mode: String) -> void:
	camera_mode = new_mode if new_mode == "first_person" else "third_person"
	_apply_camera_mode()

func _apply_camera_mode() -> void:
	if local_control:
		_set_local_visuals_visible(camera_mode != "first_person")
	if camera_pivot == null or camera == null:
		return
	if camera_mode == "first_person":
		camera_pivot.position = Vector3(0.0, 1.55, -0.08)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(70.0))
		camera.position = Vector3.ZERO
		camera.near = 0.03
	else:
		camera_pivot.position = Vector3(0.0, 1.55, 0.0)
		camera.position = Vector3(0.0, 0.0, 6.0)
		camera.near = 0.08
	_update_camera_collision()

func get_catch_origin() -> Vector3:
	if local_control and camera_pivot != null:
		return camera_pivot.global_position
	return global_position + Vector3.UP * 1.0

func get_catch_direction() -> Vector3:
	if local_control and camera_pivot != null:
		return -camera_pivot.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()

func get_throw_origin() -> Vector3:
	if local_control and camera_pivot != null:
		return camera_pivot.global_position + -camera_pivot.global_transform.basis.z.normalized() * 0.4
	return global_position + Vector3.UP * 1.15

func get_throw_direction() -> Vector3:
	if local_control and camera_pivot != null:
		return -camera_pivot.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()

func _update_camera_collision() -> void:
	if camera_pivot == null or camera == null or get_world_3d() == null:
		return
	var camera_radius := 0.28
	var padding := 0.16
	if camera_mode == "first_person":
		var head_anchor := global_position + Vector3.UP * 1.05
		camera.position = _resolve_safe_camera_local_position(Vector3.ZERO, head_anchor, camera_radius, padding)
		return
	if camera_mode != "third_person":
		return
	var desired_distance := 6.0
	var min_distance := 0.55
	var from := camera_pivot.global_position
	var direction := camera_pivot.global_transform.basis.z.normalized()
	var motion := direction * desired_distance
	var space := get_world_3d().direct_space_state
	var distance := desired_distance

	var sphere := SphereShape3D.new()
	sphere.radius = camera_radius
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis(), from)
	shape_query.motion = motion
	shape_query.collision_mask = 1
	shape_query.exclude = [get_rid()]
	var cast_result := space.cast_motion(shape_query)
	if cast_result.size() > 0:
		distance = clampf(desired_distance * float(cast_result[0]) - padding, min_distance, desired_distance)

	var ray_query := PhysicsRayQueryParameters3D.create(from, from + motion)
	ray_query.collision_mask = 1
	ray_query.exclude = [get_rid()]
	var hit := space.intersect_ray(ray_query)
	if not hit.is_empty():
		distance = minf(distance, clampf(from.distance_to(hit["position"]) - padding, min_distance, desired_distance))
	camera.position = _resolve_safe_camera_local_position(Vector3(0.0, 0.0, distance), from, camera_radius, padding)

func _resolve_safe_camera_local_position(desired_local: Vector3, anchor: Vector3, camera_radius: float, padding: float) -> Vector3:
	var target := camera_pivot.to_global(desired_local)
	var motion := target - anchor
	if motion.length_squared() < 0.0001:
		return desired_local
	var space := get_world_3d().direct_space_state
	var safe_target := target
	var direction := motion.normalized()
	var sphere := SphereShape3D.new()
	sphere.radius = camera_radius
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis(), anchor)
	shape_query.motion = motion
	shape_query.collision_mask = 1
	shape_query.exclude = [get_rid()]
	var cast_result := space.cast_motion(shape_query)
	if cast_result.size() > 0 and float(cast_result[0]) < 1.0:
		safe_target = anchor + motion * float(cast_result[0]) - direction * padding
	var ray_query := PhysicsRayQueryParameters3D.create(anchor, target)
	ray_query.collision_mask = 1
	ray_query.exclude = [get_rid()]
	var hit := space.intersect_ray(ray_query)
	if not hit.is_empty():
		var hit_position: Vector3 = hit["position"]
		var ray_target := hit_position - direction * padding
		if anchor.distance_squared_to(ray_target) < anchor.distance_squared_to(safe_target):
			safe_target = ray_target
	var overlap_query := PhysicsShapeQueryParameters3D.new()
	overlap_query.shape = sphere
	overlap_query.transform = Transform3D(Basis(), safe_target)
	overlap_query.collision_mask = 1
	overlap_query.exclude = [get_rid()]
	if not space.intersect_shape(overlap_query, 1).is_empty():
		safe_target = anchor
	return camera_pivot.to_local(safe_target)

func _set_local_visuals_visible(is_visible: bool) -> void:
	for child in get_children():
		_set_visual_tree_visible(child, is_visible)

func _set_visual_tree_visible(node: Node, is_visible: bool) -> void:
	if node == camera_pivot:
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = is_visible
	for child in node.get_children():
		_set_visual_tree_visible(child, is_visible)

func _material(color: Color, roughness: float = 0.7, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = clampf(roughness, 0.0, 1.0)
	if texture != null:
		mat.albedo_texture = texture
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(1.4, 1.4, 1.4)
	return mat
