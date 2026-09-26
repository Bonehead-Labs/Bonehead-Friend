extends RefCounted

## The Ignite's payoff, every burn: a sizzle. Cyan plasma crackles off the blade where it is in him,
## re-forking every other frame; scorch marks blister up on the bone and ride on him (dark on white,
## the one colour that reads on him), and wisps of smoke curl up off them. Five a second while the
## blade is in him, so a slow draw through him leaves a trail of scorch the way a hot blade would.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Ignite", Sizzle, 4) as Sizzle
	if piece == null:
		return
	piece.fire(at, Sizzle.LIFE, size, colour)
	var him: Buddy = ability.buddy() if ability else null
	if him:
		piece.follow(him, at - him.get_interaction_rect().get_center())

class Sizzle extends Piece:
	const LIFE := 0.95
	const CRACKLE_T := 0.18
	const SOOT := Color("2e2824")
	const EMBER := Color("ff8c1a")
	const SMOKE := Color("6d665c")
	const ARCS := 5
	var _seed := 0
	var _crackle := RandomNumberGenerator.new()
	var _flecks: Array = []
	var _wisps: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		_seed = rng.randi()
		_flecks.clear()
		for i in 3:
			_flecks.append({"at": Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0)).round(),
				"side": rng.randf_range(5.0, 8.0)})
		_wisps.clear()
		for i in 2:
			_wisps.append({"x": rng.randf_range(-8.0, 8.0), "phase": rng.randf_range(0.0, TAU),
				"from": 0.04 + 0.1 * float(i)})

	func _draw() -> void:
		# The scorch: blisters of soot with a live ember at the heart while they are fresh, out by
		# growing smaller.
		var left := 1.0 - k_of(LIFE * 0.55, LIFE * 0.9)
		for f in _flecks:
			var side := roundf(float(f["side"]) * left)
			if side < 2.0:
				continue
			var p: Vector2 = f["at"]
			draw_rect(Rect2((p - Vector2(side, side) * 0.5).round(), Vector2(side, side)), SOOT)
			if t < LIFE * 0.35 and side >= 4.0:
				draw_rect(Rect2((p - Vector2(1.0, 1.0)).round(), Vector2(2.0, 2.0)), EMBER)
		# The wisps: a curl of smoke rising and shortening.
		for w in _wisps:
			var since := t - float(w["from"])
			if since <= 0.0:
				continue
			var k := since / (LIFE - float(w["from"]))
			var tall := lerpf(12.0, 44.0, k) * (1.0 - k_of(LIFE * 0.7, LIFE))
			if tall < 5.0:
				continue
			var points := PackedVector2Array()
			for i in 6:
				var s := float(i) / 5.0
				points.append(Vector2(float(w["x"]) + sin(s * 5.0 + float(w["phase"]) + since * 9.0) * 5.0,
					-since * 46.0 - s * tall))
			ink_polyline(points, SMOKE, 3.0)
		# The crackle: forked plasma, re-drawn every other frame so it fizzes.
		if t < CRACKLE_T:
			var local := _crackle
			local.seed = _seed + int(t * 30.0)
			var reach := lerpf(32.0, 46.0, size) * (1.0 - k_of(0.0, CRACKLE_T) * 0.4)
			for i in ARCS:
				var d := Vector2.RIGHT.rotated(TAU * float(i) / float(ARCS) + local.randf_range(-0.5, 0.5))
				var points := PackedVector2Array([Vector2.ZERO])
				var p := Vector2.ZERO
				for leg in 3:
					p += d.rotated(local.randf_range(-0.9, 0.9)) * reach / 3.0
					points.append(p)
				ink_polyline(points, Color("e8fdff") if i % 2 else colour, 3.0 if i % 2 == 0 else 2.0)
