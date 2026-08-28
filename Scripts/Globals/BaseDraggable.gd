extends RigidBody2D
class_name BaseDraggable

## Anything the player can grab and fling. The drag works by pinning this body to an
## invisible StaticBody2D "handle" that chases the mouse — that joint is what gives the
## game its feel, so don't replace it with direct position setting.

@export var drag_area : Area2D
@export var handle    : StaticBody2D
@export var sprite    : AnimatedSprite2D
@export var collider  : CollisionShape2D
@export var Effects_Player: EffectsPlayer

@export var joint_softness : float = 1.0
@export var joint_bias     : float = 0.2
@export var follow_lerp    : float = 1.0

var dragging    : bool = false
var mouse_joint : PinJoint2D

func _ready() -> void:
	custom_integrator = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

## Unhandled, not _input: UI must be able to consume a click before the world sees it,
## otherwise every panel the player opens also grabs whatever is behind it.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and drag_area and drag_area.is_hovered:
			_start_drag()
			get_viewport().set_input_as_handled()
		elif not event.pressed and dragging:
			_end_drag()

func _start_drag() -> void:
	if not handle:
		return
	dragging = true
	# Global space throughout. The old code mixed event.position (viewport space) here
	# with get_global_mouse_position() in _physics_process, which disagree the moment
	# any camera or stretch mode is introduced.
	handle.global_position = get_global_mouse_position()

	mouse_joint = PinJoint2D.new()
	mouse_joint.node_a   = handle.get_path()
	mouse_joint.node_b   = get_path()
	mouse_joint.softness = joint_softness
	mouse_joint.bias     = joint_bias
	add_child(mouse_joint)

func _end_drag() -> void:
	dragging = false
	if mouse_joint:
		mouse_joint.queue_free()
		mouse_joint = null

func _physics_process(_delta: float) -> void:
	if dragging and handle:
		handle.global_position = handle.global_position.lerp(get_global_mouse_position(), follow_lerp)
