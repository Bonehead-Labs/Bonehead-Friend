extends RefCounted

## The BONG's payoff: his skull rung like a gong. The pan's gold waves are still the pan's (its
## archetype draws them off the face and off his head); this is the ringing itself — three nested
## gold brackets either side of his skull, ((( and ))), shivering in and out as the note hangs and
## thinning away as it dies, a gong ring swelling out from behind him, and a small hard flash where
## the pan met him. Nothing solid over his face: the brackets stand off it, and the swell is behind
## him. A follow-up plays it again, bigger each time (`StunAbility._follow`).

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var ring := Piece.take(afx, "BongRing", Ring) as Ring
	var brackets := Piece.take(afx, "BongBrackets", Brackets) as Brackets
	var rect := Piece.him_rect(ability, at)
	var head := Vector2(rect.get_center().x, rect.position.y + 18.0)
	var him: Buddy = ability.buddy() if ability else null
	if ring:
		ring.half_width = rect.size.x * 0.5
		ring.fire(head, Ring.LIFE, size, colour)
		if him:
			ring.follow(him, head - rect.get_center())
	if brackets:
		brackets.half_width = rect.size.x * 0.5
		brackets.hit = at - head
		brackets.fire(head, Brackets.LIFE, size, colour)
		if him:
			brackets.follow(him, head - rect.get_center())

## The swell: one thick gold ring out of his skull, behind him, so it shows only round him.
class Ring extends Piece:
	const LIFE := 0.42
	var half_width := 24.0

	func _ready() -> void:
		super._ready()
		# Behind him (AbilityFX sits at 40): only the part outside his outline is drawn over the desk.
		z_index = -41

	func _draw() -> void:
		var k := ease_out(k_of(0.0, LIFE))
		var r := lerpf(half_width, half_width + lerpf(70.0, 150.0, size), k)
		var w := roundf(lerpf(lerpf(6.0, 10.0, size), 2.0, k))
		ink_arc(Vector2.ZERO, r, 0.0, TAU, colour, w)

## The ringing: ((( ))) either side of his skull, and the flash where the pan met him.
class Brackets extends Piece:
	const LIFE := 0.95
	const FLASH_T := 0.07
	var half_width := 24.0
	var hit := Vector2.ZERO

	func _draw() -> void:
		var die := k_of(LIFE * 0.55, LIFE)
		var span := deg_to_rad(lerpf(64.0, 80.0, size)) * (1.0 - die)
		if span > 0.05:
			# The note hanging: each bracket shivers out and back, fastest at the strike.
			var shiver := sin(t * 42.0) * lerpf(5.0, 1.0, k_of(0.0, LIFE * 0.7))
			for i in 3:
				var r := half_width + 12.0 + float(i) * lerpf(9.0, 13.0, size) + shiver * (1.0 + 0.4 * float(i))
				var w := 4.0 if i == 0 else 3.0
				var tint := colour if i != 1 else colour.lightened(0.35)
				for side in [0.0, PI]:
					ink_arc(Vector2.ZERO, r, float(side) - span * 0.5, float(side) + span * 0.5, tint, w)
		if t < FLASH_T:
			var r := lerpf(10.0, 18.0, size) * (1.0 - k_of(0.0, FLASH_T) * 0.5)
			ink_star(hit, 8, r, r * 0.45, Color("fff4c2"))
