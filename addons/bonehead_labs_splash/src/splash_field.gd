extends Control
## The splash's paper: the site's #f4ede0 field, its faint dot grid, and the soft teal and brass
## glows. Static: it redraws only when the splash lays it out again.

var paper: Color = Color("#f4ede0")
var dot_color: Color = Color(0.027, 0.106, 0.118, 0.07)
var dot_spacing: float = 48.0
var dot_radius: float = 2.0
## The grid is anchored here (the composition's centre), so it sits symmetrically.
var dot_anchor: Vector2 = Vector2.ZERO
## [centre, radii, colour] per glow, in local px. Drawn in order.
var glows: Array = []

var _glow_texture: GradientTexture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	# A soft falloff (smoothstep-like) rather than a linear cone, so no ring shows at the edge.
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.84), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0),
	])
	_glow_texture = GradientTexture2D.new()
	_glow_texture.gradient = gradient
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(1.0, 0.5)
	_glow_texture.width = 256
	_glow_texture.height = 256


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), paper)
	for glow: Array in glows:
		var centre: Vector2 = glow[0]
		var radii: Vector2 = glow[1]
		var color: Color = glow[2]
		draw_texture_rect(_glow_texture, Rect2(centre - radii, radii * 2.0), false, color)
	if dot_spacing < 4.0 or dot_color.a <= 0.0:
		return
	var start := Vector2(fposmod(dot_anchor.x, dot_spacing), fposmod(dot_anchor.y, dot_spacing))
	var y: float = start.y
	while y < size.y + dot_radius:
		var x: float = start.x
		while x < size.x + dot_radius:
			draw_circle(Vector2(x, y), dot_radius, dot_color, true, -1.0, true)
			x += dot_spacing
		y += dot_spacing
