extends RefCounted

## The Iaido's payoff: one clean line, far longer than he is wide, laid across him along the cut —
## a white flash, then held a beat while a glint runs its length — and then it parts, the upper
## half sliding off along the cut and the lower half the other way, until both are gone. A few
## petals drift down from where it was. Thin lines only: he is never covered, only crossed.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Iaido", Cut) as Cut
	if piece == null:
		return
	var dir := Vector2.RIGHT
	if ability:
		var cut = ability.get("_cut_dir")
		if cut is Vector2 and (cut as Vector2).length_squared() > 0.01:
			dir = (cut as Vector2).normalized()
		elif ability.him_world() != Vector2.INF:
			dir = (ability.him_world() - ability.hand_world()).normalized()
	piece.dir = dir
	piece.fire(at, Cut.LIFE, size, colour)

class Cut extends Piece:
	const LIFE := 1.2
	const FLASH_T := 0.05
	const HOLD_T := 0.3
	const PART_T := 0.3
	const PETALS := 5
	const PETAL := [
		"..pp",
		".ppp",
		"ppq.",
		"pq..",
	]

	var dir := Vector2.RIGHT
	var _petal: Texture2D
	var _petals: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		if _petal == null:
			_petal = Piece.plot(PETAL, {"p": Color("ff9cc2"), "q": Color("ff6fa6")})
		_petals.clear()
		var half := _half_length()
		for i in PETALS:
			_petals.append({
				"along": rng.randf_range(-half * 0.8, half * 0.8),
				"fall": rng.randf_range(38.0, 70.0), "sway": rng.randf_range(10.0, 22.0),
				"phase": rng.randf_range(0.0, TAU), "from": FLASH_T + rng.randf_range(0.1, 0.35),
			})

	func _half_length() -> float:
		return lerpf(120.0, 190.0, size)

	func _draw() -> void:
		var half := _half_length()
		var normal := dir.orthogonal()
		var steel := colour.lightened(0.55)
		if t < FLASH_T:
			# The flash: the whole line at once, bright and wide.
			ink_line(-dir * half, dir * half, Color("f4fbff"), 7.0)
		elif t < FLASH_T + HOLD_T:
			ink_line(-dir * half, dir * half, steel, 4.0)
			# A glint running its length, the blade's path still bright.
			var k := k_of(FLASH_T, FLASH_T + HOLD_T * 0.8)
			if k < 1.0:
				var p := -dir * half + dir * (2.0 * half * k)
				draw_line((p - dir * 9.0).round(), (p + dir * 9.0).round(), Color("f4fbff"), 3.0)
				ink_star(p, 4, 9.0, 2.0, Color("f4fbff"))
		else:
			# The parting: two halves, sliding off each other along the cut and shrinking to nothing.
			var k := ease_out(k_of(FLASH_T + HOLD_T, FLASH_T + HOLD_T + PART_T))
			var keep := half * (1.0 - k)
			if keep > 3.0:
				for s in [-1.0, 1.0]:
					var shift: Vector2 = normal * (12.0 * k * float(s)) + dir * (half * 0.6 * k * float(s))
					ink_line(shift - dir * keep, shift + dir * keep, colour if s > 0.0 else steel, 3.0)
		# The petals: drifting down off the line, swaying, and shrinking away.
		for p in _petals:
			var since := t - float(p["from"])
			if since <= 0.0:
				continue
			var left := 1.0 - k_of(LIFE * 0.75, LIFE)
			if left <= 0.0:
				continue
			var at := dir * float(p["along"]) + Vector2(sin(since * 5.0 + float(p["phase"])) * float(p["sway"]),
				since * float(p["fall"]) + 8.0)
			# Shrinking away: the whole petal, then a fleck of it.
			if left > 0.5:
				ink_sprite(_petal, at, 1, int(since * 6.0 + float(p["phase"])) % 4)
			else:
				ink_chip(at, 3.0, Color("ff9cc2"))
