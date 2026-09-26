extends RefCounted

## The Ground Pound's payoff, on the desk where the head came down: the desk cracks — a fissure
## runs out both ways along the floor, forking as it goes — chunks of it jump up and fall back,
## and dust rolls out along the floor either side. The only payoff that is the desk's, not his.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, _ability: WeaponAbility) -> void:
	var piece := Piece.take(afx, "GroundPound", Quake) as Quake
	if piece:
		piece.fire(at, Quake.LIFE, size, colour)

class Quake extends Piece:
	const LIFE := 1.1
	const RUN_T := 0.14
	const CLOSE_FROM := 0.75
	const CHUNKS := 9
	const DUST := Color("cfc9b4")
	const DUST_DARK := Color("9c957f")
	const ROCK_BIG := [
		"..aab.",
		".aaaab",
		"aaaabb",
		"aabbbb",
		".bbbb.",
	]
	const ROCK_SMALL := [
		".ab",
		"aab",
		"bb.",
	]

	var _crack: Array = []
	var _forks: Array = []
	var _chunks: Array = []
	var _rock: Array[Texture2D] = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		if _rock.is_empty():
			var palette := {"a": tint.lightened(0.25), "b": tint.darkened(0.35)}
			_rock.append(Piece.plot(ROCK_BIG, palette))
			_rock.append(Piece.plot(ROCK_SMALL, palette))
		var reach := lerpf(120.0, 200.0, amount)
		# The fissure, both ways: a jagged run of points just under the desk's surface.
		_crack.clear()
		_forks.clear()
		for side in [-1.0, 1.0]:
			var points := PackedVector2Array([Vector2(0.0, -8.0)])
			var x := 0.0
			while x < reach:
				x += rng.randf_range(12.0, 22.0)
				var p := Vector2(float(side) * minf(x, reach), -rng.randf_range(4.0, 13.0))
				points.append(p)
				if rng.randf() < 0.35 and x < reach * 0.8:
					var up := Vector2(float(side) * rng.randf_range(4.0, 12.0), -rng.randf_range(10.0, 20.0))
					_forks.append([p, p + up, x / reach])
			_crack.append(points)
		_chunks.clear()
		for i in Piece.count(CHUNKS):
			var x := rng.randf_range(-reach * 0.7, reach * 0.7)
			_chunks.append({"x": x, "vy": -rng.randf_range(280.0, 560.0) * lerpf(0.8, 1.1, amount),
				"vx": signf(x) * rng.randf_range(10.0, 90.0), "big": i % 3 == 0,
				"from": absf(x) / reach * RUN_T, "quarter": rng.randi() % 4})

	## How much of the fissure is open: running out, holding, closing back from the tips.
	func _open() -> float:
		if t < RUN_T:
			return ease_out(k_of(0.0, RUN_T))
		return 1.0 - k_of(LIFE * CLOSE_FROM, LIFE)

	func _draw() -> void:
		var open := _open()
		# The dust rolling out along the floor both ways, low and wide, shrinking as it slows.
		var roll := ease_out(k_of(0.0, LIFE * 0.7))
		var puff := (1.0 - k_of(LIFE * 0.45, LIFE * 0.8)) * lerpf(8.0, 12.0, size)
		if puff >= 2.0:
			for side in [-1.0, 1.0]:
				for i in 3:
					var p := Vector2(float(side) * (20.0 + roll * lerpf(90.0, 150.0, size) + float(i) * 14.0),
						-puff - 3.0 - float(i % 2) * 4.0)
					var r := puff * (1.0 - 0.2 * float(i))
					draw_circle(p.round(), r + 1.0, OUTLINE)
					draw_circle(p.round(), r, DUST if i != 1 else DUST_DARK)
		# The fissure: a lit rim in the hammer's clay with a black split inside it.
		for points in _crack:
			var shown := PackedVector2Array()
			var total: float = absf((points as PackedVector2Array)[points.size() - 1].x)
			for p in points:
				if absf(p.x) <= total * open + 0.5:
					shown.append(p)
			if shown.size() >= 2:
				ink_polyline(shown, colour, 6.0)
				var core := PackedVector2Array()
				for p in shown:
					core.append(p.round())
				draw_polyline(core, OUTLINE, 2.0)
		for fork in _forks:
			if float(fork[2]) <= open:
				ink_line(fork[0], fork[1], colour, 3.0)
		# The chunks: thrown up where the fissure has reached, tumbling, and gone at the desk again.
		for c in _chunks:
			var since := t - float(c["from"])
			if since <= 0.0:
				continue
			var y := float(c["vy"]) * since + 1400.0 * 0.5 * since * since
			if y > 2.0:
				continue
			var p := Vector2(float(c["x"]) + float(c["vx"]) * since, minf(y, 0.0) - 4.0)
			ink_sprite(_rock[0] if c["big"] else _rock[1], p, 1, int(c["quarter"]) + int(since * 14.0))
