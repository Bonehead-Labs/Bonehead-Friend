extends RefCounted

## The machete's SWOOSH (Brush Clear): a path cut and blown clear. Three long wind streaks with curled
## heads cross the cone the way the swipe went, one after another, and a spray of cut stalks tumbles
## out ahead of them.
##
## Straw and gold, never a leaf green: green is the chroma key's (D38). Level and across, because the
## swipe is — the sledgehammer's wave goes up out of the desk, this goes along it.

const STRAW := Color("e8c75a")
const STRAW_DARK := Color("a8822a")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Gust", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const STREAKS := 3
	const STALKS := 8
	const TRAVEL := 0.34
	const GRAVITY := 1100.0

	var _facing := 1.0
	var _from: Array[Vector2] = []
	var _speed: Array[Vector2] = []
	var _spin: Array[float] = []

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		_facing = 1.0
		var clear := ability as BrushClearAbility
		if clear:
			_facing = signf(clear.facing().x) if absf(clear.facing().x) > 0.1 else 1.0
		if _from.is_empty():
			_from.resize(STALKS)
			_speed.resize(STALKS)
			_spin.resize(STALKS)
		for i in STALKS:
			_from[i] = Vector2(rng.randf_range(-26.0, 10.0) * _facing, rng.randf_range(4.0, 30.0))
			_speed[i] = Vector2(_facing * rng.randf_range(220.0, 460.0), -rng.randf_range(160.0, 380.0))
			_spin[i] = rng.randf_range(-16.0, 16.0)
		fire(at, 0.62)

	func _paint(_k: float) -> void:
		for i in STREAKS:
			_streak(i)
		_stalks()

	## One streak: a long line with a curl at its head, blowing across and drawn in behind itself.
	func _streak(i: int) -> void:
		var start := 0.05 * float(i)
		var k := span(start, start + TRAVEL)
		if k <= 0.0 or k >= 1.0:
			return
		var y := [-34.0, -6.0, 22.0][i] as float
		var length := (120.0 + 50.0 * size) * (1.0 - k * k)
		var head_x := lerpf(-150.0, 170.0 + 60.0 * size, ease_out(k)) * _facing
		var head := Vector2(head_x, y)
		var tail := head - Vector2(length * _facing, 0.0)
		var tint := colour if i != 1 else STRAW
		var width := 4.0 if i == 1 else 3.0
		# The line and its curl as one stroke: along, then a spiral winding in over the top of the head —
		# a turn and a quarter, tighter as it goes, the way wind is drawn.
		var points := PackedVector2Array()
		if length >= 6.0:
			points.append(tail)
		var r0 := 12.0 if i == 1 else 10.0
		var centre := head + Vector2(0.0, -r0)
		var turns := 1.25 * (1.0 - 0.4 * k)
		var steps := 12
		for s in steps + 1:
			var f := float(s) / float(steps)
			var a := PI * 0.5 - _facing * TAU * turns * f
			points.append(centre + Vector2(cos(a), sin(a)) * r0 * (1.0 - 0.6 * f))
		strokes(points, tint, width)

	## Cut stalks: thin straw slivers thrown forward and up, turning as they fall, gone by scale.
	func _stalks() -> void:
		var t := maxf(age - 0.04, 0.0)
		if t <= 0.0:
			return
		var shrink := 1.0 - span(0.44, 0.62)
		if shrink <= 0.0:
			return
		for i in STALKS:
			var p: Vector2 = _from[i] + _speed[i] * t + Vector2(0.0, 0.5 * GRAVITY * t * t)
			var turn := _spin[i] * t
			var half := Vector2(2.5, 9.0) * shrink
			var along := Vector2.UP.rotated(turn)
			var side := along.orthogonal()
			var quad := PackedVector2Array([p - along * half.y - side * half.x, p - along * half.y + side * half.x,
				p + along * half.y + side * half.x, p + along * half.y - side * half.x])
			shape(quad, STRAW if i % 2 == 0 else STRAW_DARK)
