class_name StunAbility
extends WeaponAbility

## Ring the weapon, then hit him with it, and he is dazed (D74): the frying pan's BONG.
##
## Right while holding it **arms** it for `armed_seconds`: the pan rings a small high note and
## glints. The next hit it lands on him in that window is the BONG — billed at `bong_mult` on top
## of the pan's own multiplier, a bell you can hear across the room, a ring off his head — and
## he is **dazed** for `daze_seconds`: stars circling his skull, a dizzy face, a sway. While he is
## dazed every hit the pan lands is billed at `bonus_mult` and rings again, a note higher each
## time, so a flurry of follow-ups is a scale. Only the pan's own hits: the daze is the pan's
## combo, not a debuff on him that every weapon on the desk would farm.
##
## Everything it bills is his to measure: the multiplier is read by him when he attributes the
## pan's contact (D7), and nothing here touches his body.
##
## **How it reads (D77).** The owner found the first version "not obvious": a four-star burst on a
## white skull. Now, armed, the pan's face shines gold and gives off small rings, a sound you can
## see. The BONG is a gong: three thick gold waves off the pan's face and two off his head, the pan
## shuddering in the hand, "BONG!" over him, and a jolt. The daze is five big outlined stars on an
## ellipse round his skull that go out one by one as it wears off, under a badge whose ring drains
## with it. Each follow-up rings wider, flashes harder and calls out a bigger "BONG!!", then
## "BONG!!!" — the scale made visible — and kicks the stars round faster.
##
## Row: `armed_seconds`, `daze_seconds`, `bong_mult`, `bonus_mult`.

const ARMED := 0
const DAZED := 1

var _phase := ARMED
var _left := 0.0
var _bong_pending := false
var _follow_pending := false
var _follows := 0
var _next_tell := 0.0
var _glint: GPUParticles2D
var _stars: Halo
var _stars_host: Buddy
var _pan_shudder := 0.0
var _pan_rest := Vector2.INF
var _pan_wave := 0.0
var _pan_t := 0.0
## The shudder's own generator: the global one is the suites', seeded per weapon.
var _pan_rng := RandomNumberGenerator.new()

## For the suites: hits billed while he was dazed, and how big each follow-up's word was asked to be.
var dazed_hits := 0
var follow_weights: Array[float] = []

## Follow-ups grow for this many, and then hold at the biggest.
const FOLLOW_MOST := 5
## How long the pan shudders after the BONG, and after a follow-up.
const SHUDDER_BONG := 0.7
const SHUDDER_FOLLOW := 0.4

func is_armed() -> bool:
	return _active and _phase == ARMED

func is_dazed() -> bool:
	return _active and _phase == DAZED

func daze_left() -> float:
	return _left if is_dazed() else 0.0

func hit_multiplier() -> float:
	if not _active:
		return 1.0
	return num("bong_mult", 1.5) if _phase == ARMED else num("bonus_mult", 1.4)

func pip_fill() -> float:
	if not _active:
		return -1.0
	var total := num("armed_seconds", 2.0) if _phase == ARMED else num("daze_seconds", 3.0)
	return clampf(_left / maxf(total, 0.01), 0.0, 1.0)

func _on_press() -> void:
	_phase = ARMED
	_left = num("armed_seconds", 2.0)
	_bong_pending = false
	_follow_pending = false
	_follows = 0
	dazed_hits = 0
	follow_weights.clear()
	_pan_t = 0.0
	_pan_wave = 0.0
	run(true)
	_glint = emitter("glint", &"star", WorldFX.GOLD, 4, glint_local(), Vector2(0, -30), 180.0, 0.5)
	emit_from(_glint, true)
	sound(&"plink", -10.0, 1.9)
	_pan_shudder = 0.25
	var afx := AbilityFX.of(body)
	if afx:
		afx.waves(glint_world(), WorldFX.GOLD, 2, 60.0, 0.08, 4.0)
	_update_pip()

func _on_hit() -> void:
	if _phase == ARMED:
		_bong_pending = true
	else:
		_follow_pending = true

func _on_tick(delta: float) -> void:
	_pan_t += delta
	_ring_the_pan(delta)
	if _bong_pending:
		_bong_pending = false
		_bong()
		return
	if _follow_pending:
		_follow_pending = false
		_follow()
	_left -= delta
	if _phase == DAZED:
		_next_tell -= delta
		if _next_tell <= 0.0:
			_next_tell = 0.5
			tell(&"dazed", _head())
		if is_instance_valid(_stars):
			_stars.left = clampf(_left / maxf(num("daze_seconds", 3.0), 0.01), 0.0, 1.0)
	if _left <= 0.0:
		if _phase == ARMED:
			# Rang for nobody.
			finish(num("cooldown", 6.0) * 0.5)
		else:
			finish()

## The pan in the hand: armed, its face shines and gives off a small ring now and then — a sound you
## can see; struck, it shudders. The picture only, so the swing is the swing it always was.
func _ring_the_pan(delta: float) -> void:
	var s := sprite()
	if s == null:
		return
	if _phase == ARMED and _active:
		AbilityFX.shine(s, WorldFX.GOLD, 0.3 + 0.2 * sin(_pan_t * 16.0) if AbilityFX.moving() else 0.35)
		_pan_wave -= delta
		if _pan_wave <= 0.0:
			_pan_wave = 0.34
			var afx := AbilityFX.of(body)
			if afx:
				afx.waves(glint_world(), WorldFX.GOLD, 1, 42.0, 0.0, 3.0)
	else:
		AbilityFX.shine(s, WorldFX.GOLD, 0.0)
	if _pan_shudder > 0.0:
		if _pan_rest == Vector2.INF:
			_pan_rest = s.position
		_pan_shudder = maxf(_pan_shudder - delta, 0.0)
		var amp := 3.0 * minf(_pan_shudder / 0.3, 1.0) * Settings.intensity_scale()
		var jitter := Vector2(_pan_rng.randf_range(-amp, amp), _pan_rng.randf_range(-amp, amp))
		s.position = _pan_rest + jitter.round()
		if _pan_shudder <= 0.0:
			s.position = _pan_rest
			_pan_rest = Vector2.INF

## The BONG: the armed hit landed on the tick before this one. A gong: waves off the pan's face and
## off his head, the pan shuddering, the stars and their badge, and a jolt; the payoff and its word
## are the look's (`paid_off`).
func _bong() -> void:
	_phase = DAZED
	_left = num("daze_seconds", 3.0)
	_next_tell = 0.5
	emit_from(_glint, false)
	var at := _head()
	var fx := fx()
	if fx:
		fx.burst(at, &"star", WorldFX.GOLD, 7, 260.0)
		fx.shake(7.0)
	var afx := AbilityFX.of(body)
	if afx:
		afx.waves(glint_world(), WorldFX.GOLD, 3, 220.0, 0.08, 7.0)
		afx.waves(at, WorldFX.GOLD, 2, 130.0, 0.1, 5.0)
	_pan_shudder = SHUDDER_BONG
	sound(&"bong", 0.0, 1.0, 0.0)
	_start_stars()
	payoffs += 1
	tell(&"dazed", at)
	paid_off.emit(&"bong")
	_update_pip()

## A follow-up while he is dazed: a note higher each time, and every one of them bigger than the
## last — a wider ring, a harder flash, a louder word, the stars kicked round faster.
func _follow() -> void:
	_follows += 1
	dazed_hits += 1
	var n := mini(_follows, FOLLOW_MOST)
	var head := _head()
	var fx := fx()
	if fx:
		fx.burst(head, &"star", WorldFX.GOLD, 2 + n, 180.0 + 30.0 * float(n))
		fx.shake(2.0 + float(n))
	var afx := AbilityFX.of(body)
	if afx:
		afx.waves(head, WorldFX.GOLD, 2, 90.0 + 35.0 * float(n), 0.08, 4.0 + float(n))
		afx.waves(glint_world(), WorldFX.GOLD, 1, 70.0 + 20.0 * float(n), 0.0, 4.0)
		# The BONG's own ringing again (`Shapes/bong.gd`), bigger with every follow-up.
		var shape := StringName(AbilityLooks.pay_spec(look(), &"bong").get("shape", &""))
		if shape != &"":
			afx.payoff_shaped(shape, head, 0.25 + 0.14 * float(n), WorldFX.GOLD, self)
		else:
			afx.payoff(head, 0.25 + 0.14 * float(n), WorldFX.GOLD)
	var weight := AbilityFX.weight_for(ability_id(), true) * (0.7 + 0.16 * float(n))
	follow_weights.append(weight)
	callout("BONG" + "!".repeat(n + 1), head + Vector2(0.0, -58.0), true, weight)
	_pan_shudder = SHUDDER_FOLLOW
	if is_instance_valid(_stars):
		_stars.kick(n)
	sound(&"bong", -6.0, pow(2.0, float(mini(_follows, 7)) * 2.0 / 12.0), 0.0)

## Where his skull is: the top of his collider.
func _head() -> Vector2:
	var him := buddy()
	if him == null:
		return body.global_position
	var rect := him.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y + 14.0)

## Stars circling his skull: the cartoon halo, drawn — an orbiting particle emitter was tried first
## and its stars fell inward into one, which read as a single star on his head. A child of his, so
## it goes where he goes and dies with him, but `top_level`, so it stays level over his skull when
## he is lying on his side; taken off him the moment the daze ends or the pan leaves the desk, so
## nothing of the pan is ever left on him. Still at Focus Off: a daze is information, the orbit is
## motion.
func _start_stars() -> void:
	var him := buddy()
	if him == null:
		return
	if not is_instance_valid(_stars):
		_stars = Halo.new()
		_stars.name = "DazeStars"
		_stars.top_level = true
		_stars.z_index = 32
		var afx := AbilityFX.of(body)
		_stars.texture = afx.icon(&"star", WorldFX.GOLD) if afx else AbilityFX.plot(&"star", WorldFX.GOLD)
		_stars.flash_texture = afx.icon(&"star", Color("fff4c2")) if afx \
			else AbilityFX.plot(&"star", Color("fff4c2"))
		_stars.target = him
		him.add_child(_stars)
		_stars_host = him
	_stars.moving = Settings.focus_intensity != Settings.Intensity.OFF

## Five stars on an ellipse round his skull, drawn at the art's 2x with a dark rim so they read on
## white bone, the far half a step darker so the ring reads as round. They go out one at a time as
## the daze wears off (`left`), and a follow-up kicks them round faster and flashes them pale.
class Halo extends Node2D:
	const STARS := 5
	const RADIUS := Vector2(34.0, 10.0)
	var texture: Texture2D
	var flash_texture: Texture2D
	var target: Buddy
	var moving := true
	## 0..1 of the daze left: how many stars are still out.
	var left := 1.0
	var _turn := 0.0
	var _kick := 0.0
	var _flash := 0.0

	## A follow-up: round faster for a moment, and lit.
	func kick(strength: int) -> void:
		_kick = 1.0 + 0.5 * float(strength)
		_flash = 0.15

	func shown() -> int:
		return clampi(int(ceil(left * float(STARS) - 0.001)), 1, STARS)

	func _process(delta: float) -> void:
		if not is_instance_valid(target):
			return
		var rect := target.get_interaction_rect()
		global_position = Vector2(rect.get_center().x, rect.position.y + 4.0).round()
		_flash = maxf(0.0, _flash - delta)
		if moving:
			_turn = fmod(_turn + delta * (1.1 + 2.5 * _kick), 1.0)
			_kick = maxf(0.0, _kick - delta * 2.0)
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var picture := flash_texture if _flash > 0.0 and flash_texture else texture
		var size := picture.get_size() * AbilityFX.ART_SCALE
		var count := shown()
		# The far half first, so the near stars pass in front of it.
		for pass_ in 2:
			for i in count:
				var a := TAU * (_turn + float(i) / float(STARS))
				var near := sin(a) >= 0.0
				if near != (pass_ == 1):
					continue
				var p := Vector2(cos(a) * RADIUS.x, sin(a) * RADIUS.y).round()
				var tint := Color.WHITE if near else Color(0.72, 0.72, 0.72)
				draw_texture_rect(picture, Rect2((p - size * 0.5).round(), size), false, tint)

## Dropped mid-daze, he stays dazed: the pan's hits still count when it is thrown at him.
func _on_dropped() -> void:
	if _phase == ARMED:
		finish(num("cooldown", 6.0) * 0.5)

func _on_stop() -> void:
	emit_from(_glint, false)
	if is_instance_valid(_stars):
		_stars.queue_free()
	_stars = null
	_stars_host = null
	var s := sprite()
	if s:
		AbilityFX.shine(s, WorldFX.GOLD, 0.0)
		if _pan_rest != Vector2.INF:
			s.position = _pan_rest
	_pan_rest = Vector2.INF
	_pan_shudder = 0.0
