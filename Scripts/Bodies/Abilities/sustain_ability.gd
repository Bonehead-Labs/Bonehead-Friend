class_name SustainAbility
extends WeaponAbility

## Something that runs while right is held (D74): the chainsaw's Rev.
##
## Hold right and the engine catches and climbs (`spin_up` seconds to full revs), for at most
## `fuel_seconds`. While it runs the saw bucks in the hands — a small random kick about the grip
## each tick, `rattle` at full revs — exhaust puffs off the engine, and the picture shakes. Every
## `tick_seconds`, if the bar is on him, **the chain grinds**: `grind_force` at full revs, billed
## through `Buddy.take_impulse` at the saw's own multiplier (the gunshot's path, D7), and the
## same impulse drags him along the bar toward its nose, the way a chain moves; the saw is kicked
## back off him by `kick`. Sparks and bone chips fly from where it bites.
##
## The grind is a hit a tick, so it is priced like one: at the saw's own multiplier a full-rev
## grind is worth a light swing, eight times a second, for as long as the fuel lasts — and the
## cooldown is what it costs. His face holds the `cooking` row while it grinds (`grinding`).
##
## Row: `fuel_seconds`, `spin_up`, `tick_seconds`, `grind_force`, `shove`, `kick`, `rattle`,
## `reach`.

var _rev := 0.0
var _t := 0.0
var _next_tick := 0.0
var _exhaust: GPUParticles2D
var _sprite_rest := Vector2.INF

## For the suites: grinds that landed on him this run, and the revs reached.
var grinds := 0
var peak_rev := 0.0

func revs() -> float:
	return _rev if _active else 0.0

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(1.0 - _t / maxf(num("fuel_seconds", 3.0), 0.01), 0.0, 1.0)

func _on_press() -> void:
	_rev = 0.0
	_t = 0.0
	_next_tick = 0.0
	grinds = 0
	peak_rev = 0.0
	run(true)
	threaten(true)
	# The engine sits behind the grip, which is where the exhaust comes out.
	_exhaust = emitter("exhaust", &"chip", WorldFX.SOOT, 10, body.grip_offset + Vector2(-6, -10),
		Vector2(-20, -60), 40.0, 0.7, Vector2(0, -60))
	emit_from(_exhaust, true)
	sound(&"rev", -8.0, 0.6, 0.0)
	_update_pip()

func _on_release(_seconds: float) -> void:
	finish()

func _on_tick(delta: float) -> void:
	_t += delta
	_rev = minf(1.0, _rev + delta / maxf(num("spin_up", 0.3), 0.01))
	peak_rev = maxf(peak_rev, _rev)
	_shake_sprite()
	# The bar runs hot with the revs (D77): an engine you can see climbing.
	AbilityFX.shine(sprite(), accent(), 0.45 * _rev * (0.8 + 0.2 * sin(_t * 40.0)))
	_next_tick -= delta
	if _next_tick <= 0.0:
		_next_tick = num("tick_seconds", 0.12)
		_engine_tick()
	if _t >= num("fuel_seconds", 3.0):
		# Out of fuel: it coughs and stops.
		var fx := fx()
		if fx:
			fx.puff(com_world(), 6, WorldFX.SOOT, 60.0, 0.8)
		sound(&"rev", -10.0, 0.45, 0.0)
		finish()

func _engine_tick() -> void:
	sound(&"rev", lerpf(-14.0, -6.0, _rev), 0.75 + 0.55 * _rev, 0.03)
	# The engine bucking in the hands.
	var rattle := num("rattle", 60.0) * _rev
	body.apply_torque_impulse(randf_range(-1.0, 1.0) * rattle * body.mass)
	var him := buddy()
	if him == null:
		return
	var grip := grip_world()
	var tip := tip_world()
	var bar := tip - grip
	if bar.length_squared() < 1.0:
		return
	var along := bar.normalized()
	# Where the chain meets him: the point on the bar nearest his middle.
	var middle := him.get_interaction_rect().get_center()
	var t := clampf((middle - grip).dot(along) / bar.length(), 0.0, 1.0)
	var bite := grip + bar * t
	var touching := body.get_colliding_bodies().has(him) or touches_him(bite, num("reach", 6.0))
	if not touching or _rev < 0.6:
		return
	grinds += 1
	# The chain bites: it drags him along the bar toward the nose and onto the bar, so a saw held on
	# him stays on him — a shove straight along the bar threw him off it inside a second.
	var onto := (bite - middle).normalized() if bite.distance_squared_to(middle) > 1.0 else Vector2.ZERO
	strike(num("grind_force", 450.0), (along + onto).normalized(), bite, 1.0, num("shove", 0.35))
	body.apply_central_impulse((grip - middle).normalized() * body.mass * num("kick", 40.0))
	var fx := fx()
	if fx:
		fx.chips(bite, WorldFX.SPARK, 3, 260.0)
		fx.chips(bite, Color("f2ead8"), 2, 180.0)
		if grinds % 3 == 1:
			fx.shake(2.0)
	sound(&"scratch", -10.0, 1.6, 0.1)
	tell(&"grinding", bite)
	paid_off.emit(&"grind")

## The picture shakes with the engine; the body's own buck is the rattle above.
func _shake_sprite() -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_rest == Vector2.INF:
		_sprite_rest = s.position
	var amp := (0.5 + 1.0 * _rev) * Settings.intensity_scale()
	s.position = _sprite_rest + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)).round()

func _on_stop() -> void:
	emit_from(_exhaust, false)
	var s := sprite()
	if s and _sprite_rest != Vector2.INF:
		s.position = _sprite_rest
	_sprite_rest = Vector2.INF
	_rev = 0.0
	AbilityFX.shine(s, accent(), 0.0)
