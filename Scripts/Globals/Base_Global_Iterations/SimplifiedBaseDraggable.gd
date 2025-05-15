extends RigidBody2D
class_name SimplifiedBaseDraggable

# Physics parameters - adjust these to change how dragging feels
@export var drag_strength: float = 20.0  # Higher = faster response to mouse
@export var drag_damp: float = 0.9       # Lower = less oscillation
@export var max_speed: float = 1500.0    # Prevents excessive velocity

# Reference to the area that detects mouse hovering
var drag_area: Area2D
var dragging: bool = false
var drag_point: Vector2  # Local point where the object is being dragged
var drag_line: Line2D    # Visual line showing the drag force

func _ready() -> void:
	# Setup proper physics for realistic behavior
	custom_integrator = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# Create the drag area if it doesn't exist
	drag_area = _ensure_drag_area()

func _ensure_drag_area() -> Area2D:
	# Find existing drag area or create one
	for child in get_children():
		if child is Area2D:
			return child
	
	# Create a new drag area that matches the collision shape
	var area = Area2D.new()
	area.name = "DragArea"
	
	# Find collision shape and duplicate it for the area
	for child in get_children():
		if child is CollisionShape2D:
			var area_shape = CollisionShape2D.new()
			area_shape.shape = child.shape.duplicate()
			area.add_child(area_shape)
			break
	
	# Connect signals
	area.input_event.connect(_on_drag_area_input_event)
	
	add_child(area)
	return area

func _on_drag_area_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start dragging
			var local_point = to_local(event.global_position)
			_start_drag(local_point)
		elif dragging:
			# Stop dragging
			_end_drag()

func _start_drag(local_point: Vector2) -> void:
	dragging = true
	drag_point = local_point
	
	# Create visual line to show force being applied
	drag_line = Line2D.new()
	drag_line.width = 2.0
	drag_line.default_color = Color(1.0, 0.3, 0.3, 0.8)
	drag_line.add_point(to_global(drag_point))
	drag_line.add_point(get_global_mouse_position())
	get_parent().add_child(drag_line)

func _end_drag() -> void:
	dragging = false
	if drag_line:
		drag_line.queue_free()
		drag_line = null

func _physics_process(delta: float) -> void:
	if dragging:
		# Calculate the force direction from mouse to drag point
		var target_pos = get_global_mouse_position()
		var current_pos = to_global(drag_point)
		var force_direction = target_pos - current_pos
		var distance = force_direction.length()
		
		# Apply force based on distance
		var force = force_direction.normalized() * distance * drag_strength
		apply_force(force, drag_point)
		
		# Dampen velocity to prevent oscillation
		linear_velocity *= drag_damp
		
		# Update visual line
		if drag_line:
			drag_line.set_point_position(0, current_pos)
			drag_line.set_point_position(1, target_pos)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# First let the physics engine do its thing
	state.integrate_forces()
	
	# Then clamp velocity to prevent excessive speeds
	if state.linear_velocity.length() > max_speed:
		state.linear_velocity = state.linear_velocity.normalized() * max_speed