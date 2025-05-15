extends Area2D
class_name ImprovedDraggableArea

# Visual settings
@export var hover_highlight_color: Color = Color(1.0, 1.0, 1.0, 0.3)
@export var hover_outline_width: float = 2.0
@export var show_hover_outline: bool = true

# Status trackers
var is_hovered: bool = false
var hover_outline: Line2D

# Signals
signal area_hovered(area: ImprovedDraggableArea)
signal area_unhovered(area: ImprovedDraggableArea)

func _ready() -> void:
	# Connect the built-in signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Find and setup outline for hover effect
	if show_hover_outline:
		_setup_hover_outline()

func _setup_hover_outline() -> void:
	hover_outline = Line2D.new()
	hover_outline.width = hover_outline_width
	hover_outline.default_color = hover_highlight_color
	hover_outline.visible = false
	
	# Create outline based on collision shape
	var collision_shape = null
	
	# Find the collision shape
	for child in get_children():
		if child is CollisionShape2D:
			collision_shape = child
			break
	
	if collision_shape:
		if collision_shape.shape is CircleShape2D:
			_create_circle_outline(collision_shape.shape.radius)
		elif collision_shape.shape is RectangleShape2D:
			_create_rectangle_outline(collision_shape.shape.size)
		elif collision_shape.shape is CapsuleShape2D:
			_create_capsule_outline(collision_shape.shape.radius, collision_shape.shape.height)
		elif collision_shape.shape is ConvexPolygonShape2D:
			_create_polygon_outline(collision_shape.shape.points)
		
		add_child(hover_outline)

func _create_circle_outline(radius: float) -> void:
	const segments = 24
	for i in range(segments + 1):
		var angle = i * 2 * PI / segments
		var point = Vector2(cos(angle), sin(angle)) * radius
		hover_outline.add_point(point)

func _create_rectangle_outline(size: Vector2) -> void:
	var half_size = size / 2
	hover_outline.add_point(Vector2(-half_size.x, -half_size.y))
	hover_outline.add_point(Vector2(half_size.x, -half_size.y))
	hover_outline.add_point(Vector2(half_size.x, half_size.y))
	hover_outline.add_point(Vector2(-half_size.x, half_size.y))
	hover_outline.add_point(Vector2(-half_size.x, -half_size.y))

func _create_capsule_outline(radius: float, height: float) -> void:
	const segments = 12
	var half_height = height / 2
	
	# Top semicircle
	for i in range(segments + 1):
		var angle = PI + i * PI / segments
		var point = Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -half_height)
		hover_outline.add_point(point)
	
	# Bottom semicircle
	for i in range(segments + 1):
		var angle = i * PI / segments
		var point = Vector2(cos(angle), sin(angle)) * radius + Vector2(0, half_height)
		hover_outline.add_point(point)
	
	# Close the shape
	hover_outline.add_point(hover_outline.points[0])

func _create_polygon_outline(points: PackedVector2Array) -> void:
	for point in points:
		hover_outline.add_point(point)
	hover_outline.add_point(points[0])  # Close the outline

func _on_mouse_entered() -> void:
	is_hovered = true
	if hover_outline:
		hover_outline.visible = true
	emit_signal("area_hovered", self)

func _on_mouse_exited() -> void:
	is_hovered = false
	if hover_outline:
		hover_outline.visible = false
	emit_signal("area_unhovered", self)

# Method to manually set hover state (useful for mobile/touch)
func set_hover_state(hovering: bool) -> void:
	if hovering != is_hovered:
		is_hovered = hovering
		if hover_outline:
			hover_outline.visible = hovering
		
		if hovering:
			emit_signal("area_hovered", self)
		else:
			emit_signal("area_unhovered", self)