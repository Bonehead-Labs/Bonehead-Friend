extends RefCounted

## The war pick's BULLSEYE! (Pinpoint): everything it has, on one spot. Four red corner brackets snap in
## from wide round the spot to a few pixels, like a lens pulling focus; the moment they close, a
## hard little star goes off on the spot and fine dark cracks run out of it into his skull.
##
## No ring and no spray, because nothing spreads: the point of the ability is that it goes in there and
## nowhere else. The cracks are dark on bone, which reads where a bright line would not.

const CRACK := Color("3a342c")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Pinpoint", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const CLOSE := 0.08
	var _cracks: Array[PackedVector2Array] = []

	func setup(at: Vector2, s: float, tint: Color, _ability: WeaponAbility) -> void:
		size = s
		colour = tint
		if _cracks.is_empty():
			_cracks.resize(5)
		for i in 5:
			var d := Vector2.RIGHT.rotated(TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3))
			var reach := rng.randf_range(16.0, 28.0) * (0.8 + 0.4 * s)
			var kink := d * reach * 0.55 + d.orthogonal() * rng.randf_range(-4.0, 4.0)
			_cracks[i] = PackedVector2Array([d * 3.0, kink, kink + d.rotated(rng.randf_range(-0.5, 0.5)) * reach * 0.5])
		fire(at, 0.56)

	func _paint(_k: float) -> void:
		_brackets()
		if age >= CLOSE * 0.75:
			_cracks_out()
			_star()

	## Four corners, snapping in and holding, then closing to nothing.
	func _brackets() -> void:
		var d := lerpf(58.0 + 12.0 * size, 12.0, ease_out(span(0.0, CLOSE)))
		d *= 1.0 - span(0.38, 0.5)
		if d < 3.0:
			return
		var arm := minf(16.0, d)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := Vector2(sx * d, sy * d)
				strokes(PackedVector2Array([corner - Vector2(sx * arm, 0.0), corner, corner - Vector2(0.0, sy * arm)]),
					colour, 4.0)

	## The star on the spot: hard, bright and small, closing.
	func _star() -> void:
		var k := span(CLOSE * 0.75, 0.34)
		if k >= 1.0:
			return
		var reach := (12.0 + 8.0 * size) * (1.0 - k * k)
		glint_star(Vector2.ZERO, reach, colour, PI * 0.25)
		glint_star(Vector2.ZERO, reach * 0.5, Color("fff4dc"), PI * 0.25)

	## Fine cracks out of the spot, drawn back in at the end.
	func _cracks_out() -> void:
		var run := ease_out(span(CLOSE * 0.75, CLOSE + 0.08))
		var back := span(0.4, 0.56)
		var k := run * (1.0 - back)
		for crack in _cracks:
			var points := PackedVector2Array()
			for p in crack:
				points.append((p * k).round())
			if points[2].length() >= 4.0:
				draw_polyline(points, CRACK, 3.0)
