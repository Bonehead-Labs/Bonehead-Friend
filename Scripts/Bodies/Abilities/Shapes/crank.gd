extends RefCounted

## The Crank's payoff ("CREAK!"), at the bite and every half turn: a ratchet. A toothed arc of gear
## rim round him, behind him, across from the jaws — and it clicks round two teeth the way he is
## being turned, a pawl flashing on each click — then winds itself away. He is the nut.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Crank", Ratchet) as Ratchet
	if piece == null:
		return
	var rect := Piece.him_rect(ability, at)
	var centre := rect.get_center()
	var him: Buddy = ability.buddy() if ability else null
	var turn := 1.0
	if ability:
		var turned = ability.get("_turned")
		if turned is float and absf(float(turned)) > 0.01:
			turn = signf(float(turned))
		elif him and absf(him.angular_velocity) > 0.1:
			turn = signf(him.angular_velocity)
	piece.turn = turn
	piece.radius = rect.size.length() * 0.5 + 10.0
	# Across him from the jaws, where the wrench is not in the way of it.
	piece.facing = (centre - at).angle() if at.distance_squared_to(centre) > 1.0 else 0.0
	piece.fire(centre, Ratchet.LIFE, size, colour)
	if him:
		piece.follow(him)

class Ratchet extends Piece:
	const LIFE := 0.6
	const TOOTH := 0.2
	const CLICKS := 2
	const CLICK_T := 0.09
	var turn := 1.0
	var radius := 60.0
	var facing := PI

	func _ready() -> void:
		super._ready()
		z_index = -41

	func _draw() -> void:
		var clicks := mini(int(t / CLICK_T), CLICKS)
		var wind := k_of(CLICK_T * float(CLICKS) + 0.12, LIFE)
		var span := deg_to_rad(lerpf(90.0, 130.0, size)) * (1.0 - wind)
		if span < 0.1:
			return
		# Round by whole teeth, never smoothly: a ratchet clicks.
		var centre_angle := facing + turn * TOOTH * float(clicks) + turn * wind * 1.2
		var from := centre_angle - span * 0.5
		var to := centre_angle + span * 0.5
		var r := radius
		ink_arc(Vector2.ZERO, r, from, to, colour, 6.0)
		# The teeth, square, on the outside of the rim.
		var a := from - fposmod(from - centre_angle, TOOTH) + TOOTH
		while a < to - 0.02:
			var d := Vector2.RIGHT.rotated(a)
			ink_line(d * (r + 3.0), d * (r + 11.0), colour, 6.0)
			a += TOOTH
		# The pawl, on the leading end, flashing on each click.
		var lead := Vector2.RIGHT.rotated(to if turn > 0.0 else from)
		var flash := fmod(t, CLICK_T) < 0.035 and t < CLICK_T * float(CLICKS + 1)
		ink_line(lead * (r - 8.0), lead * (r + 16.0), Color("fff4dc") if flash else colour.lightened(0.4), 4.0)
