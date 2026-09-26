class_name ServeAbility
extends ThrowAbility

## The tennis ball's Serve (docs/decisions.md D78): hold right and it is tossed up out of the hand;
## let go at the top and it is struck flat and fast at him — an ace — and he volleys it back.
##
## The Tomahawk's archetype, with the timing in the player's hand. The press **tosses** the ball
## straight up at `toss_speed`, and the pip fills to the top of the toss. The release **serves** it
## from wherever it is: `timing` is 1 at the top of the toss and falls to 0 `window` seconds either
## side of it, and the serve leaves flat at him at `min_speed` to `max_speed` by it. Held until it
## has fallen back past the hand, it is a **fault**: it drops, and that is all.
##
## For the flight he and the ball do not collide and the ball is swept for him (D74). Reaching him
## he takes it: the tennis ball's own catch (`hearts_per_contact`), and for a good serve `ace_value`
## more by the timing — one act on the bus — and at `timing` of `ace` or better it is an ace, and
## says so. Then he **volleys it back**: it flies home to the hand the axe's way, and if left is
## still held the hand takes it, ready to serve again.
##
## Row: `toss_speed`, `window`, `min_speed`, `max_speed`, `ace`, `ace_value`, `out_seconds`,
## `return_speed`, `return_accel`, `catch_radius`, `give_up_seconds`.

const TOSSED := 70
const SERVED := 71

var _toss_from := Vector2.ZERO
var _apex_seconds := 0.5

## For the suites: the last serve's timing and speed, whether it was an ace, and serves he returned.
var timing := 0.0
var serve_speed := 0.0
var aces := 0
var faults := 0
var returned := 0

func pip_fill() -> float:
	if not _active or _phase != TOSSED:
		return -1.0
	return clampf(_t / maxf(_apex_seconds, 0.05), 0.0, 1.0)

## 1 at the top of the toss, 0 `window` seconds either side of it.
func timing_now() -> float:
	return clampf(1.0 - absf(_t - _apex_seconds) / maxf(num("window", 0.25), 0.01), 0.0, 1.0)

func _on_press() -> void:
	_phase = TOSSED
	_t = 0.0
	throw_hits = 0
	caught = false
	timing = 0.0
	serve_speed = 0.0
	_left_down = true
	_throwing = true
	_gravity_was = body.gravity_scale
	_cursor = hand_world()
	body._end_drag()
	# Out of the hand, but right is still down: the release is the serve, so it is still listened
	# for (the hand letting go of the ball stopped listening for it).
	_right_held = true
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	_toss_from = com_world()
	_last_com = _toss_from
	var up := num("toss_speed", 520.0)
	_apex_seconds = up / maxf(_gravity * body.gravity_scale, 1.0)
	body.apply_central_impulse((Vector2(0.0, -up) - body.linear_velocity) * body.mass)
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	body.apply_torque_impulse(-body.angular_velocity * inertia)
	set_process_input(true)
	run(true)
	sound(&"whoosh", -16.0, 1.6)
	AbilityCues.activation(self, _toss_from)
	notice_player()
	_update_pip()

## Let go: served, from wherever the toss has got to.
func _on_release(_seconds: float) -> void:
	if _phase == TOSSED:
		_serve()
		# The way home watches the cursor and the left button, as the axe's does.
		set_process_input(true)

## The focus went with right held mid-toss (D70): never a serve on a release that never came — it
## is a fault, and the ball drops.
func _on_focus_lost() -> bool:
	if _phase != TOSSED:
		return false
	faults += 1
	_let_go()
	return true

func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	match _phase:
		TOSSED:
			_t += delta
			# Fallen back past the hand with right still held: a fault.
			if _t > _apex_seconds and com_world().y > _toss_from.y + 40.0:
				faults += 1
				sound(&"ui_denied", -14.0, 0.8)
				_right_held = false
				_let_go()
			_update_pip()
		SERVED:
			_t += delta
			var him := buddy()
			var com := com_world()
			if him and throw_hits == 0 and (overlaps_him() or _crossed_him(_last_com, com)):
				_take(him)
				return
			_last_com = com
			var hit_world := false
			for other in body.get_colliding_bodies():
				if not (other is RigidBody2D):
					hit_world = true
			if hit_world or _t >= num("out_seconds", 1.2):
				_let_go()
		_:
			super._on_tick(delta)

## Struck flat at his middle, as hard as the timing says: gravity off for the flight, so flat is
## flat.
func _serve() -> void:
	timing = timing_now()
	serve_speed = lerpf(num("min_speed", 500.0), num("max_speed", 1150.0), timing)
	var him := buddy()
	var from := com_world()
	var to := him.get_interaction_rect().get_center() if him else from + Vector2.RIGHT * 300.0
	var want := (to - from).normalized() * serve_speed
	body.gravity_scale = 0.0
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	_phase = SERVED
	_t = 0.0
	last_throw_speed = serve_speed
	var fx := fx()
	if fx:
		fx.ring(from, 18.0 + 14.0 * timing, WorldFX.kind_colour(body.juice_tier), 0.16, 2.0)
	sound(&"crack", lerpf(-14.0, -4.0, timing), lerpf(1.4, 1.0, timing))
	_update_pip()
	if him:
		tell(&"served", to)

## He takes it, and it pays: his catch, and the serve's share of an ace.
func _take(him: Buddy) -> void:
	throw_hits += 1
	returned += 1
	var at := him.get_interaction_rect().get_center()
	var own = body.get(&"hearts_per_contact")
	var catch_value := float(own) if own != null else 12.0
	var bonus := num("ace_value", 6.0) * timing
	give(catch_value + bonus, at, catch_value)
	var ace := timing >= num("ace", 0.8)
	if ace:
		aces += 1
	var fx := fx()
	if fx:
		fx.burst(at, &"heart", WorldFX.kind_colour(body.juice_tier), 2 + (3 if ace else 0), 120.0, 0.6)
		if ace:
			fx.burst(at + Vector2(0, -40), &"star", WorldFX.GOLD, 5, 160.0, 0.7)
	sound(&"tock", -6.0, 1.2)
	tell(&"volley", at)
	AbilityCues.payoff(self, &"serve", at, "ACE!" if ace else "")
	# The volley: back the way it came, and home to the hand.
	var v := body.linear_velocity
	body.gravity_scale = _gravity_was
	body.apply_central_impulse((-v * 0.5 + Vector2(0.0, -160.0) - v) * body.mass)
	_t = 0.0
	_turn_back()

func on_picked_up() -> void:
	if _active and body.dragging and (_phase == TOSSED or _phase == SERVED):
		# Caught out of the air before it was served, or snatched on its way to him.
		_throwing = false
		_phase = CLEAR
		_clear_t = 0.0
	super.on_picked_up()
