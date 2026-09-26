extends RefCounted

## The sickle's TRIP! (Reap): his feet taken out from under him. The hook — a wheat-gold crescent the
## shape of the blade — sweeps along the desk under his feet and pulls back toward you, and a big
## arrow wheels up from his feet and over his head the way he goes: head over heels.
##
## Round him, never over him: the arrow is a line at arm's length from his middle, and the hook is on
## the desk under his feet.

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "HeadOverHeels", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	var _side := 1.0
	var _centre := Vector2.ZERO
	var _radius := 60.0
	var _floor := 0.0

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var reap := ability as ReapAbility
		_side = reap.side() if reap else 1.0
		if _side == 0.0:
			_side = 1.0
		var him := ability.buddy() if ability else null
		var rect := him.get_interaction_rect() if him else Rect2(at - Vector2(24, 80), Vector2(48, 88))
		fire(at, 0.8)
		_centre = rect.get_center() - global_position
		_radius = maxf(rect.size.y * 0.5 + 16.0, 52.0) * (0.9 + 0.2 * size)
		_floor = rect.end.y - global_position.y

	func _paint(_k: float) -> void:
		_hook()
		_arrow()

	## The blade's crescent, points up, swept from past his far foot back toward you along the desk.
	func _hook() -> void:
		var k := ease_out(span(0.0, 0.2))
		var gone := span(0.32, 0.44)
		if gone >= 1.0:
			return
		var x := lerpf(_side * 34.0, -_side * 46.0, k)
		var c := Vector2(x, _floor - 24.0)
		var r := 24.0 * (1.0 - gone)
		if r < 6.0:
			return
		var points := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var a := lerpf(PI * 0.1, PI * 0.9, float(i) / float(n))
			points.append(c + Vector2(cos(a), sin(a)) * r)
		for i in range(n - 1, 0, -1):
			var t := float(i) / float(n)
			var a := lerpf(PI * 0.1, PI * 0.9, t)
			points.append(c + Vector2(0.0, -r * 0.35) + Vector2(cos(a), sin(a)) * (r - r * 0.33 * sin(PI * t)))
		shape(points, colour)

	## Head over heels: an arc from his feet up and over his head, grown fast, held, then drawn in
	## from its tail to its head, with the arrowhead riding the front.
	func _arrow() -> void:
		var grow := ease_out(span(0.04, 0.26))
		var tail := span(0.5, 0.74)
		if grow <= 0.0 or tail >= 1.0:
			return
		# Clockwise when he is on your right: his head goes away from you, his feet come toward you.
		var start := PI * 0.5 + _side * 0.35
		var sweep := _side * PI * 1.45
		var from := start + sweep * tail
		var to := start + sweep * grow
		if absf(to - from) < 0.05:
			return
		var width := 5.0 + 2.0 * size
		arc(_centre, _radius, from, to, colour, width)
		# The head: a triangle along the tangent at the arc's front.
		var at := _centre + Vector2(cos(to), sin(to)) * _radius
		var along := Vector2(-sin(to), cos(to)) * signf(sweep)
		var across := along.orthogonal()
		var head := 11.0 + 5.0 * size
		shape(PackedVector2Array([at + along * head, at - along * 4.0 + across * head * 0.8,
			at - along * 4.0 - across * head * 0.8]), colour.lightened(0.2))
