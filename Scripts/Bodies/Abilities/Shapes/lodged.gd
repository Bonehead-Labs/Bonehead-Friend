extends RefCounted

## The cleaver's THUNK! (Embed): it has gone in and it is staying. Dark cracks run into the bone from
## where the blade went in, the handle sticking out of him shivers between two sets of vibration marks,
## and heavy dashes kick out of the wound on the side it came from.
##
## Drawn where the cleaver went in, on his outline, not at his middle: the blade in him is the moment.
## The cracks are dark lines on white bone, which read where anything bright would not; nothing is red
## — cartoon, not gore.

const CRACK := Color("2a2420")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Lodged", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	var _into := Vector2.RIGHT
	var _grip := Vector2.ZERO
	var _cracks: Array[PackedVector2Array] = []

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var blade := ability.com_world() if ability else at - Vector2(40, 0)
		_grip = ability.grip_world() if ability else blade
		var entry := blade
		var him := ability.buddy() if ability else null
		if him:
			var rect := him.get_interaction_rect()
			var centre := rect.get_center()
			var into := centre - blade
			_into = into.normalized() if into.length_squared() > 1.0 else Vector2.RIGHT
			# Where the line from the blade to his middle crosses his outline: the wound.
			entry = _edge(rect, blade, centre)
		fire(entry, 0.66)
		_crack_up()

	## The first point of `rect` on the way from `from` to `to`, or `from` if it is already inside.
	static func _edge(rect: Rect2, from: Vector2, to: Vector2) -> Vector2:
		if rect.has_point(from):
			return from
		for i in 33:
			var p := from.lerp(to, float(i) / 32.0)
			if rect.has_point(p):
				return p
		return to

	## Five cracks, each a line with a kink in it, fanned into him from the wound.
	func _crack_up() -> void:
		if _cracks.is_empty():
			_cracks.resize(5)
		for i in 5:
			var a := lerpf(-1.0, 1.0, float(i) / 4.0) + rng.randf_range(-0.12, 0.12)
			var d := _into.rotated(a)
			var reach := rng.randf_range(16.0, 30.0) * (0.8 + 0.4 * size)
			var kink := d.rotated(rng.randf_range(-0.6, 0.6)) * reach * 0.5
			var tip := kink + d.rotated(rng.randf_range(-0.5, 0.5)) * reach * 0.6
			_cracks[i] = PackedVector2Array([Vector2.ZERO, kink, tip])

	func _paint(_k: float) -> void:
		_draw_cracks()
		_kick()
		_shiver()

	## The cracks run out in two frames and draw back into the wound at the end.
	func _draw_cracks() -> void:
		var run := clampf(age / 0.035, 0.0, 1.0)
		var back := span(0.44, 0.66)
		var k := run * (1.0 - back)
		for crack in _cracks:
			var points := PackedVector2Array()
			for p in crack:
				points.append((p * k).round())
			if points[2].length() >= 3.0:
				draw_polyline(points, CRACK, 3.0)

	## The handle shivering: marks either side of it, swapping sides every other frame.
	func _shiver() -> void:
		if age >= 0.56:
			return
		var handle := _grip - global_position
		var along := handle.normalized() if handle.length_squared() > 1.0 else Vector2.UP
		var across := along.orthogonal()
		var wobble := 4.0 if int(age * 30.0) % 2 == 0 else -4.0
		for side in [-1.0, 1.0]:
			for j in 2:
				var mark: Vector2 = handle + across * side * (18.0 + 8.0 * float(j) + wobble) - along * 6.0
				var reach := 10.0 - 3.0 * float(j)
				line(mark - along * reach, mark + along * reach, colour, 3.0)

	## The blow: heavy dashes out of the wound, back the way it came, drawn in outward.
	func _kick() -> void:
		var k := span(0.0, 0.26)
		if k >= 1.0:
			return
		var out := -_into
		for i in 5:
			var d := out.rotated(lerpf(-1.1, 1.1, float(i) / 4.0))
			var far := 40.0 + 22.0 * size + 12.0 * (1.0 - absf(float(i) - 2.0) / 2.0)
			var near := lerpf(12.0, far, ease_out(k))
			if far - near >= 3.0:
				line(d * near, d * far, colour, 5.0)
