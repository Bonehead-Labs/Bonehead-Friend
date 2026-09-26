extends RefCounted

## The Curveball (the baseball, D78): the bend you can see, and the catch you can hear.
##
## **The pitch** (`pitch`, from the hook as it leaves the hand) leaves its seam behind it: a trail of
## red stitches, the baseball's own V's, laid along the path it actually took — so the late break
## down into his hands is drawn on the desk as a hook in a dotted line, which is the whole ability.
## The stitches are eaten from the tail once it is caught.
##
## **The catch** (`play`, the payoff) is a catcher's mitt: it pops out at his side with the ball
## in its pocket, dust thumping out of the leather and three lines driving in the way the ball came,
## and it stays up for as long as he holds the ball — then drops away as he throws it back. The mitt
## is beside him, never over his face; the ball is drawn in the pocket while the real one is hidden
## (`CurveballAbility`), so there is only ever one ball.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeCatchersMitt"

const MITT := [
	"....BBB.BBB.BBB..",
	"...BBBBBBBBBBBBB.",
	"..BBbBBbBBbBBbBB.",
	".YYBBbBBbBBbBBBBB",
	"YBYBBBBBBBBBBBBBB",
	"YBBYbbbbbbbbbbBBB",
	"YBBbbnnnnnnnbbBBB",
	".YBbnnnnnnnnnbBBB",
	".BBbnnnnnnnnnbBBB",
	".BBbnnnnnnnnnbBBn",
	".BBbbnnnnnnnbbBBn",
	"..BBbbbbbbbbbBBn.",
	"..BBBBBBBBBBBBBn.",
	"...nBcBcBcBcBn...",
	"....nnnnnnnnn....",
]
const BALL := [
	"..WWW..",
	".RWWWR.",
	"WRWWWRW",
	"WRWWWRW",
	"WRWWWRW",
	".RWWWR.",
	"..WWW..",
]
const DUST := ["cBc", "BCB", "cBc"]

## The seam trail, from the hand to wherever it is caught.
static func pitch(afx: AbilityFX, ability: WeaponAbility) -> void:
	if afx == null or not AbilityFX.moving():
		return
	(Moment.canvas(afx, NAME, Mitt) as Mitt).follow(ability)

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Mitt) as Mitt).catch(at, size, colour, ability)

## Whether the mitt is up (drawn in its pocket, the real ball hidden), for the hook.
static func holding(afx: AbilityFX) -> bool:
	var mitt := afx.get_node_or_null(NAME) as Mitt if afx else null
	return mitt != null and mitt.is_drawing() and mitt._mitt_on

class Mitt extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const STITCH_GAP := 13.0
	const POP_T := 0.12
	const DROP_T := 0.14

	var trail := Trail.new(26)
	var _ability: WeakRef
	var _tracking := false
	var _colour := Color.WHITE
	var _mitt_on := false
	var _mitt_at := Vector2.ZERO
	var _side := 1.0
	var _caught_at := -10.0
	var _dropped_at := -10.0
	var _in := Vector2.RIGHT
	var _k := 1.0

	func follow(ability: WeaponAbility) -> void:
		reserve(10)
		_ability = weakref(ability)
		trail.clear()
		_tracking = true
		hold(0.1)

	func _pitched() -> WeaponAbility:
		var ability := _ability.get_ref() as WeaponAbility if _ability else null
		return ability if ability and is_instance_valid(ability.body) else null

	func catch(at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
		reserve(10)
		_ability = weakref(ability)
		_colour = colour
		_k = lerpf(0.8, 1.0, size)
		_tracking = false
		var ball := at
		var him := ability.buddy() if ability else null
		if ability and ability.body:
			ball = ability.body.global_position
		_side = 1.0
		if him:
			_side = signf(ball.x - him.get_interaction_rect().get_center().x)
			if _side == 0.0:
				_side = 1.0
		# The way it came in: the last of its seam, or straight in from the side.
		_in = Vector2(_side * -1.0, 0.0)
		if trail.count >= 4:
			_in = (trail.at(0) - trail.at(3)).normalized()
		_mitt_at = ball + Vector2(_side * 24.0, 2.0)
		_mitt_on = true
		_caught_at = clock
		_dropped_at = -10.0
		var dust := picture("dust", DUST)
		for i in Moment.count(8):
			var a := TAU * float(i) / 8.0 + rng.randf_range(-0.2, 0.2)
			var bit := throw(dust, _mitt_at + Vector2(cos(a), sin(a)) * 8.0,
				Vector2(cos(a), sin(a)) * rng.randf_range(140.0, 230.0), rng.randf_range(0.3, 0.42), 0.0)
			bit.drag = 5.0
			bit.spin = rng.randf_range(-6.0, 6.0)
		hold(0.5)

	func _advance(_delta: float) -> void:
		var ability := _pitched()
		if _tracking:
			if ability and ability.has_method("is_pitching") and ability.call("is_pitching"):
				trail.add(ability.body.global_position)
				hold(0.1)
			else:
				_tracking = false
		if not _tracking and trail.count > 0:
			trail.shorten(2)
			hold(0.05)
		if _mitt_on:
			var held: bool = ability != null and ability.has_method("is_holding") and bool(ability.call("is_holding"))
			if held:
				_mitt_at = ability.body.global_position + Vector2(_side * 24.0, 2.0)
				hold(0.1)
			elif _dropped_at < 0.0:
				_dropped_at = clock
				hold(DROP_T)
			elif clock - _dropped_at >= DROP_T:
				_mitt_on = false

	func _parked() -> void:
		_mitt_on = false
		trail.clear()

	func _draw_shape() -> void:
		_draw_seam()
		if not _mitt_on:
			return
		var age := clock - _caught_at
		var k := 1.0
		if age < POP_T:
			# Thumped out past its size and back: it lands rather than appears.
			var p := age / POP_T
			k = lerpf(0.5, 1.3, p / 0.5) if p < 0.5 else lerpf(1.3, 1.0, (p - 0.5) / 0.5)
		if _dropped_at >= 0.0:
			k *= clampf(1.0 - (clock - _dropped_at) / DROP_T, 0.0, 1.0)
		# Three lines driving in the way the ball came, into the pocket.
		if age < 0.16:
			var run := lerpf(50.0, 10.0, age / 0.16)
			var across := Vector2(-_in.y, _in.x)
			for i in 3:
				var lane := across * (float(i) - 1.0) * 9.0
				var tip := _mitt_at - _in * 22.0 + lane
				stroke(tip - _in * run, tip, _colour, 2.0)
		stamp(picture("mitt", MITT), _mitt_at, k * _k, 0.0, _side < 0.0)
		# In the pocket.
		stamp(picture("ball", BALL), _mitt_at + Vector2(-_side, 2.0) * k * _k, k * _k)

	## The seam: red V's every few pixels back along the path, pointing the way it flew, smaller
	## toward the tail.
	func _draw_seam() -> void:
		if trail.count < 2:
			return
		var walked := 0.0
		var next := STITCH_GAP * 0.5
		var total := float(trail.count)
		for i in range(1, trail.count):
			var a := trail.at(i - 1)
			var b := trail.at(i)
			var leg := a.distance_to(b)
			if leg < 0.01:
				continue
			var dir := (a - b) / leg
			while walked + leg >= next:
				var p := a.lerp(b, (next - walked) / leg)
				var k := clampf(1.0 - float(i) / total, 0.35, 1.0)
				var back := -dir * 4.0 * k
				var side := Vector2(-dir.y, dir.x) * 4.0 * k
				stroke(p + back + side, p, KEY["R"], 2.0)
				stroke(p + back - side, p, KEY["R"], 2.0)
				next += STITCH_GAP
			walked += leg
