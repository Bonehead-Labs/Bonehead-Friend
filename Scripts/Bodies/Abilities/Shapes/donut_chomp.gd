extends RefCounted

## Donut Toss (the box of donuts, D78): it goes in in two bites.
##
## When the donut reaches him (`play`, the payoff) it is eaten where you can see it: the pink donut
## sits at the corner of his mouth, on the side it came from, and goes in two bites — whole, a
## scallop gone, half gone — and on the last bite it is crumbs: a puff of dough falling off him and the
## sprinkles flying, every colour of them. A third of a second from arriving to gone, at his mouth's
## edge so his face stays his.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeDonutChomp"

const DONUT := [
	"...bBBBBBb...",
	".bbPPpPPPpbb.",
	"bPPYPPPaPPPpb",
	"bPaPPbbbPPYPb",
	"bPPPb...bPPpb",
	"bpPYb...bPaPb",
	"bpPPPbbbPPPpb",
	".bpPPPYPPPpb.",
	"..bbpppppbb..",
	"....bbbbb....",
]
## Where each bite comes out, in the donut's own pixels: a circle, and its radius.
const BITES := [Vector3(11.5, 1.5, 3.3), Vector3(11.0, 6.5, 3.7)]
const BITTEN_KEYS := ["donut0", "donut1", "donut2"]
const CRUMB := ["Bb"]
const SPRINKLES := [["Y"], ["a"], ["W"], ["p"], ["u"], ["V"]]
const SPRINKLE_KEYS := ["sprinkle_y", "sprinkle_a", "sprinkle_w", "sprinkle_p", "sprinkle_u", "sprinkle_v"]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Chomp) as Chomp).chomp(at, size, colour, ability)

class Chomp extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const BITE_T := 0.09

	var _at := Vector2.ZERO
	var _side := 1.0
	var _eaten_from := -10.0
	var _crumbed := true

	func chomp(at: Vector2, _size: float, _colour: Color, ability: WeaponAbility) -> void:
		reserve(24)
		var mouth := at
		var him := ability.buddy() if ability else null
		if him:
			var rect := him.get_interaction_rect()
			var box := ability.com_world() if ability.body else at
			_side = signf(box.x - rect.get_center().x)
			if _side == 0.0:
				_side = 1.0
			# At the corner of his mouth, on the side it came from: never over his face.
			mouth = Vector2(rect.get_center().x + _side * rect.size.x * 0.4,
				rect.position.y + rect.size.y * 0.45)
		_at = mouth
		_eaten_from = clock
		_crumbed = false
		hold(BITE_T * 3.0 + 0.05)

	func _advance(_delta: float) -> void:
		if _crumbed or clock - _eaten_from < BITE_T * 3.0:
			return
		_crumbed = true
		var crumb := picture("crumb", CRUMB)
		for i in Moment.count(6):
			var bit := throw(crumb, _at + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-4.0, 4.0)),
				Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-120.0, -20.0)), rng.randf_range(0.45, 0.65), 900.0)
			bit.spin = rng.randf_range(-8.0, 8.0)
		for i in Moment.count(12):
			var grid: Array = SPRINKLES[i % SPRINKLES.size()]
			var a := -PI * 0.5 + rng.randf_range(-1.3, 1.3)
			var bit := throw(picture(SPRINKLE_KEYS[i % SPRINKLES.size()], grid), _at,
				Vector2(cos(a), sin(a)) * rng.randf_range(150.0, 280.0), rng.randf_range(0.5, 0.75), 800.0)
			bit.spin = rng.randf_range(-14.0, 14.0)

	func _draw_shape() -> void:
		var age := clock - _eaten_from
		if age < 0.0 or age >= BITE_T * 3.0:
			return
		var bites := int(age / BITE_T)
		# In with a pop, then smaller with every bite.
		var k := lerpf(0.6, 1.1, clampf(age / 0.05, 0.0, 1.0)) if age < 0.05 else 1.0
		# Its bites face his mouth: drawn on his right, it is turned round.
		stamp(_bitten(bites), _at, k * (1.0 - 0.08 * float(bites)), 0.0, _side > 0.0)

	## The donut with `n` bites out of it, plotted once each.
	func _bitten(n: int) -> Texture2D:
		var key: String = BITTEN_KEYS[clampi(n, 0, BITTEN_KEYS.size() - 1)]
		if _textures.has(key):
			return _textures[key]
		var grid: Array = []
		for y in DONUT.size():
			var row := String(DONUT[y])
			var out := ""
			for x in row.length():
				var gone := false
				for b in mini(n, BITES.size()):
					var bite: Vector3 = BITES[b]
					if Vector2(x, y).distance_to(Vector2(bite.x, bite.y)) <= bite.z:
						gone = true
				out += "." if gone else row[x]
			grid.append(out)
		return picture(key, grid)
