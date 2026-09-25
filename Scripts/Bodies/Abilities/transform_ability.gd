class_name TransformAbility
extends WeaponAbility

## The weapon becomes something else for a while (D74): the mace's Lead Heart, the energy sabre's
## Ignite.
##
## Tap right and for `seconds` it changes. What changes is the row's, and each is a different way
## of being the same weapon:
##
## - **Its weight.** `mass_mult` times as heavy. The drag joint lags a heavier body, so it is slower
##   to bring round and hands him more momentum when it arrives — the physics, not a number. The
##   weight is the body's own `mass`, restored through `apply_augments` so a Weight node bought
##   meanwhile is honoured.
## - **Every blow.** Each contact it lands on him is billed at `hit_mult` on top of its own
##   multiplier (he reads `hit_multiplier` when he attributes it, as he reads a charged bat's), and
##   the desk jolts under him: `quake` px of shake, dust off the floor at his feet.
## - **What it is made of.** With `phase`, he and it do not collide: it passes through him. Every
##   `burn_seconds` it spends *inside* him — added up across passes, so a slow draw and three quick
##   ones pay alike — it burns him once: `burn_force`, billed through `Buddy.take_impulse` at
##   `burn_mult` (D7), hopping him up by `shove` of it, from the tick before `StepStart` (D64). The
##   part of the blade inside him glows where it went.
##
## While it lasts the sprite wears a light of `tint` (an additive copy of itself, so it glows rather
## than darkens) over its own picture multiplied by `shade` — a blue-grey head only glows red once
## it has been made red; added alone, red on blue-grey is purple — beating every `pulse` seconds if
## the row has one, and chips of `embers` come off
## it at `ember_at` of the way from the hand to the far end, falling at `ember_gravity`. A voice
## rises when it changes (`sound_on`) and another repeats every `hum_seconds` while it lasts
## (`hum`). It stays changed out of the hand: a lit blade thrown through him still burns him.
##
## When its time is up with the blade still inside him the exception stays until it is clear of
## him, or a second has passed (D61: a body let go of inside him is thrown out of him).
##
## Row: `seconds`, `mass_mult`, `hit_mult`, `quake`, `phase`, `burn_seconds`, `burn_force`,
## `burn_mult`, `shove`, `tint`, `shade`, `glow`, `pulse`, `embers`, `ember_at`, `ember_gravity`,
## `sound_on`, `sound_off`, `hum`, `hum_seconds`, `tell`.

const ON := 0
const SETTLE := 1

var _phase := ON
var _t := 0.0
var _settle_t := 0.0
var _mass_before := 0.0
var _excepted: Buddy
var _inside_acc := 0.0
var _was_inside := false
var _hum_clock := 0.0
var _beat_clock := 0.0
var _quake_pending := false
var _light: Sprite2D
var _shade_was := Color.WHITE
var _shaded := false
var _embers: GPUParticles2D

## For the suites: blows landed while changed, burns dealt, seconds spent inside him, and the mass
## it reached.
var blows := 0
var burns := 0
var inside_seconds := 0.0
var peak_mass := 0.0

func is_changed() -> bool:
	return _active and _phase == ON

func is_settling() -> bool:
	return _active and _phase == SETTLE

## Whether it goes through him right now.
func is_phased() -> bool:
	return _active and bool(row.get("phase", false))

func time_left() -> float:
	return maxf(num("seconds", 4.0) - _t, 0.0) if is_changed() else 0.0

func hit_multiplier() -> float:
	return num("hit_mult", 1.0) if is_changed() else 1.0

func pip_fill() -> float:
	if not is_changed():
		return -1.0
	return clampf(1.0 - _t / maxf(num("seconds", 4.0), 0.01), 0.0, 1.0)

func _on_press() -> void:
	_phase = ON
	_t = 0.0
	_inside_acc = 0.0
	_was_inside = false
	_hum_clock = num("hum_seconds", 0.0)
	_beat_clock = 0.0
	_quake_pending = false
	blows = 0
	burns = 0
	inside_seconds = 0.0
	_mass_before = body.mass
	var weight := num("mass_mult", 1.0)
	if not is_equal_approx(weight, 1.0):
		body.mass = _mass_before * weight
	peak_mass = body.mass
	if bool(row.get("phase", false)):
		var him := buddy()
		if him:
			body.add_collision_exception_with(him)
			_excepted = him
	run(true)
	threaten(true)
	_light_up(true)
	if String(row.get("embers", "")) != "":
		_embers = _ember_emitter(Color(String(row["embers"])))
		emit_from(_embers, true)
	var fx := fx()
	if fx:
		fx.ring(_along(num("ember_at", 0.8)), 30.0, _tint(), 0.25, 3.0)
	var on_sound := StringName(row.get("sound_on", &""))
	if on_sound != &"":
		sound(on_sound, -4.0, 1.0, 0.0)
	_update_pip()

## Nothing to release: it is a tap.
func _on_release(_seconds: float) -> void:
	pass

## Out of the hand it stays what it became until its time is up.
func _on_dropped() -> void:
	pass

func _on_hit() -> void:
	# He is attributing the hit inside his `_integrate_forces`: record it, act on the next tick.
	if is_changed():
		blows += 1
		_quake_pending = true

func _on_tick(delta: float) -> void:
	if _phase == SETTLE:
		_settle_t += delta
		if not overlaps_him() or _settle_t >= 1.0:
			finish()
		return
	_t += delta
	_beat(delta)
	if _quake_pending:
		_quake_pending = false
		_quake()
	if bool(row.get("phase", false)):
		_burn(delta)
	if _t >= num("seconds", 4.0):
		_go_out()

## The time is up: the light goes out, and the weight comes off. A blade still in him keeps its
## exception until it is clear.
func _go_out() -> void:
	_light_up(false)
	emit_from(_embers, false)
	_restore_mass()
	var off_sound := StringName(row.get("sound_off", &""))
	if off_sound != &"":
		sound(off_sound, -8.0, 1.0, 0.0)
	if _excepted and overlaps_him():
		_phase = SETTLE
		_settle_t = 0.0
		_update_pip()
		return
	finish()

## The light, the heartbeat and the hum.
func _beat(delta: float) -> void:
	var hum := StringName(row.get("hum", &""))
	var every := num("hum_seconds", 0.0)
	if hum != &"" and every > 0.0:
		_hum_clock -= delta
		if _hum_clock <= 0.0:
			_hum_clock = every
			sound(hum, -12.0, 1.0, 0.04)
	if _light == null:
		return
	var glow := num("glow", 0.6)
	var pulse := num("pulse", 0.0)
	var moving := Settings.focus_intensity != Settings.Intensity.OFF
	if pulse > 0.0:
		_beat_clock -= delta
		if _beat_clock <= 0.0:
			_beat_clock = pulse
			var fx := fx()
			if fx:
				fx.ring(_along(num("ember_at", 0.8)), 22.0, _tint(), 0.3, 2.0)
		# Lub-dub: two swells, the second smaller, a fifth of a beat apart, then rest.
		var k := 1.0 - _beat_clock / pulse
		var lub := exp(-pow((k - 0.08) / 0.07, 2.0))
		var dub := 0.6 * exp(-pow((k - 0.28) / 0.07, 2.0))
		var swell := (lub + dub) if moving else 0.5
		_light.modulate = Color(_tint(), glow * (0.45 + 0.55 * swell))
	else:
		var flicker := (0.85 + 0.15 * sin(_t * 31.0)) if moving else 1.0
		_light.modulate = Color(_tint(), glow * flicker)

## A blow landed while it was heavy: the desk jolts under him.
func _quake() -> void:
	var him := buddy()
	var at := him_world()
	if him:
		var rect := him.get_interaction_rect()
		at = Vector2(rect.get_center().x, rect.end.y)
	var fx := fx()
	if fx:
		fx.shake(num("quake", 6.0))
		fx.ring(at, 90.0, WorldFX.DUST, 0.3, 3.0)
		fx.puff(at, 8, WorldFX.DUST, 110.0, 0.6)
		fx.chips(at, _tint(), 4, 220.0)
	sound(&"impact_metal", -4.0, 0.45)
	sound(&"quake", -10.0, 1.4, 0.05)
	payoffs += 1
	_say(him_world())
	paid_off.emit(ability_id())

## Inside him: the part of the blade that is in him glows, and every `burn_seconds` of it he burns.
func _burn(delta: float) -> void:
	var him := buddy()
	if him == null:
		return
	var inside := overlaps_him()
	var grip := grip_world()
	var tip := tip_world()
	var cut := _clip(grip, tip, him.get_interaction_rect())
	if not inside or cut.is_empty():
		_was_inside = false
		return
	inside_seconds += delta
	_inside_acc += delta
	var mid: Vector2 = (cut[0] + cut[1]) * 0.5
	var fx := fx()
	if fx:
		# Where it is in him, drawn: a glowing cut that follows the blade and cools behind it.
		fx.tracer(cut[0], cut[1], WorldFX.HEAT, 0.25, 3.0)
		if not _was_inside:
			fx.chips(mid, WorldFX.SPARK, 4, 200.0)
	if not _was_inside:
		sound(&"sizzle", -12.0, 1.3, 0.1)
	_was_inside = true
	var every := maxf(num("burn_seconds", 0.2), 0.05)
	while _inside_acc >= every:
		_inside_acc -= every
		burns += 1
		strike(num("burn_force", 700.0), Vector2.UP, mid, num("burn_mult", 1.0), num("shove", 0.3))
		if fx:
			fx.heat(mid, body.juice_tier)
			fx.puff(mid, 3, WorldFX.SOOT, 50.0, 0.6)
		sound(&"sizzle", -6.0, randf_range(0.9, 1.15), 0.0)
		_say(mid)
		paid_off.emit(ability_id())

## The part of a segment inside a rect, as its two ends, or empty.
func _clip(a: Vector2, b: Vector2, rect: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(d[axis]) < 0.0001:
			if a[axis] < lo or a[axis] > hi:
				return []
			continue
		var ta := (lo - a[axis]) / d[axis]
		var tb := (hi - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return []
	return [a + d * t0, a + d * t1]

## His face, for the row's `tell`: a blow while heavy, a burn while lit.
func _say(at: Vector2) -> void:
	var event := StringName(row.get("tell", &""))
	if event != &"":
		tell(event, at)

func _on_stop() -> void:
	_light_up(false)
	emit_from(_embers, false)
	_restore_mass()
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null

func _restore_mass() -> void:
	if body == null or _mass_before <= 0.0:
		return
	body.mass = _mass_before
	# The Weight augment's mass, if one was bought while it was heavy.
	body.apply_augments()
	_mass_before = 0.0

func _tint() -> Color:
	return Color(String(row.get("tint", "ffffff")))

## A point `k` of the way from the hand to the far end, in the world.
func _along(k: float) -> Vector2:
	return grip_world().lerp(tip_world(), clampf(k, 0.0, 1.0))

## The light it wears: a copy of its own sprite, drawn additively in the tint, so it glows rather
## than darkens. A child of the sprite, so it turns and flips with it. Kept once built.
func _light_up(on: bool) -> void:
	var s := sprite()
	if s == null:
		return
	if _light == null and on:
		_light = Sprite2D.new()
		_light.name = "AbilityLight"
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_light.material = add
		s.add_child(_light)
	var shade := String(row.get("shade", ""))
	if on and shade != "" and not _shaded:
		_shade_was = s.self_modulate
		s.self_modulate = Color(shade)
		_shaded = true
	elif not on and _shaded:
		s.self_modulate = _shade_was
		_shaded = false
	if _light == null:
		return
	if on:
		_light.texture = s.texture
		_light.centered = s.centered
		_light.offset = s.offset
		_light.flip_h = s.flip_h
		_light.flip_v = s.flip_v
		_light.region_enabled = s.region_enabled
		_light.region_rect = s.region_rect
		_light.hframes = s.hframes
		_light.vframes = s.vframes
		_light.frame = s.frame
		_light.modulate = Color(_tint(), num("glow", 0.6))
	_light.visible = on

## Chips coming off it: sparks off a blade, drips off a head. Along the weapon's length at
## `ember_at`, spread a little across it.
func _ember_emitter(colour: Color) -> GPUParticles2D:
	var at := body.grip_offset.lerp(body._find_tip(), clampf(num("ember_at", 0.8), 0.0, 1.0))
	var fall := num("ember_gravity", -60.0)
	return emitter("embers", &"chip", colour, 10, at, Vector2(0, -30 if fall < 0.0 else 20), 180.0, 0.6,
		Vector2(0, fall))
