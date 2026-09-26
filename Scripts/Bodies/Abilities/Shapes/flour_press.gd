extends RefCounted

## The rolling pin's SQUISH! (Flatten, every pass): pressed flat like dough. A dark pressed line runs
## along the desk under him, squash lines shoot out of both his sides at floor height, and two clouds
## of flour billow out left and right along the desk and roll away.
##
## All of it at the level of the desk, beside him: he is the pancake, and the eye has to see him
## squashed, so nothing is drawn over him.

const FLOUR := Color("f4f1e6")
const FLOUR_SHADE := Color("d8d6c4")
const PRESS := Color("6b4426")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "FlourPress", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	var _half := 24.0
	var _floor := 0.0

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		fire(at, 0.55)
		var him := ability.buddy() if ability else null
		if him:
			var rect := him.get_interaction_rect()
			_half = rect.size.x * 0.5
			_floor = rect.end.y - global_position.y
			global_position = Vector2(rect.get_center().x, global_position.y).round()
		else:
			_floor = 10.0

	func _paint(_k: float) -> void:
		_pressed()
		for side in [-1.0, 1.0]:
			_squash(side)
			_cloud(side)

	## The line he is pressed into: along the desk under him, drawn in from both ends.
	func _pressed() -> void:
		var k := span(0.0, 0.08)
		var gone := span(0.25, 0.4)
		if k <= 0.0 or gone >= 1.0:
			return
		var reach := (_half + 18.0) * ease_out(k) * (1.0 - gone)
		if reach < 3.0:
			return
		line(Vector2(-reach, _floor - 2.0), Vector2(reach, _floor - 2.0), PRESS, 4.0)

	## Squash lines out of his side at floor height: shot out, then drawn in from his end.
	func _squash(side: float) -> void:
		var out := ease_out(span(0.0, 0.1))
		var gone := span(0.14, 0.36)
		if gone >= 1.0:
			return
		for j in 3:
			var y := _floor - 8.0 - 10.0 * float(j)
			var reach := _half + 10.0 + (24.0 + 12.0 * float(2 - j) + 16.0 * size) * out
			var near := lerpf(_half + 6.0, reach, gone)
			if reach - near >= 3.0:
				line(Vector2(side * near, y), Vector2(side * reach, y), colour, 3.0)

	## A cloud of flour: overlapping puffs, one rim round the lot, rolling out along the desk and
	## shrinking away.
	func _cloud(side: float) -> void:
		var k := span(0.02, 0.55)
		if k <= 0.0 or k >= 1.0:
			return
		var grow := ease_out(span(0.02, 0.14)) * (1.0 - span(0.36, 0.55))
		if grow <= 0.05:
			return
		var centre := Vector2(side * (_half + 18.0 + (70.0 + 40.0 * size) * ease_out(k)), _floor - 14.0 - 12.0 * k)
		var puffs := [Vector2(0, 0), Vector2(side * 15.0, 4.0), Vector2(-side * 14.0, 5.0), Vector2(side * 4.0, -11.0)]
		var radii := [14.0, 11.0, 10.0, 10.0]
		for i in puffs.size():
			var p: Vector2 = centre + (puffs[i] as Vector2) * (0.6 + 0.4 * grow)
			draw_circle(p.round(), float(radii[i]) * grow * (0.9 + 0.3 * size) + RIM, OUTLINE)
		for i in puffs.size():
			var p: Vector2 = centre + (puffs[i] as Vector2) * (0.6 + 0.4 * grow)
			var r: float = float(radii[i]) * grow * (0.9 + 0.3 * size)
			draw_circle(p.round(), r, FLOUR)
			draw_circle((p + Vector2(0.0, r * 0.35)).round(), r * 0.6, FLOUR_SHADE)
		# Crumbs of it on the desk, flicked out ahead.
		for i in 3:
			var q := centre + Vector2(side * (14.0 + 8.0 * float(i)), 8.0 - 2.0 * float(i)) * (0.5 + 0.8 * k)
			draw_rect(Rect2(q.round() - Vector2(3, 3), Vector2(6, 6)), OUTLINE)
			draw_rect(Rect2(q.round() - Vector2(1, 1), Vector2(2, 2)), FLOUR)
