extends RigidBody2D
class_name ImprovedBaseDraggable

# Object properties
@export var grab_points: Array[Node2D] = []  # Points where object can be grabbed
@export var sprite: AnimatedSprite2D
@export var collider: CollisionShape2D

# Physics parameters
@export_group("Drag Settings")
@export var drag_force_multiplier: float = 100.0
@export var rotation_force_multiplier: float = 5.0
@export var drag_damping: float = 0.9
@export var max_linear_speed: float = 1000.0
@export var max_angular_speed: float = 50.0
@export var grab_radius: float = 20.0  # How close you need to be to grab an object

# Visual settings
@export_group("Visual Settings")
@export var drag_line_width: float = 2.0
@export var drag_line_color: Color = Color(1.0, 0.3, 0.3, 0.7)
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 0.3)
@export var highlight_width: float = 2.0
@export var show_grab_points: bool = false

# Runtime variables
var active_drags: Dictionary = {}  # Maps pointer IDs to drag points
var highlight: bool = false
var highlight_outline: Line2D

func _ready() -> void:
	# Initialize physics settings
	custom_integrator = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# If no grab points are specified, add the center as a default grab point
	if grab_points.is_empty():
		var center_point = Node2D.new()
		center_point.name = "CenterGrabPoint"
		add_child(center_point)
		grab_points.append(center_point)
	
	# Create highlight outline if needed
	if collider and sprite:
		_setup_highlight_outline()

func _setup_highlight_outline() -> void:
	highlight_outline = Line2D.new()
	highlight_outline.width = highlight_width
	highlight_outline.default_color = highlight_color
	highlight_outline.visible = false
	
	# Create outline based on collision shape
	if collider.shape is CircleShape2D:
		_create_circle_outline(collider.shape.radius)
	elif collider.shape is RectangleShape2D:
		_create_rectangle_outline(collider.shape.size)
	elif collider.shape is CapsuleShape2D:
		_create_capsule_outline(collider.shape.radius, collider.shape.height)
	elif collider.shape is ConvexPolygonShape2D:
		_create_polygon_outline(collider.shape.points)
	
	add_child(highlight_outline)

func _create_circle_outline(radius: float) -> void:
	const segments = 24
	for i in range(segments + 1):
		var angle = i * 2 * PI / segments
		var point = Vector2(cos(angle), sin(angle)) * radius
		highlight_outline.add_point(point)

func _create_rectangle_outline(size: Vector2) -> void:
	var half_size = size / 2
	highlight_outline.add_point(Vector2(-half_size.x, -half_size.y))
	highlight_outline.add_point(Vector2(half_size.x, -half_size.y))
	highlight_outline.add_point(Vector2(half_size.x, half_size.y))
	highlight_outline.add_point(Vector2(-half_size.x, half_size.y))
	highlight_outline.add_point(Vector2(-half_size.x, -half_size.y))

func _create_capsule_outline(radius: float, height: float) -> void:
	const segments = 12
	var half_height = height / 2
	
	# Top semicircle
	for i in range(segments + 1):
		var angle = PI + i * PI / segments
		var point = Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -half_height)
		highlight_outline.add_point(point)
	
	# Bottom semicircle
	for i in range(segments + 1):
		var angle = i * PI / segments
		var point = Vector2(cos(angle), sin(angle)) * radius + Vector2(0, half_height)
		highlight_outline.add_point(point)
	
	# Close the shape
	highlight_outline.add_point(highlight_outline.points[0])

func _create_polygon_outline(points: PackedVector2Array) -> void:
	for point in points:
		highlight_outline.add_point(point)
	highlight_outline.add_point(points[0])  # Close the outline

func _input(event: InputEvent) -> void:
	# Handle mouse events
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_grab(event.position, event.device)
			else:
				_release(event.device)
	
	# Handle touch events
	elif event is InputEventScreenTouch:
		if event.pressed:
			_try_grab(event.position, event.index)
		else:
			_release(event.index)

func _try_grab(position: Vector2, pointer_id: int) -> void:
	# Don't grab if already being dragged by this pointer
	if active_drags.has(pointer_id):
		return
	
	# Find closest grab point within grab radius
	var closest_point = null
	var closest_distance = grab_radius
	
	for point in grab_points:
		var distance = position.distance_to(point.global_position)
		if distance < closest_distance:
			closest_point = point
			closest_distance = distance
	
	if closest_point:
		# Store drag info
		var drag_info = {
			"grab_point": closest_point,
			"global_grab_position": closest_point.global_position,
			"start_position": position,
			"line": _create_drag_line(closest_point.global_position, position)
		}
		active_drags[pointer_id] = drag_info
		
		# Mark object as being dragged
		freeze = false  # Ensure physics is active
		
		# Make this object top-level in the scene tree
		if get_parent().has_method("bring_to_front"):
			get_parent().bring_to_front(self)

func _release(pointer_id: int) -> void:
	if active_drags.has(pointer_id):
		# Remove the visual line
		if active_drags[pointer_id].has("line"):
			active_drags[pointer_id]["line"].queue_free()
		
		# Remove drag info
		active_drags.erase(pointer_id)

func _create_drag_line(from: Vector2, to: Vector2) -> Line2D:
	var line = Line2D.new()
	line.width = drag_line_width
	line.default_color = drag_line_color
	line.add_point(from)
	line.add_point(to)
	get_tree().root.add_child(line)  # Add to root to avoid transform issues
	return line

func _physics_process(delta: float) -> void:
	_update_highlight()
	_apply_drag_forces(delta)

func _update_highlight() -> void:
	# Update highlight when mouse hovers over grab points
	var should_highlight = false
	var mouse_pos = get_global_mouse_position()
	
	for point in grab_points:
		if mouse_pos.distance_to(point.global_position) < grab_radius:
			should_highlight = true
			break
	
	if should_highlight != highlight:
		highlight = should_highlight
		if highlight_outline:
			highlight_outline.visible = highlight

func _apply_drag_forces(delta: float) -> void:
	if active_drags.is_empty():
		return
	
	for pointer_id in active_drags:
		var drag_info = active_drags[pointer_id]
		var target_position = get_global_mouse_position()
		if pointer_id > 0:  # For touch input
			# Use the stored start position for touch input
			target_position = drag_info["start_position"]
		
		var grab_point = drag_info["grab_point"]
		var direction = target_position - grab_point.global_position
		var distance = direction.length()
		
		# Update the visual line
		if drag_info.has("line"):
			drag_info["line"].set_point_position(0, grab_point.global_position)
			drag_info["line"].set_point_position(1, target_position)
		
		# Apply forces - linear and rotational
		var force = direction * drag_force_multiplier
		apply_force(force, grab_point.position)
		
		# Apply torque to assist rotation when needed
		var angle_to_target = grab_point.global_position.angle_to_point(target_position)
		var current_angle = global_rotation
		var angle_diff = _angle_difference(current_angle, angle_to_target)
		apply_torque(angle_diff * rotation_force_multiplier * distance)
		
		# Apply damping to reduce oscillation
		linear_velocity *= drag_damping
		angular_velocity *= drag_damping

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.integrate_forces()
	
	# Apply speed limits
	if linear_velocity.length() > max_linear_speed:
		linear_velocity = linear_velocity.normalized() * max_linear_speed
	
	if abs(angular_velocity) > max_angular_speed:
		angular_velocity = sign(angular_velocity) * max_angular_speed

func _angle_difference(a: float, b: float) -> float:
	var diff = fmod(b - a + PI, 2 * PI) - PI
	return diff if diff > -PI else diff + 2 * PI

# Called when object enters a sleep state
func _on_sleeping_state_changed() -> void:
	if sleeping and not active_drags.is_empty():
		sleeping = false  # Keep active while being dragged

# Public method to add a new grab point at a local position
func add_grab_point(local_position: Vector2, name: String = "") -> Node2D:
	var point = Node2D.new()
	if name.is_empty():
		point.name = "GrabPoint" + str(grab_points.size())
	else:
		point.name = name
	
	point.position = local_position
	add_child(point)
	grab_points.append(point)
	return point

# Public method to remove a grab point
func remove_grab_point(point: Node2D) -> void:
	if grab_points.has(point):
		grab_points.erase(point)
		if point.is_inside_tree():
			point.queue_free()