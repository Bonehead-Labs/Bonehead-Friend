extends RefCounted

## The mechanical keyboard's CLACK! (Keycap Barrage): the barrage spells it. Five keycaps — C, L, A, C,
## K — bounce up off his skull where the first one hit, fanned out and tumbling, each a little amber
## cap with its letter on it, and fall away.
##
## The only payoff with letters in it that are not a callout: the word is made of the thing that hit
## him.

const WORD := ["C", "L", "A", "C", "K"]

const LETTERS := {
	"C": [".xxx.", "x....", "x....", "x....", ".xxx."],
	"L": ["x....", "x....", "x....", "x....", "xxxx."],
	"A": [".xxx.", "x...x", "xxxxx", "x...x", "x...x"],
	"K": ["x..x.", "x.x..", "xx...", "x.x..", "x..x."],
}

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Keycaps", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const CAPS := 5
	const GAP := 0.03
	const GRAVITY := 1300.0
	var _caps: Array[Texture2D] = []
	var _speed: Array[Vector2] = []
	var _spin: Array[float] = []

	func setup(at: Vector2, s: float, tint: Color, _ability: WeaponAbility) -> void:
		size = s
		colour = tint
		if _caps.is_empty():
			_caps.resize(CAPS)
			_speed.resize(CAPS)
			_spin.resize(CAPS)
			for i in CAPS:
				_caps[i] = plot("cap_%s" % WORD[i], _cap_rows(WORD[i]))
		for i in CAPS:
			var a := deg_to_rad(lerpf(-62.0, 62.0, float(i) / float(CAPS - 1)))
			_speed[i] = Vector2.UP.rotated(a) * rng.randf_range(430.0, 480.0) * (0.9 + 0.2 * s)
			_spin[i] = rng.randf_range(4.0, 9.0) * (1.0 if i % 2 == 0 else -1.0)
		fire(at + Vector2(0.0, -6.0), 0.85)

	func _paint(_k: float) -> void:
		var shrink := 1.0 - span(0.66, 0.85)
		for i in CAPS:
			var t := age - GAP * float(i)
			if t < 0.0:
				continue
			var p: Vector2 = _speed[i] * t + Vector2(0.0, 0.5 * GRAVITY * t * t)
			var pop := overshoot(clampf(t / 0.08, 0.0, 1.0))
			picture(_caps[i], p, (1.5 + 0.3 * size) * pop * shrink, _spin[i] * maxf(t - 0.14, 0.0))

	## A cap: the lit top with the letter pressed into it, over its brown skirt.
	func _cap_rows(letter: String) -> Array:
		var glyph: Array = LETTERS.get(letter, LETTERS["C"])
		var rows: Array = ["YYYYYYYYY"]
		for row in glyph:
			rows.append("YY%sYY" % String(row).replace("x", "k").replace(".", "Y"))
		rows.append("YYYYYYYYY")
		rows.append("bbbbbbbbb")
		rows.append("nnnnnnnnn")
		return rows
