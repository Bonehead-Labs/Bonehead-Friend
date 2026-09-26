extends RefCounted

## Wring (the sponge, D78): a lather on him, and the bubbles popping off it.
##
## **The rinse** (`play`, the payoff: the first drop on him) splashes a crown of drops up off him and
## lathers him: two clumps of soap bubbles, four sizes of them, round his ears and the corners of his
## skull — never the top of his head, where his badge is — hollow and pale with a dark rim only on the
## outside, so he shows through every one. They wobble, and pop one at a time, each a little star of
## lines and two drops. **The shower** (`bubble`, from the hook as drops land on him) keeps a few
## more rising off him, drifting up to pop, for as long as it rains. Nothing else blows bubbles.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeSpongeSuds"

const SIZES := [
	[
		".uuu.",
		"u..Wu",
		"u...u",
		"u...u",
		".uuu.",
	],
	[
		"..uuu..",
		".u...u.",
		"u...WWu",
		"u....Wu",
		"u.....u",
		".u...u.",
		"..uuu..",
	],
	[
		"...uuu...",
		".uu...uu.",
		".u....WW.",
		"u......Wu",
		"u.......u",
		"u.......u",
		".u.....u.",
		".uu...uu.",
		"...uuu...",
	],
	[
		"....uuu....",
		"..uu...uu..",
		".u.....WWu.",
		".u......Wu.",
		"u.........u",
		"u.........u",
		"u.........u",
		".u.......u.",
		".u.......u.",
		"..uu...uu..",
		"....uuu....",
	],
]
const SIZE_KEYS := ["bubble0", "bubble1", "bubble2", "bubble3"]
const DROP := [
	".u.",
	"uUu",
	"UUU",
	".U.",
]
## The lather on him: where each bubble sits, as a fraction of his width from his middle and of his
## height from his top, and which size it is. Round his ears and the corners of his skull.
const LATHER := [
	Vector3(-0.44, 0.02, 2), Vector3(-0.6, 0.2, 3), Vector3(-0.28, -0.06, 0), Vector3(-0.56, 0.42, 1),
	Vector3(0.44, 0.03, 3), Vector3(0.62, 0.22, 1), Vector3(0.3, -0.05, 0), Vector3(0.55, 0.43, 2),
]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Suds) as Suds).rinse(at, size, colour, ability)

## One bubble off him where a drop landed, drifting up to pop.
static func bubble(afx: AbilityFX, at: Vector2) -> void:
	if afx == null or not AbilityFX.moving():
		return
	(Moment.canvas(afx, NAME, Suds) as Suds).one(at)

class Suds extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const POP_T := 0.09
	const POPS := 8

	var _pops := PackedVector2Array()
	var _pop_at := PackedFloat32Array()
	var _pop_r := PackedFloat32Array()
	var _next_pop := 0

	func _ready() -> void:
		super._ready()
		_pops.resize(POPS)
		_pop_at.resize(POPS)
		_pop_r.resize(POPS)
		for i in POPS:
			_pop_at[i] = -10.0

	func rinse(at: Vector2, _size: float, _colour: Color, ability: WeaponAbility) -> void:
		reserve(32)
		# A crown of drops up off him where the first one landed.
		var drop := picture("drop", DROP)
		for i in Moment.count(6):
			var a := -PI * 0.5 + (float(i) - 2.5) * 0.36
			throw(drop, at, Vector2(cos(a), sin(a)) * rng.randf_range(160.0, 240.0), rng.randf_range(0.4, 0.55), 900.0)
		# The lather: two clumps, round his ears, popping one at a time.
		var rect := Rect2(at - Vector2(32.0, 10.0), Vector2(64.0, 110.0))
		var him := ability.buddy() if ability else null
		if him:
			rect = him.get_interaction_rect()
		var n := Moment.count(LATHER.size())
		for i in n:
			var spot: Vector3 = LATHER[i if n == LATHER.size() else i * 2]
			var from := Vector2(rect.get_center().x + spot.x * rect.size.x, rect.position.y + spot.y * rect.size.y)
			var order := float(i % 4) * 2.0 + floorf(float(i) / 4.0)
			_suds(int(spot.z), from + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0)),
				0.5 + 0.11 * order + rng.randf_range(0.0, 0.04), -10.0)

	func one(at: Vector2) -> void:
		reserve(32)
		var bit := _suds(rng.randi() % 3, at + Vector2(rng.randf_range(-10.0, 10.0), -4.0),
			rng.randf_range(0.5, 0.8), -70.0)
		bit.vel = Vector2(rng.randf_range(-15.0, 15.0), -40.0)

	func _suds(which: int, at: Vector2, life: float, lift: float) -> Bit:
		var bit := throw(picture(SIZE_KEYS[which], SIZES[which], true, true), at, Vector2.ZERO, life, lift)
		bit.pops = true
		bit.sway = 3.0
		bit.sway_hz = 1.2
		bit.drag = 1.5
		return bit

	## A bubble reached its time: a pop where it was, and two drops.
	func _bit_died(bit: Bit) -> void:
		var r := bit.tex.get_size().x * ART * 0.5
		_pops[_next_pop] = bit.pos
		_pop_at[_next_pop] = clock
		_pop_r[_next_pop] = r
		_next_pop = (_next_pop + 1) % POPS
		var drop := picture("drop", DROP)
		for s in [-1.0, 1.0]:
			var d := throw(drop, bit.pos, Vector2(s * rng.randf_range(50.0, 90.0), -rng.randf_range(40.0, 90.0)),
				0.35, 900.0)
			d.size = 0.7
		hold(POP_T)

	## A wobble as they sit: a bubble is never quite round.
	func bit_scale(bit: Bit) -> float:
		var k := super.bit_scale(bit)
		if bit.pops:
			k *= 1.0 + 0.08 * sin(bit.age * 18.0 + bit.phase)
		return k

	func _draw_shape() -> void:
		for i in POPS:
			var age := clock - _pop_at[i]
			if age < 0.0 or age > POP_T:
				continue
			var r := _pop_r[i] * lerpf(0.9, 1.5, age / POP_T)
			var p := _pops[i]
			for s in 4:
				var d := Vector2.RIGHT.rotated(PI * 0.25 + PI * 0.5 * float(s))
				stroke(p + d * r * 0.55, p + d * r, KEY["u"], 2.0)
