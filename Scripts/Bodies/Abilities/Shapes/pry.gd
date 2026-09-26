extends RefCounted

## The Pry's payoff ("POP!"): leverage. A fulcrum wedge under the claw, a dashed arrow arcing up and
## over the way he was popped, and the bent nails the bar pulled out of him spinning off into the
## air — the crowbar's own trade.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Pry", Pop) as Pop
	if piece == null:
		return
	var rect := Piece.him_rect(ability, at)
	var side := 1.0
	if ability:
		var s = ability.get("_side")
		if s is float and absf(float(s)) > 0.1:
			side = signf(float(s))
		elif ability.body:
			side = 1.0 if rect.get_center().x >= ability.grip_world().x else -1.0
	piece.side = side
	piece.centre = rect.get_center() - at
	piece.half = rect.size.x * 0.5
	piece.fire(at, Pop.LIFE, size, colour)

class Pop extends Piece:
	const LIFE := 0.85
	const DRAW_T := 0.18
	const ERASE_FROM := 0.5
	const NAILS := 3
	const NAIL := [
		"hhhh",
		".nn.",
		".nn.",
		".nn.",
		".nn.",
		".nnn",
		"..nn",
		"...n",
	]
	var side := 1.0
	var centre := Vector2.ZERO
	var half := 24.0
	var _nail: Texture2D
	var _nails: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		if _nail == null:
			_nail = Piece.plot(NAIL, {"h": Color("8d96a8"), "n": Color("c4ccd8")})
		_nails.clear()
		for i in NAILS:
			var d := Vector2(side * rng.randf_range(0.1, 0.6), -1.0).normalized()
			_nails.append({"v": d * rng.randf_range(300.0, 460.0), "from": 0.03 * float(i),
				"quarter": rng.randi() % 4})

	func _draw() -> void:
		# The fulcrum: a dark wedge on the desk side of the claw, there while the arrow is.
		var hold := 1.0 - k_of(LIFE * 0.6, LIFE * 0.75)
		if hold > 0.0:
			var w := 9.0 * hold
			if w >= 3.0:
				ink_poly(PackedVector2Array([Vector2(-w, 12.0), Vector2(0.0, 12.0 - w * 1.4), Vector2(w, 12.0)]),
					Color("5a5f6e"))
		# The arrow: up out of him and over, drawn along, then eaten from its tail.
		var drawn := ease_out(k_of(0.0, DRAW_T))
		var eaten := k_of(LIFE * ERASE_FROM, LIFE)
		var r := half + lerpf(30.0, 46.0, size)
		var start := PI * 0.5 + side * PI * 0.5
		var sweep := side * PI * 0.8
		if drawn > eaten:
			var dashes := 7
			for i in dashes:
				var a0 := float(i) / float(dashes)
				var a1 := a0 + 0.6 / float(dashes)
				if a1 < eaten or a0 > drawn:
					continue
				ink_arc(centre, r, start + sweep * maxf(a0, eaten), start + sweep * minf(a1, drawn), colour, 5.0)
			if drawn >= 1.0 and eaten < 0.9:
				var tip := centre + Vector2.RIGHT.rotated(start + sweep) * r
				var along := Vector2.RIGHT.rotated(start + sweep + PI * 0.5 * signf(sweep))
				var normal := along.orthogonal()
				ink_poly(PackedVector2Array([tip + along * 14.0, tip + normal * 10.0, tip - normal * 10.0]), colour)
		# The nails, popped out and spinning, falling away.
		for n in _nails:
			var since := t - float(n["from"])
			if since <= 0.0 or t > LIFE * 0.85:
				continue
			var p := (n["v"] as Vector2) * since + Vector2(0.0, 1100.0) * (0.5 * since * since)
			ink_sprite(_nail, p, 1, int(n["quarter"]) + int(since * 16.0))
