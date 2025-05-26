class_name DraggableArea
extends Area2D

var is_hovered: bool = false

func _ready() -> void:
	# Connect the built-in signals.
	self.mouse_entered.connect(_on_mouse_entered)
	self.mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	is_hovered = true
	#print("Mouse entered area")

func _on_mouse_exited() -> void:
	is_hovered = false
	#print("Mouse exited area")
