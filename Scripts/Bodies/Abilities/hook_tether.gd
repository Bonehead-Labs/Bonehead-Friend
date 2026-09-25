class_name HookTether
extends TetherAbility

## A tether caught at range and reeled in (D74): the halberd's Hook and Spike.
##
## Tap right and the hook leaves the spike on a line, at `hook_speed`, reaching `reach` px — at him,
## if he is inside that reach, and straight on along the haft if he is not. Each tick the stretch of
## line it flew is swept for him on his layer, so a fast hook cannot pass through him. It catches
## what it meets. A hook that meets nobody comes back empty, and half the cooldown is spent.
##
## **Caught, he is reeled in**: pulled at `reel_speed` along the line to the spike (the base class's
## spring, capped at `max_accel`), and he and the halberd do not collide on the way. **On the spike**
## — the first tick his body reaches the tip — he is struck once: `spike_force`, scaled by how fast
## he was coming (0.6x to 1.4x of `reel_speed`), billed through `Buddy.take_impulse` at the
## halberd's multiplier times `spike_mult` (D7), and the same impulse throws him back off it by
## `shove`. Where he lands is the halberd's for `claim_seconds` (D65). If he cannot be reeled in
## within `reel_seconds` — pinned under something — the line lets go.
##
## Row (as well as the base's `stiffness`, `max_accel`, `reaction`, `claim_seconds`): `reach`,
## `hook_speed`, `reel_speed`, `reel_seconds`, `spike_force`, `spike_mult`, `shove`.

const REACH := 3
const RETURN := 4

var _hook := Vector2.ZERO
var _hook_dir := Vector2.RIGHT
var _hook_out := 0.0
var _hook_len := 0.0
var _last_hook := Vector2.INF
var _caught_at := Vector2.ZERO

## For the suites: how far the hook flew, the speed he hit the spike at and what it handed him.
var last_reach := 0.0
var last_arrival := 0.0
var last_spike := 0.0
var spiked := false
## How far his body was from the spike when the hook left.
var last_gap := 0.0

func hit_multiplier() -> float:
	return 1.0

func is_reaching() -> bool:
	return _active and (_phase == REACH or _phase == RETURN)

func pip_fill() -> float:
	if not _active:
		return -1.0
	if _phase == HELD:
		return clampf(1.0 - _held_t / maxf(num("reel_seconds", 0.8), 0.01), 0.0, 1.0)
	return -1.0

func _on_press() -> void:
	_reset()
	_phase = REACH
	_hook_out = 0.0
	last_reach = 0.0
	last_arrival = 0.0
	last_spike = 0.0
	spiked = false
	var tip := tip_world()
	var haft := (tip - grip_world()).normalized()
	var to_him := him_world() - tip
	# At him if his body is in reach: a hook thrown by a person goes where they are looking.
	var him := buddy()
	var edge := to_him.length()
	if him:
		var rect := him.get_interaction_rect()
		edge = tip.distance_to(tip.clamp(rect.position, rect.end))
	last_gap = edge
	_hook_dir = haft
	_hook_len = num("reach", 220.0)
	if edge <= num("reach", 220.0):
		# At him, and as far as his middle if that is further: it has to reach his body, not a
		# point short of it on the line to his middle.
		_hook_dir = to_him.normalized()
		_hook_len = maxf(_hook_len, to_him.length())
	_hook = tip
	_last_hook = tip
	_show_chain(true)
	sound(&"zip", -4.0, 0.7)
	sound(&"shing", -10.0, 0.6)

func _on_tick(delta: float) -> void:
	match _phase:
		REACH:
			var step := num("hook_speed", 1400.0) * delta
			_hook_out = minf(_hook_out + step, _hook_len)
			_hook = tip_world() + _hook_dir * _hook_out
			last_reach = _hook_out
			var hit := _sweep(_last_hook, _hook)
			_last_hook = _hook
			if hit != Vector2.INF:
				_caught_at = hit
				_catch()
				return
			_draw_line()
			if _hook_out >= _hook_len:
				_phase = RETURN
				sound(&"zip", -10.0, 0.5)
		RETURN:
			_hook_out = maxf(_hook_out - num("hook_speed", 1400.0) * 1.5 * delta, 0.0)
			_hook = tip_world() + _hook_dir * _hook_out
			_draw_line()
			if _hook_out <= 0.0:
				_show_chain(false)
				finish(num("cooldown", 4.0) * 0.5)
		_:
			super._on_tick(delta)

## Where the line meets him, or INF: the segment the hook flew this tick, on his layer.
func _sweep(from: Vector2, to: Vector2) -> Vector2:
	if from.is_equal_approx(to) or not body.is_inside_tree():
		return Vector2.INF
	var query := PhysicsRayQueryParameters2D.create(from, to, BUDDY_LAYER)
	query.hit_from_inside = true
	var hit := body.get_world_2d().direct_space_state.intersect_ray(query)
	return hit.get("position", Vector2.INF)

## The hook bites: a clack and a few chips where it went in.
func _caught() -> void:
	var fx := fx()
	if fx:
		fx.chips(_caught_at, Color("f2ead8"), 4, 200.0)
		fx.ring(_caught_at, 30.0, Color("c9c4b4"), 0.2, 2.0)
	sound(&"clack", -4.0, 0.7)
	sound(&"chain", -8.0, 1.2)

## Reeled in along the line, to the spike; struck the tick he reaches it.
func _hold(delta: float) -> void:
	var him := buddy()
	if him == null:
		return
	var tip := tip_world()
	var to := tip - him_world()
	var distance := to.length()
	if touches_him(tip, 4.0) or distance <= 20.0:
		_spike()
		return
	if _held_t >= num("reel_seconds", 0.8):
		_let_go(false)
		return
	var along := to / maxf(distance, 0.001)
	# A reel, not a spring: at `reel_speed` toward the spike from wherever he is, and the spike's own
	# motion on top so a moving halberd still lands him on its point.
	var want := velocity_at(tip) + along * num("reel_speed", 900.0) * clampf(distance / 60.0, 0.5, 1.0)
	steer(him_world() + (want * delta), Vector2.ZERO, delta, 1.0 / maxf(delta, 0.001), num("max_accel", 12000.0))
	_hook = him.get_interaction_rect().get_center()
	_draw_line()

## On the spike: the hit, billed once, and he is thrown back off it.
func _spike() -> void:
	var him := buddy()
	if him == null:
		_let_go(false)
		return
	var v := him.linear_velocity
	last_arrival = v.length()
	var share := clampf(last_arrival / maxf(num("reel_speed", 900.0), 1.0), 0.6, 1.4)
	last_spike = num("spike_force", 2400.0) * share
	var back := -v.normalized() if v.length_squared() > 1.0 else (him_world() - tip_world()).normalized()
	# His momentum into the spike is taken out first: a spear stops what runs onto it.
	him.apply_central_impulse(-v * him.mass)
	strike(last_spike, back, tip_world(), num("spike_mult", 1.5), num("shove", 0.4))
	him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 1.5))
	spiked = true
	var fx := fx()
	if fx:
		var at := tip_world()
		fx.ring(at, 60.0, tier_colour(), 0.25, 3.0)
		fx.burst(at, &"star", WorldFX.GOLD, 5, 260.0)
		fx.chips(at, Color("f2ead8"), 6, 280.0)
		fx.shake(5.0)
	sound(&"crack", -2.0, 0.8)
	sound(&"impact_metal", -6.0, 0.9)
	tell(&"skewered", tip_world())
	paid_off.emit(&"spike")
	_show_chain(false)
	_settle_gap = -1.0
	_phase = SETTLE
	_settle_t = 0.0
	_update_pip()

## The line from the spike to the hook: links, and the hook on the end.
func _draw_line() -> void:
	if _chain:
		_chain.set_line(tip_world(), _hook)
		_chain.hook_at = _hook
		_chain.hook_dir = _hook_dir

func _update_chain() -> void:
	_draw_line()

## Held: the reel; he is not flung when it ends, he is either spiked or let go.
func _on_release(_seconds: float) -> void:
	pass

func _on_dropped() -> void:
	match _phase:
		REACH, RETURN:
			_show_chain(false)
			finish(num("cooldown", 4.0) * 0.5)
		HELD:
			_release_pending = true

## The halberd dropped mid-reel: the line goes slack.
func _release_hold() -> void:
	_let_go(false)

## The reel pulls toward the spike, and the halberd takes the strain there.
func _anchor() -> Vector2:
	return tip_world()

func _held_event() -> StringName:
	return &"hooked"
