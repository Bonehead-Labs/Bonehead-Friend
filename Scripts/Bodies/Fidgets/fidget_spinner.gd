class_name FidgetSpinner
extends FidgetToy

## A fidget spinner (D57).
##
## - **Left grabs it**, by the hub or anywhere — the arms claim only the right button.
## - **Right-drag across an arm spins it.** Pressing the arms catches it, as a finger would;
##   the drag turns the body with the cursor, and letting go throws it at the speed of the
##   swipe — the faster of the stroke's angular rate and its release velocity round the hub.
## - It **runs down over about half a minute** and settles on a third of a turn, where it looks
##   exactly as it started.
## - **While it spins and he is watching, it pays** a trickle of Hearts, faster the faster it
##   goes, and he stares at it. Left alone with it, he flicks it himself.
##
## Only the body turns. The centre cap is the bit your fingers hold, and it stays still, which
## is the whole trick of reading a spin at a glance.

## The picture that turns: the body's own sprite, pivoted on the hub by the seed tool.
@export var rotor: Node2D
## Top speed, rad/s. Six turns a second — at sixty frames that is still a readable blur.
@export var max_spin: float = 38.0
## Seconds for the spin to fall by e, before the "time between uses" node lengthens it.
@export var decay_seconds: float = 9.0
## A small constant drag on top, so it actually stops instead of creeping forever.
@export var friction: float = 0.35
## Kindness value per second at full speed while he is watching it.
@export var watch_value: float = 0.8
## How near he has to be to count as watching.
@export var watch_range: float = 380.0

## Below this it is stopped, and it settles onto the nearest third of a turn.
const STOP_SPIN := 0.9
const REST_STEP := TAU / 3.0
## His own flick, as a share of top speed. Less than the player's best: he is not very good at it.
const HIS_FLICK := 0.65
## How often the whirr sounds and the watching is re-checked, in seconds.
const TICK_SECONDS := 0.35

var spin := 0.0
var _tick := 0.0
var _held := false
## The stroke's own angular rate: radians over the last crank event's interval.
var _stroke_rate := 0.0
var _stroke_msec := 0
var _settling := false

func _ready() -> void:
	super._ready()
	set_process(false)

func _on_gesture(g: GestureZones.Gesture) -> void:
	if g.button != MOUSE_BUTTON_RIGHT or g.zone != &"arms":
		return
	match g.kind:
		GestureZones.PRESS:
			# A finger on it stops it.
			_held = true
			spin = 0.0
			_stroke_rate = 0.0
			_stroke_msec = Time.get_ticks_msec()
			_settling = false
		GestureZones.CRANK:
			# The body follows the hand.
			if rotor:
				rotor.rotation += g.angle * (-1.0 if gestures.mirrored else 1.0)
			var now := Time.get_ticks_msec()
			var dt := float(now - _stroke_msec) / 1000.0
			if dt > 0.0:
				_stroke_rate = g.angle / dt
			_stroke_msec = now
		GestureZones.FLICK:
			launch(_swipe_spin(g), true)
		GestureZones.RELEASE:
			_held = false
			if is_zero_approx(spin):
				# No flick: whatever the stroke was doing when it let go, if it was recent.
				var fresh := Time.get_ticks_msec() - _stroke_msec <= GestureZones.FLICK_FRESH_MSEC
				launch(_stroke_rate if fresh else 0.0, true)

## Spin from a swipe: the release velocity's component round the hub, over the distance from
## it. A stroke straight at the hub spins nothing; one across an arm at its tip spins most.
func _swipe_spin(g: GestureZones.Gesture) -> float:
	var hub := rotor.global_position if rotor else global_position
	var arm := g.world - hub
	var reach := maxf(arm.length(), 6.0)
	var tangential := arm.cross(g.velocity) / reach
	var from_swipe := tangential / reach
	return from_swipe if absf(from_swipe) >= absf(_stroke_rate) else _stroke_rate

## Sets it going. Direction as given; speed capped.
func launch(rad_per_second: float, by_player: bool) -> void:
	spin = clampf(rad_per_second, -max_spin, max_spin)
	if absf(spin) < STOP_SPIN:
		spin = 0.0
		_start_settling()
		return
	_settling = false
	_tick = 0.0
	set_process(true)
	if by_player:
		AudioManager.play(&"whirr", 0.1, -8.0, 1.4)

func is_spinning() -> bool:
	return absf(spin) >= STOP_SPIN

func _start_settling() -> void:
	if rotor == null or _held:
		return
	var rest := snappedf(rotor.rotation, REST_STEP)
	if is_equal_approx(rest, rotor.rotation):
		set_process(false)
		return
	_settling = true
	set_process(true)

func _process(delta: float) -> void:
	if _held:
		return
	if _settling:
		_settle(delta)
		return
	if rotor:
		rotor.rotation += spin * delta
	var tau := decay_seconds / maxf(upgrade(&"cooldown_mult"), 0.05)
	spin -= spin * delta / tau + signf(spin) * friction * delta
	if absf(spin) < STOP_SPIN:
		spin = 0.0
		_start_settling()
		return
	_tick += delta
	if _tick >= TICK_SECONDS:
		_on_tick(_tick)
		_tick = 0.0

## Coming to rest on a third of a turn, eased, so it stops looking exactly as it started.
func _settle(delta: float) -> void:
	if rotor == null:
		_settling = false
		set_process(false)
		return
	var rest := snappedf(rotor.rotation, REST_STEP)
	var step := 3.0 * delta
	if absf(rest - rotor.rotation) <= step:
		rotor.rotation = wrapf(rest, 0.0, TAU)
		_settling = false
		set_process(false)
		return
	rotor.rotation += signf(rest - rotor.rotation) * step

## Every third of a second while it spins: the whirr, and whether he is watching.
func _on_tick(seconds: float) -> void:
	var share := absf(spin) / max_spin
	if animating() and share > 0.2:
		AudioManager.play(&"whirr", 0.06, lerpf(-20.0, -10.0, share), 0.8 + 0.8 * share)
	if not _he_is_watching():
		return
	pay_sustained(watch_value * share * seconds, global_position)
	fidget(&"spinning")

func _he_is_watching() -> bool:
	var him := buddy()
	if him == null or him.dragging:
		return false
	if him.state == &"knockout" or him.state == &"pile" or him.state == &"reassemble":
		return false
	return him.global_position.distance_to(global_position) <= watch_range

func idle_appeal() -> float:
	return watch_value * HIS_FLICK * 0.5

## He gives it a flick when it has run down. At Focus Off he is simply there and it simply
## pays — nothing on the desk moves that the player did not move (D36).
func idle_use(him: Buddy) -> void:
	if absf(spin) >= max_spin * 0.3:
		return
	if not animating():
		pay_sustained(watch_value * HIS_FLICK * IdleBrain.THINK_SECONDS * 0.5, global_position)
		return
	var side := signf(global_position.x - him.global_position.x)
	launch(max_spin * HIS_FLICK * (side if side != 0.0 else 1.0), false)
	AudioManager.play(&"whirr", 0.1, -10.0, 1.2)
