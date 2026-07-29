extends RefCounted

const FlickerScript = preload("res://scripts/light_flicker.gd")

const DEFAULT_RUNNER_SPAWN := Vector3(-23.0, 0.12, 22.0)
const DEFAULT_TAGGER_SPAWN := Vector3(23.0, 0.12, -22.0)

static func load_map(parent: Node3D, map_path: String) -> Dictionary:
	var result := {
		"ok": false,
		"name": map_path.get_file(),
		"map_root": null,
		"runner_spawn": DEFAULT_RUNNER_SPAWN,
		"tagger_spawn": DEFAULT_TAGGER_SPAWN,
		"environment": {},
		"gameplay": {},
		"format_version": 1,
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

	var context := _build_context(data, map_path)
	for raw_object in raw_objects:
		if typeof(raw_object) == TYPE_DICTIONARY:
			_add_object(root, raw_object, context)

	var raw_lights = data.get("lights", [])
	if typeof(raw_lights) == TYPE_ARRAY:
		for raw_light in raw_lights:
			if typeof(raw_light) == TYPE_DICTIONARY:
				_add_light(root, raw_light, context)

	var raw_decals = data.get("decals", [])
	if typeof(raw_decals) == TYPE_ARRAY:
		for raw_decal in raw_decals:
			if typeof(raw_decal) == TYPE_DICTIONARY:
				_add_decal(root, raw_decal, context)

	result["ok"] = true
	result["name"] = String(data.get("name", root.name))
	result["map_root"] = root
	result["runner_spawn"] = _to_vector3(data.get("runner_spawn", DEFAULT_RUNNER_SPAWN), DEFAULT_RUNNER_SPAWN)
	result["tagger_spawn"] = _to_vector3(data.get("tagger_spawn", DEFAULT_TAGGER_SPAWN), DEFAULT_TAGGER_SPAWN)
	result["environment"] = data["environment"] if data.has("environment") and typeof(data["environment"]) == TYPE_DICTIONARY else {}
	result["gameplay"] = data["gameplay"] if data.has("gameplay") and typeof(data["gameplay"]) == TYPE_DICTIONARY else {}
	result["format_version"] = int(data.get("format_version", 1))
	return result

static func _build_context(data: Dictionary, map_path: String) -> Dictionary:
	return {
		"map_path": map_path,
		"materials": data["materials"] if data.has("materials") and typeof(data["materials"]) == TYPE_DICTIONARY else {},
		"prefabs": data["prefabs"] if data.has("prefabs") and typeof(data["prefabs"]) == TYPE_DICTIONARY else {}
	}

static func _add_object(root: Node3D, data: Dictionary, context: Dictionary) -> void:
	var object_type := String(data.get("type", "box")).to_lower()
	match object_type:
		"box":
			_add_box(root, data, context)
		"sphere":
			_add_sphere(root, data, context)
		"cylinder":
			_add_cylinder(root, data, context)
		"csg_cylinder":
			_add_csg_cylinder(root, data, context)
		"capsule":
			_add_capsule(root, data, context)
		"model", "scene", "mesh":
			_add_model(root, data, context)
		"prefab":
			_add_prefab(root, data, context)
		"light":
			_add_light(root, data, context)
		"decal":
			_add_decal(root, data, context)
		_:
			push_warning("未知地图物体类型：%s" % object_type)

static func _add_box(root: Node3D, data: Dictionary, context: Dictionary) -> StaticBody3D:
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
		mesh.material_override = _material_from_data(data, context, Color(0.4, 0.4, 0.4))
		body.add_child(mesh)
	return body

static func _add_sphere(root: Node3D, data: Dictionary, context: Dictionary) -> StaticBody3D:
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
		mesh.material_override = _material_from_data(data, context, Color(0.4, 0.4, 0.4))
		body.add_child(mesh)
	return body

static func _add_cylinder(root: Node3D, data: Dictionary, context: Dictionary) -> StaticBody3D:
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
		mesh.material_override = _material_from_data(data, context, Color(0.4, 0.4, 0.4))
		body.add_child(mesh)
	return body

static func _add_csg_cylinder(root: Node3D, data: Dictionary, context: Dictionary) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = String(data.get("name", "MapCSGCylinder"))
	cylinder.radius = float(data.get("radius", 1.0))
	cylinder.height = float(data.get("height", 2.0))
	cylinder.sides = maxi(8, int(data.get("sides", 64)))
	cylinder.material = _material_from_data(data, context, Color(0.4, 0.4, 0.4))
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

static func _add_capsule(root: Node3D, data: Dictionary, context: Dictionary) -> StaticBody3D:
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
		mesh.material_override = _material_from_data(data, context, Color(0.4, 0.4, 0.4))
		body.add_child(mesh)
	return body

static func _add_model(root: Node3D, data: Dictionary, context: Dictionary) -> StaticBody3D:
	var body := _create_body(root, data)
	var raw_path := String(data.get("path", ""))
	if raw_path.is_empty():
		push_warning("模型物体缺少 path：%s" % body.name)
		return body

	var map_path := String(context.get("map_path", ""))
	var model_path := _resolve_asset_path(map_path, raw_path)
	var instance := _load_model_node(model_path)
	if instance == null:
		push_warning("模型加载失败：%s" % model_path)
		return body

	instance.name = "Visual"
	instance.visible = _to_bool(data.get("visible", true), true)
	body.add_child(instance)
	if data.has("material") or data.has("material_id") or data.has("texture") or data.has("albedo_texture"):
		_apply_material_to_meshes(instance, _material_from_data(data, context, Color.WHITE))
	var material_overrides: Dictionary = data["material_overrides"] if data.has("material_overrides") and typeof(data["material_overrides"]) == TYPE_DICTIONARY else {}
	var node_material_overrides: Dictionary = data["node_material_overrides"] if data.has("node_material_overrides") and typeof(data["node_material_overrides"]) == TYPE_DICTIONARY else {}
	if not material_overrides.is_empty() or not node_material_overrides.is_empty():
		_apply_material_overrides_to_meshes(instance, material_overrides, node_material_overrides, context)

	var mode := _collision_mode(data, "mesh")
	if mode == "none":
		return body
	if mode == "box":
		_add_collision_shape(body, {"type": "box", "size": data.get("size", Vector3.ONE)})
		return body
	if mode == "proxy" or data.has("collision_shapes"):
		var proxy_count := _add_collision_shapes(body, data.get("collision_shapes", []))
		if proxy_count == 0:
			push_warning("模型代理碰撞为空：%s" % model_path)
		return body

	var collision_count := _add_mesh_collisions(body, instance, Transform3D.IDENTITY)
	if collision_count == 0:
		push_warning("模型没有可用网格碰撞：%s" % model_path)
	return body

static func _add_prefab(root: Node3D, data: Dictionary, context: Dictionary) -> void:
	var prefab_id := String(data.get("prefab", data.get("id", "")))
	var prefabs: Dictionary = context.get("prefabs", {})
	if prefab_id.is_empty() or not prefabs.has(prefab_id) or typeof(prefabs[prefab_id]) != TYPE_DICTIONARY:
		push_warning("未知 prefab：%s" % prefab_id)
		return
	var merged: Dictionary = (prefabs[prefab_id] as Dictionary).duplicate(true)
	if not merged.has("type"):
		merged["type"] = "model" if merged.has("path") else "box"
	for key in data.keys():
		if String(key) == "type" or String(key) == "prefab":
			continue
		merged[key] = data[key]
	_add_object(root, merged, context)

static func _add_light(root: Node3D, data: Dictionary, context: Dictionary) -> Light3D:
	var light_type := String(data.get("light_type", data.get("kind", "omni"))).to_lower()
	var light: Light3D
	match light_type:
		"directional", "sun":
			light = DirectionalLight3D.new()
		"spot":
			var spot := SpotLight3D.new()
			spot.spot_range = float(data.get("range", 18.0))
			spot.spot_angle = float(data.get("spot_angle", 42.0))
			light = spot
		_:
			var omni := OmniLight3D.new()
			omni.omni_range = float(data.get("range", 14.0))
			light = omni
	light.name = String(data.get("name", "MapLight"))
	light.light_color = _to_color(data.get("color", Color.WHITE), Color.WHITE)
	light.light_energy = float(data.get("energy", 2.5))
	light.shadow_enabled = _to_bool(data.get("shadow", false), false)
	_apply_transform(light, data)
	root.add_child(light)
	_apply_light_flicker(light, data)
	return light

static func _apply_light_flicker(light: Light3D, data: Dictionary) -> void:
	if not data.has("flicker"):
		return
	var raw = data["flicker"]
	var cfg := {}
	if typeof(raw) == TYPE_DICTIONARY:
		cfg = raw
	elif not _to_bool(raw, false):
		return
	var node := FlickerScript.new()
	node.name = "Flicker"
	node.target = light
	node.base_energy = light.light_energy
	node.mode = String(cfg.get("mode", "flicker")).to_lower()
	node.frequency = float(cfg.get("frequency", 9.0))
	node.min_energy = float(cfg.get("min", 0.12))
	node.max_energy = float(cfg.get("max", 1.0))
	# 关联灯座自发光：让灯座的暖黄自发光与频闪同步明灭
	if data.has("emissive_fixture"):
		var mat := _find_emissive_material(light.get_parent(), String(data["emissive_fixture"]))
		if mat != null:
			node.emissive_material = mat
			node.emission_base = float(data.get("fixture_emission_base", mat.emission_energy_multiplier))
	light.add_child(node)

static func _find_emissive_material(parent: Node, fixture_name: String) -> StandardMaterial3D:
	if parent == null:
		return null
	var fixture := parent.get_node_or_null(NodePath(fixture_name))
	if fixture == null:
		return null
	return _first_mesh_material(fixture)

static func _first_mesh_material(node: Node) -> StandardMaterial3D:
	if node is MeshInstance3D:
		var m = (node as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			return m as StandardMaterial3D
	for child in node.get_children():
		var found := _first_mesh_material(child)
		if found != null:
			return found
	return null

static func _add_decal(root: Node3D, data: Dictionary, context: Dictionary) -> Decal:
	var decal := Decal.new()
	decal.name = String(data.get("name", "MapDecal"))
	decal.size = _to_vector3(data.get("size", Vector3(2.0, 2.0, 0.4)), Vector3(2.0, 2.0, 0.4))
	var map_path := String(context.get("map_path", ""))
	var texture_path := String(data.get("texture", data.get("albedo_texture", "")))
	var texture := _load_texture(_resolve_asset_path(map_path, texture_path))
	if texture != null:
		decal.texture_albedo = texture
	var normal_texture := _load_texture(_resolve_asset_path(map_path, String(data.get("normal_texture", ""))))
	if normal_texture != null:
		decal.texture_normal = normal_texture
	var orm_texture := _load_texture(_resolve_asset_path(map_path, String(data.get("orm_texture", ""))))
	if orm_texture != null:
		decal.texture_orm = orm_texture
	decal.albedo_mix = float(data.get("albedo_mix", 1.0))
	decal.modulate = _to_color(data.get("color", Color.WHITE), Color.WHITE)
	_apply_transform(decal, data)
	root.add_child(decal)
	return decal

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

static func _add_collision_shapes(body: StaticBody3D, raw_shapes) -> int:
	if typeof(raw_shapes) != TYPE_ARRAY:
		return 0
	var count := 0
	for raw_shape in raw_shapes:
		if typeof(raw_shape) == TYPE_DICTIONARY and _add_collision_shape(body, raw_shape):
			count += 1
	return count

static func _add_collision_shape(parent: Node3D, data: Dictionary) -> bool:
	var shape_type := String(data.get("type", "box")).to_lower()
	var shape: Shape3D
	match shape_type:
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = float(data.get("radius", 1.0))
			shape = sphere
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(data.get("radius", 1.0))
			cylinder.height = float(data.get("height", 2.0))
			shape = cylinder
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = float(data.get("radius", 0.8))
			capsule.height = float(data.get("height", 2.0))
			shape = capsule
		_:
			var box := BoxShape3D.new()
			box.size = _to_vector3(data.get("size", Vector3.ONE), Vector3.ONE)
			shape = box
	if shape == null:
		return false
	var collision := CollisionShape3D.new()
	collision.name = String(data.get("name", "CollisionProxy"))
	collision.shape = shape
	_apply_transform(collision, data)
	parent.add_child(collision)
	return true

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
	if raw_path.is_empty():
		return ""
	if raw_path.begins_with("res://") or raw_path.begins_with("user://") or raw_path.begins_with("/") or raw_path.find(":/") != -1 or raw_path.find(":\\") != -1:
		return raw_path
	return map_path.get_base_dir().path_join(raw_path)

static func _apply_material_to_meshes(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material_to_meshes(child, material)

static func _apply_material_overrides_to_meshes(node: Node, material_overrides: Dictionary, node_overrides: Dictionary, context: Dictionary) -> void:
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
					var override_material := _material_from_data(material_overrides[material_name], context, Color.WHITE)
					override_material.resource_name = material_name
					mesh_instance.set_surface_override_material(surface, override_material)
					matched_surface = true
		if not matched_surface:
			var node_data := _find_node_material_override(mesh_instance.name, node_overrides)
			if not node_data.is_empty():
				mesh_instance.material_override = _material_from_data(node_data, context, Color.WHITE)
	for child in node.get_children():
		_apply_material_overrides_to_meshes(child, material_overrides, node_overrides, context)

static func _find_node_material_override(node_name: String, overrides: Dictionary) -> Dictionary:
	for key in overrides.keys():
		var prefix := String(key)
		if node_name.begins_with(prefix) and typeof(overrides[key]) == TYPE_DICTIONARY:
			return overrides[key]
	return {}

static func _material_from_data(data: Dictionary, context: Dictionary, default_color: Color) -> StandardMaterial3D:
	var material_data := {}
	var materials: Dictionary = context.get("materials", {})
	var material_id := String(data.get("material_id", ""))
	if not material_id.is_empty() and materials.has(material_id) and typeof(materials[material_id]) == TYPE_DICTIONARY:
		material_data = (materials[material_id] as Dictionary).duplicate(true)
	if data.has("material") and typeof(data["material"]) == TYPE_DICTIONARY:
		for key in (data["material"] as Dictionary).keys():
			material_data[key] = data["material"][key]
	for key in ["color", "texture", "albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "emission", "emission_texture", "roughness", "metallic", "uv_scale", "uv_offset"]:
		if data.has(key) and not material_data.has(key):
			material_data[key] = data[key]

	var map_path := String(context.get("map_path", ""))
	var color := _to_color(material_data.get("color", data.get("color", default_color)), default_color)
	var mat := _material(color)
	mat.roughness = float(material_data.get("roughness", 0.82))
	mat.metallic = float(material_data.get("metallic", 0.0))
	var albedo_path := String(material_data.get("albedo_texture", material_data.get("texture", "")))
	var albedo_texture := _load_texture(_resolve_asset_path(map_path, albedo_path))
	if albedo_texture != null:
		mat.albedo_texture = albedo_texture
	var normal_texture := _load_texture(_resolve_asset_path(map_path, String(material_data.get("normal_texture", ""))))
	if normal_texture != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_texture
	var orm_texture := _load_texture(_resolve_asset_path(map_path, String(material_data.get("orm_texture", ""))))
	if orm_texture != null:
		mat.set("orm_texture", orm_texture)
	var roughness_texture := _load_texture(_resolve_asset_path(map_path, String(material_data.get("roughness_texture", ""))))
	if roughness_texture != null:
		mat.set("roughness_texture", roughness_texture)
	var metallic_texture := _load_texture(_resolve_asset_path(map_path, String(material_data.get("metallic_texture", ""))))
	if metallic_texture != null:
		mat.set("metallic_texture", metallic_texture)
	var emission_color := _to_color(material_data.get("emission", Color.BLACK), Color.BLACK)
	if emission_color != Color.BLACK or material_data.has("emission_texture"):
		mat.emission_enabled = true
		mat.emission = emission_color
		mat.emission_energy_multiplier = float(material_data.get("emission_energy", 1.0))
		var emission_texture := _load_texture(_resolve_asset_path(map_path, String(material_data.get("emission_texture", ""))))
		if emission_texture != null:
			mat.emission_texture = emission_texture
	if material_data.has("uv_scale"):
		mat.uv1_scale = _to_vector3(material_data.get("uv_scale", [1.0, 1.0, 1.0]), Vector3.ONE)
	if material_data.has("uv_offset"):
		mat.uv1_offset = _to_vector3(material_data.get("uv_offset", [0.0, 0.0, 0.0]), Vector3.ZERO)
	return mat

static func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://") or path.begins_with("user://"):
		var resource := load(path)
		if resource is Texture2D:
			return resource as Texture2D
		path = ProjectSettings.globalize_path(path)
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
