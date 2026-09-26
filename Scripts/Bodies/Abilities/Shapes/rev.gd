extends RefCounted

## The Rev's payoff, every grind: a rooster tail of chips thrown back off the chain along the bar,
## the chain's teeth flickering where it bites, and a blue-black puff of exhaust kicked out of the
## engine. Played several times a second while it grinds, so each one is small and quick; together
## they are the spray a running saw throws.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Rev", Tail, 3) as Tail
	if piece == null:
		return
	var along := Vector2.RIGHT
	var engine := at + Vector2(-60.0, -10.0)
	if ability and ability.body:
		var bar := ability.tip_world() - ability.grip_world()
		if bar.length_squared() > 1.0:
			along = bar.normalized()
		engine = ability.grip_world() - along * 10.0
	piece.along = along
	piece.engine = engine - at
	piece.fire(at, Tail.LIFE, size, colour)

class Tail extends Piece:
	const LIFE := 0.5
	const TEETH_T := 0.1
	const CHIPS := 12
	const PUFFS := 2
	const SAWDUST := [Color("e8b872"), Color("c98a4a"), Color("fff1b8"), Color("5c574c")]
	const SOOT := Color("3a3f4a")

	var along := Vector2.RIGHT
	var engine := Vector2.ZERO
	var _chips: Array = []
	var _puffs: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		# Back along the bar toward the hand and up: the way the chain carries what it cuts.
		var back := -along
		if back.y > 0.0:
			back.y = -back.y
		_chips.clear()
		var chips := CHIPS if amount >= 0.15 else CHIPS - 3
		for i in Piece.count(chips):
			var d := back.rotated(rng.randf_range(-0.35, 0.25) - 0.35 * signf(back.x))
			_chips.append({"v": d * rng.randf_range(300.0, 600.0), "side": rng.randf_range(4.0, 6.0),
				"tint": SAWDUST[i % SAWDUST.size()]})
		_puffs.clear()
		for i in PUFFS:
			_puffs.append({"v": Vector2(-along.x * rng.randf_range(20.0, 50.0), -rng.randf_range(40.0, 70.0)),
				"from": 0.06 * float(i), "r": rng.randf_range(6.0, 9.0)})

	func _draw() -> void:
		var shrink := 1.0 - k_of(LIFE * 0.6, LIFE)
		for c in _chips:
			var v: Vector2 = c["v"]
			var p := v * t + Vector2(0.0, 1100.0) * (0.5 * t * t)
			var side := roundf(float(c["side"]) * shrink)
			if side >= 1.0:
				ink_chip(p, side, c["tint"])
		for puff in _puffs:
			var since := t - float(puff["from"])
			if since <= 0.0:
				continue
			var k := since / LIFE
			var r := float(puff["r"]) * (1.0 + 1.2 * k) * (1.0 - k_of(LIFE * 0.55, LIFE))
			if r < 1.5:
				continue
			var p: Vector2 = (engine + (puff["v"] as Vector2) * since).round()
			draw_circle(p, r + 1.0, OUTLINE)
			draw_circle(p, r, SOOT)
			draw_circle(p + Vector2(-r * 0.3, -r * 0.3).round(), maxf(r * 0.35, 1.0), Color("6a7080"))
		# The teeth biting: a sawtooth along the bar, flickering between two phases.
		if t < TEETH_T:
			var normal := along.orthogonal()
			var phase := 1.0 if int(t * 60.0) % 2 == 0 else -1.0
			var points := PackedVector2Array()
			for i in 9:
				var s := float(i) - 4.0
				points.append(along * s * 7.0 + normal * (6.0 if (i % 2 == 0) == (phase > 0.0) else -6.0))
			ink_polyline(points, colour, 3.0)
