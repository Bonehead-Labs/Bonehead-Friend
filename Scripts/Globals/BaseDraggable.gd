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

## Everything grabbable joins this group so the overlay knows which parts of the window
## must accept clicks rather than passing them through to the desktop.
const GROUP_INTERACTIVE := &"interactive"

func _ready() -> void:
	custom_integrator = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	add_to_group(GROUP_INTERACTIVE)

## World-space rect the overlay should keep clickable. Derived from the actual collision
## shape where there is one, so a mace and a grenade get appropriately sized regions.
func get_interaction_rect() -> Rect2:
	var extent := Vector2(48, 48)
	if collider and collider.shape:
		var r := collider.shape.get_rect() if collider.shape.has_method("get_rect") else Rect2()
		if r.size.length() > 0.0:
			extent = (r.size * 0.5 * global_scale).abs()
		elif collider.shape is CircleShape2D:
			var radius: float = (collider.shape as CircleShape2D).radius
			extent = Vector2(radius, radius) * global_scale.abs()
	return Rect2(global_position - extent, extent * 2.0)

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
