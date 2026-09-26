extends RefCounted

## Keepy-Uppy (the beach ball, D78): the rally drawn in the ball's own panels, and a boing on his
## head every time he heads it.
##
## **The rally** (`rally`, from the hook as it is lobbed) leaves a dotted line of beads behind the ball
## in its panels — red, white, teal, white — so the up-and-down of the rally hangs over him as a
## dotted arc, drawn as it happens and eaten from its tail.
##
## **Each header** (`play`, the payoff) squashes the ball flat on his skull and lets it spring back,
## and two pairs of bounce marks, red and teal, kick out either side of the contact. Every header is
## bigger than the last — wider marks, a harder squash — up to the fourth, the one headed home.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeBeachHeader"
## The beach ball's panels, as its picture has them.
const STRIPES := ["R", "W", "a", "W"]
const BEAD := [".xx.", "xxxx", "xxxx", ".xx."]
const BEAD_KEYS := ["bead_r", "bead_w1", "bead_a", "bead_w2"]

static func rally(afx: AbilityFX, ability: WeaponAbility) -> void:
	if afx == null or not AbilityFX.moving():
		return
	(Moment.canvas(afx, NAME, Header) as Header).follow(ability)

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Header) as Header).header(at, size, colour, ability)

class Header extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const SQUASH_T := 0.18
	const MARKS_T := 0.28
	const BEAD_GAP := 15.0

	var trail := Trail.new(24)
	var _ability: WeakRef
	var _tracking := false
	var _colour := Color("ff9a2e")
	var _headed_at := -10.0
	var _at := Vector2.ZERO
	var _count := 1
	var _sprite: Sprite2D
	var _rest_scale := Vector2.ONE
	var _squashing := false
	var _ball_r := 30.0

	func follow(ability: WeaponAbility) -> void:
		_ability = weakref(ability)
		if ability and ability.body:
			_ball_r = ability.body.get_interaction_rect().size.x * 0.5
		trail.clear()
		_tracking = true
		hold(0.1)

	func header(at: Vector2, _size: float, colour: Color, ability: WeaponAbility) -> void:
		_colour = colour
		_at = at
		_headed_at = clock
		_count = maxi(1, int(ability.get("count"))) if ability and ability.get("count") != null else 1
		# The ball squashes flat on him and springs back: its picture only, put back exactly.
		var sprite := ability.sprite() if ability else null
		if sprite and not _squashing:
			_sprite = sprite
			_rest_scale = sprite.scale
		_squashing = _sprite != null
		hold(MARKS_T)

	func _advance(_delta: float) -> void:
		var ability := _ability.get_ref() as WeaponAbility if _ability else null
		if _tracking:
			if ability and is_instance_valid(ability.body) and ability.has_method("is_rallying") \
					and ability.call("is_rallying"):
				trail.add(ability.body.global_position)
				hold(0.1)
			else:
				_tracking = false
		if not _tracking and trail.count > 0:
			trail.shorten(2)
			hold(0.05)
		if _squashing:
			if not is_instance_valid(_sprite):
				_squashing = false
			else:
				var age := clock - _headed_at
				if age >= SQUASH_T:
					_sprite.scale = _rest_scale
					_squashing = false
				else:
					# Flat on the contact, then past round and back: a squash and a stretch.
					var k := age / SQUASH_T
					var amount := lerpf(0.22, 0.34, clampf(float(_count - 1) / 3.0, 0.0, 1.0))
					var s := amount * (1.0 - k) * cos(k * PI * 1.5)
					_sprite.scale = _rest_scale * Vector2(1.0 + s, 1.0 - s)

	func _parked() -> void:
		trail.clear()
		if _squashing and is_instance_valid(_sprite):
			_sprite.scale = _rest_scale
		_squashing = false

	func _draw_shape() -> void:
		_draw_beads()
		_draw_marks()

	## The rally in the ball's panels: a dotted line of beads along the way it went, red, white, teal,
	## white, one every few pixels of its path, smaller toward the tail and none under the ball itself.
	func _draw_beads() -> void:
		if trail.count < 2:
			return
		var walked := 0.0
		var next := BEAD_GAP
		var total := float(trail.count)
		var ball := trail.at(0)
		var bead := 0
		for i in range(1, trail.count):
			var a := trail.at(i - 1)
			var b := trail.at(i)
			var leg := a.distance_to(b)
			while leg > 0.01 and walked + leg >= next:
				var p := a.lerp(b, (next - walked) / leg)
				next += BEAD_GAP
				bead += 1
				if p.distance_to(ball) < _ball_r:
					continue
				var ink: String = STRIPES[bead % STRIPES.size()]
				stamp(tinted(BEAD_KEYS[bead % STRIPES.size()], BEAD, "x", ink), p, lerpf(1.0, 0.5, float(i) / total))
			walked += leg

	## Two pairs of bounce marks kicked out either side of where it met his skull, in the ball's red
	## and teal, wider and heavier every header.
	func _draw_marks() -> void:
		var age := clock - _headed_at
		if age < 0.0 or age > MARKS_T:
			return
		var k := age / MARKS_T
		var grow := clampf(float(_count - 1) / 3.0, 0.0, 1.0)
		var reach := lerpf(34.0, 58.0, grow)
		var r := lerpf(14.0, reach, 1.0 - (1.0 - k) * (1.0 - k))
		var w := lerpf(lerpf(4.0, 6.0, grow), 1.0, k)
		var centre := _at + Vector2(0.0, -6.0)
		for side in [-1.0, 1.0]:
			for j in 2:
				var rr := r + float(j) * 10.0
				var from := (PI if side < 0.0 else 0.0) - 0.6
				var points := PackedVector2Array()
				for s in 7:
					var a := from + 1.2 * float(s) / 6.0
					points.append((centre + Vector2(cos(a), sin(a) * 0.55) * rr).round())
				strokes(points, KEY["R"] if j == 1 else KEY["a"], w)
