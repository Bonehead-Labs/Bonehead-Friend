class_name PryTether
extends TetherAbility

## A tether that is a lever (D74): the crowbar's Pry. The one ability where the hand goes one way
## and he goes the other.
##
## Right with the crowbar's claw against him — within `reach` px of his body; anywhere else the press
## is refused, the way a charge with nothing to charge at is — **wedges** it under his near side.
## From then, while right is held, **pull the hand down and he goes up**: every pixel the hand drops
## below where it pressed lifts him `lever_ratio` pixels, up to `max_lift`, eased at `lift_speed`
## px/s, and tips him away from the bar by up to `tilt_degrees`, the way a crate tips when its near
## edge is levered. The bar creaks a notch at a time, and its claw stays on him: steered onto his
## near corner as he rises, with the handle on the line from there toward the hand.
##
## **Let go of right, or lever him all the way, and he pops**: thrown up and over at `pop` px/s,
## scaled by how far he was levered, a third of that away from the bar, spun head over heels by
## `spin` rad/s. The pry is billed once as `pry_force`, scaled the same way, through
## `Buddy.take_impulse` at the crowbar's multiplier times `pry_mult` (D7); where he comes down is the
## crowbar's for `claim_seconds` (D65). Let go before he is a fifth of the way up and he is only set
## down, for half the cooldown.
##
## Row (as well as the base's `stiffness`, `max_accel`, `claim_seconds`): `reach`, `lever_ratio`,
## `max_lift`, `lift_speed`, `tilt_degrees`, `hold_seconds`, `pop`, `spin`, `pry_force`, `pry_mult`.

var _hand0 := Vector2.ZERO
var _start := Vector2.ZERO
var _side := 1.0
var _lift := 0.0
var _creak_at := 0.0
var _pop_pending := false
var _offset := Vector2.ZERO

## For the suites: how high he was levered, and how hard the pop was.
var last_lift := 0.0
var last_pop := 0.0
var last_pull := 0.0
var popped := false

func hit_multiplier() -> float:
	return 1.0

## How high he is levered, 0..1.
func lift() -> float:
	return clampf(_lift / maxf(num("max_lift", 90.0), 1.0), 0.0, 1.0) if is_holding() else 0.0

func pip_fill() -> float:
	return lift() if is_holding() else -1.0

## Only with the claw against him.
func _can_start() -> bool:
	var him := buddy()
	return him != null and touches_him(tip_world(), num("reach", 24.0))

func _on_press() -> void:
	_reset()
	var him := buddy()
	_hand0 = _cursor()
	_start = him_world()
	_side = signf(_start.x - _hand0.x)
	if _side == 0.0:
		_side = 1.0
	_lift = 0.0
	_creak_at = 0.0
	_pop_pending = false
	last_lift = 0.0
	last_pop = 0.0
	popped = false
	_catch()
	_show_chain(false)
	if him == null:
		return

## The claw goes in under him: a clank and sparks at his corner.
func _caught() -> void:
	var fx := fx()
	if fx:
		fx.chips(_wedge(), WorldFX.SPARK, 4, 180.0)
		fx.ring(_wedge(), 26.0, WorldFX.DUST, 0.2, 2.0)
	sound(&"clack", -4.0, 0.6)
	sound(&"creak", -8.0, 0.8)

## The hand, as the cursor puts it: the handle less anything an ability added to it.
func _cursor() -> Vector2:
	if body.dragging and body.handle:
		return body.handle.global_position - body.hand_offset
	return hand_world()

## His near bottom corner: where the claw goes.
func _wedge() -> Vector2:
	var him := buddy()
	if him == null:
		return tip_world()
	var rect := him.get_interaction_rect()
	var x := rect.get_center().x - _side * rect.size.x * 0.4
	return Vector2(x, rect.end.y - 4.0)

func _anchor() -> Vector2:
	return _start + Vector2(_side * _lift * 0.2, -_lift)

func _held_event() -> StringName:
	return &"pried"

## Right let go (or the crowbar dropped) while he is levered: the pop, on the tick.
func _release_hold() -> void:
	_pop()

func _hold(delta: float) -> void:
	var him := buddy()
	if him == null:
		return
	# Held too long: it pops at whatever height it has — before the base's own time-out, which
	# would fling him instead.
	if _held_t >= num("hold_seconds", 2.5) - 0.02:
		_pop()
		return
	var max_lift := num("max_lift", 90.0)
	var drop := maxf(_cursor().y - _hand0.y, 0.0)
	var want := clampf(drop * num("lever_ratio", 1.2), 0.0, max_lift)
	_lift = move_toward(_lift, want, num("lift_speed", 260.0) * delta)
	last_lift = maxf(last_lift, _lift)
	steer(_anchor(), Vector2.ZERO, delta, num("stiffness", 16.0), num("max_accel", 9000.0))
	_tip_him(delta)
	_hold_bar(delta)
	if absf(_lift - _creak_at) >= 10.0:
		_creak_at = _lift
		sound(&"creak", -10.0, lerpf(0.8, 1.3, lift()), 0.05)
		var fx := fx()
		if fx:
			fx.chips(_wedge(), WorldFX.DUST, 2, 90.0)
	if _lift >= max_lift - 0.5:
		_pop()

## Tipped away from the bar as he rises: a torque impulse toward the tilt the lift says, never a
## write to his spin (D54).
func _tip_him(delta: float) -> void:
	var him := buddy()
	if him == null:
		return
	var target := _side * deg_to_rad(num("tilt_degrees", 30.0)) * lift()
	var err := wrapf(target - him.global_rotation, -PI, PI)
	var want := err * 10.0
	var inertia := _inertia_of(him)
	var change := clampf(want - him.angular_velocity, -30.0 * delta, 30.0 * delta)
	him.apply_torque_impulse(change * inertia)

## The bar kept on him: its claw on his near corner as he rises, and its handle on the line from
## there toward the hand (`BaseDraggable.hand_offset`), each steered by an impulse at that point —
## never a write (D54). Left to the drag joint the claw hung under the hand and he rose off it,
## which read as him floating, not as a lever.
func _hold_bar(delta: float) -> void:
	var wedge := _wedge()
	var cursor := _cursor()
	var length := grip_world().distance_to(tip_world())
	var out := cursor - wedge
	var handle := wedge + (out.normalized() if out.length_squared() > 1.0 else Vector2.LEFT) * length
	_set_offset(handle - cursor)
	var com := com_world()
	var lift := Vector2(0.0, -_gravity * body.gravity_scale * delta * 0.5)
	for pair in [[grip_world(), handle], [tip_world(), wedge]]:
		var at: Vector2 = pair[0]
		var target: Vector2 = pair[1]
		var r := at - com
		var here := body.linear_velocity + Vector2(-r.y, r.x) * body.angular_velocity
		var change := ((target - at) * 20.0 - here).limit_length(20000.0 * delta) + lift
		body.apply_impulse(change * body.mass * 0.5, at - body.global_position)

func _set_offset(offset: Vector2) -> void:
	var delta := offset - _offset
	_offset = offset
	body.hand_offset = offset
	if body.dragging and body.handle:
		body.handle.global_position += delta

func _on_stop() -> void:
	_set_offset(Vector2.ZERO)
	super._on_stop()

## He pops off the bar: up and over, spinning, and the lever's work billed once.
func _pop() -> void:
	var him := buddy()
	var frac := lift()
	if him == null or frac < 0.2:
		_set_offset(Vector2.ZERO)
		# Hardly lifted: set down, not popped, for half the cooldown once the claw is out of him.
		_let_go(false, num("cooldown", 5.0) * 0.5)
		return
	_set_offset(Vector2.ZERO)
	var up := num("pop", 900.0) * frac
	var launch := Vector2(_side * up * 0.33, -up)
	him.apply_central_impulse(launch * him.mass)
	him.apply_torque_impulse(_side * num("spin", 9.0) * frac * _inertia_of(him))
	last_pop = up
	var at := _wedge()
	last_pull = num("pry_force", 2000.0) * frac
	strike(last_pull, Vector2.UP, at, num("pry_mult", 1.3), 0.0)
	him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 2.0))
	popped = true
	var fx := fx()
	if fx:
		fx.ring(at, 50.0 + 40.0 * frac, WorldFX.DUST, 0.3, 3.0)
		fx.puff(at, 6, WorldFX.DUST, 90.0, 0.6)
		fx.chips(at, WorldFX.SPARK, 5, 260.0)
		fx.shake(3.0 + 3.0 * frac)
	sound(&"crack", -4.0, 0.7)
	sound(&"impact_metal", -8.0, 0.6)
	tell(&"flung", him_world())
	paid_off.emit(&"pry")
	_show_chain(false)
	_settle_gap = -1.0
	_phase = SETTLE
	_settle_t = 0.0
	_update_pip()

func _inertia_of(other: RigidBody2D) -> float:
	var state := PhysicsServer2D.body_get_direct_state(other.get_rid())
	if state and state.inverse_inertia > 0.0:
		return 1.0 / state.inverse_inertia
	return other.mass * 1200.0

func _update_chain() -> void:
	pass
