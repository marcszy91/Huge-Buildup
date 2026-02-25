extends CharacterBody3D

const WALK_SPEED: float = 6.0
const SPRINT_MULTIPLIER: float = 1.45
const GRAVITY: float = 20.0
const REMOTE_LERP_SPEED: float = 12.0
const COLOR_NEUTRAL: Color = Color(0.7, 0.72, 0.78, 1.0)
const COLOR_CATCHER: Color = Color(0.93, 0.21, 0.22, 1.0)
const COLOR_SELF: Color = Color(0.2, 0.82, 0.42, 1.0)
const COLOR_RUNNER_VISIBLE_TO_CATCHER: Color = Color(0.25, 0.55, 0.95, 1.0)

var _is_local_controlled: bool = true
var _is_frozen: bool = false
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_yaw: float = 0.0
@onready var _camera: Camera3D = $Pivot/Camera3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		var material: StandardMaterial3D = (
			(_mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		)
		_mesh.material_override = material
	_remote_target_position = global_position
	_remote_target_yaw = rotation.y
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


func _physics_process(delta: float) -> void:
	if not _is_local_controlled:
		return
	if _is_frozen:
		velocity = Vector3.ZERO
		return

	var input_vec: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var move_dir: Vector3 = Vector3(input_vec.x, 0.0, input_vec.y).normalized()

	var speed: float = WALK_SPEED
	if Input.is_action_pressed("sprint"):
		speed *= SPRINT_MULTIPLIER

	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()


func _apply_control_mode() -> void:
	if _camera != null:
		_camera.current = _is_local_controlled

	set_physics_process(_is_local_controlled)
	set_process(not _is_local_controlled)

	if _is_local_controlled:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		velocity = Vector3.ZERO
