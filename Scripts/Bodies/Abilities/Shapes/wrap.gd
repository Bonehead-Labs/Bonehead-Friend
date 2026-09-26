extends RefCounted

## The Wrap's fling ("FLING!"): a hammer throw let go. Speed lines stream off the back of him the
## way he is flying, riding with him and shortening as he slows, and the loop of chain that held
## him springs open, its links flung off behind.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "WrapFling", Fling) as Fling
	if piece == null:
		return
	var rect := Piece.him_rect(ability, at)
	var him: Buddy = ability.buddy() if ability else null
	var dir := Vector2(1.0, -0.4).normalized()
	if him and him.linear_velocity.length_squared() > 400.0:
		dir = him.linear_velocity.normalized()
	elif ability and ability.body:
		dir = (rect.get_center() - ability.hand_world()).normalized()
	piece.dir = dir
	piece.radius = rect.size.length() * 0.4
	piece.fire(rect.get_center(), Fling.LIFE, size, colour)
	if him:
		piece.follow(him)

class Fling extends Piece:
	const LIFE := 0.6
	const STREAKS := 5
	const LINKS := 6
	const FLAT := ["xxxxx", "xw..x", "xxxxx"]
	var dir := Vector2.RIGHT
	var radius := 40.0
	var _link: Texture2D
	var _streaks: Array = []
	var _links: Array = []
	var _from := Vector2.ZERO

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		_from = at
		if _link == null:
			_link = Piece.plot(FLAT, {"x": tint, "w": tint.lightened(0.5)})
		_streaks.clear()
		for i in STREAKS:
			_streaks.append({"off": (float(i) - float(STREAKS - 1) * 0.5) * 11.0,
				"length": rng.randf_range(60.0, 130.0) * lerpf(0.8, 1.2, amount)})
		_links.clear()
		for i in LINKS:
			var d := (-dir).rotated(rng.randf_range(-1.2, 1.2))
			_links.append({"v": d * rng.randf_range(140.0, 300.0), "quarter": i % 2})

	func _draw() -> void:
		var normal := dir.orthogonal()
		var left := 1.0 - k_of(LIFE * 0.35, LIFE)
		for s in _streaks:
			var length := float(s["length"]) * left
			if length < 6.0:
				continue
			var start := -dir * radius + normal * float(s["off"])
			ink_line(start, start - dir * length, colour.lightened(0.25) if int(s["off"]) % 2 == 0 else colour.lightened(0.6), 4.0)
		# The links: thrown off where he was let go, not riding with him.
		var back := _from - global_position
		for l in _links:
			var v: Vector2 = l["v"]
			var p := back + v * t + Vector2(0.0, 900.0) * (0.5 * t * t)
			if t < LIFE * 0.8:
				ink_sprite(_link, p, 1, int(l["quarter"]) + int(t * 12.0))
