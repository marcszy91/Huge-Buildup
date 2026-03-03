extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")
const TRANSFORM_SEND_INTERVAL_S: float = 1.0 / 15.0
const CATCH_ATTEMPT_COOLDOWN_S: float = 0.15
const POWERUP_COLLECT_COOLDOWN_S: float = 0.15
const SPAWN_ROW_WIDTH: int = 4
const SPAWN_SPACING: float = 4.0
const POWERUP_Y_ROTATION_SPEED: float = 2.2

var _spawned_players: Dictionary[int, CharacterBody3D] = {}
var _powerup_nodes: Dictionary[int, Node3D] = {}
var _local_peer_id: int = 0
var _tx_accum_s: float = 0.0
var _catch_attempt_cooldown_s: float = 0.0
var _powerup_collect_cooldown_s: float = 0.0
@onready var _players_root: Node3D = $Players
@onready var _powerups_root: Node3D = $Powerups


func _ready() -> void:
	_local_peer_id = Net.my_peer_id()
	_spawn_match_players()
	Net.player_transform_received.connect(_on_player_transform_received)
	Net.catch_applied.connect(_on_catch_applied)
	Net.powerup_teleport_received.connect(_on_powerup_teleport_received)
	Game.catchers_changed.connect(_refresh_role_visuals)
	Game.powerups_changed.connect(_refresh_powerup_nodes)
	Game.powerup_effect_changed.connect(_on_powerup_effect_changed)
	_refresh_powerup_nodes()
	_refresh_role_visuals()


func _exit_tree() -> void:
	if Net.player_transform_received.is_connected(_on_player_transform_received):
		Net.player_transform_received.disconnect(_on_player_transform_received)
	if Net.catch_applied.is_connected(_on_catch_applied):
		Net.catch_applied.disconnect(_on_catch_applied)
	if Net.powerup_teleport_received.is_connected(_on_powerup_teleport_received):
		Net.powerup_teleport_received.disconnect(_on_powerup_teleport_received)
	if Game.catchers_changed.is_connected(_refresh_role_visuals):
		Game.catchers_changed.disconnect(_refresh_role_visuals)
	if Game.powerups_changed.is_connected(_refresh_powerup_nodes):
		Game.powerups_changed.disconnect(_refresh_powerup_nodes)
	if Game.powerup_effect_changed.is_connected(_on_powerup_effect_changed):
		Game.powerup_effect_changed.disconnect(_on_powerup_effect_changed)


func _physics_process(delta: float) -> void:
	if not _spawned_players.has(_local_peer_id):
		return
	_refresh_local_freeze_state()

	if _catch_attempt_cooldown_s > 0.0:
		_catch_attempt_cooldown_s = maxf(0.0, _catch_attempt_cooldown_s - delta)
	if _powerup_collect_cooldown_s > 0.0:
		_powerup_collect_cooldown_s = maxf(0.0, _powerup_collect_cooldown_s - delta)

	_tx_accum_s += delta
	var player: CharacterBody3D = _spawned_players[_local_peer_id]
	if _tx_accum_s >= TRANSFORM_SEND_INTERVAL_S:
		_tx_accum_s = 0.0
		Net.request_player_transform(player.global_position, player.rotation.y)

	_refresh_player_effect_visuals()
	_update_powerup_visuals(delta)
	if _powerup_collect_cooldown_s <= 0.0:
		var powerup_id: int = _find_touching_powerup(player.global_position)
		if powerup_id > 0:
			_powerup_collect_cooldown_s = POWERUP_COLLECT_COOLDOWN_S
			Net.request_collect_powerup(powerup_id, player.global_position)

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
				"character_id": Settings.character_id,
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
		var character_id: String = str(players_snapshot[i].get("character_id", "chef_female"))
		if player.has_method("set_character_id"):
			player.call("set_character_id", character_id)

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


func _on_powerup_teleport_received(peer_id: int, pos: Vector3) -> void:
	if not _spawned_players.has(peer_id):
		return
	var player: CharacterBody3D = _spawned_players[peer_id]
	if player.has_method("snap_to_world_position"):
		player.call("snap_to_world_position", pos)
		return
	player.global_position = pos


func _on_powerup_effect_changed(_peer_id: int) -> void:
	_refresh_player_effect_visuals()


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


func _find_touching_powerup(origin: Vector3) -> int:
	var best_powerup_id: int = 0
	var best_distance: float = INF

	for powerup in Game.spawned_powerups:
		var powerup_id: int = int(powerup.get("powerup_id", 0))
		if powerup_id <= 0:
			continue
		var powerup_pos: Vector3 = powerup.get("position", Vector3.ZERO)
		var distance: float = origin.distance_to(powerup_pos)
		if distance > 1.4:
			continue
		if distance < best_distance:
			best_distance = distance
			best_powerup_id = powerup_id

	return best_powerup_id


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
	_refresh_player_effect_visuals()


func _refresh_local_freeze_state() -> void:
	if not _spawned_players.has(_local_peer_id):
		return
	var local_player: CharacterBody3D = _spawned_players[_local_peer_id]
	if local_player.has_method("set_frozen"):
		local_player.call("set_frozen", Game.is_peer_catch_frozen(_local_peer_id))


func _refresh_player_effect_visuals() -> void:
	for peer_id in _spawned_players.keys():
		var player: CharacterBody3D = _spawned_players[peer_id]
		var is_hidden_from_local_view: bool = (
			peer_id != _local_peer_id and Game.has_active_powerup_effect(peer_id, "invisible")
		)
		if player.has_method("set_invisible_state"):
			player.call("set_invisible_state", is_hidden_from_local_view)


func _refresh_powerup_nodes() -> void:
	var active_ids: Array[int] = []
	for powerup in Game.spawned_powerups:
		var powerup_id: int = int(powerup.get("powerup_id", 0))
		if powerup_id <= 0:
			continue
		active_ids.append(powerup_id)
		if not _powerup_nodes.has(powerup_id):
			_powerup_nodes[powerup_id] = _create_powerup_node(str(powerup.get("type", "")))
			_powerups_root.add_child(_powerup_nodes[powerup_id])
		var powerup_node: Node3D = _powerup_nodes[powerup_id]
		powerup_node.global_position = powerup.get("position", Vector3.ZERO)

	var existing_ids: Array[int] = []
	for powerup_id in _powerup_nodes.keys():
		existing_ids.append(powerup_id)
	for powerup_id in existing_ids:
		if active_ids.has(powerup_id):
			continue
		_powerup_nodes[powerup_id].queue_free()
		_powerup_nodes.erase(powerup_id)


func _update_powerup_visuals(delta: float) -> void:
	for powerup_node in _powerup_nodes.values():
		powerup_node.rotate_y(POWERUP_Y_ROTATION_SPEED * delta)


func _create_powerup_node(powerup_type: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Powerup_%s" % powerup_type
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	match powerup_type:
		"invisible":
			mesh_instance.mesh = SphereMesh.new()
			material.albedo_color = Color(0.45, 0.85, 1.0, 0.9)
		"speed":
			mesh_instance.mesh = CapsuleMesh.new()
			material.albedo_color = Color(1.0, 0.8, 0.2, 1.0)
		_:
			mesh_instance.mesh = BoxMesh.new()
			material.albedo_color = Color(0.8, 0.35, 1.0, 1.0)
	mesh_instance.position.y = 0.6
	mesh_instance.scale = Vector3.ONE * 0.6
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.75
	mesh_instance.material_override = material
	root.add_child(mesh_instance)
	return root


func _spawn_position_for_index(i: int) -> Vector3:
	var col: int = i % SPAWN_ROW_WIDTH
	var row: int = i / SPAWN_ROW_WIDTH
	var x: float = (float(col) - 1.5) * SPAWN_SPACING
	var z: float = (float(row) - 1.5) * SPAWN_SPACING
	return Vector3(x, 1.0, z)
