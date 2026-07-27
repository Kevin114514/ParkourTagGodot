extends RefCounted
class_name SkinAPI

const DEFAULT_SKIN_ID := "default"
const RESOURCE_SKIN_ROOT := "res://skins"
const USER_SKIN_ROOT := "user://skins"

static func load_role_skin(role: String, skin_id: String = DEFAULT_SKIN_ID) -> Dictionary:
	var safe_role := role.strip_edges().to_lower()
	if safe_role.is_empty():
		safe_role = "runner"

	var requested := skin_id.strip_edges()
	if requested.is_empty():
		requested = DEFAULT_SKIN_ID

	for candidate_id in _candidate_skin_ids(requested):
		var loaded := _load_role_skin_from_id(safe_role, candidate_id)
		if not loaded.is_empty():
			return _merge_with_default(safe_role, loaded)

	return _merge_with_default(safe_role, {})

static func _candidate_skin_ids(requested: String) -> Array[String]:
	if requested == DEFAULT_SKIN_ID:
		return [DEFAULT_SKIN_ID]
	return [requested, DEFAULT_SKIN_ID]

static func _load_role_skin_from_id(role: String, skin_id: String) -> Dictionary:
	for root in _search_roots():
		var config_path := "%s/%s/skin.json" % [root, skin_id]
		if not FileAccess.file_exists(config_path):
			continue
		var raw := _read_json_dict(config_path)
		if raw.is_empty():
			continue
		var role_data := _extract_role_data(raw, role)
		if role_data.is_empty():
			continue
		return _normalize_skin(role_data)
	return {}

static func _search_roots() -> Array[String]:
	var roots: Array[String] = [RESOURCE_SKIN_ROOT, USER_SKIN_ROOT]
	var executable_dir := OS.get_executable_path().get_base_dir()
	if not executable_dir.is_empty():
		roots.append(executable_dir.path_join("skins"))
	return roots

static func list_available_skin_ids() -> Array[String]:
	var ids: Array[String] = []
	for root in _search_roots():
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				var config_path := "%s/%s/skin.json" % [root, entry]
				if FileAccess.file_exists(config_path) and not ids.has(entry):
					ids.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	if not ids.has(DEFAULT_SKIN_ID):
		ids.append(DEFAULT_SKIN_ID)
	ids.sort()
	return ids

static func _read_json_dict(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

static func _extract_role_data(raw: Dictionary, role: String) -> Dictionary:
	var roles_data = raw.get("roles", null)
	if roles_data is Dictionary and (roles_data as Dictionary).has(role):
		var entry = (roles_data as Dictionary).get(role)
		if entry is Dictionary:
			return entry

	var direct = raw.get(role, null)
	if direct is Dictionary:
		return direct

	return {}

static func _normalize_skin(raw: Dictionary) -> Dictionary:
	var normalized := {}
	normalized["body_color"] = _color_from_any(raw.get("body_color", null), Color(0.15, 0.5, 1.0))
	normalized["marker_color"] = _color_from_any(raw.get("marker_color", null), Color(0.95, 0.98, 1.0))
	normalized["roughness"] = clampf(float(raw.get("roughness", 0.72)), 0.0, 1.0)
	normalized["marker_roughness"] = clampf(float(raw.get("marker_roughness", normalized["roughness"])), 0.0, 1.0)

	if raw.has("radius"):
		normalized["radius"] = maxf(0.1, float(raw.get("radius", 0.35)))
	if raw.has("height"):
		normalized["height"] = maxf(0.2, float(raw.get("height", 1.72)))
	if raw.has("collision_y"):
		normalized["collision_y"] = float(raw.get("collision_y", 0.92))
	if raw.has("mesh_y"):
		normalized["mesh_y"] = float(raw.get("mesh_y", 0.92))
	if raw.has("marker_y"):
		normalized["marker_y"] = float(raw.get("marker_y", 1.34))
	if raw.has("marker_z"):
		normalized["marker_z"] = float(raw.get("marker_z", -0.34))

	normalized["body_texture"] = String(raw.get("body_texture", ""))
	normalized["marker_texture"] = String(raw.get("marker_texture", ""))
	normalized["preview_texture"] = String(raw.get("preview_texture", ""))
	normalized["model_scene"] = String(raw.get("model_scene", ""))
	normalized["model_scale"] = maxf(0.01, float(raw.get("model_scale", 1.0)))
	return normalized

static func _merge_with_default(role: String, skin: Dictionary) -> Dictionary:
	var defaults := _default_role_skin(role)
	for key in skin.keys():
		defaults[key] = skin[key]

	if float(defaults.get("radius", -1.0)) <= 0.0:
		defaults["radius"] = float(_default_role_skin(role).get("radius", 0.35))
	if float(defaults.get("height", -1.0)) <= 0.0:
		defaults["height"] = float(_default_role_skin(role).get("height", 1.72))
	return defaults

static func load_skin_texture(skin_id: String, relative_path: String) -> Texture2D:
	var rel := relative_path.strip_edges()
	if rel.is_empty():
		return null
	for root in _search_roots():
		var full_path := "%s/%s/%s" % [root, skin_id, rel]
		if ResourceLoader.exists(full_path):
			var tex := load(full_path)
			if tex is Texture2D:
				return tex
		var os_path := full_path.replace("res://", ProjectSettings.globalize_path("res://"))
		if FileAccess.file_exists(os_path):
			var image := Image.load_from_file(os_path)
			if image != null and not image.is_empty():
				return ImageTexture.create_from_image(image)
	return null

static func get_skin_preview_texture(skin_id: String, role: String = "runner") -> Texture2D:
	var manifest := _load_skin_manifest(skin_id)
	if manifest.is_empty():
		return null

	var role_data := _extract_role_data(manifest, role)
	var preview_rel := String(role_data.get("preview_texture", manifest.get("preview_texture", "")))
	if not preview_rel.is_empty():
		var preview_tex := load_skin_texture(skin_id, preview_rel)
		if preview_tex != null:
			return preview_tex

	var marker_rel := String(role_data.get("marker_texture", ""))
	if not marker_rel.is_empty():
		var marker_tex := load_skin_texture(skin_id, marker_rel)
		if marker_tex != null:
			return marker_tex

	var body_rel := String(role_data.get("body_texture", ""))
	if not body_rel.is_empty():
		return load_skin_texture(skin_id, body_rel)
	return null

static func load_skin_model_scene(skin_id: String, relative_path: String) -> PackedScene:
	var rel := relative_path.strip_edges()
	if rel.is_empty():
		return null
	for root in _search_roots():
		var full_path := "%s/%s/%s" % [root, skin_id, rel]
		if ResourceLoader.exists(full_path):
			var scene := load(full_path)
			if scene is PackedScene:
				return scene
	return null

static func instantiate_skin_model(skin_id: String, relative_path: String) -> Node3D:
	var rel := relative_path.strip_edges()
	if rel.is_empty():
		return null
	for root in _search_roots():
		var full_path := "%s/%s/%s" % [root, skin_id, rel]
		if not ResourceLoader.exists(full_path):
			continue
		var resource := load(full_path)
		if resource is PackedScene:
			var packed := resource as PackedScene
			var instance := packed.instantiate()
			if instance is Node3D:
				return instance as Node3D
		elif resource is Mesh:
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = resource as Mesh
			return mesh_instance
	return null

static func _load_skin_manifest(skin_id: String) -> Dictionary:
	for root in _search_roots():
		var config_path := "%s/%s/skin.json" % [root, skin_id]
		if not FileAccess.file_exists(config_path):
			continue
		var raw := _read_json_dict(config_path)
		if not raw.is_empty():
			return raw
	return {}

static func _default_role_skin(role: String) -> Dictionary:
	if role == "tagger":
		return {
			"body_color": Color(1.0, 0.24, 0.18),
			"marker_color": Color(1.0, 0.9, 0.15),
			"roughness": 0.68,
			"marker_roughness": 0.68,
			"radius": 0.38,
			"height": 1.82,
			"collision_y": 0.96,
			"mesh_y": 0.96,
			"marker_y": 1.42,
			"marker_z": -0.37
		}
	return {
		"body_color": Color(0.15, 0.5, 1.0),
		"marker_color": Color(0.95, 0.98, 1.0),
		"roughness": 0.74,
		"marker_roughness": 0.74,
		"radius": 0.35,
		"height": 1.72,
		"collision_y": 0.92,
		"mesh_y": 0.92,
		"marker_y": 1.34,
		"marker_z": -0.34
	}

static func _color_from_any(value, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		var parsed := Color.from_string(String(value), fallback)
		return parsed
	if value is Array:
		var arr := value as Array
		if arr.size() >= 3:
			var r := float(arr[0])
			var g := float(arr[1])
			var b := float(arr[2])
			var a := float(arr[3]) if arr.size() >= 4 else 1.0
			return Color(r, g, b, a)
	return fallback
