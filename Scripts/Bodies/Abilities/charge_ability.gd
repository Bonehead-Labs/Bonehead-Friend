class_name ChargeAbility
extends WeaponAbility

## Hold to wind up, let go to swing (D74): the baseball bat's Home Run.
##
## **Winding up** is a torque about the grip that lays the head back over the shoulder, away from
## him, and holds it there against gravity — the held gun's PD, scaled by the inertia about the
## grip so it feels the same on a light bat and a heavy one (D56). The charge fills over
## `charge_seconds`; sparks gather at the barrel, a ratchet climbs, and he sees it coming (the
## `windup` threat). **Letting go** whips the head round toward him (`whip`, rad/s at a full
## charge) and arms the next hit for `window` seconds.
##
## **The armed hit** is billed at the weapon's own multiplier times up to `hit_mult`, by charge —
## he reads `hit_multiplier` when he attributes the contact, as he reads the damage augment. It
## also throws him: `launch` px/s, `launch_degrees` above level, away from the hand. The throw is
## applied on the physics tick after the hit, before `Buddy.StepStart` reads the step, so his
## ledger never bills it as a second contact (D64). Where he comes down is billed to the bat for
## `claim_seconds` (`Buddy.claim_impacts`, D65) — only who is billed changes, never whether.
##
## Row: `charge_seconds`, `min_charge`, `hit_mult`, `window`, `whip`, `cock_degrees`,
## `cock_frequency`, `cock_accel`, `launch`, `launch_degrees`, `claim_seconds`.

const WINDING := 0
const ARMED := 1

var _phase := WINDING
var _charge := 0.0
var _armed_left := 0.0
var _landed := false
var _next_click := 0.0
var _full := false
var _sparks: GPUParticles2D
var _sprite_rest := Vector2.INF
var _gravity := 980.0

## What the last armed hit was billed at, and how hard it threw him — for the suites.
var last_launch := 0.0

func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func charge() -> float:
	return _charge

func is_armed() -> bool:
	return _active and _phase == ARMED and not _landed

func hit_multiplier() -> float:
	if _active and _phase == ARMED:
		return 1.0 + (num("hit_mult", 2.0) - 1.0) * _charge
	return 1.0

func pip_fill() -> float:
	return _charge if _active and _phase == WINDING else -1.0

func _on_press() -> void:
	_phase = WINDING
	_charge = 0.0
	_landed = false
	_full = false
	_next_click = 0.0
	run(true)
	threaten(true)
	_sparks = emitter("charge", &"chip", tier_colour(), 12, body._find_tip(), Vector2(0, -50), 180.0, 0.35)
	emit_from(_sparks, true)
	sound(&"whoosh", -18.0, 0.6)
	_update_pip()

func _on_tick(delta: float) -> void:
	if _phase == WINDING:
		_charge = minf(1.0, _charge + delta / maxf(num("charge_seconds", 0.9), 0.05))
		_cock()
		_tremble()
		_next_click -= delta
		if _next_click <= 0.0 and not _full:
			# A ratchet that climbs with the charge, so the ear can time the release.
			sound(&"ratchet", -14.0, 0.7 + 0.9 * _charge, 0.0)
			_next_click = 0.11
		if _charge >= 1.0 and not _full:
			_full = true
			sound(&"plink", -8.0, 1.25)
			var fx := fx()
			if fx:
				fx.ring(tip_world(), 26.0, Color.WHITE, 0.18, 2.0)
		return
	if _landed:
		_land()
		return
	_armed_left -= delta
	if _armed_left <= 0.0:
		# The swing met nothing: the charge is spent all the same.
		var fx := fx()
		if fx:
			fx.puff(tip_world(), 4, WorldFX.DUST, 40.0, 0.4)
		finish()

func _on_release(_seconds: float) -> void:
	if _phase != WINDING:
		return
	_charge = maxf(num("min_charge", 0.25), _charge)
	_phase = ARMED
	_armed_left = num("window", 0.8)
	_rest_sprite()
	emit_from(_sparks, false)
	threaten(false)
	whip(swing_sign() * num("whip", 12.0) * _charge)
	sound(&"whoosh", lerpf(-12.0, -4.0, _charge), lerpf(1.3, 0.85, _charge))
	_update_pip()

func _on_hit() -> void:
	if _phase == ARMED:
		_landed = true

## Letting go of the bat mid-wind-up spends half a cooldown; letting go of it armed keeps the
## hit armed — a charged bat thrown at him is still a charged bat.
func _on_dropped() -> void:
	if _phase == WINDING:
		finish(num("cooldown", 5.0) * 0.5)

func _on_stop() -> void:
	_rest_sprite()
	emit_from(_sparks, false)

## The hit landed on the tick before this one: throw him, claim where he comes down, and make it
## look and sound like it.
func _land() -> void:
	var him := buddy()
	var at := tip_world()
	if him:
		var side := signf(him.global_position.x - grip_world().x)
		if side == 0.0:
			side = 1.0
		var up := deg_to_rad(num("launch_degrees", 38.0))
		var dir := Vector2(side, 0.0).rotated(-side * up)
		last_launch = num("launch", 850.0) * _charge
		# Through his centre of mass (D54), and from this tick, before StepStart (D64).
		him.apply_central_impulse(dir * him.mass * last_launch)
		him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 2.0))
		at = him.get_interaction_rect().get_center()
	payoffs += 1
	var fx := fx()
	if fx:
		fx.ring(at, 70.0 + 50.0 * _charge, WorldFX.GOLD, 0.35, 4.0)
		fx.burst(at, &"star", WorldFX.GOLD, 4 + int(5.0 * _charge), 320.0)
		fx.chips(at, Color.WHITE, 6, 260.0)
		fx.shake(4.0 + 5.0 * _charge)
	sound(&"crack", -2.0, lerpf(1.15, 0.9, _charge))
	tell(&"home_run", at)
	paid_off.emit(&"home_run")
	finish()

## Lays the head back over the shoulder, away from him, and holds it there.
func _cock() -> void:
	var him := him_world()
	var grip := grip_world()
	var com := com_world()
	var arm := com - grip
	if arm.length_squared() < 1.0:
		return
	var away := Vector2.LEFT
	if him != Vector2.INF:
		away = (grip - him)
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 1.0 else Vector2.LEFT
	# Up and back: the away direction turned toward straight up by `cock_degrees`.
	var target := away.rotated(-signf(away.x) * deg_to_rad(num("cock_degrees", 50.0)))
	var err := wrapf(target.angle() - arm.angle(), -PI, PI)
	var inertia := pivot_inertia()
	var w := num("cock_frequency", 14.0)
	var pd := inertia * (w * w * err - 2.0 * 0.8 * w * body.angular_velocity)
	var cap := inertia * num("cock_accel", 260.0)
	# The hand holding it up against gravity, as a held gun's does (D56).
	var torque := -arm.x * body.mass * _gravity * body.gravity_scale
	body.apply_torque(torque + clampf(pd, -cap, cap))

## The bat shakes in the hands as the charge builds: the sprite, not the body, so the physics of
## the wind-up is exactly the torque above.
func _tremble() -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_rest == Vector2.INF:
		_sprite_rest = s.position
	var amp := 1.5 * _charge * Settings.intensity_scale()
	s.position = _sprite_rest + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)).round()

func _rest_sprite() -> void:
	var s := sprite()
	if s and _sprite_rest != Vector2.INF:
		s.position = _sprite_rest
	_sprite_rest = Vector2.INF
