extends CharacterBody3D

const WALK_SPEED: float = 6.0
const SPRINT_MULTIPLIER: float = 1.45
const GRAVITY: float = 20.0

func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
    var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
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
