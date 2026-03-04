extends CanvasLayer

@onready var _title_label: Label = %TitleLabel
@onready var _role_label: Label = %RoleLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _effects_label: Label = %EffectsLabel


func _ready() -> void:
	Game.catchers_changed.connect(_refresh_role)
	Game.freeze_state_changed.connect(_on_freeze_state_changed)
	Game.match_state_changed.connect(_refresh_role)
	Game.timer_changed.connect(_on_timer_changed)
	Game.score_changed.connect(_refresh_score)
	Game.powerup_effect_changed.connect(_on_powerup_effect_changed)
	_refresh_role()
	_refresh_timer()
	_refresh_score()
	_refresh_effects()


func _exit_tree() -> void:
	if Game.catchers_changed.is_connected(_refresh_role):
		Game.catchers_changed.disconnect(_refresh_role)
	if Game.freeze_state_changed.is_connected(_on_freeze_state_changed):
		Game.freeze_state_changed.disconnect(_on_freeze_state_changed)
	if Game.match_state_changed.is_connected(_refresh_role):
		Game.match_state_changed.disconnect(_refresh_role)
	if Game.timer_changed.is_connected(_on_timer_changed):
		Game.timer_changed.disconnect(_on_timer_changed)
	if Game.score_changed.is_connected(_refresh_score):
		Game.score_changed.disconnect(_refresh_score)
	if Game.powerup_effect_changed.is_connected(_on_powerup_effect_changed):
		Game.powerup_effect_changed.disconnect(_on_powerup_effect_changed)


func _process(_delta: float) -> void:
	if not Game.is_running:
		return
	var my_peer_id: int = Net.my_peer_id()
	if my_peer_id <= 0:
		return
	if Game.get_peer_freeze_remaining_ms(my_peer_id) > 0:
		_refresh_role()
	if Game.is_running:
		_refresh_timer()
		_refresh_effects()


func _refresh_role() -> void:
	_title_label.text = "HUD"
	var my_peer_id: int = Net.my_peer_id()
	if my_peer_id <= 0:
		_role_label.text = "Role: Unknown"
		return

	var role_text: String = "Runner"
	if Game.is_catcher(my_peer_id):
		role_text = "Catcher"

	var freeze_remaining_ms: int = Game.get_peer_freeze_remaining_ms(my_peer_id)
	if freeze_remaining_ms > 0:
		var remaining_s: float = ceilf(float(freeze_remaining_ms) / 100.0) / 10.0
		role_text += " (Frozen %.1fs)" % remaining_s

	_role_label.text = "Role: %s" % role_text


func _refresh_timer() -> void:
	_timer_label.text = "Time: %ds" % Game.time_remaining_s


func _refresh_score() -> void:
	var my_peer_id: int = Net.my_peer_id()
	if my_peer_id <= 0:
		_score_label.text = "Caught: -"
		return
	_score_label.text = "Caught: %d" % Game.get_times_caught(my_peer_id)


func _refresh_effects() -> void:
	var my_peer_id: int = Net.my_peer_id()
	if my_peer_id <= 0 or not Game.is_running:
		_effects_label.text = "Effects: -"
		return

	var effect_lines: PackedStringArray = []
	var invisible_remaining_ms: int = Game.get_powerup_effect_remaining_ms(my_peer_id, "invisible")
	if invisible_remaining_ms > 0:
		effect_lines.append("Invisible %.1fs" % (ceilf(float(invisible_remaining_ms) / 100.0) / 10.0))

	var speed_remaining_ms: int = Game.get_powerup_effect_remaining_ms(my_peer_id, "speed")
	if speed_remaining_ms > 0:
		effect_lines.append("Speed %.1fs" % (ceilf(float(speed_remaining_ms) / 100.0) / 10.0))

	if effect_lines.is_empty():
		_effects_label.text = "Effects: -"
		return

	_effects_label.text = "Effects: %s" % " | ".join(effect_lines)


func _on_freeze_state_changed(peer_id: int) -> void:
	if peer_id == Net.my_peer_id():
		_refresh_role()


func _on_timer_changed(_time_remaining_s: int) -> void:
	_refresh_timer()


func _on_powerup_effect_changed(peer_id: int) -> void:
	if peer_id != Net.my_peer_id():
		return
	_refresh_effects()
