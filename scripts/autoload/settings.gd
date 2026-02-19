extends Node

signal settings_changed()

const SETTINGS_PATH: String = "user://settings.cfg"

var display_name: String = "Player"
var mouse_sensitivity: float = 0.25

func _ready() -> void:
    load_settings()

func load_settings() -> void:
    var config: ConfigFile = ConfigFile.new()
    var err: int = config.load(SETTINGS_PATH)
    if err != OK:
        return

    display_name = str(config.get_value("player", "display_name", display_name))
    mouse_sensitivity = float(config.get_value("player", "mouse_sensitivity", mouse_sensitivity))
    settings_changed.emit()

func save_settings() -> void:
    var config: ConfigFile = ConfigFile.new()
    config.set_value("player", "display_name", display_name)
    config.set_value("player", "mouse_sensitivity", mouse_sensitivity)
    config.save(SETTINGS_PATH)

func set_display_name(next_name: String) -> void:
    display_name = next_name.strip_edges()
    if display_name.is_empty():
        display_name = "Player"
    save_settings()
    settings_changed.emit()

func set_mouse_sensitivity(next_value: float) -> void:
    mouse_sensitivity = clampf(next_value, 0.01, 2.0)
    save_settings()
    settings_changed.emit()
