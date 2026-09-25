class_name Slinky
extends FidgetToy

## A slinky (D66).
##
## - **Left carries it by one end.** Hold right while carrying it and that end plants where it
##   is; the cursor now has the other end, and the coil is drawn between the two. **Let go of
##   right and it boings** — the planted end is let go and springs back into your hand.
## - **Right-drag it where it lies** and the same thing happens with the desk holding the other
##   end: pull, let go, and the far end springs back onto it.
## - **A boing pays** by how far it was stretched: an act, so the combo and the contracts see
##   it. A pull too short to be a stretch pays nothing and does not boing.
## - **Throw it and it walks**: it lands, and goes end over end across the desk a few steps,
##   the way a slinky does down stairs. A step is the toy running on its own, so it trickles.
## - **He boings it himself**: a pluck, and it wobbles back.
##
## Nothing here runs a frame at rest. `_process` runs only while a coil is being drawn — a
## stretch, a spring-back, a step — and switches itself off when the slinky is a stack again.

## The ring sprites the coil is drawn with, under one node that lives in the world's space.
## Wired by the seed tool: one ring per colour, repeated.
@export var coil: Node2D
## Kindness value of a full boing, before the item's own value node. A short one is a quarter.
@export var boing_value: float = 6.0
## World px of stretch that pays a full boing, before the "time between uses" node — "Looser
## Coil" makes a full boing a shorter pull.
@export var full_stretch: float = 170.0
## The furthest the coil goes, world px. Past it the far end stops following the cursor.
@export var max_stretch: float = 260.0
## One end-over-end step: its value, its length and how long it takes.
@export var walk_value: float = 0.5
@export var walk_span: float = 34.0
@export var step_seconds: float = 0.3

## Shorter than this is a tap, not a stretch: it neither boings nor pays.
const MIN_STRETCH := 24.0
## Closer than this, the coil is a stack again.
const COMPACT := 10.0
## The spring the far end comes home on, when nothing is holding the other end: stiff and
## underdamped, so it overshoots once and settles — which is the boing.
const SPRING_K := 190.0
const SPRING_DAMP := 9.0
## A throw at least this fast walks, one step per this much speed, up to MAX_STEPS.
const WALK_SPEED := 260.0
const SPEED_PER_STEP := 300.0
const MAX_STEPS := 4
## His pluck: how far and how fast the far end leaves, and the share of a full boing it pays.
const HIS_PLUCK := 90.0
const HIS_SHARE := 0.4

enum Mode { NONE, STRETCH, HOME_TO_HAND, SPRING, STEP }

var _mode := Mode.NONE
## The far end, in the world.
var _far := Vector2.ZERO
## The spring's end relative to the body, and its velocity, while springing back.
var _rel := Vector2.ZERO
var _rel_v := Vector2.ZERO
## Steps still to take, which way, and where this one started.
var _steps_left := 0
var _step_dir := 1.0
var _step_from := Vector2.ZERO
var _step_t := 0.0
## Set when the player lets go of it and cleared when it lands: the next landing walks.
var _thrown_speed := 0.0
var _thrown_dir := 0.0
var _awaiting_landing := false
var _rings: Array[Sprite2D] = []

## Boings paid, for the suite and the F3 overlay. Never read by the simulation.
var boings := 0
var steps_walked := 0

func _ready() -> void:
	super._ready()
	set_process(false)
	if coil:
		for child in coil.get_children():
			if child is Sprite2D:
				_rings.append(child)
		coil.top_level = true
		coil.visible = false

func stretching() -> bool:
	return _mode == Mode.STRETCH

func is_compact() -> bool:
	return _mode == Mode.NONE

func is_walking() -> bool:
	return _mode == Mode.STEP

## How far the far end is from the planted one, world px. Zero as a stack.
func stretch() -> float:
	if _mode == Mode.STRETCH or _mode == Mode.HOME_TO_HAND:
		return global_position.distance_to(_far)
	if _mode == Mode.SPRING:
		return _rel.length()
	return 0.0

# --- the hand ------------------------------------------------------------------

func _on_gesture(g: GestureZones.Gesture) -> void:
	match g.kind:
		GestureZones.ACTION:
			_plant(g.world)
		GestureZones.PRESS:
			if g.button == MOUSE_BUTTON_RIGHT and g.zone == &"coil":
				_plant(g.world)
		GestureZones.DRAG, GestureZones.CARRY:
			if _mode == Mode.STRETCH:
				_pull_to(g.world)
		GestureZones.ACTION_END:
			_let_go()
		GestureZones.RELEASE:
			if g.button == MOUSE_BUTTON_RIGHT:
				_let_go()

## The end it is held by stays where it is, and the cursor has the other one.
func _plant(at: Vector2) -> void:
	if _mode == Mode.STRETCH:
		return
	_stop_walking()
	_mode = Mode.STRETCH
	freeze = true
	_awaiting_landing = false
	_pull_to(at)
	AudioManager.play(&"squeak", 0.05, -16.0, 0.6)
	set_process(true)

func _pull_to(at: Vector2) -> void:
	var offset := at - global_position
	_far = global_position + offset.limit_length(max_stretch)
	_lay(global_position, _far)

## Right comes up: a boing, if it was a stretch. In the hand the planted end is let go and the
## joint springs it home; on the desk the far end springs back onto it.
func _let_go() -> void:
	if _mode != Mode.STRETCH:
		return
	var length := global_position.distance_to(_far)
	freeze = false
	if length < MIN_STRETCH:
		_compact()
		return
	_boing(length, true)
	if dragging and handle:
		_mode = Mode.HOME_TO_HAND
	else:
		_spring_from(_far - global_position, Vector2.ZERO)

func _boing(length: float, by_player: bool) -> void:
	boings += 1
	var share := clampf(length / _full_stretch(), 0.0, 1.0)
	var value := boing_value * (0.25 + 0.75 * share)
	AudioManager.play(&"boing", 0.06, lerpf(-12.0, -4.0, share), lerpf(1.25, 0.85, share))
	chips(global_position + Vector2(0, -16), &"heart", 2 + int(round(4.0 * share)), 90.0)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	if by_player:
		pay_act(value, global_position, &"boing")
	else:
		pay_sustained(value * HIS_SHARE, global_position)
		fidget(&"boing")

func _full_stretch() -> float:
	return maxf(MIN_STRETCH * 2.0, full_stretch * upgrade(&"cooldown_mult"))

func _spring_from(rel: Vector2, velocity: Vector2) -> void:
	_mode = Mode.SPRING
	_rel = rel
	_rel_v = velocity
	set_process(true)

## Back to a stack: the drawn picture, and no frame of its own.
func _compact() -> void:
	_mode = Mode.NONE
	if coil:
		coil.visible = false
	if sprite:
		sprite.visible = true
	set_process(false)

# --- picked up, let go -----------------------------------------------------------

func _start_drag() -> void:
	# Taken off the desk mid-stretch or mid-step: it is a stack in your hand.
	if _mode == Mode.SPRING or _mode == Mode.STEP:
		_stop_walking()
		freeze = false
		_compact()
	_awaiting_landing = false
	super._start_drag()

func _end_drag() -> void:
	var was := dragging
	super._end_drag()
	# Let go of mid-boing: there is no hand to spring into, so the far end springs back onto
	# the body instead, wherever it lands.
	if _mode == Mode.HOME_TO_HAND:
		_spring_from(_far - global_position, Vector2.ZERO)
	if was and _mode == Mode.NONE:
		_thrown_speed = absf(linear_velocity.x)
		_thrown_dir = signf(linear_velocity.x)
		_awaiting_landing = _thrown_speed >= WALK_SPEED

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _awaiting_landing or freeze:
		return
	# Landed: touching something and no longer going up. A slinky that lands walks on.
	if get_contact_count() > 0 and linear_velocity.y > -5.0 and absf(linear_velocity.y) < 120.0:
		_awaiting_landing = false
		var steps := clampi(int(_thrown_speed / SPEED_PER_STEP), 1, MAX_STEPS)
		walk(steps, _thrown_dir)

# --- walking --------------------------------------------------------------------

## End over end, `steps` times, toward `direction`. At Focus Off nothing on the desk moves that
## the player did not move (D21), so it simply stays where it landed.
func walk(steps: int, direction: float) -> void:
	if steps <= 0 or not animating() or _mode != Mode.NONE:
		return
	_steps_left = steps
	_step_dir = -1.0 if direction < 0.0 else 1.0
	_next_step()

func _next_step() -> void:
	if _steps_left <= 0 or not is_inside_tree():
		_stop_walking()
		return
	# Only where there is room: a wall, a toy or him in the way ends the walk.
	var span := Vector2(_step_dir * walk_span, 0.0)
	if test_move(global_transform, span):
		_stop_walking()
		return
	_steps_left -= 1
	_mode = Mode.STEP
	freeze = true
	_step_from = global_position
	_step_t = 0.0
	set_process(true)

func _stop_walking() -> void:
	_steps_left = 0
	if _mode == Mode.STEP:
		freeze = false
		_compact()

## One step's far end: up and over, from the back of the stack to a span in front of it.
func _step_end(t: float) -> Vector2:
	var radius := walk_span * 0.5
	var centre := _step_from + Vector2(_step_dir * radius, 0.0)
	return centre + Vector2(-_step_dir * radius * cos(PI * t), -radius * 1.3 * sin(PI * t))

func _land_step() -> void:
	global_position = _step_from + Vector2(_step_dir * walk_span, 0.0)
	steps_walked += 1
	pay_sustained(walk_value, global_position)
	AudioManager.play(&"boing", 0.1, -18.0, 1.5)
	freeze = false
	_compact()
	if _steps_left > 0:
		_next_step()

# --- the coil ---------------------------------------------------------------------

func _process(delta: float) -> void:
	match _mode:
		Mode.STRETCH:
			_lay(global_position, _far)
		Mode.HOME_TO_HAND:
			if not dragging or handle == null:
				_spring_from(_far - global_position, Vector2.ZERO)
				return
			_far = handle.global_position
			if global_position.distance_to(_far) <= COMPACT:
				_compact()
				return
			_lay(global_position, _far)
		Mode.SPRING:
			# A damped spring on the far end, in the body's own space, so a slinky that is falling
			# while it boings still boings onto itself.
			_rel_v += (-SPRING_K * _rel - SPRING_DAMP * _rel_v) * delta
			_rel += _rel_v * delta
			if _rel.length() <= 3.0 and _rel_v.length() <= 40.0:
				_compact()
				return
			_lay(global_position, global_position + _rel)
		Mode.STEP:
			_step_t += delta / maxf(step_seconds, 0.05)
			if _step_t >= 1.0:
				_land_step()
				return
			_lay(_step_from, _step_end(_step_t))
		_:
			set_process(false)

## The rings from `a` to `b` along a curve that sags the way a stretched spring does: more the
## more sideways it is pulled. Each ring stands across the curve, and the six colours repeat in
## the stack's own order, so a stretched slinky is its stack pulled apart.
func _lay(a: Vector2, b: Vector2) -> void:
	if coil == null or _rings.is_empty():
		return
	var span := a.distance_to(b)
	if span <= COMPACT:
		coil.visible = false
		if sprite:
			sprite.visible = true
		return
	if sprite:
		sprite.visible = false
	coil.visible = true
	var sag := Vector2(0.0, 0.22 * absf(b.x - a.x))
	var control := (a + b) * 0.5 + sag
	var count := _rings.size()
	for i in count:
		var t := float(i) / float(count - 1)
		var ring := _rings[i]
		var at := _bezier(a, control, b, t)
		var tangent := _bezier_tangent(a, control, b, t)
		ring.global_position = at.round()
		ring.global_rotation = tangent.angle() + PI * 0.5 if tangent.length_squared() > 0.0 else 0.0

static func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + c * 2.0 * u * t + b * t * t

static func _bezier_tangent(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return (c - a) * 2.0 * (1.0 - t) + (b - c) * 2.0 * t

# --- him --------------------------------------------------------------------------

func idle_appeal() -> float:
	# A pluck every think tick, at his share of a full boing.
	return boing_value * HIS_SHARE / IdleBrain.THINK_SECONDS

## He plucks the top of it and it wobbles back: the far end leaves at speed and the spring
## brings it home. At Focus Off he is simply there and it pays without moving (D36).
func idle_use(him: Buddy) -> void:
	if _mode != Mode.NONE or dragging:
		return
	if not animating():
		pay_sustained(boing_value * HIS_SHARE * (0.25 + 0.75 * HIS_PLUCK / _full_stretch()), global_position)
		return
	var toward := signf(him.global_position.x - global_position.x)
	var out := Vector2(toward * 0.5, -1.0).normalized() * HIS_PLUCK
	_boing(HIS_PLUCK, false)
	_spring_from(Vector2.ZERO, out * sqrt(SPRING_K))
