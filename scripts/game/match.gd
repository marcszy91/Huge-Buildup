extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")
const TRANSFORM_SEND_INTERVAL_S: float = 1.0 / 15.0
const CATCH_ATTEMPT_COOLDOWN_S: float = 0.15
const POWERUP_COLLECT_COOLDOWN_S: float = 0.15
const SPAWN_ROW_WIDTH: int = 4
const SPAWN_SPACING: float = 4.0
const POWERUP_Y_ROTATION_SPEED: float = 2.2
const POWERUP_BOB_HEIGHT: float = 0.12
const POWERUP_BOB_SPEED: float = 2.6
const NAMETAG_DEFAULT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const NAMETAG_CATCHER_COLOR: Color = Color(0.95, 0.24, 0.24, 1.0)
const NAMETAG_FALLBACK_HEIGHT_M: float = 2.35
const NAMETAG_HEADROOM_M: float = 0.16
const NAMETAG_MIN_HEIGHT_M: float = 2.15
const NAMETAG_MAX_HEIGHT_M: float = 3.20

var _spawned_players: Dictionary[int, CharacterBody3D] = {}
var _player_display_names: Dictionary[int, String] = {}
var _player_name_labels: Dictionary[int, Label3D] = {}
var _powerup_nodes: Dictionary[int, Node3D] = {}
var _powerup_textures: Dictionary[String, Texture2D] = {}
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
	_build_powerup_textures()
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
	_ensure_local_peer_binding()
	_enforce_local_camera_owner()
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


func _ensure_local_peer_binding() -> void:
	var current_peer_id: int = Net.my_peer_id()
	if current_peer_id <= 0:
		return
	if current_peer_id == _local_peer_id:
		return
	_rebind_local_peer(current_peer_id)


func _rebind_local_peer(next_local_peer_id: int) -> void:
	var previous_local_peer_id: int = _local_peer_id
	_local_peer_id = next_local_peer_id

	for peer_id in _spawned_players.keys():
		var player: CharacterBody3D = _spawned_players[peer_id]
		if player.has_method("set_local_controlled"):
			player.call("set_local_controlled", peer_id == _local_peer_id)

	if _spawned_players.has(previous_local_peer_id):
		_attach_name_label(previous_local_peer_id, _spawned_players[previous_local_peer_id])
	if _player_name_labels.has(_local_peer_id):
		_player_name_labels[_local_peer_id].queue_free()
		_player_name_labels.erase(_local_peer_id)

	_enforce_local_camera_owner()
	_refresh_role_visuals()


func _spawn_match_players() -> void:
	_spawned_players.clear()
	_player_display_names.clear()
	_player_name_labels.clear()

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
		_player_display_names[peer_id] = str(players_snapshot[i].get("display_name", "Player"))

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
		_attach_name_label(peer_id, player)

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
		_refresh_name_label_color(peer_id, local_is_catcher)
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
		if _player_name_labels.has(peer_id):
			_player_name_labels[peer_id].visible = not is_hidden_from_local_view


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
		var base_y: float = float(powerup_node.get_meta("base_y", powerup_node.position.y))
		var bob_phase: float = float(powerup_node.get_meta("bob_phase", 0.0))
		powerup_node.position.y = base_y + sin(Time.get_ticks_msec() / 1000.0 * POWERUP_BOB_SPEED + bob_phase) * POWERUP_BOB_HEIGHT


func _create_powerup_node(powerup_type: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Powerup_%s" % powerup_type
	root.position.y = 0.18
	root.set_meta("base_y", root.position.y)
	root.set_meta("bob_phase", randf() * TAU)
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.0085
	sprite.texture = _powerup_textures.get(powerup_type, _powerup_textures.get("teleport"))
	sprite.position.y = 1.05
	root.add_child(sprite)
	return root


func _build_powerup_textures() -> void:
	_powerup_textures = {
		"invisible": _make_invisible_powerup_texture(),
		"speed": _make_speed_powerup_texture(),
		"teleport": _make_teleport_powerup_texture(),
	}


func _make_invisible_powerup_texture() -> Texture2D:
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.06, 0.09, 0.16, 0.0))
	_draw_rounded_rect(image, Rect2i(8, 8, 112, 112), 18, Color(0.06, 0.09, 0.16, 0.95))
	_draw_ring(image, Vector2i(64, 64), 34, 6, Color(0.40, 0.92, 0.98, 1.0))
	_draw_filled_circle(image, Vector2i(64, 64), 8, Color(0.40, 0.92, 0.98, 1.0))
	_draw_line(image, Vector2i(28, 96), Vector2i(100, 32), 5, Color(0.93, 0.96, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


func _make_speed_powerup_texture() -> Texture2D:
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.16, 0.22, 0.0))
	_draw_rounded_rect(image, Rect2i(8, 8, 112, 112), 18, Color(0.12, 0.16, 0.22, 0.95))
	var bolt: PackedVector2Array = PackedVector2Array(
		[
			Vector2(74, 18),
			Vector2(40, 68),
			Vector2(60, 68),
			Vector2(50, 110),
			Vector2(92, 54),
			Vector2(68, 54),
		]
	)
	_fill_polygon(image, bolt, Color(1.0, 0.78, 0.16, 1.0))
	_draw_line(image, Vector2i(18, 48), Vector2i(42, 48), 5, Color(1.0, 0.92, 0.60, 1.0))
	_draw_line(image, Vector2i(14, 66), Vector2i(34, 66), 5, Color(1.0, 0.92, 0.60, 1.0))
	_draw_line(image, Vector2i(86, 88), Vector2i(110, 88), 5, Color(1.0, 0.92, 0.60, 1.0))
	return ImageTexture.create_from_image(image)


func _make_teleport_powerup_texture() -> Texture2D:
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.10, 0.30, 0.0))
	_draw_rounded_rect(image, Rect2i(8, 8, 112, 112), 18, Color(0.12, 0.10, 0.30, 0.95))
	_draw_ring(image, Vector2i(64, 64), 32, 6, Color(0.78, 0.55, 0.98, 1.0))
	_draw_ring(image, Vector2i(64, 64), 16, 6, Color(0.92, 0.84, 1.0, 1.0))
	_draw_line(image, Vector2i(64, 18), Vector2i(64, 8), 5, Color(0.78, 0.55, 0.98, 1.0))
	_draw_line(image, Vector2i(64, 120), Vector2i(64, 110), 5, Color(0.78, 0.55, 0.98, 1.0))
	_draw_line(image, Vector2i(18, 64), Vector2i(8, 64), 5, Color(0.78, 0.55, 0.98, 1.0))
	_draw_line(image, Vector2i(120, 64), Vector2i(110, 64), 5, Color(0.78, 0.55, 0.98, 1.0))
	return ImageTexture.create_from_image(image)


func _draw_rounded_rect(image: Image, rect: Rect2i, radius: int, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var dx: int = mini(x - rect.position.x, rect.end.x - 1 - x)
			var dy: int = mini(y - rect.position.y, rect.end.y - 1 - y)
			if dx >= radius or dy >= radius:
				image.set_pixel(x, y, color)
				continue
			var corner_dx: int = radius - dx
			var corner_dy: int = radius - dy
			if corner_dx * corner_dx + corner_dy * corner_dy <= radius * radius:
				image.set_pixel(x, y, color)


func _draw_filled_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var dx: int = x - center.x
			var dy: int = y - center.y
			if dx * dx + dy * dy <= radius * radius:
				image.set_pixel(x, y, color)


func _draw_ring(image: Image, center: Vector2i, radius: int, thickness: int, color: Color) -> void:
	var inner_radius: int = max(0, radius - thickness)
	var outer_sq: int = radius * radius
	var inner_sq: int = inner_radius * inner_radius
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var dx: int = x - center.x
			var dy: int = y - center.y
			var dist_sq: int = dx * dx + dy * dy
			if dist_sq <= outer_sq and dist_sq >= inner_sq:
				image.set_pixel(x, y, color)


func _draw_line(
	image: Image, start: Vector2i, end: Vector2i, thickness: int, color: Color
) -> void:
	var from: Vector2 = Vector2(start)
	var to: Vector2 = Vector2(end)
	var delta: Vector2 = to - from
	var steps: int = int(max(abs(delta.x), abs(delta.y)))
	if steps <= 0:
		_draw_filled_circle(image, start, max(1, thickness / 2), color)
		return
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var point: Vector2 = from.lerp(to, t)
		_draw_filled_circle(image, Vector2i(roundi(point.x), roundi(point.y)), max(1, thickness / 2), color)


func _fill_polygon(image: Image, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var min_x: int = maxi(0, floori(points[0].x))
	var max_x: int = mini(image.get_width() - 1, ceili(points[0].x))
	var min_y: int = maxi(0, floori(points[0].y))
	var max_y: int = mini(image.get_height() - 1, ceili(points[0].y))
	for point in points:
		min_x = maxi(0, mini(min_x, floori(point.x)))
		max_x = mini(image.get_width() - 1, maxi(max_x, ceili(point.x)))
		min_y = maxi(0, mini(min_y, floori(point.y)))
		max_y = mini(image.get_height() - 1, maxi(max_y, ceili(point.y)))

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), points):
				image.set_pixel(x, y, color)


func _spawn_position_for_index(i: int) -> Vector3:
	var col: int = i % SPAWN_ROW_WIDTH
	var row: int = i / SPAWN_ROW_WIDTH
	var x: float = (float(col) - 1.5) * SPAWN_SPACING
	var z: float = (float(row) - 1.5) * SPAWN_SPACING
	return Vector3(x, 1.0, z)


func _enforce_local_camera_owner() -> void:
	for peer_id in _spawned_players.keys():
		var player: CharacterBody3D = _spawned_players[peer_id]
		if player.has_method("set_camera_active"):
			player.call("set_camera_active", peer_id == _local_peer_id)


func _attach_name_label(peer_id: int, player: CharacterBody3D) -> void:
	if peer_id == _local_peer_id:
		return
	var label: Label3D = Label3D.new()
	label.name = "NameLabel"
	label.position = Vector3(0.0, _compute_name_label_height(player), 0.0)
	label.text = _player_display_names.get(peer_id, "Player")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = NAMETAG_DEFAULT_COLOR
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	label.font_size = 58
	label.pixel_size = 0.0028
	label.uppercase = false
	player.add_child(label)
	_player_name_labels[peer_id] = label


func _compute_name_label_height(player: CharacterBody3D) -> float:
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(player, mesh_instances)
	var player_to_local: Transform3D = player.global_transform.affine_inverse()
	var max_top_y: float = -INF
	for mesh_instance in mesh_instances:
		var aabb: AABB = mesh_instance.get_aabb()
		if aabb.size.length_squared() <= 0.000001:
			continue
		var mesh_to_player_local: Transform3D = player_to_local * mesh_instance.global_transform
		var top_y: float = _get_aabb_top_y(aabb, mesh_to_player_local)
		if top_y > max_top_y:
			max_top_y = top_y
	if not is_finite(max_top_y):
		return NAMETAG_FALLBACK_HEIGHT_M
	var desired_height: float = max_top_y + NAMETAG_HEADROOM_M
	return clampf(desired_height, NAMETAG_MIN_HEIGHT_M, NAMETAG_MAX_HEIGHT_M)


func _collect_mesh_instances(root: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		out_meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_mesh_instances(child, out_meshes)


func _get_aabb_top_y(aabb: AABB, transform_local: Transform3D) -> float:
	var max_y: float = -INF
	for corner in _get_aabb_corners(aabb):
		var transformed: Vector3 = transform_local * corner
		if transformed.y > max_y:
			max_y = transformed.y
	return max_y


func _get_aabb_corners(aabb: AABB) -> PackedVector3Array:
	var min_corner: Vector3 = aabb.position
	var max_corner: Vector3 = aabb.position + aabb.size
	return PackedVector3Array(
		[
			Vector3(min_corner.x, min_corner.y, min_corner.z),
			Vector3(min_corner.x, min_corner.y, max_corner.z),
			Vector3(min_corner.x, max_corner.y, min_corner.z),
			Vector3(min_corner.x, max_corner.y, max_corner.z),
			Vector3(max_corner.x, min_corner.y, min_corner.z),
			Vector3(max_corner.x, min_corner.y, max_corner.z),
			Vector3(max_corner.x, max_corner.y, min_corner.z),
			Vector3(max_corner.x, max_corner.y, max_corner.z),
		]
	)


func _refresh_name_label_color(peer_id: int, local_is_catcher: bool) -> void:
	if not _player_name_labels.has(peer_id):
		return
	var label: Label3D = _player_name_labels[peer_id]
	var color: Color = NAMETAG_DEFAULT_COLOR
	if local_is_catcher and Game.is_catcher(peer_id):
		color = NAMETAG_CATCHER_COLOR
	label.modulate = color
