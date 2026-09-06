class_name Backdrop
extends CanvasLayer
## What is behind him, when it is not the desktop (docs/decisions.md D38).
##
## The overlay is transparent by design, and stays the default. But not everyone wants their
## wallpaper in the game — a streamer wants a key colour, a player in a play-area window wants
## a room, a player with a busy desktop wants a flat wall. This layer sits under the world and
## paints one of a fixed set of backdrops the size of the window, whatever the window is: a
## flat colour, or a scene drawn from the window's own rect with whole-pixel blocks, so it is
## as chunky on a 3440-wide monitor as in a 480-wide play area, and never a stretched picture.
##
## Every backdrop is dark or mid-toned. The buddy is white, the cards are cream and the
## payout numbers are the palette's inks — a cream or white backdrop would swallow all three.
##
## "Desktop" hides the layer entirely, and the window is exactly as transparent as before.

const LAYER := -10

## The whole menu, in the order the settings page shows it. Two rows: flat colours, scenes.
## `kind` picks the painter; a flat one carries its colour, a scene carries its palette.
const CHOICES: Array[Dictionary] = [
	{"id": &"transparent", "name": "Desktop", "kind": &"none", "row": 0},
	{"id": &"slate", "name": "Slate", "kind": &"flat", "row": 0, "colour": Color("45474f")},
	{"id": &"charcoal", "name": "Charcoal", "kind": &"flat", "row": 0, "colour": Color("2a2b30")},
	{"id": &"forest", "name": "Forest", "kind": &"flat", "row": 0, "colour": Color("2f4a3a")},
	{"id": &"plum", "name": "Plum", "kind": &"flat", "row": 0, "colour": Color("4a3046")},
	{"id": &"navy", "name": "Navy", "kind": &"flat", "row": 0, "colour": Color("263247")},
	# Pure key green, for a stream: the colour `Settings.streamer_bg_color` was reserved for.
	{"id": &"chroma", "name": "Chroma", "kind": &"flat", "row": 0, "colour": Color(0.0, 1.0, 0.0)},
	{"id": &"night", "name": "Night sky", "kind": &"night", "row": 1},
	{"id": &"dusk", "name": "Dusk", "kind": &"dusk", "row": 1},
	{"id": &"hills", "name": "Hills", "kind": &"hills", "row": 1},
	{"id": &"paper", "name": "Graph paper", "kind": &"paper", "row": 1},
	{"id": &"desk", "name": "Desk", "kind": &"desk", "row": 1},
]
const DEFAULT := &"transparent"

## The scene palettes. Hard bands and silhouettes, never a smooth gradient: a gradient is
## the one thing that cannot be pixel art.
const NIGHT := [Color("1a1d2e"), Color("222741"), Color("2b3152")]
const STAR := Color("d9d2b0")
const DUSK := [Color("2b2340"), Color("4a2f52"), Color("7a3d5a"), Color("a8535a"),
	Color("c8744f"), Color("d9944f"), Color("3a3040")]
const HILLS_SKY := Color("3a4f63")
const HILLS := [Color("2f4a3a"), Color("263c30"), Color("1c2c24")]
const PAPER := Color("3e4a55")
const PAPER_LINE := Color("4c5a67")
const PAPER_RULE := Color("5a6a78")
const WALL := Color("54604e")
const SKIRTING := Color("3e4a3a")
const DESK := Color("6b4a2e")
const DESK_EDGE := Color("4a331f")
const DESK_TOP := Color("805630")

var _canvas: Control
var _choice: Dictionary = CHOICES[0]

static func choice(id: StringName) -> Dictionary:
	for entry in CHOICES:
		if entry["id"] == id:
			return entry
	return CHOICES[0]

static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in CHOICES:
		out.append(entry["id"])
	return out

func _ready() -> void:
	layer = LAYER
	add_to_group(&"backdrop")
	_canvas = Control.new()
	_canvas.name = "Canvas"
	# Full-rect and on a CanvasLayer: this MUST ignore the mouse, or it eats every click in
	# the game (CLAUDE.md). `ui_check` sweeps for exactly this.
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_paint)
	# The picture is a function of the rect, so a resize has to repaint. A Control does not
	# redraw on resize by itself — and the window's own resize lands after `size_changed`.
	_canvas.resized.connect(_canvas.queue_redraw)
	add_child(_canvas)
	OverlayManager.window_rect_changed.connect(func(_rect: Rect2i) -> void: _canvas.queue_redraw())
	EventBus.backdrop_changed.connect(apply)
	apply(Settings.backdrop)

func apply(id: StringName) -> void:
	_choice = choice(id)
	visible = _choice["kind"] != &"none"
	if visible:
		_canvas.queue_redraw()

func current() -> StringName:
	return _choice["id"]

# --- painting --------------------------------------------------------------

## One art pixel, in screen pixels: chosen from the window height so a scene keeps its
## proportions from a 480px play area to a 1440px monitor.
func _block(size: Vector2) -> float:
	return maxf(2.0, floorf(size.y / 240.0))

func _paint() -> void:
	var size := _canvas.size
	if size.x < 1.0 or size.y < 1.0:
		return
	match _choice["kind"]:
		&"flat":
			_canvas.draw_rect(Rect2(Vector2.ZERO, size), _choice["colour"], true)
		&"night":
			_paint_night(size)
		&"dusk":
			_paint_dusk(size)
		&"hills":
			_paint_hills(size)
		&"paper":
			_paint_paper(size)
		&"desk":
			_paint_desk(size)

func _paint_night(size: Vector2) -> void:
	var px := _block(size)
	# Three bands of sky, darkest at the top, and a scatter of stars from a fixed seed so
	# the same sky comes back every night. Star count follows the area, not the count, so a
	# wide monitor is not sparser than a small window.
	var bands := NIGHT.size()
	for i in bands:
		var top := size.y * float(i) / float(bands)
		_canvas.draw_rect(Rect2(0.0, top, size.x, size.y / float(bands) + 1.0), NIGHT[i], true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0B0E5
	var count := int(size.x * size.y / 9000.0)
	for _i in count:
		var at := Vector2(floorf(rng.randf() * size.x / px) * px, floorf(rng.randf() * size.y * 0.8 / px) * px)
		var big := rng.randf() < 0.12
		var dim := rng.randf() < 0.4
		var colour := STAR.darkened(0.35) if dim else STAR
		if big:
			_canvas.draw_rect(Rect2(at.x - px, at.y, px * 3.0, px), colour, true)
			_canvas.draw_rect(Rect2(at.x, at.y - px, px, px * 3.0), colour, true)
		else:
			_canvas.draw_rect(Rect2(at, Vector2(px, px)), colour, true)

func _paint_dusk(size: Vector2) -> void:
	# The sky in hard bands, the ground the last one. Band edges snap to the block grid.
	var px := _block(size)
	var sky := DUSK.size() - 1
	var horizon := floorf(size.y * 0.78 / px) * px
	for i in sky:
		var top := floorf(horizon * float(i) / float(sky) / px) * px
		var bottom := floorf(horizon * float(i + 1) / float(sky) / px) * px
		_canvas.draw_rect(Rect2(0.0, top, size.x, bottom - top + 1.0), DUSK[i], true)
	_canvas.draw_rect(Rect2(0.0, horizon, size.x, size.y - horizon), DUSK[sky], true)
	# A sun, half set: a stepped disc, which is what a circle is at this resolution.
	var radius := floorf(size.y * 0.09 / px) * px
	var centre := Vector2(floorf(size.x * 0.68 / px) * px, horizon)
	var y := -radius
	while y < 0.0:
		var half := floorf(sqrt(maxf(radius * radius - y * y, 0.0)) / px) * px
		_canvas.draw_rect(Rect2(centre.x - half, centre.y + y, half * 2.0, px), Color("f2c66b"), true)
		y += px

func _paint_hills(size: Vector2) -> void:
	var px := _block(size)
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), HILLS_SKY, true)
	# Three ridges, each a sum of two sines sampled once per block and filled as columns —
	# nearer ridges lower and darker. Phase is fixed, so the hills do not move when the
	# window does; they are cut off, as a window onto a landscape would be.
	for layer_index in HILLS.size():
		var base := size.y * (0.52 + 0.14 * float(layer_index))
		var amplitude := size.y * (0.11 - 0.02 * float(layer_index))
		var wave := 0.006 + 0.003 * float(layer_index)
		var x := 0.0
		while x < size.x:
			var h := base - amplitude * (0.6 * sin(x * wave + float(layer_index) * 1.7)
				+ 0.4 * sin(x * wave * 2.3 + float(layer_index) * 0.9))
			var top := floorf(h / px) * px
			_canvas.draw_rect(Rect2(x, top, px, size.y - top), HILLS[layer_index], true)
			x += px

func _paint_paper(size: Vector2) -> void:
	# A grid every eight blocks with a heavier rule every forty: engineer's paper, in the
	# skin's blue-grey rather than white, because white is his colour.
	var px := _block(size)
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), PAPER, true)
	var cell := px * 8.0
	var x := 0.0
	var column := 0
	while x < size.x:
		_canvas.draw_rect(Rect2(x, 0.0, px, size.y), PAPER_RULE if column % 5 == 0 else PAPER_LINE, true)
		x += cell
		column += 1
	var y := 0.0
	var row := 0
	while y < size.y:
		_canvas.draw_rect(Rect2(0.0, y, size.x, px), PAPER_RULE if row % 5 == 0 else PAPER_LINE, true)
		y += cell
		row += 1

func _paint_desk(size: Vector2) -> void:
	# A wall and a desk, which is where he lives. The desk top is the bottom quarter of the
	# window in every mode — the floor the world generates is at the window's bottom edge, so
	# he is always standing on it rather than floating in front of it.
	var px := _block(size)
	var desk_top := floorf(size.y * 0.74 / px) * px
	_canvas.draw_rect(Rect2(0.0, 0.0, size.x, desk_top), WALL, true)
	_canvas.draw_rect(Rect2(0.0, desk_top - px * 3.0, size.x, px * 3.0), SKIRTING, true)
	_canvas.draw_rect(Rect2(0.0, desk_top, size.x, px * 4.0), DESK_TOP, true)
	_canvas.draw_rect(Rect2(0.0, desk_top + px * 4.0, size.x, size.y - desk_top), DESK, true)
	_canvas.draw_rect(Rect2(0.0, desk_top + px * 4.0, size.x, px), DESK_EDGE, true)
	# Wood grain: a few long dashes at fixed places, one block tall.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDE5C
	for _i in int(size.x / 40.0):
		var at := Vector2(floorf(rng.randf() * size.x / px) * px,
			desk_top + px * 6.0 + floorf(rng.randf() * (size.y - desk_top - px * 8.0) / px) * px)
		_canvas.draw_rect(Rect2(at, Vector2(px * (4.0 + floorf(rng.randf() * 6.0)), px)), DESK_EDGE, true)
