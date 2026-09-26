extends Node2D

## The canvas one payoff shape draws on (D77's shapes, `AbilityFX.payoff_shaped`). Built the first
## time its shape plays, as a named child of `AbilityFX`, and parked hidden between plays: a shape
## allocates nothing after its first use, and nothing of it runs at rest. It draws in world
## coordinates and ticks only while something of it is in the air.
##
## A shape extends this (`class Pins extends "res://.../kit/moment.gd"`), fetches its canvas with
## `canvas`, and in its `play` throws `Bit`s — pieces of plotted art that fly, fall, flutter, bounce
## and leave — and draws anything else it needs in `_draw_shape`. The house rules come with it:
##
## - **Whole pixels.** Art is plotted from text grids in the locked palette (`KEY`, the characters
##   `art/tools/pixel_sprite.py` uses, so a grid means the same thing everywhere) and drawn at the
##   2x every sprite is; lines are hard-edged.
## - **A dark rim on everything**, grown round the grid when it is plotted: it has to read on the
##   chroma green, on a dark desk and on a white skeleton alike.
## - **Nothing fades** (D68). A piece pops in and leaves by shrinking to nothing; a line draws in.
## - **Its own dice.** The suites seed the global generator per weapon, and a flourish must not move
##   what they measure (the burst pool's rule, `AbilityFX._rng`).

const OUTLINE := Color("141210")
const ART := 2.0

## The locked palette (`art/src/bonehead.gpl`), keyed as `pixel_sprite.py` keys it, and five inks
## beyond it for effects: water, pale water, lilac, gold and warmth. `K` is the effects' dark rim.
const KEY := {
	"K": Color("141210"), "k": Color("1a1d24"),
	"W": Color("ffffff"), "C": Color("fcfcee"), "c": Color("d8d6c4"),
	"A": Color("7fe3df"), "a": Color("2eb8b3"), "q": Color("1b7a76"),
	"Y": Color("f2d06b"), "O": Color("e8862c"), "R": Color("c8382e"), "r": Color("8a2420"),
	"P": Color("ffa6c1"), "p": Color("f06292"), "m": Color("a83a63"),
	"G": Color("c3cad8"), "g": Color("9aa3b8"), "h": Color("5a6172"), "H": Color("2a2e38"),
	"B": Color("c98f55"), "b": Color("a9713f"), "n": Color("6b4426"),
	"U": Color("2e8fd8"), "u": Color("9fdcff"), "V": Color("d9a0ff"), "y": Color("ffc247"),
	"o": Color("ffb37a"),
}

## One piece in the air: a plotted picture with a velocity, a spin and a life.
class Bit:
	var live := false
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var turn := 0.0
	var spin := 0.0
	var age := 0.0
	var life := 1.0
	## Seconds before it appears at all: a piece that joins a moment late.
	var wait := 0.0
	var tex: Texture2D
	var size := 1.0
	var gravity := 900.0
	## A fraction of its speed lost a second: air for a feather, none for a pin.
	var drag := 0.0
	## Where the desk is under it; INF for nothing to land on.
	var floor_y := INF
	var bounce := 0.3
	## Side to side, px, and how fast: a feather rocking down, confetti fluttering.
	var sway := 0.0
	var sway_hz := 1.5
	var phase := 0.0
	## Flips as it tumbles, the way a card or a paper square does.
	var flutter := false
	var flip := false
	## Lying still on the desk: it stops turning at the nearest flat side.
	var landed := false
	## Comes to rest on its side, never standing up: a pin knocked over.
	var lies := false
	## Goes at full size when its life is up, and says so (`_bit_died`): a bubble pops, it does not
	## shrink.
	var pops := false

## Where something has been, newest first: a fixed ring of points, sampled a frame at a time while
## the thing flies and eaten from the tail once it stops, so a trail draws in rather than fading.
class Trail:
	var points := PackedVector2Array()
	var head := -1
	var count := 0

	func _init(size: int) -> void:
		points.resize(size)

	func clear() -> void:
		count = 0
		head = -1

	func add(p: Vector2) -> void:
		head = (head + 1) % points.size()
		points[head] = p
		count = mini(count + 1, points.size())

	## The `i`th newest point, 0 the newest.
	func at(i: int) -> Vector2:
		return points[(head - i + points.size() * 2) % points.size()]

	## Loses its oldest `n` points.
	func shorten(n: int) -> void:
		count = maxi(0, count - n)

var clock := 0.0
var rng := RandomNumberGenerator.new()
var bits: Array[Bit] = []
var _next_bit := 0
var _until := 0.0
var _textures := {}
var _world := Transform2D.IDENTITY

## The canvas called `node_name` under `afx`, or one built from `script` the first time: named, so
## the next play finds it and the remote tree can read it.
static func canvas(afx: AbilityFX, node_name: String, script: GDScript) -> Node2D:
	var known := afx.get_node_or_null(node_name) as Node2D
	if known:
		return known
	var made: Node2D = script.new()
	made.name = node_name
	afx.add_child(made)
	return made

func _ready() -> void:
	set_process(false)
	visible = false
	rng.seed = hash(String(name))

## How many pieces it can have in the air at once, built here once.
func reserve(count: int) -> void:
	while bits.size() < count:
		bits.append(Bit.new())

## Keeps drawing for at least `seconds` more.
func hold(seconds: float) -> void:
	_until = maxf(_until, clock + seconds)
	visible = true
	set_process(true)
	queue_redraw()

func is_drawing() -> bool:
	return is_processing()

func _process(delta: float) -> void:
	clock += delta
	_step_bits(delta)
	_advance(delta)
	if clock >= _until:
		for bit in bits:
			bit.live = false
		visible = false
		set_process(false)
		_parked()
		return
	queue_redraw()

## The shape's own step, every frame it draws, after its pieces have moved.
func _advance(_delta: float) -> void:
	pass

## Everything it drew is over and it is hidden again.
func _parked() -> void:
	pass

# --- pieces ---------------------------------------------------------------------------------

## The next piece, reset and thrown: `tex` at `pos` with `vel`, living `life` seconds.
func throw(tex: Texture2D, pos: Vector2, vel: Vector2, life: float, gravity: float = 900.0) -> Bit:
	var bit := bits[_next_bit]
	_next_bit = (_next_bit + 1) % bits.size()
	bit.live = true
	bit.tex = tex
	bit.pos = pos
	bit.vel = vel
	bit.life = life
	bit.gravity = gravity
	bit.age = 0.0
	bit.wait = 0.0
	bit.turn = 0.0
	bit.spin = 0.0
	bit.size = 1.0
	bit.drag = 0.0
	bit.floor_y = INF
	bit.bounce = 0.3
	bit.sway = 0.0
	bit.sway_hz = 1.5
	bit.phase = rng.randf() * TAU
	bit.flutter = false
	bit.flip = false
	bit.landed = false
	bit.pops = false
	bit.lies = false
	hold(life)
	return bit

func _step_bits(delta: float) -> void:
	for bit in bits:
		if not bit.live:
			continue
		if bit.wait > 0.0:
			bit.wait -= delta
			continue
		bit.age += delta
		if bit.age >= bit.life:
			bit.live = false
			if bit.pops:
				_bit_died(bit)
			continue
		bit.vel.y += bit.gravity * delta
		if bit.drag > 0.0:
			bit.vel *= maxf(0.0, 1.0 - bit.drag * delta)
		bit.pos += bit.vel * delta
		if bit.sway != 0.0:
			bit.pos.x += cos(bit.age * TAU * bit.sway_hz + bit.phase) * bit.sway * TAU * bit.sway_hz * delta
		if bit.landed:
			# Down on the desk: it settles on its nearest flat side and slides to a stop.
			var flat := roundf(bit.turn / (PI * 0.5)) * PI * 0.5
			if bit.lies:
				flat = (floorf(bit.turn / PI) + 0.5) * PI
			bit.turn = lerp_angle(bit.turn, flat, minf(1.0, delta * 14.0))
			bit.vel.x *= maxf(0.0, 1.0 - 5.0 * delta)
		else:
			bit.turn += bit.spin * delta
		if bit.pos.y > bit.floor_y:
			bit.pos.y = bit.floor_y
			if absf(bit.vel.y) > 120.0:
				bit.vel.y = -bit.vel.y * bit.bounce
				bit.vel.x *= 0.7
				bit.spin *= -0.6
			else:
				bit.vel.y = 0.0
				bit.landed = true

## A piece that `pops` has reached the end of its life, where it is.
func _bit_died(_bit: Bit) -> void:
	pass

## How big a piece is now: grown in as it arrives, whole while it flies, and down to nothing over
## the last quarter of its life — or whole to the end, for one that pops.
func bit_scale(bit: Bit) -> float:
	var arrive := clampf(bit.age / 0.08, 0.0, 1.0)
	var grow := lerpf(0.4, 1.0, arrive) if arrive < 1.0 else 1.0
	if bit.pops:
		return bit.size * grow
	var leave := clampf((bit.life - bit.age) / maxf(bit.life * 0.25, 0.01), 0.0, 1.0)
	return bit.size * grow * leave

# --- drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	_world = get_global_transform().affine_inverse()
	draw_set_transform_matrix(_world)
	_draw_shape()
	for bit in bits:
		if not bit.live or bit.wait > 0.0:
			continue
		var flip := bit.flip
		if bit.flutter:
			flip = sin(bit.age * TAU * 3.0 + bit.phase) < 0.0
		stamp(bit.tex, bit.pos, bit_scale(bit), bit.turn, flip)
	draw_set_transform_matrix(Transform2D.IDENTITY)

## Whatever the shape draws besides its pieces, in world coordinates, under them.
func _draw_shape() -> void:
	pass

## A plotted picture at `at` (world), centred, at art scale times `k`, turned `turn`.
func stamp(tex: Texture2D, at: Vector2, k: float = 1.0, turn: float = 0.0, flip: bool = false) -> void:
	if tex == null or k <= 0.05:
		return
	var s := ART * k
	var xf := Transform2D(turn, Vector2(-s if flip else s, s), 0.0, at.round())
	draw_set_transform_matrix(_world * xf)
	draw_texture(tex, -(tex.get_size() * 0.5).floor())
	draw_set_transform_matrix(_world)

## A hard line with a dark rim under it.
func stroke(a: Vector2, b: Vector2, colour: Color, width: float) -> void:
	if width < 0.5:
		return
	draw_line(a.round(), b.round(), OUTLINE, width + 2.0)
	draw_line(a.round(), b.round(), colour, width)

## A hard polyline with a dark rim under it.
func strokes(points: PackedVector2Array, colour: Color, width: float) -> void:
	if points.size() < 2 or width < 0.5:
		return
	draw_polyline(points, OUTLINE, width + 2.0)
	draw_polyline(points, colour, width)

## A hard square blob: a chip, a drop, a crumb.
func dot(at: Vector2, half: float, colour: Color) -> void:
	var p := at.round()
	draw_rect(Rect2(p - Vector2(half + 1.0, half + 1.0), Vector2(half * 2.0 + 2.0, half * 2.0 + 2.0)), OUTLINE)
	draw_rect(Rect2(p - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), colour)

# --- art ----------------------------------------------------------------------------------------

## A grid plotted once and kept on this canvas: one character an art pixel from `KEY`, `.` nothing,
## with a one-pixel dark rim grown round all of its ink unless `rim` is false. `outside` grows it only
## on the outside of the shape, so a hollow thing — a bubble — stays hollow and light.
func picture(key: String, grid: Array, rim: bool = true, outside: bool = false) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	var h := grid.size()
	var w := 0
	for row in grid:
		w = maxi(w, String(row).length())
	var pad := 1 if rim else 0
	var image := Image.create_empty(w + pad * 2, h + pad * 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var out := _outside(grid, w, h, pad) if rim and outside else PackedByteArray()
	if rim:
		for y in h:
			var row := String(grid[y])
			for x in row.length():
				if row[x] == "." or row[x] == " ":
					continue
				for dy in 3:
					for dx in 3:
						var px := x + dx
						var py := y + dy
						var outer := out.is_empty() or out[py * (w + pad * 2) + px] == 1
						if outer and image.get_pixel(px, py).a < 0.5:
							image.set_pixel(px, py, OUTLINE)
	for y in h:
		var row := String(grid[y])
		for x in row.length():
			var c := row[x]
			if KEY.has(c):
				image.set_pixel(x + pad, y + pad, KEY[c])
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture

## The same grid with one ink swapped for another: a pin with its stripes in the tier colour.
func recolour(grid: Array, from: String, to: String) -> Array:
	var out: Array = []
	for row in grid:
		out.append(String(row).replace(from, to))
	return out

## Fewer pieces at Subtle: a moment made smaller, never removed.
static func count(n: int) -> int:
	if Settings.focus_intensity == Settings.Intensity.SUBTLE:
		return maxi(1, n / 2)
	return n

## Which pixels of a padded grid are outside the shape: reached from the border without crossing ink.
func _outside(grid: Array, w: int, h: int, pad: int) -> PackedByteArray:
	var width := w + pad * 2
	var height := h + pad * 2
	var out := PackedByteArray()
	out.resize(width * height)
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height or out[p.y * width + p.x] == 1:
			continue
		var gx := p.x - pad
		var gy := p.y - pad
		if gx >= 0 and gy >= 0 and gy < h and gx < String(grid[gy]).length():
			var c := String(grid[gy])[gx]
			if c != "." and c != " ":
				continue
		out[p.y * width + p.x] = 1
		stack.append(p + Vector2i.RIGHT)
		stack.append(p + Vector2i.LEFT)
		stack.append(p + Vector2i.DOWN)
		stack.append(p + Vector2i.UP)
	return out

## `grid` with one ink swapped for another, plotted once under `key`: confetti in six colours from one
## grid, beads in the beach ball's panels.
func tinted(key: String, grid: Array, from: String, to: String) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	return picture(key, recolour(grid, from, to))
