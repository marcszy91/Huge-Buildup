extends Node

signal player_list_changed
signal lobby_config_changed
signal match_state_changed
signal score_changed
signal timer_changed(time_remaining_s: int)
signal it_changed(it_peer_id: int)
signal results_changed
signal catchers_changed
signal freeze_state_changed(peer_id: int)

const PROTOCOL_VERSION: int = 1

var max_players: int = 16
var match_duration_s: int = 180
var port: int = 24567
var tag_radius_m: float = 1.2
var arena_id: String = "default"
var catcher_count: int = 1

var players: Dictionary[int, Dictionary] = {}
var stats: Dictionary[int, Dictionary] = {}
var it_peer_id: int = 0
var catcher_peer_ids: Array[int] = []
var match_start_unix_ms: int = 0
var time_remaining_s: int = 0
var is_running: bool = false
var last_results: Array[Dictionary] = []
var catch_freeze_until_unix_ms: Dictionary[int, int] = {}


func reset_lobby() -> void:
	players.clear()
	stats.clear()
	it_peer_id = 0
	catcher_peer_ids.clear()
	is_running = false
	match_start_unix_ms = 0
	time_remaining_s = 0
	last_results.clear()
	catch_freeze_until_unix_ms.clear()
	player_list_changed.emit()
	score_changed.emit()
	match_state_changed.emit()
	timer_changed.emit(time_remaining_s)
	it_changed.emit(it_peer_id)
	results_changed.emit()
	catchers_changed.emit()


func set_config(
	next_max_players: int,
	next_duration_s: int,
	next_port: int,
	next_tag_radius_m: float,
	next_arena_id: String,
	next_catcher_count: int = 1
) -> void:
	max_players = next_max_players
	match_duration_s = next_duration_s
	port = next_port
	tag_radius_m = next_tag_radius_m
	arena_id = next_arena_id
	catcher_count = maxi(1, next_catcher_count)
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
	if config.has("catcher_count"):
		catcher_count = maxi(1, int(config.get("catcher_count", catcher_count)))

	players.clear()
	var synced_stats: Dictionary[int, Dictionary] = {}
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
		var existing_stats: Dictionary = stats.get(peer_id, {})
		synced_stats[peer_id] = {
			"times_caught": int(existing_stats.get("times_caught", 0)),
		}

	stats = synced_stats

	player_list_changed.emit()
	lobby_config_changed.emit()
	score_changed.emit()


func make_players_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array[int] = []
	for peer_id in players.keys():
		ids.append(peer_id)
	ids.sort_custom(
		func(a: int, b: int) -> bool:
			var join_a: int = int(players[a].get("join_index", 0))
			var join_b: int = int(players[b].get("join_index", 0))
			return join_a < join_b
	)

	for peer_id in ids:
		var player: Dictionary = players[peer_id]
		(
			out
			. append(
				{
					"peer_id": peer_id,
					"display_name": str(player.get("display_name", "Player")),
					"is_ready": bool(player.get("is_ready", false)),
					"join_index": int(player.get("join_index", 0)),
				}
			)
		)
	return out


func make_config_snapshot() -> Dictionary:
	return {
		"max_players": max_players,
		"match_duration_s": match_duration_s,
		"port": port,
		"tag_radius_m": tag_radius_m,
		"arena_id": arena_id,
		"catcher_count": catcher_count,
	}


func set_time_remaining(seconds: int) -> void:
	time_remaining_s = max(0, seconds)
	timer_changed.emit(time_remaining_s)


func set_it_peer_id(peer_id: int) -> void:
	it_peer_id = peer_id
	it_changed.emit(it_peer_id)


func set_catchers(next_catcher_peer_ids: Array[int]) -> void:
	var cleaned: Array[int] = []
	for raw_peer_id in next_catcher_peer_ids:
		var peer_id: int = int(raw_peer_id)
		if peer_id <= 0:
			continue
		if not players.has(peer_id):
			continue
		if cleaned.has(peer_id):
			continue
		cleaned.append(peer_id)
	catcher_peer_ids = cleaned
	if catcher_peer_ids.is_empty():
		set_it_peer_id(0)
	else:
		set_it_peer_id(catcher_peer_ids[0])
	catchers_changed.emit()


func get_catcher_peer_ids() -> Array[int]:
	return catcher_peer_ids.duplicate()


func is_catcher(peer_id: int) -> bool:
	return catcher_peer_ids.has(peer_id)


func get_effective_catcher_count(player_count: int) -> int:
	if player_count <= 1:
		return 0
	return mini(maxi(1, catcher_count), player_count - 1)


func rebalance_catchers() -> void:
	var player_ids: Array[int] = _get_sorted_player_ids()
	var target_count: int = get_effective_catcher_count(player_ids.size())
	if target_count <= 0:
		set_catchers([])
		return

	var next_catchers: Array[int] = []
	for peer_id in catcher_peer_ids:
		if player_ids.has(peer_id) and not next_catchers.has(peer_id):
			next_catchers.append(peer_id)
			if next_catchers.size() >= target_count:
				break

	if next_catchers.size() < target_count:
		for peer_id in player_ids:
			if next_catchers.has(peer_id):
				continue
			next_catchers.append(peer_id)
			if next_catchers.size() >= target_count:
				break

	set_catchers(next_catchers)


func begin_match(
	start_unix_ms: int, initial_it_peer_id: int, initial_catcher_peer_ids: Array[int] = []
) -> void:
	is_running = true
	match_start_unix_ms = start_unix_ms
	last_results.clear()
	catch_freeze_until_unix_ms.clear()
	for peer_id in players.keys():
		stats[peer_id] = {"times_caught": 0}
	if initial_catcher_peer_ids.is_empty():
		if initial_it_peer_id > 0:
			set_catchers([initial_it_peer_id])
		else:
			set_catchers([])
	else:
		set_catchers(initial_catcher_peer_ids)
	set_time_remaining(match_duration_s)
	score_changed.emit()
	results_changed.emit()
	match_state_changed.emit()


func end_match() -> void:
	is_running = false
	match_state_changed.emit()


func build_results_snapshot() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var player_ids: Array[int] = []
	for peer_id in players.keys():
		player_ids.append(peer_id)

	player_ids.sort_custom(
		func(a: int, b: int) -> bool:
			var caught_a: int = int(stats.get(a, {}).get("times_caught", 0))
			var caught_b: int = int(stats.get(b, {}).get("times_caught", 0))
			if caught_a != caught_b:
				return caught_a < caught_b
			var join_a: int = int(players.get(a, {}).get("join_index", 0))
			var join_b: int = int(players.get(b, {}).get("join_index", 0))
			return join_a < join_b
	)

	var current_rank: int = 0
	var last_times_caught: int = -1
	for i in range(player_ids.size()):
		var peer_id: int = player_ids[i]
		var player: Dictionary = players.get(peer_id, {})
		var times_caught: int = int(stats.get(peer_id, {}).get("times_caught", 0))
		if i == 0 or times_caught != last_times_caught:
			current_rank = i + 1
			last_times_caught = times_caught

		(
			rows
			. append(
				{
					"peer_id": peer_id,
					"display_name": str(player.get("display_name", "Player")),
					"times_caught": times_caught,
					"rank": current_rank,
					"is_winner": current_rank == 1,
				}
			)
		)

	return rows


func apply_match_end(results: Array[Dictionary]) -> void:
	last_results = results.duplicate(true)
	for row in results:
		var peer_id: int = int(row.get("peer_id", 0))
		if peer_id <= 0:
			continue
		stats[peer_id] = {
			"times_caught": int(row.get("times_caught", 0)),
		}
	set_time_remaining(0)
	score_changed.emit()
	end_match()
	results_changed.emit()


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
	if catcher_peer_ids.has(peer_id):
		var next_catchers: Array[int] = catcher_peer_ids.duplicate()
		next_catchers.erase(peer_id)
		set_catchers(next_catchers)
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


func set_times_caught(peer_id: int, times_caught: int) -> void:
	if not stats.has(peer_id):
		stats[peer_id] = {"times_caught": 0}
	stats[peer_id]["times_caught"] = max(0, times_caught)
	score_changed.emit()


func get_times_caught(peer_id: int) -> int:
	return int(stats.get(peer_id, {}).get("times_caught", 0))


func apply_catch_swap(catcher_peer_id: int, victim_peer_id: int, victim_times_caught: int) -> void:
	set_times_caught(victim_peer_id, victim_times_caught)

	var next_catchers: Array[int] = catcher_peer_ids.duplicate()
	var catcher_index: int = next_catchers.find(catcher_peer_id)
	if catcher_index < 0:
		return

	if next_catchers.has(victim_peer_id):
		return

	next_catchers[catcher_index] = victim_peer_id
	set_catchers(next_catchers)


func set_catch_freeze_until(peer_id: int, freeze_until_unix_ms: int) -> void:
	if peer_id <= 0:
		return
	if freeze_until_unix_ms <= 0:
		catch_freeze_until_unix_ms.erase(peer_id)
		freeze_state_changed.emit(peer_id)
		return
	catch_freeze_until_unix_ms[peer_id] = freeze_until_unix_ms
	freeze_state_changed.emit(peer_id)


func clear_catch_freeze(peer_id: int) -> void:
	if catch_freeze_until_unix_ms.erase(peer_id):
		freeze_state_changed.emit(peer_id)


func is_peer_catch_frozen(peer_id: int) -> bool:
	if peer_id <= 0:
		return false
	if not catch_freeze_until_unix_ms.has(peer_id):
		return false
	var freeze_until_unix_ms: int = int(catch_freeze_until_unix_ms[peer_id])
	var now_unix_ms: int = int(Time.get_unix_time_from_system() * 1000)
	if now_unix_ms >= freeze_until_unix_ms:
		catch_freeze_until_unix_ms.erase(peer_id)
		freeze_state_changed.emit(peer_id)
		return false
	return true


func get_peer_freeze_remaining_ms(peer_id: int) -> int:
	if peer_id <= 0:
		return 0
	if not catch_freeze_until_unix_ms.has(peer_id):
		return 0
	var freeze_until_unix_ms: int = int(catch_freeze_until_unix_ms[peer_id])
	var now_unix_ms: int = int(Time.get_unix_time_from_system() * 1000)
	return maxi(0, freeze_until_unix_ms - now_unix_ms)


func _get_sorted_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for peer_id in players.keys():
		ids.append(peer_id)
	ids.sort_custom(
		func(a: int, b: int) -> bool:
			var join_a: int = int(players[a].get("join_index", 0))
			var join_b: int = int(players[b].get("join_index", 0))
			return join_a < join_b
	)
	return ids
