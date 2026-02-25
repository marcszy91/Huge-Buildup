extends Control

@onready var _summary_label: Label = %SummaryLabel
@onready var _results_list: ItemList = %ResultsList
@onready var _back_to_lobby_button: Button = %BackToLobbyButton
@onready var _main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	_back_to_lobby_button.pressed.connect(_on_back_to_lobby_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	Game.results_changed.connect(_refresh_results)
	_refresh_results()


func _refresh_results() -> void:
	_results_list.clear()

	var results: Array[Dictionary] = Game.last_results
	if results.is_empty():
		_summary_label.text = "No results available."
		return

	var winners: Array[String] = []
	for row in results:
		if bool(row.get("is_winner", false)):
			winners.append(str(row.get("display_name", "Player")))

	if winners.is_empty():
		_summary_label.text = "Match Results"
	elif winners.size() == 1:
		_summary_label.text = "Winner: %s" % winners[0]
	else:
		_summary_label.text = "Winners: %s" % _format_names(winners)

	for row in results:
		var rank: int = int(row.get("rank", 0))
		var name: String = str(row.get("display_name", "Player"))
		var peer_id: int = int(row.get("peer_id", 0))
		var times_caught: int = int(row.get("times_caught", 0))
		var winner_marker: String = ""
		if bool(row.get("is_winner", false)):
			winner_marker = " [WIN]"
		_results_list.add_item(
			"#%d  %s (%d)  caught: %d%s" % [rank, name, peer_id, times_caught, winner_marker]
		)


func _on_back_to_lobby_pressed() -> void:
	App.goto_lobby()


func _on_main_menu_pressed() -> void:
	App.request_leave_network()


func _format_names(names: Array[String]) -> String:
	var out: String = ""
	for i in range(names.size()):
		if i > 0:
			out += ", "
		out += names[i]
	return out
