class_name PayoffSketch
extends Node2D

## The canvas one shaped payoff draws on (D77's PAYOFF, through `AbilityFX.payoff_shaped`). A shape
## script under `Shapes/` subclasses this as an inner class, paints its moment in `_paint`, and its
## static `play` takes one from the pool (`take`) and `fire`s it. Built the first time the shape
## plays and a child of `AbilityFX` from then on: hidden, with no `_process`, between plays.
##
## The rules every shape keeps, kept here once:
## - **Whole pixels.** Points are rounded, lines have no antialiasing, and pictures are plotted grids
##   drawn at a whole number of screen pixels per art pixel (`picture`), never resampled at a
##   fraction.
## - **A dark rim under everything** (`OUTLINE`): a shape is drawn over a white skeleton, a dark desk
##   and the chroma green alike, and no shape uses a green.
## - **Nothing fades** (D68): a shape leaves by drawing in, shrinking or stopping. Every pixel is ink
##   or nothing, for the chroma key.
## - **Never over his face for more than a couple of frames**: a shape goes round him, beside him, or
##   across him as a line.
## - **Its own random stream.** The global one is the suites' (they seed it per weapon), and a
##   flourish must not move what they measure — `Burst.turn_from`'s reason.

const OUTLINE := Color("141210")
## Screen pixels of dark rim round every stroke and polygon.
const RIM := 2.0
## One art pixel is two screen pixels, as for every sprite.
const ART := 2.0

## The locked palette (`art/src/bonehead.gpl`), with the characters `art/tools/pixel_sprite.py`
## gives it, so a grid here means what a grid in `art/pixel/` means. `x`, `w` and `d` are the shape's
## own colour, lighter and darker, as in `AbilityFX.ICONS`.
const KEY := {
	"K": Color8(0, 0, 0), "k": Color8(26, 29, 36),
	"W": Color8(255, 255, 255), "C": Color8(252, 252, 238), "c": Color8(216, 214, 196),
	"A": Color8(127, 227, 223), "a": Color8(46, 184, 179), "q": Color8(27, 122, 118),
	"Y": Color8(242, 208, 107), "O": Color8(232, 134, 44), "R": Color8(200, 56, 46),
	"r": Color8(138, 36, 32), "P": Color8(255, 166, 193), "p": Color8(240, 98, 146),
	"m": Color8(168, 58, 99), "E": Color8(159, 235, 196), "e": Color8(79, 163, 122),
	"G": Color8(195, 202, 216), "g": Color8(154, 163, 184), "h": Color8(90, 97, 114),
	"H": Color8(42, 46, 56), "B": Color8(201, 143, 85), "b": Color8(169, 113, 63),
	"n": Color8(107, 68, 38),
}

const _AROUND: Array[Vector2] = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0),
	Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]

## Seconds it lasts, seconds it has run, how big the moment is (0..1, the look's `size`), and the
## ability's accent.
var life := 0.5
var age := 0.0
var size := 1.0
var colour := Color.WHITE
var rng := RandomNumberGenerator.new()
var _art := {}

## A drawer of `script` (an inner class of the shape) for `key`, from a pool of `count` under `afx`:
## a parked one, or the oldest in flight when all are busy. Made the first time it is asked for.
static func take(afx: AbilityFX, key: String, script: Script, count: int = 2) -> PayoffSketch:
	var oldest: PayoffSketch = null
	for i in count:
		var node_name := "%s%d" % [key, i]
		var known := afx.get_node_or_null(node_name) as PayoffSketch
		if known == null:
			var made := script.new() as PayoffSketch
			made.name = node_name
			made.visible = false
			afx.add_child(made)
			made.set_process(false)
			return made
		if not known.is_processing():
			return known
		if oldest == null or known.age > oldest.age:
			oldest = known
	return oldest

func _init() -> void:
	# Over the desk, the weapons and him, as every ability effect is.
	z_as_relative = false
	z_index = 40
	# Seeded, not randomised: the capture tool's frames are the same frames every run.
	rng.seed = 0x5eed

## Starts it at `at` for `seconds`.
func fire(at: Vector2, seconds: float) -> void:
	global_position = at.round()
	life = maxf(seconds, 0.02)
	age = 0.0
	visible = true
	set_process(true)
	queue_redraw()

func is_busy() -> bool:
	return is_processing()

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		visible = false
		set_process(false)
		return
	queue_redraw()

func _draw() -> void:
	_paint(clampf(age / life, 0.0, 1.0))

## The shape's picture at `k` 0..1 of its life. Overridden by every shape.
func _paint(_k: float) -> void:
	pass

# --- time ----------------------------------------------------------------------------------

## 0..1 of the way from `from` to `to` seconds into its life.
func span(from: float, to: float) -> float:
	return clampf((age - from) / maxf(to - from, 0.001), 0.0, 1.0)

static func ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)

## Out past 1 and back: a thing that lands rather than appears.
static func overshoot(x: float) -> float:
	return x * 1.25 if x < 0.7 else lerpf(0.875, 1.0, (x - 0.7) / 0.3)

# --- ink -----------------------------------------------------------------------------------

## A stroke from `a` to `b` with a dark rim round it, ends included.
func line(a: Vector2, b: Vector2, tint: Color, width: float) -> void:
	if width < 1.0:
		return
	var d := (b - a).normalized() * RIM if a.distance_squared_to(b) > 0.01 else Vector2.ZERO
	draw_line((a - d).round(), (b + d).round(), OUTLINE, width + RIM * 2.0)
	draw_line(a.round(), b.round(), tint, width)

## A stroke through `points`, rimmed.
func strokes(points: PackedVector2Array, tint: Color, width: float) -> void:
	if points.size() < 2 or width < 1.0:
		return
	var rounded := PackedVector2Array()
	for p in points:
		rounded.append(p.round())
	draw_polyline(rounded, OUTLINE, width + RIM * 2.0)
	for p in [rounded[0], rounded[rounded.size() - 1]]:
		draw_rect(Rect2(p - Vector2.ONE * (width * 0.5 + RIM), Vector2.ONE * (width + RIM * 2.0)), OUTLINE)
	draw_polyline(rounded, tint, width)

## An arc, rimmed: `from` to `to` radians about `centre`.
func arc(centre: Vector2, radius: float, from: float, to: float, tint: Color, width: float) -> void:
	if radius < 2.0 or width < 1.0 or absf(to - from) < 0.01:
		return
	var steps := maxi(6, int(absf(to - from) * radius / 6.0))
	var pad := RIM / radius * signf(to - from)
	draw_arc(centre.round(), radius, from - pad, to + pad, steps, OUTLINE, width + RIM * 2.0, false)
	draw_arc(centre.round(), radius, from, to, steps, tint, width, false)

## A filled polygon with a dark rim. Skipped when it is too small to triangulate: a polygon whose
## points collapse onto each other fails and pushes an error (the flare's lesson, D77).
func shape(points: PackedVector2Array, tint: Color, rim: bool = true) -> void:
	if points.size() < 3:
		return
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	if box.size.x < 2.0 or box.size.y < 2.0:
		return
	if rim:
		for o in _AROUND:
			draw_colored_polygon(_moved(points, o * RIM), OUTLINE)
	draw_colored_polygon(points, tint)

static func _moved(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] + by
	return out

## A box, rimmed.
func box(rect: Rect2, tint: Color) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	draw_rect(r.grow(RIM), OUTLINE)
	draw_rect(r, tint)

## A disc, rimmed.
func disc(at: Vector2, radius: float, tint: Color) -> void:
	if radius < 1.0:
		return
	draw_circle(at.round(), radius + RIM, OUTLINE)
	draw_circle(at.round(), radius, tint)

## A four-point star: long thin arms, a glint.
func glint_star(at: Vector2, reach: float, tint: Color, turn: float = 0.0) -> void:
	if reach < 4.0:
		return
	var core := maxf(reach * 0.18, 2.0)
	var points := PackedVector2Array()
	for i in 8:
		var r := reach if i % 2 == 0 else core
		points.append(at + Vector2.UP.rotated(turn + PI * float(i) / 4.0) * r)
	shape(points, tint)

# --- pictures ----------------------------------------------------------------------------------

## A plotted grid at `at`, `scale` 1 being the art's 2x; stepped to whole screen pixels per art
## pixel, so it shrinks in steps and is never resampled at a fraction. Nothing under half a step.
func picture(texture: Texture2D, at: Vector2, scale: float = 1.0, turn: float = 0.0,
		flip: bool = false) -> void:
	if texture == null:
		return
	var s := floorf(ART * scale + 0.5)
	if s < 1.0:
		return
	draw_set_transform(at.round(), turn, Vector2(-s if flip else s, s))
	draw_texture(texture, -(texture.get_size() * 0.5).floor())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A grid plotted once per tint and kept on this drawer: palette characters (`KEY`), `x` `w` `d` for
## `tint` and its lighter and darker, `.` nothing — with a one-pixel dark rim grown round its ink.
func plot(key: String, rows: Array, tint: Color = Color.WHITE) -> Texture2D:
	var cache := "%s|%s" % [key, tint.to_html()]
	if _art.has(cache):
		return _art[cache]
	var h := rows.size()
	var w := 0
	for row in rows:
		w = maxi(w, String(row).length())
	var image := Image.create_empty(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in h:
		var row := String(rows[y])
		for x in row.length():
			if row[x] == ".":
				continue
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var px := x + 1 + int(dx)
					var py := y + 1 + int(dy)
					if image.get_pixel(px, py).a < 0.5:
						image.set_pixel(px, py, OUTLINE)
	for y in h:
		var row := String(rows[y])
		for x in row.length():
			var c := row[x]
			var ink := Color(0, 0, 0, 0)
			match c:
				".":
					continue
				"x":
					ink = tint
				"w":
					ink = tint.lightened(0.5)
				"d":
					ink = tint.darkened(0.35)
				_:
					ink = KEY.get(c, OUTLINE)
			image.set_pixel(x + 1, y + 1, ink)
	var texture := ImageTexture.create_from_image(image)
	_art[cache] = texture
	return texture

## `texture`'s shape in flat white, for tinting: built once per texture and kept on this drawer.
func silhouette(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache := "silhouette|%d" % texture.get_instance_id()
	if _art.has(cache):
		return _art[cache]
	var image := texture.get_image()
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(1, 1, 1, 1) if image.get_pixel(x, y).a > 0.5 else Color(0, 0, 0, 0))
	var made := ImageTexture.create_from_image(image)
	_art[cache] = made
	return made
