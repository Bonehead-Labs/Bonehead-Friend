class_name LevitationPower
extends SpellPower

## Levitation (D72): hold the button on him and he floats up off the desk, sways a little on
## nothing, and after a moment falls asleep up there. Let go and he drifts back down — slowly
## enough that the landing is a touch and never a fall.
##
## The lift is a kind act (`kindness_given`): it starts a combo, ticks the contracts, and is the
## player arriving as far as his idle brain is concerned. Every second he spends aloft is paid as
## a rate (`kindness_sustained`), outside the combo like every trickle. Nothing he does up there
## can hurt him: the descent is held under `sink_speed`, and at 120 px/s a 3 kg skeleton touches
## down with 360 of impulse, a quarter of the world's 1,500 fall floor.
##
## Two tree nodes and no third. A lift has no rate to shorten and no weight that matters; like
## the sponge and the hot tub, an invented third lever would be a price for a number nobody can
## feel.

@export var z_texture: Texture2D
## The lift, as a kind act.
@export var lift_value: float = 4.0
## Kindness per second aloft, paid every `flush_seconds`.
@export var float_rate: float = 3.0
@export var flush_seconds: float = 0.5
## How far above where he was he floats, and how fast he gets there.
@export var lift_height: float = 130.0
@export var rise_speed: float = 120.0
## The fastest he comes down once let go.
@export var sink_speed: float = 120.0
## How far he drifts either side while he floats.
@export var sway: float = 10.0
## Seconds aloft before he nods off.
@export var doze_after: float = 1.2
## The longest a descent is steered before he is simply let go.
@export var sink_limit: float = 4.0
@export var reach_padding: float = 20.0

const RESTING := 0
const FLOATING := 1
const SINKING := 2

var _phase := RESTING
var _anchor := Vector2.ZERO
var _started_msec := 0
var _next_flush_msec := 0
var _cushion: GPUParticles2D
var _zs: GPUParticles2D

func is_live() -> bool:
	return _phase != RESTING

func is_floating() -> bool:
	return _phase == FLOATING

func can_fire_at(at: Vector2) -> bool:
	return _phase != FLOATING and _reachable(_buddy()) and _on_him(at, reach_padding)

func fire(at: Vector2) -> void:
	var buddy := _buddy()
	if buddy == null:
		return
	_held = true
	_build()
	_phase = FLOATING
	_anchor = buddy.global_position
	var now := Time.get_ticks_msec()
	_started_msec = now
	_next_flush_msec = now + int(flush_seconds * 1000.0)
	EventBus.kindness_given.emit(item_id, lift_value * effective_damage_mult(), at)
	_notice_player()
	var fx := _fx()
	if fx:
		var feet := _feet(buddy)
		fx.ring(feet, 44.0, AIR, 0.35, 2.0)
		fx.puff(feet, 6, AIR, 50.0, 0.7)
	AudioManager.play(&"float", 0.04, -8.0)
	_face(&"levitating")
	_use()
	_place(buddy)
	_emitting(_cushion, true)
	set_physics_process(true)
	_update_input()

func _released(_at: Vector2) -> void:
	_sink()

func _spell_deactivated(_was_held: bool) -> void:
	_sink()

func _sink() -> void:
	if _phase != FLOATING:
		return
	_phase = SINKING
	_started_msec = Time.get_ticks_msec()
	_emitting(_zs, false)

func _stop() -> void:
	_phase = RESTING
	_emitting(_cushion, false)
	_emitting(_zs, false)
	set_physics_process(false)
	_update_input()

func _physics_process(delta: float) -> void:
	var buddy := _buddy()
	if _phase == RESTING or not _reachable(buddy) or buddy.freeze:
		_stop()
		return
	var now := Time.get_ticks_msec()
	var aloft := float(now - _started_msec) / 1000.0
	if _phase == FLOATING:
		var target := _anchor + Vector2(sin(aloft * 0.9) * sway, -lift_height)
		var want := ((target - buddy.global_position) * 2.5).limit_length(rise_speed * 1.5)
		_steer(buddy, want, 900.0, delta)
		_upright(buddy)
		if aloft >= doze_after and _zs and not _zs.emitting:
			_emitting(_zs, true)
		if now >= _next_flush_msec:
			_next_flush_msec += int(flush_seconds * 1000.0)
			EventBus.kindness_sustained.emit(item_id,
				float_rate * flush_seconds * effective_damage_mult(), buddy.global_position)
			var fx := _fx()
			if fx:
				fx.ring(_feet(buddy), 34.0, AIR, 0.45, 2.0)
			_face(&"levitating")
			_notice_player()
	else:
		if buddy.is_grounded() or aloft >= sink_limit:
			_stop()
			return
		# Down no faster than `sink_speed`: gravity is paid for only as far as it would take him
		# past it, so the step ends at exactly that speed and not a pixel a second more.
		var v := buddy.linear_velocity
		var dv := Vector2(-v.x * 0.1, 0.0)
		var falling := v.y + _gravity(buddy).y * delta
		if falling > sink_speed:
			dv.y = sink_speed - falling
		buddy.apply_central_impulse(dv * buddy.mass)
		_upright(buddy)
	_place(buddy)

func _place(buddy: Buddy) -> void:
	if _cushion:
		_cushion.global_position = _feet(buddy)
	if _zs:
		var rect := buddy.get_interaction_rect()
		_zs.global_position = Vector2(rect.get_center().x + 14.0, rect.position.y + 4.0)

func _feet(buddy: Buddy) -> Vector2:
	var rect := buddy.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.end.y)

func _build() -> void:
	if _cushion != null:
		return
	var tier := _tier()
	# An updraft under his feet: pale chips drifting up past him, the air he is lying on.
	_cushion = _emitter("Updraft", _chip(), AIR.lerp(Color("7fe3df"), 0.45 + 0.1 * float(tier)),
		16 + 3 * tier, 1.0, -60.0, 50.0, Vector2(26, 3), 1.5, 2.5)
	# And sleep, once he has dozed off: slow Zs rising off his head.
	_zs = _emitter("Sleep", z_texture, Color.WHITE, 3, 1.8, -30.0, 24.0, Vector2(3, 2), 1.6, 2.2)
