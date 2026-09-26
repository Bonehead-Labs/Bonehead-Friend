extends RefCounted

## Make a Wish (the birthday cake, D78): he blows, they go out, and it is a party.
##
## The payoff (`play`, the moment the candles go out) is told in order. His breath goes across to the
## cake — three wavy lines from his mouth to the wicks. A curl of smoke unwinds up off every wick. Then
## over his head it is a birthday: confetti in six colours thrown up and fluttering down end over end,
## and a big gold twinkle with two small ones either side. The only payoff that is a story in three
## beats, because a wish is.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeBirthdayWish"

const CONFETTI := ["p", "Y", "a", "O", "V", "u"]
const PIECE := ["xx", "xx", "xx"]
const CONFETTI_KEYS := ["confetti_p", "confetti_y", "confetti_a", "confetti_o", "confetti_v", "confetti_u"]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Wish) as Wish).wish(at, size, colour, ability)

class Wish extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const BREATH_T := 0.2
	const SMOKE_T := 1.0
	const PARTY_AT := 0.22
	const TWINKLE_T := 0.4
	const WICKS := 4

	var _over := Vector2.ZERO
	var _mouth := Vector2.ZERO
	var _edge := 20.0
	var _wicks := PackedVector2Array()
	var _wick_count := 0
	var _wished_at := -10.0
	var _partied := true
	var _k := 1.0
	var _colour := Color("ffd23a")

	func _ready() -> void:
		super._ready()
		_wicks.resize(WICKS)

	func wish(at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
		reserve(24)
		_colour = colour
		_over = at
		_k = lerpf(0.75, 1.0, size)
		_mouth = at + Vector2(0.0, 40.0)
		var him := ability.buddy() if ability else null
		if him and ability.has_method("_face"):
			_mouth = ability.call("_face", him)
		if him:
			_edge = him.get_interaction_rect().size.x * 0.5
		_wick_count = 0
		if ability and ability.has_method("_wick_points_world"):
			var points: PackedVector2Array = ability.call("_wick_points_world")
			for p in points:
				if _wick_count < WICKS:
					_wicks[_wick_count] = p
					_wick_count += 1
		_wished_at = clock
		_partied = false
		hold(SMOKE_T)

	func _advance(_delta: float) -> void:
		if _partied or clock - _wished_at < PARTY_AT:
			return
		_partied = true
		for i in Moment.count(18):
			var ink: String = CONFETTI[i % CONFETTI.size()]
			var a := -PI * 0.5 + rng.randf_range(-1.2, 1.2)
			var bit := throw(tinted(CONFETTI_KEYS[i % CONFETTI.size()], PIECE, "x", ink), _over,
				Vector2(cos(a), sin(a)) * rng.randf_range(200.0, 330.0) * _k, rng.randf_range(1.2, 1.6), 380.0)
			bit.drag = 2.6
			bit.flutter = true
			bit.sway = 10.0
			bit.sway_hz = 1.1
			bit.spin = rng.randf_range(-5.0, 5.0)
		hold(TWINKLE_T + 0.1)

	func _draw_shape() -> void:
		var age := clock - _wished_at
		if age < 0.0:
			return
		if age < BREATH_T and _wick_count > 0:
			_draw_breath(age / BREATH_T)
		if age < SMOKE_T:
			for i in _wick_count:
				_draw_smoke(_wicks[i], age / SMOKE_T, float(i))
		var party := age - PARTY_AT
		if party >= 0.0 and party < TWINKLE_T:
			var k := party / TWINKLE_T
			var grow := sin(k * PI)
			_twinkle(_over + Vector2(0.0, -14.0), 24.0 * grow * _k)
			var late := clampf((party - 0.1) / (TWINKLE_T - 0.1), 0.0, 1.0)
			var small := sin(late * PI) * 11.0 * _k
			_twinkle(_over + Vector2(-34.0, 6.0), small)
			_twinkle(_over + Vector2(34.0, 6.0), small)

	## Three wavy lines from his mouth across to the wicks, running as a gust does.
	func _draw_breath(k: float) -> void:
		var target := Vector2.ZERO
		for i in _wick_count:
			target += _wicks[i]
		target /= float(_wick_count)
		var dir := target - _mouth
		var length := dir.length()
		if length < 1.0:
			return
		dir /= length
		var across := Vector2(-dir.y, dir.x)
		var head := clampf(k * 1.4, 0.0, 1.0)
		var tail := clampf(k * 1.4 - 0.45, 0.0, 1.0)
		for line in 3:
			var off := across * (float(line) - 1.0) * 8.0
			var points := PackedVector2Array()
			for s in 9:
				var t := lerpf(tail, head, float(s) / 8.0)
				var wave := sin(t * 14.0 + float(line)) * 3.0
				points.append((_mouth + dir * (_edge + (length - _edge - 18.0) * t) + off + across * wave).round())
			strokes(points, KEY["u"], 2.0)

	## A curl of smoke unwinding up off a wick, and taken back into the air from the bottom.
	func _draw_smoke(wick: Vector2, k: float, which: float) -> void:
		var top := clampf(k / 0.45, 0.0, 1.0)
		var bottom := clampf((k - 0.45) / 0.55, 0.0, 1.0)
		if top - bottom < 0.02:
			return
		var points := PackedVector2Array()
		for s in 10:
			var t := lerpf(bottom, top, float(s) / 9.0)
			var wave := sin(t * 9.0 + which * 2.1 + k * 6.0) * lerpf(1.0, 7.0, t)
			points.append((wick + Vector2(wave, -4.0 - 46.0 * t)).round())
		strokes(points, KEY["g"], 2.0)

	## A four-point twinkle: two long points and two short, gold on a dark rim.
	func _twinkle(at: Vector2, r: float) -> void:
		if r < 4.0:
			return
		var star := PackedVector2Array()
		var rim := PackedVector2Array()
		for i in 8:
			var long := i % 2 == 0
			var d := Vector2.UP.rotated(PI * 0.25 * float(i))
			var reach := (r if (i % 4 == 0) else r * 0.7) if long else r * 0.18
			star.append(at + d * reach)
			rim.append(at + d * (reach + 3.0))
		draw_colored_polygon(rim, OUTLINE)
		draw_colored_polygon(star, _colour)
		draw_rect(Rect2(at.round() - Vector2(1, 1), Vector2(2, 2)), KEY["W"])
