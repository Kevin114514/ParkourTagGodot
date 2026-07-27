extends CharacterBody3D

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
var last_position := Vector3.ZERO
var jump_cooldown := 0.0
var descent_dir := Vector3.ZERO
var descent_repath_timer := 0.0
var spawn_position := Vector3.ZERO
const VOID_Y := -12.0

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
	if global_position.y < VOID_Y:
		_respawn()

	jump_cooldown = maxf(jump_cooldown - delta, 0.0)
	if velocity.y > MAX_UPWARD_VELOCITY:
		velocity.y = MAX_UPWARD_VELOCITY
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
		avoid_sign = -avoid_sign
		stuck_timer = 0.0

	_apply_gravity(delta)
	if velocity.y > MAX_UPWARD_VELOCITY:
		velocity.y = MAX_UPWARD_VELOCITY
	velocity.x = move_toward(velocity.x, move_dir.x * chase_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, move_dir.z * chase_speed, acceleration * delta)

	if move_dir.length_squared() > 0.01:
		look_at(global_position + move_dir, Vector3.UP)
	move_and_slide()
	last_position = global_position

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	stuck_timer = 0.0
	jump_cooldown = 0.0
	descent_dir = Vector3.ZERO
	descent_repath_timer = 0.0
	last_position = global_position

func _line_to_target_blocked() -> bool:
	var from: Vector3 = global_position + Vector3.UP * 0.9
	var to: Vector3 = target.global_position + Vector3.UP * 0.75
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()

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

func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.2
	elif not is_on_floor():
		velocity.y -= gravity * delta

func _front_blocked(dir: Vector3) -> bool:
	if dir.length_squared() < 0.01:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.65
	var to := from + dir.normalized() * 1.25
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return not hit.is_empty()

func _build_body() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.82
	collision.shape = capsule
	collision.position.y = 0.96
	add_child(collision)

	var mesh := MeshInstance3D.new()
	mesh.name = "TaggerMesh"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.38
	capsule_mesh.height = 1.82
	mesh.mesh = capsule_mesh
	mesh.position.y = 0.96
	mesh.material_override = _material(Color(1.0, 0.24, 0.18))
	add_child(mesh)

	var marker := MeshInstance3D.new()
	marker.name = "ForwardMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.5, 0.12, 0.1)
	marker.mesh = marker_mesh
	marker.position = Vector3(0.0, 1.42, -0.37)
	marker.material_override = _material(Color(1.0, 0.9, 0.15))
	add_child(marker)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.68
	return mat
