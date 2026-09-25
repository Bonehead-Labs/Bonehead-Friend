class_name RicochetAbility
extends ThrowAbility

## The tyre iron is thrown into the desk and banks off everything it hits, at him (D74): Ricochet.
##
## A tap lets it go — not at him, as the axe goes, but **into the world**: along the hand's own
## flick if it is moving (`flick_speed`), and otherwise down into the desk in front of him
## (`skip_degrees` below level), a skip shot. From then on, every time it strikes the world —
## the desk, a wall, the top of the window — it **banks**: a ping, a spark, and the iron leaves
## the surface straight at his middle at `bank_speed`, a little faster each time
## (`bank_gain`), with gravity off for the leg so the line it takes is the line it was given. Up to
## `banks` banks, then it is only a tyre iron again: it falls where it falls, and you go and get it.
##
## **Each leg can hit him once.** The throw bills itself the axe's way (D74): for the flight he and
## the iron do not collide, and it is swept for him — its shapes and the segment its centre flew.
## A leg that finds him hands him `hit_force`, scaled by how fast it was going (0.6x to 1.4x of
## `bank_speed`), through `Buddy.take_impulse` at the iron's multiplier times `1 + bank_mult x
## banks so far` — a straight throw that hits him is plain, a third-bank hit is x1.75 — and it
## rebounds off him with gravity back on, to find the next surface.
##
## The Tomahawk is the other throw: that one goes straight at him and comes home to the hand. This
## one never goes straight at him on purpose, and does not come back.
##
## Row: `throw_speed`, `flick_speed`, `skip_degrees`, `spin`, `banks`, `bank_speed`, `bank_gain`,
## `hit_force`, `bank_mult`, `shove`, `give_up_seconds`.

const FLY := 0
const FALL := 1
const DONE := 2

var _leg_hit := false
var _banked := 0
var _state := FLY
var _world_touch := false
var _cool_touch := 0.0
var _gravity_scale_was := 1.0

## For the suites: every bank's world point, every hit's multiplier, and the flight's length.
var bank_points: Array[Vector2] = []
var hit_mults: Array[float] = []
var last_flight := 0.0

func in_flight() -> bool:
	return _active and _state != DONE

func banks_done() -> int:
	return _banked

func _on_press() -> void:
	_t = 0.0
	_state = FLY
	_banked = 0
	_leg_hit = false
	_world_touch = false
	_cool_touch = 0.0
	throw_hits = 0
	last_hit = 0.0
	caught = false
	bank_points.clear()
	hit_mults.clear()
	_throwing = true
	_gravity_scale_was = body.gravity_scale
	var hand_v := body.linear_velocity
	var from := com_world()
	_last_com = from
	body._end_drag()
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	var speed := num("throw_speed", 1300.0)
	var dir := Vector2.ZERO
	if hand_v.length() >= num("flick_speed", 450.0):
		# A flick: where the hand was already going.
		dir = hand_v.normalized()
	else:
		# Still: down into the desk short of him, so the first thing it meets is the world.
		var side := 1.0
		var at := him_world()
		if at != Vector2.INF:
			side = 1.0 if at.x >= from.x else -1.0
		dir = Vector2(side, 0.0).rotated(side * deg_to_rad(num("skip_degrees", 55.0)))
	var want := dir * speed
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	var spin := signf(want.x) if absf(want.x) > 1.0 else 1.0
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	body.apply_torque_impulse((spin * num("spin", 18.0) - body.angular_velocity) * inertia)
	last_throw_speed = want.length()
	run(true)
	sound(&"whoosh", -4.0, 0.8)

## No catching: the left button is not watched, and a drop mid-flight changes nothing.
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		release()

func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	_t += delta
	last_flight = _t
	_cool_touch -= delta
	if _state == DONE:
		_clear_t += delta
		if not overlaps_him() or _clear_t >= 1.0:
			finish()
		return
	var com := com_world()
	if not _leg_hit and (overlaps_him() or _crossed_him(_last_com, com)):
		_hit_him()
		_last_com = com_world()
		return
	_last_com = com
	var touching := false
	for other in body.get_colliding_bodies():
		if not (other is RigidBody2D):
			touching = true
	if _state == FLY and touching and not _world_touch and _cool_touch <= 0.0:
		if _banked < int(num("banks", 3)):
			_bank()
		else:
			_fall()
	_world_touch = touching
	if _state == FALL and (touching and _t > 0.1 or body.linear_velocity.length() < 40.0):
		_settle()
	if _t >= num("give_up_seconds", 3.5):
		_settle()

## Off the world and straight at him, a little faster than last time.
func _bank() -> void:
	_banked += 1
	_leg_hit = false
	_cool_touch = 0.08
	var at := com_world()
	var target := him_world()
	var fx := fx()
	if target == Vector2.INF:
		_fall()
		return
	var speed := num("bank_speed", 1300.0) * (1.0 + num("bank_gain", 0.1) * float(_banked - 1))
	var want := (target - at).normalized() * speed
	body.gravity_scale = 0.0
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	bank_points.append(at)
	if fx:
		fx.ring(at, 26.0, WorldFX.SPARK, 0.14, 2.0)
		fx.chips(at, WorldFX.SPARK, 5, 260.0)
		# The line it is about to take, for a blink: the bank reads as aimed, not as luck.
		fx.tracer(at, at + want.normalized() * minf(at.distance_to(target), 220.0), Color.WHITE, 0.12, 2.0)
	sound(&"ricochet", -4.0, 1.0 + 0.08 * float(_banked), 0.04)
	tell(&"incoming", target)

func _hit_him() -> void:
	var him := buddy()
	if him == null:
		return
	_leg_hit = true
	var v := body.linear_velocity
	var share := clampf(v.length() / maxf(num("bank_speed", 1300.0), 1.0), 0.6, 1.4)
	last_hit = num("hit_force", 2200.0) * share
	var mult := 1.0 + num("bank_mult", 0.25) * float(_banked)
	var at := him.get_interaction_rect().get_center()
	strike(last_hit, v if v.length_squared() > 1.0 else Vector2.RIGHT, at, mult, num("shove", 0.5))
	hit_mults.append(mult)
	throw_hits += 1
	paid_off.emit(&"ricochet")
	# Off him: turned round and slowed, with gravity back, to find the next surface.
	body.gravity_scale = _gravity_scale_was
	body.apply_central_impulse((-v * 0.45 + Vector2(0, -260) - v) * body.mass)
	var fx := fx()
	if fx:
		fx.chips(at, Color("f2ead8"), 6, 260.0)
		fx.ring(at, 40.0 + 12.0 * float(_banked), tier_colour(), 0.2, 3.0)
		fx.shake(2.0 + 1.5 * float(_banked))
	sound(&"impact_metal", -4.0, 0.9 + 0.1 * float(_banked))
	if _banked >= int(num("banks", 3)):
		_fall()

func _fall() -> void:
	_state = FALL
	body.gravity_scale = _gravity_scale_was

func _settle() -> void:
	body.gravity_scale = _gravity_scale_was
	_throwing = false
	_state = DONE
	_clear_t = 0.0
	sound(&"impact_metal", -14.0, 0.6)

func _on_stop() -> void:
	if body:
		body.gravity_scale = _gravity_scale_was
	_throwing = false
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null
