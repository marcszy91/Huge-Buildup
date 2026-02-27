extends Node

signal settings_changed

const SETTINGS_PATH: String = "user://settings.cfg"

var display_name: String = "Player"
var mouse_sensitivity: float = 0.25
var character_id: String = "chef_female"


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_PATH)
	if err != OK:
		return

	display_name = str(config.get_value("player", "display_name", display_name))
	mouse_sensitivity = float(config.get_value("player", "mouse_sensitivity", mouse_sensitivity))
	character_id = _sanitize_character_id(
		str(config.get_value("player", "character_id", character_id))
	)
	settings_changed.emit()


func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("player", "display_name", display_name)
	config.set_value("player", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("player", "character_id", character_id)
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


func set_character_id(next_character_id: String) -> void:
	character_id = _sanitize_character_id(next_character_id)
	save_settings()
	settings_changed.emit()


func _sanitize_character_id(raw_character_id: String) -> String:
	var clean_id: String = raw_character_id.strip_edges().to_lower()
	if clean_id.is_empty():
		return "chef_female"
	match clean_id:
		"chef_female", "casual_male":
			return clean_id
		_:
			return "chef_female"
