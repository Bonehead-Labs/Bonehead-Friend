class_name TetherAbility
extends WeaponAbility

## He is on the end of the weapon for a while, and goes where it goes (D74): the flail's Wrap. The
## halberd's Hook and Spike (`HookTether`) and the crowbar's Pry (`PryTether`) are the same
## machinery caught and moved another way.
##
## **The Wrap.** Right pressed arms the chain for `armed_seconds`: it rattles, and the next hit the
## weapon lands on him (billed at `catch_mult`, read by him as he reads a charged bat) wraps it round
## him. From then he is **held** on `rope` px of chain from the head (`_anchor`): slack when he is
## nearer than that, taut when he is not, so he hangs from it, swings on it and whirls round when the
## hand goes round — a ball on a chain with him as the ball. While right stays down he stays on it, up to
## `hold_seconds`; **letting go of right flings him**, the way the head was going, at `fling_mult`
## of its speed (or his, if he is the faster), never slower than `fling_min` or faster than
## `fling_max` (and never slower than he already is). The fling itself is not a hit: the chain
## throws him, and what he is thrown into is. A tap that catches him holds him for `hold_seconds` and
## then flings him the same way. Anything he is swung into while he is on it, and wherever he comes
## down for `claim_seconds` after, is the weapon's hit at `slam_mult` of its multiplier (D65): he is
## its head, and the desk it throws him into is who hits him.
##
## **How he is held.** Never by a write to his velocity (D54): by one impulse through his centre of
## mass a tick, capped at `max_accel` a second. A chain (`rope`) takes out the part of his velocity
## carrying him further from the anchor than the chain is long and closes `stiffness` of any stretch
## a second; with no chain, `steer` pulls him onto the anchor itself — the velocity that closes
## `stiffness` of the gap a second, plus the anchor's own, less the gravity the step will add. It is applied from the ability's `_physics_process`, which runs
## before `Buddy.StepStart` reads the step's starting velocity, so his ledger never bills the pull as
## a contact (D64). Half of it (`reaction`) is handed back to the weapon, so a chain with him on it
## is heavier to swing. He and the weapon do not collide while he is held — the head is wrapped in
## him — and the exception stays until they are clear of each other afterwards (D61).
##
## It lets go by itself if he is picked up, knocked out, or leaves the hand's reach.
##
## Row: `armed_seconds`, `catch_mult`, `hold_seconds`, `rope`, `stiffness`, `max_accel`, `reaction`,
## `fling_mult`, `fling_min`, `fling_max`, `slam_mult`, `claim_seconds`, `leash`, `tell`.

const ARMED := 0
const HELD := 1
const SETTLE := 2
## Held further from the anchor than this, he has come off it.
const LEASH := 320.0
const TELL_SECONDS := 0.5

var _phase := ARMED
var _t := 0.0
var _held_t := 0.0
var _settle_t := 0.0
var _catch_pending := false
var _release_pending := false
var _excepted: Buddy
var _tell_clock := 0.0
var _gravity := 980.0
var _chain: Chain
var _sparks: GPUParticles2D
## The cooldown to start once it has settled; negative for the row's own.
var _settle_gap := -1.0

## For the suites: times he was caught, how long he was held, his fastest while held, how fast he
## left, and whether the last one ended in a fling.
var catches := 0
var held_for := 0.0
var peak_speed := 0.0
var last_fling := 0.0
var flung := false

func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func _can_start() -> bool:
	return buddy() != null

func is_armed() -> bool:
	return _active and _phase == ARMED

func is_holding() -> bool:
	return _active and _phase == HELD

func hit_multiplier() -> float:
	return num("catch_mult", 1.0) if is_armed() else 1.0

func pip_fill() -> float:
	if not _active:
		return -1.0
	if _phase == ARMED:
		return clampf(1.0 - _t / maxf(num("armed_seconds", 1.5), 0.01), 0.0, 1.0)
	if _phase == HELD:
		return clampf(1.0 - _held_t / maxf(num("hold_seconds", 2.0), 0.01), 0.0, 1.0)
	return -1.0

func _on_press() -> void:
	_reset()
	threaten(true)
	_sparks = emitter("chain_sparks", &"chip", Color("c9c4b4"), 6, body.center_of_mass, Vector2(0, -40),
		180.0, 0.4)
	emit_from(_sparks, true)
	sound(&"chain", -8.0, 0.9)
	_update_pip()

## A fresh use: every clock and count back to the start, and the tick on.
func _reset() -> void:
	_phase = ARMED
	_t = 0.0
	_held_t = 0.0
	_settle_gap = -1.0
	_catch_pending = false
	_release_pending = false
	catches = 0
	held_for = 0.0
	peak_speed = 0.0
	last_fling = 0.0
	flung = false
	run(true)

func _on_hit() -> void:
	if is_armed():
		_catch_pending = true

## Letting go of right lets go of him — on the next tick, which is where anything done to him is
## done (D64). An impulse from the input handler would land before `StepStart` too, but only by the
## accident of when input is flushed.
func _on_release(_seconds: float) -> void:
	if _phase == HELD:
		_release_pending = true

func _on_dropped() -> void:
	match _phase:
		ARMED:
			finish(num("cooldown", 4.0) * 0.5)
		HELD:
			# A flail let go of mid-swing lets go of him too: the swing carries him off.
			_release_pending = true

func _on_tick(delta: float) -> void:
	match _phase:
		ARMED:
			if _catch_pending:
				_catch_pending = false
				_catch()
				return
			_t += delta
			if _t >= num("armed_seconds", 1.5):
				emit_from(_sparks, false)
				finish(num("cooldown", 4.0) * 0.5)
		HELD:
			if _release_pending:
				_release_pending = false
				_release_hold()
				return
			_held_t += delta
			held_for = _held_t
			if not _still_on():
				_let_go(false)
				return
			_hold(delta)
			var him := buddy()
			if him:
				peak_speed = maxf(peak_speed, him.linear_velocity.length())
			_tell_clock -= delta
			if _tell_clock <= 0.0 and _phase == HELD:
				_tell_clock = TELL_SECONDS
				tell(_held_event(), _tell_at())
			if _phase == HELD and _held_t >= num("hold_seconds", 2.0):
				_let_go(true)
		SETTLE:
			_settle_t += delta
			if not overlaps_him() or _settle_t >= 1.0:
				finish(_settle_gap)

## He is on it now.
func _catch() -> void:
	var him := buddy()
	if him == null:
		finish(num("cooldown", 4.0) * 0.5)
		return
	emit_from(_sparks, false)
	threaten(false)
	body.add_collision_exception_with(him)
	_excepted = him
	_phase = HELD
	_held_t = 0.0
	_tell_clock = TELL_SECONDS
	catches += 1
	payoffs += 1
	_show_chain(true)
	_caught()
	tell(_held_event(), _tell_at())
	paid_off.emit(&"catch")
	_update_pip()

## What catching him looks and sounds like. The Wrap: the chain closing round him.
func _caught() -> void:
	var fx := fx()
	if fx:
		# The lasso round him is the look's (`Shapes/wrap_catch.gd`); the ring is the generic one.
		if not AbilityLooks.pay_spec(look(), &"catch").has("shape"):
			fx.ring(him_world(), 56.0, Color("c9c4b4"), 0.25, 3.0)
		fx.chips(him_world(), WorldFX.SPARK, 5, 220.0)
	sound(&"chain", -2.0, 1.1)
	sound(&"impact_metal", -8.0, 0.7)

## Whether he is still on it: not picked up, not knocked out, not torn off.
func _still_on() -> bool:
	var him := buddy()
	if him == null or him.dragging or him.freeze or (him.health and him.health.down):
		return false
	return him_world().distance_to(_anchor()) <= num("leash", LEASH)

## One tick of being held. The Wrap: he goes where the head goes, and anything he is swung into is
## the flail's hit (D65) — he is its head now.
func _hold(delta: float) -> void:
	var rope := num("rope", 0.0)
	if rope > 0.0:
		chain_to(_anchor(), _anchor_velocity(), rope, delta, num("stiffness", 14.0), num("max_accel", 9000.0))
	else:
		steer(_anchor(), _anchor_velocity(), delta, num("stiffness", 14.0), num("max_accel", 9000.0))
	var him := buddy()
	if him:
		him.claim_impacts(body.item_id, base_mult() * num("slam_mult", 1.0), 0.3)
	_update_chain()

## Where he is pulled: the head, wrapped in him.
func _anchor() -> Vector2:
	return com_world()

## How fast that point on the weapon is moving.
func _anchor_velocity() -> Vector2:
	return velocity_at(_anchor())

## Where he is told it happens from — he leans away from it.
func _tell_at() -> Vector2:
	return _anchor()

## The row he pulls a face from while he is held.
func _held_event() -> StringName:
	return StringName(row.get("tell", &"wrapped"))

## Right let go while he is held. The Wrap: the fling.
func _release_hold() -> void:
	_let_go(true)

## Off it. A fling, or just let go — and `gap`, if given, is the cooldown once it has settled.
func _let_go(fling: bool, gap: float = -1.0) -> void:
	_settle_gap = gap
	var him := buddy()
	flung = false
	if fling and him and _phase == HELD:
		# A hammer throw leaves at the speed of the hammer: the faster of him and the head he is
		# wrapped round, times `fling_mult`, the way the faster one was going — never slower than
		# `fling_min`, so letting go always throws him, and never faster than `fling_max`.
		var v := him.linear_velocity
		var head := _anchor_velocity()
		var lead := head if head.length() > v.length() else v
		if lead.length_squared() < 1.0:
			lead = Vector2(signf(him_world().x - hand_world().x), -0.5)
		# Never slower than he already is: a whirl past the cap is let go as it is.
		var want := maxf(clampf(lead.length() * num("fling_mult", 1.5), num("fling_min", 500.0),
			num("fling_max", 1500.0)), v.length())
		var target := lead.normalized() * want
		him.apply_central_impulse((target - v) * him.mass)
		last_fling = want
		flung = true
		him.claim_impacts(body.item_id, base_mult() * num("slam_mult", 1.0), num("claim_seconds", 2.0))
		var fx := fx()
		if fx and not AbilityLooks.pay_spec(look(), &"fling").has("shape"):
			fx.ring(him_world(), 40.0, tier_colour(), 0.2, 2.0)
		sound(&"whoosh", -4.0, 0.8)
		sound(&"chain", -10.0, 1.3)
		tell(&"flung", him_world())
		paid_off.emit(&"fling")
	_show_chain(false)
	_phase = SETTLE
	_settle_t = 0.0
	_update_pip()

func _on_stop() -> void:
	emit_from(_sparks, false)
	_show_chain(false)
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null

# --- for the subclasses --------------------------------------------------------------

## Pulls him toward `anchor`, which moves at `anchor_v`: the velocity that closes `stiffness` of the
## gap a second on top of the anchor's own, less the gravity this step will add, reached by one
## impulse through his centre of mass capped at `max_accel` px/s² — never a write to his velocity
## (D54), and from the tick before StepStart (D64). `reaction` of it goes back into the weapon.
func steer(anchor: Vector2, anchor_v: Vector2, delta: float, stiffness: float, max_accel: float) -> void:
	var him := buddy()
	if him == null:
		return
	var want := anchor_v + (anchor - him_world()) * stiffness
	var change := want - him.linear_velocity
	change.y -= _gravity * him.gravity_scale * delta
	change = change.limit_length(max_accel * delta)
	him.apply_central_impulse(change * him.mass)
	var back := num("reaction", 0.5)
	if back > 0.0:
		body.apply_impulse(-change * him.mass * back, _anchor() - body.global_position)

## Keeps him within `rope` px of `anchor`, which moves at `anchor_v`: an inextensible chain. Slack,
## it does nothing; taut, it takes out the part of his velocity, relative to the anchor, that is
## carrying him away, and pulls any stretch back in at `stiffness` a second. Gravity is his own —
## he hangs from it. The same caps, the same tick and the same reaction as `steer`.
func chain_to(anchor: Vector2, anchor_v: Vector2, rope: float, delta: float, stiffness: float,
		max_accel: float) -> void:
	var him := buddy()
	if him == null:
		return
	var out := him_world() - anchor
	var distance := out.length()
	if distance <= rope or distance < 0.001:
		return
	var n := out / distance
	var change := Vector2.ZERO
	var away := (him.linear_velocity - anchor_v).dot(n)
	if away > 0.0:
		change -= n * away
	change -= n * (distance - rope) * stiffness
	change = change.limit_length(max_accel * delta)
	him.apply_central_impulse(change * him.mass)
	var back := num("reaction", 0.5)
	if back > 0.0:
		body.apply_impulse(-change * him.mass * back, _anchor() - body.global_position)

## The velocity of a point fixed to the weapon.
func velocity_at(point: Vector2) -> Vector2:
	var r := point - com_world()
	return body.linear_velocity + Vector2(-r.y, r.x) * body.angular_velocity

func _show_chain(on: bool) -> void:
	if on and _chain == null:
		_chain = Chain.new()
		_chain.name = "AbilityChain"
		_chain.top_level = true
		_chain.z_index = 32
		add_child(_chain)
	if _chain:
		_chain.visible = on
		if on:
			_update_chain()

## The chain as it is now: for the Wrap, a loop round his middle and the links up to the head.
func _update_chain() -> void:
	var him := buddy()
	if _chain == null or him == null:
		return
	# Round his waist, under his face, in his own frame, so it turns with him as he tumbles.
	var rect := him.get_interaction_rect()
	_chain.set_wrap(him.global_transform * Vector2(0, 30), Vector2(rect.size.x * 0.5 + 4.0, 8.0),
		_anchor(), him.global_rotation)

## Links, drawn: a loop round something and a run of links to a point, or just the run. Two-pixel
## links, dark and steel in turn, so it reads as a chain at 1x and never as a line.
class Chain extends Node2D:
	const DARK := Color("26221d")
	const STEEL := Color("c9c4b4")
	var loop_centre := Vector2.INF
	var loop_radius := Vector2.ZERO
	var loop_turn := 0.0
	var run_from := Vector2.INF
	var run_to := Vector2.INF
	## A hook on the end of the run, pointing along `hook_dir` — the halberd's; INF for none.
	var hook_at := Vector2.INF
	var hook_dir := Vector2.RIGHT

	func set_wrap(centre: Vector2, radius: Vector2, to: Vector2, turn: float = 0.0) -> void:
		global_position = Vector2.ZERO
		hook_at = Vector2.INF
		loop_centre = centre.round()
		loop_radius = radius
		loop_turn = turn
		# The run leaves the loop from the side nearest the head.
		var toward := (to - centre).rotated(-turn)
		var a := atan2(toward.y / maxf(radius.y, 1.0), toward.x / maxf(radius.x, 1.0))
		run_from = centre + Vector2(cos(a) * radius.x, sin(a) * radius.y).rotated(turn)
		run_to = to
		queue_redraw()

	func set_line(from: Vector2, to: Vector2) -> void:
		global_position = Vector2.ZERO
		loop_centre = Vector2.INF
		run_from = from
		run_to = to
		queue_redraw()

	func _draw() -> void:
		if loop_centre != Vector2.INF:
			# Only the half in front of him, link against link, so it reads as wound round him and
			# not as a ring of dots laid over him.
			var steps := maxi(8, int(PI * loop_radius.x / 5.0))
			for i in steps + 1:
				var a := PI * float(i) / float(steps)
				var p := loop_centre + Vector2(cos(a) * loop_radius.x, sin(a) * loop_radius.y).rotated(loop_turn)
				_link(p, i)
		if run_from != Vector2.INF and run_to != Vector2.INF:
			var length := run_from.distance_to(run_to)
			var n := maxi(1, int(length / 6.0))
			for i in n + 1:
				_link(run_from.lerp(run_to, float(i) / float(n)), i)
		if hook_at != Vector2.INF:
			# A J: a shank along the line and a barb curling back, steel on a dark rim.
			var d := hook_dir.normalized()
			var side := d.orthogonal()
			var tip := hook_at + d * 6.0
			var points := PackedVector2Array([hook_at - d * 8.0, tip, tip + side * 7.0 - d * 2.0,
				tip + side * 8.0 - d * 8.0])
			draw_polyline(points, DARK, 5.0)
			draw_polyline(points, STEEL, 3.0)

	func _link(p: Vector2, i: int) -> void:
		var at := p.round()
		draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), DARK)
		draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), STEEL if i % 2 == 0 else STEEL.darkened(0.3))
