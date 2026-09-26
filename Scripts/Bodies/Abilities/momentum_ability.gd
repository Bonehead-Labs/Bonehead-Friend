class_name MomentumAbility
extends SustainAbility

## The greatsword's Momentum (D74, the blades): hold right and the grip loosens, so the sword
## carries its own weight round in long arcs, and every hit it lands without stopping is worth
## more than the one before.
##
## **Loosened.** While right is held the hand stops fighting the blade: its angular damping comes
## off (it keeps whatever spin you give it), gravity's pull about the grip is cancelled (a slow arc
## does not sag and stall at the bottom), and the press heaves it into its first arc toward him
## (`heave` rad/s). From then on it only *keeps* momentum: while it turns faster than half of
## `carry_spin` the wrist tops it up toward `carry_spin`, capped at `carry_accel`, and never brakes
## it. So a swing goes on round the hand in long heavy arcs, a hand that stops lets it go on, and a
## blade that meets the desk or is fought to a stop stays stopped until it is swung again. The
## nunchaku's whirl is a motor at 18 rad/s for a second; this is a flywheel at a sixth of that for
## four, and the player steers it into him.
##
## **The chain.** The first hit is an ordinary hit. Each hit after it, without the blade having
## stopped in between, adds `step_mult`, to `max_mult` — x1, x1.15, x1.3, x1.45, x1.6 — and a
## notch lights by the hand for each. Stopped means its point slower than `keep_speed` px/s for
## `stop_grace` seconds together: the reversal of a hand swinging back and forth is quicker than
## that, a sword brought to rest is not. A stop drops the chain, and the notches fall off.
##
## He reads the multiplier when he attributes the contact (D7), as he reads the damage augment:
## `note_hit` records it before `_on_hit` hears of the hit, and the chain only grows on the next
## tick, so the multiplier he reads is always the one the hit was armed with.
##
## Row: `fuel_seconds`, `heave`, `carry_spin`, `carry_accel`, `keep_speed`, `stop_grace`,
## `step_mult`, `max_mult`.

var _chain := 0
var _pending := 0
var _slow_t := 0.0
var _turned := 0.0
var _damp_mode := RigidBody2D.DAMP_MODE_COMBINE
var _damp := 0.0
var _loosened := false
var _gravity_ := 980.0
var _arc: Arc
var _notches: Notches
var _sparks: GPUParticles2D

## For the suites: the longest chain this use, and hits it landed.
var best_chain := 0
var chain_hits := 0
var chains_broken := 0

func _ready() -> void:
	super._ready()
	_gravity_ = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func chain() -> int:
	return _chain if _active else 0

func hit_multiplier() -> float:
	if not _active:
		return 1.0
	return minf(1.0 + num("step_mult", 0.15) * float(_chain), num("max_mult", 1.6))

func _max_chain() -> int:
	return int(round((num("max_mult", 1.6) - 1.0) / maxf(num("step_mult", 0.15), 0.01)))

func _on_press() -> void:
	_t = 0.0
	_chain = 0
	_pending = 0
	_slow_t = 0.0
	_turned = 0.0
	best_chain = 0
	chain_hits = 0
	chains_broken = 0
	grinds = 0
	peak_rev = 0.0
	run(true)
	threaten(true)
	# The grip loosens: the damping that settles a swing is taken off for as long as it is held.
	_damp_mode = body.angular_damp_mode
	_damp = body.angular_damp
	body.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	_loosened = true
	if _arc == null:
		_arc = Arc.new()
		_arc.name = "AbilityArc"
		_arc.top_level = true
		_arc.z_index = -1
		add_child(_arc)
		_notches = Notches.new()
		_notches.name = "AbilityNotches"
		_notches.top_level = true
		_notches.z_index = 40
		add_child(_notches)
	_arc.visible = Settings.focus_intensity != Settings.Intensity.OFF
	_notches.visible = true
	_notches.show_chain(0, _max_chain(), tier_colour())
	_sparks = emitter("momentum", &"chip", tier_colour(), 14, body._find_tip(), Vector2(0, -40), 180.0,
		0.4, Vector2(0, 200))
	# The heave: the loosened grip lets the weight go, into its first arc toward him.
	whip(swing_sign() * num("heave", 4.0))
	sound(&"whoosh", -6.0, 0.5)
	_update_pip()

func _on_release(_seconds: float) -> void:
	finish()

func _on_tick(delta: float) -> void:
	_t += delta
	var grip := grip_world()
	var arm := com_world() - grip
	var omega := body.angular_velocity
	# The wrist holds its weight up, and keeps a turning blade turning — never brakes it.
	var torque := -arm.x * body.mass * _gravity_ * body.gravity_scale
	var carry := num("carry_spin", 6.0)
	if absf(omega) >= carry * 0.5 and absf(omega) < carry:
		var inertia := pivot_inertia()
		torque += signf(omega) * minf(inertia * 8.0 * (carry - absf(omega)), inertia * num("carry_accel", 40.0))
	body.apply_torque(torque)
	var tip := tip_world()
	var r := tip - com_world()
	var speed := (body.linear_velocity + Vector2(-omega * r.y, omega * r.x)).length()
	peak_rev = maxf(peak_rev, speed)
	if _pending > 0:
		_add_links(_pending)
		_pending = 0
	if speed < num("keep_speed", 220.0):
		_slow_t += delta
		if _slow_t >= num("stop_grace", 0.3) and _chain > 0:
			_break_chain()
	else:
		_slow_t = 0.0
	# The air it moves, every half turn, lower and louder the longer the chain.
	_turned += absf(omega) * delta
	if _turned >= PI:
		_turned -= PI
		sound(&"whoosh", -12.0 + 1.5 * float(_chain), 0.55 - 0.03 * float(_chain), 0.05)
	if _arc and _arc.visible:
		_arc.follow(grip, tip, omega, tier_colour(), _chain)
	# The point throws sparks once the chain is going.
	emit_from(_sparks, _chain >= 2 and speed >= num("keep_speed", 220.0))
	if _t >= num("fuel_seconds", 4.0):
		finish()

func _on_hit() -> void:
	_pending += 1

func _add_links(n: int) -> void:
	for i in n:
		chain_hits += 1
		payoffs += 1
		if chain_hits == 1:
			fx_at = tip_world()
			paid_off.emit(&"momentum")
		if _chain < _max_chain():
			_chain += 1
			best_chain = maxi(best_chain, _chain)
			# A rising note for each link, so the ear can count them.
			sound(&"plink", -9.0, pow(2.0, float(_chain) * 2.0 / 12.0), 0.0)
			var fx := fx()
			if fx:
				fx.ring(tip_world(), 26.0 + 10.0 * float(_chain), tier_colour(), 0.2, 2.0 + float(_chain) * 0.5)
				fx.chips(tip_world(), WorldFX.SPARK, 2 + _chain, 240.0)
				if _chain == _max_chain():
					fx.shake(3.0)
	if _notches:
		_notches.show_chain(_chain, _max_chain(), tier_colour())
	# The chain counted on the badge over him too (D77), where the eye is when the blade lands, and
	# the blade burning brighter with every link.
	show_state(&"momentum")
	AbilityFX.shine(sprite(), accent(), 0.12 * float(_chain))

func _break_chain() -> void:
	_chain = 0
	chains_broken += 1
	var fx := fx()
	if fx and _notches:
		fx.chips(_notches.global_position, tier_colour(), 4, 120.0)
	sound(&"clack", -12.0, 0.6)
	if _notches:
		_notches.show_chain(0, _max_chain(), tier_colour())
	AbilityFX.shine(sprite(), accent(), 0.0)

## The notches stay by the hand, under the pip.
func _draw_pip() -> void:
	super._draw_pip()
	if _notches and _notches.visible:
		_notches.global_position = (hand_world() + Vector2(16, 10)).round()

func _on_stop() -> void:
	super._on_stop()
	emit_from(_sparks, false)
	if _loosened and body:
		body.angular_damp_mode = _damp_mode
		body.angular_damp = _damp
	_loosened = false
	_chain = 0
	_pending = 0
	if _arc:
		_arc.visible = false
	if _notches:
		_notches.visible = false

## The smear behind the point: a long arc at the point's radius, as long as the spin and as thick
## as the chain. Redrawn only while it is held.
class Arc extends Node2D:
	var radius := 0.0
	var from := 0.0
	var sweep := 0.0
	var colour := Color.WHITE
	var width := 3.0

	func follow(grip: Vector2, tip: Vector2, omega: float, tint: Color, links: int) -> void:
		global_position = grip.round()
		radius = grip.distance_to(tip)
		from = (tip - grip).angle()
		sweep = -signf(omega) * clampf(absf(omega) * 0.16, 0.0, 2.6)
		colour = tint
		width = 4.0 + 2.0 * float(links)
		queue_redraw()

	func _draw() -> void:
		if radius <= 2.0 or absf(sweep) < 0.08:
			return
		var steps := maxi(4, int(absf(sweep) * 12.0))
		draw_arc(Vector2.ZERO, radius - width * 0.5, from, from + sweep, steps, colour, width, false)
		draw_arc(Vector2.ZERO, radius - width - 4.0, from, from + sweep * 0.55, steps, Color("f2ead8"), 2.0, false)

## One diamond per link the chain can hold, lit as it grows: a meter the player reads without
## looking away from the blade.
class Notches extends Node2D:
	const TRACK := Color("1a1714")
	const EMPTY := Color("4a433a")
	var lit := 0
	var slots := 4
	var colour := Color.WHITE

	func show_chain(value: int, total: int, tint: Color) -> void:
		if value == lit and total == slots and tint == colour:
			return
		lit = value
		slots = total
		colour = tint
		queue_redraw()

	func _draw() -> void:
		for i in slots:
			var at := Vector2(float(i) * 13.0, 0.0)
			var diamond := PackedVector2Array([at + Vector2(0, -7), at + Vector2(7, 0),
				at + Vector2(0, 7), at + Vector2(-7, 0)])
			draw_colored_polygon(diamond, TRACK)
			var inner := PackedVector2Array([at + Vector2(0, -4), at + Vector2(4, 0),
				at + Vector2(0, 4), at + Vector2(-4, 0)])
			draw_colored_polygon(inner, colour if i < lit else EMPTY)
