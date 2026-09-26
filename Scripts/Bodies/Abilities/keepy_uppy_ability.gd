class_name KeepyUppyAbility
extends ThrowAbility

## The beach ball's Keepy-Uppy (docs/decisions.md D78): a tap, and it is lobbed up and over onto
## his head — and he heads it back up, again and again, and the last one back to you.
##
## The Tomahawk's archetype, played by him. The lob leaves the hand on the arc whose top is
## `lob_height` over his skull and comes down on it. For the whole rally he and the ball do not
## collide; the ability watches for it instead. Each time it comes down within `window` of the top
## of his skull he **heads it**: he pops up to meet it, a nod and a hop, and it goes back up,
## `bounce_height` over his head and re-aimed at where his head is now, so a rally survives him
## drifting. Every header is one act of kindness worth `header_value` — the beach ball's delight,
## paid on the bus, the combo climbing — and a count over his head. After `headers` of them he
## heads it back to you: it flies home the way the axe does, and left still held takes it again.
## If he is not under it when it comes down, it bounces off wherever it lands and the rally is over.
##
## Row: `lob_height`, `bounce_height`, `window`, `headers`, `header_value`, `hop`, `out_seconds`,
## `return_speed`, `return_accel`, `catch_radius`, `give_up_seconds`.

const RALLY := 50

## For the suites: headers this rally, and whether the last one went home.
var count := 0
var rallies := 0
var headed_home := false
var peak_height := 0.0

func _gravity_now() -> float:
	return _gravity * body.gravity_scale

## The top of his skull, where a header comes off.
func _head_top(him: Buddy) -> Vector2:
	var rect := him.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y)

func _ball_radius() -> float:
	if body.collider and body.collider.shape is CircleShape2D:
		return (body.collider.shape as CircleShape2D).radius * absf(body.collider.global_scale.x)
	return body.get_interaction_rect().size.y * 0.5

## The velocity that goes up to `apex_rise` over `top` and comes down on `top` from `from`.
func _arc_onto(from: Vector2, top: Vector2, apex_rise: float) -> Vector2:
	var g := maxf(_gravity_now(), 1.0)
	var r := _ball_radius()
	var land_y := top.y - r
	var apex_y := minf(land_y - apex_rise, from.y - 20.0)
	var up := sqrt(2.0 * g * maxf(from.y - apex_y, 1.0))
	var down := sqrt(2.0 * maxf(land_y - apex_y, 1.0) / g)
	var flight := up / g + down
	return Vector2((top.x - from.x) / maxf(flight, 0.05), -up)

func _on_press() -> void:
	_phase = RALLY
	_t = 0.0
	count = 0
	throw_hits = 0
	caught = false
	headed_home = false
	peak_height = 0.0
	_left_down = true
	_throwing = true
	_gravity_was = body.gravity_scale
	_cursor = hand_world()
	body._end_drag()
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	var from := com_world()
	var want := _arc_onto(from, _head_top(him), num("lob_height", 200.0)) if him else Vector2(0, -400)
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	last_throw_speed = want.length()
	rallies += 1
	set_process_input(true)
	run(true)
	sound(&"boing", -8.0, 0.8)
	AbilityCues.activation(self, from)
	# Something is coming to him to catch, head or wear: whatever routine he was in stands down.
	notice_player()
	AbilityCues.state(self, true, from)
	tell(&"lobbed", _head_top(him) if him else from)

func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	if _phase != RALLY:
		# The way home, and clearing him, are the Tomahawk's, which keeps its own clock.
		super._on_tick(delta)
		return
	_t += delta
	var him := buddy()
	if him == null or him.dragging or him.health == null or him.health.down:
		_rally_over()
		return
	var com := com_world()
	var top := _head_top(him)
	peak_height = maxf(peak_height, top.y - com.y)
	var v := body.linear_velocity
	var bottom := com.y + _ball_radius()
	if v.y > 0.0 and bottom >= top.y - 6.0:
		if absf(com.x - top.x) <= num("window", 46.0) and bottom <= top.y + 30.0:
			_header(him, top)
			return
		_rally_over()
		return
	if _t >= num("out_seconds", 2.5):
		_rally_over()

## He heads it: up it goes again, over where his head is now — or, the last one, home to you.
func _header(him: Buddy, top: Vector2) -> void:
	count += 1
	throw_hits += 1
	_t = 0.0
	var com := com_world()
	var at := Vector2(com.x, top.y)
	give(num("header_value", 3.0), at)
	notice_player()
	# He pops up to meet it: a small hop straight up, from the tick, before `StepStart` (D64).
	him.apply_central_impulse(Vector2(0.0, -num("hop", 170.0)) * him.mass)
	var fx := fx()
	if fx:
		fx.ring(at, 26.0 + 4.0 * count, WorldFX.kind_colour(body.juice_tier), 0.18, 2.0)
		fx.burst(at, &"heart", WorldFX.kind_colour(body.juice_tier), 2 + body.juice_tier, 100.0, 0.5)
	sound(&"boing", -6.0, 0.9 + 0.12 * float(count))
	tell(&"header", at)
	AbilityCues.payoff(self, &"header", at, "%d!" % count)
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	body.apply_torque_impulse(randf_range(-4.0, 4.0) * inertia)
	if count >= int(num("headers", 4)):
		# The last one goes back to the hand, headed hard toward it.
		headed_home = true
		var to := (_hand() - com).normalized()
		var want := to * num("return_speed", 900.0) * 0.6 + Vector2(0.0, -200.0)
		body.apply_central_impulse((want - body.linear_velocity) * body.mass)
		_turn_back()
		AbilityCues.state(self, false, at)
		return
	var up := _arc_onto(com, _head_top(him), num("bounce_height", 150.0))
	body.apply_central_impulse((up - body.linear_velocity) * body.mass)

## Not under it: it lands where it lands, and the rally is over.
func _rally_over() -> void:
	AbilityCues.state(self, false, com_world())
	_let_go()

func on_picked_up() -> void:
	if _active and body.dragging and _phase == RALLY:
		# Snatched out of the air.
		_throwing = false
		_phase = CLEAR
		_clear_t = 0.0
		AbilityCues.state(self, false, com_world())
	super.on_picked_up()
