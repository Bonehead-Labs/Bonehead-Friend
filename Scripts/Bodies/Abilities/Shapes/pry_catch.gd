extends RefCounted

## The Pry's bite: the claw going in under him. A tink of steel on bone at the claw, two sparks
## squeezed out of the gap, and a small fulcrum wedge set down under it — the lever's point, there
## before the lift that uses it.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "PryCatch", Tink, 1) as Tink
	if piece == null:
		return
	var at_claw := at
	if ability and ability.has_method("_wedge"):
		at_claw = ability.call("_wedge")
	piece.fire(at_claw, Tink.LIFE, size, colour)

class Tink extends Piece:
	const LIFE := 0.4

	func _draw() -> void:
		var s := ease_out(k_of(0.0, 0.08)) * (1.0 - k_of(LIFE * 0.6, LIFE))
		var w := roundf(8.0 * s)
		if w >= 3.0:
			ink_poly(PackedVector2Array([Vector2(-w, 12.0), Vector2(0.0, 12.0 - w * 1.4), Vector2(w, 12.0)]),
				Color("5a5f6e"))
		if t < 0.1:
			ink_star(Vector2.ZERO, 4, 12.0 * (1.0 - k_of(0.0, 0.1) * 0.5), 2.5, Color("f4f8ff"), 0.4)
		var spark := k_of(0.0, 0.25)
		if spark < 1.0:
			for side in [-1.0, 1.0]:
				var p := Vector2(float(side) * (6.0 + 26.0 * spark), -18.0 * spark + 30.0 * spark * spark)
				ink_chip(p, 3.0, colour.lightened(0.5))
