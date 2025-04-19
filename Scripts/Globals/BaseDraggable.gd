class_name BaseDraggable
extends RigidBody2D


# Attached Nodes
@export var sprite: AnimatedSprite2D
@export var collider: CollisionShape2D
@export var drag_area: DraggableArea

@export var is_uniform: bool = true  # True for uniform (center-based) dragging; false for non-uniform.
var dragging: bool = false
var force_multiplier: float = 8000.0
var max_force: float = 8000.0

# Damping values for dynamic damping.
@export var min_damping: float = 5.0   # Lower damping when far from the mouse.
@export var max_damping: float = 100.0  # Higher damping when close to the mouse.

# Deadzone: if displacement is less than this, snap the object.
var deadzone: float = 10.0

var drag_offset: Vector2 = Vector2.ZERO

@onready var mouse_collider = drag_area

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start dragging only if the mouse is over the collider.
			if mouse_collider.is_hovered:
				dragging = true
				# For uniform objects, use the center; for non-uniform, record the click offset in local space.
				drag_offset = Vector2.ZERO if is_uniform else to_local(get_global_mouse_position())
		else:
			dragging = false

func _physics_process(delta: float) -> void:
	if dragging:
		var target_pos: Vector2 = get_global_mouse_position()
		var displacement: Vector2
		var force_offset: Vector2
		
		if is_uniform:
			# For uniform objects, the displacement is from the center.
			displacement = target_pos - global_position
			force_offset = Vector2.ZERO
		else:
			# For non-uniform objects, calculate displacement from the clicked point.
			var clicked_point_global: Vector2 = to_global(drag_offset)
			displacement = target_pos - clicked_point_global
			force_offset = drag_offset
		
		# If within the deadzone, snap the object to the mouse.
		if displacement.length() < deadzone:
			if is_uniform:
				global_position = target_pos
			else:
				# For non-uniform objects, ensure the clicked point stays at the mouse.
				global_position = target_pos - drag_offset.rotated(rotation)
			linear_velocity = Vector2.ZERO
			return
		
		# Compute the drag force.
		var drag_force: Vector2 = displacement * force_multiplier
		if drag_force.length() > max_force:
			drag_force = drag_force.normalized() * max_force
		
		# Dynamic damping: lower damping when far, higher when close.
		var distance: float = displacement.length()
		var distance_threshold: float = 11.0  # Adjust to control the transition range.
		var effective_damping: float = lerp(max_damping, min_damping, clamp(distance / distance_threshold, 0, 1))
		var damping_force: Vector2 = -linear_velocity * effective_damping
		
		# Apply the combined force at the appropriate offset.
		apply_force(drag_force + damping_force, force_offset)
	else:
		# Apply simple air resistance when not dragging.
		apply_central_force(-linear_velocity * 0.5)
