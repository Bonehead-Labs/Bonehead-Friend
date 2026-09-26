extends RefCounted

## The Ground Pound's payoff, on the desk where the head came down: the desk breaks. Slabs of it
## heave up out of the floor line both ways from the impact, tallest at the middle and tipped away
## from it, running out as the crack does; a split opens along their feet; chunks jump up and fall
## back; dust rolls out along the floor either side. The only payoff that is the desk's, not his.
##
## **Everything stands on the floor line and rises from it** (`at` is where the head met the desk).
## The desk is often the bottom edge of the window — the play area, and every capture — so anything
## drawn across the line, or just under it, is half off screen: the first fissure was a six-pixel
## zigzag along the window's edge and read as a scratch. The slabs are what carries it: broken floor
## standing up is the picture of a ground pound, and it is all above the line.

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
	## Slabs each way, and how tall the one at the impact stands.
	const SLABS := 5
	const TALLEST := 30.0
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
	var _slabs: Array = []
	var _chunks: Array = []
	var _rock: Array[Texture2D] = []
	var _reach := 160.0

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		if _rock.is_empty():
			var palette := {"a": tint.lightened(0.25), "b": tint.darkened(0.35)}
			_rock.append(Piece.plot(ROCK_BIG, palette))
			_rock.append(Piece.plot(ROCK_SMALL, palette))
		_reach = lerpf(120.0, 200.0, amount)
		# The split along the floor, both ways: a jagged run of points just above the line.
		_crack.clear()
		for side in [-1.0, 1.0]:
			var points := PackedVector2Array([Vector2(0.0, -3.0)])
			var x := 0.0
			while x < _reach:
				x += rng.randf_range(10.0, 18.0)
				points.append(Vector2(float(side) * minf(x, _reach), -rng.randf_range(2.0, 6.0)))
			_crack.append(points)
		# The slabs: broken floor heaved up out of the line, tipped away from the impact, tallest at
		# it and smaller the further out, each standing up as the crack reaches it.
		_slabs.clear()
		for side in [-1.0, 1.0]:
			var x := rng.randf_range(4.0, 8.0)
			for i in SLABS:
				var out := x / _reach
				if out >= 0.95:
					break
				var width := rng.randf_range(12.0, 18.0) * lerpf(1.0, 0.7, out)
				_slabs.append({"x": float(side) * (x + width * 0.5), "w": width, "side": float(side),
					"h": TALLEST * lerpf(0.75, 1.1, amount) * lerpf(1.0, 0.35, out) * rng.randf_range(0.8, 1.1),
					"tip": rng.randf_range(0.25, 0.55), "from": out * RUN_T, "lean": rng.randf_range(-0.2, 0.2)})
				x += width + rng.randf_range(4.0, 14.0)
		_chunks.clear()
		for i in Piece.count(CHUNKS):
			var x := rng.randf_range(-_reach * 0.7, _reach * 0.7)
			_chunks.append({"x": x, "vy": -rng.randf_range(280.0, 560.0) * lerpf(0.8, 1.1, amount),
				"vx": signf(x) * rng.randf_range(10.0, 90.0), "big": i % 3 == 0,
				"from": absf(x) / _reach * RUN_T, "quarter": rng.randi() % 4})

	## How much of the break is open: running out, holding, closing back from the tips.
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
		# The slabs, far ones first so the tall ones at the impact stand in front of them.
		for i in range(_slabs.size() - 1, -1, -1):
			_slab(_slabs[i], open)
		# The split at their feet: a lit rim in the hammer's clay with a black split inside it.
		for points in _crack:
			var shown := PackedVector2Array()
			var total: float = absf((points as PackedVector2Array)[points.size() - 1].x)
			for p in points:
				if absf(p.x) <= total * open + 0.5:
					shown.append(p)
			if shown.size() >= 2:
				ink_polyline(shown, colour, 4.0)
				var core := PackedVector2Array()
				for p in shown:
					core.append(p.round())
				draw_polyline(core, OUTLINE, 2.0)
		# The chunks: thrown up where the break has reached, tumbling, and gone at the desk again.
		for c in _chunks:
			var since := t - float(c["from"])
			if since <= 0.0:
				continue
			var y := float(c["vy"]) * since + 1400.0 * 0.5 * since * since
			if y > 2.0:
				continue
			var p := Vector2(float(c["x"]) + float(c["vx"]) * since, minf(y, 0.0) - 4.0)
			ink_sprite(_rock[0] if c["big"] else _rock[1], p, 1, int(c["quarter"]) + int(since * 14.0))

	## One slab standing up out of the floor line: its foot on the line, its top edge broken and tipped
	## away from the impact, a lit face toward it and a dark one away. It heaves up as the crack reaches
	## it, overshooting, and sinks back into the desk as the break closes.
	func _slab(s: Dictionary, open: float) -> void:
		var since := t - float(s["from"])
		if since <= 0.0:
			return
		var rise := ease_out(clampf(since / 0.07, 0.0, 1.0))
		# A heave past its height and back.
		rise *= 1.0 + 0.25 * sin(PI * clampf((since - 0.07) / 0.12, 0.0, 1.0))
		if t >= LIFE * CLOSE_FROM:
			rise *= open
		var h := float(s["h"]) * rise
		if h < 4.0:
			return
		var side := float(s["side"])
		var x := float(s["x"])
		var w := float(s["w"])
		var tip := float(s["tip"])
		var near := x - side * w * 0.5
		var far := x + side * w * 0.5
		# A four-sided slab, convex: the near corner stands tallest, the top slopes away from the impact.
		var top_near := Vector2(near + side * w * (tip * 0.3 + float(s["lean"]) * 0.2), -h)
		var top_far := Vector2(far + side * w * tip * 0.4, -h * (0.55 + 0.2 * tip))
		var slab := PackedVector2Array([Vector2(near, 0.0), top_near, top_far, Vector2(far, 0.0)])
		if side < 0.0:
			slab.reverse()
		var rounded := PackedVector2Array()
		for p in slab:
			rounded.append(p.round())
		ink_poly(rounded, colour.darkened(0.15))
		# Its broken top edge, lit, and the face toward the impact catching the light.
		ink_line(top_near, top_far, colour.lightened(0.35), 2.0)
		draw_line(Vector2(near, -1.0).round(), top_near.round(), colour.lightened(0.2), 2.0)
