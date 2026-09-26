extends RefCounted

## The Whirlwind's payoff: he is caught in it. Three speed arcs whip round him the way the sticks
## are turning, behind him so they show only round his outline, tightening and winding faster
## until they blow apart; and a hard little WHAP where the first stick met him.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var gust := Piece.take(afx, "Whirl", Gust) as Gust
	var whap := Piece.take(afx, "WhirlWhap", Whap) as Whap
	var rect := Piece.him_rect(ability, at)
	var him: Buddy = ability.buddy() if ability else null
	var turn := 1.0
	if ability and ability.body and absf(ability.body.angular_velocity) > 0.1:
		turn = signf(ability.body.angular_velocity)
	if gust:
		gust.turn = turn
		gust.radius = rect.size.length() * 0.5
		gust.fire(rect.get_center(), Gust.LIFE, size, colour)
		if him:
			gust.follow(him)
	if whap:
		whap.fire(at, Whap.LIFE, size, colour)

class Gust extends Piece:
	const LIFE := 0.7
	const ARCS := 3
	var turn := 1.0
	var radius := 50.0

	func _ready() -> void:
		super._ready()
		z_index = -41

	func _draw() -> void:
		var wind := ease_out(k_of(0.0, LIFE))
		var burst := k_of(LIFE * 0.6, LIFE)
		# Round and round, a turn and a half, the arcs flung wider as it lets go.
		var angle := turn * wind * TAU * 1.6
		var span := deg_to_rad(lerpf(70.0, 100.0, size)) * (1.0 - burst)
		if span < 0.08:
			return
		for i in ARCS:
			var r := radius * (0.85 + 0.2 * float(i)) + burst * 40.0
			var from := angle + TAU * float(i) / float(ARCS)
			var w := 5.0 if i == 0 else 4.0
			var tint := colour if i != 1 else colour.lightened(0.4)
			ink_arc(Vector2.ZERO, r, from, from + turn * span, tint, w)
			# A hooked head on the leading end, the way the wind is going.
			var head := Vector2.RIGHT.rotated(from + turn * span) * r
			var back := Vector2.RIGHT.rotated(from + turn * span * 0.8) * (r + 9.0)
			ink_line(head, back, tint, w - 1.0)

class Whap extends Piece:
	const LIFE := 0.12

	func _draw() -> void:
		var r := lerpf(12.0, 20.0, size) * (1.0 - k_of(0.0, LIFE) * 0.6)
		ink_star(Vector2.ZERO, 5, r, r * 0.4, colour.lightened(0.5), 0.4)
