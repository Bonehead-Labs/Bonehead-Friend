extends RefCounted

## The rapier's TOUCHE! (En Garde, every thrust): one precise point, and a flourish. A single sharp
## four-point glint sits exactly on the point of the blade — no rings, no spray: the whole hit is that
## one spot — and a fencer's flourish, a ribbon that loops once, is written up and away from the tip
## and drawn back in behind itself.
##
## Small on purpose: a thrust is an ordinary blow done well, and it lands every time you lunge.

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Touche", Drawing, 3) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const POINTS := 28
	var _forward := 1.0
	var _flourish := PackedVector2Array()

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var guard := ability as EnGardeAbility
		var axis := guard.blade_axis() if guard else Vector2.RIGHT
		_forward = 1.0 if axis.x >= 0.0 else -1.0
		# The ribbon: out along the lunge, a loop, and up and away — a signature, not a slash.
		if _flourish.is_empty():
			_flourish.resize(POINTS)
		var reach := 34.0 + 30.0 * s
		for i in POINTS:
			var t := float(i) / float(POINTS - 1)
			var loop := Vector2(sin(TAU * t) * 12.0, (1.0 - cos(TAU * t)) * -10.0)
			var rise := Vector2(reach * t * 0.8, -reach * t * t * 1.3)
			_flourish[i] = Vector2((rise.x + loop.x) * _forward, rise.y + loop.y)
		fire(at, 0.5)

	func _paint(_k: float) -> void:
		# The point: a glint dead on the tip, turning an eighth and closing.
		var close := span(0.0, 0.32)
		if close < 1.0:
			var reach := (14.0 + 12.0 * size) * (1.0 - close * close)
			glint_star(Vector2.ZERO, reach, colour, close * PI * 0.25)
			glint_star(Vector2.ZERO, reach * 0.45, Color.WHITE, close * PI * 0.25)
		# The flourish, written out and then drawn in from its start.
		var head := ease_out(span(0.03, 0.22))
		var tail := span(0.26, 0.48)
		var first := int(tail * float(POINTS - 1))
		var last := int(head * float(POINTS - 1))
		if last - first < 2:
			return
		strokes(_flourish.slice(first, last + 1), colour, 3.0)
