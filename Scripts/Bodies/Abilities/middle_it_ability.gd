class_name MiddleItAbility
extends StunAbility

## The cricket bat's middle lights up, and a hit off it is a six (D74): Middle It.
##
## A tap. For `armed_seconds` a band across the middle of the face glows — `middle_band` of the
## blade's length, centred on it — and sparkles. A hit he takes off that band is billed at
## `middle_mult` on top of the bat's own multiplier (he reads `hit_multiplier` when he attributes
## the contact, D7) and sends him **straight up**: on the tick after, from `_physics_process` and
## before `Buddy.StepStart` (D64), his sideways speed is mostly taken off and he is given
## `six_speed` upward. Where he comes down is the bat's for `claim_seconds` (D65). A hit off the
## edge, or the toe, or the splice, is an ordinary hit and a dry click, and the middle stays lit
## for the rest of the window — so it is a thing you aim, not a thing you arm.
##
## The bat's opposite numbers: the Home Run is a wind-up you time and a throw at 38 degrees; the
## BONG is any hit and a daze. This is where on the bat, and up.
##
## **Where the blade met him** is read from the geometry at the moment he attributes the hit —
## the stretch of the blade's axis within reach of his collider — cached for the physics frame, so
## the multiplier recorded for the hit and the one he bills are the same number. It is the middle
## if that stretch reaches the lit band: the face through him, not its toe grazing his skull nor
## its handle arriving first. Measured on hand heights: the first rule (the stretch's own midpoint
## in the band) middled a 16 px window of them; this one is the width of the band.
##
## Row: `armed_seconds`, `middle_band`, `middle_mult`, `six_speed`, `keep_sideways`,
## `claim_seconds`.

const SAMPLES := 16

var _blade_from := Vector2.ZERO
var _blade_to := Vector2.ZERO
var _blade_half_width := 12.0
var _frame := -1
var _frame_middled := false
var _six_pending := false
## After a six: he and the bat do not collide until he is clear of it, or the bat still in the
## swing would stop him going up — it did, at 43 px.
var _clearing := -1.0
var _excepted: Buddy
var _glow: Glow
var _sparkle: GPUParticles2D
var _edges := 0

## For the suites: where on the blade the last hit met him (0 the shoulder, 1 the toe), whether
## it was the middle, and how fast the six sent him up.
var last_blade_t := -1.0
var last_blade_from := -1.0
var last_blade_to := -1.0
var last_middled := false
var last_six := 0.0
var sixes := 0

func _ready() -> void:
	super._ready()
	_learn_blade()

func is_armed() -> bool:
	return _active and not _six_pending and _clearing < 0.0

## Read by him as he bills a hit, and by `note_hit` a line before: both in the same physics frame,
## so the same answer. Not gated on the six being pending — the middled hit that set it is still
## being billed when it is.
func hit_multiplier() -> float:
	if not _active or _clearing >= 0.0:
		return 1.0
	return num("middle_mult", 2.5) if _middled_now() else 1.0

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(_left / maxf(num("armed_seconds", 1.5), 0.01), 0.0, 1.0)

## The blade, from the bat's own main collider: the long axis of its biggest box, shoulder (the
## end nearer the grip) to toe.
func _learn_blade() -> void:
	if body == null or body.collider == null or body.collider.shape == null:
		return
	var rect := body.collider.shape.get_rect()
	var xf := body.collider.transform
	var long_is_y := rect.size.y >= rect.size.x
	var half := rect.size * 0.5
	var a := rect.get_center() + (Vector2(0, half.y) if long_is_y else Vector2(half.x, 0))
	var b := rect.get_center() - (Vector2(0, half.y) if long_is_y else Vector2(half.x, 0))
	a = xf * a
	b = xf * b
	# Shoulder first: the end nearer the grip.
	if a.distance_to(body.grip_offset) <= b.distance_to(body.grip_offset):
		_blade_from = a
		_blade_to = b
	else:
		_blade_from = b
		_blade_to = a
	_blade_half_width = (rect.size.x if long_is_y else rect.size.y) * 0.5 * xf.get_scale().x

## Where along the blade (0 shoulder .. 1 toe) the local point is.
func blade_t_of(world: Vector2) -> float:
	var a := body.to_global(_blade_from)
	var b := body.to_global(_blade_to)
	var ab := b - a
	return clampf((world - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)

func middle_world() -> Vector2:
	return body.to_global(_blade_from.lerp(_blade_to, 0.5))

## Where the blade meets him now: the stretch of its axis within reach of his collider, and that
## stretch's middle. Once per physics frame; `note_hit` and his attribution read the same answer.
func _middled_now() -> bool:
	var frame := Engine.get_physics_frames()
	if frame == _frame:
		return _frame_middled
	_frame = frame
	_frame_middled = false
	var him := buddy()
	if him == null:
		return false
	var rect := him.get_interaction_rect().grow(_blade_half_width + 4.0)
	var a := body.to_global(_blade_from)
	var b := body.to_global(_blade_to)
	var lo := 2.0
	var hi := -1.0
	var nearest := 0.0
	var best := INF
	for i in SAMPLES + 1:
		var t := float(i) / float(SAMPLES)
		var p := a.lerp(b, t)
		if rect.has_point(p):
			lo = minf(lo, t)
			hi = maxf(hi, t)
		var d := _rect_distance(rect, p)
		if d < best:
			best = d
			nearest = t
	var half := num("middle_band", 0.34) * 0.5
	if hi < lo:
		# Nothing of the blade inside him: the nearest point of it is where it touched.
		lo = nearest
		hi = nearest
	last_blade_t = (lo + hi) * 0.5
	last_blade_from = lo
	last_blade_to = hi
	# The middle is on him if the stretch of the blade that is in him reaches the lit band: a blade
	# through his middle is middled even though its shoulder is in him too; a toe grazing his skull
	# or a handle arriving first is not.
	_frame_middled = hi >= 0.5 - half and lo <= 0.5 + half
	return _frame_middled

static func _rect_distance(rect: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return Vector2(dx, dy).length()

func _on_press() -> void:
	_left = num("armed_seconds", 1.5)
	_six_pending = false
	_clearing = -1.0
	_edges = 0
	last_middled = false
	last_six = 0.0
	run(true)
	if _glow == null:
		_glow = Glow.new()
		_glow.name = "MiddleGlow"
		_glow.z_index = 1
		body.add_child(_glow)
	_glow.set_band(_blade_from, _blade_to, num("middle_band", 0.34), _blade_half_width)
	_glow.visible = true
	_glow.set_process(true)
	_sparkle = emitter("middle", &"star", WorldFX.GOLD, 5, _blade_from.lerp(_blade_to, 0.5),
		Vector2(0, -40), 180.0, 0.5, Vector2.ZERO, true)
	emit_from(_sparkle, true)
	sound(&"plink", -10.0, 1.5)
	sound(&"tock", -14.0, 0.9)
	var fx := fx()
	if fx:
		fx.ring(middle_world(), 30.0, WorldFX.GOLD, 0.16, 2.0)
	_update_pip()

## A hit landed on him while it glowed: it was the middle if it was billed at the middle's
## multiplier, which `note_hit` recorded a line ago.
func _on_hit() -> void:
	if _six_pending:
		return
	var middled: bool = not billed.is_empty() and billed.back() > 1.0
	last_middled = middled
	if middled:
		_six_pending = true
	else:
		_edges += 1
		_edge_pending = true

var _edge_pending := false

func _on_tick(delta: float) -> void:
	if _clearing >= 0.0:
		_clearing += delta
		if _clearing >= 0.12 and (not overlaps_him() or _clearing >= 0.6):
			finish()
		return
	if _six_pending:
		_six()
		return
	if _edge_pending:
		_edge_pending = false
		var fx := fx()
		if fx:
			fx.puff(middle_world(), 3, WorldFX.DUST, 40.0, 0.3)
		sound(&"tock", -10.0, 1.9)
	_left -= delta
	if _left <= 0.0:
		# The light went out with nothing off the middle: half a cooldown.
		finish(num("cooldown", 5.0) * 0.5)

## Off the middle, on the tick after the hit: up he goes.
func _six() -> void:
	_six_pending = false
	var him := buddy()
	var at := middle_world()
	if him:
		var v := him.linear_velocity
		var up := num("six_speed", 950.0)
		var want := Vector2(v.x * num("keep_sideways", 0.3), -up)
		# One impulse, from the tick, before StepStart (D64): through his centre of mass (D54).
		him.apply_central_impulse((want - v) * him.mass)
		him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 2.5))
		body.add_collision_exception_with(him)
		_excepted = him
		last_six = up
		at = him.get_interaction_rect().get_center()
	sixes += 1
	payoffs += 1
	var fx := fx()
	if fx:
		fx.ring(at, 110.0, WorldFX.GOLD, 0.4, 4.0)
		fx.ring(at, 60.0, Color.WHITE, 0.25, 3.0)
		fx.burst(at, &"star", WorldFX.GOLD, 8, 380.0)
		fx.tracer(at, at + Vector2(0, -260), Color.WHITE, 0.3, 4.0)
		fx.shake(6.0)
	sound(&"crack", -2.0, 0.78)
	sound(&"tock", -4.0, 0.62)
	sound(&"applause", -6.0, 1.0)
	tell(&"six", at)
	paid_off.emit(&"six")
	emit_from(_sparkle, false)
	if _glow:
		_glow.visible = false
		_glow.set_process(false)
	_clearing = 0.0

func _on_dropped() -> void:
	# The middle only glows in the hand; a six already hit is already gone.
	if _clearing < 0.0:
		finish(num("cooldown", 5.0) * 0.5)

func _on_stop() -> void:
	_six_pending = false
	_edge_pending = false
	_clearing = -1.0
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null
	emit_from(_sparkle, false)
	if _glow:
		_glow.visible = false
		_glow.set_process(false)

## The lit middle: a band across the face, over the sprite, breathing between white and gold, with
## a bright rim at each end so it reads as a place on the bat rather than a tint.
class Glow extends Node2D:
	var _rect := Rect2()
	var _angle := 0.0
	var _t := 0.0

	func set_band(from: Vector2, to: Vector2, band: float, half_width: float) -> void:
		var middle := from.lerp(to, 0.5)
		var length := from.distance_to(to) * band
		_angle = (to - from).angle() - PI * 0.5
		position = middle
		rotation = _angle
		_rect = Rect2(-half_width + 2.0, -length * 0.5, half_width * 2.0 - 4.0, length).abs()
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var k := 0.5 + 0.5 * sin(_t * 9.0)
		var fill := Color("fff4c2").lerp(Color("ffc247"), k)
		fill.a = 0.55
		draw_rect(_rect, fill)
		draw_rect(Rect2(_rect.position, Vector2(_rect.size.x, 2.0)), Color.WHITE)
		draw_rect(Rect2(Vector2(_rect.position.x, _rect.end.y - 2.0), Vector2(_rect.size.x, 2.0)), Color.WHITE)
