extends CharacterBody3D

const SkinAPI = preload("res://scripts/skin_api.gd")

var walk_speed := 7.0
var acceleration := 26.0
var air_acceleration := 9.0
var jump_velocity := 7.4
var vault_velocity := 6.2
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var mouse_sensitivity := 0.0024
var is_control_locked := false
var camera_mode := "third_person"

var camera_pivot: Node3D
var camera: Camera3D
var coyote_timer := 0.0
var skin_id := "default"
var spawn_position := Vector3.ZERO
var move_speed_multiplier := 1.0
var move_speed_effect_time := 0.0
const VOID_Y := -12.0
const STEP_MAX_HEIGHT := 0.55
const STEP_FORWARD_DISTANCE := 0.45
const CAMERA_PIVOT_FROM_COLLISION := Vector3(0.0, 0.63, 0.0)
const FIRST_PERSON_CAMERA_OFFSET := Vector3(0.0, 0.0, -0.08)
const FIRST_PERSON_CAMERA_RADIUS := 0.08
const FIRST_PERSON_CAMERA_PADDING := 0.04
const CAMERA_TOP_CLEARANCE := 0.03
func _ready() -> void:
	spawn_position = global_position
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	_build_body()

func _unhandled_input(event: InputEvent) -> void:
	if is_control_locked:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		var min_pitch := deg_to_rad(-80.0) if camera_mode == "first_person" else deg_to_rad(-38.0)
		var max_pitch := deg_to_rad(80.0) if camera_mode == "first_person" else deg_to_rad(24.0)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
		_update_camera_collision()

func _physics_process(delta: float) -> void:
	if move_speed_effect_time > 0.0:
		move_speed_effect_time = maxf(move_speed_effect_time - delta, 0.0)
		if move_speed_effect_time <= 0.0:
			move_speed_multiplier = 1.0
	if is_control_locked:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		_update_camera_collision()
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
	var current_walk_speed := walk_speed * move_speed_multiplier
	velocity.x = move_toward(velocity.x, wish_dir.x * current_walk_speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish_dir.z * current_walk_speed, accel * delta)
	_move_with_step_climbing(delta)
	_update_camera_collision()

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	coyote_timer = 0.0
	move_speed_multiplier = 1.0
	move_speed_effect_time = 0.0

func apply_speed_multiplier(multiplier: float, duration: float) -> void:
	move_speed_multiplier = clampf(multiplier, 0.25, 2.5)
	move_speed_effect_time = maxf(duration, 0.0)

func get_throw_origin() -> Vector3:
	var right := global_transform.basis.x.normalized()
	var forward := -global_transform.basis.z.normalized()
	return global_position + right * 0.44 + Vector3.UP * 1.05 + forward * 0.16

func get_throw_direction() -> Vector3:
	if camera_pivot != null:
		return -camera_pivot.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()

func _move_with_step_climbing(delta: float) -> void:
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_vel.length_squared() >= 0.01 and is_on_floor() and velocity.y <= 0.0:
		if _try_step_move(horizontal_vel, delta):
			return
	move_and_slide()

func _try_step_move(horizontal_vel: Vector3, delta: float) -> bool:
	var foot_origin := _get_step_foot_position()
	var step_result := _detect_step_ahead(get_world_3d().direct_space_state, foot_origin, horizontal_vel.normalized())
	if step_result == Vector3.ZERO:
		return false

	var step_up := step_result.y - foot_origin.y + 0.01
	if step_up <= 0.0 or step_up > STEP_MAX_HEIGHT + 0.02:
		return false

	var start_transform := global_transform
	var up_motion := Vector3.UP * step_up
	var up_result := PhysicsTestMotionResult3D.new()
	if _body_test_motion(start_transform, up_motion, up_result):
		return false

	var raised_transform := start_transform
	raised_transform.origin += up_motion
	var horizontal_motion := horizontal_vel * delta
	var forward_result := PhysicsTestMotionResult3D.new()
	if _body_test_motion(raised_transform, horizontal_motion, forward_result):
		return false

	var forward_transform := raised_transform
	forward_transform.origin += horizontal_motion
	var down_result := PhysicsTestMotionResult3D.new()
	if not _body_test_motion(forward_transform, Vector3.DOWN * (step_up + 0.05), down_result):
		return false
	# 胶囊首次落到台阶棱角时法线会偏斜；只要求落点具有向上的支撑分量。
	# 台阶顶面是否水平已经由 _detect_step_ahead() 单独验证。
	if down_result.get_collision_normal().dot(Vector3.UP) <= 0.05:
		return false

	var target_position := forward_transform.origin + down_result.get_travel()
	var actual_step_height := target_position.y - start_transform.origin.y
	if actual_step_height < 0.02 or actual_step_height > STEP_MAX_HEIGHT + 0.01:
		return false

	global_position = target_position
	velocity.x = horizontal_vel.x
	velocity.y = -0.2
	velocity.z = horizontal_vel.z
	return true

func _body_test_motion(from: Transform3D, motion: Vector3, result: PhysicsTestMotionResult3D) -> bool:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = from
	parameters.motion = motion
	parameters.margin = safe_margin
	parameters.max_collisions = 4
	parameters.recovery_as_collision = false
	parameters.collide_separation_ray = false
	return PhysicsServer3D.body_test_motion(get_rid(), parameters, result)

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
	# 仅沿实际移动方向发射角色身宽内的平行射线，避免侧方台阶提前抬升。
	var angles := [0.0]
	var side := move_dir.cross(Vector3.UP).normalized()
	var lateral_offsets := [0.0, 0.25, -0.25]
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
	# 低位射线直接命中可行走表面时是斜坡，不应触发台阶传送。
	var low_normal: Vector3 = low_hit["normal"]
	if low_normal.angle_to(Vector3.UP) <= floor_max_angle:
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

	var hit_point: Vector3 = low_hit["position"]
	var hit_normal: Vector3 = low_hit["normal"]
	# 可行走斜坡交给 move_and_slide，只有陡峭立面才可能是台阶。
	if hit_normal.angle_to(Vector3.UP) <= floor_max_angle:
		return Vector3.ZERO
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

	# 低位射线已确认前方是陡峭端面；允许端面后方连接可行走斜坡。
	# 普通斜坡会在低位法线检查处返回，不会持续触发手动步进。
	if step_normal.angle_to(Vector3.UP) > floor_max_angle:
		return Vector3.ZERO

	var step_height := step_top.y - origin.y
	if step_height < 0.02 or step_height > STEP_MAX_HEIGHT:
		return Vector3.ZERO

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
	velocity.x = dir.x * walk_speed * 1.18
	velocity.z = dir.z * walk_speed * 1.18
	return true

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
		custom_model.name = "RunnerCustomModel"
		add_child(custom_model)
	else:
		var model_node := SkinAPI.instantiate_skin_model(skin_id, String(skin.get("model_scene", "")))
		if model_node != null:
			model_node.name = "RunnerModel"
			model_node.position.y = float(skin.get("mesh_y", collision.position.y))
			var model_scale := maxf(0.01, float(skin.get("model_scale", 1.0)))
			model_node.scale = Vector3.ONE * model_scale
			add_child(model_node)
		else:
			var mesh := MeshInstance3D.new()
			mesh.name = "RunnerMesh"
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

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = _get_camera_pivot_position()
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

func _get_camera_pivot_position() -> Vector3:
	var collision := get_node_or_null("Collision") as CollisionShape3D
	var collision_position := collision.position if collision != null else Vector3(0.0, 0.92, 0.0)
	var desired_position := collision_position + CAMERA_PIVOT_FROM_COLLISION
	desired_position.y = minf(desired_position.y, _get_collision_top_local_y() - CAMERA_TOP_CLEARANCE)
	return desired_position

func _get_collision_top_local_y() -> float:
	var collision := get_node_or_null("Collision") as CollisionShape3D
	if collision == null or collision.shape == null:
		return 1.78
	var half_height := 0.0
	if collision.shape is CapsuleShape3D:
		half_height = (collision.shape as CapsuleShape3D).height * 0.5
	elif collision.shape is BoxShape3D:
		half_height = (collision.shape as BoxShape3D).size.y * 0.5
	elif collision.shape is SphereShape3D:
		half_height = (collision.shape as SphereShape3D).radius
	elif collision.shape is CylinderShape3D:
		half_height = (collision.shape as CylinderShape3D).height * 0.5
	return collision.position.y + half_height * absf(collision.scale.y)

func _get_collision_top_global_y() -> float:
	return to_global(Vector3(0.0, _get_collision_top_local_y(), 0.0)).y

func _get_camera_collision_anchor() -> Vector3:
	var collision := get_node_or_null("Collision") as CollisionShape3D
	return collision.global_position if collision != null else global_position + Vector3.UP * 0.92

func _apply_camera_mode() -> void:
	_set_local_visuals_visible(camera_mode != "first_person")
	if camera_pivot == null or camera == null:
		return
	var pivot_position := _get_camera_pivot_position()
	if camera_mode == "first_person":
		camera_pivot.position = pivot_position + FIRST_PERSON_CAMERA_OFFSET
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(70.0))
		camera.position = Vector3.ZERO
		camera.near = 0.03
	else:
		camera_pivot.position = pivot_position
		camera.position = Vector3(0.0, 0.0, 6.0)
		camera.near = 0.08
	_update_camera_collision()

func _update_camera_collision() -> void:
	if camera_pivot == null or camera == null or get_world_3d() == null:
		return
	var camera_radius := 0.28
	var padding := 0.16
	if camera_mode == "first_person":
		camera.position = _resolve_safe_camera_local_position(
			Vector3.ZERO,
			_get_camera_collision_anchor(),
			FIRST_PERSON_CAMERA_RADIUS,
			FIRST_PERSON_CAMERA_PADDING,
			FIRST_PERSON_CAMERA_RADIUS + CAMERA_TOP_CLEARANCE
		)
		return
	if camera_mode != "third_person":
		return
	var desired_distance := 6.0
	var from := camera_pivot.global_position
	camera.position = _resolve_safe_camera_local_position(Vector3(0.0, 0.0, desired_distance), from, camera_radius, padding)

func _resolve_safe_camera_local_position(
	desired_local: Vector3,
	anchor: Vector3,
	camera_radius: float,
	padding: float,
	top_clearance: float = CAMERA_TOP_CLEARANCE
) -> Vector3:
	var target := camera_pivot.to_global(desired_local)
	target.y = minf(target.y, _get_collision_top_global_y() - top_clearance)
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

func _material(color: Color, roughness: float = 0.74, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = clampf(roughness, 0.0, 1.0)
	if texture != null:
		mat.albedo_texture = texture
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(1.4, 1.4, 1.4)
	return mat
