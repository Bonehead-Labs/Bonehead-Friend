class_name StrikeAbility
extends ThrowAbility

## The bowling ball's Strike (docs/decisions.md D78): a tap, and it is bowled — down onto the desk
## and rolling at him — and he goes over like a pin.
##
## The Tomahawk's archetype, on the floor. The ball leaves the hand toward him at `roll_speed`,
## drops to the desk if the hand was high, and rolls with the topspin that speed means for its
## radius, so it keeps its speed along the desk and passes under anything. For the roll he and the
## ball do not collide and the ball is swept for him instead (D74: a thrown body's contact bills a
## fraction of its speed), so the strike is billed once: `hit_force`, by how fast it arrived
## (0.6x to 1.4x of `roll_speed`), at the ball's multiplier times `strike_mult`, through
## `Buddy.take_impulse`, from this tick, before `StepStart` (D64). Then **he topples**: lifted `lift`
## px/s off the desk and turned stiff, head first, away down the lane at `topple` rad/s, the way a
## pin goes; where he comes down is the ball's for `claim_seconds` (D65). The ball rolls on at a
## third of its speed. It does not come back: a bowling ball is fetched.
##
## The only ability that arrives along the desk, and the only one that sends him over *away* from
## you, stiff (the sickle's reap turns him head over heels *toward* you).
##
## Row: `roll_speed`, `hit_force`, `strike_mult`, `shove`, `topple`, `lift`, `claim_seconds`,
## `out_seconds`.

const ROLLING := 30
const ROLLED_ON := 31

## For the suites: the speed it arrived at, and how he went over.
var arrived_at := 0.0
var toppled := 0.0
var strikes := 0

func _on_press() -> void:
	_phase = ROLLING
	_t = 0.0
	throw_hits = 0
	last_hit = 0.0
	caught = false
	arrived_at = 0.0
	toppled = 0.0
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
	var side := signf(him_world().x - from.x) if him else 1.0
	if side == 0.0:
		side = 1.0
	var speed := num("roll_speed", 900.0)
	# Along the desk at him, and never upward: a ball bowled from high is dropped, then rolls.
	var want := Vector2(side * speed, maxf(body.linear_velocity.y, 60.0))
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	# Rolling, not sliding: the spin that speed means for its radius, clockwise to the right.
	var radius := _radius()
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	body.apply_torque_impulse((side * speed / maxf(radius, 4.0) - body.angular_velocity) * inertia)
	last_throw_speed = speed
	run(true)
	sound(&"rumble", -4.0, 1.0)
	AbilityCues.activation(self, from)
	tell(&"incoming", him_world())

func _radius() -> float:
	if body.collider and body.collider.shape is CircleShape2D:
		return (body.collider.shape as CircleShape2D).radius * absf(body.collider.global_scale.x)
	return body.get_interaction_rect().size.y * 0.5

## Bowled, it is no longer in the hand; a drop after that changes nothing.
func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	_t += delta
	match _phase:
		ROLLING:
			var com := com_world()
			if throw_hits == 0 and (overlaps_him() or _crossed_him(_last_com, com)):
				_strike()
				return
			_last_com = com
			# Rolling on or not, it is done once it has all but stopped or run out of time.
			if _t >= num("out_seconds", 2.5) or (_t > 0.4 and body.linear_velocity.length() < 40.0):
				_phase = CLEAR
				_clear_t = 0.0
		ROLLED_ON:
			if _t >= 0.25:
				_phase = CLEAR
				_clear_t = 0.0
		CLEAR:
			_clear_t += delta
			if not overlaps_him() or _clear_t >= 1.0:
				finish()

## Down he goes: the strike billed once, his feet taken toward the way it rolled, and he turns
## over stiff as a pin.
func _strike() -> void:
	var him := buddy()
	if him == null:
		return
	var v := body.linear_velocity
	var side := signf(v.x) if absf(v.x) > 1.0 else signf(him.global_position.x - com_world().x)
	if side == 0.0:
		side = 1.0
	arrived_at = absf(v.x)
	var share := clampf(arrived_at / maxf(num("roll_speed", 900.0), 1.0), 0.6, 1.4)
	last_hit = num("hit_force", 2400.0) * share
	var rect := him.get_interaction_rect()
	var at := Vector2(rect.get_center().x - side * rect.size.x * 0.3, rect.end.y - 12.0)
	strike(last_hit, Vector2(side, -0.35), at, num("strike_mult", 1.5), num("shove", 0.35))
	throw_hits += 1
	strikes += 1
	# Over like a pin: lifted off his feet, and turned head-first the way the ball was going.
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(him.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	toppled = side * num("topple", 7.0)
	him.apply_torque_impulse(toppled * inertia)
	him.apply_central_impulse(Vector2(0.0, -num("lift", 260.0)) * him.mass)
	him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 2.0))
	# It rolls on under him, slower.
	body.apply_central_impulse(-v * body.mass * 0.65)
	_phase = ROLLED_ON
	_t = 0.0
	var fx := fx()
	if fx:
		fx.chips(at, Color("f2ead8"), 8, 300.0)
		fx.chips(at, WorldFX.SOOT, 4, 200.0)
		fx.ring(at, 60.0, tier_colour(), 0.25, 3.0)
		fx.shake(4.0)
	sound(&"pins", 0.0, 1.0)
	tell(&"bowled", rect.get_center())
	AbilityCues.payoff(self, &"strike", rect.get_center(), "STRIKE!")

## Picked up while it rolls: the bowl is over.
func on_picked_up() -> void:
	if _active and body.dragging:
		finish()
	super.on_picked_up()
