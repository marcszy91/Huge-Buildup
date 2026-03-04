extends Control

const SPLASH_DURATION_S: float = 4.6

var _is_finished: bool = false
@onready var _timer: Timer = $Timer
@onready var _subtitle_label: Label = %SubtitleLabel


func _ready() -> void:
	_timer.timeout.connect(_finish)
	_timer.start(SPLASH_DURATION_S)
	_subtitle_label.text = "Tag. Hide. Escape."
	_play_preview_idle(%ChefFemale)
	_play_preview_idle(%CasualMale)
	_play_preview_idle(%NinjaFemale)

func _process(delta: float) -> void:
	%ChefFemale.rotation.y += delta * 0.22
	%CasualMale.rotation.y += delta * 0.16
	%NinjaFemale.rotation.y -= delta * 0.2


func _finish() -> void:
	if _is_finished:
		return
	_is_finished = true
	App.goto_main_menu()


func _play_preview_idle(root: Node) -> void:
	var animation_player: AnimationPlayer = _find_animation_player(root)
	if animation_player == null:
		return
	if animation_player.has_animation("Idle"):
		animation_player.play("Idle")
		return
	var animation_list: PackedStringArray = animation_player.get_animation_list()
	if animation_list.is_empty():
		return
	animation_player.play(animation_list[0])


func _find_animation_player(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var nested: AnimationPlayer = _find_animation_player(child)
		if nested != null:
			return nested
	return null
