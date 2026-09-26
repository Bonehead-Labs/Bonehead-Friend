extends RefCounted

## The greatsword's CLEAVE (Momentum): the weight of the swing, as a picture of where the blade has
## just been. Three echoes of the sword hang behind it round the hand, periwinkle and darker the older
## they are, and go out one at a time from the oldest; a diamond — the chain's own notch — slams out
## of the point, with the heavy bars of its travel behind it.
##
## A flywheel's payoff, not a cut's: the scythe's crescent flies, the machete's gust blows across and
## the katana's line is a line. This one is the sword itself, three times, in the air.

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "CleaveEcho", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const ECHOES := 3
	## Radians between echoes, back along the swing.
	const STEP := 0.3

	var _texture: Texture2D
	var _sprite_xf := Transform2D.IDENTITY
	var _origin := Vector2.ZERO
	var _flip := false
	var _grip := Vector2.ZERO
	var _turn := 1.0
	var _tangent := Vector2.RIGHT

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		_texture = null
		var sprite := ability.sprite() if ability else null
		if sprite and sprite.texture:
			_texture = silhouette(sprite.texture)
			_sprite_xf = sprite.global_transform
			var tex_size := sprite.texture.get_size()
			_origin = sprite.offset - tex_size * 0.5 if sprite.centered else sprite.offset
			_flip = sprite.flip_h
		_grip = ability.grip_world() if ability else at
		var omega := ability.body.angular_velocity if ability and ability.body else 1.0
		_turn = 1.0 if omega >= 0.0 else -1.0
		var r := at - _grip
		_tangent = Vector2(-r.y, r.x).normalized() * _turn if r.length_squared() > 1.0 else Vector2.RIGHT
		fire(at, 0.5)

	func _paint(_k: float) -> void:
		_echoes()
		_diamond()

	## The sword where it was: rotated back about the hand, oldest first so the newest is on top, each
	## gone at its own moment.
	func _echoes() -> void:
		if _texture == null:
			return
		var here := Transform2D(0.0, -global_position)
		for n in range(ECHOES, 0, -1):
			if age >= 0.12 + 0.1 * float(ECHOES - n):
				continue
			var back := Transform2D(-_turn * STEP * float(n), Vector2.ZERO)
			var about := Transform2D(0.0, _grip) * back * Transform2D(0.0, -_grip)
			var xf := here * about * _sprite_xf
			var tint := colour.darkened(0.12 * float(n - 1))
			draw_set_transform_matrix(xf)
			var rect := Rect2(_origin, _texture.get_size())
			if _flip:
				rect = Rect2(Vector2(_origin.x + rect.size.x, _origin.y), Vector2(-rect.size.x, rect.size.y))
			for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_texture_rect(_texture, Rect2(rect.position + o, rect.size), false, OUTLINE)
			draw_texture_rect(_texture, rect, false, tint)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	## The notch slamming out of the point, and the bars of its travel.
	func _diamond() -> void:
		var grow := ease_out(span(0.0, 0.26))
		if age < 0.3:
			for ring in 2:
				var r := lerpf(14.0, 40.0 + 36.0 * size, grow) * (1.0 if ring == 0 else 0.6)
				var w := lerpf(8.0, 3.0, grow) * (1.0 if ring == 0 else 0.6)
				var corners := PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0),
					Vector2(0, -r)])
				strokes(corners, colour if ring == 0 else colour.lightened(0.35), w)
			if age < 0.1:
				var c := 14.0 * (1.0 - age / 0.1) + 5.0
				shape(PackedVector2Array([Vector2(0, -c), Vector2(c, 0), Vector2(0, c), Vector2(-c, 0)]),
					colour.lightened(0.6))
		# Behind the point, along the way it came: drawn in from the point end.
		var bars := ease_out(span(0.04, 0.36))
		var far := 64.0 + 24.0 * size
		var across := _tangent.orthogonal()
		for i in 3:
			var off := across * (float(i) - 1.0) * 10.0
			var reach := far - (8.0 if i == 1 else 20.0)
			var near := lerpf(12.0, reach, bars)
			if reach - near >= 4.0:
				line(-_tangent * near + off, -_tangent * reach + off, colour.lightened(0.25), 4.0 if i == 1 else 3.0)
