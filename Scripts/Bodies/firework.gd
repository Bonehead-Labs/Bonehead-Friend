class_name Firework
extends ThrowableBase

## Erratic flight, colourful, low damage, high comedy.
##
## Primed like a grenade, but instead of sitting where it lands it lights and *flies*,
## wandering off its heading a little more every tick until its motor burns out and it goes
## off wherever it happens to be. It is the one explosive the player cannot aim, which is
## the whole joke: everything else in the category rewards a good throw, and this rewards
## letting go.

## Motor thrust, and how long it burns before the charge goes off.
@export var thrust: float = 1400.0
@export var flight_seconds: float = 1.4

## Radians per second of drift added to the heading, direction re-rolled on a timer. Low
## enough that the flight reads as a wobble rather than a spin.
@export var wander: float = 3.2
@export var wander_interval: float = 0.18

var _flying := false
var _flight_left := 0.0
var _heading := Vector2.UP
var _wander_left := 0.0
var _drift := 1.0

## The fuse is the launch, so the base class's timed explosion is replaced rather than
## extended: it lights the motor and the motor decides when the charge goes off.
func prime_explosion() -> void:
	if is_primed or _flying:
		return
	_flying = true
	_flight_left = flight_seconds
	# Launched along whatever it was already doing, or straight up from a standstill —
	# a rocket lit on the desk should leave the desk.
	_heading = linear_velocity.normalized() if linear_velocity.length() > 30.0 else Vector2.UP
	gravity_scale = 0.15
	if explosion_area:
		explosion_area.monitoring = true

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _flying:
		return

	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = wander_interval
		# Re-rolled per interval rather than per frame: a new random direction sixty times
		# a second averages out to a straight line, which is the opposite of the intent.
		_drift = randf_range(-1.0, 1.0)
	_heading = _heading.rotated(wander * _drift * delta)
	apply_central_force(_heading * thrust)
	rotation = _heading.angle() + PI / 2.0

	_flight_left -= delta
	if _flight_left > 0.0:
		return
	_flying = false
	gravity_scale = 1.0
	is_primed = true
	explode()
