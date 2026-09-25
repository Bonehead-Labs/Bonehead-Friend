class_name BladeAim
extends RefCounted

## Lays a held blade's line — grip to point — along a direction and holds it there (D74, the
## blades): the rapier on guard, the katar's jabs, the boxcutter's snaps.
##
## D56's aim, applied to a weapon rather than a gun: a PD on the angle between the blade's line and
## the direction, scaled by the moment of inertia about the grip so a light knife and a heavy sword
## answer it alike, capped at `accel` rad/s² — so a blade already swinging still has to be caught —
## with gravity's pull about the grip cancelled on top. A torque, never a write to its spin (D54).
##
## **Up and over, never down through the desk.** A blade hanging from the hand with its point on
## the desk, turned the short way, drives its point into the desk and jams there. If the short way
## passes straight down, it goes the long way round, the way a fencer raises a blade.
##
## Returns how far off the direction the blade was, in radians, before this tick's torque.
static func hold(ability: WeaponAbility, direction: Vector2, frequency: float, damping: float,
		accel: float, gravity: float) -> float:
	var body := ability.body
	if body == null or direction.length_squared() < 0.0001:
		return 0.0
	var grip := ability.grip_world()
	var arm := ability.com_world() - grip
	var torque := -arm.x * body.mass * gravity * body.gravity_scale
	var axis := ability.tip_world() - grip
	var from := axis.angle() if axis.length_squared() > 1.0 else 0.0
	var err := wrapf(direction.angle() - from, -PI, PI)
	var off := absf(err)
	var down := wrapf(PI * 0.5 - from, -PI, PI)
	if absf(err) > 0.05 and signf(down) == signf(err) and absf(down) < absf(err):
		err -= signf(err) * TAU
	var inertia := ability.pivot_inertia()
	var pd := inertia * (frequency * frequency * err - 2.0 * damping * frequency * body.angular_velocity)
	var cap := inertia * accel
	body.apply_torque(torque + clampf(pd, -cap, cap))
	return off
