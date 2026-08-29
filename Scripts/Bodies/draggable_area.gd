class_name DraggableArea
extends Area2D

## Hover sensor for BaseDraggable. Kept as its own node so the grab region can be larger
## and simpler than the physics collider.

var is_hovered: bool = false

func _ready() -> void:
	# Mouse picking works off input_pickable, not monitoring. Leaving monitoring on made
	# every grab region track overlaps with the world walls for nobody's benefit.
	monitoring = false
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	is_hovered = true

func _on_mouse_exited() -> void:
	is_hovered = false
