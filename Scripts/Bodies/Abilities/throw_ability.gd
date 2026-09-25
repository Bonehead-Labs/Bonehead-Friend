class_name ThrowAbility
extends WeaponAbility

## It flies at him and comes back to the hand (D74): the fire axe's Tomahawk.
##
## Right while holding it lets it go at him: the low arc through his middle at `throw_speed`
## (45 degrees if that speed cannot reach him), spinning end over end at `spin` rad/s.
##
## **The throw bills itself, once,** the golf ball's way (D66's pellet). A thrown body reaching
## him is the case D64 measured and left alone: Godot's cast-ray CCD slows a fast body so it
## arrives "softly" the step before contact, so a throw pays a fraction of its speed — a thrown axe
## measured a fifth of an ordinary swing. So for the flight he and the axe do not collide, and the
## axe is swept for him instead — its own shapes, and the segment its centre flew. The first tick it
## is in him it hands him `hit_force`, scaled by how fast it is going (0.6x to 1.4x of
## `throw_speed`), through `Buddy.take_impulse` at the axe's multiplier times `throw_mult`, shoved
## along its flight; then it rebounds off him.
##
## **Then it comes back.** After the hit, or after `out_seconds`, or off the world, gravity lets
## go of it and it steers home to the cursor: a steering impulse toward the velocity that would
## take it there at `return_speed`, capped at `return_accel` — never a write to its velocity (D54).
## If the left button is still down when it arrives within `catch_radius` of the hand, the hand
## takes it again. If the player let go meanwhile, it drops where the hand is. A throw not home
## after `give_up_seconds` simply falls. The exception with him comes off once it is clear of him.
##
## Row: `throw_speed`, `spin`, `hit_force`, `throw_mult`, `shove`, `out_seconds`, `return_speed`,
## `return_accel`, `catch_radius`, `give_up_seconds`.

const OUT := 0
const BACK := 1
const CLEAR := 2

var _phase := OUT
var _t := 0.0
var _left_down := false
var _throwing := false
var _gravity_was := 1.0
var _gravity := 980.0
var _last_com := Vector2.INF
var _excepted: Buddy
var _clear_t := 0.0
## Where the cursor is, from the motion events that arrive while it is in the air — never polled
## (CLAUDE.md: a synthetic event cannot move the OS cursor, so a poll cannot be driven by a test).
var _cursor := Vector2.ZERO

## For the suites: how fast it left, the hit it landed, whether it was caught, and how long the
## round trip took.
var last_throw_speed := 0.0
var last_hit := 0.0
var throw_hits := 0
var caught := false
var last_trip := 0.0

func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func _can_start() -> bool:
	return buddy() != null

func in_flight() -> bool:
	return _active and _throwing

func returning() -> bool:
	return _active and _throwing and _phase == BACK

func _on_press() -> void:
	_phase = OUT
	_t = 0.0
	throw_hits = 0
	last_hit = 0.0
	caught = false
	_left_down = true
	_throwing = true
	# Where the hand is, before it opens: the handle stops following the cursor once it lets go.
	_cursor = hand_world()
	# Its own release first: the hand opens.
	body._end_drag()
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	var from := com_world()
	_last_com = from
	var want := _aim(from, num("throw_speed", 1100.0))
	# One impulse to the velocity the throw wants, from the velocity it has — not a write.
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	# Heading right it turns clockwise, top first — the way an axe leaves a hand.
	var spin := signf(want.x) if absf(want.x) > 1.0 else 1.0
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	body.apply_torque_impulse((spin * num("spin", 16.0) - body.angular_velocity) * inertia)
	last_throw_speed = want.length()
	# The left button is watched from here, since the body no longer is.
	set_process_input(true)
	run(true)
	sound(&"whoosh", -4.0, 0.9)
	tell(&"incoming", him_world())

func _input(event: InputEvent) -> void:
	super._input(event)
	var motion := event as InputEventMouseMotion
	if motion:
		_cursor = body.get_canvas_transform().affine_inverse() * motion.position
		return
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		_left_down = false

## Its own `_end_drag` is what threw it; any other drop mid-flight changes nothing.
func _on_dropped() -> void:
	if not _throwing and _phase != CLEAR:
		finish()

func _on_tick(delta: float) -> void:
	_t += delta
	if _phase == CLEAR:
		_clear_t += delta
		if not overlaps_him() or _clear_t >= 1.0:
			finish()
		return
	last_trip = _t
	if _phase == OUT:
		var com := com_world()
		if throw_hits == 0 and (overlaps_him() or _crossed_him(_last_com, com)):
			_hit()
			_turn_back()
			return
		_last_com = com
		var hit_world := false
		for other in body.get_colliding_bodies():
			if not (other is RigidBody2D):
				hit_world = true
		if hit_world or _t >= num("out_seconds", 0.55):
			_turn_back()
		return
	if _t >= num("give_up_seconds", 3.0):
		_let_go()
		return
	var hand := _hand()
	var to := hand - com_world()
	var distance := to.length()
	var reach := num("catch_radius", 48.0)
	if distance <= reach or grip_world().distance_to(hand) <= reach:
		_arrive()
		return
	# Slows as it comes in, so it arrives rather than overshoots.
	var speed := num("return_speed", 1200.0) * clampf(distance / 140.0, 0.35, 1.0)
	var want := to / maxf(distance, 0.001) * speed
	var change := (want - body.linear_velocity).limit_length(num("return_accel", 5000.0) * delta)
	body.apply_central_impulse(change * body.mass)

func _crossed_him(from: Vector2, to: Vector2) -> bool:
	if from == Vector2.INF or from.is_equal_approx(to) or not body.is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters2D.create(from, to, BUDDY_LAYER)
	query.hit_from_inside = true
	return not body.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

## In him: the chop, billed once, and the axe bounces back off him.
func _hit() -> void:
	var him := buddy()
	if him == null:
		return
	var v := body.linear_velocity
	var share := clampf(v.length() / maxf(num("throw_speed", 1100.0), 1.0), 0.6, 1.4)
	last_hit = num("hit_force", 2400.0) * share
	var at := him.get_interaction_rect().get_center()
	strike(last_hit, v if v.length_squared() > 1.0 else Vector2.RIGHT, at, num("throw_mult", 1.3),
		num("shove", 0.5))
	throw_hits += 1
	paid_off.emit(&"tomahawk")
	# Off him: most of its speed turned round.
	body.apply_central_impulse(-v * body.mass * 1.4)
	var fx := fx()
	if fx:
		fx.chips(at, Color("f2ead8"), 6, 260.0)
		fx.ring(at, 50.0, tier_colour(), 0.2, 3.0)
		fx.shake(3.0)
	sound(&"impact_metal", -4.0, 0.8)

func _turn_back() -> void:
	_phase = BACK
	_gravity_was = body.gravity_scale
	body.gravity_scale = 0.0
	sound(&"whoosh", -10.0, 1.3)

## Where the hand is: the cursor, as the motion events last put it.
func _hand() -> Vector2:
	return _cursor

func _arrive() -> void:
	body.gravity_scale = _gravity_was
	_throwing = false
	set_process_input(false)
	if _left_down:
		# Back in the hand: the joint pins at the grip again, and the handle chases the cursor.
		body._start_drag()
		caught = body.dragging
		var fx := fx()
		if fx:
			fx.ring(hand_world(), 26.0, tier_colour(), 0.18, 2.0)
		sound(&"impact_metal", -10.0, 1.4)
	_phase = CLEAR
	_clear_t = 0.0

func _let_go() -> void:
	body.gravity_scale = _gravity_was
	_throwing = false
	set_process_input(false)
	_phase = CLEAR
	_clear_t = 0.0

func _on_stop() -> void:
	if _throwing and body:
		body.gravity_scale = _gravity_was
	_throwing = false
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null

## The low arc through his middle from `from` at `speed`, or 45 degrees toward him when that
## speed cannot reach him — the golf ball's solution.
func _aim(from: Vector2, speed: float) -> Vector2:
	var target := him_world()
	if target == Vector2.INF:
		return Vector2.RIGHT * speed
	var dx := target.x - from.x
	var rise := from.y - target.y
	var side := 1.0 if dx >= 0.0 else -1.0
	var x := absf(dx)
	var g := _gravity * body.gravity_scale
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * rise * v2)
	var angle := PI * 0.25
	if x > 1.0 and disc >= 0.0 and g > 0.0:
		angle = atan((v2 - sqrt(disc)) / (g * x))
	return Vector2(cos(angle) * side, -sin(angle)) * speed
