class_name PullBackCar
extends FidgetToy

## A pull-back car (D66).
##
## - **Right-press it and drag it backwards to wind it.** It rolls back under your hand and
##   clicks once a notch, and the notches show above it as you go. Whichever way you pull it is
##   backwards: the car turns to face away from the pull on the first notch.
## - **Let go and it zooms** along its facing, as fast and as far as it was wound.
## - **Send it into him and he hops on for a ride.** He jumps, lands on the roof, and rides it
##   across the desk before hopping off. The ride is the payout — an act, by how far the car was
##   wound — because a ride is a thing you gave him, which is the kind side's whole verb.
## - **Left alone with it, he winds it himself** and lets it go away from him, then chases it.
##
## **Why kind, not a ram.** A car that drives *at* him and pays Bones is a melee weapon with a
## motor: the harm side already has thirty ways to hit him and a contact solver that cannot
## bill a hit that parts in one step (D59's F1) — which a small fast car bouncing off him is.
## A ride is a verb nothing in the game has: he stands on a thing that moves. So it sits in
## Play, is bought with Hearts, and pays Hearts for the rides it gives.
##
## At rest it runs no frame of its own. The motor and the ride run in `_physics_process` only
## while there is something to drive, and the notches are drawn only while it is being wound.

## The two wheels, drawn over the ones in the body sprite, turned as it rolls.
@export var rear_wheel: Node2D
@export var front_wheel: Node2D
## Kindness value of a ride from a full wind, before the item's own value node.
@export var ride_value: float = 24.0
## Top speed from a full wind, world px/s, and how long the motor runs for.
@export var max_speed: float = 540.0
@export var run_seconds: float = 2.4
## World px of pull that is a full wind, before the "time between uses" node — "Tighter
## Spring" winds it fully in a shorter pull.
@export var full_pull: float = 150.0
## The ride: how long, and how fast the car carries him.
@export var ride_seconds: float = 1.6
@export var ride_speed: float = 230.0
## Slower than this, the car only bumps him.
@export var ride_min_speed: float = 140.0

const NOTCHES := 8
## Wound less than this, letting go does nothing.
const MIN_CHARGE := 0.12
const WHEEL_RADIUS := 7.0
## The motor: how hard it pushes toward its target speed, as an acceleration.
const DRIVE_GAIN := 9.0
const DRIVE_ACCEL := 1500.0
## A motor that has not got it past this speed in this long is against a wall.
const STUCK_SPEED := 20.0
const STUCK_SECONDS := 0.3
## His hop onto the roof: how far above it he clears, and how long he has to land.
const HOP_CLEARANCE := 16.0
const HOP_GRACE := 0.45
## How near the roof his feet must be to count as landed on it, world px.
const ROOF_SLACK := 12.0
## His own wind: a middling one, and what he gets out of it.
const HIS_CHARGE := 0.55
const HIS_SHARE := 0.15
## The notch pips drawn above it while it is wound, world px.
const PIP := 4.0
const PIP_GAP := 2.0
const PIP_LIFT := 14.0
const PIP_FULL := Color("f2d06b")
const PIP_EMPTY := Color("2a2e38")
const PIP_EDGE := Color("000000")

var facing := 1.0
var charge := 0.0

var _winding := false
var _pull := 0.0
var _notches := 0
var _wind_x := 0.0
var _driving := false
var _drive_left := 0.0
var _target_speed := 0.0
var _stuck := 0.0
var _by_player := true
var _launch_charge := 0.0

var _rider: Buddy = null
var _hopping := false
var _hop_deadline := 0
var _riding := false
var _ride_left := 0.0
var _welds: Array[PinJoint2D] = []

## Rides given, for the suite and the F3 overlay. Never read by the simulation.
var rides := 0
var launches := 0

func _ready() -> void:
	super._ready()
	set_process(false)
	body_entered.connect(_on_body_entered)

func is_winding() -> bool:
	return _winding

func is_driving() -> bool:
	return _driving

func is_riding() -> bool:
	return _riding

func is_hopping() -> bool:
	return _hopping

func notches() -> int:
	return _notches

## Faces the art one way or the other. The body's origin is the middle of the car, so every
## part mirrors about it, and so do the zones.
func set_facing(direction: float) -> void:
	direction = -1.0 if direction < 0.0 else 1.0
	if is_equal_approx(direction, facing):
		return
	facing = direction
	for part in [sprite, rear_wheel, front_wheel]:
		var s := part as Sprite2D
		if s == null:
			continue
		s.flip_h = facing < 0.0
		s.position.x = -s.position.x
		s.offset.x = -s.offset.x
	if gestures:
		gestures.mirrored = facing < 0.0

# --- winding -------------------------------------------------------------------

func _on_gesture(g: GestureZones.Gesture) -> void:
	if g.button != MOUSE_BUTTON_RIGHT or g.zone != &"car":
		return
	match g.kind:
		GestureZones.PRESS:
			_start_wind(g.world)
		GestureZones.DRAG:
			_wind_to(g.world)
		GestureZones.RELEASE:
			_end_wind()

func _start_wind(at: Vector2) -> void:
	# In the hand it is being carried, not wound; a ride under way is not interrupted.
	if dragging or _riding or _hopping:
		return
	_winding = true
	_driving = false
	_pull = 0.0
	_notches = 0
	charge = 0.0
	_wind_x = at.x
	freeze = true
	queue_redraw()

## A drag backwards rolls it back under the hand and winds the spring. It is a ratchet: pushing
## forward winds nothing and unwinds nothing. The first move decides which way is backwards.
func _wind_to(at: Vector2) -> void:
	if not _winding:
		return
	var dx := at.x - _wind_x
	_wind_x = at.x
	if is_zero_approx(dx):
		return
	if _pull <= 0.0:
		set_facing(-signf(dx))
	var back := -dx * facing
	if back <= 0.0:
		return
	var full := _full_pull()
	var before := _pull
	_pull = minf(_pull + back, full)
	var roll := Vector2(-facing * (_pull - before), 0.0)
	# Rolled back only where there is room: against a wall it winds in place.
	if not test_move(global_transform.translated(Vector2(0.0, -2.0)), roll):
		global_position += roll
		_turn_wheels(roll.x)
	var reached := mini(NOTCHES, int(floor(_pull / full * float(NOTCHES) + 0.0001)))
	while _notches < reached:
		_notches += 1
		AudioManager.play(&"ratchet", 0.04, -10.0, 0.9 + 0.05 * float(_notches))
	charge = float(_notches) / float(NOTCHES)
	queue_redraw()

func _end_wind() -> void:
	if not _winding:
		return
	_winding = false
	freeze = false
	queue_redraw()
	if charge >= MIN_CHARGE:
		launch(charge, true)
	charge = 0.0
	_notches = 0
	_pull = 0.0

func _full_pull() -> float:
	return maxf(20.0, full_pull * upgrade(&"cooldown_mult"))

## Lets it go: the motor runs for a time and to a speed set by the wind.
func launch(wound: float, by_player: bool) -> void:
	_launch_charge = clampf(wound, 0.0, 1.0)
	_by_player = by_player
	_driving = true
	_drive_left = run_seconds * _launch_charge
	_target_speed = max_speed * (0.4 + 0.6 * _launch_charge)
	_stuck = 0.0
	launches += 1
	sleeping = false
	AudioManager.play(&"zoom", 0.06, lerpf(-14.0, -6.0, _launch_charge), 0.8 + 0.4 * _launch_charge)
	if by_player:
		EventBus.contract_event.emit(&"use:%s" % item_id, 1)

func _draw() -> void:
	if not _winding:
		return
	# The wind, as pips above the roof: one per notch, filled as they click.
	var width := float(NOTCHES) * (PIP + PIP_GAP) - PIP_GAP
	var top := -_half_extent().y - PIP_LIFT
	for i in NOTCHES:
		var rect := Rect2(Vector2(-width * 0.5 + float(i) * (PIP + PIP_GAP), top), Vector2(PIP, PIP))
		draw_rect(rect.grow(1.0), PIP_EDGE)
		draw_rect(rect, PIP_FULL if i < _notches else PIP_EMPTY)

# --- driving ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _riding:
		_ride_step(delta)
		return
	if _hopping:
		_hop_step()
		return
	if not _driving or dragging or freeze:
		if not freeze and absf(linear_velocity.x) > 1.0:
			_turn_wheels(linear_velocity.x * delta)
		return
	var along := linear_velocity.x * facing
	var err := _target_speed - along
	if err > 0.0:
		apply_central_force(Vector2(facing * mass * minf(err * DRIVE_GAIN, DRIVE_ACCEL), 0.0))
	_turn_wheels(linear_velocity.x * delta)
	_drive_left -= delta
	if along < STUCK_SPEED:
		_stuck += delta
	else:
		_stuck = 0.0
	if _drive_left <= 0.0 or _stuck >= STUCK_SECONDS:
		_driving = false

func _turn_wheels(distance: float) -> void:
	if not animating():
		return
	var turn := distance / WHEEL_RADIUS
	for wheel in [rear_wheel, front_wheel]:
		if wheel:
			(wheel as Node2D).rotation += turn

func _start_drag() -> void:
	_end_ride(false)
	_driving = false
	if _winding:
		_winding = false
		freeze = false
		queue_redraw()
	super._start_drag()

# --- the ride ---------------------------------------------------------------------

## Running into him fast enough, sent by the player: he hops on. Deferred, because this arrives
## from inside the physics flush and the hop changes his velocity and the car's freeze.
func _on_body_entered(other: Node) -> void:
	var him := other as Buddy
	if him == null or not _driving or not _by_player or _hopping or _riding:
		return
	if absf(linear_velocity.x) < ride_min_speed and absf(_previous_speed) < ride_min_speed:
		return
	_start_hop.call_deferred(him)

## He jumps: straight up enough to clear the roof, and across by just enough to come down on
## the middle of it. The car waits for him — frozen where it is, so the landing is on a thing
## that stays put.
func _start_hop(him: Buddy) -> void:
	if not is_instance_valid(him) or _hopping or _riding or dragging or not is_inside_tree():
		return
	if him.dragging or _knocked_out(him):
		return
	_driving = false
	freeze = true
	_rider = him
	_hopping = true
	# He and the car pass through each other until the ride is over: the hop starts beside the
	# car, and a skeleton rising past its roof corner catches on it and tips over (measured: a
	# 43 px hop topped out at 29 and turned him a radian). The welds hold him on it.
	add_collision_exception_with(him)
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)) \
		* him.gravity_scale
	var feet := him.get_interaction_rect().end.y
	var roof := _roof_y()
	var rise := maxf(feet - roof, 0.0) + HOP_CLEARANCE
	var up := sqrt(2.0 * gravity * rise)
	var flight := up / gravity + sqrt(2.0 * HOP_CLEARANCE / gravity)
	var across := (global_position.x - him.global_position.x) / flight
	var velocity := him.linear_velocity
	him.apply_central_impulse(Vector2(across - velocity.x, -up - velocity.y) * him.mass)
	_hop_deadline = Time.get_ticks_msec() + int((flight + HOP_GRACE) * 1000.0)
	AudioManager.play(&"boing", 0.1, -12.0, 1.3)

## Waits for him to come down on the roof, and welds him to it when he does.
func _hop_step() -> void:
	var him := _rider
	if not is_instance_valid(him) or him.dragging or _knocked_out(him):
		_end_ride(false)
		return
	var feet := him.get_interaction_rect().end.y
	var roof := _roof_y()
	var over := absf(him.global_position.x - global_position.x) <= _half_extent().x
	# Coming down through the roof line, over the car: he has landed. Nothing collides, so this
	# is a crossing rather than a contact, and he is set exactly on the roof before the weld.
	if over and him.linear_velocity.y >= 0.0 and feet >= roof - 2.0 and feet <= roof + ROOF_SLACK:
		him.global_position.y -= feet - roof
		_weld(him)
		return
	if Time.get_ticks_msec() > _hop_deadline:
		_end_ride(false)

## Two pins a head apart: one would let him spin on it, two hold him as he stands.
func _weld(him: Buddy) -> void:
	_hopping = false
	_riding = true
	_ride_left = ride_seconds
	var com := him.global_transform * him.center_of_mass
	for lift in [0.0, -30.0]:
		var joint := PinJoint2D.new()
		joint.name = "Ride"
		joint.softness = 0.0
		add_child(joint)
		joint.global_position = com + Vector2(0.0, lift)
		joint.node_a = get_path()
		joint.node_b = him.get_path()
		_welds.append(joint)
	rides += 1
	var value := ride_value * _launch_charge
	chips(him.global_position + Vector2(0, -40), &"heart", 4 + int(round(4.0 * _launch_charge)), 110.0)
	pay_act(value, him.global_position, &"ride")

## The ride itself: the car carries him along its facing, slowing as it goes. Frozen, so it is
## the car that sets the pace and not his weight on it — and moved by `move_and_collide`, so a
## wall or a toy in the way ends the ride instead of being driven through.
func _ride_step(delta: float) -> void:
	var him := _rider
	if not is_instance_valid(him) or him.dragging or _knocked_out(him) or dragging:
		_end_ride(true)
		return
	_ride_left -= delta
	if _ride_left <= 0.0:
		_end_ride(true)
		return
	var ease_out := clampf(_ride_left / maxf(ride_seconds, 0.1), 0.25, 1.0)
	var step := Vector2(facing * ride_speed * ease_out * delta, 0.0)
	if move_and_collide(step) != null:
		_end_ride(true)
		return
	_turn_wheels(step.x)

## Off he gets — with a little hop forward if the ride ended properly — and the car is a car
## again.
func _end_ride(hop_off: bool) -> void:
	for joint in _welds:
		if is_instance_valid(joint):
			joint.queue_free()
	_welds.clear()
	var him := _rider
	_rider = null
	var was := _riding or _hopping
	_riding = false
	_hopping = false
	if was:
		freeze = false
	if is_instance_valid(him):
		remove_collision_exception_with(him)
	if hop_off and is_instance_valid(him) and not him.dragging:
		him.apply_central_impulse(Vector2(facing * 90.0, -240.0) * him.mass)

func _exit_tree() -> void:
	_end_ride(false)
	super._exit_tree()

static func _knocked_out(him: Buddy) -> bool:
	return him.state == &"knockout" or him.state == &"pile" or him.state == &"reassemble"

## The top of the car, in the world: the collider's top edge. It is locked upright, so this is
## the roof he stands on.
func _roof_y() -> float:
	return global_position.y - _half_extent().y

func _half_extent() -> Vector2:
	if collider and collider.shape:
		return collider.shape.get_rect().size * 0.5
	return Vector2(32, 16)

# --- him --------------------------------------------------------------------------

func idle_appeal() -> float:
	if _driving or _riding or _hopping:
		return 0.0
	# A launch every other think tick, and a chase between them.
	return ride_value * HIS_CHARGE * HIS_SHARE / (IdleBrain.THINK_SECONDS * 2.0)

## He winds it a little and lets it go, pointed away from him — then the brain's own steering
## sends him after it, which is the game: he chases his car. At Focus Off he is simply there
## and it pays without moving (D36).
func idle_use(him: Buddy) -> void:
	if _winding or _driving or _riding or _hopping or dragging:
		return
	pay_sustained(ride_value * HIS_CHARGE * HIS_SHARE, global_position)
	fidget(&"amused")
	if not animating():
		return
	var away := signf(global_position.x - him.global_position.x)
	set_facing(away if away != 0.0 else facing)
	AudioManager.play(&"ratchet", 0.04, -12.0, 1.0)
	launch(HIS_CHARGE, false)
