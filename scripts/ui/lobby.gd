extends Control

const PREVIEW_IDLE_ANIMATION_NAME: String = "Idle"
const PREVIEW_BACKGROUND_COLOR: Color = Color(0.06, 0.07, 0.09, 1.0)
const CHARACTER_CHEF_SCENE: PackedScene = preload(
	"res://assets/quaternius/ultimate_animated_characters/glTF/Chef_Female.gltf"
)
const CHARACTER_CASUAL_SCENE: PackedScene = preload(
	"res://assets/quaternius/ultimate_animated_characters/glTF/Casual_Male.gltf"
)

var _character_options: Array[Dictionary] = [
	{"id": "chef_female", "name": "Chef Female"},
	{"id": "casual_male", "name": "Casual Male"},
]
var _local_ready: bool = false
var _preview_character_instance: Node
var _preview_pivot: Node3D

@onready var _session_label: Label = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/SessionLabel
@onready var _players_list: ItemList = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/PlayersList
@onready var _catcher_count_spin_box: SpinBox = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/CatcherCountSpinBox
@onready var _distribution_label: Label = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/DistributionLabel
@onready var _character_name_label: Label = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/CharacterNameLabel
@onready var _character_prev_button: Button = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/CharacterPreviewControls/CharacterPrevButton
@onready var _character_next_button: Button = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/CharacterPreviewControls/CharacterNextButton
@onready var _character_preview_viewport: SubViewport = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/CharacterPreviewControls/CharacterPreviewViewportContainer/CharacterPreviewViewport
@onready var _character_preview_root: Node3D = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/CharacterPreviewControls/CharacterPreviewViewportContainer/CharacterPreviewViewport/CharacterPreviewRoot
@onready var _character_preview_camera: Camera3D = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/CharacterPreviewControls/CharacterPreviewViewportContainer/CharacterPreviewViewport/CharacterPreviewCamera
@onready var _note_label: Label = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/NoteLabel
@onready var _leave_button: Button = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/LeaveButton
@onready var _start_match_button: Button = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/StartMatchButton
@onready var _ready_button: Button = $CenterContainer/PanelContainer/MarginContainer/ScrollContainer/VBox/ReadyButton


func _ready() -> void:
	_leave_button.pressed.connect(_on_leave_pressed)
	_start_match_button.pressed.connect(_on_start_match_pressed)
	_ready_button.pressed.connect(_on_ready_pressed)
	_catcher_count_spin_box.value_changed.connect(_on_catcher_count_changed)
	_character_prev_button.pressed.connect(_on_character_prev_pressed)
	_character_next_button.pressed.connect(_on_character_next_pressed)

	Game.player_list_changed.connect(_refresh_players)
	Game.lobby_config_changed.connect(_refresh_lobby_config)
	Game.catchers_changed.connect(_refresh_lobby_config)
	Net.connection_state_changed.connect(_refresh_session)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Settings.settings_changed.connect(_refresh_character_preview)

	_setup_character_preview_viewport()
	_refresh_session(Net.connection_state)
	_refresh_lobby_config()
	_refresh_players()
	_refresh_character_preview()


func _process(delta: float) -> void:
	if _preview_pivot != null:
		_preview_pivot.rotation.y += delta * 0.8


func _on_leave_pressed() -> void:
	App.request_leave_network()


func _on_start_match_pressed() -> void:
	if not Net.is_host():
		_note_label.text = "Only host can start match."
		return
	_note_label.text = "Starting match..."
	Net.request_start_match()


func _on_ready_pressed() -> void:
	_local_ready = not _local_ready
	Net.request_set_ready(_local_ready)
	_refresh_ready_button()


func _refresh_session(_state: int) -> void:
	if Net.is_host():
		_session_label.text = "Lobby: Host (%d)" % Net.my_peer_id()
		_start_match_button.disabled = false
		_catcher_count_spin_box.editable = true
	else:
		_session_label.text = "Lobby: Client (%d)" % Net.my_peer_id()
		_start_match_button.disabled = true
		_catcher_count_spin_box.editable = false


func _refresh_lobby_config() -> void:
	var player_count: int = Game.make_players_snapshot().size()
	var max_configurable_catchers: int = maxi(1, player_count - 1)
	_catcher_count_spin_box.min_value = 1
	_catcher_count_spin_box.max_value = max_configurable_catchers
	if int(_catcher_count_spin_box.value) != Game.catcher_count:
		_catcher_count_spin_box.set_value_no_signal(Game.catcher_count)
	_refresh_distribution_label(player_count)


func _refresh_players() -> void:
	_players_list.clear()

	var ids: Array[int] = []
	for peer_id in Game.players.keys():
		ids.append(peer_id)
	ids.sort_custom(
		func(a: int, b: int) -> bool:
			var join_a: int = int(Game.players[a].get("join_index", 0))
			var join_b: int = int(Game.players[b].get("join_index", 0))
			return join_a < join_b
	)

	for peer_id in ids:
		var player: Dictionary = Game.players[peer_id]
		var name: String = str(player.get("display_name", "Player"))
		var ready_text: String = "not ready"
		if bool(player.get("is_ready", false)):
			ready_text = "ready"
		_players_list.add_item("%s (%d) - %s" % [name, peer_id, ready_text])

	var my_id: int = Net.my_peer_id()
	if Game.players.has(my_id):
		_local_ready = bool(Game.players[my_id].get("is_ready", false))
		var authoritative_character_id: String = str(
			Game.players[my_id].get("character_id", Settings.character_id)
		)
		if authoritative_character_id != Settings.character_id:
			Settings.set_character_id(authoritative_character_id)
	_refresh_ready_button()
	_refresh_lobby_config()
	_refresh_character_preview()


func _on_peer_connected(peer_id: int) -> void:
	_note_label.text = "Peer connected: %d" % peer_id


func _on_peer_disconnected(peer_id: int) -> void:
	_note_label.text = "Peer disconnected: %d" % peer_id


func _refresh_ready_button() -> void:
	if _local_ready:
		_ready_button.text = "Set Not Ready"
	else:
		_ready_button.text = "Set Ready"
	_character_prev_button.disabled = _local_ready
	_character_next_button.disabled = _local_ready


func _on_catcher_count_changed(value: float) -> void:
	if not Net.is_host():
		_refresh_lobby_config()
		return
	Net.request_set_catcher_count(int(value))
	_refresh_lobby_config()


func _refresh_distribution_label(player_count: int = -1) -> void:
	if player_count < 0:
		player_count = Game.make_players_snapshot().size()
	if player_count <= 0:
		_distribution_label.text = "Catcher config: %d | Waiting for players" % Game.catcher_count
		return
	var effective_catchers: int = Game.get_effective_catcher_count(player_count)
	var runners: int = maxi(0, player_count - effective_catchers)
	_distribution_label.text = (
		"Catcher config: %d | Effective: %d catcher / %d runner"
		% [Game.catcher_count, effective_catchers, runners]
	)


func _on_character_prev_pressed() -> void:
	_cycle_character_selection(-1)


func _on_character_next_pressed() -> void:
	_cycle_character_selection(1)


func _cycle_character_selection(direction: int) -> void:
	if _local_ready:
		return
	if _character_options.is_empty():
		return
	var current_index: int = _get_character_index_by_id(Settings.character_id)
	var next_index: int = posmod(current_index + direction, _character_options.size())
	var next_character_id: String = str(_character_options[next_index].get("id", "chef_female"))
	Settings.set_character_id(next_character_id)
	if Net.has_multiplayer_peer():
		Net.request_set_character(next_character_id)
	_refresh_character_preview()


func _refresh_character_preview() -> void:
	if _character_options.is_empty():
		return
	var current_index: int = _get_character_index_by_id(Settings.character_id)
	var entry: Dictionary = _character_options[current_index]
	_character_name_label.text = str(entry.get("name", "Character"))
	_spawn_preview_character(str(entry.get("id", "chef_female")))


func _get_character_index_by_id(character_id: String) -> int:
	for i in range(_character_options.size()):
		if str(_character_options[i].get("id", "")) == character_id:
			return i
	return 0


func _setup_character_preview_viewport() -> void:
	if _character_preview_viewport == null or _character_preview_root == null:
		return
	_character_preview_viewport.disable_3d = false
	_character_preview_viewport.own_world_3d = true
	_character_preview_viewport.msaa_3d = Viewport.MSAA_2X
	_character_preview_viewport.positional_shadow_atlas_size = 1024
	_character_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _character_preview_camera != null:
		_character_preview_camera.position = Vector3(0, 1.5, 3.2)
		_character_preview_camera.look_at(Vector3(0, 1.1, 0), Vector3.UP)

	if _preview_pivot == null:
		_preview_pivot = Node3D.new()
		_preview_pivot.name = "PreviewPivot"
		_character_preview_root.add_child(_preview_pivot)

	var world_environment: WorldEnvironment = _character_preview_viewport.get_node_or_null(
		"PreviewEnvironment"
	)
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "PreviewEnvironment"
		var env: Environment = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = PREVIEW_BACKGROUND_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.38, 0.4, 0.44, 1.0)
		env.ambient_light_energy = 1.0
		world_environment.environment = env
		_character_preview_viewport.add_child(world_environment)


func _spawn_preview_character(character_id: String) -> void:
	if _preview_pivot == null:
		return
	if _preview_character_instance != null:
		_preview_character_instance.queue_free()
		_preview_character_instance = null

	var scene: PackedScene = _get_character_scene(character_id)
	if scene == null:
		return

	var instance: Node = scene.instantiate()
	_preview_character_instance = instance
	if instance is Node3D:
		var model: Node3D = instance as Node3D
		model.position = Vector3(0, -1.0, 0)
		model.scale = Vector3(1.0, 1.0, 1.0)
	_preview_pivot.rotation = Vector3.ZERO
	_preview_pivot.add_child(instance)
	_play_preview_idle(instance)


func _get_character_scene(character_id: String) -> PackedScene:
	match character_id:
		"casual_male":
			return CHARACTER_CASUAL_SCENE
		_:
			return CHARACTER_CHEF_SCENE


func _play_preview_idle(root: Node) -> void:
	var animation_player: AnimationPlayer = _find_animation_player_recursive(root)
	if animation_player == null:
		return
	if animation_player.has_animation(PREVIEW_IDLE_ANIMATION_NAME):
		animation_player.play(PREVIEW_IDLE_ANIMATION_NAME)
		return
	var animations: PackedStringArray = animation_player.get_animation_list()
	if not animations.is_empty():
		animation_player.play(animations[0])


func _find_animation_player_recursive(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var nested: AnimationPlayer = _find_animation_player_recursive(child)
		if nested != null:
			return nested
	return null
