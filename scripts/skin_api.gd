extends RefCounted
class_name SkinAPI

const DEFAULT_SKIN_ID := "irris"
const RESOURCE_SKIN_ROOT := "res://skins"
const USER_SKIN_ROOT := "user://skins"
const UPLOADED_IMAGE_SKIN_ID := "uploaded_image"
const UPLOADED_IMAGE_TEXTURE := "image.png"
const UPLOADED_IMAGE_SIZE := 512
const IMAGE_MODEL_SIZE := 1.35
const GENERATED_PREVIEW_SKIN_IDS := ["badge2", "default", "neon"]
const PREVIEW_TEXTURE_SIZE := 256

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
	if ids.has(DEFAULT_SKIN_ID):
		ids.erase(DEFAULT_SKIN_ID)
		ids.push_front(DEFAULT_SKIN_ID)
	return ids

static func get_skin_display_name(skin_id: String) -> String:
	var requested_id := skin_id.strip_edges()
	if requested_id.is_empty():
		requested_id = DEFAULT_SKIN_ID
	var manifest := _load_skin_manifest(requested_id)
	var display_name := String(manifest.get("name", "")).strip_edges()
	return display_name if not display_name.is_empty() else requested_id

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
	if raw.has("collision_shape"):
		normalized["collision_shape"] = String(raw.get("collision_shape", "capsule"))
	if raw.has("collision_size"):
		normalized["collision_size"] = _vector3_from_any(raw.get("collision_size", null), Vector3(0.7, 1.2, 0.5))

	normalized["body_texture"] = String(raw.get("body_texture", ""))
	normalized["marker_texture"] = String(raw.get("marker_texture", ""))
	normalized["preview_texture"] = String(raw.get("preview_texture", ""))
	normalized["model_scene"] = String(raw.get("model_scene", ""))
	normalized["model_scale"] = maxf(0.01, float(raw.get("model_scale", 1.0)))
	normalized["visual_type"] = String(raw.get("visual_type", ""))
	normalized["hide_marker"] = bool(raw.get("hide_marker", false))
	normalized["image_size"] = maxf(0.1, float(raw.get("image_size", IMAGE_MODEL_SIZE)))
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
	var requested_id := skin_id.strip_edges()
	if requested_id.is_empty():
		requested_id = DEFAULT_SKIN_ID

	var safe_role := role.strip_edges().to_lower()
	if safe_role.is_empty():
		safe_role = "runner"

	var manifest := _load_skin_manifest(requested_id)
	if manifest.is_empty():
		return _create_generated_skin_preview_texture(requested_id, safe_role)

	if GENERATED_PREVIEW_SKIN_IDS.has(requested_id):
		var generated_builtin := _create_generated_skin_preview_texture(requested_id, safe_role)
		if generated_builtin != null:
			return generated_builtin

	var role_data := _extract_role_data(manifest, safe_role)
	var preview_rel := String(role_data.get("preview_texture", manifest.get("preview_texture", "")))
	if not preview_rel.is_empty():
		var preview_tex := load_skin_texture(requested_id, preview_rel)
		if preview_tex != null:
			return preview_tex

	var marker_rel := String(role_data.get("marker_texture", ""))
	if not marker_rel.is_empty():
		var marker_tex := load_skin_texture(requested_id, marker_rel)
		if marker_tex != null:
			return marker_tex

	var body_rel := String(role_data.get("body_texture", ""))
	if not body_rel.is_empty():
		var body_tex := load_skin_texture(requested_id, body_rel)
		if body_tex != null:
			return body_tex
	return _create_generated_skin_preview_texture(requested_id, safe_role)

static func create_uploaded_image_skin(source_path: String) -> String:
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		return ""
	var square_size := mini(image.get_width(), image.get_height())
	if square_size <= 0:
		return ""
	var crop_x := int((image.get_width() - square_size) * 0.5)
	var crop_y := int((image.get_height() - square_size) * 0.5)
	var square_image := image.get_region(Rect2i(crop_x, crop_y, square_size, square_size))
	square_image.convert(Image.FORMAT_RGBA8)
	square_image.resize(UPLOADED_IMAGE_SIZE, UPLOADED_IMAGE_SIZE, Image.INTERPOLATE_LANCZOS)

	var skin_dir := "%s/%s" % [USER_SKIN_ROOT, UPLOADED_IMAGE_SKIN_ID]
	var absolute_skin_dir := ProjectSettings.globalize_path(skin_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_skin_dir) != OK:
		return ""
	if square_image.save_png("%s/%s" % [skin_dir, UPLOADED_IMAGE_TEXTURE]) != OK:
		return ""

	var manifest := {
		"name": "上传图片皮肤",
		"preview_texture": UPLOADED_IMAGE_TEXTURE,
		"roles": {
			"runner": _uploaded_image_role_manifest("runner"),
			"tagger": _uploaded_image_role_manifest("tagger")
		}
	}
	var file := FileAccess.open("%s/skin.json" % skin_dir, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	return UPLOADED_IMAGE_SKIN_ID

static func _uploaded_image_role_manifest(role: String) -> Dictionary:
	var is_tagger := role == "tagger"
	return {
		"visual_type": "image_square",
		"body_texture": UPLOADED_IMAGE_TEXTURE,
		"preview_texture": UPLOADED_IMAGE_TEXTURE,
		"hide_marker": true,
		"image_size": IMAGE_MODEL_SIZE,
		"radius": 0.38 if is_tagger else 0.35,
		"height": 1.72,
		"collision_y": 0.86,
		"mesh_y": 1.08,
		"roughness": 0.88
	}

static func create_skin_visual_model(skin_id: String, skin: Dictionary) -> Node3D:
	var visual_type := String(skin.get("visual_type", ""))
	if visual_type == "image_square":
		return create_image_square_model(skin_id, skin)
	if visual_type == "chair_3d":
		return create_chair_model(skin)
	return null

static func create_image_square_model(skin_id: String, skin: Dictionary) -> Node3D:
	var texture := load_skin_texture(skin_id, String(skin.get("body_texture", "")))
	if texture == null:
		return null
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var size := maxf(0.1, float(skin.get("image_size", IMAGE_MODEL_SIZE)))
	quad.size = Vector2(size, size)
	mesh_instance.mesh = quad
	mesh_instance.position.y = float(skin.get("mesh_y", 1.08))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = texture
	mat.roughness = clampf(float(skin.get("roughness", 0.88)), 0.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	return mesh_instance

static func create_chair_model(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var roughness := clampf(float(skin.get("roughness", 0.82)), 0.0, 1.0)
	var wood := skin.get("body_color", Color(0.58, 0.32, 0.32)) as Color
	var dark := skin.get("marker_color", _shade_color(wood, -0.22)) as Color
	var light := _shade_color(wood, 0.16)

	root.add_child(_create_chair_box("Seat", Vector3(0.0, 0.58, 0.0), Vector3(0.86, 0.14, 0.76), wood, roughness))
	root.add_child(_create_chair_box("SeatFrontLip", Vector3(0.0, 0.51, -0.39), Vector3(0.9, 0.12, 0.08), dark, roughness))
	root.add_child(_create_chair_box("SeatHighlight", Vector3(0.0, 0.66, -0.08), Vector3(0.72, 0.03, 0.48), light, roughness))

	root.add_child(_create_chair_box("BackLeftPost", Vector3(-0.34, 1.03, 0.31), Vector3(0.12, 0.9, 0.12), dark, roughness))
	root.add_child(_create_chair_box("BackRightPost", Vector3(0.34, 1.03, 0.31), Vector3(0.12, 0.9, 0.12), dark, roughness))
	root.add_child(_create_chair_box("BackTopRail", Vector3(0.0, 1.43, 0.33), Vector3(0.9, 0.18, 0.14), wood, roughness))
	root.add_child(_create_chair_box("BackLowerRail", Vector3(0.0, 1.14, 0.33), Vector3(0.74, 0.14, 0.12), _shade_color(wood, 0.08), roughness))

	var leg_size := Vector3(0.12, 0.72, 0.12)
	root.add_child(_create_chair_box("FrontLeftLeg", Vector3(-0.34, 0.23, -0.28), leg_size, dark, roughness, Vector3(0.0, 0.0, deg_to_rad(-8.0))))
	root.add_child(_create_chair_box("FrontRightLeg", Vector3(0.34, 0.23, -0.28), leg_size, dark, roughness, Vector3(0.0, 0.0, deg_to_rad(8.0))))
	root.add_child(_create_chair_box("BackLeftLeg", Vector3(-0.34, 0.23, 0.28), leg_size, wood, roughness, Vector3(deg_to_rad(7.0), 0.0, deg_to_rad(-5.0))))
	root.add_child(_create_chair_box("BackRightLeg", Vector3(0.34, 0.23, 0.28), leg_size, wood, roughness, Vector3(deg_to_rad(7.0), 0.0, deg_to_rad(5.0))))
	return root

static func _create_chair_box(part_name: String, position: Vector3, size: Vector3, color: Color, roughness: float, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mesh_instance.material_override = mat
	return mesh_instance

static func _create_generated_skin_preview_texture(skin_id: String, role: String) -> Texture2D:
	var skin := load_role_skin(role, skin_id)
	if skin.is_empty():
		return null

	var image := Image.create(PREVIEW_TEXTURE_SIZE, PREVIEW_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var model_scene := String(skin.get("model_scene", ""))
	if model_scene.is_empty():
		_draw_capsule_actor_preview(image, skin, role)
	else:
		_draw_badge_model_preview(image)
	return ImageTexture.create_from_image(image)

static func _draw_capsule_actor_preview(image: Image, skin: Dictionary, role: String) -> void:
	var safe_role := role.strip_edges().to_lower()
	var default_radius := 0.38 if safe_role == "tagger" else 0.35
	var default_height := 1.82 if safe_role == "tagger" else 1.72
	var radius := maxf(0.1, float(skin.get("radius", default_radius)))
	var height := maxf(0.2, float(skin.get("height", default_height)))
	var visual_radius := clampf(46.0 * radius / default_radius, 36.0, 58.0)
	var visual_height := clampf(152.0 * height / default_height, 132.0, 178.0)
	var top := 128.0 - visual_height * 0.5 + 8.0
	var bottom := top + visual_height
	var center_x := 128.0
	var body_color := skin.get("body_color", Color(0.15, 0.5, 1.0)) as Color
	var marker_color := skin.get("marker_color", Color(0.95, 0.98, 1.0)) as Color
	var border_color := _shade_color(body_color, -0.34)

	_draw_ellipse(image, Vector2(center_x, bottom + 12.0), Vector2(54.0, 12.0), Color(0.05, 0.07, 0.11, 0.24))
	_draw_capsule_shape(image, center_x + 5.0, top + 6.0, bottom + 6.0, visual_radius, Color(0.06, 0.07, 0.1, 0.18), false)
	_draw_capsule_shape(image, center_x, top - 4.0, bottom + 4.0, visual_radius + 5.0, border_color, false)
	_draw_capsule_shape(image, center_x, top, bottom, visual_radius, body_color, true)

	var marker_width := clampf(72.0 * visual_radius / 46.0, 58.0, 88.0)
	var marker_height := 22.0
	var marker_y := top + visual_height * 0.48
	_draw_box(image, Rect2(center_x - marker_width * 0.5 - 4.0, marker_y - marker_height * 0.5 - 4.0, marker_width + 8.0, marker_height + 8.0), _shade_color(marker_color, -0.38))
	_draw_box(image, Rect2(center_x - marker_width * 0.5, marker_y - marker_height * 0.5, marker_width, marker_height), marker_color)
	_draw_box(image, Rect2(center_x - marker_width * 0.42, marker_y - marker_height * 0.36, marker_width * 0.42, marker_height * 0.22), Color(1.0, 1.0, 1.0, 0.32))
	_draw_ellipse(image, Vector2(center_x - visual_radius * 0.28, top + visual_height * 0.22), Vector2(visual_radius * 0.18, visual_height * 0.11), Color(1.0, 1.0, 1.0, 0.22))

static func _draw_badge_model_preview(image: Image) -> void:
	var center := Vector2(128.0, 126.0)
	var silver := Color(0.86, 0.88, 0.92, 1.0)
	var highlight := Color(0.97, 0.98, 1.0, 1.0)
	_draw_ellipse(image, Vector2(center.x + 6.0, center.y + 92.0), Vector2(70.0, 14.0), Color(0.05, 0.07, 0.11, 0.22))
	_draw_ellipse(image, center + Vector2(7.0, 8.0), Vector2(82.0, 82.0), Color(0.04, 0.05, 0.07, 0.2))
	_draw_ellipse(image, center, Vector2(86.0, 86.0), Color(0.42, 0.44, 0.5, 1.0))
	_draw_ellipse(image, center, Vector2(80.0, 80.0), _shade_color(silver, -0.1))
	_draw_ellipse(image, center + Vector2(-5.0, -6.0), Vector2(68.0, 68.0), silver)
	_draw_ellipse(image, center + Vector2(-16.0, -22.0), Vector2(28.0, 18.0), Color(1.0, 1.0, 1.0, 0.26))
	_draw_ellipse(image, center, Vector2(45.0, 45.0), Color(0.58, 0.6, 0.66, 1.0))
	_draw_ellipse(image, center + Vector2(-2.0, -2.0), Vector2(37.0, 37.0), highlight)
	_draw_ellipse(image, center + Vector2(-10.0, -12.0), Vector2(15.0, 10.0), Color(1.0, 1.0, 1.0, 0.34))
	_draw_ellipse(image, center + Vector2(19.0, 20.0), Vector2(8.0, 8.0), Color(0.7, 0.72, 0.78, 0.32))

static func _draw_capsule_shape(image: Image, center_x: float, top: float, bottom: float, radius: float, color: Color, shaded: bool) -> void:
	var x0 := clampi(int(floor(center_x - radius - 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var x1 := clampi(int(ceil(center_x + radius + 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var y0 := clampi(int(floor(top - 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var y1 := clampi(int(ceil(bottom + 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var top_center_y := top + radius
	var bottom_center_y := bottom - radius
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var edge_distance := 0.0
			if float(y) < top_center_y:
				edge_distance = Vector2(float(x) - center_x, float(y) - top_center_y).length() - radius
			elif float(y) > bottom_center_y:
				edge_distance = Vector2(float(x) - center_x, float(y) - bottom_center_y).length() - radius
			else:
				edge_distance = absf(float(x) - center_x) - radius
			var alpha := clampf(0.75 - edge_distance, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var final_color := color
			if shaded:
				var nx := (float(x) - center_x) / radius
				var ny := (float(y) - top) / maxf(bottom - top, 1.0)
				var shade := clampf(0.22 - nx * 0.18 - ny * 0.1, -0.18, 0.28)
				final_color = _shade_color(color, shade)
			final_color.a *= alpha
			_blend_pixel(image, x, y, final_color)

static func _draw_ellipse(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	var x0 := clampi(int(floor(center.x - radius.x - 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var x1 := clampi(int(ceil(center.x + radius.x + 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var y0 := clampi(int(floor(center.y - radius.y - 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var y1 := clampi(int(ceil(center.y + radius.y + 2.0)), 0, PREVIEW_TEXTURE_SIZE - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var px := (float(x) - center.x) / maxf(radius.x, 1.0)
			var py := (float(y) - center.y) / maxf(radius.y, 1.0)
			var d := px * px + py * py
			var alpha := clampf((1.055 - d) / 0.055, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var final_color := color
			final_color.a *= alpha
			_blend_pixel(image, x, y, final_color)

static func _draw_box(image: Image, rect: Rect2, color: Color) -> void:
	var x0 := clampi(int(floor(rect.position.x)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var x1 := clampi(int(ceil(rect.position.x + rect.size.x)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var y0 := clampi(int(floor(rect.position.y)), 0, PREVIEW_TEXTURE_SIZE - 1)
	var y1 := clampi(int(ceil(rect.position.y + rect.size.y)), 0, PREVIEW_TEXTURE_SIZE - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_blend_pixel(image, x, y, color)

static func _blend_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or x >= PREVIEW_TEXTURE_SIZE or y < 0 or y >= PREVIEW_TEXTURE_SIZE:
		return
	var src_a := clampf(color.a, 0.0, 1.0)
	if src_a <= 0.0:
		return
	var dst := image.get_pixel(x, y)
	var out_a := src_a + dst.a * (1.0 - src_a)
	if out_a <= 0.0:
		image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
		return
	var out := Color(0.0, 0.0, 0.0, out_a)
	out.r = (color.r * src_a + dst.r * dst.a * (1.0 - src_a)) / out_a
	out.g = (color.g * src_a + dst.g * dst.a * (1.0 - src_a)) / out_a
	out.b = (color.b * src_a + dst.b * dst.a * (1.0 - src_a)) / out_a
	image.set_pixel(x, y, out)

static func _shade_color(color: Color, amount: float) -> Color:
	var alpha := color.a
	var target := Color(1.0, 1.0, 1.0, alpha) if amount >= 0.0 else Color(0.0, 0.0, 0.0, alpha)
	var result := color.lerp(target, clampf(absf(amount), 0.0, 1.0))
	result.a = alpha
	return result

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

static func _vector3_from_any(value, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array:
		var arr := value as Array
		if arr.size() >= 3:
			return Vector3(maxf(0.05, float(arr[0])), maxf(0.05, float(arr[1])), maxf(0.05, float(arr[2])))
	if value is Dictionary:
		var dict := value as Dictionary
		return Vector3(maxf(0.05, float(dict.get("x", fallback.x))), maxf(0.05, float(dict.get("y", fallback.y))), maxf(0.05, float(dict.get("z", fallback.z))))
	return fallback
