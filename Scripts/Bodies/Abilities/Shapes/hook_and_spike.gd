extends RefCounted

## Hook and Spike's spike ("SKEWERED!"): the spike runs him through. A long steel point shoots out of
## the halberd's tip straight through him and out of his far side, holds for a blink and is gone,
## and what it pushed through him bursts out of his back.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "HookSpike", Skewer) as Skewer
	if piece == null:
		return
	var rect := Piece.him_rect(ability, at)
	var dir := Vector2.RIGHT
	var centre := rect.get_center()
	if at.distance_squared_to(centre) > 16.0:
		# Through his middle: he was reeled onto the point, so that is the way it went into him.
		dir = (centre - at).normalized()
	elif ability and ability.body:
		var shaft := ability.tip_world() - ability.grip_world()
		if shaft.length_squared() > 1.0:
			dir = shaft.normalized()
	# Through to his far side: the length of him along the thrust, and a little more.
	var through := at.distance_to(centre) + (absf(dir.x) * rect.size.x + absf(dir.y) * rect.size.y) * 0.5
	piece.dir = dir
	piece.reach = clampf(through + 44.0, 90.0, 200.0)
	piece.fire(at, Skewer.LIFE, size, colour)

class Skewer extends Piece:
	const LIFE := 0.55
	const OUT_T := 0.04
	const HOLD_T := 0.05
	const THROUGH_T := 0.1
	const CHIPS := 6
	const STEEL := Color("d5dde8")
	var dir := Vector2.RIGHT
	var reach := 120.0
	var _chips: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		_chips.clear()
		for i in Piece.count(CHIPS):
			_chips.append({"v": dir.rotated(rng.randf_range(-0.7, 0.7)) * rng.randf_range(180.0, 380.0),
				"side": rng.randf_range(3.0, 5.0)})

	## Where the point is, and where its back end is: out through him, held a blink, then on through
	## and out of his back, never pulled back across him.
	func _head() -> float:
		return reach * ease_out(k_of(0.0, OUT_T)) + 30.0 * k_of(OUT_T + HOLD_T, OUT_T + HOLD_T + THROUGH_T)

	func _tail() -> float:
		return -8.0 + (reach + 38.0) * ease_out(k_of(OUT_T + HOLD_T, OUT_T + HOLD_T + THROUGH_T))

	func _draw() -> void:
		var head := _head()
		var tail := _tail()
		var normal := dir.orthogonal()
		if head - tail > 12.0:
			var base := lerpf(6.0, 9.0, size)
			var wedge := PackedVector2Array([dir * tail + normal * base, dir * head, dir * tail - normal * base])
			ink_poly(wedge, STEEL)
			# The bright edge down its middle.
			draw_line((dir * (tail + 4.0)).round(), (dir * (head - 12.0)).round(), colour.lightened(0.6), 2.0)
		# Out of his back: chips, and a star where the point came through.
		var exit := dir * reach
		if t >= OUT_T:
			var since := t - OUT_T
			var shrink := 1.0 - k_of(LIFE * 0.6, LIFE)
			for c in _chips:
				var p := exit + (c["v"] as Vector2) * since + Vector2(0.0, 900.0) * (0.5 * since * since)
				var side := roundf(float(c["side"]) * shrink)
				if side >= 1.0:
					ink_chip(p, side, colour.lightened(0.2))
			var s := k_of(OUT_T, OUT_T + 0.12)
			if s < 1.0:
				ink_star(exit, 6, lerpf(14.0, 20.0, size) * (1.0 - s * 0.6), 5.0, Color("fff1b8"))
