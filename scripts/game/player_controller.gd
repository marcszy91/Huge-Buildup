extends CharacterBody3D

const CharacterRegistryRef = preload("res://scripts/data/character_registry.gd")
const RUN_SPEED: float = 8.7
const GRAVITY: float = 20.0
const JUMP_VELOCITY: float = 8.8
const REMOTE_LERP_SPEED: float = 12.0
const TURN_SPEED_RAD: float = 10.0
const MOUSE_SENSITIVITY: float = 0.0024
const CAMERA_PITCH_MIN_RAD: float = deg_to_rad(-50.0)
const CAMERA_PITCH_MAX_RAD: float = deg_to_rad(-10.0)
const CAMERA_COLLISION_MARGIN: float = 0.18
const CAMERA_MIN_DISTANCE: float = 2.45
const CAMERA_HIDE_CHARACTER_DISTANCE: float = 3.4
const CAMERA_DISTANCE_LERP_SPEED: float = 16.0
const DEFAULT_IDLE_ANIMATION_NAME: String = "Idle"
const DEFAULT_WALK_ANIMATION_NAME: String = "Walk"
const DEFAULT_RUN_ANIMATION_NAME: String = "Run"
const JUMP_ANIMATION_CANDIDATES: PackedStringArray = [
	"Jump",
	"Jump_Full_Short",
	"Jump_Idle",
]
const FALL_ANIMATION_CANDIDATES: PackedStringArray = [
	"Fall",
	"Fall_Idle",
	"Jump_Loop",
]
const DEFAULT_CHARACTER_ID: String = CharacterRegistryRef.DEFAULT_CHARACTER_ID
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
var _camera_default_local_position: Vector3 = Vector3.ZERO
var _camera_target_distance: float = 0.0
var _active_character_instance: Node3D


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
	if _camera != null:
		_camera_default_local_position = _camera.position
		_camera_target_distance = _camera_default_local_position.length()
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
	_update_character_animation(global_position.distance_to(_remote_target_position) > 0.05, false)


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
		_update_character_animation(false, false)
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

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
		else:
			velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	_update_camera_collision(delta)
	_update_character_animation(move_dir.length_squared() > 0.0, is_on_floor())


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


func _update_camera_collision(delta: float) -> void:
	if _camera == null or _camera_pitch == null or not _is_local_controlled:
		return

	var origin: Vector3 = _camera_pitch.global_position
	var desired_camera_position: Vector3 = _camera_pitch.to_global(_camera_default_local_position)
	var max_distance: float = _camera_default_local_position.length()
	var target_distance: float = max_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, desired_camera_position
	)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	if not result.is_empty():
		var hit_position: Vector3 = result["position"]
		var hit_distance: float = origin.distance_to(hit_position) - CAMERA_COLLISION_MARGIN
		target_distance = clampf(hit_distance, CAMERA_MIN_DISTANCE, max_distance)

	var local_direction: Vector3 = _camera_default_local_position.normalized()
	_camera_target_distance = move_toward(
		_camera_target_distance,
		target_distance,
		CAMERA_DISTANCE_LERP_SPEED * delta
	)
	_camera.position = local_direction * _camera_target_distance

	if _character_visual != null:
		_character_visual.visible = _camera_target_distance >= CAMERA_HIDE_CHARACTER_DISTANCE


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


func _update_character_animation(is_moving: bool, on_floor: bool) -> void:
	if _character_animation_player == null:
		return
	if not on_floor:
		if velocity.y > 0.2 and _play_first_available_character_animation(JUMP_ANIMATION_CANDIDATES):
			return
		if velocity.y < -0.2 and _play_first_available_character_animation(FALL_ANIMATION_CANDIDATES):
			return
	if not is_moving:
		_play_character_animation(DEFAULT_IDLE_ANIMATION_NAME)
		return
	if _character_animation_player.has_animation(DEFAULT_RUN_ANIMATION_NAME):
		_play_character_animation(DEFAULT_RUN_ANIMATION_NAME)
		return
	if _character_animation_player.has_animation(DEFAULT_WALK_ANIMATION_NAME):
		_play_character_animation(DEFAULT_WALK_ANIMATION_NAME)


func _play_first_available_character_animation(animation_names: PackedStringArray) -> bool:
	for animation_name in animation_names:
		if _character_animation_player.has_animation(animation_name):
			_play_character_animation(animation_name)
			return true
	return false


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
	if _active_character_instance != null:
		_active_character_instance.queue_free()
		_active_character_instance = null

	var scene: PackedScene = CharacterRegistryRef.load_scene(_character_id)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	_active_character_instance = instance as Node3D
	_character_visual.add_child(_active_character_instance)


func _get_active_character_root() -> Node:
	return _active_character_instance


func _sanitize_character_id(raw_character_id: String) -> String:
	return CharacterRegistryRef.sanitize_id(raw_character_id)
