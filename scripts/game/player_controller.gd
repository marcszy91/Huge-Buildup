extends CharacterBody3D

const RUN_SPEED: float = 8.7
const GRAVITY: float = 20.0
const REMOTE_LERP_SPEED: float = 12.0
const TURN_SPEED_RAD: float = 10.0
const MOUSE_SENSITIVITY: float = 0.0024
const CAMERA_PITCH_MIN_RAD: float = deg_to_rad(-50.0)
const CAMERA_PITCH_MAX_RAD: float = deg_to_rad(-10.0)
const DEFAULT_IDLE_ANIMATION_NAME: String = "Idle"
const DEFAULT_WALK_ANIMATION_NAME: String = "Walk"
const DEFAULT_RUN_ANIMATION_NAME: String = "Run"
const DEFAULT_CHARACTER_ID: String = "chef_female"
const COLOR_NEUTRAL: Color = Color(0.7, 0.72, 0.78, 1.0)
const COLOR_CATCHER: Color = Color(0.93, 0.21, 0.22, 1.0)
const COLOR_SELF: Color = Color(0.2, 0.82, 0.42, 1.0)
const COLOR_RUNNER_VISIBLE_TO_CATCHER: Color = Color(0.25, 0.55, 0.95, 1.0)

var _is_local_controlled: bool = true
var _is_frozen: bool = false
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_yaw: float = 0.0
@onready var _camera_yaw: Node3D = $CameraYaw
@onready var _camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var _camera: Camera3D = $CameraYaw/CameraPitch/Camera3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _character_visual: Node3D = $CharacterVisual

var _character_animation_player: AnimationPlayer
var _current_character_animation_name: String = ""
var _character_id: String = DEFAULT_CHARACTER_ID


func _ready() -> void:
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		var material: StandardMaterial3D = (
			(_mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		)
		_mesh.material_override = material
	_remote_target_position = global_position
	_remote_target_yaw = rotation.y
	if _camera_yaw != null:
		_camera_yaw.rotation.y = rotation.y
	_apply_character_visual()
	_setup_character_animation()
	_apply_control_mode()
	set_role_visual(false, false, _is_local_controlled)


func set_local_controlled(is_local_controlled: bool) -> void:
	_is_local_controlled = is_local_controlled
	_apply_control_mode()


func set_network_target_transform(pos: Vector3, yaw: float) -> void:
	_remote_target_position = pos
	_remote_target_yaw = yaw


func set_frozen(is_frozen: bool) -> void:
	_is_frozen = is_frozen
	if _is_frozen:
		velocity = Vector3.ZERO


func set_character_id(next_character_id: String) -> void:
	var clean_character_id: String = _sanitize_character_id(next_character_id)
	if _character_id == clean_character_id:
		return
	_character_id = clean_character_id
	_apply_character_visual()
	_setup_character_animation()


func set_role_visual(
	local_is_catcher: bool, player_is_catcher: bool, is_local_player: bool
) -> void:
	if _mesh == null:
		return
	var material: StandardMaterial3D = _mesh.material_override as StandardMaterial3D
	if material == null:
		return

	var color: Color = COLOR_NEUTRAL
	if is_local_player:
		color = COLOR_SELF
	elif local_is_catcher:
		if player_is_catcher:
			color = COLOR_CATCHER
		else:
			color = COLOR_RUNNER_VISIBLE_TO_CATCHER
	else:
		color = COLOR_NEUTRAL
	material.albedo_color = color


func _process(delta: float) -> void:
	if _is_local_controlled:
		return

	var t: float = clampf(REMOTE_LERP_SPEED * delta, 0.0, 1.0)
	global_position = global_position.lerp(_remote_target_position, t)
	rotation.y = lerp_angle(rotation.y, _remote_target_yaw, t)
	_update_character_animation(global_position.distance_to(_remote_target_position) > 0.05)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_controlled:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_camera_pitch.rotation.x = clampf(
			_camera_pitch.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			CAMERA_PITCH_MIN_RAD,
			CAMERA_PITCH_MAX_RAD
		)
		return

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not _is_local_controlled:
		return
	if _is_frozen:
		velocity = Vector3.ZERO
		_update_character_animation(false)
		return

	var input_vec: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var camera_forward: Vector3 = -_camera.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right: Vector3 = _camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var move_dir: Vector3 = (
		(camera_right * input_vec.x + camera_forward * -input_vec.y).normalized()
	)
	if move_dir.length_squared() > 0.0:
		var target_yaw: float = atan2(move_dir.x, move_dir.z)
		var previous_root_yaw: float = rotation.y
		var t_turn: float = clampf(TURN_SPEED_RAD * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, target_yaw, t_turn)
		if _camera_yaw != null:
			# Compensate root turn so mouse-look camera yaw stays visually stable in world space.
			_camera_yaw.rotation.y += previous_root_yaw - rotation.y

	velocity.x = move_dir.x * RUN_SPEED
	velocity.z = move_dir.z * RUN_SPEED

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	_update_character_animation(move_dir.length_squared() > 0.0)


func _apply_control_mode() -> void:
	if _camera != null:
		_camera.current = _is_local_controlled

	set_physics_process(_is_local_controlled)
	set_process(not _is_local_controlled)
	set_process_unhandled_input(_is_local_controlled)

	if _is_local_controlled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		velocity = Vector3.ZERO


func _setup_character_animation() -> void:
	if _character_visual == null:
		return
	var active_character_root: Node = _get_active_character_root()
	if active_character_root == null:
		_character_animation_player = null
		_current_character_animation_name = ""
		return
	_character_animation_player = _find_animation_player_recursive(active_character_root)
	_current_character_animation_name = ""
	if _character_animation_player == null:
		return

	if _character_animation_player.has_animation(DEFAULT_IDLE_ANIMATION_NAME):
		_play_character_animation(DEFAULT_IDLE_ANIMATION_NAME)
		return

	var animation_list: PackedStringArray = _character_animation_player.get_animation_list()
	if not animation_list.is_empty():
		_play_character_animation(animation_list[0])


func _find_animation_player_recursive(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var nested: AnimationPlayer = _find_animation_player_recursive(child)
		if nested != null:
			return nested
	return null


func _update_character_animation(is_moving: bool) -> void:
	if _character_animation_player == null:
		return
	if not is_moving:
		_play_character_animation(DEFAULT_IDLE_ANIMATION_NAME)
		return
	if _character_animation_player.has_animation(DEFAULT_RUN_ANIMATION_NAME):
		_play_character_animation(DEFAULT_RUN_ANIMATION_NAME)
		return
	if _character_animation_player.has_animation(DEFAULT_WALK_ANIMATION_NAME):
		_play_character_animation(DEFAULT_WALK_ANIMATION_NAME)


func _play_character_animation(animation_name: String) -> void:
	if _character_animation_player == null:
		return
	if animation_name.is_empty():
		return
	if not _character_animation_player.has_animation(animation_name):
		return
	if (
		_current_character_animation_name == animation_name
		and _character_animation_player.is_playing()
	):
		return
	_current_character_animation_name = animation_name
	_character_animation_player.play(animation_name)


func _apply_character_visual() -> void:
	if _character_visual == null:
		return
	for child in _character_visual.get_children():
		if not (child is Node3D):
			continue
		var child_node: Node3D = child as Node3D
		var should_show: bool = child_node.name.to_lower() == _node_name_for_character_id(_character_id)
		child_node.visible = should_show


func _get_active_character_root() -> Node:
	if _character_visual == null:
		return null
	var target_name: String = _node_name_for_character_id(_character_id)
	for child in _character_visual.get_children():
		if (child is Node3D) and (child as Node3D).name.to_lower() == target_name:
			return child
	for child in _character_visual.get_children():
		if child is Node3D:
			return child
	return null


func _sanitize_character_id(raw_character_id: String) -> String:
	var clean_id: String = raw_character_id.strip_edges().to_lower()
	match clean_id:
		"chef_female", "casual_male":
			return clean_id
		_:
			return DEFAULT_CHARACTER_ID


func _node_name_for_character_id(character_id: String) -> String:
	match character_id:
		"casual_male":
			return "casualmale"
		_:
			return "cheffemale"
