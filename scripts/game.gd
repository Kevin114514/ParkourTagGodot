extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const TaggerScript = preload("res://scripts/tagger.gd")
const RLPolicyTaggerScript = preload("res://scripts/rl_policy_tagger.gd")
const NetworkActorScript = preload("res://scripts/network_actor.gd")
const MapLoader = preload("res://scripts/map_loader.gd")
const SkinAPI = preload("res://scripts/skin_api.gd")
const PORT = 24591
const USE_RL_POLICY_TAGGER := true
const VOID_Y = -12.0
const DEFAULT_MAP_PATH = "res://maps/default_arena.json"
const USER_MAP_PATH = "user://maps/current_map.json"
const MULTIPLAYER_RESULT_DELAY := 3.0
const CATCH_RANGE := 1.6
const CATCH_AIM_DOT := 0.92
const AI_CATCH_COOLDOWN := 0.45
const CATCH_ORIGIN_TOLERANCE := 2.2
const OFFICIAL_MAPS = [
	{
		"name": "默认跑酷竞技场",
		"path": "res://maps/default_arena.json",
		"description": "综合地图：斜坡、挡板、低障碍、平台和平衡木都有，适合正式对局。"
	},
	{
		"name": "圆环障碍训练场",
		"path": "res://maps/ring_training.json",
		"description": "节奏更快的官方地图：圆柱、球体、环形绕行路线和中场高台更多。"
	},
	{
		"name": "双层别墅追逐战",
		"path": "res://maps/two_story_villa.json",
		"description": "开放首层、中庭与二层环廊组成的多路线别墅；三条坡道让追逐能在上下层持续转换。"
	}
]

var player
var tagger
var hud_layer: CanvasLayer
var hud_label: Label
var center_label: Label
var title_layer: CanvasLayer
var title_status: Label
var ip_input: LineEdit
var win_time_row: HBoxContainer
var win_time_spinbox: SpinBox
var map_summary_label: Label
var map_select_button: Button
var map_list: ItemList
var map_description_label: Label
var settings_display_mode_option: OptionButton
var camera_mode_option: OptionButton
var runner_skin_option: OptionButton
var tagger_skin_option: OptionButton
var runner_skin_preview: TextureRect
var tagger_skin_preview: TextureRect
var runner_skin_preview_label: Label
var tagger_skin_preview_label: Label
var available_skin_ids: Array[String] = []
var lobby_role_label: Label
var switch_role_button: Button
var start_game_button: Button
var setup_controls: Array[Control] = []
var menu_controls: Array[Control] = []
var lobby_controls: Array[Control] = []
var map_page_controls: Array[Control] = []
var settings_controls: Array[Control] = []
var time_alive := 0.0
var caught := false
var ai_catch_cooldown := 0.0
var game_mode := "title"
var network_started := false
var remote_peer_id := 0
var host_is_runner := true
var win_time_seconds := 60.0
var is_leaving_room := false
var round_transition_token := 0
var map_root: Node3D
var map_name := "默认地图"
var active_map_path := ""
var selected_map_index := 0
var map_preview_index := 0
var selected_map_path := DEFAULT_MAP_PATH
var map_page_return_mode := "menu"
var debug_mode := false
var debug_obstacle_material: StandardMaterial3D
var debug_actor_material: StandardMaterial3D
@export var runner_skin_id := "badge2"
@export var tagger_skin_id := "default"
var selected_camera_mode := "third_person"
var runner_spawn_position := Vector3(-23.0, 0.12, 22.0)
var tagger_spawn_position := Vector3(23.0, 0.12, -22.0)

func _ready() -> void:
	randomize()
	_ensure_default_fullscreen()
	_ensure_input_actions()
	_connect_multiplayer_signals()
	_setup_world()
	_load_active_map()
	_build_hud()
	_build_title_ui()
	_show_title("选择模式开始游戏")

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("quit_room"):
		if game_mode == "single":
			_show_title("已返回标题界面。")
			return
		if _is_in_network_room():
			_leave_room("已退出房间。")
			return

	if Input.is_action_just_pressed("toggle_debug"):
		_toggle_debug_mode()

	if game_mode == "title" or game_mode == "waiting" or game_mode == "lobby":
		return

	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if Input.is_action_just_pressed("restart"):
		if game_mode == "single":
			_start_single_game()
		elif game_mode == "host" and remote_peer_id != 0:
			_start_network_round(remote_peer_id)
			rpc("_rpc_begin_network_round", remote_peer_id, host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode)
		return

	if caught:
		return

	if (game_mode == "single" or game_mode == "host") and player.global_position.y < VOID_Y:
		_on_runner_fell()
		return

	time_alive += delta
	ai_catch_cooldown = maxf(ai_catch_cooldown - delta, 0.0)
	var catch_offset: Vector3 = player.global_position - tagger.global_position
	catch_offset.y = 0.0
	var distance: float = catch_offset.length()
	var mode_text := "单人模式" if game_mode == "single" else "联机一打一：" + _local_role_text()
	var controls_text := "WASD 移动  空格跳跃/翻越  鼠标视角  Esc 鼠标  R 重开  F3 碰撞箱:%s" % ["开" if debug_mode else "关"]
	if _local_is_tagger():
		controls_text += "  左键抓人"
	if game_mode == "single":
		controls_text += "  Q 回标题"
	else:
		controls_text += "  Q 退出房间"
	hud_label.text = "%s\n地图：%s\n逃跑时间：%05.2f / %d 秒\n抓人者速度：7.8  逃跑者速度：7.0\n抓捕距离：%04.1f / %.1f 米\n%s" % [mode_text, map_name, time_alive, int(win_time_seconds), distance, CATCH_RANGE, controls_text]

	if (game_mode == "single" or game_mode == "host") and time_alive >= win_time_seconds:
		_on_runner_survived()
		return

	if _local_is_tagger() and Input.is_action_just_pressed("catch_attack") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_request_local_catch_attempt()

	if game_mode == "single":
		_try_ai_catch_attempt(distance)

func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(Callable(self, "_on_peer_connected"))
	multiplayer.peer_disconnected.connect(Callable(self, "_on_peer_disconnected"))
	multiplayer.connected_to_server.connect(Callable(self, "_on_connected_to_server"))
	multiplayer.connection_failed.connect(Callable(self, "_on_connection_failed"))
	multiplayer.server_disconnected.connect(Callable(self, "_on_server_disconnected"))

func _cartoon_style(fill: Color, border: Color, border_width: int = 4, radius: int = 16, shadow_offset: Vector2 = Vector2(0.0, 5.0), margin: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0.08, 0.1, 0.18, 0.22)
	style.shadow_size = 8
	style.shadow_offset = shadow_offset
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	return style

func _style_button(button: Button, fill: Color, border: Color) -> void:
	button.custom_minimum_size = Vector2(0.0, 46.0)
	button.add_theme_stylebox_override("normal", _cartoon_style(fill, border, 4, 16, Vector2(0.0, 5.0), 12))
	button.add_theme_stylebox_override("hover", _cartoon_style(fill.lightened(0.1), border, 4, 16, Vector2(0.0, 4.0), 12))
	button.add_theme_stylebox_override("pressed", _cartoon_style(fill.darkened(0.1), border.darkened(0.05), 4, 16, Vector2(0.0, 2.0), 12))
	button.add_theme_stylebox_override("disabled", _cartoon_style(Color(0.7, 0.72, 0.78, 0.75), Color(0.42, 0.44, 0.52), 4, 16, Vector2(0.0, 2.0), 12))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.92, 0.92, 0.95, 0.8))
	button.add_theme_color_override("font_outline_color", Color(0.07, 0.08, 0.15))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_font_size_override("font_size", 18)

func _style_input(control: Control) -> void:
	control.add_theme_stylebox_override("normal", _cartoon_style(Color(1.0, 1.0, 0.96, 0.98), Color(0.25, 0.33, 0.58), 3, 14, Vector2(0.0, 3.0), 9))
	control.add_theme_stylebox_override("focus", _cartoon_style(Color(1.0, 0.98, 0.86, 0.98), Color(1.0, 0.55, 0.16), 4, 14, Vector2(0.0, 3.0), 9))
	control.add_theme_color_override("font_color", Color(0.14, 0.16, 0.3))
	control.add_theme_color_override("font_placeholder_color", Color(0.42, 0.46, 0.62))
	control.add_theme_font_size_override("font_size", 17)

func _style_item_list(item_list: ItemList) -> void:
	item_list.add_theme_stylebox_override("panel", _cartoon_style(Color(1.0, 1.0, 0.96, 0.98), Color(0.25, 0.33, 0.58), 3, 14, Vector2(0.0, 3.0), 10))
	item_list.add_theme_stylebox_override("focus", _cartoon_style(Color(1.0, 0.98, 0.86, 0.98), Color(1.0, 0.55, 0.16), 3, 14, Vector2(0.0, 3.0), 10))
	item_list.add_theme_color_override("font_color", Color(0.14, 0.16, 0.3))
	item_list.add_theme_color_override("font_selected_color", Color.WHITE)
	item_list.add_theme_color_override("guide_color", Color(1.0, 0.62, 0.18, 0.45))
	item_list.add_theme_font_size_override("font_size", 18)

func _apply_label_style(label: Label, color: Color = Color(0.18, 0.22, 0.42), outline_size: int = 2) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.72))
	label.add_theme_constant_override("outline_size", outline_size)

func _build_title_ui() -> void:
	title_layer = CanvasLayer.new()
	title_layer.name = "TitleUI"
	add_child(title_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.78, 1.0, 0.98)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	title_layer.add_child(bg)

	var grass := ColorRect.new()
	grass.color = Color(0.34, 0.82, 0.38, 0.9)
	grass.anchor_top = 0.83
	grass.anchor_right = 1.0
	grass.anchor_bottom = 1.0
	title_layer.add_child(grass)

	var sun := Panel.new()
	sun.position = Vector2(54.0, 44.0)
	sun.custom_minimum_size = Vector2(118.0, 118.0)
	sun.add_theme_stylebox_override("panel", _cartoon_style(Color(1.0, 0.86, 0.25, 0.95), Color(1.0, 0.58, 0.12), 5, 64, Vector2(0.0, 4.0)))
	title_layer.add_child(sun)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	title_layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560.0, 0.0)
	card.add_theme_stylebox_override("panel", _cartoon_style(Color(1.0, 0.95, 0.76, 0.96), Color(0.17, 0.23, 0.43), 5, 22, Vector2(0.0, 9.0), 18))
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)

	var title := Label.new()
	title.text = "跑酷抓人"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.43, 0.14))
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.18, 0.32))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "卡通跑酷派对 · 单人逃脱 / 联机一打一"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	_apply_label_style(subtitle, Color(0.16, 0.24, 0.42), 2)
	box.add_child(subtitle)

	win_time_row = HBoxContainer.new()
	win_time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	win_time_row.add_theme_constant_override("separation", 10)
	box.add_child(win_time_row)
	setup_controls.append(win_time_row)

	var win_time_label := Label.new()
	win_time_label.text = "胜利时间"
	_apply_label_style(win_time_label)
	win_time_row.add_child(win_time_label)

	win_time_spinbox = SpinBox.new()
	win_time_spinbox.min_value = 10.0
	win_time_spinbox.max_value = 600.0
	win_time_spinbox.step = 5.0
	win_time_spinbox.value = win_time_seconds
	win_time_spinbox.suffix = " 秒"
	win_time_spinbox.custom_minimum_size = Vector2(124.0, 42.0)
	_style_input(win_time_spinbox)
	win_time_spinbox.value_changed.connect(Callable(self, "_on_win_time_changed"))
	win_time_row.add_child(win_time_spinbox)

	var win_time_hint := Label.new()
	win_time_hint.text = "逃跑者坚持到即胜"
	_apply_label_style(win_time_hint, Color(0.35, 0.28, 0.18), 1)
	win_time_row.add_child(win_time_hint)

	var map_row := HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row.add_theme_constant_override("separation", 10)
	box.add_child(map_row)
	setup_controls.append(map_row)

	map_summary_label = Label.new()
	map_summary_label.text = "当前地图：%s" % map_name
	_apply_label_style(map_summary_label)
	map_row.add_child(map_summary_label)

	map_select_button = Button.new()
	map_select_button.text = "选择官方地图"
	_style_button(map_select_button, Color(0.15, 0.61, 1.0), Color(0.06, 0.29, 0.58))
	map_select_button.pressed.connect(Callable(self, "_show_map_page"))
	map_row.add_child(map_select_button)

	var skin_row := HBoxContainer.new()
	skin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skin_row.add_theme_constant_override("separation", 10)
	box.add_child(skin_row)
	setup_controls.append(skin_row)

	var runner_skin_label := Label.new()
	runner_skin_label.text = "逃跑者皮肤"
	_apply_label_style(runner_skin_label)
	skin_row.add_child(runner_skin_label)

	runner_skin_option = OptionButton.new()
	runner_skin_option.custom_minimum_size = Vector2(130.0, 42.0)
	_style_button(runner_skin_option, Color(0.15, 0.61, 1.0), Color(0.06, 0.29, 0.58))
	runner_skin_option.item_selected.connect(Callable(self, "_on_runner_skin_selected"))
	skin_row.add_child(runner_skin_option)

	var tagger_skin_label := Label.new()
	tagger_skin_label.text = "抓人者皮肤"
	_apply_label_style(tagger_skin_label)
	skin_row.add_child(tagger_skin_label)

	tagger_skin_option = OptionButton.new()
	tagger_skin_option.custom_minimum_size = Vector2(130.0, 42.0)
	_style_button(tagger_skin_option, Color(1.0, 0.52, 0.17), Color(0.64, 0.23, 0.06))
	tagger_skin_option.item_selected.connect(Callable(self, "_on_tagger_skin_selected"))
	skin_row.add_child(tagger_skin_option)

	var camera_row := HBoxContainer.new()
	camera_row.alignment = BoxContainer.ALIGNMENT_CENTER
	camera_row.add_theme_constant_override("separation", 10)
	box.add_child(camera_row)
	setup_controls.append(camera_row)

	var camera_mode_label := Label.new()
	camera_mode_label.text = "视角"
	_apply_label_style(camera_mode_label)
	camera_row.add_child(camera_mode_label)

	camera_mode_option = OptionButton.new()
	camera_mode_option.custom_minimum_size = Vector2(230.0, 42.0)
	_style_button(camera_mode_option, Color(0.36, 0.5, 1.0), Color(0.14, 0.2, 0.58))
	camera_mode_option.add_item("第三人称")
	camera_mode_option.add_item("第一人称")
	camera_mode_option.item_selected.connect(Callable(self, "_on_camera_mode_selected"))
	camera_row.add_child(camera_mode_option)

	_refresh_skin_options()

	var preview_row := HBoxContainer.new()
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_theme_constant_override("separation", 18)
	box.add_child(preview_row)
	setup_controls.append(preview_row)

	var runner_preview_card := PanelContainer.new()
	runner_preview_card.custom_minimum_size = Vector2(170.0, 200.0)
	runner_preview_card.add_theme_stylebox_override("panel", _cartoon_style(Color(0.86, 0.95, 1.0, 0.96), Color(0.06, 0.29, 0.58), 3, 16, Vector2(0.0, 4.0), 10))
	preview_row.add_child(runner_preview_card)

	var runner_preview_box := VBoxContainer.new()
	runner_preview_box.alignment = BoxContainer.ALIGNMENT_CENTER
	runner_preview_box.add_theme_constant_override("separation", 8)
	runner_preview_card.add_child(runner_preview_box)

	var runner_preview_title := Label.new()
	runner_preview_title.text = "逃跑者预览"
	runner_preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(runner_preview_title, Color(0.16, 0.27, 0.48), 2)
	runner_preview_box.add_child(runner_preview_title)

	runner_skin_preview = TextureRect.new()
	runner_skin_preview.custom_minimum_size = Vector2(116.0, 116.0)
	runner_skin_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	runner_skin_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	runner_skin_preview.self_modulate = Color(0.96, 0.98, 1.0, 1.0)
	runner_preview_box.add_child(runner_skin_preview)

	runner_skin_preview_label = Label.new()
	runner_skin_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(runner_skin_preview_label, Color(0.2, 0.24, 0.38), 1)
	runner_preview_box.add_child(runner_skin_preview_label)

	var tagger_preview_card := PanelContainer.new()
	tagger_preview_card.custom_minimum_size = Vector2(170.0, 200.0)
	tagger_preview_card.add_theme_stylebox_override("panel", _cartoon_style(Color(1.0, 0.93, 0.87, 0.96), Color(0.64, 0.23, 0.06), 3, 16, Vector2(0.0, 4.0), 10))
	preview_row.add_child(tagger_preview_card)

	var tagger_preview_box := VBoxContainer.new()
	tagger_preview_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tagger_preview_box.add_theme_constant_override("separation", 8)
	tagger_preview_card.add_child(tagger_preview_box)

	var tagger_preview_title := Label.new()
	tagger_preview_title.text = "抓人者预览"
	tagger_preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(tagger_preview_title, Color(0.44, 0.17, 0.1), 2)
	tagger_preview_box.add_child(tagger_preview_title)

	tagger_skin_preview = TextureRect.new()
	tagger_skin_preview.custom_minimum_size = Vector2(116.0, 116.0)
	tagger_skin_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tagger_skin_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tagger_skin_preview.self_modulate = Color(1.0, 0.97, 0.92, 1.0)
	tagger_preview_box.add_child(tagger_skin_preview)

	tagger_skin_preview_label = Label.new()
	tagger_skin_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(tagger_skin_preview_label, Color(0.33, 0.2, 0.16), 1)
	tagger_preview_box.add_child(tagger_skin_preview_label)

	_update_skin_previews()

	var single_button := Button.new()
	single_button.text = "单人模式：逃跑者 VS AI 抓人者"
	_style_button(single_button, Color(1.0, 0.52, 0.17), Color(0.64, 0.23, 0.06))
	single_button.pressed.connect(Callable(self, "_start_single_game"))
	box.add_child(single_button)
	menu_controls.append(single_button)

	var host_button := Button.new()
	host_button.text = "创建联机房间"
	_style_button(host_button, Color(0.34, 0.78, 0.32), Color(0.12, 0.42, 0.17))
	host_button.pressed.connect(Callable(self, "_start_host_game"))
	box.add_child(host_button)
	menu_controls.append(host_button)

	ip_input = LineEdit.new()
	ip_input.text = "127.0.0.1"
	ip_input.placeholder_text = "输入房主 IP"
	ip_input.custom_minimum_size = Vector2(0.0, 42.0)
	_style_input(ip_input)
	box.add_child(ip_input)
	menu_controls.append(ip_input)

	var join_button := Button.new()
	join_button.text = "加入联机房间"
	_style_button(join_button, Color(0.61, 0.42, 1.0), Color(0.28, 0.18, 0.58))
	join_button.pressed.connect(Callable(self, "_start_client_game"))
	box.add_child(join_button)
	menu_controls.append(join_button)

	var settings_button := Button.new()
	settings_button.text = "设置"
	_style_button(settings_button, Color(0.18, 0.58, 0.78), Color(0.06, 0.28, 0.42))
	settings_button.pressed.connect(Callable(self, "_show_settings_page"))
	box.add_child(settings_button)
	menu_controls.append(settings_button)

	var quit_button := Button.new()
	quit_button.text = "退出游戏"
	_style_button(quit_button, Color(0.93, 0.45, 0.45), Color(0.56, 0.12, 0.12))
	quit_button.pressed.connect(Callable(self, "_quit_game"))
	box.add_child(quit_button)
	menu_controls.append(quit_button)

	lobby_role_label = Label.new()
	lobby_role_label.text = ""
	lobby_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_role_label.add_theme_font_size_override("font_size", 22)
	_apply_label_style(lobby_role_label)
	box.add_child(lobby_role_label)
	lobby_controls.append(lobby_role_label)

	switch_role_button = Button.new()
	switch_role_button.text = "切换角色"
	_style_button(switch_role_button, Color(1.0, 0.72, 0.2), Color(0.7, 0.38, 0.06))
	switch_role_button.pressed.connect(Callable(self, "_toggle_lobby_roles"))
	box.add_child(switch_role_button)
	lobby_controls.append(switch_role_button)

	start_game_button = Button.new()
	start_game_button.text = "开始游戏"
	_style_button(start_game_button, Color(0.22, 0.78, 0.48), Color(0.08, 0.38, 0.18))
	start_game_button.pressed.connect(Callable(self, "_start_lobby_game"))
	box.add_child(start_game_button)
	lobby_controls.append(start_game_button)

	var map_page_title := Label.new()
	map_page_title.text = "官方地图列表"
	map_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_page_title.add_theme_font_size_override("font_size", 32)
	_apply_label_style(map_page_title, Color(0.18, 0.22, 0.45), 3)
	box.add_child(map_page_title)
	map_page_controls.append(map_page_title)

	map_list = ItemList.new()
	map_list.custom_minimum_size = Vector2(500.0, 210.0)
	_style_item_list(map_list)
	map_list.item_selected.connect(Callable(self, "_on_map_item_selected"))
	for map_info in OFFICIAL_MAPS:
		map_list.add_item(String(map_info.get("name", "官方地图")))
	map_list.select(selected_map_index)
	box.add_child(map_list)
	map_page_controls.append(map_list)

	map_description_label = Label.new()
	map_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(map_description_label, Color(0.24, 0.25, 0.34), 1)
	box.add_child(map_description_label)
	map_page_controls.append(map_description_label)

	var map_page_buttons := HBoxContainer.new()
	map_page_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	map_page_buttons.add_theme_constant_override("separation", 10)
	box.add_child(map_page_buttons)
	map_page_controls.append(map_page_buttons)

	var use_map_button := Button.new()
	use_map_button.text = "使用选中地图"
	_style_button(use_map_button, Color(0.25, 0.74, 0.48), Color(0.08, 0.38, 0.18))
	use_map_button.pressed.connect(Callable(self, "_confirm_map_selection"))
	map_page_buttons.add_child(use_map_button)

	var back_map_button := Button.new()
	back_map_button.text = "返回"
	_style_button(back_map_button, Color(0.93, 0.45, 0.45), Color(0.56, 0.12, 0.12))
	back_map_button.pressed.connect(Callable(self, "_close_map_page"))
	map_page_buttons.add_child(back_map_button)

	var settings_title := Label.new()
	settings_title.text = "设置"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 32)
	_apply_label_style(settings_title, Color(0.18, 0.22, 0.45), 3)
	box.add_child(settings_title)
	settings_controls.append(settings_title)

	var display_mode_row := HBoxContainer.new()
	display_mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	display_mode_row.add_theme_constant_override("separation", 10)
	box.add_child(display_mode_row)
	settings_controls.append(display_mode_row)

	var display_mode_label := Label.new()
	display_mode_label.text = "显示模式"
	_apply_label_style(display_mode_label)
	display_mode_row.add_child(display_mode_label)

	settings_display_mode_option = OptionButton.new()
	settings_display_mode_option.custom_minimum_size = Vector2(150.0, 42.0)
	_style_button(settings_display_mode_option, Color(0.15, 0.61, 1.0), Color(0.06, 0.29, 0.58))
	settings_display_mode_option.add_item("全屏")
	settings_display_mode_option.add_item("窗口")
	settings_display_mode_option.item_selected.connect(Callable(self, "_on_display_mode_selected"))
	display_mode_row.add_child(settings_display_mode_option)

	var settings_hint := Label.new()
	settings_hint.text = "当前只支持切换全屏 / 窗口模式。"
	settings_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_label_style(settings_hint, Color(0.24, 0.25, 0.34), 1)
	box.add_child(settings_hint)
	settings_controls.append(settings_hint)

	var back_settings_button := Button.new()
	back_settings_button.text = "返回主页"
	_style_button(back_settings_button, Color(0.93, 0.45, 0.45), Color(0.56, 0.12, 0.12))
	back_settings_button.pressed.connect(Callable(self, "_close_settings_page"))
	box.add_child(back_settings_button)
	settings_controls.append(back_settings_button)

	title_status = Label.new()
	title_status.text = ""
	title_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_label_style(title_status, Color(0.25, 0.22, 0.32), 1)
	box.add_child(title_status)
	_set_lobby_visible(false)
	_set_map_page_visible(false)
	_set_settings_page_visible(false)
	_update_map_ui()
	_update_display_mode_ui()
	_update_camera_mode_ui()

func _set_setup_visible(is_visible: bool) -> void:
	for control in setup_controls:
		control.visible = is_visible

func _set_menu_visible(is_visible: bool) -> void:
	for control in menu_controls:
		control.visible = is_visible

func _set_lobby_visible(is_visible: bool) -> void:
	for control in lobby_controls:
		control.visible = is_visible

func _set_map_page_visible(is_visible: bool) -> void:
	for control in map_page_controls:
		control.visible = is_visible

func _set_settings_page_visible(is_visible: bool) -> void:
	for control in settings_controls:
		control.visible = is_visible

func _show_settings_page() -> void:
	_set_setup_visible(false)
	_set_menu_visible(false)
	_set_lobby_visible(false)
	_set_map_page_visible(false)
	_set_settings_page_visible(true)
	_update_display_mode_ui()
	_update_camera_mode_ui()
	if title_status != null:
		title_status.text = "调整游戏设置。"

func _close_settings_page() -> void:
	_set_settings_page_visible(false)
	_set_setup_visible(true)
	_set_menu_visible(true)
	_update_map_ui()
	if title_status != null:
		title_status.text = "选择模式开始游戏"

func _is_fullscreen_mode() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _update_display_mode_ui() -> void:
	if settings_display_mode_option == null:
		return
	settings_display_mode_option.select(0 if _is_fullscreen_mode() else 1)

func _on_display_mode_selected(index: int) -> void:
	var use_fullscreen := index == 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if use_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	_update_display_mode_ui()
	if title_status != null:
		title_status.text = "已切换为：%s。" % ["全屏" if use_fullscreen else "窗口"]

func _on_camera_mode_selected(index: int) -> void:
	if game_mode == "lobby" and not multiplayer.is_server():
		_update_camera_mode_ui()
		return
	selected_camera_mode = "first_person" if index == 1 else "third_person"
	_update_camera_mode_ui()
	_apply_camera_mode_to_local_actor()
	if game_mode == "lobby" and multiplayer.is_server() and remote_peer_id != 0:
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "房主已切换视角为：%s，等待房主开始游戏。" % _camera_mode_display_name())
	if title_status != null:
		title_status.text = "已选择视角：%s。" % _camera_mode_display_name()

func _update_camera_mode_ui() -> void:
	if camera_mode_option == null:
		return
	camera_mode_option.select(1 if selected_camera_mode == "first_person" else 0)
	camera_mode_option.disabled = game_mode == "lobby" and not multiplayer.is_server()

func _camera_mode_display_name() -> String:
	return "第一人称" if selected_camera_mode == "first_person" else "第三人称"

func _apply_camera_mode_to_local_actor() -> void:
	var local_peer := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	for actor in [player, tagger]:
		if actor == null or not is_instance_valid(actor) or not actor.has_method("set_camera_mode"):
			continue
		if game_mode == "single" and actor == player:
			actor.set_camera_mode(selected_camera_mode)
		elif game_mode != "single" and int(actor.get("owner_peer_id")) == local_peer:
			actor.set_camera_mode(selected_camera_mode)

func _show_map_page() -> void:
	if game_mode == "lobby" and not multiplayer.is_server():
		return
	map_page_return_mode = "lobby" if game_mode == "lobby" else "menu"
	map_preview_index = selected_map_index
	_set_setup_visible(false)
	_set_menu_visible(false)
	_set_lobby_visible(false)
	_set_settings_page_visible(false)
	_set_map_page_visible(true)
	_update_map_ui()
	if title_status != null:
		title_status.text = "从官方地图列表中选择本局地图。"

func _close_map_page() -> void:
	_set_map_page_visible(false)
	_set_setup_visible(true)
	if map_page_return_mode == "lobby":
		_set_lobby_visible(true)
		_update_lobby_ui()
	else:
		_set_menu_visible(true)
		_update_map_ui()
	if title_status != null:
		title_status.text = "当前地图：%s" % map_name

func _on_map_item_selected(index: int) -> void:
	map_preview_index = index
	_update_map_ui()

func _confirm_map_selection() -> void:
	if _select_official_map(map_preview_index, true):
		_close_map_page()

func _select_official_map(index: int, should_sync: bool) -> bool:
	if index < 0 or index >= OFFICIAL_MAPS.size():
		return false
	selected_map_index = index
	selected_map_path = String(OFFICIAL_MAPS[index].get("path", DEFAULT_MAP_PATH))
	var loaded := _load_active_map()
	_update_map_ui()
	if title_status != null:
		title_status.text = "已选择官方地图：%s" % map_name if loaded else "地图加载失败，已保留当前选择。"
	if loaded and should_sync and game_mode == "lobby" and multiplayer.is_server() and remote_peer_id != 0:
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "地图已切换为：%s，等待房主开始游戏。" % map_name)
	return loaded

func _update_map_ui() -> void:
	if map_summary_label != null:
		map_summary_label.text = "当前地图：%s" % map_name
	if map_select_button != null:
		map_select_button.disabled = game_mode == "lobby" and not multiplayer.is_server()
	if map_list != null and OFFICIAL_MAPS.size() > 0:
		if map_preview_index < 0 or map_preview_index >= OFFICIAL_MAPS.size():
			map_preview_index = selected_map_index
		map_list.select(map_preview_index)
	if map_description_label != null and map_preview_index >= 0 and map_preview_index < OFFICIAL_MAPS.size():
		var info: Dictionary = OFFICIAL_MAPS[map_preview_index]
		map_description_label.text = "%s\n%s" % [String(info.get("name", "官方地图")), String(info.get("description", ""))]

func _on_win_time_changed(value: float) -> void:
	win_time_seconds = value
	if game_mode == "lobby" and multiplayer.is_server() and remote_peer_id != 0:
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "胜利时间已改为 %d 秒，等待房主开始游戏。" % int(win_time_seconds))
	_update_lobby_ui()

func _refresh_win_time_from_ui() -> void:
	if win_time_spinbox != null:
		win_time_seconds = win_time_spinbox.value

func _refresh_skin_options() -> void:
	available_skin_ids = SkinAPI.list_available_skin_ids()
	if available_skin_ids.is_empty():
		available_skin_ids = ["default"]
	if not available_skin_ids.has(runner_skin_id):
		runner_skin_id = "default"
	if not available_skin_ids.has(tagger_skin_id):
		tagger_skin_id = "default"

	if runner_skin_option != null:
		runner_skin_option.clear()
		for skin in available_skin_ids:
			runner_skin_option.add_item(skin)
		var idx := available_skin_ids.find(runner_skin_id)
		runner_skin_option.select(maxi(idx, 0))

	if tagger_skin_option != null:
		tagger_skin_option.clear()
		for skin in available_skin_ids:
			tagger_skin_option.add_item(skin)
		var idx2 := available_skin_ids.find(tagger_skin_id)
		tagger_skin_option.select(maxi(idx2, 0))

	_update_skin_previews()

func _update_skin_previews() -> void:
	if runner_skin_preview != null:
		runner_skin_preview.texture = SkinAPI.get_skin_preview_texture(runner_skin_id, "runner")
	if runner_skin_preview_label != null:
		runner_skin_preview_label.text = "当前：%s" % runner_skin_id

	if tagger_skin_preview != null:
		tagger_skin_preview.texture = SkinAPI.get_skin_preview_texture(tagger_skin_id, "tagger")
	if tagger_skin_preview_label != null:
		tagger_skin_preview_label.text = "当前：%s" % tagger_skin_id

func _on_runner_skin_selected(index: int) -> void:
	if index < 0 or index >= available_skin_ids.size():
		return
	runner_skin_id = available_skin_ids[index]
	_update_skin_previews()
	if game_mode == "lobby" and multiplayer.is_server() and remote_peer_id != 0:
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "皮肤已更新，等待房主开始游戏。")
	_update_lobby_ui()

func _on_tagger_skin_selected(index: int) -> void:
	if index < 0 or index >= available_skin_ids.size():
		return
	tagger_skin_id = available_skin_ids[index]
	_update_skin_previews()
	if game_mode == "lobby" and multiplayer.is_server() and remote_peer_id != 0:
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "皮肤已更新，等待房主开始游戏。")
	_update_lobby_ui()

func _show_title(message: String) -> void:
	_close_network()
	_clear_characters()
	game_mode = "title"
	network_started = false
	remote_peer_id = 0
	host_is_runner = true
	caught = false
	ai_catch_cooldown = 0.0
	time_alive = 0.0
	if title_layer != null:
		title_layer.visible = true
	if hud_layer != null:
		hud_layer.visible = false
	if center_label != null:
		center_label.text = ""
	_set_setup_visible(true)
	_set_menu_visible(true)
	_set_lobby_visible(false)
	_set_map_page_visible(false)
	_set_settings_page_visible(false)
	_update_map_ui()
	_update_display_mode_ui()
	_update_camera_mode_ui()
	_refresh_skin_options()
	if win_time_row != null:
		win_time_row.visible = true
	if win_time_spinbox != null:
		win_time_spinbox.editable = true
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	if title_status != null:
		title_status.text = message
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _start_single_game() -> void:
	_refresh_win_time_from_ui()
	_close_network()
	_clear_characters()
	if not _load_active_map():
		if title_status != null:
			title_status.text = "地图加载失败，无法开始游戏。"
		return
	game_mode = "single"
	caught = false
	ai_catch_cooldown = 0.0
	time_alive = 0.0
	title_layer.visible = false
	hud_layer.visible = true
	center_label.text = ""
	_spawn_single_characters()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _start_host_game() -> void:
	_refresh_win_time_from_ui()
	is_leaving_room = false
	_close_network()
	_clear_characters()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 1)
	if error != OK:
		title_status.text = "创建房间失败，端口可能被占用。错误码：%s" % error
		return
	multiplayer.multiplayer_peer = peer
	game_mode = "lobby"
	network_started = false
	remote_peer_id = 0
	host_is_runner = true
	_enter_lobby("房间已创建，等待 1 名玩家加入...\n端口：%d\n加入者输入你的局域网 IP。" % PORT)

func _start_client_game() -> void:
	is_leaving_room = false
	_close_network()
	_clear_characters()
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, PORT)
	if error != OK:
		title_status.text = "连接失败，错误码：%s" % error
		return
	multiplayer.multiplayer_peer = peer
	game_mode = "waiting"
	_set_setup_visible(false)
	_set_menu_visible(false)
	_set_lobby_visible(false)
	_set_map_page_visible(false)
	_set_settings_page_visible(false)
	title_status.text = "正在连接 %s:%d ..." % [ip, PORT]

func _quit_game() -> void:
	get_tree().quit()

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server() or network_started:
		return
	remote_peer_id = peer_id
	network_started = true
	_enter_lobby("玩家已加入。双方可在房间内切换角色，房主点击开始游戏。")
	rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "已加入房间。双方可在房间内切换角色，等待房主开始游戏。")

func _on_peer_disconnected(peer_id: int) -> void:
	if is_leaving_room:
		return
	if game_mode == "host" or game_mode == "client" or game_mode == "waiting" or game_mode == "lobby":
		_show_title("对方已断开，已返回标题界面。")

func _on_connected_to_server() -> void:
	game_mode = "lobby"
	_enter_lobby("已连接房主，等待房主同步房间信息...")

func _on_connection_failed() -> void:
	_show_title("连接失败，请检查 IP、防火墙或房主是否已创建房间。")

func _on_server_disconnected() -> void:
	_show_title("与房主断开连接，已返回标题界面。")

func _enter_lobby(message: String) -> void:
	round_transition_token += 1
	game_mode = "lobby"
	_clear_characters()
	if title_layer != null:
		title_layer.visible = true
	if hud_layer != null:
		hud_layer.visible = false
	_set_setup_visible(true)
	_set_menu_visible(false)
	_set_lobby_visible(true)
	_set_map_page_visible(false)
	_set_settings_page_visible(false)
	_refresh_skin_options()
	if title_status != null:
		title_status.text = message
	_update_lobby_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _update_lobby_ui() -> void:
	if lobby_role_label == null:
		return
	var local_role := _local_lobby_role_text()
	var other_role := "抓人者" if local_role == "逃跑者" else "逃跑者"
	lobby_role_label.text = "你的角色：%s\n对方角色：%s\n胜利时间：%d 秒\n地图：%s\n视角：%s（房主选择）\n按 Q 退出房间" % [local_role, other_role, int(win_time_seconds), map_name, _camera_mode_display_name()]
	if win_time_spinbox != null:
		win_time_spinbox.editable = multiplayer.is_server()
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	if start_game_button != null:
		start_game_button.visible = multiplayer.is_server()
		start_game_button.disabled = not multiplayer.is_server() or remote_peer_id == 0
	if switch_role_button != null:
		switch_role_button.visible = true
	_update_map_ui()
	_update_camera_mode_ui()

func _schedule_return_to_lobby_after_round() -> void:
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	var token := round_transition_token
	await get_tree().create_timer(MULTIPLAYER_RESULT_DELAY).timeout
	if token != round_transition_token or game_mode != "host" or remote_peer_id == 0:
		return
	_return_to_lobby_after_round()

func _return_to_lobby_after_round() -> void:
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	host_is_runner = not host_is_runner
	_enter_lobby("上一局结算完成，已自动交换追/被追。房主可继续切换角色、地图或开始下一局。")
	rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "上一局结算完成，已自动交换追/被追。等待房主开始下一局。")

func _local_lobby_role_text() -> String:
	var is_host := multiplayer.is_server()
	var local_is_runner := host_is_runner if is_host else not host_is_runner
	return "逃跑者" if local_is_runner else "抓人者"

func _toggle_lobby_roles() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		host_is_runner = not host_is_runner
		_update_lobby_ui()
		if remote_peer_id != 0:
			rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "角色已切换，等待房主开始游戏。")
	else:
		rpc_id(1, "_rpc_request_role_switch")

func _start_lobby_game() -> void:
	_refresh_win_time_from_ui()
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	_start_network_round(remote_peer_id)
	rpc("_rpc_begin_network_round", remote_peer_id, host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode)

@rpc("any_peer", "reliable")
func _rpc_request_role_switch() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	host_is_runner = not host_is_runner
	_update_lobby_ui()
	rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "角色已切换，等待房主开始游戏。")

@rpc("call_remote", "reliable")
func _rpc_sync_lobby(new_host_is_runner: bool, new_win_time_seconds: float, new_map_index: int, new_runner_skin_id: String, new_tagger_skin_id: String, new_camera_mode: String, message: String) -> void:
	host_is_runner = new_host_is_runner
	win_time_seconds = new_win_time_seconds
	runner_skin_id = new_runner_skin_id
	tagger_skin_id = new_tagger_skin_id
	selected_camera_mode = "first_person" if new_camera_mode == "first_person" else "third_person"
	_select_official_map(new_map_index, false)
	if win_time_spinbox != null:
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	network_started = true
	_enter_lobby(message)

@rpc("call_remote", "reliable")
func _rpc_begin_network_round(client_id: int, new_host_is_runner: bool, new_win_time_seconds: float, new_map_index: int, new_runner_skin_id: String, new_tagger_skin_id: String, new_camera_mode: String) -> void:
	remote_peer_id = client_id
	host_is_runner = new_host_is_runner
	win_time_seconds = new_win_time_seconds
	runner_skin_id = new_runner_skin_id
	tagger_skin_id = new_tagger_skin_id
	selected_camera_mode = "first_person" if new_camera_mode == "first_person" else "third_person"
	_select_official_map(new_map_index, false)
	if win_time_spinbox != null:
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	network_started = true
	_start_network_round(client_id)

func _start_network_round(client_id: int) -> void:
	round_transition_token += 1
	_clear_characters()
	if not _load_active_map():
		if title_status != null:
			title_status.text = "地图加载失败，无法开始联机游戏。"
		return
	game_mode = "host" if multiplayer.is_server() else "client"
	caught = false
	ai_catch_cooldown = 0.0
	time_alive = 0.0
	if title_layer != null:
		title_layer.visible = false
	hud_layer.visible = true
	center_label.text = ""
	_spawn_network_characters(client_id)
	_apply_camera_mode_to_local_actor()
	if debug_mode:
		_refresh_debug_collision_shapes()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _spawn_single_characters() -> void:
	player = CharacterBody3D.new()
	player.name = "Runner"
	player.set_script(PlayerScript)
	player.skin_id = runner_skin_id
	add_child(player)
	player.global_position = _grounded_spawn_position(runner_spawn_position)

	tagger = CharacterBody3D.new()
	tagger.name = "Tagger"
	tagger.set_script(RLPolicyTaggerScript if USE_RL_POLICY_TAGGER else TaggerScript)
	tagger.skin_id = tagger_skin_id
	add_child(tagger)
	tagger.global_position = _grounded_spawn_position(tagger_spawn_position)
	tagger.target = player

func _spawn_network_characters(client_id: int) -> void:
	var runner_peer_id := 1 if host_is_runner else client_id
	var tagger_peer_id := client_id if host_is_runner else 1

	player = CharacterBody3D.new()
	player.name = "NetworkRunner"
	player.set_script(NetworkActorScript)
	player.configure("runner", runner_peer_id, runner_skin_id)
	add_child(player)
	player.global_position = _grounded_spawn_position(runner_spawn_position)

	tagger = CharacterBody3D.new()
	tagger.name = "NetworkTagger"
	tagger.set_script(NetworkActorScript)
	tagger.configure("tagger", tagger_peer_id, tagger_skin_id)
	add_child(tagger)
	tagger.global_position = _grounded_spawn_position(tagger_spawn_position)

func _clear_characters() -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	if tagger != null and is_instance_valid(tagger):
		tagger.queue_free()
	player = null
	tagger = null

func _close_network() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func _is_in_network_room() -> bool:
	return game_mode == "waiting" or game_mode == "lobby" or game_mode == "host" or game_mode == "client"

func _leave_room(message: String) -> void:
	is_leaving_room = true
	_close_network()
	_show_title(message)

func _local_role_text() -> String:
	if game_mode == "host":
		return ("你是逃跑者" if host_is_runner else "你是抓人者") + "，房主按 R 可重开"
	if game_mode == "client":
		return ("你是抓人者" if host_is_runner else "你是逃跑者") + "，房主按 R 可重开"
	return ""

func _local_is_tagger() -> bool:
	if game_mode == "host":
		return not host_is_runner
	if game_mode == "client":
		return host_is_runner
	return false

func _tagger_peer_id() -> int:
	if remote_peer_id == 0:
		return 1
	return remote_peer_id if host_is_runner else 1

func _ensure_default_fullscreen() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _grounded_spawn_position(base_position: Vector3) -> Vector3:
	if get_world_3d() == null:
		return base_position
	var from := base_position + Vector3.UP * 6.0
	var to := base_position + Vector3.DOWN * 20.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return base_position
	var point := hit.get("position", base_position) as Vector3
	return point + Vector3.UP * 0.08

func _request_local_catch_attempt() -> void:
	if tagger == null or not is_instance_valid(tagger):
		return
	var origin: Vector3 = tagger.get_catch_origin() if tagger.has_method("get_catch_origin") else tagger.global_position + Vector3.UP * 1.0
	var direction: Vector3 = tagger.get_catch_direction() if tagger.has_method("get_catch_direction") else -tagger.global_transform.basis.z
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_catch", origin, direction)
		return
	if _validate_catch_attempt(origin, direction, true):
		_on_player_caught()

@rpc("any_peer", "reliable")
func _rpc_request_catch(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _tagger_peer_id() or caught:
		return
	if _validate_catch_attempt(origin, direction, true):
		_on_player_caught()

func _try_ai_catch_attempt(flat_distance: float) -> void:
	if ai_catch_cooldown > 0.0 or flat_distance > CATCH_RANGE + 0.5:
		return
	if tagger.has_method("should_consume_ai_catch_attempt") and not tagger.should_consume_ai_catch_attempt():
		return
	ai_catch_cooldown = AI_CATCH_COOLDOWN
	var origin: Vector3 = tagger.get_catch_origin() if tagger.has_method("get_catch_origin") else tagger.global_position + Vector3.UP * 1.0
	var direction: Vector3 = tagger.get_catch_direction() if tagger.has_method("get_catch_direction") else -tagger.global_transform.basis.z
	if _validate_catch_attempt(origin, direction, false):
		_on_player_caught()

func _validate_catch_attempt(origin: Vector3, direction: Vector3, validate_origin: bool) -> bool:
	if player == null or tagger == null or not is_instance_valid(player) or not is_instance_valid(tagger):
		return false
	if direction.length_squared() < 0.001:
		return false
	direction = direction.normalized()
	if validate_origin:
		var expected_origin: Vector3 = tagger.global_position + Vector3.UP * 1.0
		if origin.distance_to(expected_origin) > CATCH_ORIGIN_TOLERANCE:
			return false
	var target: Vector3 = player.global_position + Vector3.UP * 0.85
	var to_target: Vector3 = target - origin
	var distance: float = to_target.length()
	if distance > CATCH_RANGE or distance < 0.1:
		return false
	if direction.dot(to_target.normalized()) < CATCH_AIM_DOT:
		return false
	return _has_clear_catch_line(origin, target)

func _has_clear_catch_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [tagger.get_rid(), player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func _on_runner_survived() -> void:
	caught = true
	player.is_control_locked = true
	tagger.is_active = false
	if game_mode == "single":
		center_label.text = "逃跑者胜利！\n成功坚持 %.2f 秒\n按 R 重新开始" % time_alive
	else:
		center_label.text = "本局结束\n逃跑者胜利！\n成功坚持 %.2f 秒\n%.0f 秒后返回房间并自动换边" % [time_alive, MULTIPLAYER_RESULT_DELAY]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_survived", time_alive)
		_schedule_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_survived(final_time: float) -> void:
	caught = true
	time_alive = final_time
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "本局结束\n逃跑者胜利！\n成功坚持 %.2f 秒\n等待房主返回房间并自动换边" % final_time
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_player_caught() -> void:
	_finish_runner_failed("逃跑者被抓到了！")

func _on_runner_fell() -> void:
	_finish_runner_failed("逃跑者掉出地图！")

func _finish_runner_failed(reason: String) -> void:
	caught = true
	player.is_control_locked = true
	tagger.is_active = false
	if game_mode == "single":
		center_label.text = "%s\n抓人者胜利\n坚持了 %.2f 秒\n按 R 重新开始" % [reason, time_alive]
	else:
		center_label.text = "本局结束\n%s\n抓人者胜利\n坚持了 %.2f 秒\n%.0f 秒后返回房间并自动换边" % [reason, time_alive, MULTIPLAYER_RESULT_DELAY]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_failed", time_alive, reason)
		_schedule_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_failed(final_time: float, reason: String) -> void:
	caught = true
	time_alive = final_time
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "本局结束\n%s\n抓人者胜利\n坚持了 %.2f 秒\n等待房主返回房间并自动换边" % [reason, final_time]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _setup_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.48, 0.78, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.9, 0.78)
	env.ambient_light_energy = 1.15
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 2.1
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	add_child(sun)

func _load_active_map() -> bool:
	if _load_map_from_path(selected_map_path):
		return true
	for map_path in _map_search_paths():
		if map_path == selected_map_path:
			continue
		if _load_map_from_path(map_path):
			return true
	_clear_map()
	map_root = Node3D.new()
	map_root.name = "LegacyBuiltinMap"
	add_child(map_root)
	_build_arena()
	map_name = "内置备用地图"
	active_map_path = "legacy_builtin"
	_update_map_ui()
	if debug_mode:
		_refresh_debug_collision_shapes()
	return true

func _load_map_from_path(map_path: String) -> bool:
	if map_path.is_empty() or not FileAccess.file_exists(map_path):
		return false
	_clear_map()
	runner_spawn_position = Vector3(-23.0, 0.12, 22.0)
	tagger_spawn_position = Vector3(23.0, 0.12, -22.0)
	var result: Dictionary = MapLoader.load_map(self, map_path)
	if not bool(result.get("ok", false)):
		push_warning("地图加载失败：%s" % String(result.get("error", map_path)))
		return false
	map_root = result.get("map_root", null) as Node3D
	map_name = String(result.get("name", "官方地图"))
	active_map_path = map_path
	runner_spawn_position = result.get("runner_spawn", runner_spawn_position)
	tagger_spawn_position = result.get("tagger_spawn", tagger_spawn_position)
	_update_map_ui()
	if debug_mode:
		_refresh_debug_collision_shapes()
	return true

func _clear_map() -> void:
	if map_root != null and is_instance_valid(map_root):
		if map_root.get_parent() != null:
			map_root.get_parent().remove_child(map_root)
		map_root.queue_free()
	map_root = null

func _map_search_paths() -> Array[String]:
	var paths: Array[String] = [DEFAULT_MAP_PATH, USER_MAP_PATH]
	var executable_dir := OS.get_executable_path().get_base_dir()
	if not executable_dir.is_empty():
		paths.append(executable_dir.path_join("maps").path_join("current_map.json"))
	return paths

func _toggle_debug_mode() -> void:
	debug_mode = not debug_mode
	_refresh_debug_collision_shapes()
	if title_status != null and title_layer != null and title_layer.visible:
		title_status.text = "Debug Mode：%s。按 F3 可切换碰撞箱显示。" % ["开启" if debug_mode else "关闭"]

func _refresh_debug_collision_shapes() -> void:
	_ensure_debug_materials()
	_update_debug_collision_shapes(self)

func _ensure_debug_materials() -> void:
	if debug_obstacle_material == null:
		debug_obstacle_material = StandardMaterial3D.new()
		debug_obstacle_material.albedo_color = Color(0.1, 0.75, 1.0, 0.28)
		debug_obstacle_material.emission_enabled = true
		debug_obstacle_material.emission = Color(0.05, 0.55, 1.0)
		debug_obstacle_material.emission_energy_multiplier = 0.28
		debug_obstacle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		debug_obstacle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_obstacle_material.no_depth_test = true
	if debug_actor_material == null:
		debug_actor_material = StandardMaterial3D.new()
		debug_actor_material.albedo_color = Color(1.0, 0.35, 0.08, 0.38)
		debug_actor_material.emission_enabled = true
		debug_actor_material.emission = Color(1.0, 0.22, 0.0)
		debug_actor_material.emission_energy_multiplier = 0.35
		debug_actor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		debug_actor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_actor_material.no_depth_test = true

func _update_debug_collision_shapes(node: Node) -> void:
	if node is CollisionShape3D:
		_sync_debug_collision_shape(node as CollisionShape3D)
	for child in node.get_children():
		if child.get_meta("debug_collision_visual", false):
			continue
		_update_debug_collision_shapes(child)

func _sync_debug_collision_shape(collision: CollisionShape3D) -> void:
	var visual := collision.get_node_or_null("DebugCollisionVisual") as MeshInstance3D
	if not debug_mode or collision.disabled or collision.shape == null:
		if visual != null:
			visual.visible = false
		return

	var mesh := _debug_mesh_from_shape(collision.shape)
	if mesh == null:
		if visual != null:
			visual.visible = false
		return

	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = "DebugCollisionVisual"
		visual.set_meta("debug_collision_visual", true)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		collision.add_child(visual)
	visual.transform = Transform3D.IDENTITY
	visual.mesh = mesh
	visual.material_override = debug_actor_material if _is_actor_collision(collision) else debug_obstacle_material
	visual.visible = true

func _debug_mesh_from_shape(shape: Shape3D) -> Mesh:
	if shape is BoxShape3D:
		var box_shape := shape as BoxShape3D
		var box_mesh := BoxMesh.new()
		box_mesh.size = box_shape.size
		return box_mesh
	if shape is SphereShape3D:
		var sphere_shape := shape as SphereShape3D
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = sphere_shape.radius
		sphere_mesh.height = sphere_shape.radius * 2.0
		return sphere_mesh
	if shape is CylinderShape3D:
		var cylinder_shape := shape as CylinderShape3D
		var cylinder_mesh := CylinderMesh.new()
		cylinder_mesh.top_radius = cylinder_shape.radius
		cylinder_mesh.bottom_radius = cylinder_shape.radius
		cylinder_mesh.height = cylinder_shape.height
		return cylinder_mesh
	if shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = capsule_shape.radius
		capsule_mesh.height = capsule_shape.height
		return capsule_mesh
	if shape is ConcavePolygonShape3D:
		var concave_shape := shape as ConcavePolygonShape3D
		var faces := concave_shape.get_faces()
		if faces.size() < 3:
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return array_mesh
	return null

func _is_actor_collision(collision: CollisionShape3D) -> bool:
	var current: Node = collision
	while current != null:
		if current is CharacterBody3D:
			return true
		current = current.get_parent()
	return false

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(14.0, 14.0)
	panel.custom_minimum_size = Vector2(610.0, 150.0)
	panel.add_theme_stylebox_override("panel", _cartoon_style(Color(1.0, 0.95, 0.72, 0.88), Color(0.12, 0.18, 0.36), 4, 18, Vector2(0.0, 5.0), 12))
	hud_layer.add_child(panel)

	var hud_margin := MarginContainer.new()
	hud_margin.add_theme_constant_override("margin_left", 14)
	hud_margin.add_theme_constant_override("margin_right", 14)
	hud_margin.add_theme_constant_override("margin_top", 10)
	hud_margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(hud_margin)

	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_color", Color(0.11, 0.16, 0.31))
	hud_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.72))
	hud_label.add_theme_constant_override("outline_size", 2)
	hud_label.text = ""
	hud_margin.add_child(hud_label)

	center_label = Label.new()
	center_label.anchor_right = 1.0
	center_label.anchor_bottom = 1.0
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 38)
	center_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.18))
	center_label.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.16))
	center_label.add_theme_constant_override("outline_size", 8)
	center_label.text = ""
	hud_layer.add_child(center_label)
	hud_layer.visible = false

func _build_arena() -> void:
	_add_box("Ground", Vector3(0.0, -0.15, 0.0), Vector3(64.0, 0.3, 64.0), Color(0.16, 0.18, 0.2))
	_add_box("NorthWall", Vector3(0.0, 1.6, -32.0), Vector3(64.0, 3.2, 0.8), Color(0.09, 0.1, 0.12))
	_add_box("SouthWall", Vector3(0.0, 1.6, 32.0), Vector3(64.0, 3.2, 0.8), Color(0.09, 0.1, 0.12))
	_add_box("WestWall", Vector3(-32.0, 1.6, 0.0), Vector3(0.8, 3.2, 64.0), Color(0.09, 0.1, 0.12))
	_add_box("EastWall", Vector3(32.0, 1.6, 0.0), Vector3(0.8, 3.2, 64.0), Color(0.09, 0.1, 0.12))

	_add_box("RampA", Vector3(-18.0, 1.75, -14.0), Vector3(9.0, 0.55, 11.0), Color(0.35, 0.38, 0.42), Vector3(deg_to_rad(18.0), 0.0, 0.0))
	_add_box("RampAPlatform", Vector3(-18.0, 3.38, -7.0), Vector3(10.5, 0.55, 5.5), Color(0.25, 0.28, 0.33))
	_add_box("RampB", Vector3(17.0, 1.55, 12.0), Vector3(8.0, 0.5, 10.0), Color(0.33, 0.36, 0.41), Vector3(deg_to_rad(-17.0), deg_to_rad(12.0), 0.0))
	_add_box("RampBPlatform", Vector3(18.3, 3.0, 5.8), Vector3(9.0, 0.5, 5.0), Color(0.25, 0.28, 0.33), Vector3(0.0, deg_to_rad(12.0), 0.0))
	_add_box("CenterSlope", Vector3(0.0, 1.25, 0.0), Vector3(11.0, 0.5, 8.0), Color(0.31, 0.34, 0.39), Vector3(0.0, 0.0, deg_to_rad(-14.0)))

	for i in range(8):
		var x := -21.0 + i * 6.0
		var z := 6.5 if i % 2 == 0 else -6.5
		_add_box("SlalomWall%d" % i, Vector3(x, 0.9, z), Vector3(1.2, 1.8, 8.0), Color(0.48, 0.29, 0.16), Vector3(0.0, deg_to_rad(8.0 if i % 2 == 0 else -8.0), 0.0))

	for i in range(12):
		var x := -26.0 + (i % 6) * 10.0
		var z := -24.0 + int(i / 6) * 48.0
		_add_box("VaultBlock%d" % i, Vector3(x, 0.55, z), Vector3(3.2, 1.1, 1.4), Color(0.18, 0.42, 0.46), Vector3(0.0, deg_to_rad(15.0 * ((i % 3) - 1)), 0.0))

	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var pos := Vector3(cos(angle) * 19.0, 1.25, sin(angle) * 19.0)
		_add_box("Pillar%d" % i, pos, Vector3(1.8, 2.5, 1.8), Color(0.42, 0.42, 0.48))

	_add_box("BalanceBeam1", Vector3(-6.0, 2.35, -20.0), Vector3(13.0, 0.45, 1.25), Color(0.55, 0.45, 0.24), Vector3(0.0, deg_to_rad(18.0), 0.0))
	_add_box("BalanceBeam2", Vector3(8.0, 2.1, 21.0), Vector3(14.0, 0.45, 1.25), Color(0.55, 0.45, 0.24), Vector3(0.0, deg_to_rad(-22.0), 0.0))
	_add_box("BridgeBlock1", Vector3(-4.5, 1.15, -15.0), Vector3(3.5, 2.3, 2.0), Color(0.32, 0.24, 0.2))
	_add_box("BridgeBlock2", Vector3(2.5, 1.15, -18.0), Vector3(3.5, 2.3, 2.0), Color(0.32, 0.24, 0.2))
	_add_box("BridgeBlock3", Vector3(11.5, 1.05, 16.5), Vector3(3.2, 2.1, 2.0), Color(0.32, 0.24, 0.2))
	_add_box("BridgeBlock4", Vector3(3.5, 1.05, 18.5), Vector3(3.2, 2.1, 2.0), Color(0.32, 0.24, 0.2))

	_add_box("StartPad", Vector3(-23.0, 0.03, 22.0), Vector3(4.0, 0.08, 4.0), Color(0.0, 0.32, 0.75))
	_add_box("TaggerPad", Vector3(23.0, 0.03, -22.0), Vector3(4.0, 0.08, 4.0), Color(0.75, 0.05, 0.02))

func _add_box(name: String, position: Vector3, size: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = position
	body.rotation = rotation
	if map_root != null and is_instance_valid(map_root):
		map_root.add_child(body)
	else:
		add_child(body)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)
	return body

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	return mat

func _ensure_input_actions() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_forward", KEY_UP)
	_bind_key("move_back", KEY_S)
	_bind_key("move_back", KEY_DOWN)
	_bind_key("move_left", KEY_A)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_D)
	_bind_key("move_right", KEY_RIGHT)
	_bind_key("jump", KEY_SPACE)
	_bind_key("restart", KEY_R)
	_bind_key("quit_room", KEY_Q)
	_bind_key("toggle_debug", KEY_F3)
	_bind_mouse_button("catch_attack", MOUSE_BUTTON_LEFT)

func _bind_key(action_name: String, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.keycode == keycode:
			return
	var key := InputEventKey.new()
	key.keycode = keycode
	InputMap.action_add_event(action_name, key)

func _bind_mouse_button(action_name: String, button_index: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		if event is InputEventMouseButton and event.button_index == button_index:
			return
	var mouse_button := InputEventMouseButton.new()
	mouse_button.button_index = button_index
	InputMap.action_add_event(action_name, mouse_button)
