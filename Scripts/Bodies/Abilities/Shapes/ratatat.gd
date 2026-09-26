extends RefCounted

## The katar's RATATAT! (Flurry): the rhythm of it. Six sharp stab marks punch onto him one after
## another, a nineteenth of a second apart, zig-zagging round where the point went in — each a crossed
## spike that lands big and settles, with a jab chevron behind it — and they stay until the last is in,
## a cluster of hits, then all close together.
##
## The only payoff that is a sequence: every other is one moment. A flurry is many.

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Ratatat", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const MARKS := 6
	const GAP := 0.055
	const HOLD := 0.16
	const CLOSE := 0.1
	const HOT := Color("ffd23a")

	var _dir := Vector2.RIGHT
	var _spots: Array[Vector2] = []

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var him := ability.him_world() if ability else Vector2.INF
		var to := him - at if him != Vector2.INF else Vector2.RIGHT
		_dir = to.normalized() if to.length_squared() > 1.0 else Vector2.RIGHT
		if _spots.is_empty():
			_spots.resize(MARKS)
		var across := _dir.orthogonal()
		var sway := [-16.0, 12.0, -6.0, 20.0, -22.0, 6.0]
		var depth := [4.0, 12.0, -4.0, 8.0, 14.0, 0.0]
		for i in MARKS:
			_spots[i] = across * float(sway[i]) + _dir * (float(depth[i]) + rng.randf_range(-3.0, 3.0))
		fire(at, GAP * float(MARKS - 1) + HOLD + CLOSE)

	func _paint(_k: float) -> void:
		var end := GAP * float(MARKS - 1) + HOLD
		var closing := span(end, end + CLOSE)
		for i in MARKS:
			var t := age - GAP * float(i)
			if t < 0.0:
				continue
			var at: Vector2 = _spots[i]
			var land := overshoot(clampf(t / 0.05, 0.0, 1.0))
			var reach := (11.0 + 5.0 * size) * land * (1.0 - closing)
			if reach < 3.0:
				continue
			var tint := colour if i % 2 == 0 else HOT
			# The jab that put it there: a chevron behind it, pointing in, for its first moment only.
			if t < 0.09:
				var back := at - _dir * 20.0
				var side := _dir.orthogonal() * 8.0
				strokes(PackedVector2Array([back - _dir * 8.0 + side, back, back - _dir * 8.0 - side]), tint, 3.0)
			# The stab: a crossed spike, each turned a little from the last.
			var turn := 0.3 * float(i % 3)
			for arm in 2:
				var d := Vector2.RIGHT.rotated(PI * 0.25 + PI * 0.5 * float(arm) + turn) * reach
				line(at - d, at + d, tint, 4.0)
