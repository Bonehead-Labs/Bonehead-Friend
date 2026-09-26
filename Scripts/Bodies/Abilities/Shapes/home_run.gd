extends RefCounted

## The Home Run's payoff: a CRACK off the barrel, splinters flying back past the bat, and a baseball
## leaving him on a long rising arc for the sky, a dotted trail behind it, until it is a speck and
## a twinkle — going, going, gone. Nothing else in the game sends a ball off the top of the desk.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "HomeRun", Crack) as Crack
	if piece == null:
		return
	var side := 1.0
	if ability:
		var him := ability.him_world()
		if him != Vector2.INF:
			side = 1.0 if him.x >= ability.grip_world().x else -1.0
	piece.side = side
	piece.fire(at, Crack.LIFE, size, colour)

class Crack extends Piece:
	const LIFE := 1.05
	const CRACK_T := 0.1
	const FLY_FROM := 0.03
	const FLY_T := 0.62
	const TWINKLE_T := 0.16
	const SPLINTERS := 7
	const WOOD := Color("d9a066")
	const WOOD_DARK := Color("a8692e")
	const PALE := Color("fff1b8")
	const BALL := [
		"..wwww..",
		".wrwwrw.",
		"wrwwwwrw",
		"wwwwwwww",
		"wwwwwwsw",
		"wrwwwwrw",
		".wrwwrs.",
		"..wwss..",
	]
	const SPECK := [
		".ww.",
		"wwrw",
		"wrws",
		".ws.",
	]

	var side := 1.0
	var _ball: Texture2D
	var _speck: Texture2D
	var _spikes: PackedFloat32Array = []
	var _splinters: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		z_index = 0
		if _ball == null:
			var palette := {"w": Color("fbf7ee"), "s": Color("cfc6b4"), "r": Color("e0402e")}
			_ball = Piece.plot(BALL, palette)
			_speck = Piece.plot(SPECK, palette)
		_spikes.clear()
		for i in 10:
			_spikes.append(rng.randf_range(0.65, 1.0))
		# Back past the bat and up: the barrel shatters toward the hand that swung it.
		_splinters.clear()
		for i in Piece.count(SPLINTERS):
			var angle := deg_to_rad(rng.randf_range(-80.0, 10.0))
			var speed := rng.randf_range(260.0, 520.0) * lerpf(0.7, 1.1, size)
			_splinters.append({
				"v": Vector2(cos(angle) * -side, sin(angle)) * speed,
				"turn": rng.randf_range(0.0, TAU), "spin": rng.randf_range(-14.0, 14.0),
				"length": rng.randf_range(12.0, 22.0), "tint": WOOD if i % 3 else WOOD_DARK,
			})

	## Where the ball is `k` of the way along its flight: out and up, slowing as it climbs away.
	func _ball_at(k: float) -> Vector2:
		var reach := lerpf(260.0, 400.0, size)
		var climb := lerpf(220.0, 340.0, size)
		# Out at fifty degrees and flattening as it climbs away: a drive, not a pop-up.
		return Vector2(side * reach * k, -climb * k * (1.4 - 0.4 * k))

	func _draw() -> void:
		# The splinters, thrown and falling, shorter as they go.
		for s in _splinters:
			var v: Vector2 = s["v"]
			var p := v * t + Vector2(0.0, 900.0) * (0.5 * t * t)
			var shrink := 1.0 - k_of(LIFE * 0.4, LIFE * 0.6)
			if shrink <= 0.0:
				continue
			var d := Vector2.RIGHT.rotated(float(s["turn"]) + float(s["spin"]) * t)
			var half := d * float(s["length"]) * 0.5 * shrink
			ink_line(p - half, p + half, s["tint"], 4.0)
		# The trail: a dot every so often along the path the ball took, eaten from the start once the
		# ball has gone.
		var fly := k_of(FLY_FROM, FLY_FROM + FLY_T)
		var tail := k_of(FLY_FROM + FLY_T, LIFE)
		var step := 0.045
		var k := step
		while k < fly:
			if k > tail:
				ink_chip(_ball_at(k), 5.0 if k < 0.55 else 3.0, colour)
			k += step
		# The ball, near and then a speck, and a twinkle where it went.
		if t >= FLY_FROM and fly < 1.0:
			var at := _ball_at(fly)
			ink_sprite(_ball if fly < 0.5 else _speck, at)
		elif fly >= 1.0:
			var tw := k_of(FLY_FROM + FLY_T, FLY_FROM + FLY_T + TWINKLE_T)
			if tw < 1.0:
				var r := 16.0 * sin(tw * PI) + 4.0
				ink_star(_ball_at(1.0), 4, r, r * 0.25, PALE, tw * PI * 0.5)
		# The CRACK: a jagged burst off the barrel, gone in a few frames so it never sits on him.
		var c := k_of(0.0, CRACK_T)
		if c < 1.0:
			var r := lerpf(26.0, 44.0, size) * (1.0 - c * 0.8)
			_crack(-Vector2(side * 6.0, 0.0), r)

	func _crack(at: Vector2, r: float) -> void:
		if r < 6.0:
			return
		for pass_ in 3:
			var grow := 3.0 if pass_ == 0 else 0.0
			var part := 0.5 if pass_ == 2 else 1.0
			var tint: Color = OUTLINE if pass_ == 0 else (colour if pass_ == 1 else PALE)
			var polygon := PackedVector2Array()
			for i in 20:
				var spike := _spikes[i >> 1] if i % 2 == 0 else 0.34
				var rr := r * part * spike + grow
				polygon.append(at + Vector2.UP.rotated(0.3 + TAU * float(i) / 20.0) * rr)
			draw_colored_polygon(polygon, tint)
