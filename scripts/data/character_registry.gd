class_name CharacterRegistry
extends RefCounted

const DEFAULT_CHARACTER_ID: String = "chef_female"
const CHARACTER_SCENE_ROOT: String = "res://assets/quaternius/ultimate_animated_characters/glTF/"
const CHARACTER_BASENAMES: PackedStringArray = [
	"BlueSoldier_Female",
	"BlueSoldier_Male",
	"Casual_Bald",
	"Casual_Female",
	"Casual_Male",
	"Casual2_Female",
	"Casual2_Male",
	"Casual3_Female",
	"Casual3_Male",
	"Chef_Female",
	"Chef_Male",
	"Cow",
	"Cowboy_Female",
	"Cowboy_Male",
	"Doctor_Female_Old",
	"Doctor_Female_Young",
	"Doctor_Male_Old",
	"Doctor_Male_Young",
	"Elf",
	"Goblin_Female",
	"Goblin_Male",
	"Kimono_Female",
	"Kimono_Male",
	"Knight_Golden_Female",
	"Knight_Golden_Male",
	"Knight_Male",
	"Ninja_Female",
	"Ninja_Male",
	"Ninja_Male_Hair",
	"Ninja_Sand",
	"Ninja_Sand_Female",
	"OldClassy_Female",
	"OldClassy_Male",
	"Pirate_Female",
	"Pirate_Male",
	"Pug",
	"Soldier_Female",
	"Soldier_Male",
	"Suit_Female",
	"Suit_Male",
	"Viking_Female",
	"Viking_Male",
	"Witch",
	"Wizard",
	"Worker_Female",
	"Worker_Male",
	"Zombie_Female",
	"Zombie_Male",
]

static var _entries_cache: Array[Dictionary] = []
static var _scene_cache: Dictionary[String, PackedScene] = {}


static func get_entries() -> Array[Dictionary]:
	if _entries_cache.is_empty():
		for basename in CHARACTER_BASENAMES:
			var entry: Dictionary = {
				"id": _basename_to_id(basename),
				"name": _basename_to_display_name(basename),
				"basename": basename,
				"path": "%s%s.gltf" % [CHARACTER_SCENE_ROOT, basename],
			}
			_entries_cache.append(entry)
	var out: Array[Dictionary] = []
	for entry in _entries_cache:
		out.append(entry.duplicate(true))
	return out


static func get_default_id() -> String:
	return DEFAULT_CHARACTER_ID


static func sanitize_id(raw_character_id: String) -> String:
	var clean_id: String = raw_character_id.strip_edges().to_lower()
	if clean_id.is_empty():
		return DEFAULT_CHARACTER_ID
	for entry in get_entries():
		if str(entry.get("id", "")) == clean_id:
			return clean_id
	return DEFAULT_CHARACTER_ID


static func get_display_name(character_id: String) -> String:
	var clean_id: String = sanitize_id(character_id)
	for entry in get_entries():
		if str(entry.get("id", "")) == clean_id:
			return str(entry.get("name", "Character"))
	return "Character"


static func load_scene(character_id: String) -> PackedScene:
	var clean_id: String = sanitize_id(character_id)
	if _scene_cache.has(clean_id):
		return _scene_cache[clean_id]
	for entry in get_entries():
		if str(entry.get("id", "")) != clean_id:
			continue
		var scene: PackedScene = load(str(entry.get("path", ""))) as PackedScene
		if scene != null:
			_scene_cache[clean_id] = scene
		return scene
	return null


static func _basename_to_id(basename: String) -> String:
	return basename.to_lower()


static func _basename_to_display_name(basename: String) -> String:
	var words: PackedStringArray = basename.split("_")
	var pretty_words: PackedStringArray = []
	for word in words:
		pretty_words.append(word.capitalize())
	return " ".join(pretty_words)
