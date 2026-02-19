extends Node

signal player_list_changed()
signal lobby_config_changed()
signal match_state_changed()
signal score_changed()
signal timer_changed(time_remaining_s: int)
signal it_changed(it_peer_id: int)

const PROTOCOL_VERSION: int = 1

var max_players: int = 16
var match_duration_s: int = 180
var port: int = 24567
var tag_radius_m: float = 1.2
var arena_id: String = "default"

var players: Dictionary[int, Dictionary] = {}
var stats: Dictionary[int, Dictionary] = {}
var it_peer_id: int = 0
var match_start_unix_ms: int = 0
var time_remaining_s: int = 0
var is_running: bool = false

func reset_lobby() -> void:
    players.clear()
    stats.clear()
    it_peer_id = 0
    is_running = false
    match_start_unix_ms = 0
    time_remaining_s = 0
    player_list_changed.emit()
    score_changed.emit()
    match_state_changed.emit()
    timer_changed.emit(time_remaining_s)
    it_changed.emit(it_peer_id)

func set_config(
    next_max_players: int,
    next_duration_s: int,
    next_port: int,
    next_tag_radius_m: float,
    next_arena_id: String
) -> void:
    max_players = next_max_players
    match_duration_s = next_duration_s
    port = next_port
    tag_radius_m = next_tag_radius_m
    arena_id = next_arena_id
    lobby_config_changed.emit()

func apply_lobby_state(players_array: Array[Dictionary], config: Dictionary) -> void:
    if config.has("max_players"):
        max_players = int(config.get("max_players", max_players))
    if config.has("match_duration_s"):
        match_duration_s = int(config.get("match_duration_s", match_duration_s))
    if config.has("port"):
        port = int(config.get("port", port))
    if config.has("tag_radius_m"):
        tag_radius_m = float(config.get("tag_radius_m", tag_radius_m))
    if config.has("arena_id"):
        arena_id = str(config.get("arena_id", arena_id))

    players.clear()
    for player in players_array:
        var peer_id: int = int(player.get("peer_id", 0))
        if peer_id <= 0:
            continue
        players[peer_id] = {
            "peer_id": peer_id,
            "display_name": str(player.get("display_name", "Player")),
            "is_ready": bool(player.get("is_ready", false)),
            "join_index": int(player.get("join_index", 0)),
        }
        if not stats.has(peer_id):
            stats[peer_id] = {"times_caught": 0}

    player_list_changed.emit()
    lobby_config_changed.emit()

func make_players_snapshot() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var ids: Array[int] = []
    for peer_id in players.keys():
        ids.append(peer_id)
    ids.sort_custom(func(a: int, b: int) -> bool:
        var join_a: int = int(players[a].get("join_index", 0))
        var join_b: int = int(players[b].get("join_index", 0))
        return join_a < join_b
    )

    for peer_id in ids:
        var player: Dictionary = players[peer_id]
        out.append({
            "peer_id": peer_id,
            "display_name": str(player.get("display_name", "Player")),
            "is_ready": bool(player.get("is_ready", false)),
            "join_index": int(player.get("join_index", 0)),
        })
    return out

func make_config_snapshot() -> Dictionary:
    return {
        "max_players": max_players,
        "match_duration_s": match_duration_s,
        "port": port,
        "tag_radius_m": tag_radius_m,
        "arena_id": arena_id,
    }

func set_time_remaining(seconds: int) -> void:
    time_remaining_s = max(0, seconds)
    timer_changed.emit(time_remaining_s)

func set_it_peer_id(peer_id: int) -> void:
    it_peer_id = peer_id
    it_changed.emit(it_peer_id)

func begin_match(start_unix_ms: int, initial_it_peer_id: int) -> void:
    is_running = true
    match_start_unix_ms = start_unix_ms
    set_time_remaining(match_duration_s)
    set_it_peer_id(initial_it_peer_id)
    match_state_changed.emit()

func end_match() -> void:
    is_running = false
    match_state_changed.emit()

func upsert_player(peer_id: int, display_name: String, is_ready: bool, join_index: int) -> void:
    players[peer_id] = {
        "peer_id": peer_id,
        "display_name": display_name,
        "is_ready": is_ready,
        "join_index": join_index,
    }
    if not stats.has(peer_id):
        stats[peer_id] = {"times_caught": 0}
    player_list_changed.emit()
    score_changed.emit()

func remove_player(peer_id: int) -> void:
    players.erase(peer_id)
    stats.erase(peer_id)
    player_list_changed.emit()
    score_changed.emit()

func set_player_ready(peer_id: int, is_ready: bool) -> void:
    if not players.has(peer_id):
        return
    players[peer_id]["is_ready"] = is_ready
    player_list_changed.emit()

func add_times_caught(peer_id: int, delta: int = 1) -> void:
    if not stats.has(peer_id):
        stats[peer_id] = {"times_caught": 0}
    var current_times: int = int(stats[peer_id].get("times_caught", 0))
    stats[peer_id]["times_caught"] = max(0, current_times + delta)
    score_changed.emit()
