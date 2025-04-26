# BaseDraggable.gd  – Godot 4.3 / 4.4
extends RigidBody2D
class_name BaseDraggable

# ───────────── Scene references (drag into Inspector) ─────────────
@export var drag_area : Area2D        # hover detection
@export var handle    : StaticBody2D  # invisible hand
@export var sprite    : AnimatedSprite2D
@export var collider  : CollisionShape2D

# ───────────── Joint parameters ─────────────
@export var joint_softness : float = 0.0   # 0 = rigid pin, >0 = springy
@export var joint_bias     : float = 0.9   # solver bias (0–1; high pulls harder)
@export var follow_lerp    : float = 0.5   # how fast the handle chases the mouse

# ───────────── Internals ─────────────
var dragging      : bool = false
var drag_offset   : Vector2
var mouse_joint   : PinJoint2D        # created at runtime

# --------------------------------------------------------------
func _ready() -> void:
	# Handle never collides; we just teleport it each physics step
	pass

# --------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if drag_area and drag_area.is_hovered:
				_start_drag(event.position)
		elif dragging:
			_end_drag()

# --------------------------------------------------------------
func _start_drag(mouse_pos: Vector2) -> void:
	dragging    = true
	drag_offset = to_local(mouse_pos)

	# Move handle to the grab point right away
	handle.global_position = mouse_pos

	# Create & configure the joint
	mouse_joint = PinJoint2D.new()
	mouse_joint.node_a = handle.get_path()
	mouse_joint.node_b = self.get_path()
	mouse_joint.softness = joint_softness      # 0 = stiff, >0 = spring
	mouse_joint.bias     = joint_bias
	add_child(mouse_joint)

# --------------------------------------------------------------
func _end_drag() -> void:
	dragging = false
	if mouse_joint:
		mouse_joint.queue_free()
		mouse_joint = null

# --------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if dragging:
		# Destination is the mouse minus the original grab offset (so centre vs handle feels right)
		var target = get_global_mouse_position()
		handle.global_position = handle.global_position.lerp(target, follow_lerp)

# --------------------------------------------------------------
func _exit_tree() -> void:
	if mouse_joint:
		mouse_joint.queue_free()
