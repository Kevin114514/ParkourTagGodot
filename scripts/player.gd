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
const VOID_Y := -12.0

func _ready() -> void:
	spawn_position = global_position
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	_build_body()

func _unhandled_input(event: InputEvent) -> void:
	if is_control_locked:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		var min_pitch := deg_to_rad(-80.0) if camera_mode == "first_person" else deg_to_rad(-38.0)
		var max_pitch := deg_to_rad(80.0) if camera_mode == "first_person" else deg_to_rad(24.0)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)

func _physics_process(delta: float) -> void:
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
	velocity.x = move_toward(velocity.x, wish_dir.x * walk_speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish_dir.z * walk_speed, accel * delta)
	move_and_slide()
	_update_camera_collision()

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	coyote_timer = 0.0

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

func _update_camera_collision() -> void:
	if camera_mode != "third_person" or camera_pivot == null or camera == null:
		return
	var desired_distance := 6.0
	var min_distance := 0.55
	var from := camera_pivot.global_position
	var to := from + camera_pivot.global_transform.basis.z.normalized() * desired_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var distance := desired_distance
	if not hit.is_empty():
		distance = clampf(from.distance_to(hit["position"]) - 0.18, min_distance, desired_distance)
	camera.position = Vector3(0.0, 0.0, distance)

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
