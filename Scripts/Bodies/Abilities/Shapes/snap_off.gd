extends RefCounted

## The boxcutter's TING! (Snap): a snap-off blade doing what it is for. The tip that hit him shows for
## a moment as a whole segment of blade, scored across, a yellow crack jumps along the score, and it
## breaks into three bright slivers that spin away off him and fall, with a spark where it broke.
##
## Steel and the knife's yellow. Drawn bigger than a tip is, because a tip is a sliver and this has to
## read from across the room; nothing else in the game breaks.

const STEEL := Color("dfe5ec")
const SCORE := Color("6b7280")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "SnapOff", Drawing, 3) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const WHOLE := 0.1
	const GRAVITY := 1200.0

	var _dir := Vector2.RIGHT
	var _speed: Array[Vector2] = []
	var _spin: Array[float] = []

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var from := ability.tip_world() if ability else at - Vector2(60, 0)
		var d := at - from
		_dir = d.normalized() if d.length_squared() > 1.0 else Vector2.RIGHT
		if _speed.is_empty():
			_speed.resize(3)
			_spin.resize(3)
		var across := _dir.orthogonal()
		for i in 3:
			var fan := float(i) - 1.0
			_speed[i] = -_dir * rng.randf_range(140.0, 240.0) + across * fan * 190.0 \
				+ Vector2(0.0, -rng.randf_range(200.0, 300.0))
			_spin[i] = rng.randf_range(10.0, 20.0) * (1.0 if i % 2 == 0 else -1.0)
		fire(at - _dir * 14.0, 0.6)

	## One piece of blade, `from` to `to` along it: a parallelogram whose ends slant with the score.
	func _piece(centre: Vector2, along: Vector2, half: float, tall: float, tint: Color) -> void:
		var across := along.orthogonal()
		var lean := along * tall * 0.6
		shape(PackedVector2Array([centre - along * half - across * tall + lean,
			centre + along * half - across * tall + lean, centre + along * half + across * tall - lean,
			centre - along * half + across * tall - lean]), tint)

	func _paint(_k: float) -> void:
		var scale := 1.0 + 0.5 * size
		var across := _dir.orthogonal()
		if age < WHOLE:
			# The segment, whole: three pieces' worth of blade, with its two score lines.
			var third := 9.0 * scale
			var tall := 6.0 * scale
			_piece(Vector2.ZERO, _dir, third * 1.5, tall, STEEL)
			var edge := across * (tall - 2.0)
			line(-_dir * third * 1.5 - edge, _dir * third * 1.5 - edge, Color.WHITE, 2.0)
			for s in [-0.5, 0.5]:
				var c: Vector2 = _dir * third * float(s) * 2.0
				var lean := _dir * tall * 0.6
				draw_line((c - across * tall + lean).round(), (c + across * tall - lean).round(), SCORE, 2.0)
			# The crack, running along the score, in the knife's yellow.
			var run := age / WHOLE
			if run > 0.4:
				var z := PackedVector2Array([-across * tall * 1.9 + _dir * 4.0, -across * tall * 0.6 - _dir * 3.0,
					across * tall * 0.6 + _dir * 3.0, across * tall * 1.9 - _dir * 4.0])
				var reach := clampi(int(ceil((run - 0.4) / 0.6 * 4.0)), 2, 4)
				strokes(z.slice(0, reach), colour, 3.0)
			return
		# Three slivers, spinning away and falling, gone by scale.
		var t := age - WHOLE
		var shrink := 1.0 - span(0.44, 0.6)
		for i in 3:
			var p: Vector2 = _dir * (float(i) - 1.0) * 18.0 * scale + _speed[i] * t \
				+ Vector2(0.0, 0.5 * GRAVITY * t * t)
			var turn: float = _spin[i] * t
			_piece(p, _dir.rotated(turn), 8.0 * scale * shrink, 5.0 * scale * shrink,
				STEEL if i != 1 else colour)
		if t < 0.1:
			# The ting: a spark where it broke, a plus that closes.
			var r := 16.0 * (1.0 - t / 0.1) + 3.0
			line(Vector2(-r, 0.0), Vector2(r, 0.0), colour, 3.0)
			line(Vector2(0.0, -r), Vector2(0.0, r), colour, 3.0)
