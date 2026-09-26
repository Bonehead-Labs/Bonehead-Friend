class_name WringAbility
extends SustainAbility

## The sponge's Wring (docs/decisions.md D78): hold right with it over him and it is squeezed, and
## clean water rains down on him and takes the grime with it.
##
## A sustain, like the duster's tickle and the chainsaw's rev: hold, and it runs for at most
## `fuel_seconds`. The sponge is squeezed in the hand — its picture squashes flat and bulges, `squeeze`
## of its height — and every `tick_seconds` a drop leaves its underside and falls. The drops are
## `AbilityShot`s (D74's spikes and staples, here a drop of water): they collide with the world and
## nothing else and sweep for him, so every drop that lands on him is counted once. Each one that does
## **takes `clean` of grime off him**, and that grime pays exactly as the sponge's own scrubbing pays
## for it (`hearts_per_grime_cleaned`, banked as a rate) — grime is finite, so a wring is quicker,
## never richer. The first drop on him is a **rinse**, one small act (`rinse_value`), the only value
## the wring adds of its own, and he stands blissful under the shower; when it stops he shakes
## himself dry like a dog.
##
## A clean skeleton still gets his rinse and his shake, and the sponge's grime pays nothing, as it
## never has for scrubbing a clean skeleton.
##
## Row: `fuel_seconds`, `spin_up`, `tick_seconds`, `clean`, `rinse_value`, `squeeze`.

var _shots: Array[WeakRef] = []
var _sprite_scale := Vector2.INF
var _rinsed := false
var _wet := false
var _next_tell := 0.0
var _last_drip := 0
var _sparkled := false
## Grime paid for is banked and flushed on FriendlyBase's cadence: a number a drop would be ten a
## second over his face.
var _banked := 0.0
var _bank_at := Vector2.ZERO
var _since_flush := 0.0
var _wringing := false
var _drain_t := 0.0

## For the suites: drops wrung out, drops that landed on him, and the grime they took.
var drops := 0
var landed := 0
var cleaned := 0.0

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot):
			shot.queue_free()
	_shots.clear()

func pip_fill() -> float:
	if not _active or not _wringing:
		return -1.0
	return clampf(1.0 - _t / maxf(num("fuel_seconds", 2.0), 0.01), 0.0, 1.0)

func is_raining() -> bool:
	return _active and _wringing

func _on_press() -> void:
	_rev = 0.0
	_t = 0.0
	_next_tick = 0.0
	_next_tell = 0.0
	_rinsed = false
	_wringing = true
	_drain_t = 0.0
	_sparkled = false
	_last_drip = 0
	_wet = false
	drops = 0
	landed = 0
	cleaned = 0.0
	grinds = 0
	peak_rev = 0.0
	run(true)
	sound(&"slosh", -6.0, 1.3)
	AbilityCues.activation(self, com_world())
	AbilityCues.state(self, true, com_world())
	_update_pip()

func _on_tick(delta: float) -> void:
	_t += delta
	_next_tell -= delta
	_since_flush += delta
	if _since_flush >= FriendlyBase.FLUSH_SECONDS:
		_flush()
	if not _wringing:
		# Let go: the last drops are still falling, and the shower is over when they are down.
		_drain_t += delta
		if _drops_alive() == 0 or _drain_t >= 1.5:
			finish()
		return
	_rev = minf(1.0, _rev + delta / maxf(num("spin_up", 0.2), 0.01))
	peak_rev = maxf(peak_rev, _rev)
	_squeeze_sprite()
	_next_tick -= delta
	if _next_tick <= 0.0:
		_next_tick = num("tick_seconds", 0.08)
		_engine_tick()
	if _t >= num("fuel_seconds", 2.0):
		_stop_wringing()

## Let go of, or wrung dry: the sponge is itself again, and the drops in the air finish falling.
func _stop_wringing() -> void:
	if not _wringing:
		return
	_wringing = false
	_drain_t = 0.0
	_restore_sprite()
	_update_pip()

func _on_release(_seconds: float) -> void:
	_stop_wringing()

func _on_dropped() -> void:
	_stop_wringing()

## The focus went with right held (D70): the squeeze lets go; the drops in the air still fall.
func _on_focus_lost() -> bool:
	_stop_wringing()
	return true

func _drops_alive() -> int:
	var n := 0
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot) and not shot.is_queued_for_deletion():
			n += 1
	return n

## The grime the drops took, paid as the sponge pays for it: the sponge's own rule, delivered.
func _flush() -> void:
	_since_flush = 0.0
	if _banked <= 0.0:
		return
	give_sustained(_banked, _bank_at, _banked)
	_banked = 0.0

## One drop out of the underside, a little either side of the middle.
func _engine_tick() -> void:
	if _rev < 0.3:
		return
	var rect := body.get_interaction_rect()
	var half := rect.size * 0.5
	var from := com_world() + Vector2(randf_range(-half.x, half.x) * 0.6, half.y * 0.6)
	var host := body.get_parent() if body.get_parent() else body
	var shot := AbilityShot.new()
	shot.name = "Drop"
	shot.look = AbilityShot.WATER
	shot.ability = weakref(self)
	shot.force = 0.0
	shot.mult = 0.0
	shot.shove = 0.0
	shot.slot = drops
	shot.mass = 0.02
	shot.lifetime = 1.6
	shot.after_hit = AbilityShot.SPLAT
	shot.after_world = AbilityShot.SPLAT
	host.add_child(shot)
	shot.global_position = from
	# Out of a squeezed sponge, not thrown: a little of the hand's own motion and a lot of gravity.
	shot.linear_velocity = body.linear_velocity * 0.3 + Vector2(randf_range(-25.0, 25.0), 90.0)
	_shots.append(weakref(shot))
	drops += 1
	if drops - _last_drip >= 3:
		_last_drip = drops
		sound(&"drip", -12.0, randf_range(0.9, 1.3), 0.1)

## A drop on him: grime off, paid as the sponge pays for it, and the first one is the rinse.
func shot_hit(_shot: AbilityShot, him: Buddy, at: Vector2, _heading: Vector2) -> void:
	if him == null or body == null:
		return
	landed += 1
	_wet = true
	if him.grime:
		var removed := him.grime.clean(num("clean", 0.03))
		if removed > 0.0:
			cleaned += removed
			_banked += removed * ItemDB.balance.hearts_per_grime_cleaned
			_bank_at = at
			if not _active:
				_flush()
	if not _rinsed:
		_rinsed = true
		give(num("rinse_value", 2.0), at)
		notice_player()
		AbilityCues.payoff(self, &"wring", at, "rinse!")
	var fx := fx()
	if fx:
		fx.chips(at, AbilityShot.WATER_DEEP, 2, 110.0)
		if not _sparkled and _all_clean(him):
			_sparkled = true
			fx.burst(him.get_interaction_rect().get_center(), &"star", WorldFX.GOLD, 3, 120.0, 0.6)
	if _next_tell <= 0.0:
		_next_tell = 0.35
		tell(&"showered", him.get_interaction_rect().get_center())

func _all_clean(him: Buddy) -> bool:
	return him.grime != null and him.grime.value <= 0.0001 and cleaned > 0.0

func shot_landed(_shot: AbilityShot, at: Vector2) -> void:
	var fx := fx()
	if fx:
		fx.chips(at, AbilityShot.WATER_LIGHT, 2, 80.0)

## Squeezed: flatter and wider in the hand as it wrings, pulsing with each drop. The picture only.
func _squeeze_sprite() -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_scale == Vector2.INF:
		_sprite_scale = s.scale
	var k := num("squeeze", 0.25) * _rev * Settings.intensity_scale()
	var pulse := 0.5 + 0.5 * sin(_t * TAU * 6.0)
	s.scale = _sprite_scale * Vector2(1.0 + k * (0.5 + 0.3 * pulse), 1.0 - k * (0.8 + 0.2 * pulse))

func _restore_sprite() -> void:
	var s := sprite()
	if s and _sprite_scale != Vector2.INF:
		s.scale = _sprite_scale
	_sprite_scale = Vector2.INF

func _on_stop() -> void:
	_wringing = false
	_restore_sprite()
	_flush()
	var alive: Array[WeakRef] = []
	for ref in _shots:
		if ref.get_ref() != null:
			alive.append(ref)
	_shots = alive
	super._on_stop()
	AbilityCues.state(self, false, com_world())
	# Wet through: he shakes himself dry.
	var him := buddy()
	if _wet and him:
		var at := him.get_interaction_rect().get_center()
		var fx := fx()
		if fx:
			fx.chips(at + Vector2(-20, -10), AbilityShot.WATER_LIGHT, 4, 200.0)
			fx.chips(at + Vector2(20, -10), AbilityShot.WATER_DEEP, 4, 200.0)
		sound(&"rattle", -12.0, 1.4)
		tell(&"shake_dry", at)
	_wet = false
