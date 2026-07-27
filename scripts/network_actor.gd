extends CharacterBody3D

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

var camera_pivot: Node3D
var body_mesh: MeshInstance3D
var coyote_timer := 0.0
var local_control := false
var remote_position := Vector3.ZERO
var remote_rotation_y := 0.0
var remote_velocity := Vector3.ZERO
var sync_timer := 0.0
var spawn_position := Vector3.ZERO
const VOID_Y := -12.0

func configure(new_role: String, peer_id: int) -> void:
	role = new_role
	owner_peer_id = peer_id
	set_multiplayer_authority(owner_peer_id)

func _ready() -> void:
	spawn_position = global_position
	set_multiplayer_authority(owner_peer_id)
	local_control = owner_peer_id == multiplayer.get_unique_id()
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
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(-38.0), deg_to_rad(24.0))

func _physics_process(delta: float) -> void:
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
		_send_state(delta)
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if is_on_floor():
		coyote_timer = 0.12
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		if role == "runner" and _try_vault(wish_dir):
			pass
		elif is_on_floor() or coyote_timer > 0.0:
			velocity.y = jump_velocity
			coyote_timer = 0.0

	_apply_gravity(delta)
	var accel := acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, wish_dir.x * move_speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish_dir.z * move_speed, accel * delta)
	move_and_slide()
	_send_state(delta)

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	coyote_timer = 0.0
	remote_position = spawn_position
	remote_velocity = Vector3.ZERO

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
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38 if role == "tagger" else 0.35
	capsule.height = 1.82 if role == "tagger" else 1.72
	collision.shape = capsule
	collision.position.y = 0.96 if role == "tagger" else 0.92
	add_child(collision)

	var mesh := MeshInstance3D.new()
	mesh.name = "TaggerMesh" if role == "tagger" else "RunnerMesh"
	mesh.mesh = _create_unwrapped_capsule_mesh(capsule.radius, capsule.height)
	mesh.position.y = collision.position.y
	mesh.material_override = _material(_default_body_color())
	body_mesh = mesh
	add_child(mesh)

	var marker := MeshInstance3D.new()
	marker.name = "ForwardMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.5, 0.12, 0.1)
	marker.mesh = marker_mesh
	marker.position = Vector3(0.0, 1.42, -0.37)
	marker.material_override = _material(Color(1.0, 0.9, 0.15) if role == "tagger" else Color(0.95, 0.98, 1.0))
	add_child(marker)

func _add_camera() -> void:
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

func get_catch_origin() -> Vector3:
	return global_position + Vector3.UP * 1.25

func get_catch_direction() -> Vector3:
	if camera_pivot != null and is_instance_valid(camera_pivot):
		return -camera_pivot.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()

func apply_skin(skin_path: String) -> void:
	if body_mesh == null or not is_instance_valid(body_mesh):
		return
	if skin_path.is_empty():
		body_mesh.material_override = _material(_default_body_color())
		return
	var texture := _load_skin_texture(skin_path)
	if texture == null:
		body_mesh.material_override = _material(_default_body_color())
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

func _default_body_color() -> Color:
	return Color(1.0, 0.24, 0.18) if role == "tagger" else Color(0.15, 0.5, 1.0)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
