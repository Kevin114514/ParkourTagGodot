extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const RunnerAIScript = preload("res://scripts/runner_ai.gd")
const TaggerScript = preload("res://scripts/tagger.gd")
const RLPolicyTaggerScript = preload("res://scripts/rl_policy_tagger.gd")
const NetworkActorScript = preload("res://scripts/network_actor.gd")
const MapLoader = preload("res://scripts/map_loader.gd")
const SkinAPI = preload("res://scripts/skin_api.gd")
const PORT = 24591
# 发布/功能变更时请同步更新该版本号；主界面右下角会显示它。
const GAME_VERSION := "1.0"
const CUSTOM_SKIN_OPTION_ID := "__custom_image_skin__"
const USE_RL_POLICY_TAGGER := true
const VOID_Y = -12.0
const DEFAULT_MAP_PATH = "res://maps/default_arena.json"
const USER_MAP_PATH = "user://maps/current_map.json"
const NETWORK_SYNC_MAP_PATH = "user://network_sync/maps/host_map.json"
const NETWORK_SYNC_SKIN_PREFIX = "network_host_"
const MULTIPLAYER_RESULT_DELAY := 3.0
const CATCH_RANGE := 2.5
const CATCH_COOLDOWN := 1.5
const CATCH_HALF_ANGLE_COS := 0.0
const AI_CATCH_COOLDOWN := CATCH_COOLDOWN
const CATCH_ORIGIN_TOLERANCE := 2.2
const THROWABLE_RESPAWN_TARGET := 5
const THROWABLE_RESPAWN_INTERVAL := 5.0
const THROWABLE_PICKUP_RANGE := 2.1
const THROWABLE_THROW_SPEED := 20.0
const THROWABLE_THROW_UPWARD_BONUS := 1.6
const THROWABLE_PROJECTILE_GRAVITY := 16.0
const THROWABLE_PROJECTILE_RADIUS := 0.95
const THROWABLE_PROJECTILE_LIFETIME := 3.4
const THROWABLE_SLOW_MULTIPLIER := 0.58
const THROWABLE_SLOW_DURATION := 2.6
const THROWABLE_MIN_SPAWN_GAP := 4.5
const THROWABLE_SPAWN_ATTEMPTS := 32
const THROWABLE_THROW_ORIGIN_TOLERANCE := 2.4
const THROWABLE_TRAJECTORY_STEPS := 34
const THROWABLE_TRAJECTORY_STEP_TIME := 0.065
const THROWABLE_TRAJECTORY_DOT_COUNT := 14
const THROWABLE_HAND_OFFSET := Vector3(0.44, 1.05, -0.16)
const THROWABLE_AI_PICKUP_RANGE := 2.25
const THROWABLE_AI_THROW_COOLDOWN := 1.15
const THROWABLE_AI_THROW_MIN_DISTANCE := 4.0
const THROWABLE_AI_THROW_MAX_DISTANCE := 17.5
const THROWABLE_NOTICE_DURATION := 2.2
const THROWABLE_PICKUP_NOTICE_PROTECT := 1.15
const TAGGER_HITS_TO_WIN := 10
const SLOW_PARTICLE_MOVE_THRESHOLD := 0.18
const ACTION_CONFIRM_DURATION := 2.0
const OPPONENT_MINIMAP_MEMORY := 5.0
const OPPONENT_SIGHT_RANGE := 28.0
const RUNNER_THREAT_RED_DISTANCE := 8.0
const MINIMAP_WORLD_RADIUS := 42.0
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
	},
	{
		"name": "林地废墟",
		"path": "res://maps/woodland_mansion.json",
		"description": "高墙木质三层废墟：整齐房间、双向楼梯、环形走廊、家具翻越点和高风险捷径。"
	},
	{
		"name": "沙漠神殿",
		"path": "res://maps/desert_temple.json",
		"description": "更大规模的三层砂岩神殿：二层大厅出生，中心旋转楼梯直达一层藏宝室，两侧阶梯可登上圆形穹顶。"
	},
	{
		"name": "森林小岛（外海+内湖）",
		"path": "res://maps/forest_island_map.json",
		"description": "森林小岛地图：使用 3D 森林岛屿模型，包含外海、内湖和开阔追逐空间。"
	}
]

var player
var tagger
var hud_layer: CanvasLayer
var hud_label: Label
var center_label: Label
var throwable_notice_label: Label
var catch_cd_label: Label
var direction_marker_label: Label
var threat_overlay: ColorRect
var minimap_panel: PanelContainer
var minimap_content: Control
var minimap_opponent_dot: ColorRect
var minimap_player_dot: ColorRect
var minimap_reward_dots: Array[ColorRect] = []
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
var image_skin_file_dialog: FileDialog
var pending_image_skin_role := "runner"
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
var catch_cooldown_remaining := 0.0
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
@export var runner_skin_id := "chair"
@export var tagger_skin_id := "irris"
var selected_camera_mode := "first_person"
var runner_spawn_position := Vector3(-23.0, 0.12, 22.0)
var tagger_spawn_position := Vector3(23.0, 0.12, -22.0)

var throwable_root: Node3D
var throwable_trajectory: MeshInstance3D
var throwable_trajectory_dots: Node3D
var throwable_landing_marker: MeshInstance3D
var held_throwable_visual: Node3D
var ground_throwables: Dictionary = {}
var flying_throwables: Dictionary = {}
var runner_has_throwable := false
var throwable_respawn_timer := THROWABLE_RESPAWN_INTERVAL
var next_ground_throwable_id := 1
var next_flying_throwable_id := 1
var throwable_notice_timer := 0.0
var throwable_notice_protect_timer := 0.0
var tagger_slow_particles: Node3D
var tagger_slow_particle_timer := 0.0
var tagger_slow_particle_elapsed := 0.0
var tagger_slow_particle_last_position := Vector3.ZERO
var tagger_hit_count := 0
var ai_runner_throw_cooldown := 0.0
var quit_confirm_timer := 0.0
var restart_confirm_timer := 0.0
var opponent_seen_timer := 0.0
var last_seen_opponent_position := Vector3.ZERO

func _ready() -> void:
	randomize()
	_ensure_default_fullscreen()
	_ensure_input_actions()
	_connect_multiplayer_signals()
	_setup_world()
	_load_active_map()
	_build_hud()
	_build_title_ui()
	_show_title("")

func _process(delta: float) -> void:
	quit_confirm_timer = maxf(quit_confirm_timer - delta, 0.0)
	restart_confirm_timer = maxf(restart_confirm_timer - delta, 0.0)
	if center_label != null and quit_confirm_timer <= 0.0 and restart_confirm_timer <= 0.0 and (center_label.text == "再按一次 Q 返回标题/房间" or center_label.text == "再按一次 R 重新开始本局"):
		center_label.text = ""
	if Input.is_action_just_pressed("quit_room"):
		if game_mode == "single" or game_mode == "single_chase":
			if not _confirm_round_action("quit"):
				return
			_show_title("")
			return
		if game_mode == "host":
			if not _confirm_round_action("quit"):
				return
			_return_active_round_to_lobby("房主已返回房间等待页面。")
			return
		if game_mode == "client":
			if not _confirm_round_action("quit"):
				return
			rpc_id(1, "_rpc_request_return_to_lobby")
			if center_label != null:
				center_label.text = "正在返回房间等待页面..."
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
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
		if game_mode == "single" or game_mode == "single_chase" or game_mode == "host":
			if not _confirm_round_action("restart"):
				return
		if game_mode == "single":
			_start_single_game()
		elif game_mode == "single_chase":
			_start_single_chase_game()
		elif game_mode == "host" and remote_peer_id != 0:
			_start_synced_network_round()
		return

	if caught:
		_hide_throwable_trajectory()
		if minimap_panel != null:
			minimap_panel.visible = false
		return

	if (game_mode == "single" or game_mode == "single_chase" or game_mode == "host") and player.global_position.y < VOID_Y:
		_on_runner_fell()
		return

	time_alive += delta
	ai_catch_cooldown = maxf(ai_catch_cooldown - delta, 0.0)
	catch_cooldown_remaining = maxf(catch_cooldown_remaining - delta, 0.0)
	_update_throwables(delta)
	_update_ai_runner_throwable_strategy(delta)
	_update_held_throwable_visual()
	_update_throwable_notice(delta)
	_update_throwable_trajectory()
	_update_tagger_slow_particles(delta)
	var catch_offset: Vector3 = player.global_position - tagger.global_position
	catch_offset.y = 0.0
	var distance: float = catch_offset.length()
	if hud_label != null:
		hud_label.text = ""
	_update_catch_crosshair()
	_update_direction_marker()
	_update_threat_overlay(distance)
	_update_minimap(delta)

	if _local_is_runner() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("pickup_item"):
			_request_local_throwable_pickup()
		if Input.is_action_just_pressed("throw_item"):
			_request_local_throwable_throw()

	if _local_is_tagger() and Input.is_action_just_pressed("catch_attack") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_request_local_catch_attempt()

	if game_mode == "single":
		_try_ai_catch_attempt(distance)

func _confirm_round_action(action: String) -> bool:
	if center_label == null:
		return true
	if caught:
		return true
	if action == "restart":
		if restart_confirm_timer <= 0.0:
			restart_confirm_timer = ACTION_CONFIRM_DURATION
			center_label.text = "再按一次 R 重新开始本局"
			return false
		restart_confirm_timer = 0.0
		center_label.text = ""
		return true
	if action == "quit":
		if quit_confirm_timer <= 0.0:
			quit_confirm_timer = ACTION_CONFIRM_DURATION
			center_label.text = "再按一次 Q 返回标题/房间"
			return false
		quit_confirm_timer = 0.0
		center_label.text = ""
		return true
	return true

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
	title.text = "椅子大逃亡 2.0"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.43, 0.14))
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.18, 0.32))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

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
	runner_skin_label.text = "躲藏者皮肤"
	_apply_label_style(runner_skin_label)
	skin_row.add_child(runner_skin_label)

	runner_skin_option = OptionButton.new()
	runner_skin_option.custom_minimum_size = Vector2(130.0, 42.0)
	_style_button(runner_skin_option, Color(0.15, 0.61, 1.0), Color(0.06, 0.29, 0.58))
	runner_skin_option.item_selected.connect(Callable(self, "_on_runner_skin_selected"))
	skin_row.add_child(runner_skin_option)

	var tagger_skin_label := Label.new()
	tagger_skin_label.text = "追逐者皮肤"
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
	runner_preview_title.text = "躲藏者预览"
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
	tagger_preview_title.text = "追逐者预览"
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

	image_skin_file_dialog = FileDialog.new()
	image_skin_file_dialog.title = "选择一张图片作为模型"
	image_skin_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	image_skin_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	image_skin_file_dialog.use_native_dialog = true
	image_skin_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 图片文件"])
	image_skin_file_dialog.file_selected.connect(Callable(self, "_on_image_skin_file_selected"))
	title_layer.add_child(image_skin_file_dialog)

	var single_button := Button.new()
	single_button.text = "单人模式：躲藏者 VS AI 追逐者"
	_style_button(single_button, Color(1.0, 0.52, 0.17), Color(0.64, 0.23, 0.06))
	single_button.pressed.connect(Callable(self, "_start_single_game"))
	box.add_child(single_button)
	menu_controls.append(single_button)

	var single_chase_button := Button.new()
	single_chase_button.text = "单人模式：追逐者 VS AI 躲藏者"
	_style_button(single_chase_button, Color(0.9, 0.28, 0.2), Color(0.48, 0.08, 0.06))
	single_chase_button.pressed.connect(Callable(self, "_start_single_chase_game"))
	box.add_child(single_chase_button)
	menu_controls.append(single_chase_button)

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
		elif game_mode == "single_chase" and actor == tagger:
			actor.set_camera_mode(selected_camera_mode)
		elif game_mode != "single" and game_mode != "single_chase" and int(actor.get("owner_peer_id")) == local_peer:
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
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "房间规则已同步，等待房主开始游戏。")
	_update_lobby_ui()

func _refresh_win_time_from_ui() -> void:
	if win_time_spinbox != null:
		win_time_seconds = win_time_spinbox.value

func _refresh_skin_options() -> void:
	available_skin_ids = SkinAPI.list_available_skin_ids()
	if available_skin_ids.is_empty():
		available_skin_ids = [SkinAPI.DEFAULT_SKIN_ID]
	if not available_skin_ids.has(runner_skin_id):
		runner_skin_id = SkinAPI.DEFAULT_SKIN_ID
	if not available_skin_ids.has(tagger_skin_id):
		tagger_skin_id = SkinAPI.DEFAULT_SKIN_ID

	if runner_skin_option != null:
		runner_skin_option.clear()
		for skin in available_skin_ids:
			runner_skin_option.add_item(SkinAPI.get_skin_display_name(skin))
		runner_skin_option.add_separator()
		runner_skin_option.add_item("自定义图片皮肤...")
		var idx := available_skin_ids.find(runner_skin_id)
		runner_skin_option.select(maxi(idx, 0))

	if tagger_skin_option != null:
		tagger_skin_option.clear()
		for skin in available_skin_ids:
			tagger_skin_option.add_item(SkinAPI.get_skin_display_name(skin))
		tagger_skin_option.add_separator()
		tagger_skin_option.add_item("自定义图片皮肤...")
		var idx2 := available_skin_ids.find(tagger_skin_id)
		tagger_skin_option.select(maxi(idx2, 0))

	_update_skin_previews()

func _update_skin_previews() -> void:
	if runner_skin_preview != null:
		runner_skin_preview.texture = SkinAPI.get_skin_preview_texture(runner_skin_id, "runner")
	if runner_skin_preview_label != null:
		runner_skin_preview_label.text = "当前：%s" % SkinAPI.get_skin_display_name(runner_skin_id)

	if tagger_skin_preview != null:
		tagger_skin_preview.texture = SkinAPI.get_skin_preview_texture(tagger_skin_id, "tagger")
	if tagger_skin_preview_label != null:
		tagger_skin_preview_label.text = "当前：%s" % SkinAPI.get_skin_display_name(tagger_skin_id)

func _on_runner_skin_selected(index: int) -> void:
	if index == available_skin_ids.size() + 1:
		pending_image_skin_role = "runner"
		_update_skin_previews()
		_open_image_skin_dialog()
		return
	if index < 0 or index >= available_skin_ids.size():
		_refresh_skin_options()
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

func _open_image_skin_dialog() -> void:
	if image_skin_file_dialog == null:
		return
	image_skin_file_dialog.popup_centered_ratio(0.55)

func _on_image_skin_file_selected(path: String) -> void:
	var uploaded_skin_id := SkinAPI.create_uploaded_image_skin(path)
	if uploaded_skin_id.is_empty():
		if title_status != null:
			title_status.text = "图片皮肤导入失败，请选择 PNG / JPG / WEBP 图片。"
		return
	if pending_image_skin_role == "tagger":
		tagger_skin_id = uploaded_skin_id
	else:
		runner_skin_id = uploaded_skin_id
	_refresh_skin_options()
	_update_skin_previews()
	if title_status != null:
		title_status.text = "已选择自定义图片皮肤：%s。" % ["追逐者" if pending_image_skin_role == "tagger" else "躲藏者"]

func _show_title(message: String) -> void:
	_close_network()
	_clear_characters()
	_clear_all_throwables()
	game_mode = "title"
	network_started = false
	remote_peer_id = 0
	host_is_runner = true
	caught = false
	ai_catch_cooldown = 0.0
	catch_cooldown_remaining = 0.0
	time_alive = 0.0
	tagger_hit_count = 0
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
	catch_cooldown_remaining = 0.0
	time_alive = 0.0
	tagger_hit_count = 0
	title_layer.visible = false
	hud_layer.visible = true
	center_label.text = ""
	_spawn_single_characters()
	_prepare_throwable_round_state()
	_apply_camera_mode_to_local_actor()
	call_deferred("_apply_camera_mode_to_local_actor")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _start_single_chase_game() -> void:
	_refresh_win_time_from_ui()
	_close_network()
	_clear_characters()
	if not _load_active_map():
		if title_status != null:
			title_status.text = "地图加载失败，无法开始游戏。"
		return
	game_mode = "single_chase"
	caught = false
	ai_catch_cooldown = 0.0
	catch_cooldown_remaining = 0.0
	time_alive = 0.0
	tagger_hit_count = 0
	title_layer.visible = false
	hud_layer.visible = true
	center_label.text = ""
	_spawn_single_chase_characters()
	_prepare_throwable_round_state()
	_apply_camera_mode_to_local_actor()
	call_deferred("_apply_camera_mode_to_local_actor")
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
	var other_role := "追逐者" if local_role == "躲藏者" else "躲藏者"
	lobby_role_label.text = "你的角色：%s\n对方角色：%s\n通关条件：躲藏者击中追逐者 %d 次\n地图：%s\n视角：%s（房主选择）\n按 Q 退出房间" % [local_role, other_role, TAGGER_HITS_TO_WIN, map_name, _camera_mode_display_name()]
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

func _return_active_round_to_lobby(message: String) -> void:
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	caught = false
	ai_catch_cooldown = 0.0
	catch_cooldown_remaining = 0.0
	time_alive = 0.0
	tagger_hit_count = 0
	_enter_lobby(message)
	rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, message)

@rpc("any_peer", "reliable")
func _rpc_request_return_to_lobby() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	_return_active_round_to_lobby("玩家已返回房间等待页面。")

func _local_lobby_role_text() -> String:
	var is_host := multiplayer.is_server()
	var local_is_runner := host_is_runner if is_host else not host_is_runner
	return "躲藏者" if local_is_runner else "追逐者"

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
	_start_synced_network_round()

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

func _start_synced_network_round() -> void:
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	_refresh_win_time_from_ui()
	var payload := _build_network_start_payload()
	_start_network_round(remote_peer_id)
	rpc("_rpc_begin_network_round", payload)

func _build_network_start_payload() -> Dictionary:
	return {
		"client_id": remote_peer_id,
		"host_is_runner": host_is_runner,
		"win_time_seconds": win_time_seconds,
		"selected_camera_mode": selected_camera_mode,
		"selected_map_index": selected_map_index,
		"map": _build_map_sync_payload(),
		"runner_skin": _build_skin_sync_payload(runner_skin_id),
		"tagger_skin": _build_skin_sync_payload(tagger_skin_id)
	}

func _build_map_sync_payload() -> Dictionary:
	var map_path := selected_map_path
	if map_path.is_empty():
		map_path = active_map_path
	var map_text := _read_text_file(map_path)
	var files: Array = []
	_collect_map_referenced_files(map_path, map_text, files)
	return {
		"index": selected_map_index,
		"path": map_path,
		"name": map_name,
		"text": map_text,
		"files": files
	}

func _build_skin_sync_payload(skin_id: String) -> Dictionary:
	var payload := {
		"id": skin_id,
		"files": []
	}
	var candidate_roots: Array[String] = [SkinAPI.USER_SKIN_ROOT, SkinAPI.RESOURCE_SKIN_ROOT]
	var executable_dir := OS.get_executable_path().get_base_dir()
	if not executable_dir.is_empty():
		candidate_roots.append(executable_dir.path_join("skins"))
	for root in candidate_roots:
		var skin_dir := "%s/%s" % [root, skin_id]
		if DirAccess.open(skin_dir) == null:
			continue
		var files: Array = []
		_collect_sync_files(skin_dir, "", files)
		payload["files"] = files
		return payload
	return payload

func _collect_sync_files(root: String, relative_dir: String, files: Array) -> void:
	var dir_path := root if relative_dir.is_empty() else root.path_join(relative_dir)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var relative_path := entry if relative_dir.is_empty() else relative_dir.path_join(entry)
			if dir.current_is_dir():
				_collect_sync_files(root, relative_path, files)
			else:
				var file_path := root.path_join(relative_path)
				var file := FileAccess.open(file_path, FileAccess.READ)
				if file != null:
					files.append({"path": relative_path, "data": file.get_buffer(file.get_length())})
					file.close()
		entry = dir.get_next()
	dir.list_dir_end()

func _collect_map_referenced_files(map_path: String, map_text: String, files: Array) -> void:
	if map_path.is_empty() or map_text.is_empty():
		return
	var parsed = JSON.parse_string(map_text)
	if parsed == null:
		return
	var seen := {}
	_collect_map_refs_recursive(parsed, map_path.get_base_dir(), files, seen)

func _collect_map_refs_recursive(value, base_dir: String, files: Array, seen: Dictionary) -> void:
	if value is Dictionary:
		var dict := value as Dictionary
		for key in dict.keys():
			var child = dict[key]
			var key_text := String(key)
			if child is String and (key_text == "path" or key_text == "texture" or key_text == "normal_texture"):
				_append_sync_file(base_dir, String(child), files, seen)
			_collect_map_refs_recursive(child, base_dir, files, seen)
	elif value is Array:
		for child in value:
			_collect_map_refs_recursive(child, base_dir, files, seen)

func _append_sync_file(base_dir: String, relative_path: String, files: Array, seen: Dictionary) -> void:
	var rel := relative_path.strip_edges().replace("\\", "/")
	if not _is_safe_relative_path(rel):
		return
	var file_path := base_dir.path_join(rel)
	if seen.has(file_path) or not FileAccess.file_exists(file_path):
		return
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return
	files.append({"path": rel, "data": file.get_buffer(file.get_length())})
	file.close()
	seen[file_path] = true

@rpc("call_remote", "reliable")
func _rpc_begin_network_round(payload: Dictionary) -> void:
	_apply_network_start_payload(payload)
	_start_network_round(remote_peer_id)

func _apply_network_start_payload(payload: Dictionary) -> void:
	remote_peer_id = int(payload.get("client_id", remote_peer_id))
	host_is_runner = bool(payload.get("host_is_runner", host_is_runner))
	win_time_seconds = float(payload.get("win_time_seconds", win_time_seconds))
	selected_camera_mode = "first_person" if String(payload.get("selected_camera_mode", selected_camera_mode)) == "first_person" else "third_person"
	selected_map_index = int(payload.get("selected_map_index", selected_map_index))
	var map_payload = payload.get("map", {})
	if map_payload is Dictionary:
		_apply_network_map_payload(map_payload as Dictionary)
	var runner_skin_payload = payload.get("runner_skin", {})
	if runner_skin_payload is Dictionary:
		runner_skin_id = _apply_network_skin_payload(runner_skin_payload as Dictionary)
	var tagger_skin_payload = payload.get("tagger_skin", {})
	if tagger_skin_payload is Dictionary:
		tagger_skin_id = _apply_network_skin_payload(tagger_skin_payload as Dictionary)
	_refresh_skin_options()
	if win_time_spinbox != null:
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	network_started = true

func _apply_network_map_payload(payload: Dictionary) -> void:
	var max_map_index := maxi(OFFICIAL_MAPS.size() - 1, 0)
	selected_map_index = clampi(int(payload.get("index", selected_map_index)), 0, max_map_index)
	map_preview_index = selected_map_index
	map_name = String(payload.get("name", map_name))
	var host_path := String(payload.get("path", ""))
	var map_text := String(payload.get("text", ""))
	var raw_files = payload.get("files", [])
	if raw_files is Array:
		_write_sync_files(NETWORK_SYNC_MAP_PATH.get_base_dir(), raw_files as Array)
	if not map_text.is_empty() and _write_text_file(NETWORK_SYNC_MAP_PATH, map_text):
		selected_map_path = NETWORK_SYNC_MAP_PATH
		return
	if host_path.begins_with("res://") and FileAccess.file_exists(host_path):
		selected_map_path = host_path
		return
	if FileAccess.file_exists(host_path):
		selected_map_path = host_path
		return
	selected_map_path = String(OFFICIAL_MAPS[selected_map_index].get("path", DEFAULT_MAP_PATH))

func _apply_network_skin_payload(payload: Dictionary) -> String:
	var source_skin_id := String(payload.get("id", SkinAPI.DEFAULT_SKIN_ID)).strip_edges()
	if source_skin_id.is_empty():
		source_skin_id = SkinAPI.DEFAULT_SKIN_ID
	var raw_files = payload.get("files", [])
	if not (raw_files is Array):
		return source_skin_id
	var files := raw_files as Array
	if files.is_empty():
		return source_skin_id
	var synced_skin_id := NETWORK_SYNC_SKIN_PREFIX + _safe_sync_name(source_skin_id)
	var skin_dir := "%s/%s" % [SkinAPI.USER_SKIN_ROOT, synced_skin_id]
	if not _ensure_user_dir(skin_dir):
		return source_skin_id
	for raw_file in files:
		if not (raw_file is Dictionary):
			continue
		var file_entry := raw_file as Dictionary
		var relative_path := String(file_entry.get("path", "")).replace("\\", "/")
		if not _is_safe_relative_path(relative_path):
			continue
		var data = file_entry.get("data", PackedByteArray())
		if not (data is PackedByteArray):
			continue
		var target_path := skin_dir.path_join(relative_path)
		if not _ensure_user_dir(target_path.get_base_dir()):
			continue
		var file := FileAccess.open(target_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(data)
			file.close()
	return synced_skin_id

func _write_sync_files(target_root: String, files: Array) -> void:
	if not _ensure_user_dir(target_root):
		return
	for raw_file in files:
		if not (raw_file is Dictionary):
			continue
		var file_entry := raw_file as Dictionary
		var relative_path := String(file_entry.get("path", "")).replace("\\", "/")
		if not _is_safe_relative_path(relative_path):
			continue
		var data = file_entry.get("data", PackedByteArray())
		if not (data is PackedByteArray):
			continue
		var target_path := target_root.path_join(relative_path)
		if not _ensure_user_dir(target_path.get_base_dir()):
			continue
		var file := FileAccess.open(target_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(data)
			file.close()

func _read_text_file(file_path: String) -> String:
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _write_text_file(file_path: String, text: String) -> bool:
	if file_path.is_empty():
		return false
	if not _ensure_user_dir(file_path.get_base_dir()):
		return false
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true

func _ensure_user_dir(dir_path: String) -> bool:
	if dir_path.is_empty():
		return false
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path)) == OK

func _safe_sync_name(source: String) -> String:
	var safe := source.strip_edges().replace("\\", "_").replace("/", "_").replace(":", "_").replace(".", "_")
	return safe if not safe.is_empty() else SkinAPI.DEFAULT_SKIN_ID

func _is_safe_relative_path(relative_path: String) -> bool:
	return not relative_path.is_empty() and not relative_path.begins_with("/") and not relative_path.contains(":") and not relative_path.contains("..")

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
	catch_cooldown_remaining = 0.0
	time_alive = 0.0
	tagger_hit_count = 0
	if title_layer != null:
		title_layer.visible = false
	hud_layer.visible = true
	center_label.text = ""
	_spawn_network_characters(client_id)
	_prepare_throwable_round_state()
	_apply_camera_mode_to_local_actor()
	call_deferred("_apply_camera_mode_to_local_actor")
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

func _spawn_single_chase_characters() -> void:
	player = CharacterBody3D.new()
	player.name = "AIRunner"
	player.set_script(RunnerAIScript)
	player.skin_id = runner_skin_id
	add_child(player)
	player.global_position = _grounded_spawn_position(runner_spawn_position)

	tagger = CharacterBody3D.new()
	tagger.name = "PlayerTagger"
	tagger.set_script(NetworkActorScript)
	tagger.configure("tagger", 1, tagger_skin_id)
	add_child(tagger)
	tagger.global_position = _grounded_spawn_position(tagger_spawn_position)
	player.target = tagger
	player.target_last_position = tagger.global_position

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
		return ("你是躲藏者" if host_is_runner else "你是追逐者") + "，房主按 R 可重开"
	if game_mode == "client":
		return ("你是追逐者" if host_is_runner else "你是躲藏者") + "，房主按 R 可重开"
	return ""

func _local_controlled_actor() -> Node3D:
	var actor: Node3D = null
	if game_mode == "single":
		actor = player as Node3D
	elif game_mode == "single_chase":
		actor = tagger as Node3D
	elif game_mode == "host":
		actor = player as Node3D
		if not host_is_runner:
			actor = tagger as Node3D
	elif game_mode == "client":
		actor = tagger as Node3D
		if not host_is_runner:
			actor = player as Node3D
	return actor if actor != null and is_instance_valid(actor) else null

func _local_is_tagger() -> bool:
	if game_mode == "single_chase":
		return true
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
	if tagger == null or not is_instance_valid(tagger) or catch_cooldown_remaining > 0.0:
		return
	var origin: Vector3 = tagger.get_catch_origin() if tagger.has_method("get_catch_origin") else tagger.global_position + Vector3.UP * 1.0
	var direction: Vector3 = tagger.get_catch_direction() if tagger.has_method("get_catch_direction") else -tagger.global_transform.basis.z
	catch_cooldown_remaining = CATCH_COOLDOWN
	_play_catch_effect(origin, direction)
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_catch", origin, direction)
		return
	_broadcast_catch_effect(origin, direction)
	if _validate_catch_attempt(origin, direction, true):
		_on_player_caught()

@rpc("any_peer", "reliable")
func _rpc_request_catch(origin: Vector3, direction: Vector3) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender_id != _tagger_peer_id() or caught or catch_cooldown_remaining > 0.0:
		return
	catch_cooldown_remaining = CATCH_COOLDOWN
	_play_catch_effect(origin, direction)
	if _validate_catch_attempt(origin, direction, true):
		_on_player_caught()

@rpc("call_remote", "unreliable")
func _rpc_play_catch_effect(origin: Vector3, direction: Vector3) -> void:
	_play_catch_effect(origin, direction)

func _broadcast_catch_effect(origin: Vector3, direction: Vector3) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_play_catch_effect", origin, direction)

func _try_ai_catch_attempt(flat_distance: float) -> void:
	if ai_catch_cooldown > 0.0 or flat_distance > CATCH_RANGE + 0.5:
		return
	if tagger.has_method("should_consume_ai_catch_attempt") and not tagger.should_consume_ai_catch_attempt():
		return
	ai_catch_cooldown = AI_CATCH_COOLDOWN
	var origin: Vector3 = tagger.get_catch_origin() if tagger.has_method("get_catch_origin") else tagger.global_position + Vector3.UP * 1.0
	var direction: Vector3 = tagger.get_catch_direction() if tagger.has_method("get_catch_direction") else -tagger.global_transform.basis.z
	_play_catch_effect(origin, direction)
	if _validate_catch_attempt(origin, direction, false):
		_on_player_caught()

func _validate_catch_attempt(origin: Vector3, direction: Vector3, validate_origin: bool) -> bool:
	if player == null or tagger == null or not is_instance_valid(player) or not is_instance_valid(tagger):
		return false
	var forward := _horizontal_dir(direction)
	if forward.length_squared() < 0.001:
		return false
	if validate_origin:
		var expected_origin: Vector3 = tagger.global_position + Vector3.UP * 1.0
		if origin.distance_to(expected_origin) > CATCH_ORIGIN_TOLERANCE:
			return false
	var target: Vector3 = player.global_position + Vector3.UP * 0.85
	var flat_to_target: Vector3 = player.global_position - tagger.global_position
	flat_to_target.y = 0.0
	var flat_distance: float = flat_to_target.length()
	var vertical_distance: float = absf(player.global_position.y - tagger.global_position.y)
	if flat_distance > CATCH_RANGE or flat_distance < 0.1 or vertical_distance > 2.25:
		return false
	if forward.dot(flat_to_target.normalized()) < CATCH_HALF_ANGLE_COS:
		return false
	return _has_clear_catch_line(origin, target)

func _horizontal_dir(direction: Vector3) -> Vector3:
	var flat := direction
	flat.y = 0.0
	return flat.normalized() if flat.length_squared() > 0.001 else Vector3.ZERO

func _has_clear_catch_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [tagger.get_rid(), player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func _play_catch_effect(origin: Vector3, direction: Vector3) -> void:
	var forward := _horizontal_dir(direction)
	if forward.length_squared() < 0.001:
		forward = -tagger.global_transform.basis.z.normalized() if tagger != null and is_instance_valid(tagger) else Vector3.FORWARD
		forward.y = 0.0
		forward = forward.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var base_position: Vector3 = tagger.global_position if tagger != null and is_instance_valid(tagger) else origin
	base_position.y += 0.08

	var effect_root := Node3D.new()
	effect_root.name = "CatchSemicircleEffect"
	effect_root.global_position = base_position
	add_child(effect_root)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SemicircleMesh"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 28
	var inner_radius := 0.28
	for i in range(segments + 1):
		var t := -PI * 0.5 + PI * float(i) / float(segments)
		var radial := forward * cos(t) + right * sin(t)
		vertices.append(radial * inner_radius)
		vertices.append(radial * CATCH_RANGE)
	for i in range(segments):
		var a := i * 2
		indices.append(a)
		indices.append(a + 1)
		indices.append(a + 3)
		indices.append(a)
		indices.append(a + 3)
		indices.append(a + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.05, 0.02, 0.34)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.02, 0.0)
	material.emission_energy_multiplier = 0.85
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	mesh_instance.material_override = material
	effect_root.add_child(mesh_instance)

	var tween := create_tween()
	effect_root.scale = Vector3(0.82, 0.82, 0.82)
	tween.tween_property(effect_root, "scale", Vector3.ONE, 0.08)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.22)
	await get_tree().create_timer(0.24).timeout
	if is_instance_valid(effect_root):
		effect_root.queue_free()

func _on_runner_survived() -> void:
	caught = true
	_update_catch_crosshair()
	_clear_tagger_slow_particles()
	player.is_control_locked = true
	tagger.is_active = false
	if game_mode == "single":
		center_label.text = "躲藏者胜利！\n已击中追逐者 %d 次\n用时 %.2f 秒\n按 R 重新开始" % [tagger_hit_count, time_alive]
	elif game_mode == "single_chase":
		center_label.text = "AI 躲藏者胜利！\n它击中追逐者 %d 次\n用时 %.2f 秒\n按 R 重新挑战" % [tagger_hit_count, time_alive]
	else:
		center_label.text = "本局结束\n躲藏者胜利！\n已击中追逐者 %d 次\n用时 %.2f 秒\n%.0f 秒后返回房间并自动换边" % [tagger_hit_count, time_alive, MULTIPLAYER_RESULT_DELAY]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_survived", time_alive, tagger_hit_count)
		_schedule_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_survived(final_time: float, final_hit_count: int) -> void:
	caught = true
	_update_catch_crosshair()
	_clear_tagger_slow_particles()
	time_alive = final_time
	tagger_hit_count = final_hit_count
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "本局结束\n躲藏者胜利！\n已击中追逐者 %d 次\n用时 %.2f 秒\n等待房主返回房间并自动换边" % [tagger_hit_count, final_time]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_player_caught() -> void:
	_finish_runner_failed("躲藏者被抓到了！")

func _on_runner_fell() -> void:
	_finish_runner_failed("躲藏者掉出地图！")

func _finish_runner_failed(reason: String) -> void:
	caught = true
	_clear_tagger_slow_particles()
	player.is_control_locked = true
	tagger.is_active = false
	if game_mode == "single":
		center_label.text = "%s\n追逐者胜利\n坚持了 %.2f 秒\n按 R 重新开始" % [reason, time_alive]
	elif game_mode == "single_chase":
		center_label.text = "%s\n你抓到了 AI 躲藏者！\n用时 %.2f 秒\n按 R 重新挑战" % [reason, time_alive]
	else:
		center_label.text = "本局结束\n%s\n追逐者胜利\n坚持了 %.2f 秒\n%.0f 秒后返回房间并自动换边" % [reason, time_alive, MULTIPLAYER_RESULT_DELAY]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_failed", time_alive, reason)
		_schedule_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_failed(final_time: float, reason: String) -> void:
	caught = true
	_update_catch_crosshair()
	time_alive = final_time
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "本局结束\n%s\n追逐者胜利\n坚持了 %.2f 秒\n等待房主返回房间并自动换边" % [reason, final_time]
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
	_ensure_throwable_root()
	_ensure_throwable_trajectory()

func _ensure_throwable_root() -> void:
	if throwable_root != null and is_instance_valid(throwable_root):
		return
	throwable_root = Node3D.new()
	throwable_root.name = "ThrowableRoot"
	add_child(throwable_root)

func _ensure_throwable_trajectory() -> void:
	if throwable_trajectory != null and is_instance_valid(throwable_trajectory):
		return
	throwable_trajectory = MeshInstance3D.new()
	throwable_trajectory.name = "ThrowableTrajectory"
	throwable_trajectory.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.92, 1.0, 0.58)
	material.emission_enabled = true
	material.emission = Color(0.12, 0.78, 1.0)
	material.emission_energy_multiplier = 1.05
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	throwable_trajectory.material_override = material
	throwable_trajectory.visible = false
	add_child(throwable_trajectory)

	throwable_trajectory_dots = Node3D.new()
	throwable_trajectory_dots.name = "ThrowableTrajectoryDots"
	add_child(throwable_trajectory_dots)
	var dot_material := StandardMaterial3D.new()
	dot_material.albedo_color = Color(0.9, 1.0, 1.0, 0.82)
	dot_material.emission_enabled = true
	dot_material.emission = Color(0.35, 0.95, 1.0)
	dot_material.emission_energy_multiplier = 1.25
	dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(THROWABLE_TRAJECTORY_DOT_COUNT):
		var dot := MeshInstance3D.new()
		dot.name = "TrajectoryDot_%02d" % i
		var sphere := SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.11
		dot.mesh = sphere
		dot.material_override = dot_material
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.visible = false
		throwable_trajectory_dots.add_child(dot)

	throwable_landing_marker = MeshInstance3D.new()
	throwable_landing_marker.name = "ThrowableLandingMarker"
	var landing_mesh := CylinderMesh.new()
	landing_mesh.top_radius = 0.45
	landing_mesh.bottom_radius = 0.45
	landing_mesh.height = 0.035
	throwable_landing_marker.mesh = landing_mesh
	var landing_material := StandardMaterial3D.new()
	landing_material.albedo_color = Color(1.0, 0.78, 0.2, 0.68)
	landing_material.emission_enabled = true
	landing_material.emission = Color(1.0, 0.48, 0.08)
	landing_material.emission_energy_multiplier = 1.1
	landing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	landing_material.no_depth_test = true
	throwable_landing_marker.material_override = landing_material
	throwable_landing_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	throwable_landing_marker.visible = false
	add_child(throwable_landing_marker)

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
		title_status.text = "Debug Mode：%s。按 F3 可切换碰撞箱与坐标显示。" % ["开启" if debug_mode else "关闭"]

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
	panel.visible = false
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

	throwable_notice_label = Label.new()
	throwable_notice_label.anchor_left = 0.18
	throwable_notice_label.anchor_top = 0.68
	throwable_notice_label.anchor_right = 0.82
	throwable_notice_label.anchor_bottom = 0.82
	throwable_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	throwable_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	throwable_notice_label.add_theme_font_size_override("font_size", 34)
	throwable_notice_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.92))
	throwable_notice_label.add_theme_color_override("font_outline_color", Color(0.02, 0.08, 0.12))
	throwable_notice_label.add_theme_constant_override("outline_size", 8)
	throwable_notice_label.text = ""
	throwable_notice_label.visible = false
	hud_layer.add_child(throwable_notice_label)

	# 追逐者抓捕冷却显示（右下角）
	catch_cd_label = Label.new()
	catch_cd_label.anchor_left = 1.0
	catch_cd_label.anchor_top = 1.0
	catch_cd_label.anchor_right = 1.0
	catch_cd_label.anchor_bottom = 1.0
	catch_cd_label.offset_left = -210.0
	catch_cd_label.offset_top = -66.0
	catch_cd_label.offset_right = -18.0
	catch_cd_label.offset_bottom = -18.0
	catch_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	catch_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	catch_cd_label.add_theme_font_size_override("font_size", 26)
	catch_cd_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55, 0.95))
	catch_cd_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.03, 0.9))
	catch_cd_label.add_theme_constant_override("outline_size", 4)
	catch_cd_label.text = ""
	catch_cd_label.visible = false
	hud_layer.add_child(catch_cd_label)

	direction_marker_label = Label.new()
	direction_marker_label.anchor_left = 0.5
	direction_marker_label.anchor_top = 0.08
	direction_marker_label.anchor_right = 0.5
	direction_marker_label.anchor_bottom = 0.08
	direction_marker_label.offset_left = -90.0
	direction_marker_label.offset_top = -24.0
	direction_marker_label.offset_right = 90.0
	direction_marker_label.offset_bottom = 32.0
	direction_marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	direction_marker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	direction_marker_label.add_theme_font_size_override("font_size", 42)
	direction_marker_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.24, 0.95))
	direction_marker_label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.02, 0.9))
	direction_marker_label.add_theme_constant_override("outline_size", 5)
	direction_marker_label.text = "▲"
	direction_marker_label.visible = false
	hud_layer.add_child(direction_marker_label)

	threat_overlay = ColorRect.new()
	threat_overlay.color = Color(1.0, 0.0, 0.0, 0.0)
	threat_overlay.anchor_right = 1.0
	threat_overlay.anchor_bottom = 1.0
	threat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(threat_overlay)

	_build_minimap_ui()
	hud_layer.visible = false

func _build_minimap_ui() -> void:
	minimap_panel = PanelContainer.new()
	# 右上角
	minimap_panel.anchor_left = 1.0
	minimap_panel.anchor_top = 0.0
	minimap_panel.anchor_right = 1.0
	minimap_panel.anchor_bottom = 0.0
	minimap_panel.offset_left = -190.0
	minimap_panel.offset_top = 18.0
	minimap_panel.offset_right = -18.0
	minimap_panel.offset_bottom = 190.0
	minimap_panel.add_theme_stylebox_override("panel", _cartoon_style(Color(0.02, 0.05, 0.08, 0.58), Color(0.28, 0.78, 1.0, 0.82), 3, 18, Vector2.ZERO, 8))
	hud_layer.add_child(minimap_panel)

	minimap_content = Control.new()
	minimap_content.custom_minimum_size = Vector2(156.0, 156.0)
	minimap_content.clip_contents = true
	minimap_panel.add_child(minimap_content)

	# 本方玩家标记（始终位于地图上其真实位置）
	minimap_player_dot = ColorRect.new()
	minimap_player_dot.name = "MinimapPlayer"
	minimap_player_dot.color = Color(0.32, 0.9, 1.0, 0.95)
	minimap_player_dot.size = Vector2(9.0, 9.0)
	minimap_player_dot.visible = false
	minimap_content.add_child(minimap_player_dot)

	minimap_opponent_dot = ColorRect.new()
	minimap_opponent_dot.name = "MinimapOpponent"
	minimap_opponent_dot.color = Color(1.0, 0.18, 0.12, 0.92)
	minimap_opponent_dot.size = Vector2(9.0, 9.0)
	minimap_opponent_dot.visible = false
	minimap_content.add_child(minimap_opponent_dot)

func _update_direction_marker() -> void:
	if direction_marker_label != null:
		direction_marker_label.visible = false

func _update_threat_overlay(distance: float) -> void:
	if threat_overlay == null:
		return
	var alpha := 0.0
	if _local_is_runner() and not caught:
		alpha = clampf((RUNNER_THREAT_RED_DISTANCE - distance) / RUNNER_THREAT_RED_DISTANCE, 0.0, 1.0) * 0.32
	threat_overlay.color = Color(1.0, 0.0, 0.0, alpha)

func _update_minimap(delta: float) -> void:
	if minimap_panel == null or minimap_content == null:
		return
	if not _throwable_system_active() or caught:
		minimap_panel.visible = false
		return
	minimap_panel.visible = true
	_update_minimap_player()
	_update_minimap_rewards()
	_update_minimap_opponent(delta)

func _update_minimap_player() -> void:
	if minimap_player_dot == null:
		return
	var local_actor := _local_controlled_actor()
	if local_actor == null or not is_instance_valid(local_actor):
		minimap_player_dot.visible = false
		return
	minimap_player_dot.position = _world_to_minimap(local_actor.global_position) - minimap_player_dot.size * 0.5
	minimap_player_dot.visible = true

func _update_minimap_rewards() -> void:
	if minimap_content == null:
		return
	while minimap_reward_dots.size() < ground_throwables.size():
		var dot := ColorRect.new()
		dot.color = Color(1.0, 0.86, 0.18, 0.95)
		dot.size = Vector2(7.0, 7.0)
		minimap_reward_dots.append(dot)
		minimap_content.add_child(dot)
	var item_index := 0
	for data in ground_throwables.values():
		var dot := minimap_reward_dots[item_index]
		dot.position = _world_to_minimap(data.get("position", Vector3.ZERO)) - dot.size * 0.5
		dot.visible = true
		item_index += 1
	for i in range(item_index, minimap_reward_dots.size()):
		minimap_reward_dots[i].visible = false

func _update_minimap_opponent(delta: float) -> void:
	if minimap_opponent_dot == null:
		return
	var local_actor := _local_controlled_actor()
	var opponent := _opponent_actor_for_local_player()
	if local_actor != null and opponent != null and _can_see_opponent(local_actor, opponent):
		opponent_seen_timer = OPPONENT_MINIMAP_MEMORY
		last_seen_opponent_position = opponent.global_position
	else:
		opponent_seen_timer = maxf(opponent_seen_timer - delta, 0.0)
	minimap_opponent_dot.visible = opponent_seen_timer > 0.0
	if minimap_opponent_dot.visible:
		minimap_opponent_dot.position = _world_to_minimap(last_seen_opponent_position) - minimap_opponent_dot.size * 0.5

func _world_to_minimap(world_position: Vector3) -> Vector2:
	var center := runner_spawn_position.lerp(tagger_spawn_position, 0.5)
	var rel := Vector2(world_position.x - center.x, world_position.z - center.z) / MINIMAP_WORLD_RADIUS
	var size := minimap_content.size
	if size.x <= 1.0 or size.y <= 1.0:
		size = Vector2(156.0, 156.0)
	return Vector2(size.x * 0.5 + clampf(rel.x, -1.0, 1.0) * size.x * 0.45, size.y * 0.5 + clampf(rel.y, -1.0, 1.0) * size.y * 0.45)

func _opponent_actor_for_local_player() -> Node3D:
	if _local_is_runner():
		return tagger if tagger != null and is_instance_valid(tagger) else null
	if _local_is_tagger():
		return player if player != null and is_instance_valid(player) else null
	return null

func _can_see_opponent(local_actor: Node3D, opponent: Node3D) -> bool:
	if local_actor == null or opponent == null or get_world_3d() == null:
		return false
	var from := local_actor.global_position + Vector3.UP * 1.0
	var to := opponent.global_position + Vector3.UP * 1.0
	if from.distance_to(to) > OPPONENT_SIGHT_RANGE:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [local_actor.get_rid(), opponent.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_catch_crosshair() -> void:
	if catch_cd_label == null:
		return
	var show_cd := hud_layer != null and hud_layer.visible and not caught and _local_is_tagger()
	catch_cd_label.visible = show_cd
	if not show_cd:
		return
	if catch_cooldown_remaining > 0.0:
		catch_cd_label.text = "抓捕冷却 %.1fs" % catch_cooldown_remaining
		catch_cd_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.3, 0.95))
	else:
		catch_cd_label.text = "抓捕就绪"
		catch_cd_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55, 0.95))

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
	_bind_key("pickup_item", KEY_F)
	_bind_mouse_button("throw_item", MOUSE_BUTTON_LEFT)
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

func _local_is_runner() -> bool:
	if game_mode == "single":
		return true
	if game_mode == "host":
		return host_is_runner
	if game_mode == "client":
		return not host_is_runner
	return false

func _runner_peer_id() -> int:
	if remote_peer_id == 0:
		return 1
	return 1 if host_is_runner else remote_peer_id

func _get_local_actor():
	if _local_is_runner():
		return player
	if _local_is_tagger():
		return tagger
	return null

func _throwable_system_active() -> bool:
	return game_mode == "single" or game_mode == "single_chase" or game_mode == "host" or game_mode == "client"

func _prepare_throwable_round_state() -> void:
	runner_has_throwable = false
	throwable_respawn_timer = 0.15
	next_ground_throwable_id = 1
	next_flying_throwable_id = 1
	_clear_all_throwables()
	if not _throwable_system_active():
		return
	_ensure_throwable_root()
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		_maybe_fill_throwable_spawns(true)

func _clear_all_throwables() -> void:
	runner_has_throwable = false
	throwable_respawn_timer = THROWABLE_RESPAWN_INTERVAL
	for data in ground_throwables.values():
		var node := data.get("node", null) as Node3D
		if node != null and is_instance_valid(node):
			node.queue_free()
	ground_throwables.clear()
	for data in flying_throwables.values():
		var node := data.get("node", null) as Node3D
		if node != null and is_instance_valid(node):
			node.queue_free()
	flying_throwables.clear()
	_hide_throwable_trajectory()
	_hide_throwable_notice()
	_hide_held_throwable_visual()
	_clear_tagger_slow_particles()

func _update_throwables(delta: float) -> void:
	if not _throwable_system_active() or caught:
		return
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		throwable_respawn_timer = maxf(throwable_respawn_timer - delta, 0.0)
		if throwable_respawn_timer <= 0.0:
			_maybe_fill_throwable_spawns(false)
	_update_flying_throwables(delta, multiplayer.multiplayer_peer == null or multiplayer.is_server())

func _update_ai_runner_throwable_strategy(delta: float) -> void:
	if game_mode != "single_chase" or caught or player == null or tagger == null or not is_instance_valid(player) or not is_instance_valid(tagger):
		return
	ai_runner_throw_cooldown = maxf(ai_runner_throw_cooldown - delta, 0.0)
	if player.has_method("set_throwable_context"):
		player.set_throwable_context(_ground_throwable_positions(), runner_has_throwable, tagger_hit_count, TAGGER_HITS_TO_WIN)
	if not runner_has_throwable:
		var pickup_id := _find_pickup_candidate_for_actor(player, THROWABLE_AI_PICKUP_RANGE)
		if pickup_id >= 0:
			_pickup_throwable_on_authority(pickup_id)
		return
	if ai_runner_throw_cooldown > 0.0:
		return
	var origin: Vector3 = _runner_throw_origin(player)
	var to_tagger: Vector3 = tagger.global_position + Vector3.UP * 0.8 - origin
	var flat_distance: float = Vector2(to_tagger.x, to_tagger.z).length()
	if flat_distance < THROWABLE_AI_THROW_MIN_DISTANCE or flat_distance > THROWABLE_AI_THROW_MAX_DISTANCE:
		return
	if not _has_clear_throw_line(origin, tagger.global_position + Vector3.UP * 0.85):
		return
	var predicted: Vector3 = tagger.global_position + Vector3.UP * 0.85
	if tagger is CharacterBody3D:
		var tagger_velocity: Vector3 = (tagger as CharacterBody3D).velocity
		tagger_velocity.y = 0.0
		predicted += tagger_velocity * clampf(flat_distance / THROWABLE_THROW_SPEED, 0.0, 0.55)
	var direction := (predicted - origin).normalized()
	direction.y = clampf(direction.y + 0.12, -0.15, 0.45)
	ai_runner_throw_cooldown = THROWABLE_AI_THROW_COOLDOWN
	_throw_throwable_on_authority(origin, direction)

func _ground_throwable_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for data in ground_throwables.values():
		positions.append(data.get("position", Vector3.ZERO))
	return positions

func _has_clear_throw_line(from: Vector3, to: Vector3) -> bool:
	if get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	if player != null and is_instance_valid(player) and tagger != null and is_instance_valid(tagger):
		query.exclude = [player.get_rid(), tagger.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func _maybe_fill_throwable_spawns(force_fill: bool) -> void:
	if not _throwable_system_active():
		return
	if not force_fill and ground_throwables.size() >= THROWABLE_RESPAWN_TARGET:
		throwable_respawn_timer = THROWABLE_RESPAWN_INTERVAL
		return
	_ensure_throwable_root()
	var fill_attempts := 0
	while ground_throwables.size() < THROWABLE_RESPAWN_TARGET and fill_attempts < THROWABLE_RESPAWN_TARGET * 4:
		fill_attempts += 1
		var spawn_position: Variant = _find_throwable_spawn_position()
		if spawn_position == null:
			break
		var spawned_id := _spawn_ground_throwable(spawn_position as Vector3)
		if spawned_id < 0:
			break
	throwable_respawn_timer = THROWABLE_RESPAWN_INTERVAL

func _find_throwable_spawn_position():
	if get_world_3d() == null:
		return null
	var center := runner_spawn_position.lerp(tagger_spawn_position, 0.5)
	var span := runner_spawn_position.distance_to(tagger_spawn_position)
	# Clamp the search radius so probes stay inside compact maps instead of
	# overshooting the map bounds (which previously yielded zero valid spawns).
	var max_radius := clampf(span * 0.5, 10.0, 26.0)
	var ground_level := (runner_spawn_position.y + tagger_spawn_position.y) * 0.5
	var space_state := get_world_3d().direct_space_state
	var total_attempts: int = maxi(THROWABLE_SPAWN_ATTEMPTS, 64)
	for attempt in range(total_attempts):
		var angle := randf() * TAU
		# Late attempts shrink toward the guaranteed-walkable centre so a slot
		# can still be found on small or crowded maps.
		var falloff := 1.0 - float(attempt) / float(total_attempts)
		var radius := randf_range(4.0, lerpf(6.0, max_radius, falloff))
		# Alternate the sampling origin so playable ground offset from the
		# midpoint (e.g. multi-room maps) is still covered.
		var origin := center
		match attempt % 3:
			1:
				origin = runner_spawn_position
			2:
				origin = tagger_spawn_position
		var probe := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var from := probe + Vector3.UP * 12.0
		var to := probe + Vector3.DOWN * 24.0
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var position: Vector3 = hit.get("position", probe)
		# Reject hits that landed on an upper floor / roof so items stay on the
		# level the players start on and remain reachable.
		if position.y - ground_level > 2.5:
			continue
		position.y += 0.28
		if position.distance_to(runner_spawn_position) < 4.0 or position.distance_to(tagger_spawn_position) < 4.0:
			continue
		var too_close := false
		for data in ground_throwables.values():
			var other: Vector3 = data.get("position", Vector3.ZERO)
			if other.distance_to(position) < THROWABLE_MIN_SPAWN_GAP:
				too_close = true
				break
		if too_close:
			continue
		return position
	return null

func _spawn_ground_throwable(position: Vector3, item_id: int = -1) -> int:
	_ensure_throwable_root()
	if throwable_root == null or not is_instance_valid(throwable_root):
		return -1
	var resolved_id: int = item_id if item_id > 0 else next_ground_throwable_id
	if item_id <= 0:
		next_ground_throwable_id += 1
	else:
		next_ground_throwable_id = max(next_ground_throwable_id, item_id + 1)
	var node := _create_throwable_visual(false)
	node.name = "GroundThrowable_%d" % resolved_id
	node.position = position
	throwable_root.add_child(node)
	ground_throwables[resolved_id] = {"id": resolved_id, "node": node, "position": position}
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_sync_ground_throwable_spawn", resolved_id, position)
	return resolved_id

func _remove_ground_throwable(item_id: int, sync_remote: bool = true) -> void:
	if not ground_throwables.has(item_id):
		return
	var data: Dictionary = ground_throwables[item_id]
	var node := data.get("node", null) as Node3D
	if node != null and is_instance_valid(node):
		node.queue_free()
	ground_throwables.erase(item_id)
	if sync_remote and multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_remove_ground_throwable", item_id)

func _request_local_throwable_pickup() -> void:
	if not _local_is_runner():
		return
	if runner_has_throwable:
		_show_throwable_notice("已经持有道具，单击左键投掷", Color(0.36, 0.94, 1.0), false)
		return
	var nearest_id := _find_pickup_candidate_id()
	if nearest_id < 0:
		_show_throwable_notice("附近没有可拾取道具", Color(1.0, 0.86, 0.22), false)
		return
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_pickup_throwable", nearest_id)
		return
	_pickup_throwable_on_authority(nearest_id)

func _find_pickup_candidate_id() -> int:
	return _find_pickup_candidate_for_actor(_get_local_actor(), THROWABLE_PICKUP_RANGE)

func _find_pickup_candidate_for_actor(actor: Node3D, pickup_range: float) -> int:
	if actor == null or not is_instance_valid(actor):
		return -1
	var actor_position: Vector3 = actor.global_position
	var best_id := -1
	var best_distance := pickup_range
	for item_id in ground_throwables.keys():
		var data: Dictionary = ground_throwables[item_id]
		var position: Vector3 = data.get("position", Vector3.ZERO)
		var distance := actor_position.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best_id = int(item_id)
	return best_id

func _pickup_throwable_on_authority(item_id: int) -> void:
	if runner_has_throwable or not ground_throwables.has(item_id):
		return
	var runner_actor = player
	if runner_actor == null or not is_instance_valid(runner_actor):
		return
	var data: Dictionary = ground_throwables[item_id]
	var position: Vector3 = data.get("position", Vector3.ZERO)
	if runner_actor.global_position.distance_to(position) > THROWABLE_PICKUP_RANGE + 0.25:
		return
	runner_has_throwable = true
	_update_held_throwable_visual()
	_remove_ground_throwable(item_id, true)
	if _local_is_runner():
		_show_throwable_notice("已拾取道具！单击左键投掷", Color(0.34, 1.0, 0.58), true)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_set_runner_throwable_state", true)

func _request_local_throwable_throw() -> void:
	if not _local_is_runner():
		return
	if not runner_has_throwable:
		_show_throwable_notice("没有道具，先靠近道具按 F 拾取", Color(1.0, 0.78, 0.22), false)
		return
	var actor = _get_local_actor()
	if actor == null or not is_instance_valid(actor):
		return
	var origin: Vector3 = _runner_throw_origin(actor)
	var direction: Vector3 = actor.get_throw_direction() if actor.has_method("get_throw_direction") else -actor.global_transform.basis.z.normalized()
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		runner_has_throwable = false
		_hide_held_throwable_visual()
		_hide_throwable_trajectory()
		_show_throwable_notice("已投掷", Color(0.35, 0.92, 1.0), true)
		rpc_id(1, "_rpc_request_throw_throwable", origin, direction)
		return
	_throw_throwable_on_authority(origin, direction)

func _throw_throwable_on_authority(origin: Vector3, direction: Vector3) -> void:
	if not runner_has_throwable:
		return
	var runner_actor = player
	if runner_actor == null or not is_instance_valid(runner_actor):
		return
	var expected_origin: Vector3 = _runner_throw_origin(runner_actor)
	if origin.distance_to(expected_origin) > THROWABLE_THROW_ORIGIN_TOLERANCE:
		origin = expected_origin
	var throw_direction := direction.normalized()
	if throw_direction.length_squared() < 0.01:
		throw_direction = runner_actor.get_throw_direction() if runner_actor.has_method("get_throw_direction") else -runner_actor.global_transform.basis.z.normalized()
	runner_has_throwable = false
	_hide_held_throwable_visual()
	_hide_throwable_trajectory()
	if _local_is_runner():
		_show_throwable_notice("已投掷", Color(0.35, 0.92, 1.0), true)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_set_runner_throwable_state", false)
	var velocity := _throw_velocity_from_direction(throw_direction)
	_spawn_flying_throwable(origin, velocity)

func _spawn_flying_throwable(origin: Vector3, velocity: Vector3, projectile_id: int = -1) -> int:
	_ensure_throwable_root()
	if throwable_root == null or not is_instance_valid(throwable_root):
		return -1
	var resolved_id: int = projectile_id if projectile_id > 0 else next_flying_throwable_id
	if projectile_id <= 0:
		next_flying_throwable_id += 1
	else:
		next_flying_throwable_id = max(next_flying_throwable_id, projectile_id + 1)
	var node := _create_throwable_visual(true)
	node.name = "FlyingThrowable_%d" % resolved_id
	node.position = origin
	throwable_root.add_child(node)
	flying_throwables[resolved_id] = {
		"id": resolved_id,
		"node": node,
		"position": origin,
		"velocity": velocity,
		"life": THROWABLE_PROJECTILE_LIFETIME
	}
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_spawn_flying_throwable", resolved_id, origin, velocity)
	return resolved_id

func _update_flying_throwables(delta: float, authority_checks: bool) -> void:
	if flying_throwables.is_empty():
		return
	var removal_ids: Array[int] = []
	for projectile_id in flying_throwables.keys():
		var data: Dictionary = flying_throwables[projectile_id]
		var velocity: Vector3 = data.get("velocity", Vector3.ZERO)
		var position: Vector3 = data.get("position", Vector3.ZERO)
		velocity.y -= THROWABLE_PROJECTILE_GRAVITY * delta
		position += velocity * delta
		data["velocity"] = velocity
		data["position"] = position
		data["life"] = float(data.get("life", THROWABLE_PROJECTILE_LIFETIME)) - delta
		var node := data.get("node", null) as Node3D
		if node != null and is_instance_valid(node):
			node.position = position
			if velocity.length_squared() > 0.01:
				node.look_at(position + velocity, Vector3.UP)
		flying_throwables[projectile_id] = data
		if float(data.get("life", 0.0)) <= 0.0:
			removal_ids.append(int(projectile_id))
			continue
		if authority_checks and _projectile_hits_tagger(position):
			_register_tagger_hit(position)
			removal_ids.append(int(projectile_id))
	for projectile_id in removal_ids:
		_remove_flying_throwable(projectile_id, authority_checks)

func _projectile_hits_tagger(projectile_position: Vector3) -> bool:
	if tagger == null or not is_instance_valid(tagger):
		return false
	var target_center: Vector3 = tagger.global_position + Vector3.UP * 0.9
	var flat_distance: float = Vector2(projectile_position.x - target_center.x, projectile_position.z - target_center.z).length()
	var vertical_distance: float = absf(projectile_position.y - target_center.y)
	return flat_distance <= THROWABLE_PROJECTILE_RADIUS and vertical_distance <= 1.15

func _remove_flying_throwable(projectile_id: int, sync_remote: bool, impact_position: Variant = null) -> void:
	if not flying_throwables.has(projectile_id):
		return
	var data: Dictionary = flying_throwables[projectile_id]
	var node := data.get("node", null) as Node3D
	var resolved_impact: Vector3 = data.get("position", Vector3.ZERO)
	if impact_position != null:
		resolved_impact = impact_position as Vector3
	if node != null and is_instance_valid(node):
		node.queue_free()
	flying_throwables.erase(projectile_id)
	if sync_remote and multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_remove_flying_throwable", projectile_id, resolved_impact)

func _register_tagger_hit(impact_position: Vector3) -> void:
	if caught:
		return
	tagger_hit_count += 1
	_apply_tagger_slow_effect(THROWABLE_SLOW_MULTIPLIER, THROWABLE_SLOW_DURATION, impact_position, tagger_hit_count)
	if tagger_hit_count >= TAGGER_HITS_TO_WIN:
		_on_runner_survived()

func _apply_tagger_slow_effect(multiplier: float, duration: float, impact_position: Vector3, current_hit_count: int = -1) -> void:
	if current_hit_count >= 0:
		tagger_hit_count = current_hit_count
	if tagger != null and is_instance_valid(tagger) and tagger.has_method("apply_speed_multiplier"):
		tagger.apply_speed_multiplier(multiplier, duration)
		_start_tagger_slow_particles(duration)
	_play_throwable_hit_effect(impact_position)
	if _local_is_runner():
		_show_throwable_notice("命中追逐者！%d / %d" % [tagger_hit_count, TAGGER_HITS_TO_WIN], Color(0.34, 1.0, 0.58), true)
	elif _local_is_tagger():
		_show_throwable_notice("被击中 %d / %d 次，暂时减速" % [tagger_hit_count, TAGGER_HITS_TO_WIN], Color(1.0, 0.46, 0.32), true)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_apply_tagger_slow_effect", multiplier, duration, impact_position, tagger_hit_count)

func _start_tagger_slow_particles(duration: float) -> void:
	if tagger == null or not is_instance_valid(tagger):
		return
	tagger_slow_particle_timer = maxf(tagger_slow_particle_timer, duration)
	tagger_slow_particle_elapsed = 0.0
	tagger_slow_particle_last_position = tagger.global_position
	if tagger_slow_particles != null and is_instance_valid(tagger_slow_particles):
		tagger_slow_particles.visible = false
		return
	tagger_slow_particles = Node3D.new()
	tagger_slow_particles.name = "TaggerSlowParticles"
	add_child(tagger_slow_particles)
	var ring := MeshInstance3D.new()
	ring.name = "SlowGroundRing"
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 1.05
	ring_mesh.bottom_radius = 1.05
	ring_mesh.height = 0.035
	ring.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.15, 0.85, 1.0, 0.34)
	ring_material.emission_enabled = true
	ring_material.emission = Color(0.08, 0.58, 1.0)
	ring_material.emission_energy_multiplier = 0.7
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tagger_slow_particles.add_child(ring)
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = Color(0.38, 0.96, 1.0, 0.78)
	particle_material.emission_enabled = true
	particle_material.emission = Color(0.2, 0.82, 1.0)
	particle_material.emission_energy_multiplier = 1.15
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(18):
		var particle := MeshInstance3D.new()
		particle.name = "SlowParticle_%02d" % i
		var sphere := SphereMesh.new()
		sphere.radius = 0.07
		sphere.height = 0.14
		particle.mesh = sphere
		particle.material_override = particle_material
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tagger_slow_particles.add_child(particle)
	_update_tagger_slow_particles(0.0)

func _update_tagger_slow_particles(delta: float) -> void:
	if tagger_slow_particle_timer <= 0.0:
		_clear_tagger_slow_particles()
		return
	if tagger == null or not is_instance_valid(tagger):
		_clear_tagger_slow_particles()
		return
	if tagger_slow_particles == null or not is_instance_valid(tagger_slow_particles):
		_start_tagger_slow_particles(tagger_slow_particle_timer)
		return
	tagger_slow_particle_timer = maxf(tagger_slow_particle_timer - delta, 0.0)
	tagger_slow_particle_elapsed += delta
	var current_position: Vector3 = tagger.global_position
	var horizontal_delta := Vector2(current_position.x - tagger_slow_particle_last_position.x, current_position.z - tagger_slow_particle_last_position.z).length()
	var moving_threshold := SLOW_PARTICLE_MOVE_THRESHOLD * maxf(delta, 0.016)
	var is_walking := horizontal_delta > moving_threshold
	tagger_slow_particle_last_position = current_position
	tagger_slow_particles.visible = is_walking
	if not is_walking:
		if tagger_slow_particle_timer <= 0.0:
			_clear_tagger_slow_particles()
		return
	tagger_slow_particles.global_position = current_position + Vector3.UP * 0.05
	tagger_slow_particles.rotation.y += delta * 2.2
	var ring := tagger_slow_particles.get_node_or_null("SlowGroundRing") as MeshInstance3D
	if ring != null:
		var pulse := 1.0 + sin(tagger_slow_particle_elapsed * 8.0) * 0.12
		ring.scale = Vector3(pulse, 1.0, pulse)
	for i in range(tagger_slow_particles.get_child_count()):
		var child := tagger_slow_particles.get_child(i)
		if not (child is MeshInstance3D) or not String(child.name).begins_with("SlowParticle_"):
			continue
		var particle := child as MeshInstance3D
		var index := float(i)
		var angle := index * 1.73 + tagger_slow_particle_elapsed * 4.4
		var radius := 0.45 + 0.36 * absf(sin(tagger_slow_particle_elapsed * 2.0 + index))
		particle.position = Vector3(cos(angle) * radius, 0.12 + 0.34 * absf(sin(tagger_slow_particle_elapsed * 5.2 + index)), sin(angle) * radius)
		var particle_scale := 0.75 + 0.45 * absf(sin(tagger_slow_particle_elapsed * 6.0 + index))
		particle.scale = Vector3.ONE * particle_scale
	if tagger_slow_particle_timer <= 0.0:
		_clear_tagger_slow_particles()

func _clear_tagger_slow_particles() -> void:
	tagger_slow_particle_timer = 0.0
	tagger_slow_particle_elapsed = 0.0
	tagger_slow_particle_last_position = Vector3.ZERO
	if tagger_slow_particles != null and is_instance_valid(tagger_slow_particles):
		tagger_slow_particles.queue_free()
	tagger_slow_particles = null

func _play_throwable_hit_effect(position: Vector3) -> void:
	var root := Node3D.new()
	root.name = "ThrowableHitEffect"
	root.position = position
	add_child(root)
	for i in range(6):
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.11
		sphere.height = 0.22
		mesh.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.35, 0.95, 1.0, 0.86)
		material.emission_enabled = true
		material.emission = Color(0.22, 0.88, 1.0)
		material.emission_energy_multiplier = 1.15
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = material
		var angle := TAU * float(i) / 6.0
		mesh.position = Vector3(cos(angle) * 0.2, 0.08, sin(angle) * 0.2)
		root.add_child(mesh)
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector3.ONE * 1.55, 0.2)
	tween.parallel().tween_property(root, "position:y", position.y + 0.45, 0.2)
	await get_tree().create_timer(0.22).timeout
	if is_instance_valid(root):
		root.queue_free()

func _create_throwable_visual(is_projectile: bool) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.96, 1.0) if is_projectile else Color(0.96, 0.9, 0.35)
	material.roughness = 0.3 if is_projectile else 0.55
	material.emission_enabled = true
	material.emission = Color(0.18, 0.85, 1.0) if is_projectile else Color(1.0, 0.72, 0.18)
	material.emission_energy_multiplier = 0.7
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	var ring := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.27
	cylinder.bottom_radius = 0.27
	cylinder.height = 0.05
	ring.mesh = cylinder
	ring.position.y = -0.18
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.08, 0.12, 0.18, 0.45)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_material
	root.add_child(ring)
	return root

func _show_throwable_notice(text: String, color: Color, protect_existing: bool) -> void:
	if throwable_notice_label == null:
		return
	if throwable_notice_protect_timer > 0.0 and not protect_existing:
		return
	throwable_notice_label.text = text
	throwable_notice_label.add_theme_color_override("font_color", color)
	throwable_notice_label.visible = true
	throwable_notice_timer = THROWABLE_NOTICE_DURATION
	throwable_notice_protect_timer = THROWABLE_PICKUP_NOTICE_PROTECT if protect_existing else 0.0

func _hide_throwable_notice() -> void:
	throwable_notice_timer = 0.0
	throwable_notice_protect_timer = 0.0
	if throwable_notice_label != null:
		throwable_notice_label.visible = false
		throwable_notice_label.text = ""

func _update_throwable_notice(delta: float) -> void:
	if throwable_notice_label == null:
		return
	throwable_notice_protect_timer = maxf(throwable_notice_protect_timer - delta, 0.0)
	if throwable_notice_timer > 0.0:
		throwable_notice_timer = maxf(throwable_notice_timer - delta, 0.0)
		if throwable_notice_timer <= 0.0:
			_hide_throwable_notice()

func _ensure_held_throwable_visual() -> void:
	if held_throwable_visual != null and is_instance_valid(held_throwable_visual):
		return
	held_throwable_visual = _create_throwable_visual(true)
	held_throwable_visual.name = "HeldThrowable"
	held_throwable_visual.scale = Vector3.ONE * 0.82
	held_throwable_visual.visible = false
	add_child(held_throwable_visual)

func _hide_held_throwable_visual() -> void:
	if held_throwable_visual != null and is_instance_valid(held_throwable_visual):
		held_throwable_visual.visible = false

func _update_held_throwable_visual() -> void:
	if not _throwable_system_active() or not runner_has_throwable or caught or player == null or not is_instance_valid(player):
		_hide_held_throwable_visual()
		return
	_ensure_held_throwable_visual()
	if held_throwable_visual == null or not is_instance_valid(held_throwable_visual):
		return
	var origin := _runner_throw_origin(player)
	held_throwable_visual.global_position = origin
	held_throwable_visual.global_rotation = player.global_rotation
	held_throwable_visual.visible = true

func _runner_throw_origin(actor: Node3D) -> Vector3:
	if actor == null or not is_instance_valid(actor):
		return Vector3.ZERO
	if actor.has_method("get_throw_origin"):
		return actor.get_throw_origin()
	var basis := actor.global_transform.basis
	var right := basis.x.normalized()
	var forward := -basis.z.normalized()
	return actor.global_position + right * THROWABLE_HAND_OFFSET.x + Vector3.UP * THROWABLE_HAND_OFFSET.y + forward * absf(THROWABLE_HAND_OFFSET.z)

func _throw_velocity_from_direction(direction: Vector3) -> Vector3:
	var throw_direction := direction.normalized()
	if throw_direction.length_squared() < 0.01:
		throw_direction = Vector3.FORWARD
	var velocity := throw_direction * THROWABLE_THROW_SPEED
	velocity.y += THROWABLE_THROW_UPWARD_BONUS
	return velocity

func _compute_throw_trajectory(origin: Vector3, velocity: Vector3) -> Dictionary:
	var points: Array[Vector3] = [origin]
	var previous := origin
	var landing := origin
	var hit_ground := false
	for step in range(1, THROWABLE_TRAJECTORY_STEPS + 1):
		var t := float(step) * THROWABLE_TRAJECTORY_STEP_TIME
		var point := origin + velocity * t + Vector3.DOWN * 0.5 * THROWABLE_PROJECTILE_GRAVITY * t * t
		var query := PhysicsRayQueryParameters3D.create(previous, point)
		query.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(query) if get_world_3d() != null else {}
		if not hit.is_empty():
			landing = hit.get("position", point)
			points.append(landing)
			hit_ground = true
			break
		points.append(point)
		landing = point
		previous = point
	return {"points": points, "landing": landing, "hit": hit_ground}

func _update_trajectory_dots(points: Array) -> void:
	if throwable_trajectory_dots == null or not is_instance_valid(throwable_trajectory_dots):
		return
	var child_count := throwable_trajectory_dots.get_child_count()
	for i in range(child_count):
		var dot := throwable_trajectory_dots.get_child(i) as MeshInstance3D
		if dot == null:
			continue
		if points.size() <= 1:
			dot.visible = false
			continue
		var ratio := float(i + 1) / float(child_count + 1)
		var point_index := clampi(roundi(ratio * float(points.size() - 1)), 0, points.size() - 1)
		dot.global_position = points[point_index]
		dot.scale = Vector3.ONE * (0.82 + ratio * 0.75)
		dot.visible = true

func _update_landing_marker(position: Vector3, has_ground_hit: bool) -> void:
	if throwable_landing_marker == null or not is_instance_valid(throwable_landing_marker):
		return
	throwable_landing_marker.global_position = position + Vector3.UP * 0.035
	throwable_landing_marker.rotation = Vector3.ZERO
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.08
	throwable_landing_marker.scale = Vector3.ONE * (pulse if has_ground_hit else 0.72)
	throwable_landing_marker.visible = true

func _hide_throwable_trajectory() -> void:
	if throwable_trajectory != null and is_instance_valid(throwable_trajectory):
		throwable_trajectory.visible = false
		throwable_trajectory.mesh = null
	if throwable_trajectory_dots != null and is_instance_valid(throwable_trajectory_dots):
		for child in throwable_trajectory_dots.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false
	if throwable_landing_marker != null and is_instance_valid(throwable_landing_marker):
		throwable_landing_marker.visible = false

func _update_throwable_trajectory() -> void:
	if not _local_is_runner() or not runner_has_throwable or caught or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		_hide_throwable_trajectory()
		return
	var actor = _get_local_actor()
	if actor == null or not is_instance_valid(actor):
		_hide_throwable_trajectory()
		return
	_ensure_throwable_trajectory()
	if throwable_trajectory == null or not is_instance_valid(throwable_trajectory):
		return
	var origin: Vector3 = _runner_throw_origin(actor)
	var direction: Vector3 = actor.get_throw_direction() if actor.has_method("get_throw_direction") else -actor.global_transform.basis.z.normalized()
	var velocity := _throw_velocity_from_direction(direction)
	var trajectory := _compute_throw_trajectory(origin, velocity)
	var points: Array = trajectory.get("points", [])
	if points.size() < 2:
		_hide_throwable_trajectory()
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	throwable_trajectory.mesh = mesh
	throwable_trajectory.visible = true
	_update_trajectory_dots(points)
	var landing_position: Vector3 = trajectory.get("landing", points[points.size() - 1])
	_update_landing_marker(landing_position, bool(trajectory.get("hit", false)))

func _throwable_status_text() -> String:
	if not _throwable_system_active():
		return ""
	if _local_is_runner():
		return "道具：%s（场上 %d 个）" % ["已持有，单击左键投掷" if runner_has_throwable else "未持有，靠近后按 F 拾取", ground_throwables.size()]
	return "场上道具：%d 个" % ground_throwables.size()

@rpc("call_remote", "reliable")
func _rpc_sync_ground_throwable_spawn(item_id: int, position: Vector3) -> void:
	_spawn_ground_throwable(position, item_id)

@rpc("call_remote", "reliable")
func _rpc_remove_ground_throwable(item_id: int) -> void:
	_remove_ground_throwable(item_id, false)

@rpc("call_remote", "reliable")
func _rpc_set_runner_throwable_state(has_throwable: bool) -> void:
	runner_has_throwable = has_throwable
	if has_throwable:
		_update_held_throwable_visual()
	else:
		_hide_held_throwable_visual()
	if _local_is_runner():
		if has_throwable:
			_show_throwable_notice("已拾取道具！单击左键投掷", Color(0.34, 1.0, 0.58), true)
		else:
			_hide_throwable_trajectory()
			_show_throwable_notice("已投掷", Color(0.35, 0.92, 1.0), true)

@rpc("any_peer", "reliable")
func _rpc_request_pickup_throwable(item_id: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _runner_peer_id():
		return
	_pickup_throwable_on_authority(item_id)

@rpc("any_peer", "reliable")
func _rpc_request_throw_throwable(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _runner_peer_id():
		return
	_throw_throwable_on_authority(origin, direction)

@rpc("call_remote", "reliable")
func _rpc_spawn_flying_throwable(projectile_id: int, origin: Vector3, velocity: Vector3) -> void:
	_spawn_flying_throwable(origin, velocity, projectile_id)

@rpc("call_remote", "reliable")
func _rpc_remove_flying_throwable(projectile_id: int, impact_position: Vector3) -> void:
	_remove_flying_throwable(projectile_id, false, impact_position)

@rpc("call_remote", "reliable")
func _rpc_apply_tagger_slow_effect(multiplier: float, duration: float, impact_position: Vector3, current_hit_count: int) -> void:
	tagger_hit_count = current_hit_count
	if tagger != null and is_instance_valid(tagger) and tagger.has_method("apply_speed_multiplier"):
		tagger.apply_speed_multiplier(multiplier, duration)
		_start_tagger_slow_particles(duration)
	_play_throwable_hit_effect(impact_position)
	if _local_is_runner():
		_show_throwable_notice("命中追逐者！%d / %d" % [tagger_hit_count, TAGGER_HITS_TO_WIN], Color(0.34, 1.0, 0.58), true)
	elif _local_is_tagger():
		_show_throwable_notice("被击中 %d / %d 次，暂时减速" % [tagger_hit_count, TAGGER_HITS_TO_WIN], Color(1.0, 0.46, 0.32), true)
