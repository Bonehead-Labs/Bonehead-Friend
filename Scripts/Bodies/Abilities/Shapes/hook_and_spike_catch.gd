extends RefCounted

## Hook and Spike's catch ("HOOKED!"): fish on. The line from the spike to where the hook bit twangs
## taut — a wave running down it and dying — tug marks jerk out behind the hook, and the barb
## glints where it went in.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "HookCatch", Twang) as Twang
	if piece == null:
		return
	var hook := at
	var from := at + Vector2(-160.0, 0.0)
	if ability:
		var caught = ability.get("_caught_at")
		if caught is Vector2 and (caught as Vector2).is_finite() and caught != Vector2.ZERO:
			hook = caught
		if ability.body:
			from = ability.tip_world()
	piece.line = from - hook
	piece.fire(hook, Twang.LIFE, size, colour)

class Twang extends Piece:
	const LIFE := 0.5
	const WAVE_T := 0.36
	var line := Vector2.LEFT * 100.0

	func _draw() -> void:
		var d := line.normalized() if line.length_squared() > 1.0 else Vector2.LEFT
		var normal := d.orthogonal()
		# The line twanging: a standing wave along it, dying.
		var die := k_of(0.0, WAVE_T)
		if die < 1.0:
			var amp := lerpf(6.0, 10.0, size) * (1.0 - die)
			var points := PackedVector2Array()
			var n := 16
			for i in n + 1:
				var s := float(i) / float(n)
				points.append(line * s + normal * sin(s * PI * 3.0) * sin(t * 70.0) * amp * sin(s * PI))
			ink_polyline(points, colour.lightened(0.4), 3.0)
		# The tug: three jerk marks behind the hook, away from the pull.
		var tug := 1.0 - k_of(LIFE * 0.5, LIFE)
		if tug > 0.0:
			var jerk := ease_out(k_of(0.0, 0.08)) * 8.0
			for i in 3:
				var r := (12.0 + float(i) * 9.0 + jerk) * tug
				var span := 0.9 * tug
				var face := (-d).angle()
				ink_arc(Vector2.ZERO, r, face - span * 0.5, face + span * 0.5, colour.lightened(0.2), 4.0)
		if t < 0.12:
			ink_star(Vector2.ZERO, 4, 11.0 * (1.0 - k_of(0.0, 0.12) * 0.5), 2.5, Color("f4f8ff"), 0.4)
