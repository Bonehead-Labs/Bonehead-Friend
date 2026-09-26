extends RefCounted

## Tickle (the feather duster, D78): every giggle wiggles out of him.
##
## Each giggle (`play`, the payoff, three a second while its feathers are on him) kicks out little
## squiggles from his sides — the wiggly lines a cartoon draws round someone who cannot keep still —
## that shiver as they go, on alternate sides, and a pink feather or two comes loose from the duster
## and rocks down to the desk. The first giggle of a tickle throws more of both. Small, because it
## comes three times a second; no ring, because a giggle is not a hit.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeFeatherGiggle"

const FEATHER := [
	".....PP",
	"....PPP",
	"...PPpP",
	"..PPpP.",
	".PPpPP.",
	".PpPP..",
	"PpPP...",
	"pP.....",
	"m......",
]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Giggle) as Giggle).giggle(at, size, colour, ability)

class Giggle extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const MARKS := 10
	const MARK_T := 0.42

	var _mark_at := PackedVector2Array()
	var _mark_born := PackedFloat32Array()
	var _mark_side := PackedFloat32Array()
	var _next_mark := 0
	var _side := 1.0
	var _colour := Color("ff6fae")

	func _ready() -> void:
		super._ready()
		_mark_at.resize(MARKS)
		_mark_born.resize(MARKS)
		_mark_side.resize(MARKS)
		for i in MARKS:
			_mark_born[i] = -10.0

	func giggle(at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
		reserve(12)
		_colour = colour
		var rect := Rect2(at - Vector2(30, 50), Vector2(60, 100))
		var him := ability.buddy() if ability else null
		if him:
			rect = him.get_interaction_rect()
		# The first giggle of a tickle is the big one: `size` is halved for the ones after.
		var first := size >= 0.2
		var marks := 4 if first else 2
		for i in Moment.count(marks):
			_side = -_side
			var y := rect.get_center().y + rng.randf_range(-rect.size.y * 0.3, rect.size.y * 0.25)
			var x := rect.get_center().x + _side * (rect.size.x * 0.5 + rng.randf_range(6.0, 14.0))
			_mark_at[_next_mark] = Vector2(x, y)
			_mark_born[_next_mark] = clock + 0.05 * float(i)
			_mark_side[_next_mark] = _side
			_next_mark = (_next_mark + 1) % MARKS
		# Feathers off the duster's end, rocking down.
		var from := ability.tip_world() if ability and ability.body else at
		var feather := picture("feather", FEATHER)
		for i in Moment.count(2 if first else 1):
			var bit := throw(feather, from + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 4.0)),
				Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-90.0, -40.0)), rng.randf_range(1.1, 1.5), 160.0)
			bit.drag = 2.5
			bit.sway = 9.0
			bit.sway_hz = 1.3
			bit.turn = rng.randf_range(-0.5, 0.5)
			bit.flip = rng.randf() < 0.5
		hold(MARK_T + 0.2)

	## A feather rocks as it falls, its tip swinging with its sway.
	func _advance(_delta: float) -> void:
		for bit in bits:
			if bit.live and bit.sway > 0.0:
				bit.turn = sin(bit.age * TAU * bit.sway_hz + bit.phase) * 0.6

	## The squiggles: a zig-zag of four legs, out from his side, shivering as it goes — the zag flips
	## every few frames — and drawn back in toward him.
	func _draw_shape() -> void:
		for i in MARKS:
			var age := clock - _mark_born[i]
			if age < 0.0 or age > MARK_T:
				continue
			var k := clampf(age / 0.07, 0.0, 1.0)
			if age > MARK_T - 0.12:
				k = clampf((MARK_T - age) / 0.12, 0.0, 1.0)
			var side := _mark_side[i]
			var p := _mark_at[i]
			var flipped := 1.0 if int(age / 0.05) % 2 == 0 else -1.0
			var points := PackedVector2Array()
			for s in 6:
				var along := float(s) * 6.0 * k
				var zig := (5.0 if s % 2 == 1 else -1.0) * flipped * k
				points.append((p + Vector2(side * along, zig - along * 0.35)).round())
			strokes(points, _colour, 3.0)
