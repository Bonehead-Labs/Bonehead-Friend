class_name DashAbility
extends WeaponAbility

## A lunge through him (D74): the katana's Iaido — the draw, one cut, and the cut lands late.
##
## Right while holding it: the blade glints for `draw_seconds`, then the **hand** lunges along
## the line through his middle to `overshoot` px past him (never more than `reach` from where it
## was) in `dash_seconds`, holds there for `hold_seconds` while the blade arrives, and comes back
## in `return_seconds`. The hand, not the blade: the drag
## joint carries the katana exactly as a fast cursor would (`BaseDraggable.hand_offset`), so it
## keeps its weight, lags the hand and swings through with its own inertia.
##
## **It goes through him.** For the lunge he and the blade do not collide
## (`add_collision_exception_with`), and the blade is swept for him instead: the path its point
## took and its own edge, each tick, as rays on his layer. The first frame either crosses him is
## the cut. Nothing happens to him then. `delay` seconds later — the moment every iaido film
## holds for — the line across him flashes and the cut lands: `cut_force`, scaled by how fast the
## point was moving (0.6x to 1.4x of `cut_speed`), billed through `Buddy.take_impulse` at the
## katana's own multiplier times `cut_mult`, and the same impulse shoves him along the cut.
## Applied from the tick, before `StepStart` (D64).
##
## The exception comes off once the blade is clear of him. A body that ends the lunge inside him
## would otherwise be thrown out of him by the solver (D61: a teleport must clear the colliders).
##
## Row: `draw_seconds`, `reach`, `overshoot`, `dash_seconds`, `hold_seconds`, `return_seconds`,
## `kick`, `delay`,
## `cut_force`, `cut_speed`, `cut_mult`, `shove`, `settle_seconds`.

const DRAW := 0
const DASH := 1
const BACK := 2
const SETTLE := 3
const HOLD := 4

var _phase := DRAW
var _t := 0.0
var _path := Vector2.ZERO
var _offset := Vector2.ZERO
var _last_tip := Vector2.INF
var _excepted: Buddy
## The cut: where it crossed him, which way, how fast the point was going, and how long until
## it lands (negative: none pending).
var _cut_at := Vector2.INF
var _cut_dir := Vector2.ZERO
var _cut_speed := 0.0
var _cut_in := -1.0
var _cut_done := false

## For the suites: the hand's furthest lunge, the blade's peak speed during it, and the impulse
## the cut handed him.
var last_lunge := 0.0
var last_peak_speed := 0.0
var last_cut := 0.0

func _can_start() -> bool:
	return buddy() != null

func is_cutting() -> bool:
	return _active and _phase != DRAW

func _on_press() -> void:
	var hand := hand_world()
	var him := him_world()
	var to := him - hand
	var length := minf(to.length() + num("overshoot", 70.0), num("reach", 280.0))
	_path = to.normalized() * length if to.length_squared() > 1.0 else Vector2.RIGHT * length
	_phase = DRAW
	_t = 0.0
	_cut_at = Vector2.INF
	_cut_in = -1.0
	_cut_done = false
	last_lunge = 0.0
	last_peak_speed = 0.0
	last_cut = 0.0
	run(true)
	threaten(true)
	sound(&"shing", -12.0, 0.75)
	var fx := fx()
	if fx:
		fx.ring(tip_world(), 12.0, Color.WHITE, 0.12, 2.0)

func _on_tick(delta: float) -> void:
	_t += delta
	match _phase:
		DRAW:
			if _t >= num("draw_seconds", 0.12):
				_begin_dash()
		DASH:
			var k := clampf(_t / maxf(num("dash_seconds", 0.1), 0.01), 0.0, 1.0)
			# Out fast and arriving: a lunge, not a glide.
			_set_offset(_path * (1.0 - pow(1.0 - k, 3.0)))
			_sweep()
			if k >= 1.0:
				_phase = HOLD
				_t = 0.0
		HOLD:
			# Zanshin: the hand stays out past him while the blade, a body on a soft joint, catches
			# up with it — without this the hand was on its way back before the blade had arrived.
			_sweep()
			if _t >= num("hold_seconds", 0.1):
				_phase = BACK
				_t = 0.0
		BACK:
			var k := clampf(_t / maxf(num("return_seconds", 0.18), 0.01), 0.0, 1.0)
			_set_offset(_path * (1.0 - k * k * (3.0 - 2.0 * k)))
			_sweep()
			if k >= 1.0:
				_set_offset(Vector2.ZERO)
				_phase = SETTLE
				_t = 0.0
		SETTLE:
			pass
	if _cut_in >= 0.0:
		_cut_in -= delta
		if _cut_in <= 0.0:
			_cut()
	if _phase == SETTLE and _cut_in < 0.0:
		if not overlaps_him() or _t >= num("settle_seconds", 1.0):
			finish()

func _begin_dash() -> void:
	_phase = DASH
	_t = 0.0
	threaten(false)
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	_last_tip = tip_world()
	# A snap along the lunge to start it clean; the joint does the rest.
	body.apply_central_impulse(_path.normalized() * body.mass * num("kick", 700.0))
	sound(&"shing", -6.0, 1.25)

## Every tick of the lunge: did the blade's point, or its edge, cross him?
func _sweep() -> void:
	var tip := tip_world()
	var speed := body.linear_velocity.length() + absf(body.angular_velocity) \
		* grip_world().distance_to(tip)
	last_peak_speed = maxf(last_peak_speed, speed)
	last_lunge = maxf(last_lunge, _offset.length())
	# The streak the blade leaves on the way out: at this speed it crosses him in two frames, and a
	# cut nobody saw is a cut that did not happen.
	if _phase == DASH and _last_tip != Vector2.INF:
		var fx := fx()
		if fx:
			fx.tracer(_last_tip, tip, Color.WHITE, 0.12, 4.0)
	if _cut_at == Vector2.INF:
		var hit := _ray(_last_tip, tip)
		if hit.is_empty():
			hit = _ray(grip_world(), tip)
		if not hit.is_empty():
			_cut_at = hit.get("position", tip)
			_cut_dir = _path.normalized()
			_cut_speed = speed
			_cut_in = num("delay", 0.3)
			# The pass: a thin line where the blade went, and nothing else — yet.
			var fx := fx()
			if fx:
				fx.tracer(_cut_at - _cut_dir * 44.0, _cut_at + _cut_dir * 44.0, Color.WHITE, 0.1, 1.0)
			# And it stays drawn on him for the held beat (D77), so the wait reads as a wait.
			_mark_cut(_cut_at, _cut_dir)
			tell(&"sliced", _cut_at)
	_last_tip = tip

func _cut() -> void:
	_cut_in = -1.0
	if _cut_done or _cut_at == Vector2.INF:
		return
	_cut_done = true
	var him := buddy()
	if him == null:
		return
	var at := him.get_interaction_rect().get_center()
	var share := clampf(_cut_speed / maxf(num("cut_speed", 1500.0), 1.0), 0.6, 1.4)
	last_cut = num("cut_force", 2600.0) * share
	strike(last_cut, _cut_dir, at, num("cut_mult", 1.0), num("shove", 0.6))
	if is_instance_valid(_cut_line):
		_cut_line.split()
	var fx := fx()
	if fx:
		# In its colour: a white cut across white bone is a cut only off the edges of him (D77).
		fx.tracer(at - _cut_dir * 70.0, at + _cut_dir * 70.0, accent(), 0.22, 4.0)
		fx.chips(at, accent(), 8, 300.0)
		fx.burst(at, &"bone", Color("f2ead8"), 3, 240.0)
		fx.shake(4.0)
	sound(&"shing", -4.0, 1.6)
	paid_off.emit(&"iaido")

func _set_offset(offset: Vector2) -> void:
	# The chase already ran this frame with the old offset: move the handle by the difference too,
	# so the hand is where the lunge says now and not a frame late.
	var delta := offset - _offset
	_offset = offset
	body.hand_offset = offset
	if body.dragging and body.handle:
		body.handle.global_position += delta

func _ray(from: Vector2, to: Vector2) -> Dictionary:
	if from == Vector2.INF or from.is_equal_approx(to) or not body.is_inside_tree():
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to, BUDDY_LAYER)
	query.hit_from_inside = true
	return body.get_world_2d().direct_space_state.intersect_ray(query)

func _on_dropped() -> void:
	# The lunge needs the hand; a pending cut does not — it already went through him. Either way it
	# settles rather than finishing on the spot: a blade let go inside him keeps its exception until
	# it is clear of him.
	_set_offset(Vector2.ZERO)
	_phase = SETTLE
	_t = 0.0

func _on_stop() -> void:
	_offset = Vector2.ZERO
	if body:
		body.hand_offset = Vector2.ZERO
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null
	if is_instance_valid(_cut_line) and not _cut_line.is_splitting():
		_cut_line.queue_free()
	_cut_line = null

var _cut_line: CutLine

## The line the blade drew across him, held on him through the beat before the cut lands (D77).
## His child, in his own frame, so it stays where it went through him however he moves.
func _mark_cut(at: Vector2, dir: Vector2) -> void:
	var him := buddy()
	if him == null:
		return
	if not is_instance_valid(_cut_line):
		_cut_line = CutLine.new()
		_cut_line.name = "IaidoCut"
		_cut_line.z_index = 3
		him.add_child(_cut_line)
	_cut_line.show_cut(him.to_local(at - dir * 46.0), him.to_local(at + dir * 46.0), accent())

## A thin cut in the ability's colour on a dark rim, a bright nick running along it while it waits;
## when the cut lands it flares wide and its two halves slide apart and shrink away. Never fades.
class CutLine extends Node2D:
	const WAIT_MAX := 0.8
	const FLARE := 0.06
	const PART := 0.22
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var colour := Color.WHITE
	var _t := 0.0
	var _split := -1.0

	func show_cut(a: Vector2, b: Vector2, tint: Color) -> void:
		from = a.round()
		to = b.round()
		colour = tint
		_t = 0.0
		_split = -1.0
		set_process(true)
		queue_redraw()

	func split() -> void:
		_split = 0.0

	func is_splitting() -> bool:
		return _split >= 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _split >= 0.0:
			_split += delta
			if _split >= FLARE + PART:
				queue_free()
				return
		elif _t >= WAIT_MAX:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var d := (to - from).normalized()
		if _split < 0.0:
			draw_line(from, to, AbilityFX.OUTLINE, 5.0)
			draw_line(from, to, colour, 3.0)
			# The nick of light running along it: the blade's path, still bright.
			var k := fmod(_t * 3.0, 1.0)
			var p := from.lerp(to, k)
			draw_line(p - d * 5.0, p + d * 5.0, colour.lightened(0.7), 3.0)
			return
		if _split < FLARE:
			draw_line(from, to, AbilityFX.OUTLINE, 9.0)
			draw_line(from, to, colour.lightened(0.4), 7.0)
			return
		var k := (_split - FLARE) / PART
		var mid := from.lerp(to, 0.5)
		var half := (to - from).length() * 0.5 * (1.0 - k)
		var apart := d * 30.0 * k
		for side in [-1.0, 1.0]:
			var centre: Vector2 = mid + apart * float(side) + d * half * 0.5 * float(side)
			var a := (centre - d * half * 0.5).round()
			var b := (centre + d * half * 0.5).round()
			draw_line(a, b, AbilityFX.OUTLINE, 5.0)
			draw_line(a, b, colour, 3.0)
