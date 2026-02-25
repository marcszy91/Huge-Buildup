extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")
const TRANSFORM_SEND_INTERVAL_S: float = 1.0 / 15.0
const CATCH_ATTEMPT_COOLDOWN_S: float = 0.15
const SPAWN_ROW_WIDTH: int = 4
const SPAWN_SPACING: float = 4.0

var _spawned_players: Dictionary[int, CharacterBody3D] = {}
var _local_peer_id: int = 0
var _tx_accum_s: float = 0.0
var _catch_attempt_cooldown_s: float = 0.0
@onready var _players_root: Node3D = $Players


func _ready() -> void:
	_local_peer_id = Net.my_peer_id()
	_spawn_match_players()
	Net.player_transform_received.connect(_on_player_transform_received)
	Net.catch_applied.connect(_on_catch_applied)
	Game.catchers_changed.connect(_refresh_role_visuals)
	_refresh_role_visuals()


func _exit_tree() -> void:
	if Net.player_transform_received.is_connected(_on_player_transform_received):
		Net.player_transform_received.disconnect(_on_player_transform_received)
	if Net.catch_applied.is_connected(_on_catch_applied):
		Net.catch_applied.disconnect(_on_catch_applied)
	if Game.catchers_changed.is_connected(_refresh_role_visuals):
		Game.catchers_changed.disconnect(_refresh_role_visuals)


func _physics_process(delta: float) -> void:
	if not _spawned_players.has(_local_peer_id):
		return
	_refresh_local_freeze_state()

	if _catch_attempt_cooldown_s > 0.0:
		_catch_attempt_cooldown_s = maxf(0.0, _catch_attempt_cooldown_s - delta)

	_tx_accum_s += delta
	var player: CharacterBody3D = _spawned_players[_local_peer_id]
	if _tx_accum_s >= TRANSFORM_SEND_INTERVAL_S:
		_tx_accum_s = 0.0
		Net.request_player_transform(player.global_position, player.rotation.y)

	if not Game.is_running:
		return
	if not Game.is_catcher(_local_peer_id):
		return
	if Game.is_peer_catch_frozen(_local_peer_id):
		return
	if _catch_attempt_cooldown_s > 0.0:
		return

	var target_peer_id: int = _find_touching_runner(player.global_position)
	if target_peer_id <= 0:
		return

	_catch_attempt_cooldown_s = CATCH_ATTEMPT_COOLDOWN_S
	Net.request_catch_attempt(target_peer_id, player.global_position)


func _spawn_match_players() -> void:
	_spawned_players.clear()

	var players_snapshot: Array[Dictionary] = Game.make_players_snapshot()
	if players_snapshot.is_empty():
		players_snapshot = [
			{
				"peer_id": _local_peer_id,
				"display_name": Settings.display_name,
				"is_ready": false,
				"join_index": 0,
			}
		]

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

	_refresh_role_visuals()


func _on_player_transform_received(peer_id: int, pos: Vector3, yaw: float) -> void:
	if not _spawned_players.has(peer_id):
		return
	if peer_id == _local_peer_id:
		return

	var player: CharacterBody3D = _spawned_players[peer_id]
	if player.has_method("set_network_target_transform"):
		player.call("set_network_target_transform", pos, yaw)


func _on_catch_applied(_catcher_peer_id: int, _victim_peer_id: int) -> void:
	_catch_attempt_cooldown_s = CATCH_ATTEMPT_COOLDOWN_S
	_refresh_local_freeze_state()
	_refresh_role_visuals()


func _find_touching_runner(origin: Vector3) -> int:
	var best_target_peer_id: int = 0
	var best_distance: float = INF
	var max_distance: float = Game.tag_radius_m + 0.1

	for peer_id in _spawned_players.keys():
		if peer_id == _local_peer_id:
			continue
		if Game.is_catcher(peer_id):
			continue
		var player: CharacterBody3D = _spawned_players[peer_id]
		var distance: float = origin.distance_to(player.global_position)
		if distance > max_distance:
			continue
		if distance < best_distance:
			best_distance = distance
			best_target_peer_id = peer_id

	return best_target_peer_id


func _refresh_role_visuals() -> void:
	var local_is_catcher: bool = Game.is_catcher(_local_peer_id)
	for peer_id in _spawned_players.keys():
		var player: CharacterBody3D = _spawned_players[peer_id]
		if player.has_method("set_role_visual"):
			player.call(
				"set_role_visual",
				local_is_catcher,
				Game.is_catcher(peer_id),
				peer_id == _local_peer_id
			)
	_refresh_local_freeze_state()


func _refresh_local_freeze_state() -> void:
	if not _spawned_players.has(_local_peer_id):
		return
	var local_player: CharacterBody3D = _spawned_players[_local_peer_id]
	if local_player.has_method("set_frozen"):
		local_player.call("set_frozen", Game.is_peer_catch_frozen(_local_peer_id))


func _spawn_position_for_index(i: int) -> Vector3:
	var col: int = i % SPAWN_ROW_WIDTH
	var row: int = i / SPAWN_ROW_WIDTH
	var x: float = (float(col) - 1.5) * SPAWN_SPACING
	var z: float = (float(row) - 1.5) * SPAWN_SPACING
	return Vector3(x, 1.0, z)
