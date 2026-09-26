class_name CurveballAbility
extends ThrowAbility

## The baseball's Curveball (docs/decisions.md D78): a tap, and it is pitched high over his glove,
## breaks late and drops into his hands — and he throws it back to you.
##
## The Tomahawk's archetype, played as a game of catch. The pitch leaves the hand fast and flat at
## a point `break_height` over his hands, spinning hard, and for most of the way it is going over
## his head. Inside `break_distance` of him it **breaks**: it is steered down into his hands, at
## most `break_accel`, so the bend comes late and sharp — a twelve-to-six curve, which is the only
## curve a side view can draw. For the flight the two do not collide and the ball is swept for him
## (D74), so the catch is his and happens once.
##
## **Caught**, it sits in his hands for `hold_seconds`, riding him, and it pays: the ordinary catch
## the baseball always paid (`hearts_per_contact`) and as much again for a curveball
## (`curve_mult`), one act on the bus. Then he throws it back: it flies home to the cursor the way
## the axe does, and if left is still held the hand takes it again. Missed — he moved, or it hit
## the desk — it drops, and that pitch paid nothing.
##
## Row: `throw_speed`, `break_height`, `break_distance`, `break_accel`, `spin`, `curve_mult`,
## `hold_seconds`, `out_seconds`, `return_speed`, `return_accel`, `catch_radius`,
## `give_up_seconds`.

const PITCHED := 40
const HELD := 41

var _glove_local := Transform2D.IDENTITY
var _held_by: Buddy
var _layer := 0
var _mask := 0
var _freeze_mode := RigidBody2D.FREEZE_MODE_STATIC
var _frozen := false
var _broke := false

## For the suites: whether it broke, how far it bent, and whether he caught it.
var broke := false
var bend := 0.0
var pitches := 0
var catches := 0
var thrown_back := false

## His hands: chest height, on the side the ball comes from.
func _glove(him: Buddy, from: Vector2) -> Vector2:
	var rect := him.get_interaction_rect()
	var side := signf(from.x - rect.get_center().x)
	return Vector2(rect.get_center().x + side * rect.size.x * 0.25, rect.get_center().y - rect.size.y * 0.05)

func _on_press() -> void:
	_phase = PITCHED
	_t = 0.0
	throw_hits = 0
	caught = false
	broke = false
	bend = 0.0
	thrown_back = false
	_broke = false
	_left_down = true
	_throwing = true
	_gravity_was = body.gravity_scale
	_cursor = hand_world()
	body._end_drag()
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	var from := com_world()
	_last_com = from
	var glove := _glove(him, from) if him else from + Vector2.RIGHT * 200.0
	var high := glove + Vector2(0.0, -num("break_height", 70.0))
	var want := _pitch_at(from, high, num("throw_speed", 820.0))
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	# Topspin, hard: the seams are what break it.
	body.apply_torque_impulse((signf(want.x) * num("spin", 26.0) - body.angular_velocity) * inertia)
	last_throw_speed = want.length()
	pitches += 1
	set_process_input(true)
	run(true)
	sound(&"whoosh", -6.0, 1.3)
	AbilityCues.activation(self, from)
	# Something is coming to him to catch, head or wear: whatever routine he was in stands down.
	notice_player()
	tell(&"pitched", glove)

## The low arc from `from` through `target` at `speed` (the Tomahawk's solution, at a point).
func _pitch_at(from: Vector2, target: Vector2, speed: float) -> Vector2:
	var dx := target.x - from.x
	var rise := from.y - target.y
	var side := 1.0 if dx >= 0.0 else -1.0
	var x := absf(dx)
	var g := _gravity * body.gravity_scale
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * rise * v2)
	var angle := PI * 0.25
	if x > 1.0 and disc >= 0.0 and g > 0.0:
		angle = atan((v2 - sqrt(disc)) / (g * x))
	return Vector2(cos(angle) * side, -sin(angle)) * speed

func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	match _phase:
		PITCHED:
			_t += delta
			_pitch_step(delta)
		HELD:
			_t += delta
			_ride()
			var him := _held_by
			if not is_instance_valid(him) or him.dragging or him.health == null or him.health.down:
				_drop_it()
				return
			if _t >= num("hold_seconds", 0.6):
				_throw_back()
		_:
			# The way home, and clearing him, are the Tomahawk's.
			super._on_tick(delta)

func _pitch_step(delta: float) -> void:
	var him := buddy()
	var com := com_world()
	if him and throw_hits == 0:
		var glove := _glove(him, _last_com)
		if overlaps_him() or _crossed_him(_last_com, com) or com.distance_to(glove) <= 26.0:
			_catch(him)
			return
		# The break: late, and hard, down into his hands.
		if absf(glove.x - com.x) <= num("break_distance", 150.0):
			var v := body.linear_velocity
			var speed := maxf(v.length(), 300.0)
			var want := (glove - com).normalized() * speed
			var change := (want - v).limit_length(num("break_accel", 5200.0) * delta)
			if not _broke:
				_broke = true
				broke = true
				sound(&"zip", -12.0, 0.9)
			bend += change.length()
			body.apply_central_impulse(change * body.mass)
	_last_com = com
	var hit_world := false
	for other in body.get_colliding_bodies():
		if not (other is RigidBody2D):
			hit_world = true
	if hit_world or _t >= num("out_seconds", 1.4):
		_let_go()

## In his hands: it stays there, riding him, and it pays.
func _catch(him: Buddy) -> void:
	throw_hits += 1
	catches += 1
	_held_by = him
	_phase = HELD
	_t = 0.0
	var glove := _glove(him, _last_com)
	var xf := Transform2D(0.0, glove)
	_glove_local = him.global_transform.affine_inverse() * xf
	_layer = body.collision_layer
	_mask = body.collision_mask
	_freeze_mode = body.freeze_mode
	body.collision_layer = 0
	body.collision_mask = 0
	body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	_frozen = true
	body.global_transform = xf
	var catch_value := _catch_value()
	give(catch_value * num("curve_mult", 2.0), glove, catch_value)
	var fx := fx()
	if fx:
		fx.ring(glove, 30.0, WorldFX.kind_colour(body.juice_tier), 0.2, 2.0)
		fx.burst(glove, &"heart", WorldFX.kind_colour(body.juice_tier), 3 + body.juice_tier, 120.0, 0.6)
	sound(&"tock", -4.0, 1.0)
	tell(&"caught_it", glove)
	AbilityCues.payoff(self, &"curveball", glove, "caught!")

## What an ordinary catch of this ball pays: its own `hearts_per_contact`.
func _catch_value() -> float:
	var own = body.get(&"hearts_per_contact")
	return float(own) if own != null else 6.0

func _ride() -> void:
	if is_instance_valid(_held_by):
		body.global_transform = _held_by.global_transform * _glove_local

func _release_hold() -> void:
	if not _frozen or body == null:
		return
	_frozen = false
	body.freeze = false
	body.freeze_mode = _freeze_mode
	body.collision_layer = _layer
	body.collision_mask = _mask
	_held_by = null

## He throws it back: an underarm lob toward the hand, and then it flies home the axe's way.
func _throw_back() -> void:
	_release_hold()
	thrown_back = true
	var to := _hand() - com_world()
	var want := to.normalized() * 420.0 + Vector2(0.0, -180.0)
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	_t = 0.0
	_turn_back()
	tell(&"threw_back", com_world())

## Dropped from his hands: knocked out, picked up, or gone.
func _drop_it() -> void:
	_release_hold()
	_let_go()

func on_picked_up() -> void:
	if _active and body.dragging and _phase != BACK and _phase != CLEAR:
		# Taken from the air, or out of his hands.
		_release_hold()
		_throwing = false
		_phase = CLEAR
		_clear_t = 0.0
	super.on_picked_up()

func _on_stop() -> void:
	_release_hold()
	super._on_stop()
