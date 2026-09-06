class_name DraggableArea
extends Area2D

## Hover sensor for BaseDraggable. Kept as its own node so the grab region can be larger
## and simpler than the physics collider.

var is_hovered: bool = false

## The cursor came over the grab region, or left it. `is_hovered` was tracked and told to
## nobody; the buddy's expression brain reads this to know he is being looked at.
signal hover_changed(hovered: bool)

func _ready() -> void:
	# Mouse picking works off input_pickable, not monitoring. Leaving monitoring on made
	# every grab region track overlaps with the world walls for nobody's benefit.
	monitoring = false
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	is_hovered = true
	hover_changed.emit(true)

func _on_mouse_exited() -> void:
	is_hovered = false
	hover_changed.emit(false)
