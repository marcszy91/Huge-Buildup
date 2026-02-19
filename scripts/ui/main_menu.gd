extends Control

@onready var _status_label: Label = %StatusLabel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_edit: LineEdit = %HostEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _max_players_edit: LineEdit = %MaxPlayersEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _quit_button: Button = %QuitButton

func _ready() -> void:
    _name_edit.text = Settings.display_name
    _host_edit.text = "127.0.0.1"
    _port_edit.text = str(Net.DEFAULT_PORT)
    _max_players_edit.text = str(Net.DEFAULT_MAX_PLAYERS)

    _host_button.pressed.connect(_on_host_pressed)
    _join_button.pressed.connect(_on_join_pressed)
    _quit_button.pressed.connect(_on_quit_pressed)

    Net.error.connect(_on_net_error)
    Net.connection_state_changed.connect(_on_connection_state_changed)
    _status_label.text = "Ready."

func _on_host_pressed() -> void:
    Settings.set_display_name(_name_edit.text)
    var port: int = _parse_positive_int(_port_edit.text, Net.DEFAULT_PORT)
    var max_players: int = _parse_positive_int(_max_players_edit.text, Net.DEFAULT_MAX_PLAYERS)

    _status_label.text = "Hosting on port %d..." % port
    App.request_host(port, max_players)

func _on_join_pressed() -> void:
    Settings.set_display_name(_name_edit.text)
    var host_ip: String = _host_edit.text.strip_edges()
    var port: int = _parse_positive_int(_port_edit.text, Net.DEFAULT_PORT)
    if host_ip.is_empty():
        _status_label.text = "Host is required."
        return

    _status_label.text = "Connecting to %s:%d..." % [host_ip, port]
    App.request_join(host_ip, port)

func _on_quit_pressed() -> void:
    get_tree().quit()

func _on_net_error(message: String) -> void:
    _status_label.text = message

func _on_connection_state_changed(state: int) -> void:
    if state == Net.ConnectionState.DISCONNECTED:
        return
    if state == Net.ConnectionState.HOSTING:
        _status_label.text = "Hosting session."
        return
    if state == Net.ConnectionState.CONNECTING:
        _status_label.text = "Connecting..."
        return
    if state == Net.ConnectionState.CONNECTED_CLIENT:
        _status_label.text = "Connected."
        return

func _parse_positive_int(raw: String, fallback: int) -> int:
    if not raw.is_valid_int():
        return fallback
    var value: int = int(raw)
    if value <= 0:
        return fallback
    return value
