extends Node2D

## One drawn piece of a payoff shape (`AbilityFX.payoff_shaped`): a node built the first time its
## shape plays, parked under `AbilityFX` and fired again from there, so a shape allocates nothing
## per use after its first and nothing at all at rest. `_process` runs only while it is in flight.
##
## Every stroke is whole pixels with a dark rim (`ink_*`), because it is drawn over a white skeleton,
## a dark desk and the chroma green alike; nothing fades (D68): a piece leaves by shrinking, thinning
## or running out of length. Its randomness is its own generator, never the global one the suites
## seed per weapon, and is seeded by its name, so a `--fixed-fps` capture of it is the same every run.
##
## A shape script subclasses this as an inner class, overrides `_draw` (reading `t`, 0 at the fire,
## and `life`) and takes one with `take(afx, key, script)`. No `class_name`: every shape preloads it
## by path, so no two streams can collide on a global name.

const OUTLINE := Color("141210")
## One art pixel is two world pixels, the scale every sprite is drawn at.
const ART := 2.0

## Seconds since it was fired, and how long it lasts.
var t := 0.0
var life := 0.5
## 0..1, as the look's payoff sizes it.
var size := 1.0
var colour := Color.WHITE
var rng := RandomNumberGenerator.new()
## Him, when the piece rides along with him (`follow`), so a moment that goes with him goes with him.
var _him: WeakRef
var _him_offset := Vector2.ZERO

func _ready() -> void:
	set_process(false)
	visible = false
	rng.seed = hash(String(name))

## A parked piece of `script` under `afx`, building `pool` of them the first time (`key0`..): the
## first one not in flight, or the oldest. Null with no `afx`.
static func take(afx: Node, key: String, script: GDScript, pool: int = 2) -> Node2D:
	if afx == null or script == null:
		return null
	if afx.get_node_or_null("%s0" % key) == null:
		for i in pool:
			var made := script.new() as Node2D
			made.name = "%s%d" % [key, i]
			afx.add_child(made)
	var meta := StringName("shape_next_%s" % key)
	var next := int(afx.get_meta(meta)) if afx.has_meta(meta) else 0
	var pick: Node2D = null
	for i in pool:
		var index := (next + i) % pool
		var piece := afx.get_node_or_null("%s%d" % [key, index]) as Node2D
		if piece and not piece.is_processing():
			pick = piece
			next = index
			break
	if pick == null:
		pick = afx.get_node_or_null("%s%d" % [key, next]) as Node2D
	afx.set_meta(meta, (next + 1) % pool)
	return pick

## Starts it at `at`, lasting `seconds`.
func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
	global_position = at.round()
	t = 0.0
	life = maxf(seconds, 0.02)
	size = clampf(amount, 0.0, 1.0)
	colour = tint
	_him = null
	visible = true
	set_process(true)
	queue_redraw()

## Rides along with `him` from here on, at `offset` from his middle.
func follow(him: Node2D, offset: Vector2 = Vector2.ZERO) -> void:
	_him = weakref(him) if him else null
	_him_offset = offset

func _process(delta: float) -> void:
	t += delta
	if t >= life:
		visible = false
		set_process(false)
		return
	if _him:
		var him := _him.get_ref() as Node2D
		if him and is_instance_valid(him) and him.is_inside_tree():
			var centre: Vector2 = him.call("get_interaction_rect").get_center() \
				if him.has_method("get_interaction_rect") else him.global_position
			global_position = (centre + _him_offset).round()
	_step(delta)
	queue_redraw()

## A subclass's own motion, between the clock and the redraw.
func _step(_delta: float) -> void:
	pass

## How many of `n` chips, splinters or chunks to throw: half of them at Subtle, as `AbilityFX.spray`
## halves its own (a moment that throws nothing reads as one that missed).
static func count(n: int) -> int:
	if Settings.focus_intensity == Settings.Intensity.SUBTLE:
		return maxi(1, n / 2)
	return n

## 0..1 of the way from `from` to `to` seconds, clamped.
func k_of(from: float, to: float) -> float:
	return clampf((t - from) / maxf(to - from, 0.001), 0.0, 1.0)

static func ease_out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)

# --- ink -----------------------------------------------------------------------------------------

## A stroke with a dark rim all round it, ends included.
func ink_line(a: Vector2, b: Vector2, tint: Color, width: float) -> void:
	var d := (b - a).normalized() if a.distance_squared_to(b) > 0.01 else Vector2.RIGHT
	draw_line((a - d).round(), (b + d).round(), OUTLINE, width + 2.0)
	draw_line(a.round(), b.round(), tint, width)

func ink_polyline(points: PackedVector2Array, tint: Color, width: float) -> void:
	if points.size() < 2:
		return
	var rounded := PackedVector2Array()
	for p in points:
		rounded.append(p.round())
	draw_polyline(rounded, OUTLINE, width + 2.0)
	draw_polyline(rounded, tint, width)

## A filled shape with a one-pixel dark rim. Convex and not degenerate, or it fails to triangulate
## and pushes an error: callers skip a shape too small to draw.
func ink_poly(points: PackedVector2Array, tint: Color) -> void:
	if points.size() < 3:
		return
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, OUTLINE, 2.0)
	draw_colored_polygon(points, tint)

func ink_arc(centre: Vector2, radius: float, from: float, to: float, tint: Color, width: float) -> void:
	if radius < 1.0 or absf(to - from) < 0.01:
		return
	var steps := maxi(4, int(absf(to - from) * radius / 6.0))
	draw_arc(centre.round(), radius, from, to, steps, OUTLINE, width + 2.0, false)
	draw_arc(centre.round(), radius, from, to, steps, tint, width, false)

## A plotted sprite, centred on `at`, at `scale` whole art pixels to one of its pixels (so 1 is the
## 2x every sprite is drawn at). Turned only in quarter turns, which never resample a pixel.
func ink_sprite(texture: Texture2D, at: Vector2, scale: int = 1, quarter: int = 0) -> void:
	if texture == null or scale <= 0:
		return
	var k := ART * float(scale)
	draw_set_transform(at.round(), PI * 0.5 * float(posmod(quarter, 4)), Vector2(k, k))
	var s := texture.get_size()
	draw_texture(texture, (-s * 0.5).floor())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A square chip of `side` px with a dark rim: sawdust, a spark, a fleck of paint.
func ink_chip(at: Vector2, side: float, tint: Color) -> void:
	var p := (at - Vector2(side, side) * 0.5).round()
	draw_rect(Rect2(p - Vector2.ONE, Vector2(side + 2.0, side + 2.0)), OUTLINE)
	draw_rect(Rect2(p, Vector2(side, side)), tint)

## An n-point star (a flash, a glint). Not rounded: a small star rounded collapses its inner points.
func ink_star(at: Vector2, points: int, outer: float, inner: float, tint: Color, turn: float = 0.0) -> void:
	if outer < 4.0:
		return
	for pass_ in 2:
		var grow := 2.0 if pass_ == 0 else 0.0
		var polygon := PackedVector2Array()
		for i in points * 2:
			var r := (outer + grow) if i % 2 == 0 else maxf(inner, 1.5) + grow
			polygon.append(at + Vector2.UP.rotated(turn + PI * float(i) / float(points)) * r)
		draw_colored_polygon(polygon, OUTLINE if pass_ == 0 else tint)

# --- sprites -------------------------------------------------------------------------------------

## Plots a text grid, one character per pixel coloured by `palette` ('.' is nothing), with a
## one-pixel dark rim grown round all of its ink — the way `AbilityFX.plot` draws the icons. Built
## once by the piece that owns it and kept on that piece (a static texture reads as a leak at exit).
static func plot(grid: Array, palette: Dictionary) -> ImageTexture:
	var h := grid.size()
	var w := 0
	for row in grid:
		w = maxi(w, String(row).length())
	var image := Image.create_empty(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in h:
		var row := String(grid[y])
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
		var row := String(grid[y])
		for x in row.length():
			var c := row[x]
			if c == "." or not palette.has(c):
				continue
			image.set_pixel(x + 1, y + 1, palette[c])
	return ImageTexture.create_from_image(image)

## Where he is, for a shape that draws round him: his collider's rect, or a box at `fallback`.
static func him_rect(ability: WeaponAbility, fallback: Vector2) -> Rect2:
	var him: Buddy = ability.buddy() if ability else null
	if him:
		return him.get_interaction_rect()
	return Rect2(fallback - Vector2(24, 48), Vector2(48, 96))
