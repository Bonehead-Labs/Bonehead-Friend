extends RigidBody2D

## Cursor power: a fist that chases the mouse. Consolidated into CursorPowerBase in M2.

const PARKING_POSITION := Vector2(-10000, -10000)

@export var _Sprite: Sprite2D
@export var follow_Speed: float = 2000.0
@export var leeway_radius: float = 50.0
@export var active: bool = false

var last_rotation: float = 0.0
var previous_mouse_position: Vector2

func _ready() -> void:
	add_to_group(&"power_fist")
	previous_mouse_position = get_global_mouse_position()
	gravity_scale = 0.0
	make_inactive()

func _physics_process(delta: float) -> void:
	if active:
		_fist_physics(delta)

func make_active() -> void:
	active = true
	if _Sprite:
		_Sprite.visible = true
	freeze = false
	set_physics_process(true)

func make_inactive() -> void:
	active = false
	if _Sprite:
		_Sprite.visible = false
	# Park off-screen and freeze. The old version disabled _physics_process *before*
	# the parking branch could run, stranding an invisible collider in the play area
	# that the player could still collide with.
	global_position = PARKING_POSITION
	linear_velocity = Vector2.ZERO
	freeze = true
	set_physics_process(false)

func _fist_physics(_delta: float) -> void:
	var mouse_position := get_global_mouse_position()

	# Velocity rather than direct positioning, so the fist still collides properly.
	var to_mouse := mouse_position - global_position
	if to_mouse.length() > leeway_radius:
		linear_velocity = to_mouse.normalized() * follow_Speed
	else:
		linear_velocity = Vector2.ZERO

	# Only re-aim once the mouse has travelled far enough to imply a direction.
	if previous_mouse_position.distance_to(mouse_position) > leeway_radius:
		var direction := (mouse_position - previous_mouse_position).normalized()
		last_rotation = direction.angle() + PI / 2.0
		previous_mouse_position = mouse_position

	rotation = last_rotation
