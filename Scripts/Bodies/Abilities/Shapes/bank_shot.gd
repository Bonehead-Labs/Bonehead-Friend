extends RefCounted

## The tyre iron's BANK SHOT! (Ricochet, every hit): the shot drawn like a pool player's diagram. A
## dashed line runs from where it last banked, through every cushion it came off, into him, the dashes
## marching the way it flew; each bank is a diamond that pings; and where it met him, a heavy X.
##
## The only payoff that draws where the ability has been rather than where it is: a ricochet is a
## path, and a hit off three walls is worth more because of that path.

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "BankShot", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const MOST := 4
	const DASH := 10.0
	const GAP := 7.0
	var _path := PackedVector2Array()
	var _length := 0.0

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		fire(at, 0.66)
		_path.clear()
		var ricochet := ability as RicochetAbility
		var banks: Array[Vector2] = ricochet.bank_points if ricochet else ([] as Array[Vector2])
		var first := maxi(0, banks.size() - (MOST - 1))
		if banks.is_empty():
			# Straight in: the last stretch of the way it came.
			var v := ability.body.linear_velocity if ability and ability.body else Vector2.RIGHT
			var back := -v.normalized() if v.length_squared() > 1.0 else Vector2.LEFT
			_path.append(back * 150.0)
		for i in range(first, banks.size()):
			_path.append(banks[i] - global_position)
		_path.append(Vector2.ZERO)
		_length = 0.0
		for i in range(1, _path.size()):
			_length += _path[i - 1].distance_to(_path[i])

	func _paint(_k: float) -> void:
		var head := ease_out(span(0.0, 0.16)) * _length
		var tail := span(0.42, 0.66) * _length
		_dashes(tail, head)
		_banks(head)
		_clang()

	## The path from `from` to `to` px along it, in dashes that march toward him.
	func _dashes(from: float, to: float) -> void:
		var march := fmod(age * 140.0, DASH + GAP)
		var walked := 0.0
		for i in range(1, _path.size()):
			var a := _path[i - 1]
			var b := _path[i]
			var leg := a.distance_to(b)
			var d := (b - a) / maxf(leg, 0.001)
			var s := -march
			while s < leg:
				var s0 := maxf(s, 0.0)
				var s1 := minf(s + DASH, leg)
				var g0 := maxf(walked + s0, from)
				var g1 := minf(walked + s1, to)
				if g1 - g0 >= 2.0:
					line(a + d * (g0 - walked), a + d * (g1 - walked), colour, 3.0)
				s += DASH + GAP
			walked += leg

	## Every cushion it came off: a diamond that pings as the line reaches it.
	func _banks(head: float) -> void:
		var walked := 0.0
		for i in range(1, _path.size() - 1):
			walked += _path[i - 1].distance_to(_path[i])
			if walked > head:
				return
			var since := (head - walked) / maxf(_length, 1.0)
			var r := (7.0 + 3.0 * size) * (1.0 + 0.8 * maxf(0.0, 0.25 - since) * 4.0) * (1.0 - span(0.5, 0.66))
			if r < 3.0:
				continue
			var p := _path[i]
			shape(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]),
				colour.lightened(0.45))

	## Where it met him: a heavy X, popped once the line gets there.
	func _clang() -> void:
		var k := span(0.12, 0.42)
		if k <= 0.0 or k >= 1.0:
			return
		var r := (12.0 + 8.0 * size) * overshoot(minf(k * 3.0, 1.0)) * (1.0 - k * k)
		if r < 3.0:
			return
		line(Vector2(-r, -r), Vector2(r, r), colour, 5.0)
		line(Vector2(-r, r), Vector2(r, -r), colour, 5.0)
