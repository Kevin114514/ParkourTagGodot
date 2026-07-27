extends RefCounted

const DEFAULT_RUNNER_SPAWN := Vector3(-23.0, 0.12, 22.0)
const DEFAULT_TAGGER_SPAWN := Vector3(23.0, 0.12, -22.0)

static func load_map(parent: Node3D, map_path: String) -> Dictionary:
	var result := {
		"ok": false,
		"name": map_path.get_file(),
		"map_root": null,
		"runner_spawn": DEFAULT_RUNNER_SPAWN,
		"tagger_spawn": DEFAULT_TAGGER_SPAWN,
		"error": ""
	}

	var file := FileAccess.open(map_path, FileAccess.READ)
	if file == null:
		result["error"] = "无法打开地图文件：%s" % map_path
		return result

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		result["error"] = "地图 JSON 格式错误：%s" % map_path
		return result

	var data: Dictionary = parsed
	var root := Node3D.new()
	root.name = String(data.get("name", map_path.get_file()))
	parent.add_child(root)

	var raw_objects = data.get("objects", [])
	if typeof(raw_objects) != TYPE_ARRAY:
		root.queue_free()
		result["error"] = "地图 objects 必须是数组：%s" % map_path
		return result

	for raw_object in raw_objects:
		if typeof(raw_object) == TYPE_DICTIONARY:
			_add_object(root, raw_object, map_path)

	result["ok"] = true
	result["name"] = String(data.get("name", root.name))
	result["map_root"] = root
	result["runner_spawn"] = _to_vector3(data.get("runner_spawn", DEFAULT_RUNNER_SPAWN), DEFAULT_RUNNER_SPAWN)
	result["tagger_spawn"] = _to_vector3(data.get("tagger_spawn", DEFAULT_TAGGER_SPAWN), DEFAULT_TAGGER_SPAWN)
	return result

static func _add_object(root: Node3D, data: Dictionary, map_path: String) -> void:
	var object_type := String(data.get("type", "box")).to_lower()
	match object_type:
		"box":
			_add_box(root, data, map_path)
		"sphere":
			_add_sphere(root, data, map_path)
		"cylinder":
			_add_cylinder(root, data, map_path)
		"csg_cylinder":
			_add_csg_cylinder(root, data, map_path)
		"capsule":
			_add_capsule(root, data, map_path)
		"model", "scene", "mesh":
			_add_model(root, data, map_path)
		_:
			push_warning("未知地图物体类型：%s" % object_type)

static func _add_box(root: Node3D, data: Dictionary, map_path: String) -> StaticBody3D:
	var size := _to_vector3(data.get("size", Vector3.ONE), Vector3.ONE)
	var body := _create_body(root, data)
	if _collision_mode(data, "shape") != "none":
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	if _to_bool(data.get("visible", true), true):
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = _material_from_data(data, map_path, Color(0.4, 0.4, 0.4))
		body.add_child(mesh)
	return body

static func _add_sphere(root: Node3D, data: Dictionary, map_path: String) -> StaticBody3D:
	var radius := float(data.get("radius", 1.0))
	var body := _create_body(root, data)
	if _collision_mode(data, "shape") != "none":
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		collision.shape = shape
		body.add_child(collision)
	if _to_bool(data.get("visible", true), true):
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh.mesh = sphere
		mesh.material_override = _material(_to_color(data.get("color", [0.4, 0.4, 0.4]), Color(0.4, 0.4, 0.4)))
		body.add_child(mesh)
	return body

static func _add_cylinder(root: Node3D, data: Dictionary, map_path: String) -> StaticBody3D:
	var radius := float(data.get("radius", 1.0))
	var height := float(data.get("height", 2.0))
	var body := _create_body(root, data)
	if _collision_mode(data, "shape") != "none":
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collision.shape = shape
		body.add_child(collision)
	if _to_bool(data.get("visible", true), true):
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = height
		mesh.mesh = cylinder
		mesh.material_override = _material_from_data(data, map_path, Color(0.4, 0.4, 0.4))
		body.add_child(mesh)
	return body

static func _add_csg_cylinder(root: Node3D, data: Dictionary, map_path: String) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = String(data.get("name", "MapCSGCylinder"))
	cylinder.radius = float(data.get("radius", 1.0))
	cylinder.height = float(data.get("height", 2.0))
	cylinder.sides = maxi(8, int(data.get("sides", 64)))
	cylinder.material = _material_from_data(data, map_path, Color(0.4, 0.4, 0.4))
	cylinder.visible = _to_bool(data.get("visible", true), true)
	cylinder.collision_layer = int(data.get("collision_layer", 1))
	cylinder.collision_mask = int(data.get("collision_mask", 1))
	_apply_transform(cylinder, data)
	root.add_child(cylinder)

	var raw_holes = data.get("holes", [])
	if typeof(raw_holes) == TYPE_ARRAY:
		for raw_hole in raw_holes:
			if typeof(raw_hole) != TYPE_DICTIONARY:
				continue
			var hole_data: Dictionary = raw_hole
			var hole := CSGBox3D.new()
			hole.name = String(hole_data.get("name", "SubtractionHole"))
			hole.size = _to_vector3(hole_data.get("size", Vector3.ONE), Vector3.ONE)
			hole.operation = CSGShape3D.OPERATION_SUBTRACTION
			hole.material = cylinder.material
			_apply_transform(hole, hole_data)
			cylinder.add_child(hole)

	cylinder.use_collision = _collision_mode(data, "shape") != "none"
	return cylinder

static func _add_capsule(root: Node3D, data: Dictionary, map_path: String) -> StaticBody3D:
	var radius := float(data.get("radius", 0.8))
	var height := float(data.get("height", 2.0))
	var body := _create_body(root, data)
	if _collision_mode(data, "shape") != "none":
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = radius
		shape.height = height
		collision.shape = shape
		body.add_child(collision)
	if _to_bool(data.get("visible", true), true):
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = radius
		capsule.height = height
		mesh.mesh = capsule
		mesh.material_override = _material_from_data(data, map_path, Color(0.4, 0.4, 0.4))
		body.add_child(mesh)
	return body

static func _add_model(root: Node3D, data: Dictionary, map_path: String) -> StaticBody3D:
	var body := _create_body(root, data)
	var raw_path := String(data.get("path", ""))
	if raw_path.is_empty():
		push_warning("模型物体缺少 path：%s" % body.name)
		return body

	var model_path := _resolve_asset_path(map_path, raw_path)
	var instance := _load_model_node(model_path)
	if instance == null:
		push_warning("模型加载失败：%s" % model_path)
		return body

	instance.name = "Visual"
	instance.visible = _to_bool(data.get("visible", true), true)
	body.add_child(instance)
	if data.has("material") or data.has("texture"):
		_apply_material_to_meshes(instance, _material_from_data(data, map_path, Color.WHITE))
	var material_overrides: Dictionary = data["material_overrides"] if data.has("material_overrides") and typeof(data["material_overrides"]) == TYPE_DICTIONARY else {}
	var node_material_overrides: Dictionary = data["node_material_overrides"] if data.has("node_material_overrides") and typeof(data["node_material_overrides"]) == TYPE_DICTIONARY else {}
	if not material_overrides.is_empty() or not node_material_overrides.is_empty():
		_apply_material_overrides_to_meshes(instance, material_overrides, node_material_overrides, map_path)

	var mode := _collision_mode(data, "mesh")
	if mode == "none":
		return body
	if mode == "box":
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _to_vector3(data.get("size", Vector3.ONE), Vector3.ONE)
		collision.shape = shape
		body.add_child(collision)
		return body

	var collision_count := _add_mesh_collisions(body, instance, Transform3D.IDENTITY)
	if collision_count == 0:
		push_warning("模型没有可用网格碰撞：%s" % model_path)
	return body

static func _create_body(root: Node3D, data: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = String(data.get("name", "MapObject"))
	body.collision_layer = int(data.get("collision_layer", 1))
	body.collision_mask = int(data.get("collision_mask", 1))
	_apply_transform(body, data)
	root.add_child(body)
	return body

static func _apply_transform(node: Node3D, data: Dictionary) -> void:
	node.position = _to_vector3(data.get("position", Vector3.ZERO), Vector3.ZERO)
	if data.has("rotation_degrees"):
		node.rotation_degrees = _to_vector3(data.get("rotation_degrees", Vector3.ZERO), Vector3.ZERO)
	elif data.has("rotation"):
		node.rotation = _to_vector3(data.get("rotation", Vector3.ZERO), Vector3.ZERO)
	node.scale = _to_vector3(data.get("scale", Vector3.ONE), Vector3.ONE)

static func _load_model_node(path: String) -> Node3D:
	var extension := path.get_extension().to_lower()
	if extension == "glb" or extension == "gltf":
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var error := gltf.append_from_file(path, state)
		if error == OK:
			var generated := gltf.generate_scene(state)
			return _ensure_node3d(generated)

	var resource := load(path)
	if resource is PackedScene:
		return _ensure_node3d((resource as PackedScene).instantiate())
	if resource is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = resource
		return mesh_instance
	return null

static func _ensure_node3d(node: Node) -> Node3D:
	if node == null:
		return null
	if node is Node3D:
		return node as Node3D
	var wrapper := Node3D.new()
	wrapper.add_child(node)
	return wrapper

static func _add_mesh_collisions(body: StaticBody3D, node: Node, parent_transform: Transform3D) -> int:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform

	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var faces := PackedVector3Array()
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var arrays := mesh_instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.size() > 0:
					for index in indices:
						if index >= 0 and index < vertices.size():
							faces.append(current_transform * vertices[index])
				else:
					for vertex in vertices:
						faces.append(current_transform * vertex)
			if faces.size() >= 3:
				var collision := CollisionShape3D.new()
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(faces)
				collision.shape = shape
				body.add_child(collision)
				count += 1

	for child in node.get_children():
		count += _add_mesh_collisions(body, child, current_transform)
	return count

static func _resolve_asset_path(map_path: String, raw_path: String) -> String:
	if raw_path.begins_with("res://") or raw_path.begins_with("user://") or raw_path.begins_with("/") or raw_path.find(":/") != -1 or raw_path.find(":\\") != -1:
		return raw_path
	return map_path.get_base_dir().path_join(raw_path)

static func _apply_material_to_meshes(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material_to_meshes(child, material)

static func _apply_material_overrides_to_meshes(node: Node, material_overrides: Dictionary, node_overrides: Dictionary, map_path: String) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var matched_surface := false
		if mesh_instance.mesh != null:
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var surface_material := mesh_instance.mesh.surface_get_material(surface)
				if surface_material == null:
					continue
				var material_name := surface_material.resource_name
				if material_overrides.has(material_name) and typeof(material_overrides[material_name]) == TYPE_DICTIONARY:
					var override_material := _material_from_data(material_overrides[material_name], map_path, Color.WHITE)
					override_material.resource_name = material_name
					mesh_instance.set_surface_override_material(surface, override_material)
					matched_surface = true
		if not matched_surface:
			var node_data := _find_node_material_override(mesh_instance.name, node_overrides)
			if not node_data.is_empty():
				mesh_instance.material_override = _material_from_data(node_data, map_path, Color.WHITE)
	for child in node.get_children():
		_apply_material_overrides_to_meshes(child, material_overrides, node_overrides, map_path)

static func _find_node_material_override(node_name: String, overrides: Dictionary) -> Dictionary:
	for key in overrides.keys():
		var prefix := String(key)
		if node_name.begins_with(prefix) and typeof(overrides[key]) == TYPE_DICTIONARY:
			return overrides[key]
	return {}

static func _material_from_data(data: Dictionary, map_path: String, default_color: Color) -> StandardMaterial3D:
	var material_data := data
	if data.has("material") and typeof(data["material"]) == TYPE_DICTIONARY:
		material_data = data["material"]
	var color := _to_color(material_data.get("color", data.get("color", default_color)), default_color)
	var mat := _material(color)
	mat.roughness = float(material_data.get("roughness", 0.82))
	mat.metallic = float(material_data.get("metallic", 0.0))
	if material_data.has("texture"):
		var texture_path := _resolve_asset_path(map_path, String(material_data.get("texture", "")))
		var texture := _load_texture(texture_path)
		if texture != null:
			mat.albedo_texture = texture
	if material_data.has("normal_texture"):
		var normal_path := _resolve_asset_path(map_path, String(material_data.get("normal_texture", "")))
		var normal_texture := _load_texture(normal_path)
		if normal_texture != null:
			mat.normal_enabled = true
			mat.normal_texture = normal_texture
	if material_data.has("uv_scale"):
		var uv_scale := _to_vector3(material_data.get("uv_scale", [1.0, 1.0, 1.0]), Vector3.ONE)
		mat.uv1_scale = uv_scale
	if material_data.has("uv_offset"):
		var uv_offset := _to_vector3(material_data.get("uv_offset", [0.0, 0.0, 0.0]), Vector3.ZERO)
		mat.uv1_offset = uv_offset
	return mat

static func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://") or path.begins_with("user://"):
		var resource := load(path)
		if resource is Texture2D:
			return resource as Texture2D
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)

static func _collision_mode(data: Dictionary, default_mode: String) -> String:
	var value = data.get("collision", default_mode)
	if typeof(value) == TYPE_BOOL:
		return default_mode if bool(value) else "none"
	return String(value).to_lower()

static func _to_vector3(value, default_value: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if typeof(value) == TYPE_DICTIONARY:
		return Vector3(float(value.get("x", default_value.x)), float(value.get("y", default_value.y)), float(value.get("z", default_value.z)))
	return default_value

static func _to_color(value, default_value: Color) -> Color:
	if value is Color:
		return value
	if typeof(value) == TYPE_ARRAY:
		if value.size() >= 4:
			return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		if value.size() >= 3:
			return Color(float(value[0]), float(value[1]), float(value[2]))
	if typeof(value) == TYPE_STRING:
		return Color(value)
	return default_value

static func _to_bool(value, default_value: bool) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	if typeof(value) == TYPE_STRING:
		var text := String(value).to_lower()
		if text == "true" or text == "yes" or text == "1":
			return true
		if text == "false" or text == "no" or text == "0":
			return false
	return default_value

static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
