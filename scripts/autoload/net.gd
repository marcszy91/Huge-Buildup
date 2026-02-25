extends Node

signal connection_state_changed(state: int)
signal error(message: String)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal join_result(ok: bool, message: String)
signal player_transform_received(peer_id: int, pos: Vector3, yaw: float)
signal catch_applied(catcher_peer_id: int, victim_peer_id: int)

enum ConnectionState {
	DISCONNECTED,
	HOSTING,
	CONNECTING,
	CONNECTED_CLIENT,
}

const DEFAULT_PORT: int = 24567
const DEFAULT_MAX_PLAYERS: int = 16
const NEW_CATCHER_FREEZE_MS: int = 3000

var connection_state: int = ConnectionState.DISCONNECTED
var _next_join_index: int = 1
var _last_synced_time_remaining: int = -1
var _host_player_positions: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(true)


func _process(_delta: float) -> void:
	if not has_multiplayer_peer():
		return
	if not is_host():
		return
	if not Game.is_running:
		return

	var now_unix_ms: int = int(Time.get_unix_time_from_system() * 1000)
	var elapsed_ms: int = max(0, now_unix_ms - Game.match_start_unix_ms)
	var remaining_s: int = maxi(0, Game.match_duration_s - int(floor(elapsed_ms / 1000.0)))

	if remaining_s != _last_synced_time_remaining:
		_last_synced_time_remaining = remaining_s
		rpc("rpc_sync_time_remaining", remaining_s)

	if remaining_s <= 0:
		_host_finish_match()


func host(port: int = DEFAULT_PORT, max_players: int = DEFAULT_MAX_PLAYERS) -> bool:
	disconnect_from_session()

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, max_players)
	if err != OK:
		_emit_error("Failed to host on port %d (err=%d)." % [port, err])
		return false

	multiplayer.multiplayer_peer = peer
	_next_join_index = 1
	_set_state(ConnectionState.HOSTING)
	return true


func join(host_ip: String, port: int = DEFAULT_PORT) -> bool:
	disconnect_from_session()

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(host_ip, port)
	if err != OK:
		_emit_error("Failed to connect to %s:%d (err=%d)." % [host_ip, port, err])
		return false

	multiplayer.multiplayer_peer = peer
	_set_state(ConnectionState.CONNECTING)
	return true


func disconnect_from_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_last_synced_time_remaining = -1
	_host_player_positions.clear()
	_set_state(ConnectionState.DISCONNECTED)


func request_set_ready(is_ready: bool) -> void:
	if is_host():
		var my_id: int = my_peer_id()
		Game.set_player_ready(my_id, is_ready)
		rpc("rpc_sync_player_ready", my_id, is_ready)
		_broadcast_lobby_state()
		return
	rpc_id(1, "rpc_req_set_ready", is_ready)


func request_start_match() -> void:
	if not is_host():
		_emit_error("Only host can start match.")
		return
	_host_start_match()


func request_set_catcher_count(next_catcher_count: int) -> void:
	if not is_host():
		_emit_error("Only host can change catcher count.")
		return
	var player_count: int = Game.players.size()
	var clamped_catcher_count: int = maxi(1, next_catcher_count)
	if player_count >= 2:
		clamped_catcher_count = mini(clamped_catcher_count, player_count - 1)
	Game.set_config(
		Game.max_players,
		Game.match_duration_s,
		Game.port,
		Game.tag_radius_m,
		Game.arena_id,
		clamped_catcher_count
	)
	Game.rebalance_catchers()
	_broadcast_lobby_state()


func request_player_transform(pos: Vector3, yaw: float) -> void:
	if is_host():
		var my_id: int = my_peer_id()
		_host_player_positions[my_id] = pos
		rpc("rpc_sync_player_transform", my_id, pos, yaw)
		return
	rpc_id(1, "rpc_req_player_transform", pos, yaw)


func request_catch_attempt(target_peer_id: int, my_pos: Vector3) -> void:
	if not Game.is_running:
		return
	if is_host():
		_host_handle_catch_attempt(my_peer_id(), target_peer_id, my_pos)
		return
	rpc_id(1, "rpc_req_catch_attempt", target_peer_id, my_pos)


func is_host() -> bool:
	if not has_multiplayer_peer():
		return false
	return multiplayer.is_server()


func my_peer_id() -> int:
	if not has_multiplayer_peer():
		return 0
	return multiplayer.get_unique_id()


func has_multiplayer_peer() -> bool:
	return multiplayer.multiplayer_peer != null


func _set_state(next_state: int) -> void:
	if connection_state == next_state:
		return
	connection_state = next_state
	connection_state_changed.emit(connection_state)


func _emit_error(message: String) -> void:
	error.emit(message)


func _on_peer_connected(peer_id: int) -> void:
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if is_host():
		_host_player_positions.erase(peer_id)
		Game.clear_catch_freeze(peer_id)
		Game.remove_player(peer_id)
		Game.rebalance_catchers()
		rpc("rpc_sync_player_left", peer_id)
		_broadcast_lobby_state()
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	_set_state(ConnectionState.CONNECTED_CLIENT)
	rpc_id(1, "rpc_req_join", Settings.display_name, Game.PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	_emit_error("Connection failed.")
	disconnect_from_session()
	App.goto_main_menu()


func _on_server_disconnected() -> void:
	_emit_error("Disconnected from host.")
	disconnect_from_session()
	App.goto_main_menu()


@rpc("any_peer", "reliable")
func rpc_req_join(display_name: String, client_version: int) -> void:
	if not is_host():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if client_version != Game.PROTOCOL_VERSION:
		rpc_id(sender_id, "rpc_sync_join_result", false, "Protocol mismatch.", 0)
		return
	if Game.players.size() >= Game.max_players:
		rpc_id(sender_id, "rpc_sync_join_result", false, "Lobby full.", 0)
		return

	var clean_name: String = display_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Player"

	Game.upsert_player(sender_id, clean_name, false, _next_join_index)
	_next_join_index += 1
	Game.rebalance_catchers()
	rpc_id(sender_id, "rpc_sync_join_result", true, "Joined.", sender_id)
	_broadcast_lobby_state()


@rpc("any_peer", "reliable")
func rpc_req_set_ready(is_ready: bool) -> void:
	if not is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not Game.players.has(sender_id):
		return
	Game.set_player_ready(sender_id, is_ready)
	rpc("rpc_sync_player_ready", sender_id, is_ready)
	_broadcast_lobby_state()


@rpc("authority", "reliable")
func rpc_sync_join_result(ok: bool, message: String, assigned_peer_id: int) -> void:
	join_result.emit(ok, message)
	if not ok:
		_emit_error(message)
		disconnect_from_session()
		App.goto_main_menu()
		return
	if not Game.players.has(assigned_peer_id):
		Game.upsert_player(assigned_peer_id, Settings.display_name, false, 9999)


@rpc("authority", "reliable")
func rpc_sync_lobby_state(players: Array[Dictionary], config: Dictionary) -> void:
	Game.apply_lobby_state(players, config)


@rpc("authority", "reliable")
func rpc_sync_player_ready(peer_id: int, is_ready: bool) -> void:
	Game.set_player_ready(peer_id, is_ready)


@rpc("authority", "reliable")
func rpc_sync_player_left(peer_id: int) -> void:
	Game.remove_player(peer_id)


@rpc("authority", "reliable")
func rpc_sync_start_match(
	config: Dictionary, it_peer_id: int, _seed: int, catcher_ids: Array[int]
) -> void:
	var max_players: int = int(config.get("max_players", Game.max_players))
	var match_duration_s: int = int(config.get("match_duration_s", Game.match_duration_s))
	var port: int = int(config.get("port", Game.port))
	var tag_radius_m: float = float(config.get("tag_radius_m", Game.tag_radius_m))
	var arena_id: String = str(config.get("arena_id", Game.arena_id))
	var catcher_count: int = int(config.get("catcher_count", Game.catcher_count))

	Game.set_config(max_players, match_duration_s, port, tag_radius_m, arena_id, catcher_count)
	var start_unix_ms: int = int(Time.get_unix_time_from_system() * 1000)
	_last_synced_time_remaining = -1
	Game.begin_match(start_unix_ms, it_peer_id, catcher_ids)
	App.goto_match()


@rpc("authority", "call_local", "reliable")
func rpc_sync_time_remaining(time_remaining_s: int) -> void:
	Game.set_time_remaining(time_remaining_s)


@rpc("authority", "call_local", "reliable")
func rpc_sync_match_end(results: Array[Dictionary]) -> void:
	Game.apply_match_end(results)


@rpc("any_peer", "unreliable_ordered")
func rpc_req_player_transform(pos: Vector3, yaw: float) -> void:
	if not is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not Game.players.has(sender_id):
		return
	_host_player_positions[sender_id] = pos
	rpc("rpc_sync_player_transform", sender_id, pos, yaw)


@rpc("authority", "call_local", "unreliable_ordered")
func rpc_sync_player_transform(peer_id: int, pos: Vector3, yaw: float) -> void:
	player_transform_received.emit(peer_id, pos, yaw)


@rpc("any_peer", "reliable")
func rpc_req_catch_attempt(target_peer_id: int, my_pos: Vector3) -> void:
	if not is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_host_handle_catch_attempt(sender_id, target_peer_id, my_pos)


@rpc("authority", "call_local", "reliable")
func rpc_sync_catch_applied(
	catcher_peer_id: int,
	victim_peer_id: int,
	victim_times_caught: int,
	catcher_ids: Array[int],
	freeze_until_unix_ms: int
) -> void:
	Game.set_times_caught(victim_peer_id, victim_times_caught)
	Game.set_catchers(catcher_ids)
	Game.set_catch_freeze_until(victim_peer_id, freeze_until_unix_ms)
	catch_applied.emit(catcher_peer_id, victim_peer_id)


func _broadcast_lobby_state() -> void:
	var players: Array[Dictionary] = Game.make_players_snapshot()
	var config: Dictionary = Game.make_config_snapshot()
	rpc("rpc_sync_lobby_state", players, config)


func _host_start_match() -> void:
	var players_snapshot: Array[Dictionary] = Game.make_players_snapshot()
	if players_snapshot.is_empty():
		_emit_error("Cannot start match without players.")
		return
	if players_snapshot.size() < 2:
		_emit_error("Need at least 2 players (at least 1 catcher and 1 runner).")
		return

	Game.rebalance_catchers()
	var catcher_ids: Array[int] = Game.get_catcher_peer_ids()
	if catcher_ids.is_empty():
		_emit_error("No catchers assigned.")
		return

	var initial_it_peer_id: int = int(catcher_ids[0])
	var seed: int = randi()
	var config: Dictionary = Game.make_config_snapshot()

	rpc("rpc_sync_start_match", config, initial_it_peer_id, seed, catcher_ids)
	rpc_sync_start_match(config, initial_it_peer_id, seed, catcher_ids)


func _host_finish_match() -> void:
	if not is_host():
		return
	if not Game.is_running:
		return

	var results: Array[Dictionary] = Game.build_results_snapshot()
	_last_synced_time_remaining = 0
	rpc("rpc_sync_match_end", results)


func _host_handle_catch_attempt(sender_id: int, target_peer_id: int, my_pos: Vector3) -> void:
	if not is_host():
		return
	if not Game.is_running:
		return
	if sender_id <= 0 or target_peer_id <= 0:
		return
	if sender_id == target_peer_id:
		return
	if not Game.players.has(sender_id) or not Game.players.has(target_peer_id):
		return
	if not Game.is_catcher(sender_id):
		return
	if Game.is_catcher(target_peer_id):
		return
	if Game.is_peer_catch_frozen(sender_id):
		return

	var sender_pos: Vector3
	if _host_player_positions.has(sender_id):
		sender_pos = _host_player_positions[sender_id]
	else:
		sender_pos = my_pos
	_host_player_positions[sender_id] = sender_pos

	if not _host_player_positions.has(target_peer_id):
		return
	var target_pos: Vector3 = _host_player_positions[target_peer_id]

	var max_distance: float = Game.tag_radius_m + 0.25
	if sender_pos.distance_to(target_pos) > max_distance:
		return

	Game.add_times_caught(target_peer_id, 1)
	var victim_times_caught: int = Game.get_times_caught(target_peer_id)

	var next_catchers: Array[int] = Game.get_catcher_peer_ids()
	var catcher_index: int = next_catchers.find(sender_id)
	if catcher_index < 0:
		return
	next_catchers[catcher_index] = target_peer_id
	Game.set_catchers(next_catchers)
	var freeze_until_unix_ms: int = (
		int(Time.get_unix_time_from_system() * 1000) + NEW_CATCHER_FREEZE_MS
	)
	Game.set_catch_freeze_until(target_peer_id, freeze_until_unix_ms)

	rpc(
		"rpc_sync_catch_applied",
		sender_id,
		target_peer_id,
		victim_times_caught,
		next_catchers,
		freeze_until_unix_ms
	)
