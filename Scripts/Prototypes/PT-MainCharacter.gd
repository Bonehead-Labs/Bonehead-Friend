extends RigidBody2D

var dragging: bool = false
var force_multiplier: float = 1000.0

@onready var mouse_collider = $Area2D

# Global input: only start dragging if the mouse is over the Area2D.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start dragging if the mouse is hovering over the Area2D.
			if mouse_collider.is_hovered:
				dragging = true
		else:
			dragging = false

func _physics_process(delta: float) -> void:
	if dragging:
		var target_pos: Vector2 = get_global_mouse_position()
		var displacement: Vector2 = target_pos - global_position
		# Apply a force proportional to the displacement.
		var damping_force: Vector2 = -linear_velocity * 50.0
		apply_force(displacement * force_multiplier + damping_force, Vector2.ZERO)
