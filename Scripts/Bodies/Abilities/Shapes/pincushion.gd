extends RefCounted

## The morning star's SPIKES! (Bristle): he is a pincushion for a moment. Five iron spikes punch into
## his side one after another, points in and bases out, in a row along where the fan struck; they
## quiver, and then pop back out and drop.
##
## Iron on bone — dark cones with a steel edge — so they read on white where a bright spark would not.

const IRON := Color("2a2e38")
const IRON_EDGE := Color("8f97a8")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Pincushion", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const SPIKES := 5
	const GAP := 0.03
	const GRAVITY := 1100.0

	var _dir := Vector2.RIGHT
	var _spots: Array[Vector2] = []
	var _tilt: Array[float] = []

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var from := ability.com_world() if ability else at - Vector2(100, 0)
		var d := at - from
		_dir = d.normalized() if d.length_squared() > 1.0 else Vector2.RIGHT
		if _spots.is_empty():
			_spots.resize(SPIKES)
			_tilt.resize(SPIKES)
		var across := _dir.orthogonal()
		var order := [0.0, -1.0, 1.0, -2.0, 2.0]
		for i in SPIKES:
			var o: float = order[i]
			_spots[i] = across * o * 15.0 + _dir * absf(o) * 4.0
			_tilt[i] = o * 0.14
		fire(at, 0.72)

	func _paint(_k: float) -> void:
		var out := span(0.5, 0.72)
		for i in SPIKES:
			var t := age - GAP * float(i)
			if t < 0.0:
				continue
			var dir := _dir.rotated(_tilt[i])
			# In: driven from outside to its depth in two frames. Then a quiver, then out and down.
			var drive := ease_out(clampf(t / 0.035, 0.0, 1.0))
			var base: Vector2 = _spots[i] - dir * lerpf(34.0, 6.0, drive)
			var quiver := sin(t * 60.0) * 0.2 * (1.0 - clampf(t / 0.4, 0.0, 1.0))
			var pointing := dir.rotated(quiver)
			if out > 0.0:
				var ot := out * 0.22
				base += -dir * 160.0 * ot + Vector2(0.0, -120.0 * ot + 0.5 * GRAVITY * ot * ot)
				pointing = pointing.rotated(out * 3.0 * (1.0 if i % 2 == 0 else -1.0))
			var scale := (1.0 + 0.5 * size) * (1.0 - span(0.62, 0.72))
			_spike(base, pointing, scale)

	## A cone of iron: its point `reach` along `dir` from `base`, a steel edge on its upper side.
	func _spike(base: Vector2, dir: Vector2, scale: float) -> void:
		if scale <= 0.2:
			return
		var reach := 20.0 * scale
		var half := 7.0 * scale
		var across := dir.orthogonal()
		var tip := base + dir * reach
		shape(PackedVector2Array([tip, base - across * half, base - dir * 3.0 * scale, base + across * half]), IRON)
		line(base - across * (half - 2.0), tip - dir * 3.0, IRON_EDGE, 2.0)
		# Its collar, in the star's own iron colour.
		line(base - across * half, base + across * half, colour, 3.0)
