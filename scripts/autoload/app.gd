extends Node

const MAIN_MENU_SCENE: String = "res://scenes/MainMenu.tscn"
const LOBBY_SCENE: String = "res://scenes/Lobby.tscn"
const MATCH_SCENE: String = "res://scenes/Match.tscn"
const RESULTS_SCENE: String = "res://scenes/Results.tscn"


func _ready() -> void:
	if not Game.results_changed.is_connected(_on_game_results_changed):
		Game.results_changed.connect(_on_game_results_changed)


func request_host(port: int, max_players: int) -> void:
	var ok: bool = Net.host(port, max_players)
	if ok:
		Game.reset_lobby()
		Game.set_config(
			max_players,
			Game.match_duration_s,
			port,
			Game.tag_radius_m,
			Game.arena_id,
			Game.catcher_count
		)
		_upsert_local_player(false, 0)
		Game.rebalance_catchers()
		goto_lobby()


func request_join(host_ip: String, port: int) -> void:
	var ok: bool = Net.join(host_ip, port)
	if ok:
		Game.reset_lobby()
		goto_lobby()


func request_leave_network() -> void:
	Net.disconnect_from_session()
	Game.reset_lobby()
	goto_main_menu()


func goto_main_menu() -> void:
	_change_scene_if_exists(MAIN_MENU_SCENE)


func goto_lobby() -> void:
	_change_scene_if_exists(LOBBY_SCENE)


func goto_match() -> void:
	_change_scene_if_exists(MATCH_SCENE)


func goto_results() -> void:
	_change_scene_if_exists(RESULTS_SCENE)


func _change_scene_if_exists(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_warning("Scene does not exist yet: %s" % scene_path)
		return
	get_tree().change_scene_to_file(scene_path)


func _upsert_local_player(is_ready: bool, join_index: int) -> void:
	var peer_id: int = Net.my_peer_id()
	var display_name: String = Settings.display_name
	Game.upsert_player(peer_id, display_name, is_ready, join_index)


func _on_game_results_changed() -> void:
	if Game.is_running:
		return
	if Game.last_results.is_empty():
		return
	goto_results()
