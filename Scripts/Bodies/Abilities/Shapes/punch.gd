extends RefCounted

## The Punch's payoff ("CHUNK!"): the jaws slam shut — two bars meeting on the bite — and the chads
## come out: a burst of punched paper dots in five pastel colours, round and rimmed, thrown clear of
## him and fluttering down slowly, swaying as paper does. Nothing else in the game snows.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "Punch", Chads) as Chads
	if piece == null:
		return
	var rect := Piece.him_rect(ability, at)
	var out := (at - rect.get_center()).normalized() if at.distance_squared_to(rect.get_center()) > 1.0 \
		else Vector2.LEFT
	piece.out = out
	piece.fire(at, Chads.LIFE, size, colour)

class Chads extends Piece:
	const LIFE := 1.3
	const JAW_T := 0.05
	const JAW_HOLD := 0.1
	const COUNT := 16
	const PAPER := [Color("ff8fbb"), Color("ffe08a"), Color("8fd3ff"), Color("c9a8ff"), Color("fff4dc")]
	const DOT := [".xx.", "xxxx", "xxxx", ".xx."]
	const SMALL := ["xx", "xx"]
	var out := Vector2.LEFT
	var _dots: Array[Texture2D] = []
	var _small: Array[Texture2D] = []
	var _chads: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		if _dots.is_empty():
			for paper in PAPER:
				_dots.append(Piece.plot(DOT, {"x": paper}))
				_small.append(Piece.plot(SMALL, {"x": paper}))
		_chads.clear()
		var many := int(lerpf(10.0, float(COUNT), amount))
		for i in Piece.count(many):
			# Out of the bite, away from him and up.
			var d := (out + Vector2(0.0, -0.9)).normalized().rotated(rng.randf_range(-1.1, 1.1))
			_chads.append({"v": d * rng.randf_range(150.0, 330.0), "sway": rng.randf_range(8.0, 20.0),
				"phase": rng.randf_range(0.0, TAU), "paper": i % PAPER.size(), "fall": rng.randf_range(90.0, 150.0)})

	func _draw() -> void:
		# The chads: a quick throw, then paper drag takes over and they flutter down.
		for c in _chads:
			var v: Vector2 = c["v"]
			var drag := 1.0 - exp(-t * 7.0)
			var p := v * drag / 7.0 + Vector2(sin(t * 7.0 + float(c["phase"])) * float(c["sway"]) * drag,
				float(c["fall"]) * t * t * 0.9)
			var small := t > LIFE * 0.72
			if t > LIFE * 0.92:
				continue
			ink_sprite((_small if small else _dots)[int(c["paper"])], p)
		# The jaws: two bars snapping shut across the bite and holding a moment.
		if t < JAW_T + JAW_HOLD:
			var shut := ease_out(k_of(0.0, JAW_T))
			var across := out.orthogonal()
			var gap := lerpf(24.0, 4.0, shut)
			var bar := lerpf(16.0, 22.0, size)
			for s in [-1.0, 1.0]:
				var mid := across * gap * float(s)
				ink_line(mid - out * bar, mid + out * bar, Color("4a4f5c") if s > 0.0 else colour, 6.0)
