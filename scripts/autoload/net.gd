extends Node

signal connection_state_changed(state: int)
signal error(message: String)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal join_result(ok: bool, message: String)
signal player_transform_received(peer_id: int, pos: Vector3, yaw: float)

enum ConnectionState {
    DISCONNECTED,
    HOSTING,
    CONNECTING,
    CONNECTED_CLIENT,
}

const DEFAULT_PORT: int = 24567
const DEFAULT_MAX_PLAYERS: int = 16

var connection_state: int = ConnectionState.DISCONNECTED
var _next_join_index: int = 1

func _ready() -> void:
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

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

func request_player_transform(pos: Vector3, yaw: float) -> void:
    if is_host():
        var my_id: int = my_peer_id()
        rpc("rpc_sync_player_transform", my_id, pos, yaw)
        return
    rpc_id(1, "rpc_req_player_transform", pos, yaw)

func is_host() -> bool:
    return multiplayer.is_server()

func my_peer_id() -> int:
    return multiplayer.get_unique_id()

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
        Game.remove_player(peer_id)
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
func rpc_sync_start_match(config: Dictionary, it_peer_id: int, _seed: int) -> void:
    var max_players: int = int(config.get("max_players", Game.max_players))
    var match_duration_s: int = int(config.get("match_duration_s", Game.match_duration_s))
    var port: int = int(config.get("port", Game.port))
    var tag_radius_m: float = float(config.get("tag_radius_m", Game.tag_radius_m))
    var arena_id: String = str(config.get("arena_id", Game.arena_id))

    Game.set_config(max_players, match_duration_s, port, tag_radius_m, arena_id)
    var start_unix_ms: int = int(Time.get_unix_time_from_system() * 1000)
    Game.begin_match(start_unix_ms, it_peer_id)
    App.goto_match()

@rpc("any_peer", "unreliable_ordered")
func rpc_req_player_transform(pos: Vector3, yaw: float) -> void:
    if not is_host():
        return
    var sender_id: int = multiplayer.get_remote_sender_id()
    if not Game.players.has(sender_id):
        return
    rpc("rpc_sync_player_transform", sender_id, pos, yaw)

@rpc("authority", "call_local", "unreliable_ordered")
func rpc_sync_player_transform(peer_id: int, pos: Vector3, yaw: float) -> void:
    player_transform_received.emit(peer_id, pos, yaw)

func _broadcast_lobby_state() -> void:
    var players: Array[Dictionary] = Game.make_players_snapshot()
    var config: Dictionary = Game.make_config_snapshot()
    rpc("rpc_sync_lobby_state", players, config)

func _host_start_match() -> void:
    var players_snapshot: Array[Dictionary] = Game.make_players_snapshot()
    if players_snapshot.is_empty():
        _emit_error("Cannot start match without players.")
        return

    var first_player: Dictionary = players_snapshot[0]
    var initial_it_peer_id: int = int(first_player.get("peer_id", 1))
    var seed: int = randi()
    var config: Dictionary = Game.make_config_snapshot()

    rpc("rpc_sync_start_match", config, initial_it_peer_id, seed)
    rpc_sync_start_match(config, initial_it_peer_id, seed)
