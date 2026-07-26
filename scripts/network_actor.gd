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
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = capsule.radius
	capsule_mesh.height = capsule.height
	mesh.mesh = capsule_mesh
	mesh.position.y = collision.position.y
	mesh.material_override = _material(Color(1.0, 0.24, 0.18) if role == "tagger" else Color(0.15, 0.5, 1.0))
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

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	return mat
