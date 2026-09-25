class_name EnGardeAbility
extends SustainAbility

## The rapier's En Garde (D74, the blades): hold right and the blade points itself at him, the way
## a held gun's barrel does (D56), for as long as it is held or `guard_seconds` runs out. On guard,
## how it meets him is what it pays: **a thrust along the blade is x`thrust_mult`, a swipe across
## it x`swipe_mult`.** The player's part is the lunge — move the hand at him and the point goes in.
##
## **The aim is D56's.** A PD on the blade's line (grip to point) toward his centre of mass, scaled
## by the moment of inertia about the grip so it feels the same whatever the weapon weighs, capped
## at `aim_accel` — so the hand still has to catch a blade that is swinging — with gravity's pull
## about the grip cancelled on top. A torque, never a write to its spin (D54). It turns the point
## up and over to him, never down through the desk, where a hanging blade's point would jam.
##
## **The stance, every tick.** The point's velocity, split along the blade and across it. Along
## it and faster than `thrust_speed` is a thrust; across it by more than along is a swipe; anything
## else is an ordinary hit. He reads the stance's multiplier when he attributes the contact (D7) —
## it is set on the tick before the step he measures, so the multiplier he reads is the one the hit
## was armed with, and `note_hit` records exactly that.
##
## He squares up to it (`en_garde`), and a thrust that lands flashes down the line of the blade.
##
## Row: `guard_seconds`, `aim_frequency`, `aim_damping`, `aim_accel`, `thrust_speed`,
## `thrust_mult`, `swipe_mult`.

const NEUTRAL := 0
const THRUST := 1
const SWIPE := 2

var _stance := NEUTRAL
var _stance_mult := 1.0
var _hit_stances: Array[int] = []
var _next_tell := 0.0
var _next_glint := 0.0
var _gravity_ := 980.0

## For the suites: thrusts and swipes that landed this use, and how close the aim got.
var thrusts := 0
var swipes := 0
var best_aim := PI

func _ready() -> void:
	super._ready()
	_gravity_ = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func stance() -> int:
	return _stance if _active else NEUTRAL

func hit_multiplier() -> float:
	return _stance_mult if _active else 1.0

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(1.0 - _t / maxf(num("guard_seconds", 4.0), 0.01), 0.0, 1.0)

## The blade's line, grip to point, as a unit vector.
func blade_axis() -> Vector2:
	var axis := tip_world() - grip_world()
	return axis.normalized() if axis.length_squared() > 1.0 else Vector2.RIGHT

## How far off him the point is aimed, radians.
func aim_error() -> float:
	var him := him_world()
	if him == Vector2.INF:
		return PI
	return absf(wrapf((him - grip_world()).angle() - blade_axis().angle(), -PI, PI))

func _on_press() -> void:
	_t = 0.0
	_stance = NEUTRAL
	_stance_mult = 1.0
	_hit_stances.clear()
	_next_tell = 0.0
	_next_glint = 0.0
	thrusts = 0
	swipes = 0
	best_aim = PI
	run(true)
	threaten(true)
	sound(&"shing", -8.0, 1.5)
	var fx := fx()
	if fx:
		fx.ring(tip_world(), 14.0, Color.WHITE, 0.14, 2.0)
	_update_pip()

func _on_release(_seconds: float) -> void:
	finish()

func _on_tick(delta: float) -> void:
	_t += delta
	_hold_guard()
	_read_stance()
	if not _hit_stances.is_empty():
		for s in _hit_stances:
			_landed(s)
		_hit_stances.clear()
	var him := him_world()
	_next_tell -= delta
	if _next_tell <= 0.0 and him != Vector2.INF:
		_next_tell = 0.6
		tell(&"en_garde", him)
	_next_glint -= delta
	if _next_glint <= 0.0:
		# A glint runs off the point now and then: it is on guard, and pointed.
		_next_glint = 0.45
		var fx := fx()
		if fx:
			fx.burst(tip_world(), &"star", Color.WHITE, 1, 40.0, 0.3)
	if _t >= num("guard_seconds", 4.0):
		finish()

## Lays the blade's line through his centre of mass and holds it there (`BladeAim`, D56's aim).
func _hold_guard() -> void:
	var him := him_world()
	var toward := him - grip_world() if him != Vector2.INF else blade_axis()
	var off := BladeAim.hold(self, toward, num("aim_frequency", 18.0), num("aim_damping", 0.8),
		num("aim_accel", 260.0), _gravity_)
	if him != Vector2.INF:
		best_aim = minf(best_aim, off)

## The point's velocity along the blade and across it, and what that makes a hit.
func _read_stance() -> void:
	var axis := blade_axis()
	var r := tip_world() - com_world()
	var omega := body.angular_velocity
	var v := body.linear_velocity + Vector2(-omega * r.y, omega * r.x)
	var along := v.dot(axis)
	var across := absf(v.cross(axis))
	if along >= num("thrust_speed", 300.0) and along >= across:
		_stance = THRUST
		_stance_mult = num("thrust_mult", 2.0)
	elif across > absf(along) and across >= num("thrust_speed", 300.0) * 0.5:
		_stance = SWIPE
		_stance_mult = num("swipe_mult", 0.5)
	else:
		_stance = NEUTRAL
		_stance_mult = 1.0

func _on_hit() -> void:
	_hit_stances.append(_stance)

func _landed(s: int) -> void:
	var fx := fx()
	var tip := tip_world()
	if s == THRUST:
		thrusts += 1
		payoffs += 1
		if thrusts == 1:
			paid_off.emit(&"thrust")
		# Touché: a flash down the line of the blade and out through him.
		var axis := blade_axis()
		if fx:
			fx.tracer(grip_world(), tip + axis * 60.0, Color.WHITE, 0.16, 3.0)
			fx.ring(tip, 34.0, Color.WHITE, 0.18, 2.0)
			fx.burst(tip, &"star", WorldFX.GOLD, 3, 200.0)
		sound(&"tink", -3.0, 1.0, 0.04)
	elif s == SWIPE:
		swipes += 1
		# The flat of it: a dull slap and a puff, and half the hit.
		if fx:
			fx.puff(tip, 4, WorldFX.DUST, 50.0, 0.4)
		sound(&"clack", -10.0, 0.7)

func _on_stop() -> void:
	super._on_stop()
	_stance = NEUTRAL
	_stance_mult = 1.0
	_hit_stances.clear()
