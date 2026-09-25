class_name DeliveryAbility
extends ThrowAbility

## The letter opener's Special Delivery (D74, the blades): tap right and it leaves the hand
## **point-first in a dead straight line** at him — no arc, no spin — and x`point_mult` if the point
## arrives. Then it **sticks where it lands**, quivering, and the ability is not over until you go
## and fetch it: the cooldown starts when your hand closes on it.
##
## The axe comes back to you and the cleaver stays in him. This one goes where it is sent and stays
## there, in the desk or the wall, and the walk to get it back is the price of the next one.
##
## **The flight.** Gravity off, turned so its point leads (grip to point along the line to him),
## launched at `throw_speed`, and held point-first by a PD torque on its heading — a dart's
## fletching — never a write to its spin (D54). For the flight he and it do not collide; it is
## swept for him instead, and the first tick it is in him the point bills once through
## `Buddy.take_impulse`: `point_force` scaled by how fast it was going, at the letter opener's own
## multiplier times `point_mult` (D64's reason a throw bills itself). Then it glances off, gravity
## back on, and falls.
##
## **It sticks** the first time it touches the world — the desk, a wall — with its point in it: it
## is frozen where it met it, collides with nothing, and quivers (the picture only). Past the
## top of the window it does not stick, because nobody could fetch it from there; it falls
## instead. Nothing runs while it waits: the tick stops once the quiver has.
##
## **Fetched** by taking hold of it: it comes free with a zip and the cooldown starts. Right on it
## while it is stuck is refused, not the bin, like any ability mid-effect; Shift+right still bins it.
##
## Row: `throw_speed`, `point_force`, `point_mult`, `shove`, `align_frequency`,
## `flight_seconds`, `quiver_seconds`, `give_up_seconds`.

const FLYING := 10
const FALLING := 11
const STUCK := 12

var _gravity_before := 1.0
var _layer := 0
var _mask := 0
var _freeze_mode := RigidBody2D.FREEZE_MODE_STATIC
var _frozen := false
var _sprite_rot := INF
var _quiver := 0.0

## For the suites: the point's hit, where it stuck and whether it was fetched.
var point_hits := 0
var stuck_at := Vector2.INF
var fetched := false
var launch_heading := Vector2.ZERO
var worst_heading := 0.0

func is_stuck() -> bool:
	return _active and _phase == STUCK

func in_flight() -> bool:
	return _active and (_phase == FLYING or _phase == FALLING)

func _on_press() -> void:
	_phase = FLYING
	_t = 0.0
	point_hits = 0
	throw_hits = 0
	last_hit = 0.0
	stuck_at = Vector2.INF
	fetched = false
	caught = false
	worst_heading = 0.0
	_throwing = true
	body._end_drag()
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	_gravity_before = body.gravity_scale
	body.gravity_scale = 0.0
	# Turned so the point leads: the blade's line laid along the line to his middle, about the
	# centre of mass, once — the launch is the one place it is placed rather than pushed.
	var from := com_world()
	var target := him_world()
	var heading := (target - from).normalized() if target != Vector2.INF and target.distance_to(from) > 1.0 \
		else Vector2.RIGHT
	launch_heading = heading
	var turn := wrapf(heading.angle() - _blade().angle(), -PI, PI)
	var xf := body.global_transform
	var about := from
	xf = Transform2D(turn, Vector2.ZERO) * Transform2D(xf.x, xf.y, xf.origin - about)
	xf.origin += about
	body.global_transform = xf
	var want := heading * num("throw_speed", 1500.0)
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	body.apply_torque_impulse(-body.angular_velocity * _inertia())
	last_throw_speed = want.length()
	_last_com = com_world()
	run(true)
	sound(&"zip", -4.0, 1.3)
	sound(&"whoosh", -12.0, 1.6)

func _on_dropped() -> void:
	pass

func _blade() -> Vector2:
	var axis := tip_world() - grip_world()
	return axis.normalized() if axis.length_squared() > 1.0 else Vector2.RIGHT

func _inertia() -> float:
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		return 1.0 / state.inverse_inertia
	return body.mass * 400.0

func _on_tick(delta: float) -> void:
	_t += delta
	match _phase:
		FLYING:
			_point_first()
			var com := com_world()
			if point_hits == 0 and (overlaps_him() or _crossed_him(_last_com, com)):
				_point_hit()
				return
			_last_com = com
			if _touching_world():
				_stick()
				return
			if _t >= num("flight_seconds", 1.2):
				_fall()
		FALLING:
			if _touching_world() and not overlaps_him():
				_stick()
				return
			if _t >= num("give_up_seconds", 3.0):
				# Never came to rest against anything it could stick in: it lies where it is.
				_phase = STUCK
				stuck_at = com_world()
				_quiver = 0.0
				_release_him()
				run(false)
		STUCK:
			_quiver = maxf(0.0, _quiver - delta / maxf(num("quiver_seconds", 0.6), 0.05))
			_quiver_sprite()
			if _quiver <= 0.0:
				# Nothing runs while it waits to be fetched.
				run(false)

## A dart's fletching: a torque that lays the blade along its velocity. Never a write to the spin.
func _point_first() -> void:
	var v := body.linear_velocity
	if v.length_squared() < 100.0:
		return
	var err := wrapf(v.angle() - _blade().angle(), -PI, PI)
	# Measured once the hand has let go of it: the joint is freed at the end of the frame it is
	# thrown in, and pulls the grip back once on its way out.
	if _t > 0.05:
		worst_heading = maxf(worst_heading, absf(err))
	var inertia := _inertia()
	var w := num("align_frequency", 30.0)
	body.apply_torque(inertia * (w * w * err - 2.0 * 0.9 * w * body.angular_velocity))

func _touching_world() -> bool:
	for other in body.get_colliding_bodies():
		if not (other is RigidBody2D):
			return true
	# Straight down onto the desk the contact can lag the arrival by a step: ask the desk too.
	if not body.is_inside_tree():
		return false
	var tip := tip_world()
	var v := body.linear_velocity
	if v.length_squared() < 1.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(tip, tip + v.normalized() * maxf(8.0, v.length() / 60.0),
		WORLD_LAYER, [body.get_rid()])
	return not body.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

## The point arrived: billed once, and it glances off and falls.
func _point_hit() -> void:
	var him := buddy()
	if him == null:
		return
	var v := body.linear_velocity
	var share := clampf(v.length() / maxf(num("throw_speed", 1500.0), 1.0), 0.6, 1.4)
	last_hit = num("point_force", 1600.0) * share
	var at := tip_world()
	if not touches_him(at, 6.0):
		at = him.get_interaction_rect().get_center()
	strike(last_hit, v if v.length_squared() > 1.0 else Vector2.RIGHT, at, num("point_mult", 2.0),
		num("shove", 0.5))
	point_hits += 1
	throw_hits += 1
	paid_off.emit(&"special_delivery")
	var fx := fx()
	if fx:
		fx.tracer(at - v.normalized() * 50.0, at + v.normalized() * 30.0, Color.WHITE, 0.14, 3.0)
		fx.ring(at, 30.0, WorldFX.GOLD, 0.2, 3.0)
		fx.burst(at, &"star", WorldFX.GOLD, 3, 220.0)
	sound(&"tink", -2.0, 0.85)
	tell(&"delivered", at)
	# Off him: most of its speed spent, turned back and up, and it falls.
	body.apply_central_impulse((Vector2(-v.x * 0.25, -120.0) - v) * body.mass)
	_fall()

func _fall() -> void:
	_phase = FALLING
	_t = 0.0
	body.gravity_scale = _gravity_before

## In the world, point first: frozen where it met it, quivering.
func _stick() -> void:
	var at := com_world()
	var visible_rect := body.get_viewport_rect() if body.is_inside_tree() else Rect2()
	var top := visible_rect.position.y if visible_rect.size != Vector2.ZERO else -INF
	if at.y < top + 8.0:
		# Up where nobody can reach it: it does not stick there.
		_fall()
		return
	stuck_at = at
	_phase = STUCK
	_t = 0.0
	_quiver = 1.0
	body.gravity_scale = _gravity_before
	_layer = body.collision_layer
	_mask = body.collision_mask
	_freeze_mode = body.freeze_mode
	body.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	_frozen = true
	_release_him()
	var fx := fx()
	if fx:
		fx.puff(tip_world(), 4, WorldFX.DUST, 40.0, 0.5)
		fx.chips(tip_world(), WorldFX.DUST, 3, 120.0)
	sound(&"thunk", -2.0, 1.25)
	sound(&"twang", -10.0, 1.4)

func _release_him() -> void:
	_throwing = false
	if is_instance_valid(_excepted) and body and not overlaps_him():
		body.remove_collision_exception_with(_excepted)
		_excepted = null

func _quiver_sprite() -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_rot == INF:
		_sprite_rot = s.rotation
	var amp := 0.1 * _quiver * Settings.intensity_scale()
	s.rotation = _sprite_rot + sin(Time.get_ticks_msec() * 0.06) * amp

func _unstick() -> void:
	if not _frozen or body == null:
		return
	_frozen = false
	body.freeze = false
	body.freeze_mode = _freeze_mode
	body.collision_layer = _layer
	body.collision_mask = _mask
	var s := sprite()
	if s and _sprite_rot != INF:
		s.rotation = _sprite_rot
	_sprite_rot = INF

## Fetched: taken hold of wherever it stuck, it comes free, and the cooldown starts now.
func on_picked_up() -> void:
	if _active:
		if _phase == STUCK:
			fetched = true
			var fx := fx()
			if fx:
				fx.puff(tip_world(), 3, WorldFX.DUST, 40.0, 0.4)
			sound(&"zip", -8.0, 0.9)
		finish()
	super.on_picked_up()

func _on_stop() -> void:
	_unstick()
	if _throwing and body:
		body.gravity_scale = _gravity_before
	_throwing = false
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null
