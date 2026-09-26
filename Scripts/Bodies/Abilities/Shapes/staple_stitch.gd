extends RefCounted

## The stapler's STAPLED! (Staple Gun): stitched. A row of five big staples is driven along his side
## where the strip is going in, ka-chunk, ka-chunk, one after another, joined by a red stitch; they hold
## a moment and come out in the order they went in.
##
## Steel brackets with a dark rim on the bone, legs pointing into him — the notice-board look the strip
## leaves on him, said once, big, in the moment it starts.

const STEEL := Color("dfe5ec")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "StapleStitch", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const STAPLES := 5
	const GAP := 0.045
	var _dir := Vector2.RIGHT

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var gun := ability as StapleGunAbility
		var d := gun.last_heading if gun else Vector2.RIGHT
		_dir = d.normalized() if d.length_squared() > 0.5 else Vector2.RIGHT
		fire(at, 0.78)

	func _spot(i: int) -> Vector2:
		var along := _dir.orthogonal()
		# Down his side, a staple's length in from where the first went in.
		return along * (float(i) - float(STAPLES - 1) * 0.5) * 20.0 + _dir * 6.0

	func _paint(_k: float) -> void:
		var shown := 0
		for i in STAPLES:
			if age >= GAP * float(i) and age < 0.5 + 0.05 * float(i):
				shown = i + 1
		# The stitch under them: red dashes from the first staple to the last one in.
		var first := 0
		for i in STAPLES:
			if age >= 0.5 + 0.05 * float(i):
				first = i + 1
		if shown - first >= 2:
			var from := _spot(first)
			var to := _spot(shown - 1)
			var steps := int(from.distance_to(to) / 6.0)
			for s in steps:
				if s % 2 == 0:
					var a := from.lerp(to, float(s) / float(steps))
					var b := from.lerp(to, float(s + 1) / float(steps))
					line(a - _dir * 4.0, b - _dir * 4.0, colour, 4.0)
		for i in range(first, shown):
			var t := age - GAP * float(i)
			# Driven: in from a little outside him, over two frames.
			var drive := clampf(t / 0.03, 0.0, 1.0)
			_staple(_spot(i) - _dir * 14.0 * (1.0 - drive), 1.4 + 0.4 * size)

	## A staple: a crown across the stitch and two legs into him.
	func _staple(at: Vector2, scale: float) -> void:
		var along := _dir.orthogonal()
		var half := 6.0 * scale
		var legs := 6.0 * scale
		var crown_a := at - along * half - _dir * 2.0
		var crown_b := at + along * half - _dir * 2.0
		strokes(PackedVector2Array([crown_a + _dir * legs, crown_a, crown_b, crown_b + _dir * legs]), STEEL, 4.0)
