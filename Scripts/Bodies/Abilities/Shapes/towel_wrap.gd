extends RefCounted

## Swaddle (the warm towel, D78): the towel goes round him, and it is warm.
##
## **The wrap** (`play`, the payoff) is the throw finishing: a band of the towel's own cloth — cream
## with its teal stripe — whips once round him and folds into the towel. **For as long as it is on
## him** the towel's two ends hang down his sides from where it is folded across his middle, so it is
## round him and not across him, and warm steam rises off both ends in wavy lines — the sign for
## something hot — curling up his sides and taken back into the air. The ends and the steam are at his
## edges, never over his face (`SwaddleAbility` lays the towel under his face, too).

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeTowelWrap"

## One hanging end: the towel's cream, its teal stripe, and a brown hem.
const END := [
	"CCCC",
	"CCCC",
	"qqqq",
	"CCCC",
	"CCCC",
	"CCCC",
	"CCCC",
	"qqqq",
	"CCCC",
	"cccc",
	"nnnn",
]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Wrap) as Wrap).wrap(at, size, colour, ability)

class Wrap extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const SWOOSH_T := 0.26
	const WISPS := 6
	const WISP_T := 1.0
	const WISP_EVERY := 0.28

	var _ability: WeakRef
	var _wrapped := false
	var _wrapped_at := -10.0
	var _centre := Vector2.ZERO
	var _half := 36.0
	var _next_wisp := 0.0
	var _wisp_side := 1.0
	var _wisp_at := PackedVector2Array()
	var _wisp_born := PackedFloat32Array()
	var _next := 0

	func _ready() -> void:
		super._ready()
		_wisp_at.resize(WISPS)
		_wisp_born.resize(WISPS)
		for i in WISPS:
			_wisp_born[i] = -10.0

	func wrap(at: Vector2, _size: float, _colour: Color, ability: WeaponAbility) -> void:
		_ability = weakref(ability)
		_wrapped = true
		_wrapped_at = clock
		_next_wisp = clock
		_centre = at
		_follow()
		hold(SWOOSH_T)

	func _wrapping() -> WeaponAbility:
		var ability := _ability.get_ref() as WeaponAbility if _ability else null
		if ability and is_instance_valid(ability.body) and ability.has_method("is_wrapped") \
				and ability.call("is_wrapped"):
			return ability
		return null

	## Where the towel is on him — its picture, which the hook lays under his face — and how wide.
	func _follow() -> void:
		var ability := _ability.get_ref() as WeaponAbility if _ability else null
		if ability == null or not is_instance_valid(ability.body):
			return
		var s := ability.sprite()
		_centre = s.global_position if s else ability.body.global_position
		# Laid a little wider than it folds (the hook's `drape`).
		_half = ability.body.get_interaction_rect().size.x * 0.5 * ability.num("drape", 1.25)

	func _advance(_delta: float) -> void:
		if not _wrapped:
			return
		if _wrapping() == null:
			_wrapped = false
			return
		_follow()
		hold(WISP_T)
		if clock >= _next_wisp:
			_next_wisp = clock + WISP_EVERY
			_wisp_side = -_wisp_side
			_wisp_at[_next] = Vector2(_wisp_side * (_half - 6.0 + rng.randf_range(-3.0, 3.0)), -4.0)
			_wisp_born[_next] = clock
			_next = (_next + 1) % WISPS

	func _parked() -> void:
		_wrapped = false

	func _draw_shape() -> void:
		var age := clock - _wrapped_at
		if _wrapped:
			_draw_ends(clampf(age / 0.12, 0.0, 1.0))
		_draw_wisps()
		if age >= 0.0 and age <= SWOOSH_T:
			_draw_swoosh(age / SWOOSH_T)

	## The two ends hanging down his sides from where the towel folds across him.
	func _draw_ends(k: float) -> void:
		if k <= 0.05:
			return
		var end := picture("end", END)
		var drop := end.get_size().y * ART * 0.5 * k
		for side in [-1.0, 1.0]:
			var top := _centre + Vector2(side * (_half - 5.0), 4.0)
			stamp(end, top + Vector2(0.0, drop - 1.0), k)

	## Steam off the ends: a wavy line rising from each in turn, drawn up out of the towel and taken
	## back into the air from the bottom, riding with him.
	func _draw_wisps() -> void:
		for i in WISPS:
			var age := clock - _wisp_born[i]
			if age < 0.0 or age > WISP_T:
				continue
			var k := age / WISP_T
			var top := clampf(k / 0.5, 0.0, 1.0)
			var bottom := clampf((k - 0.4) / 0.6, 0.0, 1.0)
			if top - bottom < 0.03:
				continue
			var base := _centre + _wisp_at[i]
			var points := PackedVector2Array()
			for s in 8:
				var t := lerpf(bottom, top, float(s) / 7.0)
				var wave := sin(t * 11.0 + float(i) * 1.7 - k * 5.0) * 4.0
				points.append((base + Vector2(wave, -8.0 - 40.0 * t)).round())
			strokes(points, KEY["o"], 2.0)

	## Once round him: a band of cloth running round an ellipse at the towel, closing up into it.
	func _draw_swoosh(k: float) -> void:
		var rx := _half + 16.0
		var ry := 12.0
		var lead := k * TAU
		var tail := maxf(0.0, lead - PI * 0.9)
		var steps := 14
		var points := PackedVector2Array()
		for s in steps + 1:
			var a := lerpf(tail, lead, float(s) / float(steps)) + PI
			points.append((_centre + Vector2(cos(a) * rx, sin(a) * ry)).round())
		var w := lerpf(8.0, 3.0, k)
		strokes(points, KEY["C"], w)
		draw_polyline(points, KEY["q"], maxf(1.0, w * 0.3))
