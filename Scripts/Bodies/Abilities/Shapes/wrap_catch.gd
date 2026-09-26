extends RefCounted

## The Wrap's catch ("GOTCHA!"): a lasso of chain cinched round his middle. It whips in from wide and
## tight, the back of the loop behind him and the front across him, as a chain round a waist is, with
## squeeze marks where it bites; then it unwinds round him and is gone.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var rect := Piece.him_rect(ability, at)
	var him: Buddy = ability.buddy() if ability else null
	for front in [false, true]:
		var loop := Piece.take(afx, "WrapLoopFront" if front else "WrapLoopBack", Loop, 1) as Loop
		if loop == null:
			continue
		loop.front = front
		loop.half_width = rect.size.x * 0.5
		loop.fire(rect.get_center() + Vector2(0.0, 6.0), Loop.LIFE, size, colour)
		if him:
			loop.follow(him, Vector2(0.0, 6.0))

class Loop extends Piece:
	const LIFE := 0.8
	const CINCH_T := 0.12
	const UNWIND_FROM := 0.5
	const STEPS := 26
	var front := true
	var half_width := 24.0

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		z_index = 0 if front else -41

	func _draw() -> void:
		var cinch := ease_out(k_of(0.0, CINCH_T))
		var rx := lerpf(half_width * 2.4, half_width + 7.0, cinch)
		var ry := lerpf(22.0, 9.0, cinch)
		var whirl := (1.0 - cinch) * 3.0 + t * 2.0
		var shown := 1.0 - ease_out(k_of(UNWIND_FROM, LIFE))
		if shown <= 0.02:
			return
		var steel := colour
		var lit := colour.lightened(0.5)
		var run := PackedVector2Array()
		var runs: Array = []
		for i in STEPS + 1:
			var a := whirl + TAU * shown * float(i) / float(STEPS)
			if (sin(a) >= 0.0) == front:
				run.append(Vector2(cos(a) * rx, sin(a) * ry))
			elif run.size() > 0:
				runs.append(run)
				run = PackedVector2Array()
		if run.size() > 0:
			runs.append(run)
		for points in runs:
			if (points as PackedVector2Array).size() < 2:
				continue
			ink_polyline(points, steel, 6.0)
			# The links: every other stretch lit, so the band reads as a chain.
			for i in range(0, points.size() - 1, 2):
				draw_line((points[i] as Vector2).round(), (points[i + 1] as Vector2).round(), lit, 3.0)
		# Squeeze marks at his sides as it bites, on the front piece only.
		if front and t > CINCH_T * 0.8 and t < CINCH_T + 0.2:
			for s in [-1.0, 1.0]:
				var side := Vector2(float(s) * (rx + 8.0), 0.0)
				for k in 3:
					var d := Vector2(float(s), (float(k) - 1.0) * 0.7).normalized()
					ink_line(side + d * 3.0, side + d * 11.0, lit, 2.0)
