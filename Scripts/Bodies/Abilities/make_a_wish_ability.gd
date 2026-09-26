class_name MakeAWishAbility
extends ChargeAbility

## The birthday cake's Make a Wish (docs/decisions.md D78): hold it up to him and the candles burn
## brighter; let go, and he shuts his eyes, takes a breath, and blows them out.
##
## The Home Run's archetype, turned to a birthday. Held within `reach` of his face — and not on it,
## or he eats it, as he always has — right held **gathers the wish** over `charge_seconds`: the three
## flames drawn on the cake swell and flicker brighter, sparkles gather over it, and the pip fills.
## Let go at `min_charge` or more and he makes his wish: eyes shut and a deep breath (his `wishing`
## row, the chest-out `puff`), and `blow_delay` later he **blows them out** — the flames are gone from
## the picture, a wisp of smoke rises off each wick, and a burst of stars goes up over his head. The
## wish is one act of kindness, `wish_value` — the only value it adds; the cake still pays its whole
## helping when he eats it. Let go too early and the flames settle back, and nothing is wished.
##
## The candles relight themselves when the cooldown is up, one spark a wick, so the wish can be made
## again for as long as the cake is uneaten.
##
## The flames are part of the cake's own art. "Blown out" is the same picture with `flame_rows` (art
## pixels, top to bottom) cleared, made once per texture and kept; the wicks' smoke rises from
## `wicks`, also in art pixels.
##
## Row: `reach`, `charge_seconds`, `min_charge`, `blow_delay`, `wish_value`, `flame_rows`, `wicks`.

const WISHING := 10
const FLAME := Color("ffd166")
const SMOKE := Color("8a8478")

## The blown-out copy of this cake's picture, made the first time it is blown out and kept for as
## long as the cake is. Not in a static: a static holding a texture keeps it past shutdown, where it
## reads as a leak (AbilityTable's note, and ExplosionUtil's).
var _unlit: Texture2D

var _lit_texture: Texture2D
var _blown := false
var _glow: Glow
var _gather: GPUParticles2D
var _wait := 0.0

## For the suites: wishes made, whether the candles are out, and how full the last wish was.
var wishes := 0
var fizzled := 0
var last_charge := 0.0

func hit_multiplier() -> float:
	return 1.0

func is_blown_out() -> bool:
	return _blown

func pip_fill() -> float:
	return _charge if _active and _phase == WINDING else -1.0

## His face: the top quarter of him, where a candle is blown out from.
func _face(him: Buddy) -> Vector2:
	var rect := him.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.25)

func _can_start() -> bool:
	var him := buddy()
	if him == null or _blown:
		return false
	return com_world().distance_to(_face(him)) <= num("reach", 260.0)

func _on_press() -> void:
	_phase = WINDING
	_charge = 0.0
	_full = false
	_next_click = 0.0
	_wait = 0.0
	run(true)
	notice_player()
	if _glow == null:
		_glow = Glow.new()
		_glow.name = "WishGlow"
		_glow.z_index = 2
		var s := sprite()
		if s:
			s.add_child(_glow)
		else:
			body.add_child(_glow)
	_glow.points = _wick_points()
	_glow.visible = true
	_glow.strength = 0.0
	_gather = emitter("wish", &"star", FLAME, 8, body.to_local(_wicks_world_centre()) + Vector2(0, -10),
		Vector2(0, -30), 180.0, 0.6)
	emit_from(_gather, true)
	sound(&"bless", -18.0, 1.4)
	AbilityCues.activation(self, _wicks_world_centre())
	_update_pip()

func _on_tick(delta: float) -> void:
	if _phase == WINDING:
		_charge = minf(1.0, _charge + delta / maxf(num("charge_seconds", 1.2), 0.05))
		if _glow:
			_glow.strength = _charge
			_glow.flicker = randf()
			_glow.queue_redraw()
		if _charge >= 1.0 and not _full:
			_full = true
			sound(&"plink", -8.0, 1.5)
			var fx := fx()
			if fx:
				fx.ring(_wicks_world_centre(), 22.0, FLAME, 0.2, 2.0)
		return
	# He has shut his eyes and taken his breath: then the candles go out.
	_wait -= delta
	if _wait <= 0.0:
		_blow()
		finish()

func _on_release(_seconds: float) -> void:
	if _phase != WINDING:
		return
	if _charge < num("min_charge", 0.6):
		# Not held long enough to wish on: the flames settle back.
		_fizzle()
		return
	emit_from(_gather, false)
	last_charge = _charge
	_phase = WISHING
	_wait = num("blow_delay", 0.45)
	var him := buddy()
	if him:
		tell(&"wish", _face(him))

## The focus went with right held (D70): nothing is wished on a release that never came — the flames
## settle back, as for a wish let go too early.
func _on_focus_lost() -> bool:
	if _phase != WINDING:
		return false
	_fizzle()
	return true

## Let go of mid-wish, the cake is still where it was: the wish goes ahead. Let go of while gathering,
## it is a fizzle — a cake put down is not a wish made.
func _on_dropped() -> void:
	if _phase == WINDING:
		_fizzle()

## Nothing wished: the flames settle back, and a short wait.
func _fizzle() -> void:
	emit_from(_gather, false)
	fizzled += 1
	_rest_glow()
	finish(num("cooldown", 6.0) * 0.25)

## Out: the flames gone from the picture, smoke off every wick, stars over his head, and the wish.
func _blow() -> void:
	var s := sprite() as Sprite2D
	_rest_glow()
	if s and s.texture:
		_lit_texture = s.texture
		s.texture = _unlit_for(s.texture)
	_blown = true
	wishes += 1
	var fx := fx()
	for p in _wick_points_world():
		if fx:
			fx.puff(p, 3, SMOKE, 30.0, 0.9)
	var him := buddy()
	var over := _face(him) + Vector2(0, -50) if him else _wicks_world_centre()
	if fx:
		fx.burst(over, &"star", WorldFX.GOLD, 6 + 2 * body.juice_tier, 150.0, 0.8)
		fx.burst(over, &"heart", WorldFX.kind_colour(body.juice_tier), 3, 100.0, 0.7)
	give(num("wish_value", 8.0), over)
	sound(&"gust", -8.0, 1.3)
	sound(&"bless", -10.0, 1.0)
	AbilityCues.payoff(self, &"wish", over, "make a wish!")

## The cooldown is up: the candles relight, a spark a wick.
func _on_cooled() -> void:
	_relight(true)
	super._on_cooled()

func _relight(spark: bool) -> void:
	if not _blown:
		return
	_blown = false
	var s := sprite() as Sprite2D
	if s and _lit_texture:
		s.texture = _lit_texture
	if spark:
		var fx := fx()
		if fx:
			for p in _wick_points_world():
				fx.chips(p, FLAME, 2, 60.0)
		sound(&"ignite", -18.0, 1.6)

func _rest_glow() -> void:
	if _glow:
		_glow.visible = false
		_glow.strength = 0.0

func _on_stop() -> void:
	emit_from(_gather, false)
	_rest_glow()

func _exit_tree() -> void:
	super._exit_tree()
	_relight(false)

## The wicks, in the sprite's own frame (art pixels to its centred, unscaled local space).
func _wick_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := sprite() as Sprite2D
	var size := s.texture.get_size() if s and s.texture else Vector2(64, 64)
	for w in row.get("wicks", []):
		var p: Vector2 = w
		out.append(p + Vector2(0.5, 0.5) - size * 0.5)
	return out

func _wick_points_world() -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := sprite()
	for p in _wick_points():
		out.append(s.to_global(p) if s else body.to_global(p))
	return out

func _wicks_world_centre() -> Vector2:
	var points := _wick_points_world()
	if points.is_empty():
		return com_world()
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())

## The same cake with its flames cleared: every pixel of `flame_rows`, made once and kept.
func _unlit_for(texture: Texture2D) -> Texture2D:
	if _unlit:
		return _unlit
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var rows: Vector2i = row.get("flame_rows", Vector2i(16, 19))
	for y in range(maxi(rows.x, 0), mini(rows.y + 1, image.get_height())):
		for x in image.get_width():
			image.set_pixel(x, y, Color(0, 0, 0, 0))
	_unlit = ImageTexture.create_from_image(image)
	return _unlit

## The flames swelling while the wish gathers: each candle's flame drawn over the art in whole art
## pixels, bigger at each third of the wish — a bud, a flame, a tall one — with a white heart and a
## dark rim, flickering a pixel side to side. In the sprite's frame, so it sits exactly on the art at
## any angle. Opaque, like everything on the chroma key: a soft halo read as a green smudge (D68).
class Glow extends Node2D:
	const FLAMES := [
		[".O.", "OYO", "OWO", ".O."],
		[".O.", ".O.", "OYO", "OYO", "YWY", "OWO", ".O."],
		[".O.", ".O.", ".O.", "OYO", "OYO", "YWY", "YWY", "OWO", ".O."],
	]
	const INK := {"O": Color("e8862c"), "Y": Color("f2d06b"), "W": Color("ffffff")}
	const RIM := Color("141210")

	var points := PackedVector2Array()
	var strength := 0.0
	var flicker := 0.0

	func _draw() -> void:
		if strength <= 0.0:
			return
		var grid: Array = FLAMES[clampi(int(strength * 3.0), 0, FLAMES.size() - 1)]
		var h := grid.size()
		var w := String(grid[0]).length()
		for i in points.size():
			# Its foot on the wick; a pixel either way as it flickers, the candles out of step.
			var sway := 1.0 if (flicker > 0.5) == (i % 2 == 0) else 0.0
			var origin := (points[i] + Vector2(-floorf(w * 0.5) + sway - 0.5, -float(h) + 1.5)).floor()
			for y in h:
				var row := String(grid[y])
				for x in w:
					if row[x] != ".":
						draw_rect(Rect2(origin + Vector2(x - 1, y - 1), Vector2(3, 3)), RIM)
			for y in h:
				var row := String(grid[y])
				for x in w:
					if row[x] != ".":
						draw_rect(Rect2(origin + Vector2(x, y), Vector2(1, 1)), INK[row[x]])