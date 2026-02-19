extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")
const TRANSFORM_SEND_INTERVAL_S: float = 1.0 / 15.0
const SPAWN_ROW_WIDTH: int = 4
const SPAWN_SPACING: float = 4.0

var _spawned_players: Dictionary[int, CharacterBody3D] = {}
var _local_peer_id: int = 0
var _tx_accum_s: float = 0.0
@onready var _players_root: Node3D = $Players

func _ready() -> void:
    _local_peer_id = Net.my_peer_id()
    _spawn_match_players()
    Net.player_transform_received.connect(_on_player_transform_received)

func _exit_tree() -> void:
    if Net.player_transform_received.is_connected(_on_player_transform_received):
        Net.player_transform_received.disconnect(_on_player_transform_received)

func _physics_process(delta: float) -> void:
    if not _spawned_players.has(_local_peer_id):
        return

    _tx_accum_s += delta
    if _tx_accum_s < TRANSFORM_SEND_INTERVAL_S:
        return
    _tx_accum_s = 0.0

    var player: CharacterBody3D = _spawned_players[_local_peer_id]
    Net.request_player_transform(player.global_position, player.rotation.y)

func _spawn_match_players() -> void:
    _spawned_players.clear()

    var players_snapshot: Array[Dictionary] = Game.make_players_snapshot()
    if players_snapshot.is_empty():
        players_snapshot = [{
            "peer_id": _local_peer_id,
            "display_name": Settings.display_name,
            "is_ready": false,
            "join_index": 0,
        }]

    for i in range(players_snapshot.size()):
        var peer_id: int = int(players_snapshot[i].get("peer_id", 0))
        if peer_id <= 0:
            continue

        var player: CharacterBody3D = PLAYER_SCENE.instantiate()
        player.name = "Player_%d" % peer_id
        player.position = _spawn_position_for_index(i)
        _players_root.add_child(player)

        if player.has_method("set_local_controlled"):
            player.call("set_local_controlled", peer_id == _local_peer_id)
        _spawned_players[peer_id] = player

func _on_player_transform_received(peer_id: int, pos: Vector3, yaw: float) -> void:
    if not _spawned_players.has(peer_id):
        return
    if peer_id == _local_peer_id:
        return

    var player: CharacterBody3D = _spawned_players[peer_id]
    if player.has_method("set_network_target_transform"):
        player.call("set_network_target_transform", pos, yaw)

func _spawn_position_for_index(i: int) -> Vector3:
    var col: int = i % SPAWN_ROW_WIDTH
    var row: int = i / SPAWN_ROW_WIDTH
    var x: float = (float(col) - 1.5) * SPAWN_SPACING
    var z: float = (float(row) - 1.5) * SPAWN_SPACING
    return Vector3(x, 1.0, z)
