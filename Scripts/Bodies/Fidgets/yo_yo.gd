class_name YoYo
extends WeaponBase

## A yo-yo (D66). A weapon, filed under Melee and bought with Bones: it is a lump of wood on a
## string, and the game is swinging it into him.
##
## - **Left holds the finger loop.** In the hand it is a small hard thing like any other.
## - **Right throws it out on its string.** The string pays out to its length and the yo-yo hangs
##   off the hand on it, a pendulum you swing by moving the mouse — so it goes where the hand
##   sends it, and a swing through him bonks him.
## - **Keep right held and it sleeps** at the end of the string, spinning. **Let go and it climbs
##   back** into the hand.
## - **A trick** — sleep it for `trick_seconds`, then bring it back — makes the next bonk inside
##   `trick_window` a trick shot, at `trick_mult` its damage. Bones are only ever minted from
##   damage (one pipeline), so a trick pays by making the hit that follows it count for more.
## - **He watches it sleep** and is impressed by a trick; the bonk is the ordinary hurt.
##
## **A bonk on the string bills itself.** D59's F1: a contact that parts inside one physics
## step is never seen by the solver's impulse, and a yo-yo on a string bouncing off him is
## exactly that. So while it is out, the yo-yo measures its own approach speed at the moment it
## touches him and bills the collision's impulse — `(1 + e) x reduced mass x approach` —
## through `Buddy.take_impulse`, the path a gunshot takes; and his contact path bills it at
## zero in the meantime (`effective_damage_mult`), so it is never billed twice. In the hand or
## loose on the desk it is an ordinary weapon and his contact path bills it as one.
##
## The string is a rope, not a joint: in `_integrate_forces` the body is held within
## `_length` of the hand and only the outward part of its velocity is removed — taut, it pulls;
## slack, it does nothing. Written there and only when taut, where the state is the current
## one, never a copy from the last step (D56).

@export var gestures: GestureZones
## The loose end of the string with its finger loop, shown while it is not out.
@export var tail: Sprite2D
## The string's full length, world px, and how fast it pays out and winds back in.
@export var string_length: float = 170.0
@export var throw_speed: float = 900.0
@export var return_speed: float = 1000.0
## A downward flick on the throw, world px/s.
@export var throw_kick: float = 520.0
## The trick: how long a sleep counts, before the "time between uses" node, what the next bonk
## is worth, and for how long after the return.
@export var trick_seconds: float = 1.5
@export var trick_mult: float = 2.5
@export var trick_window: float = 2.5
## Slower than this, touching him is not a bonk.
@export var min_bonk_speed: float = 300.0

## Back in the hand when the yo-yo is this near it.
const HOME_DISTANCE := 14.0
## A little rebound off the end of the string, so it jerks rather than sticks.
const STRING_BOUNCE := 0.15
## Seconds between two bonks it bills itself: one swing, one bill.
const BONK_GAP := 0.25
## How many physics frames of its speed it remembers. The contact is reported a step after the
## step that stopped it (D57's stress ball), so the approach is read from before that.
const HISTORY := 4
const SPIN_SLEEPING := 30.0
const SPIN_TRAVEL := 12.0
const TICK_SECONDS := 0.35
const STRING_COLOUR := Color("fcfcee")

var _out := false
var _returning := false
var _sleeping := false
var _length := 0.0
var _sleep_seconds := 0.0
var _trick_until_msec := 0
var _next_bonk_msec := 0
var _anchor_velocity := Vector2.ZERO
var _anchor_last := Vector2.INF
var _history := PackedVector2Array()
var _history_at := 0
var _tick := 0.0
var _string: Line2D

## Counts for the suite and the F3 overlay. Never read by the simulation.
var throws := 0
var tricks := 0
var bonks := 0

func _ready() -> void:
	super._ready()
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 4)
	body_entered.connect(_on_body_entered)
	if gestures:
		gestures.gesture.connect(_on_gesture)

func is_out() -> bool:
	return _out

func is_asleep() -> bool:
	return _sleeping

func is_returning() -> bool:
	return _returning

func string_out() -> float:
	return _length

func sleep_seconds() -> float:
	return _sleep_seconds

func trick_armed() -> bool:
	return Time.get_ticks_msec() < _trick_until_msec

# --- the hand ------------------------------------------------------------------

func _on_gesture(g: GestureZones.Gesture) -> void:
	match g.kind:
		GestureZones.ACTION:
			throw()
		GestureZones.ACTION_END:
			wind_in()

## Out it goes: off the finger and down the string.
func throw() -> void:
	if not dragging or _out or handle == null:
		return
	_out = true
	_returning = false
	_sleeping = false
	_sleep_seconds = 0.0
	throws += 1
	if mouse_joint:
		mouse_joint.queue_free()
		mouse_joint = null
	_length = maxf(global_position.distance_to(handle.global_position), 4.0)
	_anchor_last = handle.global_position
	apply_central_impulse(Vector2(0.0, throw_kick) * mass)
	if tail:
		tail.visible = false
	_show_string(true)
	AudioManager.play(&"zip", 0.08, -10.0, 1.0)

## Right comes up: it climbs back into the hand. A long enough sleep before it makes the next
## bonk a trick shot.
func wind_in() -> void:
	if not _out or _returning:
		return
	_returning = true
	if _sleep_seconds >= _trick_needed():
		_trick()
	_sleeping = false
	AudioManager.play(&"zip", 0.08, -12.0, 1.35)

func _trick_needed() -> float:
	return maxf(0.2, trick_seconds * Progression.get_modifier(item_id, &"cooldown_mult")) \
		if item_id != &"" else trick_seconds

func _trick() -> void:
	tricks += 1
	_trick_until_msec = Time.get_ticks_msec() + int(trick_window * 1000.0)
	AudioManager.play(&"plink", 0.0, -8.0, 1.5)
	var fx := WorldFX.of(self)
	if fx:
		fx.burst(global_position, &"star", trail_colour(), 6, 120.0, 0.5)
	EventBus.fidget_event.emit(item_id, &"yoyo_trick", global_position)

## Back in the hand: pinned to it again as it was picked up, the tail showing.
func _home() -> void:
	_out = false
	_returning = false
	_sleeping = false
	_sleep_seconds = 0.0
	_show_string(false)
	if tail:
		tail.visible = true
	if sprite:
		sprite.rotation = 0.0
	if dragging and handle and mouse_joint == null:
		mouse_joint = PinJoint2D.new()
		mouse_joint.position = grip_offset
		mouse_joint.node_a = handle.get_path()
		mouse_joint.node_b = get_path()
		mouse_joint.softness = joint_softness
		mouse_joint.bias = joint_bias
		add_child(mouse_joint)

## Let go of the finger loop with it out, and the string goes with it: it is loose.
func _end_drag() -> void:
	super._end_drag()
	if _out:
		_out = false
		_returning = false
		_sleeping = false
		_show_string(false)
		if tail:
			tail.visible = true

# --- the string -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# A ring, not a queue: this runs every physics frame for as long as it is on the desk.
	if _history.size() != HISTORY:
		_history.resize(HISTORY)
	_history[_history_at] = linear_velocity
	_history_at = (_history_at + 1) % HISTORY
	if not _out or handle == null:
		return
	var anchor := handle.global_position
	if _anchor_last != Vector2.INF and delta > 0.0:
		_anchor_velocity = (anchor - _anchor_last) / delta
	_anchor_last = anchor
	var spin := 0.0
	if _returning:
		_length = maxf(_length - return_speed * delta, 0.0)
		spin = SPIN_TRAVEL
		if global_position.distance_to(anchor) <= HOME_DISTANCE:
			_home()
			return
	elif _length < string_length:
		_length = minf(_length + throw_speed * delta, string_length)
		spin = SPIN_TRAVEL
	elif gestures and gestures.action_live():
		# At the end of the string with the button still down: asleep, spinning in place.
		_sleeping = true
		_sleep_seconds += delta
		spin = SPIN_SLEEPING
		_tick += delta
		if _tick >= TICK_SECONDS:
			_tick = 0.0
			if _animating():
				AudioManager.play(&"whirr", 0.06, -16.0, 1.6)
			EventBus.fidget_event.emit(item_id, &"spinning", global_position)
	if sprite and _animating():
		sprite.rotation += spin * delta
	_update_string(anchor)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not _out or handle == null:
		return
	var anchor := handle.global_position
	var offset := state.transform.origin - anchor
	var distance := offset.length()
	if distance <= _length or distance <= 0.0:
		return
	var n := offset / distance
	var xf := state.transform
	xf.origin = anchor + n * _length
	state.transform = xf
	var outward := (state.linear_velocity - _anchor_velocity).dot(n)
	if outward > 0.0:
		state.linear_velocity -= n * outward * (1.0 + STRING_BOUNCE)

func _show_string(on: bool) -> void:
	if on and _string == null:
		_string = Line2D.new()
		_string.name = "String"
		# World space, so the line does not turn with the yo-yo.
		_string.top_level = true
		_string.width = 2.0
		_string.default_color = STRING_COLOUR
		_string.antialiased = false
		_string.z_index = -1
		add_child(_string)
	if _string:
		_string.visible = on
		if on and handle:
			_update_string(handle.global_position)

func _update_string(anchor: Vector2) -> void:
	if _string == null:
		return
	_string.clear_points()
	_string.add_point(anchor.round())
	_string.add_point(global_position.round())

func _animating() -> bool:
	return Settings.focus_intensity != Settings.Intensity.OFF

# --- the bonk ----------------------------------------------------------------------

## Bonking him on the string. See the class comment for why it bills itself.
func _on_body_entered(other: Node) -> void:
	var him := other as Buddy
	if him == null or not _out:
		return
	var now := Time.get_ticks_msec()
	if now < _next_bonk_msec:
		return
	var approach := approach_speed(him)
	if approach < min_bonk_speed:
		return
	_next_bonk_msec = now + int(BONK_GAP * 1000.0)
	var bounce := physics_material_override.bounce if physics_material_override else 0.0
	var reduced := mass * him.mass / maxf(mass + him.mass, 0.001)
	var impulse := (1.0 + bounce) * reduced * approach
	var mult := Progression.damage_mult_for(item_id, damage_mult)
	if now < _trick_until_msec:
		mult *= trick_mult
		_trick_until_msec = 0
	bonks += 1
	him.take_impulse(impulse, item_id, mult, global_position)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

## The fastest it was closing on him over the last few steps, world px/s.
func approach_speed(him: Node2D) -> float:
	var toward := him.global_position - global_position
	if toward.length_squared() <= 0.0:
		return 0.0
	var n := toward.normalized()
	var best := 0.0
	for v in _history:
		best = maxf(best, v.dot(n))
	return best

## On the string, his contact path bills nothing: the yo-yo has billed the bonk itself.
func effective_damage_mult() -> float:
	if _out:
		return 0.0
	return super.effective_damage_mult()

func register_use() -> void:
	if not _out:
		super.register_use()
