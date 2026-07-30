extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const RunnerAIScript = preload("res://scripts/runner_ai.gd")
const RLPolicyRunnerScript = preload("res://scripts/rl_policy_runner.gd")
const TaggerScript = preload("res://scripts/tagger.gd")
const RLPolicyTaggerScript = preload("res://scripts/rl_policy_tagger.gd")
const NetworkActorScript = preload("res://scripts/network_actor.gd")
const MapLoader = preload("res://scripts/map_loader.gd")
const SkinAPI = preload("res://scripts/skin_api.gd")
const NETHER_SKY_SHADER = preload("res://scripts/nether_sky.gdshader")
const LAVA_FLOW_SHADER = preload("res://scripts/lava_flow.gdshader")
const CatchAttackIconScript = preload("res://scripts/catch_attack_icon.gd")
const BasketballKillSequenceScript = preload("res://scripts/basketball_kill_sequence.gd")
# 减速弹与药剂模型来自 Quaternius/Poly Pizza（CC0 1.0）；透视卡为项目内建立体模型。
const THROWABLE_MODEL_PATH := "res://assets/throwables/scifi_slow_grenade.glb"
const SPEED_BOOST_MODEL_PATH := "res://assets/throwables/speed_boost_potion.glb"
const VISION_CARD_MODEL_PATH := "res://assets/throwables/vision_card.tscn"
const CHASE_MUSIC_PATH := "res://assets/audio/chase_loop.ogg"
const RUNNER_THROW_SOUND_PATH := "res://assets/audio/runner_throw.ogg"
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MUSIC_VOLUME := 100.0
const DEFAULT_THROW_VOLUME := 100.0
const ITEM_TYPE_SLOW_GRENADE := "slow_grenade"
const ITEM_TYPE_SPEED_BOOST := "speed_boost"
const ITEM_TYPE_VISION_CARD := "vision_card"
const PORT = 24591
const BASKETBALL_SECRET_CODE := "0721"
# 发布/功能变更时请同步更新该版本号；主界面右下角会显示它。
const GAME_VERSION := "1.6.0"
const CUSTOM_SKIN_OPTION_ID := "__custom_image_skin__"
const USE_RL_POLICY_TAGGER := true
const USE_RL_POLICY_RUNNER := true
const VOID_Y = -12.0
const DEFAULT_SKY_COLOR := Color(0.48, 0.78, 1.0)
const DEFAULT_MAP_PATH = "res://maps/default_arena.json"
const DEFAULT_MAP_BGM_PATH := "res://assets/audio/chase_loop.ogg"
const MENU_BGM_PATH := "res://assets/audio/bgm_menu.mp3"
const CUSTOM_FONT_PATH := "res://assets/fonts/FusionPixel12-Proportional-zh_hans.ttf"
const USER_MAP_PATH = "user://maps/current_map.json"
const NETWORK_SYNC_MAP_PATH = "user://network_sync/maps/host_map.json"
const NETWORK_SYNC_SKIN_PREFIX = "network_host_"
const MULTIPLAYER_RESULT_DELAY := 3.0
const NETWORK_ACTIVE_TIMEOUT_MIN_MS := 1500
const NETWORK_ACTIVE_TIMEOUT_MAX_MS := 10000
const NETWORK_LOADING_TIMEOUT_MIN_MS := 10000
const NETWORK_LOADING_TIMEOUT_MAX_MS := 120000
const NETWORK_ROUND_READY_TIMEOUT_SECONDS := 125.0
const CATCH_RANGE := 2.5
const CATCH_COOLDOWN := 1.5
const CATCH_HALF_ANGLE_COS := 0.0
const AI_CATCH_COOLDOWN := CATCH_COOLDOWN
const CATCH_ORIGIN_TOLERANCE := 2.2
const THROWABLE_RESPAWN_TARGET := 12
const THROWABLE_RESPAWN_INTERVAL := 1.0
const THROWABLE_PICKUP_RANGE := 2.1
const THROWABLE_THROW_SPEED := 20.0
const THROWABLE_THROW_UPWARD_BONUS := 1.6
const THROWABLE_PROJECTILE_GRAVITY := 16.0
const THROWABLE_PROJECTILE_RADIUS := 0.95
const THROWABLE_PROJECTILE_LIFETIME := 3.4
const THROWABLE_SLOW_MULTIPLIER := 0.58
const THROWABLE_SLOW_DURATION := 2.6
const SPEED_BOOST_MULTIPLIER := 1.45
const SPEED_BOOST_DURATION := 2.0
const SPEED_BOOST_SPAWN_CHANCE := 0.35
const TAGGER_CARD_RESPAWN_TARGET := 6
const TAGGER_VISION_CARD_DURATION := 7.0
const HUD_REFERENCE_HEIGHT := 720.0
const HUD_FULLSCREEN_SCALE_BONUS := 1.10
const HUD_FULLSCREEN_MAX_SCALE := 1.80
const THROWABLE_MIN_SPAWN_GAP := 3.6
const THROWABLE_SPAWN_ATTEMPTS := 32
const THROWABLE_SPAWN_CLEARANCE_HEIGHT := 1.8
const THROWABLE_SPAWN_CLEARANCE_RADIUS := 0.32
const THROWABLE_MIN_SURFACE_NORMAL_Y := 0.7
const THROWABLE_ACTIVE_LEVEL_TOLERANCE := 3.25
const THROWABLE_MAX_SURFACE_LAYERS := 12
# 主动楼层发现：不再让道具高度被出生点绑定，而是扫描整张地图收集所有可站立楼层。
const THROWABLE_LEVEL_SCAN_COLUMNS := 40          # 水平扫描列数（网格采样点，越大越精细）
const THROWABLE_LEVEL_SCAN_TOP := 80.0           # 每列向下射线的起始高度（相对出生层顶部）
const THROWABLE_LEVEL_SCAN_BOTTOM := 60.0        # 每列向下射线的终止深度（相对出生层底部）
const THROWABLE_LEVEL_SCAN_MAX_LAYERS := 16      # 每列逐层排除时的最大楼层数
const THROWABLE_LEVEL_CLUSTER_TOLERANCE := 1.6   # 楼层聚类容差：高度差小于此值视为同一层
const THROWABLE_LEVEL_MIN_SAMPLES := 2           # 一个楼层至少被命中多少次才算有效（滤除孤立薄板）
const THROWABLE_LEVEL_SCAN_RADIUS_MIN := 18.0    # 网格扫描的最小半径
const THROWABLE_LEVEL_SCAN_RADIUS_MAX := 60.0    # 网格扫描的最大半径
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
const WIN_MODE_HITS := "hits"
const WIN_MODE_SURVIVAL := "survival"
const DEFAULT_HITS_TO_WIN := 10
const MIN_HITS_TO_WIN := 1
const MAX_HITS_TO_WIN := 100
const DEFAULT_SURVIVAL_TIME_SECONDS := 60.0
const DEFAULT_HITS_TIME_SECONDS := 300.0
const MIN_WIN_TIME_SECONDS := 10.0
const MAX_WIN_TIME_SECONDS := 3600.0
const SLOW_PARTICLE_MOVE_THRESHOLD := 0.18
const ACTION_CONFIRM_DURATION := 2.0
const OPPONENT_MINIMAP_MEMORY := 5.0
const OPPONENT_SIGHT_RANGE := 28.0
const RUNNER_THREAT_RED_DISTANCE := 8.0
const DEFAULT_MINIMAP_WORLD_RADIUS := 42.0
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
	},
	{
		"name": "下界要塞",
		"path": "res://maps/nether_fortress.json",
		"description": "大尺度三层露顶下界要塞：中央四向悬空桥、环形回廊与多座楼梯塔，断桥跳台、柱顶捷径与烈焰塔、下界疣房；无岩浆改为虚空坠落风险，点缀大型绯红菌。"
	},
	{
		"name": "冬日小镇",
		"path": "res://maps/winter_town.json",
		"description": "MCC Winter Town 风格的紧凑雪地箱庭：中央圣诞树、礼物跳台、冰面捷径、四向木屋与连通屋顶组成多层追逐路线。"
	},
	{
		"name": "城市训练工地",
		"path": "res://maps/urban_training_site.json",
		"description": "v2 写实标杆地图：工业街区、仓库灯光、二层平台、低障碍翻越点和清晰追逐路线。"
	},
	{
		"name": "猴子旅馆走廊",
		"path": "res://maps/monkey_hotel_corridors.json",
		"description": "昏暗压抑的旅馆迷宫走廊：低环境光配暗红体积雾，沿路贴顶灯座投下昏黄点光，只照亮近处路径，灯与灯之间陷入黑暗。"
	},
	{
		"name": "Dragon Palace · 龙馆道场",
		"path": "res://maps/dragon_palace.json",
		"description": "复刻《Mario Kart 8 Deluxe》对战场地：南侧双龙庭院连接北侧圆形道场；双屏风直达一层，左右耳形坡道直达二层，室内圆形回廊与回落坡道形成完整立体环路。"
	}
]

var player
var tagger
var hud_layer: CanvasLayer
var hud_status_panel: PanelContainer
var hud_status_margin: MarginContainer
var hud_label: Label
var round_time_label: Label
var center_label: Label
var throwable_notice_label: Label
var runner_inventory_bar: HBoxContainer
var slow_grenade_slot: PanelContainer
var speed_boost_slot: PanelContainer
var slow_grenade_slot_label: Label
var speed_boost_slot_label: Label
var tagger_inventory_bar: HBoxContainer
var vision_card_slot: PanelContainer
var vision_card_slot_label: Label
var catch_cd_label: Control
var direction_marker_label: Label
var threat_overlay: ColorRect
var minimap_panel: PanelContainer
var minimap_content: Control
var minimap_opponent_dot: ColorRect
var minimap_player_dot: ColorRect
var minimap_reward_dots: Array[ColorRect] = []
var title_layer: CanvasLayer
var map_loading_layer: CanvasLayer
var map_loading_title: Label
var map_loading_label: Label
var title_status: Label
var ip_input: LineEdit
var win_mode_label: Label
var win_mode_previous_button: Button
var win_mode_next_button: Button
var win_target_row: HBoxContainer
var win_target_label: Label
var win_target_spinbox: SpinBox
var win_target_unit_label: Label
var win_time_row: HBoxContainer
var win_time_spinbox: SpinBox
var map_summary_label: Label
var map_select_button: Button
var map_list: ItemList
var map_description_label: Label
var settings_display_mode_option: OptionButton
var settings_music_volume_slider: HSlider
var settings_music_volume_value: Label
var settings_throw_volume_slider: HSlider
var settings_throw_volume_value: Label
var music_volume_percent := DEFAULT_MUSIC_VOLUME
var throw_volume_percent := DEFAULT_THROW_VOLUME
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
# When true a single_chase round runs with BOTH sides driven by the trained
# self-play AI so the player can watch the tagger and runner fight each other.
var ai_vs_ai_spectate := false
var basketball_finish_mode := false
var basketball_finish_playing := false
var basketball_sequence: Node3D = null
var spectator_camera: Camera3D = null
var network_started := false
var network_round_loading := false
var network_round_load_token := 0
var local_round_load_ready := false
var remote_round_load_ready := false
var remote_peer_id := 0
var host_is_runner := true
var win_mode := WIN_MODE_SURVIVAL
var hits_to_win := DEFAULT_HITS_TO_WIN
var survival_time_seconds := DEFAULT_SURVIVAL_TIME_SECONDS
var hits_time_seconds := DEFAULT_HITS_TIME_SECONDS
var win_time_seconds := DEFAULT_SURVIVAL_TIME_SECONDS
var is_leaving_room := false
var round_transition_token := 0
var map_root: Node3D
var world_environment: WorldEnvironment
var sun_light: DirectionalLight3D
var map_name := "默认地图"
var active_map_path := ""
var minimap_world_radius := DEFAULT_MINIMAP_WORLD_RADIUS
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
# 主动发现的所有可站立楼层高度（升序），由 _discover_spawnable_levels() 填充并缓存。
var discovered_throwable_levels: Array[float] = []
# 每层已发现的水平采样点，用于把撒点集中到该层真实存在地面的区域。
var discovered_level_samples: Array = []
# 楼层轮转索引，保证道具在各楼层之间均衡分配。
var throwable_level_cursor := 0

var throwable_root: Node3D
var throwable_trajectory: MeshInstance3D
var throwable_trajectory_dots: Node3D
var throwable_landing_marker: MeshInstance3D
var held_throwable_visual: Node3D
var held_speed_boost_visual: Node3D
var held_vision_card_visual: Node3D
var ground_throwables: Dictionary = {}
var flying_throwables: Dictionary = {}
var runner_has_slow_grenade := false
var runner_has_speed_boost := false
var tagger_has_vision_card := false
var tagger_vision_timer := 0.0
var throwable_respawn_timer := THROWABLE_RESPAWN_INTERVAL
var next_ground_throwable_id := 1
var next_flying_throwable_id := 1
var throwable_notice_timer := 0.0
var throwable_notice_protect_timer := 0.0
var tagger_slow_particles: Node3D
var vision_outline_entries: Array[Dictionary] = []
var vision_outline_material: ShaderMaterial
var tagger_slow_particle_timer := 0.0
var tagger_slow_particle_elapsed := 0.0
var tagger_slow_particle_last_position := Vector3.ZERO
var tagger_hit_count := 0
var ai_runner_throw_cooldown := 0.0
var quit_confirm_timer := 0.0
var restart_confirm_timer := 0.0
var opponent_seen_timer := 0.0
var last_seen_opponent_position := Vector3.ZERO
var active_map_bgm_enabled := true
var active_map_bgm_loop := true
var active_map_bgm_path := DEFAULT_MAP_BGM_PATH
var active_map_bgm_volume_db := 0.0
@onready var chase_music: AudioStreamPlayer = $ChaseMusic
@onready var menu_music: AudioStreamPlayer = $MenuMusic
@onready var runner_throw_sound: AudioStreamPlayer = $RunnerThrowSound

func _ready() -> void:
	randomize()
	_setup_runtime_font()
	_load_audio_settings()
	_setup_chase_music()
	_setup_menu_music()
	_setup_runner_throw_sound()
	_apply_audio_volumes()
	_ensure_default_fullscreen()
	_ensure_input_actions()
	_connect_multiplayer_signals()
	_setup_world()
	_build_hud()
	get_viewport().size_changed.connect(_apply_hud_layout_scale)
	_build_title_ui()
	_build_map_loading_ui()
	_show_title("")
	_load_active_map()

func _setup_runtime_font() -> void:
	if not FileAccess.file_exists(CUSTOM_FONT_PATH):
		push_warning("自定义字体文件不存在：%s" % CUSTOM_FONT_PATH)
		return
	var font_data := FileAccess.get_file_as_bytes(CUSTOM_FONT_PATH)
	if font_data.is_empty():
		push_warning("自定义字体文件为空：%s" % CUSTOM_FONT_PATH)
		return
	var font := FontFile.new()
	font.data = font_data
	ThemeDB.fallback_font = font

func _load_raw_audio(path: String, should_loop: bool) -> AudioStream:
	if not FileAccess.file_exists(path):
		push_error("音频文件不存在：%s" % path)
		return null
	var sound_data := FileAccess.get_file_as_bytes(path)
	if sound_data.is_empty():
		push_error("音频文件为空：%s" % path)
		return null
	var sound_stream: AudioStream
	match path.get_extension().to_lower():
		"ogg":
			var ogg_stream := AudioStreamOggVorbis.load_from_buffer(sound_data)
			if ogg_stream != null:
				ogg_stream.loop = should_loop
				sound_stream = ogg_stream
		"mp3":
			var mp3_stream := AudioStreamMP3.load_from_buffer(sound_data)
			if mp3_stream != null:
				mp3_stream.loop = should_loop
				sound_stream = mp3_stream
	if sound_stream == null:
		push_error("无法读取音频：%s" % path)
	return sound_stream

func _setup_chase_music() -> void:
	chase_music.stop()
	if not chase_music.finished.is_connected(_on_chase_music_finished):
		chase_music.finished.connect(_on_chase_music_finished)

func _setup_runner_throw_sound() -> void:
	runner_throw_sound.stop()
	runner_throw_sound.stream = _load_raw_audio(RUNNER_THROW_SOUND_PATH, false)

func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		music_volume_percent = DEFAULT_MUSIC_VOLUME
		throw_volume_percent = DEFAULT_THROW_VOLUME
		return
	music_volume_percent = clampf(float(config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 100.0)
	throw_volume_percent = clampf(float(config.get_value("audio", "throw_volume", DEFAULT_THROW_VOLUME)), 0.0, 100.0)

func _save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", music_volume_percent)
	config.set_value("audio", "throw_volume", throw_volume_percent)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("保存音量设置失败：%s" % error_string(error))

func _percent_to_volume_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)

func _apply_audio_volumes() -> void:
	var music_volume_db := _percent_to_volume_db(music_volume_percent)
	if chase_music != null:
		chase_music.volume_db = clampf(active_map_bgm_volume_db + music_volume_db, -80.0, 6.0)
	if menu_music != null:
		menu_music.volume_db = music_volume_db
	if runner_throw_sound != null:
		runner_throw_sound.volume_db = _percent_to_volume_db(throw_volume_percent)

func _update_audio_settings_ui() -> void:
	if settings_music_volume_slider != null:
		settings_music_volume_slider.set_value_no_signal(music_volume_percent)
	if settings_music_volume_value != null:
		settings_music_volume_value.text = "%d%%" % roundi(music_volume_percent)
	if settings_throw_volume_slider != null:
		settings_throw_volume_slider.set_value_no_signal(throw_volume_percent)
	if settings_throw_volume_value != null:
		settings_throw_volume_value.text = "%d%%" % roundi(throw_volume_percent)

func _on_music_volume_changed(value: float) -> void:
	music_volume_percent = clampf(value, 0.0, 100.0)
	_apply_audio_volumes()
	_update_audio_settings_ui()
	_save_audio_settings()

func _on_throw_volume_changed(value: float) -> void:
	throw_volume_percent = clampf(value, 0.0, 100.0)
	_apply_audio_volumes()
	_update_audio_settings_ui()
	_save_audio_settings()

func _ensure_audio_preview_stream(player: AudioStreamPlayer, path: String, should_loop: bool) -> bool:
	if player == null:
		return false
	if player.stream == null:
		player.stream = _load_raw_audio(path, should_loop)
	return player.stream != null

func _on_test_music_pressed() -> void:
	if chase_music.stream == null:
		chase_music.stream = _load_map_bgm_stream(active_map_bgm_path)
	if chase_music.stream == null:
		return
	_stop_menu_music()
	chase_music.stop()
	chase_music.play()

func _on_test_throw_sound_pressed() -> void:
	if not _ensure_audio_preview_stream(runner_throw_sound, RUNNER_THROW_SOUND_PATH, false):
		return
	runner_throw_sound.stop()
	runner_throw_sound.play()

func _stop_audio_previews() -> void:
	if game_mode == "title":
		chase_music.stop()
		_start_menu_music()
	if runner_throw_sound != null:
		runner_throw_sound.stop()

func _on_chase_music_finished() -> void:
	if active_map_bgm_loop:
		_start_chase_music()

func _setup_menu_music() -> void:
	if menu_music == null:
		return
	if not menu_music.finished.is_connected(_on_menu_music_finished):
		menu_music.finished.connect(_on_menu_music_finished)
	menu_music.stop()

func _on_menu_music_finished() -> void:
	if game_mode == "title":
		_start_menu_music()

func _start_menu_music() -> void:
	if menu_music == null:
		return
	if menu_music.stream == null:
		menu_music.stream = _load_raw_audio(MENU_BGM_PATH, true)
		if menu_music.stream == null:
			push_warning("初始界面 BGM 资源未找到：%s" % MENU_BGM_PATH)
			return
	if not menu_music.playing:
		menu_music.play()

func _stop_menu_music() -> void:
	if menu_music != null:
		menu_music.stop()

func _apply_map_bgm(config: Dictionary) -> void:
	_stop_chase_music()
	active_map_bgm_enabled = bool(config.get("enabled", true))
	active_map_bgm_loop = bool(config.get("loop", true))
	active_map_bgm_path = String(config.get("path", "")).strip_edges()
	if active_map_bgm_path.is_empty():
		active_map_bgm_path = DEFAULT_MAP_BGM_PATH
	active_map_bgm_volume_db = clampf(float(config.get("volume_db", 0.0)), -80.0, 6.0)
	_apply_audio_volumes()
	if not active_map_bgm_enabled:
		chase_music.stream = null
		return
	var stream := _load_map_bgm_stream(active_map_bgm_path)
	if stream == null and active_map_bgm_path != DEFAULT_MAP_BGM_PATH:
		push_warning("地图 BGM 加载失败，使用默认音乐：%s" % active_map_bgm_path)
		active_map_bgm_path = DEFAULT_MAP_BGM_PATH
		stream = _load_map_bgm_stream(DEFAULT_MAP_BGM_PATH)
	chase_music.stream = stream

func _load_map_bgm_stream(path: String) -> AudioStream:
	var stream := _load_raw_audio(path, active_map_bgm_loop)
	if stream != null:
		return stream
	# 为导出包中的其他 AudioStream 格式保留资源加载回退。
	if ResourceLoader.exists(path, "AudioStream"):
		stream = ResourceLoader.load(path, "AudioStream") as AudioStream
	if stream == null:
		return null
	stream = stream.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = active_map_bgm_loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = active_map_bgm_loop
	return stream

func _start_chase_music() -> void:
	_stop_menu_music()
	if not active_map_bgm_enabled:
		return
	if network_round_loading or map_loading_layer == null or map_loading_layer.visible:
		return
	if game_mode != "single" and game_mode != "single_chase" and game_mode != "host" and game_mode != "client":
		return
	if chase_music.stream == null:
		push_error("地图 BGM 资源未加载：%s" % active_map_bgm_path)
		return
	if not chase_music.playing:
		chase_music.play()

func _stop_chase_music() -> void:
	chase_music.stop()

func _process(delta: float) -> void:
	quit_confirm_timer = maxf(quit_confirm_timer - delta, 0.0)
	restart_confirm_timer = maxf(restart_confirm_timer - delta, 0.0)
	if center_label != null and quit_confirm_timer <= 0.0 and restart_confirm_timer <= 0.0 and (center_label.text == "再按一次 Q 返回标题/房间" or center_label.text == "再按一次 R 重新开始本局"):
		center_label.text = ""
	if basketball_finish_playing:
		return
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

	if game_mode == "title" or game_mode == "waiting" or game_mode == "lobby" or network_round_loading:
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
			_start_ai_vs_ai_game() if ai_vs_ai_spectate else _start_single_chase_game()
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
	if (game_mode == "single" or game_mode == "single_chase" or game_mode == "host") \
	and time_alive >= win_time_seconds:
		_on_runner_time_limit_survived()
		return
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
	_update_round_hud()
	_update_runner_inventory_hud()
	_update_tagger_inventory_hud()
	_update_catch_crosshair()
	_update_direction_marker()
	_update_threat_overlay(distance)
	_update_minimap(delta)

	if _local_is_runner() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("pickup_item"):
			_request_local_throwable_pickup()
		if Input.is_action_just_pressed("throw_item"):
			_request_local_throwable_throw()
		if Input.is_action_just_pressed("use_speed_boost"):
			_request_local_speed_boost_use()

	if _local_is_tagger() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("pickup_item"):
			_request_local_tagger_card_pickup()
		if Input.is_action_just_pressed("use_speed_boost"):
			_request_local_vision_card_use()
		if Input.is_action_just_pressed("catch_attack"):
			_request_local_catch_attempt()

	if game_mode == "single" or ai_vs_ai_spectate:
		if tagger.has_method("set_rl_match_context"):
			tagger.set_rl_match_context(ai_catch_cooldown <= 0.0, tagger_hit_count, hits_to_win, maxf(win_time_seconds - time_alive, 0.0), win_time_seconds)
		_try_ai_catch_attempt(distance)

	if ai_vs_ai_spectate:
		_update_spectator_camera(delta)

func _format_round_time(seconds: float) -> String:
	var total := maxi(int(ceil(maxf(seconds, 0.0))), 0)
	return "%02d:%02d" % [total / 60, total % 60]

func _update_round_hud() -> void:
	if hud_label == null:
		return
	var text := ""
	var remaining := maxf(win_time_seconds - time_alive, 0.0)
	if win_mode == WIN_MODE_SURVIVAL:
		if round_time_label != null:
			round_time_label.text = "剩余时间  %s" % _format_round_time(remaining)
		text = "限时躲藏"
	else:
		if round_time_label != null:
			round_time_label.text = "剩余时间  %s\n命中进度  %d / %d" % [_format_round_time(remaining), tagger_hit_count, hits_to_win]
		text = "命中获胜"
	var local_actor := _local_controlled_actor()
	if local_actor != null:
		var actor_position: Vector3 = local_actor.global_position
		text += "\n坐标  X %.1f  Y %.1f  Z %.1f" % [actor_position.x, actor_position.y, actor_position.z]
	hud_label.text = text

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
	item_list.add_theme_color_override("font_selected_color", Color(0.32, 0.34, 0.4))
	item_list.add_theme_color_override("guide_color", Color(1.0, 0.62, 0.18, 0.45))
	item_list.add_theme_font_size_override("font_size", 18)

func _apply_label_style(label: Label, color: Color = Color(0.18, 0.22, 0.42), outline_size: int = 2) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.72))
	label.add_theme_constant_override("outline_size", outline_size)

func _build_map_loading_ui() -> void:
	map_loading_layer = CanvasLayer.new()
	map_loading_layer.name = "MapLoadingUI"
	map_loading_layer.layer = 20
	add_child(map_loading_layer)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.025, 0.055, 0.98)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	map_loading_layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_loading_layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560.0, 224.0)
	card.add_theme_stylebox_override("panel", _cartoon_style(Color(0.08, 0.15, 0.28, 0.98), Color(0.28, 0.82, 1.0), 5, 24, Vector2(0.0, 10.0), 18))
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	map_loading_title = Label.new()
	map_loading_title.text = "加载中"
	map_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_loading_title.add_theme_font_size_override("font_size", 42)
	map_loading_title.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	map_loading_title.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.08, 0.95))
	map_loading_title.add_theme_constant_override("outline_size", 5)
	box.add_child(map_loading_title)

	map_loading_label = Label.new()
	map_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_loading_label.add_theme_font_size_override("font_size", 21)
	map_loading_label.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	box.add_child(map_loading_label)

	var hint := Label.new()
	hint.text = "请稍候，场景资源首次加载可能需要几秒钟"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	box.add_child(hint)
	map_loading_layer.visible = false

func _build_title_ui() -> void:
	title_layer = CanvasLayer.new()
	title_layer.name = "TitleUI"
	add_child(title_layer)

	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var bg_path := "res://assets/title_bg/adapted/parkour_tag_cartoon.png"
	var bg_file_path := ProjectSettings.globalize_path(bg_path)
	# 优先直接读取高清源图，避免继续使用 .godot/imported 中旧的低分辨率缓存。
	if FileAccess.file_exists(bg_file_path):
		var img := Image.load_from_file(bg_file_path)
		if img != null and not img.is_empty():
			bg.texture = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(bg_path):
		bg.texture = ResourceLoader.load(bg_path) as Texture2D
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	title_layer.add_child(bg)

	var version_label := Label.new()
	version_label.text = "v%s" % GAME_VERSION
	version_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	version_label.offset_right = -24.0
	version_label.offset_bottom = -18.0
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	version_label.add_theme_font_size_override("font_size", 22)
	_apply_label_style(version_label, Color(1.0, 1.0, 1.0, 1.0), 6)
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	version_label.z_index = 100
	title_layer.add_child(version_label)

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
	title.text = "椅子大逃亡 2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.43, 0.14))
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.18, 0.32))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	# 仅在模式名称上方留白；下方的回合限时输入行紧跟模式名称。
	var win_mode_margin := MarginContainer.new()
	win_mode_margin.add_theme_constant_override("margin_top", 10)
	box.add_child(win_mode_margin)
	setup_controls.append(win_mode_margin)

	var win_mode_selector := HBoxContainer.new()
	win_mode_selector.alignment = BoxContainer.ALIGNMENT_CENTER
	win_mode_selector.add_theme_constant_override("separation", 14)
	win_mode_margin.add_child(win_mode_selector)

	win_mode_previous_button = Button.new()
	win_mode_previous_button.text = "◀"
	win_mode_previous_button.tooltip_text = "上一个模式"
	win_mode_previous_button.custom_minimum_size = Vector2(58.0, 52.0)
	win_mode_previous_button.add_theme_font_size_override("font_size", 24)
	_style_button(win_mode_previous_button, Color(0.15, 0.61, 1.0), Color(0.06, 0.29, 0.58))
	win_mode_previous_button.pressed.connect(Callable(self, "_switch_win_mode").bind(-1))
	win_mode_selector.add_child(win_mode_previous_button)

	win_mode_label = Label.new()
	win_mode_label.custom_minimum_size = Vector2(330.0, 52.0)
	win_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win_mode_label.add_theme_font_size_override("font_size", 30)
	win_mode_label.add_theme_color_override("font_color", Color(0.92, 0.27, 0.12))
	win_mode_label.add_theme_color_override("font_outline_color", Color(1.0, 0.91, 0.62))
	win_mode_label.add_theme_constant_override("outline_size", 5)
	win_mode_selector.add_child(win_mode_label)

	win_mode_next_button = Button.new()
	win_mode_next_button.text = "▶"
	win_mode_next_button.tooltip_text = "下一个模式"
	win_mode_next_button.custom_minimum_size = Vector2(58.0, 52.0)
	win_mode_next_button.add_theme_font_size_override("font_size", 24)
	_style_button(win_mode_next_button, Color(1.0, 0.52, 0.17), Color(0.64, 0.23, 0.06))
	win_mode_next_button.pressed.connect(Callable(self, "_switch_win_mode").bind(1))
	win_mode_selector.add_child(win_mode_next_button)

	win_time_row = HBoxContainer.new()
	win_time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	win_time_row.add_theme_constant_override("separation", 10)
	box.add_child(win_time_row)
	setup_controls.append(win_time_row)

	var win_time_label := Label.new()
	win_time_label.text = "回合限时"
	_apply_label_style(win_time_label)
	win_time_row.add_child(win_time_label)

	win_time_spinbox = SpinBox.new()
	win_time_spinbox.custom_minimum_size = Vector2(150.0, 48.0)
	win_time_spinbox.min_value = MIN_WIN_TIME_SECONDS
	win_time_spinbox.max_value = MAX_WIN_TIME_SECONDS
	win_time_spinbox.step = 10.0
	win_time_spinbox.value = win_time_seconds
	win_time_spinbox.add_theme_font_size_override("font_size", 24)
	win_time_spinbox.get_line_edit().add_theme_font_size_override("font_size", 24)
	win_time_spinbox.value_changed.connect(Callable(self, "_on_win_time_changed"))
	win_time_row.add_child(win_time_spinbox)

	var win_time_unit_label := Label.new()
	win_time_unit_label.text = "秒"
	_apply_label_style(win_time_unit_label)
	win_time_row.add_child(win_time_unit_label)

	# 将模式差异占位放到回合限时输入行之后，保证限时输入紧跟模式名称，
	# 同时保持下方地图、皮肤和视角选项在切换模式时位置不变。
	var win_target_slot := CenterContainer.new()
	win_target_slot.custom_minimum_size = Vector2(0.0, 48.0)
	box.add_child(win_target_slot)
	setup_controls.append(win_target_slot)

	win_target_row = HBoxContainer.new()
	win_target_row.alignment = BoxContainer.ALIGNMENT_CENTER
	win_target_row.add_theme_constant_override("separation", 10)
	win_target_slot.add_child(win_target_row)

	win_target_label = Label.new()
	_apply_label_style(win_target_label)
	win_target_row.add_child(win_target_label)

	win_target_spinbox = SpinBox.new()
	win_target_spinbox.custom_minimum_size = Vector2(150.0, 48.0)
	win_target_spinbox.add_theme_font_size_override("font_size", 24)
	win_target_spinbox.get_line_edit().add_theme_font_size_override("font_size", 24)
	win_target_spinbox.value_changed.connect(Callable(self, "_on_win_target_changed"))
	win_target_row.add_child(win_target_spinbox)

	win_target_unit_label = Label.new()
	_apply_label_style(win_target_unit_label)
	win_target_row.add_child(win_target_unit_label)

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

	_update_win_mode_ui()
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
	single_button.pressed.connect(Callable(self, "_start_normal_single_game"))
	box.add_child(single_button)
	menu_controls.append(single_button)

	var single_chase_button := Button.new()
	single_chase_button.text = "单人模式：追逐者 VS AI 躲藏者"
	_style_button(single_chase_button, Color(0.9, 0.28, 0.2), Color(0.48, 0.08, 0.06))
	single_chase_button.pressed.connect(Callable(self, "_start_single_chase_game"))
	box.add_child(single_chase_button)
	menu_controls.append(single_chase_button)

	var ai_vs_ai_button := Button.new()
	ai_vs_ai_button.text = "观战模式：追逐 AI VS 躲藏 AI"
	_style_button(ai_vs_ai_button, Color(0.55, 0.32, 0.85), Color(0.22, 0.1, 0.42))
	ai_vs_ai_button.pressed.connect(Callable(self, "_start_ai_vs_ai_game"))
	box.add_child(ai_vs_ai_button)
	menu_controls.append(ai_vs_ai_button)

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
	ip_input.text_submitted.connect(Callable(self, "_on_ip_input_submitted"))
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

	var music_volume_row := HBoxContainer.new()
	music_volume_row.alignment = BoxContainer.ALIGNMENT_CENTER
	music_volume_row.add_theme_constant_override("separation", 12)
	box.add_child(music_volume_row)
	settings_controls.append(music_volume_row)

	var music_volume_label := Label.new()
	music_volume_label.text = "背景音乐"
	music_volume_label.custom_minimum_size = Vector2(105.0, 0.0)
	_apply_label_style(music_volume_label)
	music_volume_row.add_child(music_volume_label)

	settings_music_volume_slider = HSlider.new()
	settings_music_volume_slider.custom_minimum_size = Vector2(270.0, 36.0)
	settings_music_volume_slider.min_value = 0.0
	settings_music_volume_slider.max_value = 100.0
	settings_music_volume_slider.step = 1.0
	settings_music_volume_slider.value = music_volume_percent
	settings_music_volume_slider.tooltip_text = "调节对局中的背景音乐音量"
	settings_music_volume_slider.value_changed.connect(Callable(self, "_on_music_volume_changed"))
	music_volume_row.add_child(settings_music_volume_slider)

	settings_music_volume_value = Label.new()
	settings_music_volume_value.custom_minimum_size = Vector2(58.0, 0.0)
	settings_music_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_label_style(settings_music_volume_value, Color(0.1, 0.38, 0.7), 1)
	music_volume_row.add_child(settings_music_volume_value)

	var test_music_button := Button.new()
	test_music_button.text = "测试"
	test_music_button.custom_minimum_size = Vector2(74.0, 38.0)
	test_music_button.tooltip_text = "按当前音量播放游戏中的背景音乐"
	_style_button(test_music_button, Color(0.35, 0.76, 1.0), Color(0.05, 0.3, 0.55))
	test_music_button.pressed.connect(Callable(self, "_on_test_music_pressed"))
	music_volume_row.add_child(test_music_button)

	var throw_volume_row := HBoxContainer.new()
	throw_volume_row.alignment = BoxContainer.ALIGNMENT_CENTER
	throw_volume_row.add_theme_constant_override("separation", 12)
	box.add_child(throw_volume_row)
	settings_controls.append(throw_volume_row)

	var throw_volume_label := Label.new()
	throw_volume_label.text = "投掷音效"
	throw_volume_label.custom_minimum_size = Vector2(105.0, 0.0)
	_apply_label_style(throw_volume_label)
	throw_volume_row.add_child(throw_volume_label)

	settings_throw_volume_slider = HSlider.new()
	settings_throw_volume_slider.custom_minimum_size = Vector2(270.0, 36.0)
	settings_throw_volume_slider.min_value = 0.0
	settings_throw_volume_slider.max_value = 100.0
	settings_throw_volume_slider.step = 1.0
	settings_throw_volume_slider.value = throw_volume_percent
	settings_throw_volume_slider.tooltip_text = "调节逃跑者投掷时双方听到的音效音量"
	settings_throw_volume_slider.value_changed.connect(Callable(self, "_on_throw_volume_changed"))
	throw_volume_row.add_child(settings_throw_volume_slider)

	settings_throw_volume_value = Label.new()
	settings_throw_volume_value.custom_minimum_size = Vector2(58.0, 0.0)
	settings_throw_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_label_style(settings_throw_volume_value, Color(0.1, 0.38, 0.7), 1)
	throw_volume_row.add_child(settings_throw_volume_value)

	var test_throw_sound_button := Button.new()
	test_throw_sound_button.text = "测试"
	test_throw_sound_button.custom_minimum_size = Vector2(74.0, 38.0)
	test_throw_sound_button.tooltip_text = "按当前音量播放 runner_throw.ogg"
	_style_button(test_throw_sound_button, Color(0.35, 0.76, 1.0), Color(0.05, 0.3, 0.55))
	test_throw_sound_button.pressed.connect(Callable(self, "_on_test_throw_sound_pressed"))
	throw_volume_row.add_child(test_throw_sound_button)

	_update_audio_settings_ui()

	var settings_hint := Label.new()
	settings_hint.text = "音量修改会立即生效，并在下次打开游戏时自动恢复。"
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
	_update_audio_settings_ui()
	_update_camera_mode_ui()
	if title_status != null:
		title_status.text = "调整游戏设置。"

func _close_settings_page() -> void:
	_set_settings_page_visible(false)
	_set_setup_visible(true)
	_set_menu_visible(true)
	_update_map_ui()
	_update_win_mode_ui()
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
	call_deferred("_apply_hud_layout_scale")
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
		rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "房主已切换视角为：%s，等待房主开始游戏。" % _camera_mode_display_name())
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
	_update_win_mode_ui()
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
		_configure_network_peer_timeout(remote_peer_id, true)
		rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "地图已切换为：%s，等待房主开始游戏。" % map_name)
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

func _switch_win_mode(_direction: int) -> void:
	if game_mode == "lobby" and not multiplayer.is_server():
		_update_win_mode_ui()
		return
	_refresh_win_target_from_ui()
	win_mode = WIN_MODE_HITS if win_mode == WIN_MODE_SURVIVAL else WIN_MODE_SURVIVAL
	win_time_seconds = _time_for_mode(win_mode)
	_update_win_mode_ui()
	_sync_lobby_settings("房间规则已同步，等待房主开始游戏。")
	_update_lobby_ui()

func _on_win_target_changed(value: float) -> void:
	if game_mode == "lobby" and not multiplayer.is_server():
		_update_win_mode_ui()
		return
	hits_to_win = clampi(int(round(value)), MIN_HITS_TO_WIN, MAX_HITS_TO_WIN)
	_sync_lobby_settings("房间规则已同步，等待房主开始游戏。")
	_update_lobby_ui()

func _on_win_time_changed(value: float) -> void:
	if game_mode == "lobby" and not multiplayer.is_server():
		_update_win_mode_ui()
		return
	win_time_seconds = clampf(value, MIN_WIN_TIME_SECONDS, MAX_WIN_TIME_SECONDS)
	_set_time_for_mode(win_mode, win_time_seconds)
	_sync_lobby_settings("房间规则已同步，等待房主开始游戏。")
	_update_lobby_ui()

func _time_for_mode(mode: String) -> float:
	return survival_time_seconds if mode == WIN_MODE_SURVIVAL else hits_time_seconds

func _set_time_for_mode(mode: String, value: float) -> void:
	var clamped_value := clampf(value, MIN_WIN_TIME_SECONDS, MAX_WIN_TIME_SECONDS)
	if mode == WIN_MODE_SURVIVAL:
		survival_time_seconds = clamped_value
	else:
		hits_time_seconds = clamped_value

func _refresh_win_target_from_ui() -> void:
	if win_target_spinbox != null:
		hits_to_win = clampi(int(round(win_target_spinbox.value)), MIN_HITS_TO_WIN, MAX_HITS_TO_WIN)
	if win_time_spinbox != null:
		win_time_seconds = clampf(win_time_spinbox.value, MIN_WIN_TIME_SECONDS, MAX_WIN_TIME_SECONDS)
	_set_time_for_mode(win_mode, win_time_seconds)

func _update_win_mode_ui() -> void:
	var is_survival := win_mode == WIN_MODE_SURVIVAL
	var can_edit := game_mode != "lobby" or multiplayer.is_server()
	win_time_seconds = _time_for_mode(win_mode)
	if win_mode_label != null:
		win_mode_label.text = "限时躲藏" if is_survival else "命中获胜"
	if win_mode_previous_button != null:
		win_mode_previous_button.disabled = not can_edit
	if win_mode_next_button != null:
		win_mode_next_button.disabled = not can_edit
	if win_target_row != null:
		win_target_row.visible = not is_survival
	if win_target_label != null:
		win_target_label.text = "目标命中"
		win_target_label.visible = not is_survival
	if win_target_unit_label != null:
		win_target_unit_label.text = "次"
		win_target_unit_label.visible = not is_survival
	if win_target_spinbox != null:
		win_target_spinbox.set_block_signals(true)
		win_target_spinbox.min_value = MIN_HITS_TO_WIN
		win_target_spinbox.max_value = MAX_HITS_TO_WIN
		win_target_spinbox.step = 1.0
		win_target_spinbox.value = hits_to_win
		win_target_spinbox.set_block_signals(false)
		win_target_spinbox.editable = can_edit
		win_target_spinbox.visible = not is_survival
	if win_time_spinbox != null:
		win_time_spinbox.set_value_no_signal(win_time_seconds)
		win_time_spinbox.editable = can_edit

func _win_rule_display_text() -> String:
	if win_mode == WIN_MODE_SURVIVAL:
		return "躲藏者坚持 %d 秒不被抓到" % int(round(win_time_seconds))
	return "躲藏者击中追逐者 %d 次，或坚持 %d 秒可获胜" % [hits_to_win, int(round(win_time_seconds))]

func _sync_lobby_settings(message: String) -> void:
	if game_mode == "lobby" and multiplayer.is_server() and remote_peer_id != 0:
		rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, message)

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
		rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "皮肤已更新，等待房主开始游戏。")
	_update_lobby_ui()

func _on_tagger_skin_selected(index: int) -> void:
	if index < 0 or index >= available_skin_ids.size():
		return
	tagger_skin_id = available_skin_ids[index]
	_update_skin_previews()
	if game_mode == "lobby" and multiplayer.is_server() and remote_peer_id != 0:
		rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "皮肤已更新，等待房主开始游戏。")
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
	_stop_chase_music()
	_reset_network_round_loading()
	_close_network()
	_clear_characters()
	_clear_all_throwables()
	game_mode = "title"
	basketball_finish_mode = false
	basketball_finish_playing = false
	_start_menu_music()
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
	_update_win_mode_ui()
	if title_status != null:
		title_status.text = message
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _start_normal_single_game() -> void:
	basketball_finish_mode = false
	_start_single_game()

func _start_basketball_single_game() -> void:
	basketball_finish_mode = true
	_start_single_game()
	if center_label != null:
		center_label.text = "篮球终结模式"
		var mode_token := round_transition_token
		get_tree().create_timer(1.5).timeout.connect(func():
			if mode_token == round_transition_token and not caught and center_label != null and center_label.text == "篮球终结模式":
				center_label.text = ""
		)

func _start_single_game() -> void:
	round_transition_token += 1
	_refresh_win_target_from_ui()
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
	_hide_map_loading_screen()
	_start_chase_music()
	_apply_camera_mode_to_local_actor()
	call_deferred("_apply_camera_mode_to_local_actor")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _start_single_chase_game() -> void:
	ai_vs_ai_spectate = false
	_begin_single_chase_round()

func _start_ai_vs_ai_game() -> void:
	# Watch the self-play trained tagger and runner AIs battle each other.
	ai_vs_ai_spectate = true
	_begin_single_chase_round()

func _begin_single_chase_round() -> void:
	_refresh_win_target_from_ui()
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
	_hide_map_loading_screen()
	_start_chase_music()
	_apply_camera_mode_to_local_actor()
	call_deferred("_apply_camera_mode_to_local_actor")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if not ai_vs_ai_spectate else Input.MOUSE_MODE_VISIBLE)

func _start_host_game() -> void:
	_refresh_win_target_from_ui()
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

func _on_ip_input_submitted(_submitted_text: String) -> void:
	_start_client_game()

func _start_client_game() -> void:
	var ip := ip_input.text.strip_edges()
	if ip == BASKETBALL_SECRET_CODE:
		_start_basketball_single_game()
		return
	basketball_finish_mode = false
	is_leaving_room = false
	_close_network()
	_clear_characters()
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

func _configure_network_peer_timeout(peer_id: int, loading: bool = false) -> void:
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null or peer_id <= 0:
		return
	var timeout_min := NETWORK_LOADING_TIMEOUT_MIN_MS if loading else NETWORK_ACTIVE_TIMEOUT_MIN_MS
	var timeout_max := NETWORK_LOADING_TIMEOUT_MAX_MS if loading else NETWORK_ACTIVE_TIMEOUT_MAX_MS
	enet_peer.set_peer_timeout(peer_id, 64, timeout_min, timeout_max)

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server() or network_started:
		return
	remote_peer_id = peer_id
	_configure_network_peer_timeout(peer_id)
	network_started = true
	_enter_lobby("玩家已加入。双方可在房间内切换角色，房主点击开始游戏。")
	rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "已加入房间。双方可在房间内切换角色，等待房主开始游戏。")

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and remote_peer_id != 0 and peer_id != remote_peer_id:
		return
	_handle_network_disconnect("对方连接已中断，已返回标题界面。")

func _on_connected_to_server() -> void:
	_configure_network_peer_timeout(1)
	game_mode = "lobby"
	_enter_lobby("已连接房主，等待房主同步房间信息...")

func _on_connection_failed() -> void:
	_handle_network_disconnect("连接失败，请检查 IP、防火墙或房主是否已创建房间。")

func _on_server_disconnected() -> void:
	_handle_network_disconnect("与房主的连接已中断，已返回标题界面。")

func _handle_network_disconnect(message: String) -> void:
	if is_leaving_room or (not _is_in_network_room() and not network_round_loading):
		return
	# 先屏蔽 close() 触发的后续断线信号，避免提示被重复覆盖。
	is_leaving_room = true
	_show_title(message)

func _enter_lobby(message: String) -> void:
	_stop_chase_music()
	round_transition_token += 1
	_reset_network_round_loading()
	game_mode = "lobby"
	_clear_characters()
	_clear_all_throwables()
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
	if game_mode != "lobby" or lobby_role_label == null:
		return
	var local_role := _local_lobby_role_text()
	var other_role := "追逐者" if local_role == "躲藏者" else "躲藏者"
	lobby_role_label.text = "你的角色：%s\n对方角色：%s\n通关条件：%s\n地图：%s\n视角：%s（房主选择）\n按 Q 退出房间" % [local_role, other_role, _win_rule_display_text(), map_name, _camera_mode_display_name()]
	_update_win_mode_ui()
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
	rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "上一局结算完成，已自动交换追/被追。等待房主开始下一局。")

func _return_active_round_to_lobby(message: String) -> void:
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	caught = false
	ai_catch_cooldown = 0.0
	catch_cooldown_remaining = 0.0
	time_alive = 0.0
	tagger_hit_count = 0
	_enter_lobby(message)
	rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, message)

@rpc("any_peer", "reliable")
func _rpc_request_return_to_lobby() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	if game_mode != "host" and not network_round_loading:
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
			rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "角色已切换，等待房主开始游戏。")
	else:
		rpc_id(1, "_rpc_request_role_switch")

func _start_lobby_game() -> void:
	_refresh_win_target_from_ui()
	if not multiplayer.is_server() or remote_peer_id == 0:
		return
	_start_synced_network_round()

@rpc("any_peer", "reliable")
func _rpc_request_role_switch() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	if game_mode != "lobby" or network_round_loading:
		return
	host_is_runner = not host_is_runner
	_update_lobby_ui()
	rpc("_rpc_sync_lobby", host_is_runner, win_mode, hits_to_win, win_time_seconds, selected_map_index, runner_skin_id, tagger_skin_id, selected_camera_mode, "角色已切换，等待房主开始游戏。")

@rpc("call_remote", "reliable")
func _rpc_sync_lobby(new_host_is_runner: bool, new_win_mode: String, new_hits_to_win: int, new_win_time_seconds: float, new_map_index: int, new_runner_skin_id: String, new_tagger_skin_id: String, new_camera_mode: String, message: String) -> void:
	host_is_runner = new_host_is_runner
	win_mode = WIN_MODE_SURVIVAL if new_win_mode == WIN_MODE_SURVIVAL else WIN_MODE_HITS
	hits_to_win = clampi(new_hits_to_win, MIN_HITS_TO_WIN, MAX_HITS_TO_WIN)
	win_time_seconds = clampf(new_win_time_seconds, MIN_WIN_TIME_SECONDS, MAX_WIN_TIME_SECONDS)
	_set_time_for_mode(win_mode, win_time_seconds)
	runner_skin_id = new_runner_skin_id
	tagger_skin_id = new_tagger_skin_id
	selected_camera_mode = "first_person" if new_camera_mode == "first_person" else "third_person"
	if new_map_index != selected_map_index:
		_select_official_map(new_map_index, false)
	_update_win_mode_ui()
	network_started = true
	_enter_lobby(message)
	_configure_network_peer_timeout(1)
	rpc_id(1, "_rpc_network_lobby_ready", network_round_load_token)

@rpc("any_peer", "reliable")
func _rpc_network_lobby_ready(_load_token: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	_configure_network_peer_timeout(remote_peer_id)

func _start_synced_network_round() -> void:
	if not multiplayer.is_server() or remote_peer_id == 0 or network_round_loading:
		return
	_refresh_win_target_from_ui()
	network_round_load_token += 1
	var load_token := network_round_load_token
	network_round_loading = true
	local_round_load_ready = false
	remote_round_load_ready = false
	_configure_network_peer_timeout(remote_peer_id, true)
	var payload := _build_network_start_payload()
	payload["load_token"] = load_token
	_show_network_waiting_screen("正在通知另一名玩家准备加载场景...")
	rpc_id(remote_peer_id, "_rpc_prepare_network_round", payload)
	_monitor_network_round_loading(load_token)
	# 先让开始加载的 RPC 发出，再执行会阻塞主线程的同步地图构建。
	await get_tree().process_frame
	if not network_round_loading or load_token != network_round_load_token or remote_peer_id == 0:
		return
	if not _start_network_round(remote_peer_id):
		_abort_network_round_to_lobby(load_token, "房主地图加载失败，已返回房间等待页面。")
		return
	local_round_load_ready = true
	_set_network_round_actors_enabled(false)
	call_deferred("_show_network_waiting_screen", "本机场景已加载完成\n正在等待其他玩家加载场景...")
	_try_activate_loaded_network_round(load_token)

func _monitor_network_round_loading(load_token: int) -> void:
	await get_tree().create_timer(NETWORK_ROUND_READY_TIMEOUT_SECONDS).timeout
	if not multiplayer.is_server() or not network_round_loading or load_token != network_round_load_token:
		return
	_abort_network_round_to_lobby(load_token, "等待另一名玩家加载超时，已返回房间等待页面。")

func _build_network_start_payload() -> Dictionary:
	return {
		"client_id": remote_peer_id,
		"host_is_runner": host_is_runner,
		"win_mode": win_mode,
		"hits_to_win": hits_to_win,
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
			if child is String and _is_map_asset_key(key_text):
				_append_sync_file(base_dir, String(child), files, seen)
			_collect_map_refs_recursive(child, base_dir, files, seen)
	elif value is Array:
		for child in value:
			_collect_map_refs_recursive(child, base_dir, files, seen)

func _is_map_asset_key(key: String) -> bool:
	return key in ["path", "texture", "albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "emission_texture", "detail_texture"]

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
func _rpc_prepare_network_round(payload: Dictionary) -> void:
	var load_token := int(payload.get("load_token", network_round_load_token + 1))
	network_round_load_token = load_token
	network_round_loading = true
	local_round_load_ready = false
	remote_round_load_ready = false
	_configure_network_peer_timeout(1, true)
	_show_network_waiting_screen("已收到开局信息\n正在准备加载场景...")
	# 先绘制等待页，再写入同步资源并构建大地图。
	await get_tree().process_frame
	if not network_round_loading or load_token != network_round_load_token:
		return
	_apply_network_start_payload(payload)
	if not _start_network_round(remote_peer_id):
		_show_network_waiting_screen("本机地图加载失败\n正在通知房主返回房间...")
		rpc_id(1, "_rpc_network_round_load_failed", load_token, "另一名玩家地图加载失败，已返回房间等待页面。")
		return
	local_round_load_ready = true
	_set_network_round_actors_enabled(false)
	call_deferred("_show_network_waiting_screen", "本机场景已加载完成\n正在等待房主完成场景加载...")
	rpc_id(1, "_rpc_network_round_loaded", load_token)

@rpc("any_peer", "reliable")
func _rpc_network_round_loaded(load_token: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	if not network_round_loading or load_token != network_round_load_token:
		return
	remote_round_load_ready = true
	_try_activate_loaded_network_round(load_token)

@rpc("any_peer", "reliable")
func _rpc_network_round_load_failed(load_token: int, message: String) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	_abort_network_round_to_lobby(load_token, message)

func _abort_network_round_to_lobby(load_token: int, message: String) -> void:
	if not multiplayer.is_server() or not network_round_loading or load_token != network_round_load_token:
		return
	if remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_abort_network_round", load_token, message)
	_enter_lobby(message)

@rpc("call_remote", "reliable")
func _rpc_abort_network_round(load_token: int, message: String) -> void:
	if not network_round_loading or load_token != network_round_load_token:
		return
	_enter_lobby(message)
	_configure_network_peer_timeout(1)
	rpc_id(1, "_rpc_network_lobby_ready", load_token)

func _try_activate_loaded_network_round(load_token: int) -> void:
	if not multiplayer.is_server() or not network_round_loading:
		return
	if load_token != network_round_load_token or not local_round_load_ready or not remote_round_load_ready:
		return
	rpc_id(remote_peer_id, "_rpc_activate_loaded_network_round", load_token)
	_activate_loaded_network_round(load_token)

@rpc("call_remote", "reliable")
func _rpc_activate_loaded_network_round(load_token: int) -> void:
	_activate_loaded_network_round(load_token)

func _activate_loaded_network_round(load_token: int) -> void:
	if not network_round_loading or load_token != network_round_load_token:
		return
	network_round_loading = false
	local_round_load_ready = false
	remote_round_load_ready = false
	time_alive = 0.0
	catch_cooldown_remaining = 0.0
	_set_network_round_actors_enabled(true)
	if map_loading_layer != null:
		map_loading_layer.visible = false
	_start_chase_music()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var peer_id := remote_peer_id if multiplayer.is_server() else 1
	_configure_network_peer_timeout(peer_id)
	if multiplayer.is_server() and remote_peer_id != 0:
		call_deferred("_sync_ground_items_to_peer", remote_peer_id)

func _apply_network_start_payload(payload: Dictionary) -> void:
	remote_peer_id = int(payload.get("client_id", remote_peer_id))
	host_is_runner = bool(payload.get("host_is_runner", host_is_runner))
	win_mode = WIN_MODE_SURVIVAL if String(payload.get("win_mode", win_mode)) == WIN_MODE_SURVIVAL else WIN_MODE_HITS
	hits_to_win = clampi(int(payload.get("hits_to_win", hits_to_win)), MIN_HITS_TO_WIN, MAX_HITS_TO_WIN)
	win_time_seconds = clampf(float(payload.get("win_time_seconds", win_time_seconds)), MIN_WIN_TIME_SECONDS, MAX_WIN_TIME_SECONDS)
	_set_time_for_mode(win_mode, win_time_seconds)
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
	_update_win_mode_ui()
	network_started = true

func _apply_network_map_payload(payload: Dictionary) -> void:
	var max_map_index := maxi(OFFICIAL_MAPS.size() - 1, 0)
	selected_map_index = clampi(int(payload.get("index", selected_map_index)), 0, max_map_index)
	map_preview_index = selected_map_index
	map_name = String(payload.get("name", map_name))
	var host_path := String(payload.get("path", ""))
	var map_text := String(payload.get("text", ""))
	var sync_root := NETWORK_SYNC_MAP_PATH.get_base_dir()
	_clear_sync_directory(sync_root)
	var raw_files = payload.get("files", [])
	if raw_files is Array:
		_write_sync_files(sync_root, raw_files as Array)
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

func _clear_sync_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := path.path_join(entry)
			if dir.current_is_dir():
				_clear_sync_directory(child_path)
				DirAccess.remove_absolute(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		entry = dir.get_next()
	dir.list_dir_end()

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

func _start_network_round(client_id: int) -> bool:
	round_transition_token += 1
	_clear_characters()
	if not _load_active_map(true):
		if title_status != null:
			title_status.text = "地图加载失败，无法开始联机游戏。"
		return false
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
	return true

func _set_network_round_actors_enabled(enabled: bool) -> void:
	var process_mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if player != null and is_instance_valid(player):
		player.process_mode = process_mode
	if tagger != null and is_instance_valid(tagger):
		tagger.process_mode = process_mode

func _spawn_single_characters() -> void:
	player = CharacterBody3D.new()
	player.name = "Runner"
	player.set_script(PlayerScript)
	player.skin_id = runner_skin_id
	add_child(player)
	_place_character_at_spawn(player, runner_spawn_position)

	tagger = CharacterBody3D.new()
	tagger.name = "Tagger"
	tagger.set_script(RLPolicyTaggerScript if USE_RL_POLICY_TAGGER else TaggerScript)
	tagger.skin_id = tagger_skin_id
	add_child(tagger)
	_place_character_at_spawn(tagger, tagger_spawn_position)
	tagger.target = player

func _spawn_single_chase_characters() -> void:
	player = CharacterBody3D.new()
	player.name = "AIRunner"
	player.set_script(RLPolicyRunnerScript if USE_RL_POLICY_RUNNER else RunnerAIScript)
	player.skin_id = runner_skin_id
	add_child(player)
	_place_character_at_spawn(player, runner_spawn_position)

	tagger = CharacterBody3D.new()
	if ai_vs_ai_spectate:
		# Both sides are self-play trained AI battling each other; the local
		# player only spectates.
		tagger.name = "AITagger"
		tagger.set_script(RLPolicyTaggerScript if USE_RL_POLICY_TAGGER else TaggerScript)
		tagger.skin_id = tagger_skin_id
		add_child(tagger)
		_place_character_at_spawn(tagger, tagger_spawn_position)
		tagger.target = player
		_create_spectator_camera()
	else:
		tagger.name = "PlayerTagger"
		tagger.set_script(NetworkActorScript)
		tagger.configure("tagger", 1, tagger_skin_id)
		add_child(tagger)
		_place_character_at_spawn(tagger, tagger_spawn_position)
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
	_place_character_at_spawn(player, runner_spawn_position)

	tagger = CharacterBody3D.new()
	tagger.name = "NetworkTagger"
	tagger.set_script(NetworkActorScript)
	tagger.configure("tagger", tagger_peer_id, tagger_skin_id)
	add_child(tagger)
	_place_character_at_spawn(tagger, tagger_spawn_position)

func _place_character_at_spawn(character: CharacterBody3D, configured_position: Vector3) -> void:
	var grounded_position := _grounded_spawn_position(configured_position)
	character.global_position = grounded_position
	character.velocity = Vector3.ZERO
	# add_child() 会先触发角色的 _ready()，当时角色仍在 (0,0,0)。
	# 将初始落点同步为复活点，掉出世界后即可按初始生成机制回到同一安全位置。
	if "spawn_position" in character:
		character.spawn_position = grounded_position
	if "last_position" in character:
		character.last_position = grounded_position
	if "remote_position" in character:
		character.remote_position = grounded_position
	if "remote_velocity" in character:
		character.remote_velocity = Vector3.ZERO

func _create_spectator_camera() -> void:
	if spectator_camera != null and is_instance_valid(spectator_camera):
		spectator_camera.queue_free()
	spectator_camera = Camera3D.new()
	spectator_camera.name = "SpectatorCamera"
	add_child(spectator_camera)
	spectator_camera.current = true
	_update_spectator_camera(0.0, true)

func _update_spectator_camera(delta: float, snap: bool = false) -> void:
	if spectator_camera == null or not is_instance_valid(spectator_camera):
		return
	if player == null or not is_instance_valid(player) or tagger == null or not is_instance_valid(tagger):
		return
	# Frame both fighters: sit behind their midpoint and look at it, backing off
	# as the gap between tagger and runner grows.
	var a: Vector3 = player.global_position
	var b: Vector3 = tagger.global_position
	var mid: Vector3 = (a + b) * 0.5
	var gap: float = a.distance_to(b)
	var back_dir: Vector3 = (b - a)
	back_dir.y = 0.0
	if back_dir.length_squared() < 0.01:
		back_dir = Vector3.FORWARD
	back_dir = back_dir.normalized()
	var side: Vector3 = back_dir.cross(Vector3.UP).normalized()
	var distance: float = clampf(gap * 0.9 + 8.0, 10.0, 34.0)
	var desired: Vector3 = mid + side * distance * 0.4 + Vector3.UP * (distance * 0.55 + 4.0) - back_dir * distance * 0.5
	if snap:
		spectator_camera.global_position = desired
	else:
		spectator_camera.global_position = spectator_camera.global_position.lerp(desired, clampf(delta * 4.0, 0.0, 1.0))
	spectator_camera.look_at(mid + Vector3.UP * 1.0, Vector3.UP)

func _clear_characters() -> void:
	_clear_vision_outline()
	basketball_finish_playing = false
	if basketball_sequence != null and is_instance_valid(basketball_sequence):
		basketball_sequence.queue_free()
	basketball_sequence = null
	if player != null and is_instance_valid(player):
		player.queue_free()
	if tagger != null and is_instance_valid(tagger):
		tagger.queue_free()
	if spectator_camera != null and is_instance_valid(spectator_camera):
		spectator_camera.queue_free()
	spectator_camera = null
	player = null
	tagger = null

func _reset_network_round_loading() -> void:
	network_round_loading = false
	local_round_load_ready = false
	remote_round_load_ready = false
	_set_network_round_actors_enabled(true)
	if map_loading_layer != null:
		map_loading_layer.visible = false

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
	# 直接在出生点就地贴地：只从出生点上方很小的高度向下探测地面，取正下方第一处地面。
	# 不再从高空坠落（避免落到建筑/高台的屋顶上），同时纠正略微陷入地下的出生点。
	var from := base_position + Vector3.UP * 2.0
	var to := base_position + Vector3.DOWN * 30.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return base_position
	var point := hit.get("position", base_position) as Vector3
	return point + Vector3.UP * 0.08

func _tagger_catch_disabled_by_slow() -> bool:
	return tagger != null and is_instance_valid(tagger) and tagger.has_method("is_catch_disabled_by_slow") and tagger.is_catch_disabled_by_slow()

func _request_local_catch_attempt() -> void:
	if tagger == null or not is_instance_valid(tagger) or catch_cooldown_remaining > 0.0 or _tagger_catch_disabled_by_slow():
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
	if not multiplayer.is_server() or sender_id != _tagger_peer_id() or caught or catch_cooldown_remaining > 0.0 or _tagger_catch_disabled_by_slow():
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
	if ai_catch_cooldown > 0.0 or flat_distance > CATCH_RANGE + 0.5 or _tagger_catch_disabled_by_slow():
		return
	# 篮球终结模式必须在进入平 A 范围时稳定出手，不能被 RL 策略中稀疏的技能动作门控。
	if not basketball_finish_mode and tagger.has_method("should_consume_ai_catch_attempt") and not tagger.should_consume_ai_catch_attempt():
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

func _on_runner_survived(reason: String = "") -> void:
	caught = true
	_stop_chase_music()
	_update_catch_crosshair()
	_clear_tagger_slow_particles()
	player.is_control_locked = true
	tagger.is_active = false
	var result_detail := reason if not reason.is_empty() else "已击中追逐者 %d 次" % tagger_hit_count
	if ai_vs_ai_spectate:
		center_label.text = "躲藏 AI 获胜！\n%s\n本局耗时 %.2f 秒\n按 R 再看一局" % [result_detail, time_alive]
	elif game_mode == "single":
		center_label.text = "躲藏者胜利！\n%s\n用时 %.2f 秒\n按 R 重新开始" % [result_detail, time_alive]
	elif game_mode == "single_chase":
		center_label.text = "AI 躲藏者胜利！\n%s\n用时 %.2f 秒\n按 R 重新挑战" % [result_detail, time_alive]
	else:
		center_label.text = "本局结束\n躲藏者胜利！\n%s\n用时 %.2f 秒\n%.0f 秒后返回房间并自动换边" % [result_detail, time_alive, MULTIPLAYER_RESULT_DELAY]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_survived", time_alive, tagger_hit_count, result_detail)
		_schedule_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_survived(final_time: float, final_hit_count: int, result_detail: String) -> void:
	caught = true
	_stop_chase_music()
	_update_catch_crosshair()
	_clear_tagger_slow_particles()
	time_alive = final_time
	tagger_hit_count = final_hit_count
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "本局结束\n躲藏者胜利！\n%s\n用时 %.2f 秒\n等待房主返回房间并自动换边" % [result_detail, final_time]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_player_caught() -> void:
	if basketball_finish_mode and game_mode == "single":
		_play_basketball_catch_finish()
		return
	_finish_runner_failed("躲藏者被抓到了！")

func _play_basketball_catch_finish() -> void:
	if basketball_finish_playing or caught or player == null or tagger == null or not is_instance_valid(player) or not is_instance_valid(tagger):
		return
	basketball_finish_playing = true
	caught = true
	_stop_chase_music()
	_clear_tagger_slow_particles()
	_update_catch_crosshair()
	player.is_control_locked = true
	tagger.is_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if center_label != null:
		center_label.text = "终结技：空中灌篮！"

	if player.has_method("set_camera_mode"):
		player.set_camera_mode("third_person")
	var sequence = BasketballKillSequenceScript.new()
	basketball_sequence = sequence
	add_child(sequence)
	sequence.play(player, tagger)
	await sequence.finished
	basketball_finish_playing = false
	if game_mode == "single" and player != null and tagger != null and is_instance_valid(player) and is_instance_valid(tagger):
		_finish_runner_failed("躲藏者被追逐者投进了篮筐！")

func _on_runner_fell() -> void:
	_finish_runner_failed("躲藏者掉出地图！")

func _on_runner_time_limit_survived() -> void:
	_on_runner_survived("坚持 %d 秒没有被追逐者抓到" % int(round(win_time_seconds)))

func _finish_runner_failed(reason: String) -> void:
	caught = true
	_stop_chase_music()
	_clear_tagger_slow_particles()
	player.is_control_locked = true
	tagger.is_active = false
	var progress_detail := "坚持了 %.2f / %.0f 秒" % [time_alive, win_time_seconds] if win_mode == WIN_MODE_SURVIVAL else "命中进度 %d / %d" % [tagger_hit_count, hits_to_win]
	if ai_vs_ai_spectate:
		center_label.text = "%s\n追逐 AI 获胜！\n%s\n按 R 再看一局" % [reason, progress_detail]
	elif game_mode == "single":
		center_label.text = "%s\n追逐者胜利\n%s\n按 R 重新开始" % [reason, progress_detail]
	elif game_mode == "single_chase":
		center_label.text = "%s\n追逐方获胜！\n%s\n按 R 重新挑战" % [reason, progress_detail]
	else:
		center_label.text = "本局结束\n%s\n追逐者胜利\n%s\n%.0f 秒后返回房间并自动换边" % [reason, progress_detail, MULTIPLAYER_RESULT_DELAY]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_mode == "host":
		rpc("_rpc_runner_failed", time_alive, tagger_hit_count, reason, progress_detail)
		_schedule_return_to_lobby_after_round()

@rpc("call_remote", "reliable")
func _rpc_runner_failed(final_time: float, final_hit_count: int, reason: String, progress_detail: String) -> void:
	caught = true
	_stop_chase_music()
	_update_catch_crosshair()
	time_alive = final_time
	tagger_hit_count = final_hit_count
	if player != null and is_instance_valid(player):
		player.is_control_locked = true
	if tagger != null and is_instance_valid(tagger):
		tagger.is_active = false
	center_label.text = "本局结束\n%s\n追逐者胜利\n%s\n等待房主返回房间并自动换边" % [reason, progress_detail]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _setup_world() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = _build_default_environment()
	add_child(world_environment)

	sun_light = DirectionalLight3D.new()
	sun_light.name = "Sun"
	sun_light.light_energy = 2.1
	sun_light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	add_child(sun_light)
	_ensure_throwable_root()
	_ensure_throwable_trajectory()

func _build_default_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = DEFAULT_SKY_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.9, 0.78)
	env.ambient_light_energy = 1.15
	return env

func _apply_map_environment(raw_environment) -> void:
	if world_environment == null or not is_instance_valid(world_environment):
		return
	if not (raw_environment is Dictionary):
		world_environment.environment = _build_default_environment()
		_apply_default_sun()
		return
	var data := raw_environment as Dictionary
	if data.is_empty():
		world_environment.environment = _build_default_environment()
		_apply_default_sun()
		return
	var env := _build_default_environment()
	var sky_type := String(data.get("sky_type", "")).to_lower()
	var background := String(data.get("background", "color")).to_lower()
	if sky_type == "nether_dynamic":
		env.background_mode = Environment.BG_SKY
		env.sky = _build_nether_sky(data)
		# 仅当地图显式声明 sky_ambient=true 时才用天空作为环境光来源；
		# 否则保持地图原有的 ambient_color/energy 颜色源，加天空云不改变画面亮度。
		if _to_bool(data.get("sky_ambient", false), false):
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		# 让雾也染天空地平线，使远处岩浆与天空之间平滑渐变而非硬切
		if "fog_sky_affect" in env:
			env.set("fog_sky_affect", float(data.get("fog_sky_affect", 1.0)))
		if "fog_aerial_perspective" in env:
			env.set("fog_aerial_perspective", float(data.get("fog_aerial_perspective", 0.0)))
	elif background == "sky":
		env.background_mode = Environment.BG_SKY
	else:
		env.background_mode = Environment.BG_COLOR
	env.background_color = _to_color(data.get("sky_color", data.get("background_color", env.background_color)), env.background_color)
	env.ambient_light_color = _to_color(data.get("ambient_color", env.ambient_light_color), env.ambient_light_color)
	env.ambient_light_energy = float(data.get("ambient_energy", env.ambient_light_energy))
	env.fog_enabled = _to_bool(data.get("fog_enabled", false), false)
	env.fog_light_color = _to_color(data.get("fog_color", env.background_color), env.background_color)
	env.fog_density = float(data.get("fog_density", 0.01))
	env.glow_enabled = _to_bool(data.get("glow", false), false)
	env.ssr_enabled = _to_bool(data.get("ssr", false), false)
	env.ssao_enabled = _to_bool(data.get("ssao", false), false)
	env.tonemap_exposure = float(data.get("exposure", 1.0))
	match String(data.get("tonemap", "linear")).to_lower():
		"filmic":
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		"aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
		"reinhard", "reinhardt":
			env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
		_:
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = env
	_apply_map_sun(data.get("sun", {}))

func _build_nether_sky(data: Dictionary) -> Sky:
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = NETHER_SKY_SHADER
	mat.set_shader_parameter("top_color", _to_color(data.get("sky_top_color", Color(0.16, 0.03, 0.02)), Color(0.16, 0.03, 0.02)))
	mat.set_shader_parameter("horizon_color", _to_color(data.get("sky_horizon_color", Color(0.95, 0.32, 0.08)), Color(0.95, 0.32, 0.08)))
	if data.has("cloud_color"):
		mat.set_shader_parameter("cloud_color", _to_color(data.get("cloud_color"), Color(0.55, 0.12, 0.03)))
	mat.set_shader_parameter("cloud_scale", float(data.get("sky_cloud_scale", 3.0)))
	mat.set_shader_parameter("cloud_speed", float(data.get("sky_cloud_speed", 0.04)))
	mat.set_shader_parameter("horizon_glow", float(data.get("sky_horizon_glow", 1.6)))
	mat.set_shader_parameter("horizon_softness", float(data.get("sky_horizon_softness", 3.0)))
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	return sky

func _apply_default_sun() -> void:
	if sun_light == null or not is_instance_valid(sun_light):
		return
	sun_light.light_color = Color.WHITE
	sun_light.light_energy = 2.1
	sun_light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun_light.shadow_enabled = false
	sun_light.visible = true

func _apply_map_sun(raw_sun) -> void:
	if sun_light == null or not is_instance_valid(sun_light):
		return
	if not (raw_sun is Dictionary):
		_apply_default_sun()
		return
	var data := raw_sun as Dictionary
	sun_light.visible = _to_bool(data.get("visible", true), true)
	sun_light.light_color = _to_color(data.get("color", Color.WHITE), Color.WHITE)
	sun_light.light_energy = float(data.get("energy", 2.1))
	sun_light.rotation_degrees = _to_vector3(data.get("rotation_degrees", Vector3(-48.0, 35.0, 0.0)), Vector3(-48.0, 35.0, 0.0))
	sun_light.shadow_enabled = _to_bool(data.get("shadow", true), true)

func _to_vector3(value, default_value: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if typeof(value) == TYPE_DICTIONARY:
		return Vector3(float(value.get("x", default_value.x)), float(value.get("y", default_value.y)), float(value.get("z", default_value.z)))
	return default_value

func _to_color(value, default_value: Color) -> Color:
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

func _to_bool(value, default_value: bool) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	if typeof(value) == TYPE_STRING:
		var text := String(value).to_lower()
		if text == "true" or text == "yes" or text == "1":
			return true
		if text == "false" or text == "no" or text == "0":
			return false
	return default_value

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

func _show_map_loading_screen() -> void:
	_stop_chase_music()
	if map_loading_layer == null:
		return
	var display_name := map_name
	for map_data in OFFICIAL_MAPS:
		if String(map_data.get("path", "")) == selected_map_path:
			display_name = String(map_data.get("name", map_name))
			break
	if map_loading_title != null:
		map_loading_title.text = "加载中"
	map_loading_label.text = "正在加载：%s\n正在生成场景、贴图与光照..." % display_name
	map_loading_layer.visible = true
	# 地图加载是同步任务；强制先提交一帧，避免大地图加载时窗口看起来卡死。
	RenderingServer.force_draw()

func _show_network_waiting_screen(message: String) -> void:
	_stop_chase_music()
	if not network_round_loading or map_loading_layer == null:
		return
	if map_loading_title != null:
		map_loading_title.text = "等待其他玩家"
	if map_loading_label != null:
		map_loading_label.text = message
	map_loading_layer.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	RenderingServer.force_draw()

func _hide_map_loading_screen() -> void:
	if map_loading_layer != null and not network_round_loading:
		map_loading_layer.visible = false

func _load_active_map(strict: bool = false) -> bool:
	_show_map_loading_screen()
	var loaded := _load_map_from_path(selected_map_path)
	if not loaded and not strict:
		for map_path in _map_search_paths():
			if map_path == selected_map_path:
				continue
			if _load_map_from_path(map_path):
				loaded = true
				break
	if not loaded and not strict:
		_clear_map()
		map_root = Node3D.new()
		map_root.name = "LegacyBuiltinMap"
		add_child(map_root)
		_build_arena()
		map_name = "内置备用地图"
		active_map_path = "legacy_builtin"
		_apply_map_environment({})
		_apply_map_bgm({})
		_update_map_ui()
		if debug_mode:
			_refresh_debug_collision_shapes()
		loaded = true
	call_deferred("_hide_map_loading_screen")
	return loaded

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
	# 新地图加载后清空楼层缓存，下一次生成道具时会重新扫描发现所有楼层。
	discovered_throwable_levels.clear()
	discovered_level_samples.clear()
	throwable_level_cursor = 0
	var gameplay: Dictionary = result.get("gameplay", {})
	minimap_world_radius = maxf(1.0, float(gameplay.get("world_radius", DEFAULT_MINIMAP_WORLD_RADIUS)))
	_apply_map_environment(result.get("environment", {}))
	_apply_map_bgm(result.get("bgm", {}))
	_apply_lava_flow_shaders(result.get("materials", {}))
	_update_map_ui()
	if debug_mode:
		_refresh_debug_collision_shapes()
	return true

# 将岩浆海网格替换为流动岩浆着色器；亮度沿用原材质的自发光设置保持不变
func _apply_lava_flow_shaders(materials) -> void:
	if map_root == null or not is_instance_valid(map_root):
		return
	var mats: Dictionary = materials if materials is Dictionary else {}
	# 需要应用流动效果的岩浆海对象 -> 其材质 id
	var targets := {
		"VoidLavaSeaBright": "void_lava_bright",
		"VoidLavaSeaDeep": "void_lava_deep",
	}
	for body_name in targets.keys():
		var body := map_root.find_child(String(body_name), true, false)
		if body == null:
			continue
		var mesh := _first_mesh_instance(body)
		if mesh == null:
			continue
		var mat_id := String(targets[body_name])
		var md: Dictionary = mats.get(mat_id, {}) if mats.has(mat_id) else {}
		var base_col := _to_color(md.get("color", Color(0.95, 0.36, 0.08)), Color(0.95, 0.36, 0.08))
		var emit_col := _to_color(md.get("emission", base_col), base_col)
		var emit_energy := float(md.get("emission_energy", 4.2))
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = LAVA_FLOW_SHADER
		shader_mat.set_shader_parameter("base_color", base_col)
		shader_mat.set_shader_parameter("emission_color", emit_col)
		shader_mat.set_shader_parameter("emission_energy", emit_energy)
		# 深层岩浆流动更慢、纹理更大
		if body_name == "VoidLavaSeaDeep":
			shader_mat.set_shader_parameter("flow_speed", 0.035)
			shader_mat.set_shader_parameter("pattern_scale", 0.08)
		else:
			shader_mat.set_shader_parameter("flow_speed", 0.06)
			shader_mat.set_shader_parameter("pattern_scale", 0.12)
		mesh.material_override = shader_mat

func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null

func _clear_map() -> void:
	minimap_world_radius = DEFAULT_MINIMAP_WORLD_RADIUS
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

	round_time_label = Label.new()
	round_time_label.anchor_left = 0.5
	round_time_label.anchor_right = 0.5
	round_time_label.offset_left = -190.0
	round_time_label.offset_top = 10.0
	round_time_label.offset_right = 190.0
	round_time_label.offset_bottom = 96.0
	round_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	round_time_label.add_theme_font_size_override("font_size", 32)
	round_time_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	round_time_label.add_theme_color_override("font_outline_color", Color(0.025, 0.04, 0.1, 0.96))
	round_time_label.add_theme_constant_override("outline_size", 7)
	round_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_time_label.text = "剩余时间  05:00"
	hud_layer.add_child(round_time_label)

	hud_status_panel = PanelContainer.new()
	hud_status_panel.position = Vector2(14.0, 14.0)
	hud_status_panel.custom_minimum_size = Vector2(300.0, 82.0)
	hud_status_panel.add_theme_stylebox_override("panel", _cartoon_style(Color(1.0, 0.95, 0.72, 0.88), Color(0.12, 0.18, 0.36), 4, 18, Vector2(0.0, 5.0), 12))
	hud_status_panel.visible = true
	hud_layer.add_child(hud_status_panel)

	hud_status_margin = MarginContainer.new()
	hud_status_margin.add_theme_constant_override("margin_left", 14)
	hud_status_margin.add_theme_constant_override("margin_right", 14)
	hud_status_margin.add_theme_constant_override("margin_top", 10)
	hud_status_margin.add_theme_constant_override("margin_bottom", 10)
	hud_status_panel.add_child(hud_status_margin)

	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_color", Color(0.11, 0.16, 0.31))
	hud_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.72))
	hud_label.add_theme_constant_override("outline_size", 2)
	hud_label.text = ""
	hud_status_margin.add_child(hud_label)

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

	_build_runner_inventory_ui()
	_build_tagger_inventory_ui()

	# 追逐者平 A 冷却显示（右下角大号透明图案）
	catch_cd_label = CatchAttackIconScript.new()
	catch_cd_label.anchor_left = 1.0
	catch_cd_label.anchor_top = 1.0
	catch_cd_label.anchor_right = 1.0
	catch_cd_label.anchor_bottom = 1.0
	catch_cd_label.offset_left = -166.0
	catch_cd_label.offset_top = -166.0
	catch_cd_label.offset_right = -22.0
	catch_cd_label.offset_bottom = -22.0
	catch_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	catch_cd_label.z_index = 10
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
	_apply_hud_layout_scale()
	hud_layer.visible = false

func _hud_layout_scale() -> float:
	# “伸展以适应显示”会保留 1280×720 的逻辑视口，不能只读取 visible_rect。
	# 同时使用真实窗口尺寸，使嵌入式伸展、普通全屏和独占全屏都能得到正确比例。
	var viewport_height := get_viewport().get_visible_rect().size.y
	var window_height := DisplayServer.window_get_size().y
	var effective_height := maxf(viewport_height, window_height)
	if effective_height <= 0.0:
		return 1.0
	return clampf((effective_height / HUD_REFERENCE_HEIGHT) * HUD_FULLSCREEN_SCALE_BONUS, 1.0, HUD_FULLSCREEN_MAX_SCALE)

func _apply_hud_layout_scale() -> void:
	var scale := _hud_layout_scale()
	if hud_status_panel != null:
		hud_status_panel.position = Vector2(14.0, 14.0) * scale
		hud_status_panel.custom_minimum_size = Vector2(300.0, 82.0) * scale
		hud_status_panel.add_theme_stylebox_override("panel", _cartoon_style(Color(1.0, 0.95, 0.72, 0.88), Color(0.12, 0.18, 0.36), roundi(4.0 * scale), roundi(18.0 * scale), Vector2(0.0, 5.0 * scale), roundi(12.0 * scale)))
	if hud_status_margin != null:
		hud_status_margin.add_theme_constant_override("margin_left", roundi(14.0 * scale))
		hud_status_margin.add_theme_constant_override("margin_right", roundi(14.0 * scale))
		hud_status_margin.add_theme_constant_override("margin_top", roundi(10.0 * scale))
		hud_status_margin.add_theme_constant_override("margin_bottom", roundi(10.0 * scale))
	if hud_label != null:
		hud_label.add_theme_font_size_override("font_size", roundi(18.0 * scale))
		hud_label.add_theme_constant_override("outline_size", roundi(2.0 * scale))
	if round_time_label != null:
		round_time_label.offset_left = -190.0 * scale
		round_time_label.offset_top = 10.0 * scale
		round_time_label.offset_right = 190.0 * scale
		round_time_label.offset_bottom = 58.0 * scale
		round_time_label.add_theme_font_size_override("font_size", roundi(32.0 * scale))
		round_time_label.add_theme_constant_override("outline_size", roundi(7.0 * scale))
	if catch_cd_label != null:
		catch_cd_label.offset_left = -166.0 * scale
		catch_cd_label.offset_top = -166.0 * scale
		catch_cd_label.offset_right = -22.0 * scale
		catch_cd_label.offset_bottom = -22.0 * scale
	if runner_inventory_bar != null:
		runner_inventory_bar.offset_left = 18.0 * scale
		runner_inventory_bar.offset_top = -128.0 * scale
		runner_inventory_bar.offset_right = 406.0 * scale
		runner_inventory_bar.offset_bottom = -18.0 * scale
		runner_inventory_bar.add_theme_constant_override("separation", roundi(12.0 * scale))
	if slow_grenade_slot != null:
		slow_grenade_slot.custom_minimum_size = Vector2(184.0, 110.0) * scale
	if speed_boost_slot != null:
		speed_boost_slot.custom_minimum_size = Vector2(184.0, 110.0) * scale
	if slow_grenade_slot_label != null:
		slow_grenade_slot_label.add_theme_font_size_override("font_size", roundi(17.0 * scale))
	if speed_boost_slot_label != null:
		speed_boost_slot_label.add_theme_font_size_override("font_size", roundi(17.0 * scale))
	if tagger_inventory_bar != null:
		tagger_inventory_bar.offset_left = 18.0 * scale
		tagger_inventory_bar.offset_top = -128.0 * scale
		tagger_inventory_bar.offset_right = 202.0 * scale
		tagger_inventory_bar.offset_bottom = -18.0 * scale
	if vision_card_slot != null:
		vision_card_slot.custom_minimum_size = Vector2(184.0, 110.0) * scale
	if vision_card_slot_label != null:
		vision_card_slot_label.add_theme_font_size_override("font_size", roundi(17.0 * scale))

	if minimap_panel == null:
		return
	minimap_panel.offset_left = -190.0 * scale
	minimap_panel.offset_top = 18.0 * scale
	minimap_panel.offset_right = -18.0 * scale
	minimap_panel.offset_bottom = 190.0 * scale
	minimap_panel.add_theme_stylebox_override("panel", _cartoon_style(Color(0.02, 0.05, 0.08, 0.58), Color(0.28, 0.78, 1.0, 0.82), roundi(3.0 * scale), roundi(18.0 * scale), Vector2.ZERO, roundi(8.0 * scale)))
	if minimap_content != null:
		minimap_content.custom_minimum_size = Vector2(156.0, 156.0) * scale
	var player_dot_size := Vector2(9.0, 9.0) * scale
	if minimap_player_dot != null:
		minimap_player_dot.size = player_dot_size
	if minimap_opponent_dot != null:
		minimap_opponent_dot.size = player_dot_size
	for dot in minimap_reward_dots:
		if dot != null and is_instance_valid(dot):
			dot.size = Vector2(7.0, 7.0) * scale

func _build_runner_inventory_ui() -> void:
	runner_inventory_bar = HBoxContainer.new()
	runner_inventory_bar.anchor_left = 0.0
	runner_inventory_bar.anchor_top = 1.0
	runner_inventory_bar.anchor_right = 0.0
	runner_inventory_bar.anchor_bottom = 1.0
	runner_inventory_bar.offset_left = 18.0
	runner_inventory_bar.offset_top = -128.0
	runner_inventory_bar.offset_right = 406.0
	runner_inventory_bar.offset_bottom = -18.0
	runner_inventory_bar.add_theme_constant_override("separation", 12)
	runner_inventory_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(runner_inventory_bar)

	slow_grenade_slot = PanelContainer.new()
	slow_grenade_slot.custom_minimum_size = Vector2(184.0, 110.0)
	runner_inventory_bar.add_child(slow_grenade_slot)
	slow_grenade_slot_label = Label.new()
	slow_grenade_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slow_grenade_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slow_grenade_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slow_grenade_slot_label.add_theme_font_size_override("font_size", 17)
	slow_grenade_slot_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.1, 0.9))
	slow_grenade_slot_label.add_theme_constant_override("outline_size", 3)
	slow_grenade_slot.add_child(slow_grenade_slot_label)

	speed_boost_slot = PanelContainer.new()
	speed_boost_slot.custom_minimum_size = Vector2(184.0, 110.0)
	runner_inventory_bar.add_child(speed_boost_slot)
	speed_boost_slot_label = Label.new()
	speed_boost_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_boost_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_boost_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speed_boost_slot_label.add_theme_font_size_override("font_size", 17)
	speed_boost_slot_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.1, 0.9))
	speed_boost_slot_label.add_theme_constant_override("outline_size", 3)
	speed_boost_slot.add_child(speed_boost_slot_label)

	_update_runner_inventory_hud()

func _update_runner_inventory_hud() -> void:
	if runner_inventory_bar == null:
		return
	var show_inventory := hud_layer != null and hud_layer.visible and _throwable_system_active() and not caught and _local_is_runner()
	runner_inventory_bar.visible = show_inventory
	if not show_inventory:
		return
	_update_inventory_slot(slow_grenade_slot, slow_grenade_slot_label, "减速弹", "左键投掷", runner_has_slow_grenade, Color(0.18, 0.72, 1.0))
	_update_inventory_slot(speed_boost_slot, speed_boost_slot_label, "加速剂", "E 使用", runner_has_speed_boost, Color(0.24, 1.0, 0.42))

func _build_tagger_inventory_ui() -> void:
	tagger_inventory_bar = HBoxContainer.new()
	tagger_inventory_bar.anchor_left = 0.0
	tagger_inventory_bar.anchor_top = 1.0
	tagger_inventory_bar.anchor_right = 0.0
	tagger_inventory_bar.anchor_bottom = 1.0
	tagger_inventory_bar.offset_left = 18.0
	tagger_inventory_bar.offset_top = -128.0
	tagger_inventory_bar.offset_right = 202.0
	tagger_inventory_bar.offset_bottom = -18.0
	tagger_inventory_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(tagger_inventory_bar)

	vision_card_slot = PanelContainer.new()
	vision_card_slot.custom_minimum_size = Vector2(184.0, 110.0)
	tagger_inventory_bar.add_child(vision_card_slot)
	vision_card_slot_label = Label.new()
	vision_card_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vision_card_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vision_card_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vision_card_slot_label.add_theme_font_size_override("font_size", 17)
	vision_card_slot_label.add_theme_color_override("font_outline_color", Color(0.06, 0.01, 0.12, 0.92))
	vision_card_slot_label.add_theme_constant_override("outline_size", 3)
	vision_card_slot.add_child(vision_card_slot_label)
	_update_tagger_inventory_hud()

func _update_tagger_inventory_hud() -> void:
	if tagger_inventory_bar == null:
		return
	var show_inventory := hud_layer != null and hud_layer.visible and _throwable_system_active() and not caught and _local_is_tagger()
	tagger_inventory_bar.visible = show_inventory
	if not show_inventory:
		return
	var vision_active := tagger_vision_timer > 0.0
	var normal_purple := Color(0.78, 0.24, 1.0)
	var active_only_purple := Color(0.72, 0.58, 0.82)
	var accent := normal_purple if tagger_has_vision_card else active_only_purple if vision_active else normal_purple
	_update_inventory_slot(vision_card_slot, vision_card_slot_label, "透视卡", "E 使用", tagger_has_vision_card or vision_active, accent)
	if vision_active:
		var reserve_text := "\n已携带备用卡" if tagger_has_vision_card else "\n目标位置已显现"
		vision_card_slot_label.text = "透视卡\n透视中 %.1fs%s" % [tagger_vision_timer, reserve_text]

func _update_inventory_slot(slot: PanelContainer, label: Label, item_name: String, action_hint: String, is_held: bool, accent: Color) -> void:
	if slot == null or label == null:
		return
	var fill := Color(accent, 0.26) if is_held else Color(0.03, 0.06, 0.12, 0.76)
	var border := accent if is_held else Color(0.38, 0.45, 0.56, 0.84)
	slot.add_theme_stylebox_override("panel", _cartoon_style(fill, border, 3, 14, Vector2(0.0, 3.0), 8))
	label.add_theme_color_override("font_color", Color(0.92, 1.0, 0.96) if is_held else Color(0.72, 0.78, 0.86))
	label.text = "%s\n%s\n%s" % [item_name, "已携带" if is_held else "空槽", action_hint if is_held else "F 拾取"]

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
	var visible_items: Array[Dictionary] = []
	for data in ground_throwables.values():
		if _local_can_see_item_type(String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE))):
			visible_items.append(data)
	while minimap_reward_dots.size() < visible_items.size():
		var dot := ColorRect.new()
		dot.size = Vector2(7.0, 7.0) * _hud_layout_scale()
		minimap_reward_dots.append(dot)
		minimap_content.add_child(dot)
	for item_index in range(visible_items.size()):
		var data := visible_items[item_index]
		var dot := minimap_reward_dots[item_index]
		var item_type := String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE))
		dot.color = Color(0.84, 0.3, 1.0, 0.95) if _is_tagger_item_type(item_type) else Color(1.0, 0.86, 0.18, 0.95)
		dot.position = _world_to_minimap(data.get("position", Vector3.ZERO)) - dot.size * 0.5
		dot.visible = true
	for i in range(visible_items.size(), minimap_reward_dots.size()):
		minimap_reward_dots[i].visible = false

func _update_minimap_opponent(delta: float) -> void:
	if minimap_opponent_dot == null:
		return
	var local_actor := _local_controlled_actor()
	var opponent := _opponent_actor_for_local_player()
	var vision_reveals_target := _local_is_tagger() and tagger_vision_timer > 0.0
	if vision_reveals_target and opponent != null and is_instance_valid(opponent):
		last_seen_opponent_position = opponent.global_position
		minimap_opponent_dot.visible = true
		minimap_opponent_dot.color = Color(0.96, 0.2, 1.0, 1.0)
		minimap_opponent_dot.position = _world_to_minimap(last_seen_opponent_position) - minimap_opponent_dot.size * 0.5
		minimap_opponent_dot.move_to_front()
		return
	if local_actor != null and opponent != null and _can_see_opponent(local_actor, opponent):
		opponent_seen_timer = OPPONENT_MINIMAP_MEMORY
		last_seen_opponent_position = opponent.global_position
	else:
		opponent_seen_timer = maxf(opponent_seen_timer - delta, 0.0)
	minimap_opponent_dot.visible = opponent_seen_timer > 0.0
	if minimap_opponent_dot.visible:
		minimap_opponent_dot.color = Color(1.0, 0.28, 0.2, 0.95)
		minimap_opponent_dot.position = _world_to_minimap(last_seen_opponent_position) - minimap_opponent_dot.size * 0.5
		minimap_opponent_dot.move_to_front()

func _world_to_minimap(world_position: Vector3) -> Vector2:
	var center := runner_spawn_position.lerp(tagger_spawn_position, 0.5)
	var rel := Vector2(world_position.x - center.x, world_position.z - center.z) / minimap_world_radius
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
	if _tagger_catch_disabled_by_slow():
		catch_cd_label.set_cooldown_state(0.0, Color(0.45, 0.75, 1.0, 0.48), "减速中无法平 A", true)
	elif catch_cooldown_remaining > 0.0:
		var recovery := clampf(1.0 - catch_cooldown_remaining / CATCH_COOLDOWN, 0.0, 1.0)
		catch_cd_label.set_cooldown_state(recovery, Color(1.0, 0.58, 0.25, 0.78), "平 A 冷却 %.1fs" % catch_cooldown_remaining)
	else:
		catch_cd_label.set_cooldown_state(1.0, Color(0.5, 1.0, 0.58, 0.9), "平 A 就绪")

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
	_bind_key("use_speed_boost", KEY_E)
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
	runner_has_slow_grenade = false
	runner_has_speed_boost = false
	tagger_has_vision_card = false
	tagger_vision_timer = 0.0
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
	runner_has_slow_grenade = false
	runner_has_speed_boost = false
	tagger_has_vision_card = false
	tagger_vision_timer = 0.0
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
	_clear_vision_outline()
	_update_runner_inventory_hud()
	_update_tagger_inventory_hud()

func _runner_inventory_full() -> bool:
	return runner_has_slow_grenade and runner_has_speed_boost

func _is_runner_item_type(item_type: String) -> bool:
	return item_type == ITEM_TYPE_SLOW_GRENADE or item_type == ITEM_TYPE_SPEED_BOOST

func _is_tagger_item_type(item_type: String) -> bool:
	return item_type == ITEM_TYPE_VISION_CARD

func _local_can_see_item_type(_item_type: String) -> bool:
	# 对局中的双方都能看见全部地面道具；角色归属只影响外观和拾取权限。
	return _local_is_runner() or _local_is_tagger()

func _item_belongs_to_local_role(item_type: String) -> bool:
	if _local_is_runner():
		return _is_runner_item_type(item_type)
	if _local_is_tagger():
		return _is_tagger_item_type(item_type)
	return false

func _runner_can_pickup_item_type(item_type: String) -> bool:
	if item_type == ITEM_TYPE_SPEED_BOOST:
		return not runner_has_speed_boost
	if item_type == ITEM_TYPE_SLOW_GRENADE:
		return not runner_has_slow_grenade
	return false

func _tagger_can_pickup_item_type(item_type: String) -> bool:
	return item_type == ITEM_TYPE_VISION_CARD and not tagger_has_vision_card

func _update_throwables(delta: float) -> void:
	if not _throwable_system_active() or caught:
		_clear_vision_outline()
		return
	tagger_vision_timer = maxf(tagger_vision_timer - delta, 0.0)
	_update_vision_outline()
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
		player.set_throwable_context(_ground_pickup_positions_for_runner(), runner_has_slow_grenade, runner_has_speed_boost, tagger_hit_count, hits_to_win)
	if player.has_method("set_rl_match_context"):
		player.set_rl_match_context(maxf(win_time_seconds - time_alive, 0.0), win_time_seconds)
	if not _runner_inventory_full():
		var pickup_id := _find_pickup_candidate_for_actor(player, THROWABLE_AI_PICKUP_RANGE)
		if pickup_id >= 0:
			_pickup_throwable_on_authority(pickup_id)

	var origin: Vector3 = _runner_throw_origin(player)
	var to_tagger: Vector3 = tagger.global_position + Vector3.UP * 0.8 - origin
	var flat_distance: float = Vector2(to_tagger.x, to_tagger.z).length()
	if runner_has_speed_boost and player.has_method("should_use_ai_speed_boost") \
	and player.should_use_ai_speed_boost(flat_distance, tagger_hit_count, hits_to_win):
		_use_speed_boost_on_authority()

	if not runner_has_slow_grenade or ai_runner_throw_cooldown > 0.0:
		return
	if player.has_method("should_consume_ai_throw_attempt") and not player.should_consume_ai_throw_attempt():
		return
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

func _ground_pickup_positions_for_runner() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for data in ground_throwables.values():
		if _runner_can_pickup_item_type(String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE))):
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

func _ground_item_count(item_type: String) -> int:
	var count := 0
	for data in ground_throwables.values():
		if String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE)) == item_type:
			count += 1
	return count

func _ground_runner_item_count() -> int:
	return _ground_item_count(ITEM_TYPE_SLOW_GRENADE) + _ground_item_count(ITEM_TYPE_SPEED_BOOST)

func _ground_items_filled() -> bool:
	return _ground_runner_item_count() >= THROWABLE_RESPAWN_TARGET and _ground_item_count(ITEM_TYPE_VISION_CARD) >= TAGGER_CARD_RESPAWN_TARGET

func _maybe_fill_throwable_spawns(force_fill: bool) -> void:
	if not _throwable_system_active():
		return
	if not force_fill and _ground_items_filled():
		throwable_respawn_timer = THROWABLE_RESPAWN_INTERVAL
		return
	_ensure_throwable_root()
	var fill_attempts := 0
	var total_target := THROWABLE_RESPAWN_TARGET + TAGGER_CARD_RESPAWN_TARGET
	while not _ground_items_filled() and fill_attempts < total_target * 6:
		fill_attempts += 1
		var spawn_position: Variant = _find_throwable_spawn_position()
		if spawn_position == null:
			break
		var spawned_id := _spawn_ground_throwable(spawn_position as Vector3, -1, _choose_ground_item_type())
		if spawned_id < 0:
			break
	throwable_respawn_timer = THROWABLE_RESPAWN_INTERVAL

func _choose_ground_item_type() -> String:
	var grenade_count := _ground_item_count(ITEM_TYPE_SLOW_GRENADE)
	var boost_count := _ground_item_count(ITEM_TYPE_SPEED_BOOST)
	var card_count := _ground_item_count(ITEM_TYPE_VISION_CARD)
	var runner_count := grenade_count + boost_count
	var runner_slots_left := THROWABLE_RESPAWN_TARGET - runner_count
	var card_slots_left := TAGGER_CARD_RESPAWN_TARGET - card_count
	if card_slots_left > 0 and (runner_slots_left <= 0 or randf() < 0.35):
		return ITEM_TYPE_VISION_CARD
	# 逃脱方保持至少一枚减速弹和一瓶加速剂，剩余槽位按既有概率分配。
	if grenade_count == 0 and runner_slots_left <= 1:
		return ITEM_TYPE_SLOW_GRENADE
	if boost_count == 0 and runner_slots_left <= 1:
		return ITEM_TYPE_SPEED_BOOST
	return ITEM_TYPE_SPEED_BOOST if randf() < SPEED_BOOST_SPAWN_CHANCE else ITEM_TYPE_SLOW_GRENADE

func _find_throwable_spawn_position():
	if get_world_3d() == null:
		return null
	var space_state := get_world_3d().direct_space_state
	# 确保已发现整张地图的所有可站立楼层（结果会缓存，切图时清空）。
	_ensure_spawnable_levels(space_state)
	var active_heights := _throwable_active_heights()
	var center := runner_spawn_position.lerp(tagger_spawn_position, 0.5)
	var span := runner_spawn_position.distance_to(tagger_spawn_position)
	# 水平搜索半径显著放宽，让远离出生点连线的边角楼层也能被覆盖。
	var max_radius := clampf(span * 0.65, 14.0, THROWABLE_LEVEL_SCAN_RADIUS_MAX)
	var total_attempts: int = maxi(THROWABLE_SPAWN_ATTEMPTS, 96)
	for attempt in range(total_attempts):
		var probe: Vector3
		# 轮转到某一层，并优先在该层实际存在地面的采样点附近撒点，
		# 保证每一层（含边角）都能均衡地刷到道具。
		var level_probe: Variant = _pick_level_biased_probe(attempt)
		if level_probe != null:
			probe = level_probe as Vector3
		else:
			# 回退：以出生点为原点的随机撒点（兼容未发现楼层的极端情况）。
			var angle := randf() * TAU
			var falloff := 1.0 - float(attempt) / float(total_attempts)
			var radius := randf_range(4.0, lerpf(8.0, max_radius, falloff))
			var origin := center
			match attempt % 3:
				1:
					origin = runner_spawn_position
				2:
					origin = tagger_spawn_position
			probe = origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var surfaces := _throwable_surfaces_at_probe(probe, active_heights, space_state)
		surfaces.shuffle()
		for surface_position in surfaces:
			var position := surface_position + Vector3.UP * 0.28
			if position.distance_to(runner_spawn_position) < 4.0 or position.distance_to(tagger_spawn_position) < 4.0:
				continue
			var too_close := false
			for data in ground_throwables.values():
				var other: Vector3 = data.get("position", Vector3.ZERO)
				if other.distance_to(position) < THROWABLE_MIN_SPAWN_GAP:
					too_close = true
					break
			if not too_close:
				# 成功放置后推进楼层游标，让下一件道具轮到其它楼层，实现跨层均衡。
				if not discovered_level_samples.is_empty():
					throwable_level_cursor = (throwable_level_cursor + 1) % discovered_level_samples.size()
				return position
	return null

# 轮转到某个已发现楼层，并在该层的一个真实水平采样点附近抖动出一个探测点。
# 返回 null 表示尚无可用楼层采样（交由调用方回退到随机撒点）。
func _pick_level_biased_probe(attempt: int) -> Variant:
	if discovered_level_samples.is_empty():
		return null
	var level_count := discovered_level_samples.size()
	# 逐层轮转，保证生成次数在各楼层之间均衡分配。
	var level_index := (throwable_level_cursor + attempt) % level_count
	var samples: Array = discovered_level_samples[level_index]
	if samples.is_empty():
		return null
	var base: Vector3 = samples[randi() % samples.size()]
	# 在该采样点周围小范围抖动，覆盖同层邻近区域又不至于跑出这一层。
	var jitter_angle := randf() * TAU
	var jitter := randf_range(0.0, 3.0)
	return base + Vector3(cos(jitter_angle) * jitter, 0.0, sin(jitter_angle) * jitter)

func _throwable_active_heights() -> Array[float]:
	# 基础高度来自出生点，再叠加主动发现的所有楼层，最后并入玩家实时踩踏高度。
	var heights: Array[float] = [runner_spawn_position.y, tagger_spawn_position.y]
	for level_height in discovered_throwable_levels:
		var known := false
		for height in heights:
			if absf(height - level_height) < 0.25:
				known = true
				break
		if not known:
			heights.append(level_height)
	for raw_actor in [player, tagger]:
		var actor := raw_actor as CharacterBody3D
		if actor == null or not is_instance_valid(actor) or not actor.is_on_floor():
			continue
		var actor_height := actor.global_position.y
		var already_known := false
		for height in heights:
			if absf(height - actor_height) < 0.25:
				already_known = true
				break
		if not already_known:
			heights.append(actor_height)
	return heights

# 主动扫描整张地图，发现所有可站立楼层（不再让道具高度被出生点绑定）。
# 结果缓存在 discovered_throwable_levels / discovered_level_samples 中，切图时清空。
func _ensure_spawnable_levels(space_state: PhysicsDirectSpaceState3D) -> void:
	if not discovered_throwable_levels.is_empty():
		return
	_discover_spawnable_levels(space_state)

func _discover_spawnable_levels(space_state: PhysicsDirectSpaceState3D) -> void:
	discovered_throwable_levels.clear()
	discovered_level_samples.clear()
	throwable_level_cursor = 0
	if space_state == null:
		return
	var center := runner_spawn_position.lerp(tagger_spawn_position, 0.5)
	var span := runner_spawn_position.distance_to(tagger_spawn_position)
	var scan_radius := clampf(span * 0.75, THROWABLE_LEVEL_SCAN_RADIUS_MIN, THROWABLE_LEVEL_SCAN_RADIUS_MAX)
	var top_y := maxf(runner_spawn_position.y, tagger_spawn_position.y) + THROWABLE_LEVEL_SCAN_TOP
	var bottom_y := minf(runner_spawn_position.y, tagger_spawn_position.y) - THROWABLE_LEVEL_SCAN_BOTTOM
	# 聚类桶：key 为四舍五入后的层高，value 为 {"sum":高度累加, "count":样本数, "samples":水平点列表}
	var clusters: Array = []
	# 用黄金角螺旋在圆盘内均匀撒列，避免规则网格产生的对齐条纹。
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for column in range(THROWABLE_LEVEL_SCAN_COLUMNS):
		var t := (float(column) + 0.5) / float(THROWABLE_LEVEL_SCAN_COLUMNS)
		var r := scan_radius * sqrt(t)
		var a := golden_angle * float(column)
		var probe_xz := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var from := Vector3(probe_xz.x, top_y, probe_xz.z)
		var to := Vector3(probe_xz.x, bottom_y, probe_xz.z)
		var last_hit_y := INF
		for _layer in range(THROWABLE_LEVEL_SCAN_MAX_LAYERS):
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collision_mask = 1
			var hit := space_state.intersect_ray(query)
			if hit.is_empty():
				break
			var normal: Vector3 = hit.get("normal", Vector3.ZERO)
			var pos: Vector3 = hit.get("position", Vector3.ZERO)
			# 防御：命中高度没有明显下降说明卡在同一面，提前结束避免死循环。
			if pos.y >= last_hit_y - 0.01:
				break
			last_hit_y = pos.y
			# 仅收集足够水平、且上方有净空可放道具的朝上表面。
			if normal.y >= THROWABLE_MIN_SURFACE_NORMAL_Y and _has_throwable_spawn_clearance(pos, space_state):
				_accumulate_level_cluster(clusters, pos)
			# 从命中点略下方继续，以穿透到更低的楼层（同一碰撞体的多层地面也能命中）。
			from = Vector3(probe_xz.x, pos.y - 0.25, probe_xz.z)
	# 滤除样本过少的孤立薄板，按高度升序输出楼层。
	clusters.sort_custom(func(x, y): return float(x["sum"]) / float(x["count"]) < float(y["sum"]) / float(y["count"]))
	for cluster in clusters:
		var count: int = int(cluster["count"])
		if count < THROWABLE_LEVEL_MIN_SAMPLES:
			continue
		var level_height := float(cluster["sum"]) / float(count)
		discovered_throwable_levels.append(level_height)
		discovered_level_samples.append(cluster["samples"])
	# 若一层都没发现（多半是物理世界尚未就绪，或极简纯出生台地图），
	# 不写入任何缓存，保持为空——这样下一帧会重新扫描；期间道具仍可
	# 借助 _throwable_active_heights 中的出生点高度与撒点回退在出生层生成，行为不退化。

# 把一个命中点归入相近高度的聚类桶，或新建一个桶。
func _accumulate_level_cluster(clusters: Array, pos: Vector3) -> void:
	for cluster in clusters:
		var avg := float(cluster["sum"]) / float(cluster["count"])
		if absf(avg - pos.y) <= THROWABLE_LEVEL_CLUSTER_TOLERANCE:
			cluster["sum"] = float(cluster["sum"]) + pos.y
			cluster["count"] = int(cluster["count"]) + 1
			(cluster["samples"] as Array).append(pos)
			return
	clusters.append({"sum": pos.y, "count": 1, "samples": [pos]})

func _throwable_surfaces_at_probe(probe: Vector3, active_heights: Array[float], space_state: PhysicsDirectSpaceState3D) -> Array[Vector3]:
	var surfaces: Array[Vector3] = []
	# 先从各个角色活动高度内部向下探测，封顶室内地图不会被屋顶抢先命中。
	for active_height in active_heights:
		var local_from := Vector3(probe.x, active_height + THROWABLE_SPAWN_CLEARANCE_HEIGHT + 0.4, probe.z)
		var local_to := Vector3(probe.x, active_height - THROWABLE_ACTIVE_LEVEL_TOLERANCE, probe.z)
		var local_query := PhysicsRayQueryParameters3D.create(local_from, local_to)
		local_query.collision_mask = 1
		_append_throwable_surface(space_state.intersect_ray(local_query), active_heights, surfaces, space_state)

	# 再从地图上方逐层向下推进探测，收集平台、楼层等重叠上表面。
	# 用命中点下移的方式穿透楼层，可正确处理同一碰撞体包含多层地面的情况。
	var highest_active := active_heights[0]
	var lowest_active := active_heights[0]
	for active_height in active_heights:
		highest_active = maxf(highest_active, active_height)
		lowest_active = minf(lowest_active, active_height)
	var from := Vector3(probe.x, highest_active + 64.0, probe.z)
	var to := Vector3(probe.x, lowest_active - 128.0, probe.z)
	var last_hit_y := INF
	for _layer in range(THROWABLE_MAX_SURFACE_LAYERS):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
		# 命中高度未明显下降说明卡在同一面，提前结束避免死循环。
		if hit_pos.y >= last_hit_y - 0.01:
			break
		last_hit_y = hit_pos.y
		_append_throwable_surface(hit, active_heights, surfaces, space_state)
		from = Vector3(probe.x, hit_pos.y - 0.25, probe.z)
	return surfaces

func _append_throwable_surface(hit: Dictionary, active_heights: Array[float], surfaces: Array[Vector3], space_state: PhysicsDirectSpaceState3D) -> void:
	if hit.is_empty():
		return
	var surface_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if surface_normal.y < THROWABLE_MIN_SURFACE_NORMAL_Y:
		return
	var surface_position: Vector3 = hit.get("position", Vector3.ZERO)
	var active_distance := INF
	for active_height in active_heights:
		active_distance = minf(active_distance, absf(surface_position.y - active_height))
	if active_distance > THROWABLE_ACTIVE_LEVEL_TOLERANCE:
		return
	if not _has_throwable_spawn_clearance(surface_position, space_state):
		return
	for existing_position in surfaces:
		if existing_position.distance_squared_to(surface_position) < 0.01:
			return
	surfaces.append(surface_position)

func _has_throwable_spawn_clearance(surface_position: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	var clearance_shape := CylinderShape3D.new()
	clearance_shape.radius = THROWABLE_SPAWN_CLEARANCE_RADIUS
	clearance_shape.height = THROWABLE_SPAWN_CLEARANCE_HEIGHT
	var clearance_query := PhysicsShapeQueryParameters3D.new()
	clearance_query.shape = clearance_shape
	clearance_query.transform = Transform3D(
		Basis(),
		surface_position + Vector3.UP * (THROWABLE_SPAWN_CLEARANCE_HEIGHT * 0.5 + 0.05)
	)
	clearance_query.collision_mask = 1
	return space_state.intersect_shape(clearance_query, 1).is_empty()

func _spawn_ground_throwable(position: Vector3, item_id: int = -1, item_type: String = ITEM_TYPE_SLOW_GRENADE) -> int:
	_ensure_throwable_root()
	if throwable_root == null or not is_instance_valid(throwable_root):
		return -1
	var resolved_id: int = item_id if item_id > 0 else next_ground_throwable_id
	if item_id <= 0:
		next_ground_throwable_id += 1
	else:
		next_ground_throwable_id = max(next_ground_throwable_id, item_id + 1)
	if ground_throwables.has(resolved_id):
		var existing: Dictionary = ground_throwables[resolved_id]
		var existing_node := existing.get("node", null) as Node3D
		if existing_node != null and is_instance_valid(existing_node):
			existing_node.position = position
			existing_node.visible = _local_can_see_item_type(item_type)
			existing["position"] = position
			existing["item_type"] = item_type
			ground_throwables[resolved_id] = existing
			return resolved_id
	var resolved_type := item_type
	if not _is_runner_item_type(resolved_type) and not _is_tagger_item_type(resolved_type):
		resolved_type = ITEM_TYPE_SLOW_GRENADE
	var node := _create_ground_item_visual(resolved_type)
	node.name = "GroundItem_%s_%d" % [resolved_type, resolved_id]
	node.position = position
	node.visible = _local_can_see_item_type(resolved_type)
	if not _item_belongs_to_local_role(resolved_type):
		_apply_opponent_item_ghost(node)
	throwable_root.add_child(node)
	ground_throwables[resolved_id] = {"id": resolved_id, "node": node, "position": position, "item_type": resolved_type}
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_sync_ground_throwable_spawn", resolved_id, position, resolved_type)
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
	var nearest_id := _find_pickup_candidate_id()
	if nearest_id < 0:
		var message := "减速弹和加速剂槽位均已满" if _runner_inventory_full() else "附近没有可拾取的缺失道具"
		_show_throwable_notice(message, Color(1.0, 0.86, 0.22), false)
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
		var item_type := String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE))
		if not _runner_can_pickup_item_type(item_type):
			continue
		var position: Vector3 = data.get("position", Vector3.ZERO)
		var distance := actor_position.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best_id = int(item_id)
	return best_id

func _pickup_throwable_on_authority(item_id: int) -> void:
	if not ground_throwables.has(item_id):
		return
	var runner_actor = player
	if runner_actor == null or not is_instance_valid(runner_actor):
		return
	var data: Dictionary = ground_throwables[item_id]
	var position: Vector3 = data.get("position", Vector3.ZERO)
	if runner_actor.global_position.distance_to(position) > THROWABLE_PICKUP_RANGE + 0.25:
		return
	var item_type := String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE))
	if not _runner_can_pickup_item_type(item_type):
		return
	_remove_ground_throwable(item_id, true)
	if item_type == ITEM_TYPE_SPEED_BOOST:
		runner_has_speed_boost = true
		if _local_is_runner():
			_show_throwable_notice("已拾取加速剂！按 E 使用", Color(0.36, 1.0, 0.42), true)
	else:
		runner_has_slow_grenade = true
		_update_held_throwable_visual()
		if _local_is_runner():
			_show_throwable_notice("已拾取减速弹！单击左键投掷", Color(0.34, 1.0, 0.58), true)
	_sync_runner_inventory_state()

func _request_local_tagger_card_pickup() -> void:
	if not _local_is_tagger():
		return
	var nearest_id := _find_tagger_card_pickup_candidate(_get_local_actor(), THROWABLE_PICKUP_RANGE)
	if nearest_id < 0:
		var message := "已携带透视卡" if tagger_has_vision_card else "附近没有可拾取的透视卡"
		_show_throwable_notice(message, Color(0.9, 0.5, 1.0), false)
		return
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_pickup_tagger_card", nearest_id)
		return
	_pickup_tagger_card_on_authority(nearest_id)

func _find_tagger_card_pickup_candidate(actor: Node3D, pickup_range: float) -> int:
	if actor == null or not is_instance_valid(actor):
		return -1
	var best_id := -1
	var best_distance := pickup_range
	for item_id in ground_throwables.keys():
		var data: Dictionary = ground_throwables[item_id]
		if not _tagger_can_pickup_item_type(String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE))):
			continue
		var distance := actor.global_position.distance_to(data.get("position", Vector3.ZERO))
		if distance < best_distance:
			best_distance = distance
			best_id = int(item_id)
	return best_id

func _pickup_tagger_card_on_authority(item_id: int) -> void:
	if not ground_throwables.has(item_id) or tagger == null or not is_instance_valid(tagger):
		return
	var data: Dictionary = ground_throwables[item_id]
	var item_type := String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE))
	var position: Vector3 = data.get("position", Vector3.ZERO)
	if not _tagger_can_pickup_item_type(item_type) or tagger.global_position.distance_to(position) > THROWABLE_PICKUP_RANGE + 0.25:
		return
	_remove_ground_throwable(item_id, true)
	tagger_has_vision_card = true
	if _local_is_tagger():
		_show_throwable_notice("已拾取透视卡！按 E 使用", Color(0.9, 0.5, 1.0), true)
	_sync_tagger_card_state()

func _sync_tagger_card_state() -> void:
	_update_held_throwable_visual()
	_update_tagger_inventory_hud()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_set_tagger_card_state", tagger_has_vision_card)

func _request_local_vision_card_use() -> void:
	if not _local_is_tagger():
		return
	if not tagger_has_vision_card:
		_show_throwable_notice("没有透视卡，靠近后按 F 拾取", Color(1.0, 0.78, 0.22), false)
		return
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_use_vision_card")
		return
	_use_vision_card_on_authority()

func _use_vision_card_on_authority() -> void:
	if not tagger_has_vision_card:
		return
	tagger_has_vision_card = false
	tagger_vision_timer = TAGGER_VISION_CARD_DURATION
	_update_vision_outline()
	if _local_is_tagger():
		_show_throwable_notice("透视卡已激活：小地图与穿墙轮廓显示 %.0f 秒" % TAGGER_VISION_CARD_DURATION, Color(0.9, 0.5, 1.0), true)
	_sync_tagger_card_state()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_activate_vision_card", TAGGER_VISION_CARD_DURATION)

func _update_vision_outline() -> void:
	var should_show := _local_is_tagger() and tagger_vision_timer > 0.0 and player != null and is_instance_valid(player)
	if not should_show:
		_clear_vision_outline()
		return
	if not vision_outline_entries.is_empty():
		return
	if vision_outline_material == null:
		var outline_shader := Shader.new()
		outline_shader.code = "shader_type spatial;\nrender_mode unshaded, depth_test_disabled, cull_front;\nvoid vertex() { VERTEX += NORMAL * 0.065; }\nvoid fragment() { ALBEDO = vec3(0.95, 0.08, 1.0); EMISSION = vec3(1.3, 0.05, 1.8); }"
		vision_outline_material = ShaderMaterial.new()
		vision_outline_material.shader = outline_shader
		vision_outline_material.render_priority = 127
	var runner_meshes: Array[MeshInstance3D] = []
	_collect_vision_meshes(player, runner_meshes)
	for mesh in runner_meshes:
		vision_outline_entries.append({"mesh": mesh, "previous_overlay": mesh.material_overlay})
		mesh.material_overlay = vision_outline_material

func _collect_vision_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_vision_meshes(child, output)

func _clear_vision_outline() -> void:
	for entry in vision_outline_entries:
		var mesh := entry.get("mesh", null) as MeshInstance3D
		if mesh != null and is_instance_valid(mesh):
			mesh.material_overlay = entry.get("previous_overlay", null) as Material
	vision_outline_entries.clear()

func _sync_runner_inventory_state() -> void:
	_update_held_throwable_visual()
	_update_runner_inventory_hud()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_set_runner_inventory_state", runner_has_slow_grenade, runner_has_speed_boost)

func _sync_runner_inventory_to_peer(peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and peer_id > 0:
		rpc_id(peer_id, "_rpc_set_runner_inventory_state", runner_has_slow_grenade, runner_has_speed_boost)

func _sync_ground_items_to_peer(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or peer_id <= 0:
		return
	for item_id in ground_throwables.keys():
		var data: Dictionary = ground_throwables[item_id]
		rpc_id(peer_id, "_rpc_sync_ground_throwable_spawn", int(item_id), data.get("position", Vector3.ZERO), String(data.get("item_type", ITEM_TYPE_SLOW_GRENADE)))
	_sync_runner_inventory_to_peer(peer_id)
	rpc_id(peer_id, "_rpc_set_tagger_card_state", tagger_has_vision_card)
	if tagger_vision_timer > 0.0:
		rpc_id(peer_id, "_rpc_activate_vision_card", tagger_vision_timer)

func _request_local_speed_boost_use() -> void:
	if not _local_is_runner():
		return
	if not runner_has_speed_boost:
		_show_throwable_notice("没有加速剂，靠近后按 F 拾取", Color(1.0, 0.78, 0.22), false)
		return
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_use_speed_boost")
		return
	_use_speed_boost_on_authority()

func _use_speed_boost_on_authority() -> void:
	if not runner_has_speed_boost:
		return
	runner_has_speed_boost = false
	_apply_runner_speed_boost(SPEED_BOOST_MULTIPLIER, SPEED_BOOST_DURATION)
	_sync_runner_inventory_state()

func _apply_runner_speed_boost(multiplier: float, duration: float) -> void:
	if player != null and is_instance_valid(player) and player.has_method("apply_speed_multiplier"):
		player.apply_speed_multiplier(multiplier, duration)
	if _local_is_runner():
		_show_throwable_notice("使用加速剂：速度提升 %.0f%%，持续 %.1f 秒" % [(multiplier - 1.0) * 100.0, duration], Color(0.36, 1.0, 0.42), true)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and remote_peer_id != 0:
		rpc_id(remote_peer_id, "_rpc_apply_runner_speed_boost", multiplier, duration)

func _request_local_throwable_throw() -> void:
	if not _local_is_runner():
		return
	if not runner_has_slow_grenade:
		_show_throwable_notice("没有减速弹，先靠近道具按 F 拾取", Color(1.0, 0.78, 0.22), false)
		return
	var actor = _get_local_actor()
	if actor == null or not is_instance_valid(actor):
		return
	var origin: Vector3 = _runner_throw_origin(actor)
	var direction: Vector3 = actor.get_throw_direction() if actor.has_method("get_throw_direction") else -actor.global_transform.basis.z.normalized()
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		runner_has_slow_grenade = false
		_hide_held_throwable_visual()
		_hide_throwable_trajectory()
		_update_runner_inventory_hud()
		_show_throwable_notice("已投掷减速弹", Color(0.35, 0.92, 1.0), true)
		rpc_id(1, "_rpc_request_throw_throwable", origin, direction)
		return
	_throw_throwable_on_authority(origin, direction)

func _throw_throwable_on_authority(origin: Vector3, direction: Vector3) -> void:
	if not runner_has_slow_grenade:
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
	runner_has_slow_grenade = false
	_hide_held_throwable_visual()
	_hide_throwable_trajectory()
	if _local_is_runner():
		_show_throwable_notice("已投掷减速弹", Color(0.35, 0.92, 1.0), true)
	_sync_runner_inventory_state()
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
	# 服务端与远端都会经过本函数生成同一个投掷物，因此双方各自在本地播放一次。
	if runner_throw_sound != null and runner_throw_sound.stream != null:
		runner_throw_sound.stop()
		runner_throw_sound.play()
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
	if win_mode == WIN_MODE_HITS and tagger_hit_count >= hits_to_win:
		_on_runner_survived()

func _apply_tagger_slow_effect(multiplier: float, duration: float, impact_position: Vector3, current_hit_count: int = -1) -> void:
	if current_hit_count >= 0:
		tagger_hit_count = current_hit_count
	if tagger != null and is_instance_valid(tagger) and tagger.has_method("apply_speed_multiplier"):
		tagger.apply_speed_multiplier(multiplier, duration)
		_start_tagger_slow_particles(duration)
	_play_throwable_hit_effect(impact_position)
	if _local_is_runner():
		var runner_notice := "命中追逐者！%d / %d" % [tagger_hit_count, hits_to_win] if win_mode == WIN_MODE_HITS else "命中追逐者，已使其暂时减速"
		_show_throwable_notice(runner_notice, Color(0.34, 1.0, 0.58), true)
	elif _local_is_tagger():
		var tagger_notice := "被击中 %d / %d 次，暂时减速" % [tagger_hit_count, hits_to_win] if win_mode == WIN_MODE_HITS else "被击中，暂时减速"
		_show_throwable_notice(tagger_notice, Color(1.0, 0.46, 0.32), true)
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

func _create_ground_item_visual(item_type: String) -> Node3D:
	if item_type == ITEM_TYPE_SPEED_BOOST:
		return _create_speed_boost_visual()
	if item_type == ITEM_TYPE_VISION_CARD:
		return _create_vision_card_visual()
	return _create_throwable_visual(false)

func _create_vision_card_visual() -> Node3D:
	var root := Node3D.new()
	var model_resource := load(VISION_CARD_MODEL_PATH)
	if model_resource is PackedScene:
		var model := (model_resource as PackedScene).instantiate() as Node3D
		if model != null:
			model.name = "VisionCardModel"
			model.position.y = 0.38
			model.rotation.y = deg_to_rad(20.0)
			root.add_child(model)
	else:
		push_error("无法加载透视卡模型：%s" % VISION_CARD_MODEL_PATH)

	var energy_ring := MeshInstance3D.new()
	energy_ring.name = "VisionCardEnergyRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.255
	torus.rings = 20
	torus.ring_segments = 10
	energy_ring.mesh = torus
	energy_ring.position.y = -0.2
	var energy_material := StandardMaterial3D.new()
	energy_material.albedo_color = Color(0.76, 0.16, 1.0)
	energy_material.metallic = 0.25
	energy_material.roughness = 0.2
	energy_material.emission_enabled = true
	energy_material.emission = Color(0.68, 0.05, 1.0)
	energy_material.emission_energy_multiplier = 2.0
	energy_ring.material_override = energy_material
	energy_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(energy_ring)

	var pickup_marker := MeshInstance3D.new()
	pickup_marker.name = "VisionCardPickupMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.32
	marker_mesh.bottom_radius = 0.32
	marker_mesh.height = 0.018
	pickup_marker.mesh = marker_mesh
	pickup_marker.position.y = -0.2
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.48, 0.08, 0.75, 0.42)
	marker_material.emission_enabled = true
	marker_material.emission = Color(0.58, 0.05, 0.9)
	marker_material.emission_energy_multiplier = 0.9
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pickup_marker.material_override = marker_material
	pickup_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pickup_marker)
	return root

func _instantiate_model_with_raw_gltf_fallback(path: String) -> Node3D:
	var model_resource := load(path)
	if model_resource is PackedScene:
		return (model_resource as PackedScene).instantiate() as Node3D
	# Direct BAT launches may not have a populated .godot/imported cache yet.
	# Parse the source GLB at runtime so the real model still appears.
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	return document.generate_scene(state)

func _create_speed_boost_visual() -> Node3D:
	var root := Node3D.new()
	var model := _instantiate_model_with_raw_gltf_fallback(SPEED_BOOST_MODEL_PATH)
	if model != null:
		model.name = "SpeedBoostPotionModel"
		model.scale = Vector3.ONE * 0.34
		root.add_child(model)
		_style_speed_boost_model(model)
	else:
		push_error("无法加载加速剂模型：%s" % SPEED_BOOST_MODEL_PATH)

	var energy_ring := MeshInstance3D.new()
	energy_ring.name = "BoostEnergyRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.16
	torus.outer_radius = 0.21
	torus.rings = 18
	torus.ring_segments = 8
	energy_ring.mesh = torus
	energy_ring.position.y = -0.18
	var energy_material := StandardMaterial3D.new()
	energy_material.albedo_color = Color(0.18, 0.88, 0.22)
	energy_material.metallic = 0.25
	energy_material.roughness = 0.2
	energy_material.emission_enabled = true
	energy_material.emission = Color(0.08, 1.0, 0.18)
	energy_material.emission_energy_multiplier = 2.2
	energy_ring.material_override = energy_material
	energy_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(energy_ring)

	var pickup_marker := MeshInstance3D.new()
	pickup_marker.name = "BoostPickupMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.3
	marker_mesh.bottom_radius = 0.3
	marker_mesh.height = 0.018
	pickup_marker.mesh = marker_mesh
	pickup_marker.position.y = -0.2
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.08, 0.72, 0.15, 0.42)
	marker_material.emission_enabled = true
	marker_material.emission = Color(0.04, 0.8, 0.12)
	marker_material.emission_energy_multiplier = 0.9
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pickup_marker.material_override = marker_material
	pickup_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pickup_marker)
	return root

func _style_speed_boost_model(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var source_material := mesh_instance.mesh.surface_get_material(surface_index)
				if not (source_material is StandardMaterial3D):
					continue
				var boost_material := (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
				if source_material.resource_name == "Glass":
					boost_material.albedo_color = Color(0.08, 0.82, 0.16, 0.78)
					boost_material.metallic = 0.18
					boost_material.roughness = 0.16
					boost_material.emission_enabled = true
					boost_material.emission = Color(0.04, 0.9, 0.12)
					boost_material.emission_energy_multiplier = 1.6
				else:
					boost_material.albedo_color = Color(0.08, 0.12, 0.1)
					boost_material.metallic = 0.62
					boost_material.roughness = 0.3
				mesh_instance.set_surface_override_material(surface_index, boost_material)
	for child in node.get_children():
		_style_speed_boost_model(child)

func _create_throwable_visual(is_projectile: bool) -> Node3D:
	var root := Node3D.new()
	var model := _instantiate_model_with_raw_gltf_fallback(THROWABLE_MODEL_PATH)
	if model != null:
		model.name = "SlowGrenadeModel"
		model.scale = Vector3.ONE * 1.35
		# 手持和飞行状态沿投掷方向横置，地面拾取状态保持直立。
		if is_projectile:
			model.rotation.x = PI * 0.5
		root.add_child(model)
		_style_throwable_model(model)
	else:
		push_error("无法加载减速弹模型：%s" % THROWABLE_MODEL_PATH)

	# 保留一圈低调的蓝色能量环，让真实模型仍能明确表达减速道具功能。
	var energy_band := MeshInstance3D.new()
	energy_band.name = "SlowEnergyBand"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.13
	torus.outer_radius = 0.17
	torus.rings = 16
	torus.ring_segments = 8
	energy_band.mesh = torus
	if is_projectile:
		energy_band.rotation.x = PI * 0.5
	var energy_material := StandardMaterial3D.new()
	energy_material.albedo_color = Color(0.08, 0.58, 0.82)
	energy_material.metallic = 0.35
	energy_material.roughness = 0.22
	energy_material.emission_enabled = true
	energy_material.emission = Color(0.04, 0.72, 1.0)
	energy_material.emission_energy_multiplier = 2.1
	energy_band.material_override = energy_material
	energy_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(energy_band)

	if not is_projectile:
		var pickup_marker := MeshInstance3D.new()
		pickup_marker.name = "PickupMarker"
		var marker_mesh := CylinderMesh.new()
		marker_mesh.top_radius = 0.29
		marker_mesh.bottom_radius = 0.29
		marker_mesh.height = 0.018
		pickup_marker.mesh = marker_mesh
		pickup_marker.position.y = -0.2
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = Color(0.05, 0.42, 0.62, 0.42)
		marker_material.emission_enabled = true
		marker_material.emission = Color(0.02, 0.35, 0.56)
		marker_material.emission_energy_multiplier = 0.8
		marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pickup_marker.material_override = marker_material
		pickup_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pickup_marker)
	return root

func _style_throwable_model(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var source_material := mesh_instance.mesh.surface_get_material(surface_index)
				if not (source_material is StandardMaterial3D) or source_material.resource_name != "Main":
					continue
				var slow_material := (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
				slow_material.albedo_color = Color(0.035, 0.32, 0.55)
				slow_material.metallic = 0.62
				slow_material.roughness = 0.28
				slow_material.emission_enabled = true
				slow_material.emission = Color(0.02, 0.48, 0.8)
				slow_material.emission_energy_multiplier = 1.25
				mesh_instance.set_surface_override_material(surface_index, slow_material)
	for child in node.get_children():
		_style_throwable_model(child)

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
	held_throwable_visual.name = "HeldSlowGrenade"
	held_throwable_visual.scale = Vector3.ONE * 0.82
	held_throwable_visual.visible = false
	add_child(held_throwable_visual)
	if not _local_is_runner():
		_apply_opponent_item_ghost(held_throwable_visual)

func _ensure_held_speed_boost_visual() -> void:
	if held_speed_boost_visual != null and is_instance_valid(held_speed_boost_visual):
		return
	held_speed_boost_visual = _create_speed_boost_visual()
	held_speed_boost_visual.name = "HeldSpeedBoost"
	held_speed_boost_visual.scale = Vector3.ONE * 0.78
	_hide_held_ground_effects(held_speed_boost_visual, ["BoostEnergyRing", "BoostPickupMarker"])
	held_speed_boost_visual.visible = false
	add_child(held_speed_boost_visual)
	if not _local_is_runner():
		_apply_opponent_item_ghost(held_speed_boost_visual)

func _ensure_held_vision_card_visual() -> void:
	if held_vision_card_visual != null and is_instance_valid(held_vision_card_visual):
		return
	held_vision_card_visual = _create_vision_card_visual()
	held_vision_card_visual.name = "HeldVisionCard"
	held_vision_card_visual.scale = Vector3.ONE * 0.38
	_hide_held_ground_effects(held_vision_card_visual, ["VisionCardEnergyRing", "VisionCardPickupMarker"])
	held_vision_card_visual.visible = false
	add_child(held_vision_card_visual)
	if not _local_is_tagger():
		_apply_opponent_item_ghost(held_vision_card_visual)

func _hide_held_ground_effects(root: Node, effect_names: Array[String]) -> void:
	for effect_name in effect_names:
		var effect := root.find_child(effect_name, true, false)
		if effect is Node3D:
			(effect as Node3D).visible = false

func _apply_opponent_item_ghost(root: Node) -> void:
	var ghost_material := StandardMaterial3D.new()
	ghost_material.resource_local_to_scene = true
	ghost_material.albedo_color = Color(0.48, 0.54, 0.62, 0.38)
	ghost_material.metallic = 0.05
	ghost_material.roughness = 0.92
	ghost_material.emission_enabled = true
	ghost_material.emission = Color(0.2, 0.28, 0.38)
	ghost_material.emission_energy_multiplier = 0.45
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_ghost_material_recursive(root, ghost_material)

func _apply_ghost_material_recursive(node: Node, ghost_material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = ghost_material.duplicate(true) as StandardMaterial3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_ghost_material_recursive(child, ghost_material)

func _hide_held_throwable_visual() -> void:
	if held_throwable_visual != null and is_instance_valid(held_throwable_visual):
		held_throwable_visual.visible = false

func _hide_all_held_item_visuals() -> void:
	for visual in [held_throwable_visual, held_speed_boost_visual, held_vision_card_visual]:
		if visual != null and is_instance_valid(visual):
			visual.visible = false

func _destroy_held_item_visuals() -> void:
	for visual in [held_throwable_visual, held_speed_boost_visual, held_vision_card_visual]:
		if visual != null and is_instance_valid(visual):
			visual.queue_free()
	held_throwable_visual = null
	held_speed_boost_visual = null
	held_vision_card_visual = null

func _update_held_throwable_visual() -> void:
	if not _throwable_system_active() or caught:
		_hide_all_held_item_visuals()
		return

	var runner_valid := player != null and is_instance_valid(player)
	if runner_has_slow_grenade and runner_valid:
		_ensure_held_throwable_visual()
		if held_throwable_visual != null and is_instance_valid(held_throwable_visual):
			held_throwable_visual.global_position = _runner_throw_origin(player)
			held_throwable_visual.global_rotation = player.global_rotation
			held_throwable_visual.visible = true
	else:
		_hide_held_throwable_visual()

	if runner_has_speed_boost and runner_valid:
		_ensure_held_speed_boost_visual()
		if held_speed_boost_visual != null and is_instance_valid(held_speed_boost_visual):
			held_speed_boost_visual.global_position = _held_item_origin(player, -1.0, 0.98, 0.13)
			held_speed_boost_visual.global_rotation = player.global_rotation + Vector3(0.0, 0.0, deg_to_rad(10.0))
			held_speed_boost_visual.visible = true
	elif held_speed_boost_visual != null and is_instance_valid(held_speed_boost_visual):
		held_speed_boost_visual.visible = false

	var tagger_valid := tagger != null and is_instance_valid(tagger)
	if tagger_has_vision_card and tagger_valid:
		_ensure_held_vision_card_visual()
		if held_vision_card_visual != null and is_instance_valid(held_vision_card_visual):
			held_vision_card_visual.global_position = _held_item_origin(tagger, 1.0, 1.05, 0.16)
			held_vision_card_visual.global_rotation = tagger.global_rotation + Vector3(0.0, 0.0, deg_to_rad(-12.0))
			held_vision_card_visual.visible = true
	elif held_vision_card_visual != null and is_instance_valid(held_vision_card_visual):
		held_vision_card_visual.visible = false

func _held_item_origin(actor: Node3D, side: float, height: float, forward_offset: float) -> Vector3:
	if actor == null or not is_instance_valid(actor):
		return Vector3.ZERO
	var basis := actor.global_transform.basis
	return actor.global_position + basis.x.normalized() * 0.44 * side + Vector3.UP * height - basis.z.normalized() * forward_offset

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
	if not _local_is_runner() or not runner_has_slow_grenade or caught or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
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
		return "道具：减速弹 %s｜加速剂 %s（场上逃脱道具 %d 个）" % ["已携带，左键投掷" if runner_has_slow_grenade else "空槽，F 拾取", "已携带，E 使用" if runner_has_speed_boost else "空槽，F 拾取", _ground_runner_item_count()]
	if _local_is_tagger():
		return "卡片：透视卡 %s（场上卡片 %d 张）" % ["透视中 %.1fs" % tagger_vision_timer if tagger_vision_timer > 0.0 else "已携带，E 使用" if tagger_has_vision_card else "空槽，F 拾取", _ground_item_count(ITEM_TYPE_VISION_CARD)]
	return "场上道具：%d 个" % ground_throwables.size()

@rpc("call_remote", "reliable")
func _rpc_sync_ground_throwable_spawn(item_id: int, position: Vector3, item_type: String) -> void:
	_spawn_ground_throwable(position, item_id, item_type)

@rpc("call_remote", "reliable")
func _rpc_remove_ground_throwable(item_id: int) -> void:
	_remove_ground_throwable(item_id, false)

@rpc("call_remote", "reliable")
func _rpc_set_runner_inventory_state(has_slow_grenade: bool, has_speed_boost: bool) -> void:
	runner_has_slow_grenade = has_slow_grenade
	runner_has_speed_boost = has_speed_boost
	_update_held_throwable_visual()
	_update_runner_inventory_hud()
	if not has_slow_grenade:
		_hide_throwable_trajectory()

@rpc("call_remote", "reliable")
func _rpc_set_tagger_card_state(has_vision_card: bool) -> void:
	tagger_has_vision_card = has_vision_card
	_update_tagger_inventory_hud()

@rpc("any_peer", "reliable")
func _rpc_request_pickup_throwable(item_id: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _runner_peer_id():
		return
	_pickup_throwable_on_authority(item_id)

@rpc("any_peer", "reliable")
func _rpc_request_pickup_tagger_card(item_id: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _tagger_peer_id():
		return
	_pickup_tagger_card_on_authority(item_id)

@rpc("any_peer", "reliable")
func _rpc_request_throw_throwable(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _runner_peer_id():
		return
	_throw_throwable_on_authority(origin, direction)

@rpc("any_peer", "reliable")
func _rpc_request_use_speed_boost() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _runner_peer_id():
		return
	_use_speed_boost_on_authority()

@rpc("any_peer", "reliable")
func _rpc_request_use_vision_card() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _tagger_peer_id():
		return
	_use_vision_card_on_authority()

@rpc("call_remote", "reliable")
func _rpc_spawn_flying_throwable(projectile_id: int, origin: Vector3, velocity: Vector3) -> void:
	_spawn_flying_throwable(origin, velocity, projectile_id)

@rpc("call_remote", "reliable")
func _rpc_remove_flying_throwable(projectile_id: int, impact_position: Vector3) -> void:
	_remove_flying_throwable(projectile_id, false, impact_position)

@rpc("call_remote", "reliable")
func _rpc_apply_runner_speed_boost(multiplier: float, duration: float) -> void:
	if player != null and is_instance_valid(player) and player.has_method("apply_speed_multiplier"):
		player.apply_speed_multiplier(multiplier, duration)
	if _local_is_runner():
		_show_throwable_notice("使用加速剂：速度提升 %.0f%%，持续 %.1f 秒" % [(multiplier - 1.0) * 100.0, duration], Color(0.36, 1.0, 0.42), true)

@rpc("call_remote", "reliable")
func _rpc_activate_vision_card(duration: float) -> void:
	tagger_vision_timer = maxf(duration, 0.0)
	_update_tagger_inventory_hud()
	_update_vision_outline()
	if _local_is_tagger():
		_show_throwable_notice("透视卡已激活：小地图与穿墙轮廓已显示", Color(0.9, 0.5, 1.0), true)

@rpc("call_remote", "reliable")
func _rpc_apply_tagger_slow_effect(multiplier: float, duration: float, impact_position: Vector3, current_hit_count: int) -> void:
	tagger_hit_count = current_hit_count
	if tagger != null and is_instance_valid(tagger) and tagger.has_method("apply_speed_multiplier"):
		tagger.apply_speed_multiplier(multiplier, duration)
		_start_tagger_slow_particles(duration)
	_play_throwable_hit_effect(impact_position)
	if _local_is_runner():
		var runner_notice := "命中追逐者！%d / %d" % [tagger_hit_count, hits_to_win] if win_mode == WIN_MODE_HITS else "命中追逐者，已使其暂时减速"
		_show_throwable_notice(runner_notice, Color(0.34, 1.0, 0.58), true)
	elif _local_is_tagger():
		var tagger_notice := "被击中 %d / %d 次，暂时减速" % [tagger_hit_count, hits_to_win] if win_mode == WIN_MODE_HITS else "被击中，暂时减速"
		_show_throwable_notice(tagger_notice, Color(1.0, 0.46, 0.32), true)
