class_name EmbedAbility
extends ThrowAbility

## The cleaver's Embed (D74, the blades): tap right and it is thrown end over end at him, and if it
## hits him **it stays in him** — for `lodge_seconds` it rides wherever he goes, and every
## `tick_seconds` it works a little deeper, a light hit each time — and then it drops out at his
## feet, where you pick it up.
##
## The fire axe's Tomahawk chops once and flies home. The cleaver does not come back and does not
## chop once: it is the one ability that keeps paying after it has landed, and the only one you can
## see *on him*.
##
## **The throw is the Tomahawk's**: the low arc through his middle at `throw_speed`, spinning at
## `spin`, the collision with him off for the flight and the blade swept for him instead, billed
## once on arrival through `Buddy.take_impulse` at the cleaver's multiplier times `throw_mult`,
## scaled by how fast it arrived (D64's reason a throw bills itself).
##
## **Lodged**, it is frozen and carried: its transform is his times where it went in, written every
## tick, and it collides with nothing (its layers are put back when it comes out). Each tick is
## `tick_force` through `take_impulse` at `tick_mult`, from the tick, before `StepStart` (D64), with
## a shove so small it only jolts him; bone dust falls from where it went in and the handle wags.
## It comes out when the time is up, when he goes down (a knockout takes him apart), or when the
## player takes hold of it and pulls — the handle is the grab region it always was.
##
## Missed, it falls where it fell and waits there like any cleaver. Cartoon, not gore: nothing it
## does is red.
##
## Row: `throw_speed`, `spin`, `hit_force`, `throw_mult`, `shove`, `out_seconds`,
## `lodge_seconds`, `tick_seconds`, `tick_force`, `tick_mult`, `give_up_seconds`.

const FLYING := 10
const LODGED := 11
const FALLING := 12

const BONE := Color("f2ead8")

var _lodge_local := Transform2D.IDENTITY
var _lodged_in: Buddy
var _next_tick_in := 0.0
var _layer := 0
var _mask := 0
var _freeze_mode := RigidBody2D.FREEZE_MODE_STATIC
var _frozen := false
var _wag := 0.0
var _sprite_rot := INF

## For the suites: whether it went in, how many ticks it worked, and how it came out.
var lodged := false
var ticks := 0
var came_out := &""

func is_lodged() -> bool:
	return _active and _phase == LODGED

func _on_press() -> void:
	_phase = FLYING
	_t = 0.0
	throw_hits = 0
	last_hit = 0.0
	ticks = 0
	lodged = false
	came_out = &""
	caught = false
	_throwing = true
	body._end_drag()
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	var from := com_world()
	_last_com = from
	var want := _aim_at(from, _chest(), num("throw_speed", 1000.0))
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	var spin := signf(want.x) if absf(want.x) > 1.0 else 1.0
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	body.apply_torque_impulse((spin * num("spin", 14.0) - body.angular_velocity) * inertia)
	last_throw_speed = want.length()
	run(true)
	sound(&"whoosh", -4.0, 0.75)
	tell(&"incoming", him_world())

## Its own `_end_drag` threw it; a drop after that changes nothing.
func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	_t += delta
	match _phase:
		FLYING:
			var com := com_world()
			if throw_hits == 0 and (overlaps_him() or _crossed_him(_last_com, com)):
				_hit()
				return
			_last_com = com
			# A tumbling blade can clip the desk on its way and fly on; it has missed when it has
			# lost most of its speed against the world, or run out of time.
			var stopped := false
			for other in body.get_colliding_bodies():
				if not (other is RigidBody2D) and body.linear_velocity.length() < last_throw_speed * 0.45:
					stopped = true
			if stopped or _t >= num("out_seconds", 0.7):
				# Missed: it lands wherever it lands.
				_phase = FALLING
				_t = 0.0
		LODGED:
			_ride(delta)
			var him := _lodged_in
			if not is_instance_valid(him) or him.health == null or him.health.down:
				_come_out(&"knocked_out")
				return
			_next_tick_in -= delta
			if _next_tick_in <= 0.0:
				_next_tick_in = num("tick_seconds", 0.5)
				_work_in()
			if _t >= num("lodge_seconds", 3.0):
				_come_out(&"time")
		FALLING:
			if (not overlaps_him() and _t >= 0.2) or _t >= num("give_up_seconds", 3.0):
				finish()

## Where it is thrown at: his chest, not his middle. It turns end over end, and a cleaver thrown
## at his middle from the side swings its handle into the desk on the way.
func _chest() -> Vector2:
	var him := buddy()
	if him == null:
		return Vector2.INF
	var rect := him.get_interaction_rect()
	return rect.get_center() - Vector2(0.0, rect.size.y * 0.2)

## The low arc from `from` through `target` at `speed` (the Tomahawk's solution, at a point).
func _aim_at(from: Vector2, target: Vector2, speed: float) -> Vector2:
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

## In him: the throw's hit, billed once, and it stays where it went in.
func _hit() -> void:
	var him := buddy()
	if him == null:
		return
	var v := body.linear_velocity
	var share := clampf(v.length() / maxf(num("throw_speed", 1000.0), 1.0), 0.6, 1.4)
	last_hit = num("hit_force", 1800.0) * share
	var at := him.get_interaction_rect().get_center()
	strike(last_hit, v if v.length_squared() > 1.0 else Vector2.RIGHT, at, num("throw_mult", 1.0),
		num("shove", 0.4))
	throw_hits += 1
	_lodge(him)
	var fx := fx()
	if fx:
		fx.chips(com_world(), BONE, 8, 240.0)
		fx.ring(com_world(), 40.0, tier_colour(), 0.2, 3.0)
		fx.shake(3.0)
	sound(&"thunk", 0.0, 1.0)
	sound(&"impact_metal", -10.0, 0.7)
	paid_off.emit(&"embed")

## Freezes it where it went in, a few pixels deeper, and remembers that place in his frame.
func _lodge(him: Buddy) -> void:
	lodged = true
	_lodged_in = him
	_phase = LODGED
	_t = 0.0
	_next_tick_in = num("tick_seconds", 0.5)
	_throwing = false
	# In by a few pixels along its flight, so the blade reads as buried rather than resting on him.
	var v := body.linear_velocity
	var xf := body.global_transform
	if v.length_squared() > 1.0:
		xf.origin += v.normalized() * 12.0
	_lodge_local = him.global_transform.affine_inverse() * xf
	_layer = body.collision_layer
	_mask = body.collision_mask
	_freeze_mode = body.freeze_mode
	body.collision_layer = 0
	body.collision_mask = 0
	body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	_frozen = true
	body.global_transform = xf
	tell(&"skewered", him.get_interaction_rect().get_center())

## Where it went in, wherever he is now.
func _ride(delta: float) -> void:
	if is_instance_valid(_lodged_in):
		body.global_transform = _lodged_in.global_transform * _lodge_local
	_wag_sprite(delta)

## One tick: a light hit, a jolt, bone dust from the cut, and the handle wags.
func _work_in() -> void:
	var him := _lodged_in
	if not is_instance_valid(him):
		return
	ticks += 1
	var at := com_world()
	var into := (him.get_interaction_rect().get_center() - at)
	strike(num("tick_force", 700.0), into if into.length_squared() > 1.0 else Vector2.DOWN, at,
		num("tick_mult", 1.0), 0.05)
	_wag = 1.0
	var fx := fx()
	if fx:
		# Grey, not bone-white: bone dust on a white skeleton is invisible.
		fx.chips(at, WorldFX.SOOT, 4, 90.0)
		fx.ring(at, 16.0, tier_colour(), 0.14, 2.0)
	sound(&"rattle", -14.0, 1.2 + 0.05 * float(ticks), 0.05)
	tell(&"skewered", him.get_interaction_rect().get_center())

## The handle wags after each tick and settles: the picture only, so the lodged transform stays
## exactly where it went in.
func _wag_sprite(delta: float) -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_rot == INF:
		_sprite_rot = s.rotation
	_wag = maxf(0.0, _wag - delta * 3.0)
	var amp := 0.12 * _wag * Settings.intensity_scale()
	s.rotation = _sprite_rot + sin(_t * 40.0) * amp

## Out of him: unfrozen, its layers back, and dropped at his feet — nudged off him, not thrown.
func _come_out(why: StringName) -> void:
	came_out = why
	_unlodge()
	var him := buddy()
	if him and not body.dragging:
		var side := signf(com_world().x - him.global_position.x)
		body.apply_central_impulse(Vector2(side * 80.0, -60.0) * body.mass)
	var fx := fx()
	if fx:
		fx.puff(com_world(), 4, WorldFX.DUST, 50.0, 0.5)
	sound(&"clack", -10.0, 0.9)
	_phase = FALLING
	_t = 0.0

func _unlodge() -> void:
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
	_lodged_in = null

## Taken hold of: pulled out, if it was in him, and the effect is over once it is clear of him.
func on_picked_up() -> void:
	if _active and _phase == LODGED:
		_come_out(&"pulled")
		var fx := fx()
		if fx:
			fx.chips(com_world(), BONE, 5, 200.0)
		sound(&"thunk", -6.0, 1.4)
	elif _active and _phase == FLYING:
		_phase = FALLING
		_t = 0.0
	super.on_picked_up()

func _on_stop() -> void:
	_unlodge()
	_throwing = false
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null
