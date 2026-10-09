extends Node2D
## One word of the Bonehead Labs wordmark, drawn glyph by glyph so each letter can pop on its own.
##
## The site's look: a cream fill inside a heavy ink outline, over an ink "lift" (the outlined
## shape again, offset down and right). Drawn in three passes over every glyph (lift, outline,
## fill), so neighbouring letters share one outline the way the site's stroke does. With
## [member outline_px] 0 and no lift it draws plain tracked text (the tagline).
##
## The origin is the left end of the baseline. Glyph positions come from the shaped line (kerning
## and the Fraunces WONK substitutions included) plus [member tracking_em].

var text: String = "":
	set(value):
		text = value
		_shape()
var font: Font = null:
	set(value):
		font = value
		_shape()
var font_size: int = 64:
	set(value):
		font_size = maxi(1, value)
		_shape()
## Extra advance per glyph, in em (the site sets -0.05em on the wordmark).
var tracking_em: float = 0.0:
	set(value):
		tracking_em = value
		_shape()
var fill_color: Color = Color("#fffcf4")
var ink_color: Color = Color("#071b1e")
## Outline thickness in px on each side of the glyph edge. 0 draws plain text.
var outline_px: float = 0.0
## Offset of the ink lift under the outlined word. Zero draws none.
var lift: Vector2 = Vector2.ZERO

## Per glyph pose (index = glyph order): offset from rest, scale and rotation about the glyph's
## baseline centre, and alpha.
var glyph_offset: Array[Vector2] = []
var glyph_scale: Array[Vector2] = []
var glyph_rotation: PackedFloat32Array = PackedFloat32Array()
var glyph_alpha: PackedFloat32Array = PackedFloat32Array()

var _glyphs: Array[Dictionary] = []
var _width: float = 0.0


func glyph_count() -> int:
	return _glyphs.size()


## The shaped word's advance width (tracking included).
func word_width() -> float:
	return _width


## Rest centre of glyph [param i] on the baseline, in local space.
func glyph_centre(i: int) -> Vector2:
	if i < 0 or i >= _glyphs.size():
		return Vector2.ZERO
	var g: Dictionary = _glyphs[i]
	return Vector2(float(g["x"]) + float(g["advance"]) * 0.5, 0.0)


## The word's ascent and descent at the current size.
func ascent() -> float:
	return font.get_ascent(font_size) if font != null else 0.0


func _shape() -> void:
	_glyphs.clear()
	_width = 0.0
	if font == null or text.is_empty():
		_resize_pose()
		queue_redraw()
		return
	var line := TextLine.new()
	line.add_string(text, font, font_size)
	var ts: TextServer = TextServerManager.get_primary_interface()
	var shaped: Array = ts.shaped_text_get_glyphs(line.get_rid())
	var x: float = 0.0
	var track: float = tracking_em * float(font_size)
	for g: Dictionary in shaped:
		var advance: float = float(g.get("advance", 0.0))
		var index: int = int(g.get("index", 0))
		var rid: RID = g.get("font_rid", RID())
		if index == 0 and advance <= 0.0:
			continue
		_glyphs.append({
			"x": x,
			"advance": advance,
			"offset": g.get("offset", Vector2.ZERO),
			"index": index,
			"rid": rid,
		})
		x += advance + track
	_width = maxf(0.0, x - track)
	_resize_pose()
	queue_redraw()


func _resize_pose() -> void:
	var n: int = _glyphs.size()
	glyph_offset.resize(n)
	glyph_scale.resize(n)
	glyph_rotation.resize(n)
	glyph_alpha.resize(n)
	for i in range(n):
		glyph_offset[i] = Vector2.ZERO
		glyph_scale[i] = Vector2.ONE
		glyph_rotation[i] = 0.0
		glyph_alpha[i] = 1.0


func _draw() -> void:
	if _glyphs.is_empty():
		return
	var ts: TextServer = TextServerManager.get_primary_interface()
	var ci: RID = get_canvas_item()
	var outline_size: int = int(roundf(outline_px * 2.0))
	var passes: Array = []
	if outline_size > 0:
		if lift != Vector2.ZERO:
			passes.append([lift, ink_color, true])
			passes.append([lift, ink_color, false])
		passes.append([Vector2.ZERO, ink_color, true])
		passes.append([Vector2.ZERO, fill_color, false])
	else:
		passes.append([Vector2.ZERO, fill_color, false])
	for pass_def: Array in passes:
		var shift: Vector2 = pass_def[0]
		var color: Color = pass_def[1]
		var is_outline: bool = pass_def[2]
		for i in range(_glyphs.size()):
			var a: float = glyph_alpha[i]
			var sc: Vector2 = glyph_scale[i]
			if a <= 0.001 or absf(sc.x) < 0.001 or absf(sc.y) < 0.001:
				continue
			var g: Dictionary = _glyphs[i]
			var pivot := Vector2(float(g["x"]) + float(g["advance"]) * 0.5, 0.0)
			var m := Transform2D(0.0, pivot + glyph_offset[i])
			m = m * Transform2D(glyph_rotation[i], Vector2.ZERO)
			m = m * Transform2D(Vector2(sc.x, 0.0), Vector2(0.0, sc.y), Vector2.ZERO)
			m = m * Transform2D(0.0, -pivot)
			draw_set_transform_matrix(m)
			var pos := Vector2(float(g["x"]), 0.0) + (g["offset"] as Vector2) + shift
			var c := Color(color, color.a * a)
			if is_outline:
				ts.font_draw_glyph_outline(g["rid"], ci, font_size, outline_size, pos, g["index"], c)
			else:
				ts.font_draw_glyph(g["rid"], ci, font_size, pos, g["index"], c)
	draw_set_transform_matrix(Transform2D.IDENTITY)
