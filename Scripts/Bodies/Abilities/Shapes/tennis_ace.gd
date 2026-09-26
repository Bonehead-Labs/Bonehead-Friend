extends RefCounted

## The Serve (the tennis ball, D78): the stroke, the ball going flat and fast, and the ace on the line.
##
## **The stroke** (`serve`, from the hook the moment the release strikes it): a racket swings
## through the top of the toss — an oval frame strung in a lattice on a dark grip, sweeping over in a
## tenth of a second — and the ball leaves it.
##
## **The flight**: speed lines stream off the back of the ball and fuzzy ghosts of it hang in a row
## behind, as long as the serve was good: a feeble one leaves a short smear, an ace a long one.
##
## **The ace** (`play`, the payoff): a chalk line is drawn on the desk in front of him, where the ball
## came in, and the chalk jumps off it in a white puff — it was on the line — while its fuzz sprays off
## him where it hit. A serve that was not an ace only sprays its fuzz. The line stands on the floor
## with its centre mark up out of it, never across the floor line: the desk is often the window's
## bottom edge, where a line centred on it was a four-pixel sliver.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeTennisAce"

const BALL := [
	"..YYY..",
	".YYYWY.",
	"YYYWYYY",
	"YYWYYYY",
	"YYYWYYY",
	".YYYWY.",
	"..YYY..",
]
const CHALK := ["CWC", "WWW", "CWc"]
const FUZZ := ["Y"]

static func serve(afx: AbilityFX, ability: WeaponAbility, at: Vector2, heading: Vector2, timing: float) -> void:
	if afx == null or not AbilityFX.moving():
		return
	(Moment.canvas(afx, NAME, Ace) as Ace).swing(ability, at, heading, timing)

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Ace) as Ace).ace(at, size, colour, ability)

class Ace extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const SWING_T := 0.14
	const RACKET_OUT_T := 0.14
	const LINE_T := 0.7
	## The chalk line's height, standing on the floor, and its centre mark's above it.
	const LINE_TALL := 6.0
	const MARK_TALL := 7.0

	var trail := Trail.new(14)
	var _ability: WeakRef
	var _tracking := false
	var _timing := 1.0
	var _colour := Color("e8b83a")
	var _pivot := Vector2.ZERO
	var _from := 0.0
	var _to := 0.0
	var _swung_at := -10.0
	var _line_at := -10.0
	var _line := Vector2.ZERO
	var _line_half := 80.0

	func swing(ability: WeaponAbility, at: Vector2, heading: Vector2, timing: float) -> void:
		reserve(16)
		_ability = weakref(ability)
		_timing = timing
		_colour = ability.accent() if ability else _colour
		trail.clear()
		_tracking = true
		# The hand under and behind the ball; the head sweeps over it in the direction of the serve.
		var side := signf(heading.x) if absf(heading.x) > 0.01 else 1.0
		_pivot = at + Vector2(-side * 12.0, 52.0)
		var through := Vector2.UP.angle_to(at - _pivot)
		_from = through - side * 1.1
		_to = through + side * 0.7
		_swung_at = clock
		hold(SWING_T + RACKET_OUT_T + 0.05)

	func ace(at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
		reserve(16)
		_colour = colour
		_tracking = false
		var timing := float(ability.get("timing")) if ability and ability.get("timing") != null else 1.0
		var ace_from := float(ability.num("ace", 0.8)) if ability else 0.8
		var is_ace := timing >= ace_from
		# The fuzz off him where it struck, the way it was going.
		var sprays := 8 if is_ace else 5
		var fuzz := picture("fuzz", FUZZ)
		var heading := Vector2.RIGHT
		if trail.count >= 3:
			heading = (trail.at(0) - trail.at(2)).normalized()
		for i in Moment.count(sprays):
			var dir := heading.rotated(rng.randf_range(-1.6, 1.6))
			var bit := throw(fuzz, at, dir * rng.randf_range(120.0, 260.0), rng.randf_range(0.25, 0.4), 300.0)
			bit.drag = 4.0
		hold(0.3)
		if not is_ace:
			return
		# On the line: a chalk line on the desk in front of him, on the side it came from, clear of
		# his feet, and the chalk off it.
		var him := ability.buddy() if ability else null
		var from_side := -signf(heading.x) if absf(heading.x) > 0.01 else -1.0
		var floor_y := at.y + 50.0
		var centre_x := at.x + from_side * 70.0
		if him:
			var rect := him.get_interaction_rect()
			floor_y = rect.end.y
			centre_x = rect.get_center().x + from_side * (rect.size.x * 0.5 + 50.0)
		_line = Vector2(centre_x, floor_y).round()
		_line_half = lerpf(34.0, 46.0, size)
		_line_at = clock
		var chalk := picture("chalk", CHALK)
		for i in Moment.count(12):
			var x := _line.x + rng.randf_range(-_line_half * 0.7, _line_half * 0.7)
			var dir := Vector2(rng.randf_range(-0.6, 0.6), -1.0).normalized()
			var bit := throw(chalk, Vector2(x, _line.y - LINE_TALL - 1.0), dir * rng.randf_range(90.0, 230.0),
				rng.randf_range(0.45, 0.7), 260.0)
			bit.drag = 3.0
			bit.wait = rng.randf_range(0.0, 0.06)
		hold(LINE_T)

	func _advance(_delta: float) -> void:
		var ability := _ability.get_ref() as WeaponAbility if _ability else null
		if _tracking:
			if ability and is_instance_valid(ability.body) and ability.has_method("is_served") \
					and ability.call("is_served"):
				trail.add(ability.body.global_position)
				hold(0.1)
			elif clock - _swung_at > SWING_T:
				_tracking = false
		if not _tracking and trail.count > 0:
			trail.shorten(2)
			hold(0.05)

	func _parked() -> void:
		trail.clear()

	func _draw_shape() -> void:
		_draw_chalk_line()
		_draw_streak()
		_draw_racket()

	func _draw_racket() -> void:
		var age := clock - _swung_at
		if age < 0.0 or age > SWING_T + RACKET_OUT_T:
			return
		var turn := lerpf(_from, _to, clampf(age / SWING_T, 0.0, 1.0))
		var k := 1.0 if age <= SWING_T else clampf(1.0 - (age - SWING_T) / RACKET_OUT_T, 0.0, 1.0)
		if k <= 0.05:
			return
		var xf := Transform2D(turn, Vector2(k, k), 0.0, _pivot)
		var head := Vector2(0.0, -42.0)
		var rx := 14.0
		var ry := 18.0
		# The grip and throat, then the strings, then the frame over them.
		stroke(xf * Vector2.ZERO, xf * (head + Vector2(0.0, ry)), KEY["n"], 5.0 * k)
		for x in [-8.0, -3.0, 3.0, 8.0]:
			var h := ry * sqrt(1.0 - x * x / (rx * rx))
			draw_line((xf * (head + Vector2(x, -h))).round(), (xf * (head + Vector2(x, h))).round(), KEY["c"], 1.0)
		for y in [-10.0, -4.0, 2.0, 8.0]:
			var w := rx * sqrt(1.0 - y * y / (ry * ry))
			draw_line((xf * (head + Vector2(-w, y))).round(), (xf * (head + Vector2(w, y))).round(), KEY["c"], 1.0)
		var frame := PackedVector2Array()
		for i in 21:
			var a := TAU * float(i) / 20.0
			frame.append((xf * (head + Vector2(cos(a) * rx, sin(a) * ry))).round())
		strokes(frame, _colour, 4.0 * k)

	## Speed lines off the back of the ball and its fuzzy ghosts behind, as long as the serve was good.
	func _draw_streak() -> void:
		if trail.count < 3:
			return
		var tip := trail.at(0)
		var dir := (tip - trail.at(2)).normalized()
		if dir == Vector2.ZERO:
			return
		var across := Vector2(-dir.y, dir.x)
		var reach := lerpf(30.0, 110.0, _timing)
		var shown := mini(trail.count, 1 + int(round(lerpf(2.0, 9.0, _timing))))
		var tail := trail.at(shown - 1)
		var run := minf(reach, tip.distance_to(tail) + 10.0)
		for i in 3:
			var off := across * (float(i) - 1.0) * 7.0
			var start := tip - dir * (10.0 + 4.0 * absf(float(i) - 1.0))
			stroke(start + off, start + off - dir * run * (1.0 - 0.25 * absf(float(i) - 1.0)), _colour, 2.0)
		var ball := picture("ball", BALL)
		for g in [3, 6, 9]:
			if g >= shown:
				break
			stamp(ball, trail.at(g), lerpf(0.9, 0.45, float(g) / 9.0))

	func _draw_chalk_line() -> void:
		var age := clock - _line_at
		if age < 0.0 or age > LINE_T:
			return
		# Out from the middle in a blink, held, and drawn back in to the middle.
		var k := clampf(age / 0.08, 0.0, 1.0)
		if age > LINE_T - 0.15:
			k = clampf((LINE_T - age) / 0.15, 0.0, 1.0)
		var half := _line_half * k
		if half < 2.0:
			return
		# On the floor line and up from it, rim included: `_line.y` is the floor.
		var top := _line.y - LINE_TALL
		draw_rect(Rect2(Vector2(_line.x - half - 1.0, top - 1.0), Vector2(half * 2.0 + 2.0, LINE_TALL + 1.0)),
			OUTLINE)
		draw_rect(Rect2(Vector2(_line.x - half, top), Vector2(half * 2.0, LINE_TALL - 1.0)), KEY["W"])
		# The centre mark, standing up out of the middle of it: a court's line, not a bar.
		if half >= 8.0:
			var mark := MARK_TALL * k
			draw_rect(Rect2(Vector2(_line.x - 2.0, top - mark - 1.0), Vector2(4.0, mark + 1.0)), OUTLINE)
			draw_rect(Rect2(Vector2(_line.x - 1.0, top - mark), Vector2(2.0, mark + 1.0)), KEY["W"])
