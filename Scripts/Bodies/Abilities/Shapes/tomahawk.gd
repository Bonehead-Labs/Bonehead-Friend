extends RefCounted

## The Tomahawk's payoff: the axe's spin, still in the air behind it — three wheels of it tumbling in
## along the line it flew, the far ones going first — and the bite of its edge, a red crescent the
## shape of the blade laid on him where it struck, shivering, with chips of him flicked out ahead.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Tomahawk", Chop) as Chop
	if piece == null:
		return
	var rect := Piece.him_rect(ability, at)
	var dir := Vector2.RIGHT
	var spin := 1.0
	if ability and ability.body:
		var v := ability.body.linear_velocity
		if v.length_squared() > 40000.0:
			dir = v.normalized()
		elif ability.him_world() != Vector2.INF:
			dir = (ability.him_world() - ability.grip_world()).normalized()
		if absf(ability.body.angular_velocity) > 0.1:
			spin = signf(ability.body.angular_velocity)
	# The bite on the near side of him, where the incoming line meets his outline.
	var centre := rect.get_center()
	var edge := centre - dir * minf(rect.size.x * 0.5, 30.0)
	piece.dir = dir
	piece.spin = spin
	piece.fire(edge, Chop.LIFE, size, colour)

class Chop extends Piece:
	const LIFE := 0.75
	const WHEELS := 3
	const WHEEL_T := 0.3
	const BITE_T := 0.45
	const CHIPS := 6
	const BONE := Color("e6dcc4")
	var dir := Vector2.RIGHT
	var spin := 1.0
	var _chips: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		_chips.clear()
		for i in Piece.count(CHIPS):
			var d := dir.rotated(rng.randf_range(-0.9, 0.9)) + Vector2(0.0, -0.7)
			_chips.append({"v": d.normalized() * rng.randf_range(320.0, 520.0),
				"turn": rng.randf_range(0.0, TAU), "spin": rng.randf_range(-16.0, 16.0),
				"r": rng.randf_range(5.0, 7.0)})

	func _draw() -> void:
		# The wheels: the axe tumbling in along the throw — a three-quarter ring for its turning and a
		# wedge for its head — drawn in from the far one.
		for i in WHEELS:
			var gone := k_of(WHEEL_T * float(WHEELS - 1 - i) / float(WHEELS), WHEEL_T * float(WHEELS - i) / float(WHEELS))
			if gone >= 1.0:
				continue
			var at := -dir * (46.0 + 44.0 * float(i))
			var r := lerpf(22.0, 14.0, float(i) / float(WHEELS)) * lerpf(0.8, 1.1, size) * (1.0 - gone)
			if r < 4.0:
				continue
			var from := spin * (float(i) * 1.9 + t * 20.0)
			var tint := colour if i == 0 else colour.darkened(0.15 * float(i))
			ink_arc(at, r, from, from + spin * 4.2, tint, 5.0 - float(i))
			var head := at + Vector2.RIGHT.rotated(from + spin * 4.2) * r
			var out := Vector2.RIGHT.rotated(from + spin * 4.2)
			ink_poly(PackedVector2Array([head - out * 2.0, head + out * 9.0 + out.orthogonal() * 5.0,
				head + out * 9.0 - out.orthogonal() * 5.0]), Color("c8ccd6"))
		# The bite: a crescent the shape of the blade's edge, bulging into him, shivering as it holds.
		var bite := 1.0 - k_of(BITE_T, BITE_T + 0.15)
		if bite > 0.0:
			var shiver := sin(t * 60.0) * 2.0 * (1.0 - k_of(0.0, BITE_T))
			var r := lerpf(26.0, 34.0, size) * bite
			var span := 1.9
			var face := dir.angle()
			var centre := -dir * (r * 0.55) + dir.orthogonal() * shiver
			# The outer edge an arc of `r`; the inner a wider circle from further back through the same two
			# tips, so it is thickest in the middle and comes to a point at each end.
			var back := r
			var tip := Vector2(cos(span * 0.5), sin(span * 0.5)) * r
			var wide := Vector2(tip.x + back, tip.y).length()
			var reach := atan2(tip.y, tip.x + back)
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for k in 9:
				var a := face - span * 0.5 + span * float(k) / 8.0
				outer.append(centre + Vector2.RIGHT.rotated(a) * r)
				var b := face - reach + 2.0 * reach * float(k) / 8.0
				inner.append(centre - dir * back + Vector2.RIGHT.rotated(b) * wide)
			inner.remove_at(8)
			inner.remove_at(0)
			if r >= 6.0:
				var crescent := outer.duplicate()
				inner.reverse()
				crescent.append_array(inner)
				ink_poly(crescent, colour.lightened(0.1))
				# The edge, bright.
				var edge := PackedVector2Array()
				for k in range(1, 8):
					edge.append((centre + Vector2.RIGHT.rotated(face - span * 0.5 + span * float(k) / 8.0) * (r - 2.0)).round())
				draw_polyline(edge, Color("fff1b8"), 2.0)
		# The chips: flicked out ahead of the blow and falling, triangles that turn as they go.
		var shrink := 1.0 - k_of(LIFE * 0.6, LIFE)
		for c in _chips:
			var v: Vector2 = c["v"]
			var p := v * t + Vector2(0.0, 1000.0) * (0.5 * t * t)
			var r := float(c["r"]) * shrink
			if r < 2.5:
				continue
			var turn := float(c["turn"]) + float(c["spin"]) * t
			var tri := PackedVector2Array()
			for k in 3:
				tri.append(p + Vector2.RIGHT.rotated(turn + TAU * float(k) / 3.0) * r)
			ink_poly(tri, BONE)
