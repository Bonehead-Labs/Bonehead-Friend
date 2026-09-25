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

## For the suites: hits billed while he was dazed.
var dazed_hits := 0

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
	run(true)
	_glint = emitter("glint", &"star", Color.WHITE, 4, Vector2.ZERO, Vector2(0, -30), 180.0, 0.5)
	emit_from(_glint, true)
	sound(&"plink", -10.0, 1.9)
	var fx := fx()
	if fx:
		fx.ring(body.global_position, 34.0, Color.WHITE, 0.2, 2.0)
	_update_pip()

func _on_hit() -> void:
	if _phase == ARMED:
		_bong_pending = true
	else:
		_follow_pending = true

func _on_tick(delta: float) -> void:
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
	if _left <= 0.0:
		if _phase == ARMED:
			# Rang for nobody.
			finish(num("cooldown", 6.0) * 0.5)
		else:
			finish()

## The BONG: the armed hit landed on the tick before this one.
func _bong() -> void:
	_phase = DAZED
	_left = num("daze_seconds", 3.0)
	_next_tell = 0.5
	emit_from(_glint, false)
	var at := _head()
	var fx := fx()
	if fx:
		fx.ring(at, 110.0, Color.WHITE, 0.4, 4.0)
		fx.ring(at, 60.0, WorldFX.GOLD, 0.3, 3.0)
		fx.burst(at, &"star", WorldFX.GOLD, 7, 260.0)
		fx.shake(5.0)
	sound(&"bong", 0.0, 1.0, 0.0)
	_start_stars()
	payoffs += 1
	tell(&"dazed", at)
	paid_off.emit(&"bong")
	_update_pip()

## A follow-up while he is dazed: a lighter ring, a note higher each time.
func _follow() -> void:
	_follows += 1
	dazed_hits += 1
	var fx := fx()
	if fx:
		fx.ring(_head(), 50.0, WorldFX.GOLD, 0.2, 2.0)
		fx.burst(_head(), &"star", WorldFX.GOLD, 2, 180.0)
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
		_stars.texture = UIStyle.glyph(&"star")
		_stars.target = him
		him.add_child(_stars)
		_stars_host = him
	_stars.moving = Settings.focus_intensity != Settings.Intensity.OFF

## Four stars on an ellipse over his skull, the far half a shade darker so the ring reads as round.
class Halo extends Node2D:
	const STARS := 4
	const RADIUS := Vector2(24.0, 7.0)
	var texture: Texture2D
	var target: Buddy
	var moving := true
	var _turn := 0.0

	func _process(delta: float) -> void:
		if not is_instance_valid(target):
			return
		var rect := target.get_interaction_rect()
		global_position = Vector2(rect.get_center().x, rect.position.y + 2.0).round()
		if moving:
			_turn = fmod(_turn + delta * 1.1, 1.0)
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var half := texture.get_size() * 0.5
		for i in STARS:
			var a := TAU * (_turn + float(i) / float(STARS))
			var p := Vector2(cos(a) * RADIUS.x, sin(a) * RADIUS.y).round()
			var tint := WorldFX.GOLD if sin(a) >= 0.0 else WorldFX.GOLD.darkened(0.25)
			draw_texture(texture, p - half, tint)

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
