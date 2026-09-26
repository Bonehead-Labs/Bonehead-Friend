extends RefCounted

## The cricket bat's SIX! (Middle It): over the rope. A boundary rope runs out along the desk on the
## far side of him between two red flags, and a red ball goes up off him in a huge arc, a dotted gold
## trail behind it, and over the rope — which sparkles as it clears.
##
## Big: a six is the whole point of the bat. Everything is beside him or above him; he is going
## straight up through the middle of it.

const ROPE := Color("fcfcee")
const FLAG := Color("c8382e")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Six", Drawing, 1) as Drawing
	drawing.setup(at, size, colour, ability)

const BALL := [
	".RRRR.",
	"RRRRrR",
	"RWRRrR",
	"RRcRRr",
	"RRRcrr",
	".Rrrr.",
]

class Drawing extends PayoffSketch:
	const FLIGHT := 0.85
	var _side := 1.0
	var _from := Vector2.ZERO
	var _to := Vector2.ZERO
	var _apex := 300.0
	var _rope_from := 0.0
	var _rope_to := 0.0
	var _floor := 0.0
	var _ball: Texture2D

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		_ball = plot("ball", BALL)
		fire(at, 1.05)
		var him := ability.buddy() if ability else null
		var rect := him.get_interaction_rect() if him else Rect2(at - Vector2(24, 44), Vector2(48, 88))
		# Over the rope the way the bat was going: a six goes where it was hit.
		var swing := ability.body.linear_velocity.x if ability and ability.body else 0.0
		if absf(swing) > 40.0:
			_side = signf(swing)
		else:
			var hand := ability.hand_world() if ability else at - Vector2(100, 0)
			_side = 1.0 if rect.get_center().x >= hand.x else -1.0
		_floor = rect.end.y - global_position.y
		var cx := rect.get_center().x - global_position.x
		_from = Vector2(cx, rect.position.y - global_position.y)
		_to = Vector2(cx + _side * (340.0 + 60.0 * s), _floor - 6.0)
		_apex = 240.0 + 110.0 * s
		_rope_from = cx + _side * 170.0
		_rope_to = cx + _side * 310.0

	func _paint(_k: float) -> void:
		_rope()
		_flight()

	func _ball_at(t: float) -> Vector2:
		var x := lerpf(_from.x, _to.x, t)
		var line_y := lerpf(_from.y, _to.y, t)
		return Vector2(x, line_y - _apex * 4.0 * t * (1.0 - t))

	## The rope, out from its middle, and two flags: gone by drawing back into the middle.
	func _rope() -> void:
		var out := ease_out(span(0.0, 0.12)) * (1.0 - span(0.9, 1.05))
		if out <= 0.02:
			return
		var mid := (_rope_from + _rope_to) * 0.5
		var half := (_rope_to - _rope_from) * 0.5 * out
		var y := _floor - 5.0
		var points := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var x := mid - half + 2.0 * half * float(i) / float(n)
			points.append(Vector2(x, y + 2.0 * sin(float(i) * PI / float(n))))
		strokes(points, ROPE, 4.0)
		# The rope's twist: red ticks along it.
		for i in range(1, n, 2):
			var p := points[i]
			draw_rect(Rect2(p.round() - Vector2(2, 2), Vector2(4, 4)), FLAG)
		for x in [mid - half, mid + half]:
			var foot := Vector2(x, _floor)
			var top := foot + Vector2(0.0, -40.0 * out)
			line(foot, top, Color("a9713f"), 3.0)
			var fly := top + Vector2(18.0 * _side * out, 6.0 * out)
			shape(PackedVector2Array([top, fly, top + Vector2(0.0, 13.0 * out)]), FLAG)

	## The ball: up off him and over the rope, a dotted trail behind it, a sparkle as it clears.
	func _flight() -> void:
		var t := ease_out(span(0.02, 0.02 + FLIGHT)) * 0.35 + span(0.02, 0.02 + FLIGHT) * 0.65
		if age < 0.02:
			return
		# The trail: dots along the arc behind the ball, the last of it only.
		var trail_from := maxf(0.0, t - 0.42)
		var dots := 9
		for i in dots:
			var tt := lerpf(trail_from, t, float(i) / float(dots))
			if tt <= 0.0:
				continue
			var p := _ball_at(tt).round()
			var r := 2.0 + float(i) * 0.25
			draw_rect(Rect2(p - Vector2.ONE * (r + 2.0), Vector2.ONE * (r * 2.0 + 4.0)), OUTLINE)
			draw_rect(Rect2(p - Vector2.ONE * r, Vector2.ONE * r * 2.0), colour)
		var shrink := 1.0 - span(0.92, 1.05)
		picture(_ball, _ball_at(t), (1.8 + 0.4 * size) * shrink, age * 14.0)
		# Over the rope: a sparkle where it clears.
		var cross := inverse_lerp(_from.x, _to.x, (_rope_from + _rope_to) * 0.5)
		var since := t - cross
		if since >= 0.0 and since < 0.18:
			var at := _ball_at(cross) + Vector2(0.0, 18.0)
			var r := (1.0 - since / 0.18) * (18.0 + 10.0 * size)
			glint_star(at, r, colour)
			glint_star(at + Vector2(_side * 22.0, 14.0), r * 0.6, colour)
