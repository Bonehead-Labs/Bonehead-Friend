extends Node2D
## The wordmark's "Labs" pill: teal, an ink border, an ink lift, ink lettering. Centred on its
## origin; the splash sets its rotation (-4 deg at rest, as on the site) and its spring scale.

var font: Font = null
var font_size: int = 40
var text: String = "Labs"
var pill_size: Vector2 = Vector2(176.0, 86.0)
var border_px: float = 4.0
var lift: Vector2 = Vector2(6.0, 6.0)
var teal: Color = Color("#11abac")
var ink: Color = Color("#071b1e")

var _face := StyleBoxFlat.new()
var _shade := StyleBoxFlat.new()


func _draw() -> void:
	var rect := Rect2(-pill_size * 0.5, pill_size)
	var radius: int = int(ceilf(pill_size.y * 0.5))
	for box: StyleBoxFlat in [_face, _shade]:
		box.set_corner_radius_all(radius)
		box.corner_detail = 16
		box.anti_aliasing = true
		box.anti_aliasing_size = 1.0
	_shade.bg_color = ink
	_shade.set_border_width_all(0)
	_face.bg_color = teal
	_face.border_color = ink
	_face.set_border_width_all(int(roundf(border_px)))
	if lift != Vector2.ZERO:
		draw_style_box(_shade, Rect2(rect.position + lift, rect.size))
	draw_style_box(_face, rect)
	if font == null or text.is_empty():
		return
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	# Centre the x-height band rather than the full line box: lowercase-led words read centred.
	var baseline: float = (ascent - descent) * 0.5 - font_size * 0.04
	draw_string(font, Vector2(-size.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
