class_name ReapAbility
extends DashAbility

## The sickle's Reap (D74, the blades): tap right and the hand drops to the desk and sweeps a low
## arc under him and back — and if the hook catches his feet, it takes them out from under him and
## he goes **head over heels**, toward you.
##
## The katana's lunge goes straight through his middle and the cut lands late. This goes along the
## floor, hooks, and pulls: what it does to him is a flip, and it happens the instant it catches.
##
## **The hand does it** (`BaseDraggable.hand_offset`, the katana's mechanism), so the sickle hangs
## off the grip and trails through the sweep with its own weight. Four beats: **drop** to
## `floor_gap` above the desk on the near side of him (`drop_seconds`); **sweep** along the desk to
## past his far foot (`sweep_seconds`); **pull** back toward you, the reaping stroke
## (`pull_seconds`); and **return** to where the hand was (`return_seconds`). For the drop, the sweep
## and the pull he and the sickle do not collide, so the blade cannot shove him away before it has
## hooked him, and it is swept for him instead: the path its point took and its own edge, against
## his lower `feet_share` of his height. With nobody there it reaps the air.
##
## **The catch**, from the tick, before `StepStart` (D64): `reap_force` handed to him through
## `Buddy.take_impulse` at the sickle's multiplier times `reap_mult` (the gunshot's path, D7), with
## no shove of its own; then his feet are pulled toward you at `pull` px/s and he is lifted at
## `lift`, and spun head over heels at `flip` rad/s — a spin is not a velocity his ledger reads, so
## it bills nothing. Where he lands is the sickle's for `claim_seconds` (D65).
##
## Row: `drop_seconds`, `sweep_seconds`, `pull_seconds`, `return_seconds`, `floor_gap`, `sweep_px`,
## `feet_share`, `reap_force`, `reap_mult`, `pull`, `lift`, `flip`, `claim_seconds`,
## `settle_seconds`.

const DROP := 10
const SWEEP := 11
const PULL := 12
const RETURN := 13

var _side := 1.0
var _origin := Vector2.ZERO
var _low_start := Vector2.ZERO
var _low_end := Vector2.ZERO
var _from := Vector2.ZERO
var _caught := false
var _spin_pending := false
var _next_dust := 0.0

## For the suites: whether it caught him, how hard, and the spin and lift it gave him.
var last_reap := 0.0
var last_flip := 0.0
var last_lift := 0.0
var caught_him := false

## Which side of the hand he was on (+1 right): the flip goes that way, for its payoff's arrow.
func side() -> float:
	return _side

func is_reaping() -> bool:
	return _active and (_phase == DROP or _phase == SWEEP or _phase == PULL)

func _on_press() -> void:
	var him := buddy()
	_origin = hand_world()
	_side = 1.0
	var floor_y := _origin.y + 120.0
	var near_x := _origin.x + 60.0
	var far_x := _origin.x + num("sweep_px", 200.0)
	if him:
		var rect := him.get_interaction_rect()
		_side = signf(rect.get_center().x - _origin.x)
		if _side == 0.0:
			_side = 1.0
		floor_y = rect.end.y
		var near := rect.get_center().x - _side * rect.size.x * 0.5
		near_x = near - _side * 46.0
		# Well past his far foot: the blade trails the hand, so the hand has to go further than
		# the blade needs to.
		far_x = rect.get_center().x + _side * (rect.size.x * 0.5 + 40.0)
		# Never further than the row allows from where the hand is.
		var span := num("sweep_px", 200.0)
		if absf(far_x - _origin.x) > span + 60.0:
			far_x = _origin.x + _side * (span + 60.0)
	# The hand holds the grip; the blade hangs below it, so the hand stops short of the desk by
	# the blade's own drop and `floor_gap`.
	# A dragged blade trails and rises, so only half its hang is counted.
	var hang := maxf(tip_world().y - hand_world().y, 0.0)
	var low_y := floor_y - num("floor_gap", 14.0) - clampf(hang * 0.5, 0.0, 40.0)
	low_y = maxf(low_y, _origin.y)
	_low_start = Vector2(near_x, low_y)
	_low_end = Vector2(far_x, low_y)
	_phase = DROP
	_t = 0.0
	_caught = false
	_spin_pending = false
	caught_him = false
	last_reap = 0.0
	last_flip = 0.0
	last_lift = 0.0
	last_lunge = 0.0
	last_peak_speed = 0.0
	_last_tip = tip_world()
	_from = Vector2.ZERO
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	run(true)
	threaten(true)
	sound(&"whoosh", -10.0, 0.8)

func _on_tick(delta: float) -> void:
	_t += delta
	if _spin_pending:
		_spin_pending = false
		_spin_him()
	match _phase:
		DROP:
			var k := clampf(_t / maxf(num("drop_seconds", 0.1), 0.01), 0.0, 1.0)
			_set_offset(_from.lerp(_low_start - _origin, k * k))
			_reap_sweep()
			if k >= 1.0:
				_phase = SWEEP
				_t = 0.0
				_from = _offset
				threaten(false)
				body.apply_central_impulse(Vector2(_side, 0.0) * body.mass * 300.0)
				sound(&"scratch", -8.0, 1.3, 0.05)
		SWEEP:
			var k := clampf(_t / maxf(num("sweep_seconds", 0.16), 0.01), 0.0, 1.0)
			# Along the desk, dipping a little under him: a reap is an arc, not a slide.
			var along := _from.lerp(_low_end - _origin, 1.0 - (1.0 - k) * (1.0 - k))
			_set_offset(along + Vector2(0.0, 8.0 * sin(k * PI)))
			_reap_sweep()
			_skim(delta)
			if k >= 1.0:
				_phase = PULL
				_t = 0.0
				_from = _offset
		PULL:
			var k := clampf(_t / maxf(num("pull_seconds", 0.12), 0.01), 0.0, 1.0)
			_set_offset(_from.lerp(_low_start - _origin, k * k))
			_reap_sweep()
			_skim(delta)
			if k >= 1.0:
				_phase = RETURN
				_t = 0.0
				_from = _offset
		RETURN:
			var k := clampf(_t / maxf(num("return_seconds", 0.2), 0.01), 0.0, 1.0)
			_set_offset(_from * (1.0 - k * k * (3.0 - 2.0 * k)))
			if k >= 1.0:
				_set_offset(Vector2.ZERO)
				_phase = SETTLE
				_t = 0.0
		SETTLE:
			if not overlaps_him() or _t >= num("settle_seconds", 1.0):
				finish(-1.0 if _caught else num("cooldown", 3.0) * 0.5)

## Did the hook cross his feet this tick? The point's path and the edge, grip to point, against
## the lower part of him.
func _reap_sweep() -> void:
	var tip := tip_world()
	last_peak_speed = maxf(last_peak_speed, body.linear_velocity.length())
	last_lunge = maxf(last_lunge, _offset.length())
	var fx := fx()
	if fx and _phase != DROP and _last_tip != Vector2.INF:
		fx.tracer(_last_tip, tip, WorldFX.harm_colour(0).lerp(Color.WHITE, 0.5), 0.14, 3.0)
	if not _caught and _phase != DROP:
		var feet := _feet_rect()
		if feet.size != Vector2.ZERO and (feet.has_point(tip) or _segment_hits(_last_tip, tip, feet)
				or _segment_hits(grip_world(), tip, feet) or _segment_hits(com_world(), tip, feet)):
			_catch(feet)
	_last_tip = tip

func _feet_rect() -> Rect2:
	var him := buddy()
	if him == null:
		return Rect2()
	var rect := him.get_interaction_rect()
	var share := clampf(num("feet_share", 0.35), 0.1, 1.0)
	var h := rect.size.y * share
	return Rect2(rect.position.x - 4.0, rect.end.y - h, rect.size.x + 8.0, h + 6.0)

func _segment_hits(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if a == Vector2.INF:
		return false
	var steps := maxi(2, int(a.distance_to(b) / 6.0))
	for i in steps + 1:
		if rect.has_point(a.lerp(b, float(i) / float(steps))):
			return true
	return false

## Dust off the desk where the blade skims it.
func _skim(delta: float) -> void:
	_next_dust -= delta
	if _next_dust > 0.0:
		return
	_next_dust = 0.04
	var fx := fx()
	if fx:
		var tip := tip_world()
		fx.puff(Vector2(tip.x, maxf(tip.y, _low_start.y + num("floor_gap", 14.0))), 2, WorldFX.DUST, 40.0, 0.4)

## Caught: the hit, the pull, the lift — and the spin on the next tick, once his hit has stood him
## down from anything that held him upright.
func _catch(feet: Rect2) -> void:
	_caught = true
	caught_him = true
	var him := buddy()
	if him == null:
		return
	var at := Vector2(feet.get_center().x, feet.end.y - 8.0)
	last_reap = num("reap_force", 1800.0)
	strike(last_reap, Vector2(-_side, -1.0), at, num("reap_mult", 1.2), 0.0)
	last_lift = num("lift", 520.0)
	# His feet toward you, and up to the lift the reap wants from whatever he had: an impulse, never
	# a write to his velocity (D54).
	var dv := Vector2(-_side * num("pull", 260.0), minf(-last_lift - him.linear_velocity.y, 0.0))
	him.apply_central_impulse(dv * him.mass)
	him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 1.5))
	_spin_pending = false
	_spin_him()
	var fx := fx()
	if fx:
		fx.ring(at, 44.0, tier_colour(), 0.22, 3.0)
		fx.chips(at, Color("f2ead8"), 6, 260.0)
		fx.puff(Vector2(at.x, feet.end.y), 6, WorldFX.DUST, 90.0, 0.5)
		fx.shake(3.0)
	sound(&"swish", -4.0, 0.8)
	sound(&"impact_metal", -8.0, 1.3)
	tell(&"upended", at)
	paid_off.emit(&"reap")

## Head over heels: feet pulled toward you, head thrown away — clockwise when he is on your right.
## Only while nothing holds him upright; tried again on the next tick if something still does.
func _spin_him() -> void:
	var him := buddy()
	if him == null:
		return
	if him.lock_rotation:
		# The idle brain is walking him. The hit this tick stands it down on his next step, which
		# unlocks him; the spin waits for that.
		_spin_pending = _phase != SETTLE or _t < 0.3
		return
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(him.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	var target := _side * num("flip", 13.0)
	him.apply_torque_impulse((target - him.angular_velocity) * inertia)
	last_flip = absf(target)

func _on_dropped() -> void:
	_set_offset(Vector2.ZERO)
	_phase = SETTLE
	_t = 0.0
