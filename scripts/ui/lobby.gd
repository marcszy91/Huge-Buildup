extends Control

var _local_ready: bool = false

@onready var _session_label: Label = %SessionLabel
@onready var _players_list: ItemList = %PlayersList
@onready var _note_label: Label = %NoteLabel
@onready var _leave_button: Button = %LeaveButton
@onready var _start_match_button: Button = %StartMatchButton
@onready var _ready_button: Button = %ReadyButton

func _ready() -> void:
    _leave_button.pressed.connect(_on_leave_pressed)
    _start_match_button.pressed.connect(_on_start_match_pressed)
    _ready_button.pressed.connect(_on_ready_pressed)

    Game.player_list_changed.connect(_refresh_players)
    Net.connection_state_changed.connect(_refresh_session)
    Net.peer_connected.connect(_on_peer_connected)
    Net.peer_disconnected.connect(_on_peer_disconnected)

    _refresh_session(Net.connection_state)
    _refresh_players()

func _on_leave_pressed() -> void:
    App.request_leave_network()

func _on_start_match_pressed() -> void:
    if not Net.is_host():
        _note_label.text = "Only host can start match."
        return
    _note_label.text = "Starting match..."
    Net.request_start_match()

func _on_ready_pressed() -> void:
    _local_ready = not _local_ready
    Net.request_set_ready(_local_ready)
    _refresh_ready_button()

func _refresh_session(_state: int) -> void:
    if Net.is_host():
        _session_label.text = "Lobby: Host (%d)" % Net.my_peer_id()
        _start_match_button.disabled = false
    else:
        _session_label.text = "Lobby: Client (%d)" % Net.my_peer_id()
        _start_match_button.disabled = true

func _refresh_players() -> void:
    _players_list.clear()

    var ids: Array[int] = []
    for peer_id in Game.players.keys():
        ids.append(peer_id)
    ids.sort_custom(func(a: int, b: int) -> bool:
        var join_a: int = int(Game.players[a].get("join_index", 0))
        var join_b: int = int(Game.players[b].get("join_index", 0))
        return join_a < join_b
    )

    for peer_id in ids:
        var player: Dictionary = Game.players[peer_id]
        var name: String = str(player.get("display_name", "Player"))
        var ready_text: String = "not ready"
        if bool(player.get("is_ready", false)):
            ready_text = "ready"
        _players_list.add_item("%s (%d) - %s" % [name, peer_id, ready_text])

    var my_id: int = Net.my_peer_id()
    if Game.players.has(my_id):
        _local_ready = bool(Game.players[my_id].get("is_ready", false))
    _refresh_ready_button()

func _on_peer_connected(peer_id: int) -> void:
    _note_label.text = "Peer connected: %d" % peer_id

func _on_peer_disconnected(peer_id: int) -> void:
    _note_label.text = "Peer disconnected: %d" % peer_id

func _refresh_ready_button() -> void:
    if _local_ready:
        _ready_button.text = "Set Not Ready"
    else:
        _ready_button.text = "Set Ready"
