# BaseDraggable.gd  – Godot 4.4
extends RigidBody2D
class_name BaseDraggable

@export var drag_area : Area2D
@export var handle    : StaticBody2D
@export var sprite    : AnimatedSprite2D
@export var collider  : CollisionShape2D

@export var joint_softness : float = 1.0
@export var joint_bias     : float = 0.2
@export var follow_lerp    : float = 1.0

@export var max_linear_speed  : float = 1000.0
@export var max_angular_speed : float =  50.0

var dragging      : bool = false
var drag_offset   : Vector2
var mouse_joint   : PinJoint2D
var joint_line    : Line2D

func _ready() -> void:
	custom_integrator = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and drag_area.is_hovered:
			_start_drag(event.position)
		elif not event.pressed and dragging:
			_end_drag()

func create_debug_line():
	# --- create the visual line ---
	joint_line = Line2D.new()
	joint_line.width = 2
	joint_line.default_color = Color.RED
	# start with two dummy points
	joint_line.add_point(handle.global_position)
	joint_line.add_point(to_global(drag_offset))
	get_parent().add_child(joint_line)


func _start_drag(mouse_pos: Vector2) -> void:
	dragging    = true
	drag_offset = to_local(mouse_pos)
	handle.global_position = mouse_pos

	# --- create the joint ---
	mouse_joint = PinJoint2D.new()
	mouse_joint.node_a   = handle.get_path()
	mouse_joint.node_b   = get_path()
	mouse_joint.softness = joint_softness
	mouse_joint.bias     = joint_bias
	add_child(mouse_joint)

	#create_debug_line()

func _end_drag() -> void:
	dragging = false
	if mouse_joint:
		mouse_joint.queue_free()
		mouse_joint = null
	if joint_line:
		joint_line.queue_free()
		joint_line = null

func _physics_process(delta: float) -> void:
	if dragging:
		# move handle toward mouse
		var target = get_global_mouse_position()
		handle.global_position = handle.global_position.lerp(target, follow_lerp)
		# update the visual line
		if joint_line:
			joint_line.set_point_position(0, handle.global_position)
			joint_line.set_point_position(1, to_global(drag_offset))

# func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
# 	state.integrate_forces()
# 	# clamp linear
# 	var lv = state.linear_velocity
# 	if lv.length() > max_linear_speed:
# 		state.linear_velocity = lv.normalized() * max_linear_speed
# 	# clamp angular
# 	var av = state.angular_velocity
# 	if abs(av) > max_angular_speed:
# 		state.angular_velocity = sign(av) * max_angular_speed
