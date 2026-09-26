extends RefCounted

## The office mug's HOT! (Hot Coffee): it lands, and it is hot. A brown splat for a frame or two where
## it hit, a crown of coffee drops thrown up and back off him, each with a lighter streak behind it, and
## three wavy threads of steam rising off his shoulders, wiggling as they go.
##
## Coffee browns and steam, each with a dark rim: steam is pale, and pale on bone is nothing without
## one. The steam is beside his head, not over it, where his badge is.

const DARK := Color("4a2a14")
const LIGHT := Color("8a5a2b")
const STEAM := Color("f4f1e6")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "CoffeeSplash", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const DROPS := 8
	const GRAVITY := 1000.0
	var _speed: Array[Vector2] = []
	var _blob: Array[Vector2] = []
	var _steam: Array[Vector2] = []

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		fire(at, 0.95)
		var mug := ability.body.global_position if ability and ability.body else at - Vector2(100, 0)
		var back := -1.0 if at.x >= mug.x else 1.0
		if _speed.is_empty():
			_speed.resize(DROPS)
			_blob.resize(5)
			_steam.resize(3)
		# A crown: up, and leaning back toward the mug it came from.
		var up := Vector2(back * 0.25, -1.0).normalized()
		for i in DROPS:
			var a := lerpf(-1.2, 1.2, float(i) / float(DROPS - 1)) + rng.randf_range(-0.1, 0.1)
			_speed[i] = up.rotated(a) * rng.randf_range(260.0, 380.0) * (0.85 + 0.3 * s)
		for i in 5:
			_blob[i] = Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-6.0, 6.0))
		var him := ability.buddy() if ability else null
		if him:
			var rect := him.get_interaction_rect()
			var top := rect.position.y + 10.0
			_steam[0] = Vector2(rect.position.x - 4.0, top + 6.0) - global_position
			_steam[1] = Vector2(rect.end.x + 4.0, top + 6.0) - global_position
			_steam[2] = Vector2(rect.get_center().x + back * (rect.size.x * 0.5 + 16.0), top + 34.0) - global_position
		else:
			_steam[0] = Vector2(-24, -30)
			_steam[1] = Vector2(24, -30)
			_steam[2] = Vector2(36, -10)

	func _paint(_k: float) -> void:
		_splat()
		_crown()
		for i in 3:
			_thread(i)

	## Where it hit: a blob for a couple of frames, then shrinking to nothing.
	func _splat() -> void:
		var k := span(0.0, 0.1)
		if k >= 1.0:
			return
		var grow := (1.0 - k) * (0.9 + 0.3 * size)
		for p in _blob:
			draw_circle(p.round(), 6.0 * grow + RIM, OUTLINE)
		for p in _blob:
			draw_circle(p.round(), 6.0 * grow, DARK)
		for p in _blob:
			draw_circle((p + Vector2(-1, -2)).round(), 3.0 * grow, LIGHT)

	## The crown: drops thrown up and back, streaks behind them, gone by scale.
	func _crown() -> void:
		var t := age
		var shrink := 1.0 - span(0.55, 0.8)
		if shrink <= 0.0:
			return
		for i in DROPS:
			var v: Vector2 = _speed[i]
			var p := v * t + Vector2(0.0, 0.5 * GRAVITY * t * t)
			var now := v + Vector2(0.0, GRAVITY * t)
			var r := (3.5 + 1.5 * float(i % 3)) * shrink
			if now.length_squared() > 100.0:
				line(p - now.normalized() * (8.0 + 6.0 * shrink), p, LIGHT, 3.0)
			disc(p, r, DARK)
			if r >= 3.0:
				draw_rect(Rect2((p + Vector2(-2, -2)).round(), Vector2(2, 2)), LIGHT)

	## A thread of steam: a wiggle rising, drawn in from the bottom.
	func _thread(i: int) -> void:
		var start := 0.08 + 0.08 * float(i)
		var k := span(start, 0.95)
		if k <= 0.0 or k >= 1.0:
			return
		var base: Vector2 = _steam[i] + Vector2(0.0, -40.0 * k)
		var tall := 44.0 * (1.0 - span(0.6, 0.95)) * minf(1.0, k * 4.0)
		if tall < 6.0:
			return
		var points := PackedVector2Array()
		for m in 8:
			var f := float(m) / 7.0
			points.append(base + Vector2(sin(f * TAU * 1.2 + age * 12.0 + float(i)) * 6.0, -tall * f))
		strokes(points, STEAM, 4.0)
