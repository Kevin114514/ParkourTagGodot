extends CharacterBody3D

const SkinAPI = preload("res://scripts/skin_api.gd")

var walk_speed := 7.0
var acceleration := 24.0
var air_acceleration := 9.0
var jump_velocity := 7.0
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var is_control_locked := false
var is_active := true
var skin_id := "default"
var target: Node3D

var spawn_position := Vector3.ZERO
var coyote_timer := 0.0
var repath_timer := 0.0
var desired_dir := Vector3.ZERO
const VOID_Y := -12.0

func _ready() -> void:
	spawn_position = global_position
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	_build_body()

func _physics_process(delta: float) -> void:
	if global_position.y < VOID_Y:
		_respawn()

	if is_control_locked or not is_active:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	if target == null or not is_instance_valid(target):
		desired_dir = -global_transform.basis.z
	else:
		repath_timer -= delta
		if repath_timer <= 0.0:
			repath_timer = 0.12
			desired_dir = _compute_escape_dir()

	if is_on_floor():
		coyote_timer = 0.12
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if _should_jump():
		velocity.y = jump_velocity
		coyote_timer = 0.0

	_apply_gravity(delta)

	var accel := acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, desired_dir.x * walk_speed, accel * delta)
	velocity.z = move_toward(velocity.z, desired_dir.z * walk_speed, accel * delta)

	if desired_dir.length_squared() > 0.01:
		var face_dir := desired_dir.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(face_dir.x, face_dir.z), clampf(delta * 8.0, 0.0, 1.0))

	move_and_slide()

func _compute_escape_dir() -> Vector3:
	var away := global_position - target.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -global_transform.basis.z
	away = away.normalized()

	var probe := _probe_dir(away)
	if probe.length_squared() > 0.01:
		return probe

	var side_a := away.rotated(Vector3.UP, deg_to_rad(42.0)).normalized()
	probe = _probe_dir(side_a)
	if probe.length_squared() > 0.01:
		return probe

	var side_b := away.rotated(Vector3.UP, deg_to_rad(-42.0)).normalized()
	probe = _probe_dir(side_b)
	if probe.length_squared() > 0.01:
		return probe

	return away

func _probe_dir(dir: Vector3) -> Vector3:
	var from := global_position + Vector3.UP * 0.78
	var to := from + dir * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return dir
	return Vector3.ZERO

func _should_jump() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not (is_on_floor() or coyote_timer > 0.0):
		return false

	var to_target := target.global_position - global_position
	if to_target.y > 0.8:
		return true

	var forward := desired_dir
	if forward.length_squared() < 0.01:
		forward = -global_transform.basis.z
	forward = forward.normalized()

	var low_from := global_position + Vector3.UP * 0.72
	var low_to := low_from + forward * 0.9
	var low_query := PhysicsRayQueryParameters3D.create(low_from, low_to)
	low_query.collision_mask = 1
	low_query.exclude = [get_rid()]
	var low_hit := get_world_3d().direct_space_state.intersect_ray(low_query)
	if low_hit.is_empty():
		return false

	var high_from := global_position + Vector3.UP * 1.45
	var high_to := high_from + forward * 0.9
	var high_query := PhysicsRayQueryParameters3D.create(high_from, high_to)
	high_query.collision_mask = 1
	high_query.exclude = [get_rid()]
	var high_hit := get_world_3d().direct_space_state.intersect_ray(high_query)
	return high_hit.is_empty()

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	coyote_timer = 0.0
	repath_timer = 0.0
	desired_dir = Vector3.ZERO

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

func _material(color: Color, roughness: float = 0.74, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = clampf(roughness, 0.0, 1.0)
	if texture != null:
		mat.albedo_texture = texture
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(1.4, 1.4, 1.4)
	return mat
