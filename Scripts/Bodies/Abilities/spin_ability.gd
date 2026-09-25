class_name SpinAbility
extends WeaponAbility

## It whirls about the hand (D74): the nunchaku's Whirlwind.
##
## Right while holding it spins it about the grip at `spin_rate` rad/s for `spin_seconds`,
## whichever way it was already going (from still, away from him first, so it comes round at speed).
## The spin is a **torque**, never a write to `angular_velocity` (D54, D56): a PD on the spin rate,
## scaled by the inertia about the grip and capped at `spin_accel`, with gravity about the grip
## cancelled on top, so it holds its rate against a hit and a hit still knocks it. Every time it
## passes through him the contact is billed by him like any swing — the whirl is simply a great
## many swings, as fast as the per-source cooldown lets them land. So each is **glancing**: billed
## at `spin_mult` of the weapon's own multiplier, because a whirl lands seven blows in the time a
## swing lands one and at full weight it would be a knockout a press. A blur follows the far end,
## and the air whooshes every half turn, higher as it goes faster.
##
## Row: `spin_seconds`, `spin_rate`, `spin_accel`, `spin_frequency`, `spin_mult`.

var _t := 0.0
var _dir := 1.0
var _turned := 0.0
var _gravity := 980.0
var _blur: Blur

## For the suites: the fastest it spun, the turns it made and the hits it landed.
var peak_spin := 0.0
var turns := 0.0
var spin_hits := 0

func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func is_spinning() -> bool:
	return _active

func hit_multiplier() -> float:
	return num("spin_mult", 0.6) if _active else 1.0

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(1.0 - _t / maxf(num("spin_seconds", 1.5), 0.01), 0.0, 1.0)

func _on_press() -> void:
	_t = 0.0
	_turned = 0.0
	peak_spin = 0.0
	turns = 0.0
	spin_hits = 0
	# Whichever way it was already turning; from still, away from him first, so it comes round
	# and through him at speed rather than starting pressed into him and grinding there.
	_dir = signf(body.angular_velocity) if absf(body.angular_velocity) > 3.0 else -swing_sign()
	run(true)
	threaten(true)
	if _blur == null:
		_blur = Blur.new()
		_blur.name = "AbilityBlur"
		_blur.top_level = true
		_blur.z_index = -1
		add_child(_blur)
	_blur.visible = Settings.focus_intensity != Settings.Intensity.OFF
	sound(&"whoosh", -8.0, 0.8)
	_update_pip()

func _on_tick(delta: float) -> void:
	_t += delta
	var grip := grip_world()
	var arm := com_world() - grip
	var inertia := pivot_inertia()
	var want := _dir * num("spin_rate", 20.0)
	var w := num("spin_frequency", 10.0)
	var drive := inertia * w * (want - body.angular_velocity)
	var cap := inertia * num("spin_accel", 400.0)
	# The wrist holds it up against gravity as it goes round.
	var torque := -arm.x * body.mass * _gravity * body.gravity_scale
	body.apply_torque(torque + clampf(drive, -cap, cap))
	var spin := absf(body.angular_velocity)
	peak_spin = maxf(peak_spin, spin)
	_turned += spin * delta
	turns += spin * delta / TAU
	if _turned >= PI:
		_turned -= PI
		sound(&"whoosh", -12.0, 0.7 + spin / maxf(num("spin_rate", 20.0), 1.0) * 0.7, 0.08)
	if _blur and _blur.visible:
		_blur.follow(grip, tip_world(), body.angular_velocity, tier_colour())
	if _t >= num("spin_seconds", 1.5):
		finish()

func _on_hit() -> void:
	spin_hits += 1
	payoffs += 1
	if spin_hits == 1:
		paid_off.emit(&"whirl")
	var fx := fx()
	if fx:
		fx.chips(tip_world(), WorldFX.SPARK, 2, 200.0)

func _on_stop() -> void:
	if _blur:
		_blur.visible = false

## The smear behind the far end: the last third of a turn, as a hard-edged arc at the tip's
## radius. Redrawn only while it spins.
class Blur extends Node2D:
	var radius := 0.0
	var from := 0.0
	var sweep := 0.0
	var colour := Color.WHITE

	func follow(grip: Vector2, tip: Vector2, omega: float, tint: Color) -> void:
		global_position = grip.round()
		radius = grip.distance_to(tip)
		var angle := (tip - grip).angle()
		# Behind the tip: against the direction it turns.
		sweep = -signf(omega) * clampf(absf(omega) * 0.05, 0.3, 2.1)
		from = angle
		colour = tint
		queue_redraw()

	func _draw() -> void:
		if radius <= 2.0:
			return
		var steps := maxi(4, int(absf(sweep) * 10.0))
		draw_arc(Vector2.ZERO, radius, from, from + sweep, steps, colour, 3.0, false)
		draw_arc(Vector2.ZERO, radius - 6.0, from, from + sweep * 0.6, steps, Color("f2ead8"), 2.0, false)
