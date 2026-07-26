extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const TaggerScript = preload("res://scripts/tagger.gd")
const NetworkActorScript = preload("res://scripts/network_actor.gd")
const MapLoader = preload("res://scripts/map_loader.gd")
const PORT = 24591
const VOID_Y = -12.0
const DEFAULT_MAP_PATH = "res://maps/default_arena.json"
const USER_MAP_PATH = "user://maps/current_map.json"
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
var lobby_role_label: Label
var switch_role_button: Button
var start_game_button: Button
var setup_controls: Array[Control] = []
var menu_controls: Array[Control] = []
var lobby_controls: Array[Control] = []
var map_page_controls: Array[Control] = []
var time_alive := 0.0
var caught := false
var game_mode := "title"
var network_started := false
var remote_peer_id := 0
var host_is_runner := true
var win_time_seconds := 60.0
var is_leaving_room := false
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
var runner_spawn_position := Vector3(-23.0, 0.12, 22.0)
var tagger_spawn_position := Vector3(23.0, 0.12, -22.0)

func _ready() -> void:
	randomize()
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
			rpc("_rpc_begin_network_round", remote_peer_id, host_is_runner, win_time_seconds, selected_map_index)
		return

	if caught:
		return

	if (game_mode == "single" or game_mode == "host") and player.global_position.y < VOID_Y:
		_on_runner_fell()
		return

	time_alive += delta
	var catch_offset: Vector3 = player.global_position - tagger.global_position
	var vertical_distance: float = absf(catch_offset.y)
	catch_offset.y = 0.0
	var distance: float = catch_offset.length()
	var mode_text := "单人模式" if game_mode == "single" else "联机一打一：" + _local_role_text()
	var controls_text := "WASD 移动  空格跳跃/翻越  鼠标视角  Esc 鼠标  R 重开  F3 碰撞箱:%s" % ["开" if debug_mode else "关"]
	if game_mode == "single":
		controls_text += "  Q 回标题"
	else:
		controls_text += "  Q 退出房间"
	hud_label.text = "%s\n地图：%s\n逃跑时间：%05.2f / %d 秒\n抓人者速度：7.8  逃跑者速度：7.0\n距离：%04.1f 米\n%s" % [mode_text, map_name, time_alive, int(win_time_seconds), distance, controls_text]

	if (game_mode == "single" or game_mode == "host") and time_alive >= win_time_seconds:
		_on_runner_survived()
		return

	if game_mode == "single":
		if distance <= 1.35 and vertical_distance <= 2.25 and _has_clear_catch_line():
			_on_player_caught()
	elif game_mode == "host":
		if distance <= 1.35 and vertical_distance <= 2.25 and _has_clear_catch_line():
			_on_player_caught()

func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(Callable(self, "_on_peer_connected"))
	multiplayer.peer_disconnected.connect(Callable(self, "_on_peer_disconnected"))
	multiplayer.connected_to_server.connect(Callable(self, "_on_connected_to_server"))
	multiplayer.connection_failed.connect(Callable(self, "_on_connection_failed"))
	multiplayer.server_disconnected.connect(Callable(self, "_on_server_disconnected"))

func _build_title_ui() -> void:
	title_layer = CanvasLayer.new()
	title_layer.name = "TitleUI"
	add_child(title_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.045, 0.94)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	title_layer.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	title_layer.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460.0, 0.0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "跑酷抓人"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "单人逃脱 / 联机一打一"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	box.add_child(subtitle)

	win_time_row = HBoxContainer.new()
	win_time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	win_time_row.add_theme_constant_override("separation", 10)
	box.add_child(win_time_row)
	setup_controls.append(win_time_row)

	var win_time_label := Label.new()
	win_time_label.text = "胜利时间"
	win_time_row.add_child(win_time_label)

	win_time_spinbox = SpinBox.new()
	win_time_spinbox.min_value = 10.0
	win_time_spinbox.max_value = 600.0
	win_time_spinbox.step = 5.0
	win_time_spinbox.value = win_time_seconds
	win_time_spinbox.suffix = " 秒"
	win_time_spinbox.custom_minimum_size = Vector2(120.0, 0.0)
	win_time_spinbox.value_changed.connect(Callable(self, "_on_win_time_changed"))
	win_time_row.add_child(win_time_spinbox)

	var win_time_hint := Label.new()
	win_time_hint.text = "逃跑者坚持到即胜"
	win_time_row.add_child(win_time_hint)

	var map_row := HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row.add_theme_constant_override("separation", 10)
	box.add_child(map_row)
	setup_controls.append(map_row)

	map_summary_label = Label.new()
	map_summary_label.text = "当前地图：%s" % map_name
	map_row.add_child(map_summary_label)

	map_select_button = Button.new()
	map_select_button.text = "选择官方地图"
	map_select_button.pressed.connect(Callable(self, "_show_map_page"))
	map_row.add_child(map_select_button)

	var single_button := Button.new()
	single_button.text = "单人模式：逃跑者 VS AI 抓人者"
	single_button.pressed.connect(Callable(self, "_start_single_game"))
	box.add_child(single_button)
	menu_controls.append(single_button)

	var host_button := Button.new()
	host_button.text = "创建联机房间"
	host_button.pressed.connect(Callable(self, "_start_host_game"))
	box.add_child(host_button)
	menu_controls.append(host_button)

	ip_input = LineEdit.new()
	ip_input.text = "127.0.0.1"
	ip_input.placeholder_text = "输入房主 IP"
	box.add_child(ip_input)
	menu_controls.append(ip_input)

	var join_button := Button.new()
	join_button.text = "加入联机房间"
	join_button.pressed.connect(Callable(self, "_start_client_game"))
	box.add_child(join_button)
	menu_controls.append(join_button)

	lobby_role_label = Label.new()
	lobby_role_label.text = ""
	lobby_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_role_label.add_theme_font_size_override("font_size", 22)
	box.add_child(lobby_role_label)
	lobby_controls.append(lobby_role_label)

	switch_role_button = Button.new()
	switch_role_button.text = "切换角色"
	switch_role_button.pressed.connect(Callable(self, "_toggle_lobby_roles"))
	box.add_child(switch_role_button)
	lobby_controls.append(switch_role_button)

	start_game_button = Button.new()
	start_game_button.text = "开始游戏"
	start_game_button.pressed.connect(Callable(self, "_start_lobby_game"))
	box.add_child(start_game_button)
	lobby_controls.append(start_game_button)

	var map_page_title := Label.new()
	map_page_title.text = "官方地图列表"
	map_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_page_title.add_theme_font_size_override("font_size", 28)
	box.add_child(map_page_title)
	map_page_controls.append(map_page_title)

	map_list = ItemList.new()
	map_list.custom_minimum_size = Vector2(460.0, 190.0)
	map_list.item_selected.connect(Callable(self, "_on_map_item_selected"))
	for map_info in OFFICIAL_MAPS:
		map_list.add_item(String(map_info.get("name", "官方地图")))
	map_list.select(selected_map_index)
	box.add_child(map_list)
	map_page_controls.append(map_list)

	map_description_label = Label.new()
	map_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(map_description_label)
	map_page_controls.append(map_description_label)

	var map_page_buttons := HBoxContainer.new()
	map_page_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	map_page_buttons.add_theme_constant_override("separation", 10)
	box.add_child(map_page_buttons)
	map_page_controls.append(map_page_buttons)

	var use_map_button := Button.new()
	use_map_button.text = "使用选中地图"
	use_map_button.pressed.connect(Callable(self, "_confirm_map_selection"))
	map_page_buttons.add_child(use_map_button)

	var back_map_button := Button.new()
	back_map_button.text = "返回"
	back_map_button.pressed.connect(Callable(self, "_close_map_page"))
	map_page_buttons.add_child(back_map_button)

	title_status = Label.new()
	title_status.text = ""
	title_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_status)
	_set_lobby_visible(false)
	_set_map_page_visible(false)
	_update_map_ui()

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

func _show_map_page() -> void:
	if game_mode == "lobby" and not multiplayer.is_server():
		return
	map_page_return_mode = "lobby" if game_mode == "lobby" else "menu"
	map_preview_index = selected_map_index
	_set_setup_visible(false)
	_set_menu_visible(false)
	_set_lobby_visible(false)
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
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, "地图已切换为：%s，等待房主开始游戏。" % map_name)
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
		rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, "胜利时间已改为 %d 秒，等待房主开始游戏。" % int(win_time_seconds))
	_update_lobby_ui()

func _refresh_win_time_from_ui() -> void:
	if win_time_spinbox != null:
		win_time_seconds = win_time_spinbox.value

func _show_title(message: String) -> void:
	_close_network()
	_clear_characters()
	game_mode = "title"
	network_started = false
	remote_peer_id = 0
	host_is_runner = true
	caught = false
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
	_update_map_ui()
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
	title_status.text = "正在连接 %s:%d ..." % [ip, PORT]

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server() or network_started:
		return
	remote_peer_id = peer_id
	network_started = true
	_enter_lobby("玩家已加入。双方可在房间内切换角色，房主点击开始游戏。")
	rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, "已加入房间。双方可在房间内切换角色，等待房主开始游戏。")

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
	if title_status != null:
		title_status.text = message
	_update_lobby_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _update_lobby_ui() -> void:
	if lobby_role_label == null:
		return
	var local_role := _local_lobby_role_text()
	var other_role := "抓人者" if local_role == "逃跑者" else "逃跑者"
	lobby_role_label.text = "你的角色：%s\n对方角色：%s\n胜利时间：%d 秒\n地图：%s\n按 Q 退出房间" % [local_role, other_role, int(win_time_seconds), map_name]
	if win_time_spinbox != null:
		win_time_spinbox.editable = multiplayer.is_server()
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	if start_game_button != null:
		start_game_button.visible = multiplayer.is_server()
		start_game_button.disabled = not multiplayer.is_server() or remote_peer_id == 0
	if switch_role_button != null:
		switch_role_button.visible = true
	_update_map_ui()

func _return_to_lobby_after_round() -> void:
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	host_is_runner = not host_is_runner
	_enter_lobby("上一局结束，已自动交换追/被追。房主可继续切换角色、地图或开始下一局。")
	rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, "上一局结束，已自动交换追/被追。等待房主开始下一局。")

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
			rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, "角色已切换，等待房主开始游戏。")
	else:
		rpc_id(1, "_rpc_request_role_switch")

func _start_lobby_game() -> void:
	_refresh_win_time_from_ui()
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	_start_network_round(remote_peer_id)
	rpc("_rpc_begin_network_round", remote_peer_id, host_is_runner, win_time_seconds, selected_map_index)

@rpc("any_peer", "reliable")
func _rpc_request_role_switch() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	host_is_runner = not host_is_runner
	_update_lobby_ui()
	rpc("_rpc_sync_lobby", host_is_runner, win_time_seconds, selected_map_index, "角色已切换，等待房主开始游戏。")

@rpc("call_remote", "reliable")
func _rpc_sync_lobby(new_host_is_runner: bool, new_win_time_seconds: float, new_map_index: int, message: String) -> void:
	host_is_runner = new_host_is_runner
	win_time_seconds = new_win_time_seconds
	_select_official_map(new_map_index, false)
	if win_time_spinbox != null:
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	network_started = true
	_enter_lobby(message)

@rpc("call_remote", "reliable")
func _rpc_begin_network_round(client_id: int, new_host_is_runner: bool, new_win_time_seconds: float, new_map_index: int) -> void:
	remote_peer_id = client_id
	host_is_runner = new_host_is_runner
	win_time_seconds = new_win_time_seconds
	_select_official_map(new_map_index, false)
	if win_time_spinbox != null:
		win_time_spinbox.set_value_no_signal(win_time_seconds)
	network_started = true
	_start_network_round(client_id)

func _start_network_round(client_id: int) -> void:
	_clear_characters()
	if not _load_active_map():
		if title_status != null:
			title_status.text = "地图加载失败，无法开始联机游戏。"
		return
	game_mode = "host" if multiplayer.is_server() else "client"
	caught = false
	time_alive = 0.0
	if title_layer != null:
		title_layer.visible = false
	hud_layer.visible = true
	center_label.text = ""
	_spawn_network_characters(client_id)
	if debug_mode:
		_refresh_debug_collision_shapes()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _spawn_single_characters() -> void:
	player = CharacterBody3D.new()
	player.name = "Runner"
	player.set_script(PlayerScript)
	player.global_position = runner_spawn_position
	add_child(player)

	tagger = CharacterBody3D.new()
	tagger.name = "Tagger"
	tagger.set_script(TaggerScript)
	tagger.global_position = tagger_spawn_position
	add_child(tagger)
	tagger.target = player

func _spawn_network_characters(client_id: int) -> void:
	var runner_peer_id := 1 if host_is_runner else client_id
	var tagger_peer_id := client_id if host_is_runner else 1

	player = CharacterBody3D.new()
	player.name = "NetworkRunner"
	player.set_script(NetworkActorScript)
	player.configure("runner", runner_peer_id)
	player.global_position = runner_spawn_position
	add_child(player)

	tagger = CharacterBody3D.new()
	tagger.name = "NetworkTagger"
	tagger.set_script(NetworkActorScript)
	tagger.configure("tagger", tagger_peer_id)
	tagger.global_position = tagger_spawn_position
	add_child(tagger)

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

func _has_clear_catch_line() -> bool:
	var from: Vector3 = tagger.global_position + Vector3.UP * 1.0
	var to: Vector3 = player.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [tagger.get_rid(), player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func _on_runner_survived() -> void:
	caught = true
	player.is_control_locked = true
	tagger.is_active = false
	center_label.text = "逃跑者胜利！\n成功坚持 %.2f 秒\n%s" % [time_alive, "按 R 重新开始" if game_mode == "single" else "房主按 R 重新开始"]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_survived", time_alive)
		_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_survived(final_time: float) -> void:
	caught = true
	time_alive = final_time
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "逃跑者胜利！\n成功坚持 %.2f 秒\n房主按 R 重新开始" % final_time
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_player_caught() -> void:
	_finish_runner_failed("逃跑者被抓到了！")

func _on_runner_fell() -> void:
	_finish_runner_failed("逃跑者掉出地图！")

func _finish_runner_failed(reason: String) -> void:
	caught = true
	player.is_control_locked = true
	tagger.is_active = false
	center_label.text = "%s\n抓人者胜利\n坚持了 %.2f 秒\n%s" % [reason, time_alive, "按 R 重新开始" if game_mode == "single" else "房主按 R 重新开始"]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_failed", time_alive, reason)
		_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_failed(final_time: float, reason: String) -> void:
	caught = true
	time_alive = final_time
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "%s\n抓人者胜利\n坚持了 %.2f 秒\n房主按 R 重新开始" % [reason, final_time]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _setup_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.7, 0.82)
	env.ambient_light_energy = 0.9
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

	var panel := ColorRect.new()
	panel.color = Color(0.0, 0.0, 0.0, 0.42)
	panel.anchor_right = 1.0
	panel.offset_bottom = 130.0
	hud_layer.add_child(panel)

	hud_label = Label.new()
	hud_label.position = Vector2(18.0, 12.0)
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.text = ""
	hud_layer.add_child(hud_label)

	center_label = Label.new()
	center_label.anchor_right = 1.0
	center_label.anchor_bottom = 1.0
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 34)
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

func _bind_key(action_name: String, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.keycode == keycode:
			return
	var key := InputEventKey.new()
	key.keycode = keycode
	InputMap.action_add_event(action_name, key)
