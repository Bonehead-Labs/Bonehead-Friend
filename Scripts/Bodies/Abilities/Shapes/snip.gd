extends RefCounted

## The Snip's payoff ("SNIP SNIP!"): the two snips, drawn. A pair of long steel blades opens and
## scissors shut across where the shears bit — once, and again a seventh of a second later, as the
## ability does — a hard white glint where the edges cross, and the snipped ends of thread falling.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Snip", Blades, 1) as Blades
	if piece == null:
		return
	var along := Vector2.RIGHT
	var gap := 0.14
	if ability and ability.body:
		# From the hand to the bite: the blades close across it from the side the shears came from.
		var reach := at - ability.grip_world()
		if reach.length_squared() > 1.0:
			along = reach.normalized()
		gap = ability.num("bite_gap", 0.14)
	piece.along = along
	piece.gap = gap
	piece.fire(at, Blades.LIFE, size, colour)

class Blades extends Piece:
	const LIFE := 0.8
	const CLOSE_T := 0.05
	const OPEN_DEG := 32.0
	const STEEL := Color("dfe6ef")
	const THREAD := Color("4a4f5c")
	var along := Vector2.RIGHT
	var gap := 0.14
	var _bits: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		_bits.clear()
		for i in 6:
			_bits.append({"from": 0.0 if i < 3 else gap, "x": rng.randf_range(-10.0, 10.0),
				"v": rng.randf_range(-60.0, 60.0), "turn": rng.randf_range(0.0, PI)})

	## How open the blades are at `since` into one snip: open, then shut fast, then open a little.
	func _open(since: float) -> float:
		if since < 0.0:
			return 1.0
		if since < CLOSE_T:
			return 1.0 - ease_out(since / CLOSE_T)
		return clampf((since - CLOSE_T) / 0.12, 0.0, 0.5)

	func _draw() -> void:
		var second := t >= gap
		var since := t - (gap if second else 0.0)
		var open := _open(since)
		var shown := 1.0 - k_of(gap + 0.2, gap + 0.34)
		var blade := lerpf(64.0, 84.0, size) * shown
		# Pivot well back from the bite, off him, the blades reaching across it.
		var pivot := -along * blade * 0.7
		if blade > 8.0:
			for s in [-1.0, 1.0]:
				var d := along.rotated(deg_to_rad(OPEN_DEG * open) * float(s))
				var normal := d.orthogonal() * float(s)
				var tip := pivot + d * blade
				var wedge := PackedVector2Array([pivot - normal * 6.0, tip, pivot + normal * 1.5])
				ink_poly(wedge, STEEL if s > 0.0 else STEEL.darkened(0.15))
			# The finger loops behind the pivot: a pair of scissors, unmistakably.
			for s in [-1.0, 1.0]:
				var loop := pivot - along * 13.0 + along.orthogonal() * (9.0 * float(s) * (0.6 + 0.4 * open))
				ink_arc(loop, 7.0, 0.0, TAU, colour, 3.0)
			ink_chip(pivot, 6.0, colour)
		# The glint where the edges cross, as each snip shuts.
		if since >= CLOSE_T * 0.6 and since < CLOSE_T + 0.1:
			var k := (since - CLOSE_T * 0.6) / (CLOSE_T * 0.4 + 0.1)
			var r := lerpf(16.0, 24.0, size) * (1.0 - k * 0.6)
			ink_star(Vector2.ZERO, 4, r, r * 0.2, Color("f4fbff"), 0.4)
			ink_star(Vector2.ZERO, 4, r * 0.6, r * 0.15, colour, 0.4 + PI * 0.25)
		# The snipped ends: short threads falling and turning.
		for b in _bits:
			var s := t - float(b["from"]) - CLOSE_T
			if s <= 0.0 or t > LIFE * 0.9:
				continue
			var p := Vector2(float(b["x"]) + float(b["v"]) * s, 380.0 * s * s)
			var d := Vector2.RIGHT.rotated(float(b["turn"]) + s * 9.0) * 4.0
			ink_line(p - d, p + d, THREAD, 2.0)
