extends CharacterBody3D

var walk_speed := 7.0
var acceleration := 26.0
var air_acceleration := 9.0
var jump_velocity := 7.4
var vault_velocity := 6.2
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var mouse_sensitivity := 0.0024
var is_control_locked := false

var camera_pivot: Node3D
var body_mesh: MeshInstance3D
var coyote_timer := 0.0
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
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(-38.0), deg_to_rad(24.0))

func _physics_process(delta: float) -> void:
	if is_control_locked:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
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
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.72
	collision.shape = capsule
	collision.position.y = 0.92
	add_child(collision)

	var mesh := MeshInstance3D.new()
	mesh.name = "RunnerMesh"
	mesh.mesh = _create_unwrapped_capsule_mesh(capsule.radius, capsule.height)
	mesh.position.y = collision.position.y
	mesh.material_override = _material(Color(0.15, 0.5, 1.0))
	body_mesh = mesh
	add_child(mesh)

	var visor := MeshInstance3D.new()
	visor.name = "ForwardVisor"
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.44, 0.1, 0.08)
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 1.34, -0.34)
	visor.material_override = _material(Color(0.95, 0.98, 1.0))
	add_child(visor)

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0.0, 1.55, 0.0)
	camera_pivot.rotation.x = deg_to_rad(-11.0)
	add_child(camera_pivot)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 72.0
	camera.position = Vector3(0.0, 0.0, 6.0)
	camera_pivot.add_child(camera)

func apply_skin(skin_path: String) -> void:
	if body_mesh == null or not is_instance_valid(body_mesh):
		return
	if skin_path.is_empty():
		body_mesh.material_override = _material(Color(0.15, 0.5, 1.0))
		return
	var texture := _load_skin_texture(skin_path)
	if texture == null:
		body_mesh.material_override = _material(Color(0.15, 0.5, 1.0))
		return
	var mat := _material(Color.WHITE)
	mat.albedo_texture = texture
	body_mesh.material_override = mat

func _create_unwrapped_capsule_mesh(radius: float, total_height: float) -> ArrayMesh:
	var segments := 32
	var cap_rings := 6
	var cylinder_height := maxf(total_height - radius * 2.0, 0.01)
	var ring_data: Array[Vector2] = []
	for i in range(cap_rings + 1):
		var theta := -PI * 0.5 + (PI * 0.5 * float(i) / float(cap_rings))
		ring_data.append(Vector2(-cylinder_height * 0.5 + sin(theta) * radius, cos(theta) * radius))
	ring_data.append(Vector2(cylinder_height * 0.5, radius))
	for i in range(1, cap_rings + 1):
		var theta := PI * 0.5 * float(i) / float(cap_rings)
		ring_data.append(Vector2(cylinder_height * 0.5 + sin(theta) * radius, cos(theta) * radius))

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring_index in range(ring_data.size()):
		var y := ring_data[ring_index].x
		var ring_radius := ring_data[ring_index].y
		var v := 1.0 - clampf((y + total_height * 0.5) / total_height, 0.0, 1.0)
		for segment in range(segments + 1):
			var u := float(segment) / float(segments)
			var angle := TAU * (u - 0.125)
			var x := -sin(angle) * ring_radius
			var z := cos(angle) * ring_radius
			vertices.append(Vector3(x, y, z))
			uvs.append(Vector2(u, v))
			normals.append(_capsule_normal(Vector3(x, y, z), radius, cylinder_height))

	var stride := segments + 1
	for ring_index in range(ring_data.size() - 1):
		for segment in range(segments):
			var a := ring_index * stride + segment
			var b := a + 1
			var c := (ring_index + 1) * stride + segment
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _capsule_normal(point: Vector3, radius: float, cylinder_height: float) -> Vector3:
	var cap_center_y := 0.0
	if point.y > cylinder_height * 0.5:
		cap_center_y = cylinder_height * 0.5
	elif point.y < -cylinder_height * 0.5:
		cap_center_y = -cylinder_height * 0.5
	else:
		return Vector3(point.x, 0.0, point.z).normalized()
	var normal := Vector3(point.x, point.y - cap_center_y, point.z)
	if normal.length_squared() < 0.001:
		return Vector3.UP if point.y > 0.0 else Vector3.DOWN
	return normal.normalized()

func _load_skin_texture(skin_path: String) -> Texture2D:
	if skin_path.begins_with("res://") or skin_path.begins_with("user://"):
		var resource := load(skin_path)
		if resource is Texture2D:
			return resource as Texture2D
	var image := Image.new()
	var error := image.load(skin_path)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.74
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
