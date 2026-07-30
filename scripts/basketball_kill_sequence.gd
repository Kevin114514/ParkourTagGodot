extends Node3D

signal finished

var cinematic_camera: Camera3D
var hoop_root: Node3D

func play(runner: Node3D, tagger: Node3D) -> void:
	if runner == null or tagger == null or not is_instance_valid(runner) or not is_instance_valid(tagger):
		finished.emit()
		queue_free()
		return

	var shot_forward := runner.global_position - tagger.global_position
	shot_forward.y = 0.0
	if shot_forward.length_squared() < 0.01:
		shot_forward = -tagger.global_transform.basis.z
	shot_forward.y = 0.0
	shot_forward = shot_forward.normalized()
	var side := shot_forward.cross(Vector3.UP).normalized()
	var catch_center := (runner.global_position + tagger.global_position) * 0.5
	var basket_base := _ground_position(catch_center + shot_forward * 5.0)

	hoop_root = _build_hoop()
	add_child(hoop_root)
	hoop_root.global_position = basket_base
	hoop_root.look_at(basket_base - shot_forward, Vector3.UP)
	hoop_root.scale = Vector3(0.01, 0.01, 0.01)

	var previous_camera := get_viewport().get_camera_3d()
	if previous_camera != null:
		previous_camera.current = false
	cinematic_camera = Camera3D.new()
	cinematic_camera.name = "BasketballFinishCamera"
	cinematic_camera.fov = 62.0
	cinematic_camera.near = 0.05
	add_child(cinematic_camera)
	cinematic_camera.global_position = catch_center + side * 6.2 + Vector3.UP * 3.4 - shot_forward * 1.2
	cinematic_camera.look_at(catch_center + shot_forward * 2.3 + Vector3.UP * 2.0, Vector3.UP)
	cinematic_camera.current = true
	await get_tree().process_frame
	cinematic_camera.current = true

	_set_actor_collision(runner, false)
	_set_actor_collision(tagger, false)
	runner.velocity = Vector3.ZERO
	tagger.velocity = Vector3.ZERO

	var reveal := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(hoop_root, "scale", Vector3.ONE, 0.34)
	await reveal.finished
	if not _actors_valid(runner, tagger):
		_finish_sequence()
		return

	var pickup_position := runner.global_position - shot_forward * 0.9
	pickup_position.y = tagger.global_position.y
	var approach := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	approach.tween_property(tagger, "global_position", pickup_position, 0.38)
	approach.parallel().tween_property(tagger, "rotation:y", _yaw_toward(shot_forward), 0.38)
	await approach.finished
	if not _actors_valid(runner, tagger):
		_finish_sequence()
		return

	var hold_position := tagger.global_position + Vector3.UP * 2.15 + shot_forward * 0.2
	var lift := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lift.tween_property(runner, "global_position", hold_position, 0.42)
	lift.parallel().tween_property(runner, "rotation:z", deg_to_rad(90.0), 0.42)
	lift.parallel().tween_property(tagger, "scale", Vector3(1.08, 0.92, 1.08), 0.18)
	lift.tween_property(tagger, "scale", Vector3.ONE, 0.16)
	await lift.finished
	if not _actors_valid(runner, tagger):
		_finish_sequence()
		return

	var rim_center := hoop_root.to_global(Vector3(0.0, 3.05, 0.0))
	var launch_point := hold_position + Vector3.UP * 2.8 + shot_forward * 1.2
	var dunk_entry := rim_center + Vector3.UP * 1.25 - shot_forward * 0.35
	var throw_tween := create_tween()
	throw_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	throw_tween.tween_property(runner, "global_position", launch_point, 0.34)
	throw_tween.parallel().tween_property(runner, "rotation:z", deg_to_rad(235.0), 0.34)
	throw_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	throw_tween.tween_property(runner, "global_position", dunk_entry, 0.42)
	throw_tween.parallel().tween_property(runner, "rotation:z", deg_to_rad(430.0), 0.42)
	throw_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	throw_tween.tween_property(runner, "global_position", rim_center + Vector3.DOWN * 1.45, 0.36)
	throw_tween.parallel().tween_property(runner, "rotation:z", deg_to_rad(540.0), 0.36)
	await throw_tween.finished
	if not _actors_valid(runner, tagger):
		_finish_sequence()
		return

	var celebration := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	celebration.tween_property(tagger, "scale", Vector3(1.22, 0.78, 1.22), 0.16)
	celebration.tween_property(tagger, "scale", Vector3(0.9, 1.18, 0.9), 0.18)
	celebration.tween_property(tagger, "scale", Vector3.ONE, 0.2)
	await celebration.finished
	await get_tree().create_timer(0.45).timeout
	_finish_sequence()

func _actors_valid(runner: Node3D, tagger: Node3D) -> bool:
	return is_instance_valid(runner) and is_instance_valid(tagger)

func _finish_sequence() -> void:
	finished.emit()

func _ground_position(desired: Vector3) -> Vector3:
	if get_world_3d() == null:
		return desired
	var query := PhysicsRayQueryParameters3D.create(desired + Vector3.UP * 8.0, desired + Vector3.DOWN * 30.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	return hit.get("position", desired) as Vector3

func _yaw_toward(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)

func _set_actor_collision(actor: Node3D, enabled: bool) -> void:
	if actor is CollisionObject3D:
		(actor as CollisionObject3D).collision_layer = 2 if enabled else 0
		(actor as CollisionObject3D).collision_mask = 1 if enabled else 0
	var collision := actor.get_node_or_null("Collision") as CollisionShape3D
	if collision != null:
		collision.disabled = not enabled

func _build_hoop() -> Node3D:
	var root := Node3D.new()
	root.name = "BasketballHoop"

	var dark := _material(Color(0.14, 0.16, 0.2), 0.42)
	var orange := _material(Color(1.0, 0.27, 0.04), 0.3, Color(1.0, 0.12, 0.01))
	var board := _material(Color(0.93, 0.97, 1.0, 0.9), 0.22)
	board.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var net := _material(Color(0.96, 0.98, 1.0, 0.55), 0.65)
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_add_box(root, "Pole", Vector3(0.18, 3.15, 0.18), Vector3(0.0, 1.55, 0.72), dark)
	_add_box(root, "Base", Vector3(1.15, 0.16, 1.05), Vector3(0.0, 0.08, 0.72), dark)
	_add_box(root, "Backboard", Vector3(2.25, 1.35, 0.12), Vector3(0.0, 3.55, 0.55), board)
	_add_box(root, "BoardTargetTop", Vector3(0.72, 0.06, 0.03), Vector3(0.0, 3.72, 0.47), orange)
	_add_box(root, "BoardTargetBottom", Vector3(0.72, 0.06, 0.03), Vector3(0.0, 3.24, 0.47), orange)
	_add_box(root, "BoardTargetLeft", Vector3(0.06, 0.54, 0.03), Vector3(-0.33, 3.48, 0.47), orange)
	_add_box(root, "BoardTargetRight", Vector3(0.06, 0.54, 0.03), Vector3(0.33, 3.48, 0.47), orange)

	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.57
	torus.rings = 32
	torus.ring_segments = 12
	rim.mesh = torus
	rim.position = Vector3(0.0, 3.05, 0.0)
	rim.material_override = orange
	root.add_child(rim)

	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var strand := MeshInstance3D.new()
		strand.name = "NetStrand%d" % i
		var strand_mesh := CylinderMesh.new()
		strand_mesh.top_radius = 0.012
		strand_mesh.bottom_radius = 0.012
		strand_mesh.height = 0.9
		strand_mesh.radial_segments = 5
		strand.mesh = strand_mesh
		strand.position = Vector3(cos(angle) * 0.43, 2.62, sin(angle) * 0.43)
		strand.rotation.z = sin(angle) * 0.22
		strand.rotation.x = cos(angle) * 0.22
		strand.material_override = net
		root.add_child(strand)
	return root

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)

func _material(color: Color, roughness: float, emission: Color = Color(0.0, 0.0, 0.0, 1.0)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission.r > 0.0 or emission.g > 0.0 or emission.b > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.3
	return material
