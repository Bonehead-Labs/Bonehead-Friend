class_name NewtonsCradle
extends FidgetToy

## A Newton's cradle (D66).
##
## - **Right-drag an end ball out and let go.** It swings back into the row, and the ball at
##   the other end answers; then back again, each clack a little softer than the last, for
##   the best part of half a minute.
## - **Every clack is a tiny Hearts tick**, and a clack sound. It is the toy running on its
##   own after the player started it, so it trickles rather than acting — the player's own act
##   was the pull, and that is what the contract board counts.
## - **He watches it**, and it calms him: near enough to see it, he settles into a blissful
##   stare for as long as it clacks. Left alone with a still one, he pulls a ball himself.
##
## The balls are not physics bodies. Five pendulums touching in a row are a famously hard thing
## to simulate and a trivially easy thing to animate: only the two end balls ever move, one at a
## time, and the energy that leaves one arrives at the other. So the swing is a clock, not a
## solver — `_process` runs only while it swings and switches itself off when it has stopped.

## The five ball sprites, in slot order left to right, each pivoted at the top of its string.
## Wired by the seed tool.
@export var balls: Node2D
## Kindness value of a full-height clack, before the item's own value node.
@export var clack_value: float = 0.6
## Seconds for an end ball to swing out and back: a clack every this long.
@export var swing_seconds: float = 0.52
## Share of the swing kept at each clack, before the "time between uses" node.
@export var restitution: float = 0.9
## How near he has to be to watch it.
@export var watch_range: float = 380.0

## The furthest an end ball can be pulled.
const MAX_PULL := deg_to_rad(60.0)
## Below this the swing is over.
const STOP_ANGLE := deg_to_rad(2.5)
## A pull shorter than this is a nudge, and does nothing.
const MIN_PULL := deg_to_rad(4.0)
## His own pull: a modest one.
const HIS_PULL := deg_to_rad(32.0)
const ART_SCALE := 2.0

## -1 while the left end ball is the one moving, +1 the right, 0 at rest.
var _moving := 0
var _amplitude := 0.0
var _t := 0.0
## The first half-swing, from the pull back into the row, is a quarter period, not a half.
var _returning := false
## The end the player has hold of: -1 left, +1 right, 0 none.
var _pulling := 0
var _by_player := true
var _balls: Array[Node2D] = []

## Clacks since spawn, for the suite. Never read by the simulation.
var clacks := 0

func _ready() -> void:
	super._ready()
	set_process(false)
	if balls:
		for child in balls.get_children():
			if child is Node2D:
				_balls.append(child)

func is_swinging() -> bool:
	return _moving != 0

func amplitude() -> float:
	return _amplitude

## The angle a ball is at, radians; positive swings it left.
func ball_angle(slot: int) -> float:
	return _balls[slot].rotation if slot >= 0 and slot < _balls.size() else 0.0

# --- the hand ------------------------------------------------------------------

func _on_gesture(g: GestureZones.Gesture) -> void:
	if g.button != MOUSE_BUTTON_RIGHT:
		return
	var side := -1 if g.zone == &"ball_l" else (1 if g.zone == &"ball_r" else 0)
	match g.kind:
		GestureZones.PRESS:
			if side != 0:
				_stop()
				_pulling = side
		GestureZones.DRAG:
			if _pulling != 0:
				_set_end(_pulling, _pull_angle(_pulling, g.at))
		GestureZones.RELEASE:
			if _pulling != 0:
				var angle := absf(ball_angle(_end_slot(_pulling)))
				var side_pulled := _pulling
				_pulling = 0
				# Focus lost with a ball held out is not a let-go (D70): it goes back to the row.
				if angle >= MIN_PULL and not g.cancelled:
					release(side_pulled, angle, true)
				else:
					_set_end(side_pulled, 0.0)

## Where the cursor puts the end ball: the angle of the cursor about the top of its string,
## outward only, and never past `MAX_PULL`. In art px in the toy's own frame, so a cradle lying
## on its side is still pulled along its own string.
func _pull_angle(side: int, at: Vector2) -> float:
	var ball := _balls[_end_slot(side)] if not _balls.is_empty() else null
	if ball == null:
		return 0.0
	var pivot := ball.position / ART_SCALE
	var v := at - pivot
	if v.length_squared() < 1.0:
		return 0.0
	# Straight down is zero; out to the left is positive (a clockwise turn as drawn).
	var angle := atan2(-v.x, v.y)
	if side < 0:
		return clampf(angle, 0.0, MAX_PULL)
	return clampf(angle, -MAX_PULL, 0.0)

func _end_slot(side: int) -> int:
	return 0 if side < 0 else _balls.size() - 1

func _set_end(side: int, angle: float) -> void:
	if _balls.is_empty():
		return
	_balls[_end_slot(side)].rotation = angle

## Lets go of an end ball at `angle` (radians, unsigned): it swings back into the row and the
## clacking starts.
func release(side: int, angle: float, by_player: bool) -> void:
	if _balls.is_empty():
		return
	_amplitude = clampf(angle, 0.0, MAX_PULL)
	_moving = -1 if side < 0 else 1
	_returning = true
	_t = 0.0
	_by_player = by_player
	_set_end(_moving, _signed(_moving, _amplitude))
	if by_player:
		EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	set_process(true)

## Outward is positive on the left and negative on the right.
static func _signed(side: int, angle: float) -> float:
	return angle if side < 0 else -angle

func _stop() -> void:
	_moving = 0
	_amplitude = 0.0
	for ball in _balls:
		ball.rotation = 0.0
	set_process(false)

# --- the swing -------------------------------------------------------------------

func _process(delta: float) -> void:
	if _moving == 0:
		set_process(false)
		return
	_t += delta
	var half := maxf(swing_seconds, 0.1)
	if _returning:
		# From the pull back into the row: a quarter of a period.
		var k := _t / (half * 0.5)
		if k >= 1.0:
			_clack()
			return
		_set_end(_moving, _signed(_moving, _amplitude * cos(PI * 0.5 * k)))
		return
	var k := _t / half
	if k >= 1.0:
		_clack()
		return
	_set_end(_moving, _signed(_moving, _amplitude * sin(PI * k)))

## The moving ball meets the row. What it brings goes out through the other end, a little less
## of it each time.
func _clack() -> void:
	_set_end(_moving, 0.0)
	clacks += 1
	var share := _amplitude / MAX_PULL
	AudioManager.play(&"clack", 0.05, lerpf(-22.0, -8.0, share), 1.0 + 0.1 * (1.0 - share))
	pay_sustained(clack_value * share, _ball_world(_moving))
	if _he_is_watching():
		fidget(&"clacking")
	_amplitude *= _kept()
	_returning = false
	_t = 0.0
	if _amplitude < STOP_ANGLE:
		_stop()
		return
	_moving = -_moving

## Share of the swing kept per clack. "Harder Steel" (`cooldown_mult` < 1) loses less of it, so
## the same pull clacks for longer.
func _kept() -> float:
	var loss := (1.0 - restitution) * upgrade(&"cooldown_mult")
	return clampf(1.0 - loss, 0.0, 0.99)

func _ball_world(side: int) -> Vector2:
	if _balls.is_empty():
		return global_position
	var ball := _balls[_end_slot(side)] as Node2D
	return ball.to_global(Vector2(0, 14))

func _he_is_watching() -> bool:
	var him := buddy()
	if him == null or him.dragging:
		return false
	if him.state == &"knockout" or him.state == &"pile" or him.state == &"reassemble":
		return false
	return him.global_position.distance_to(global_position) <= watch_range

# --- him --------------------------------------------------------------------------

## What one of his pulls pays over its whole swing, spread over the swing: the clacks form a
## geometric series, and it lasts about as many clacks as it takes to fall from his pull to
## `STOP_ANGLE`.
##
## **The same whether it is swinging or not** (D70). Zero is the brain's "nothing to do here"
## (D57), and a swinging cradle is not that: he goes over, watches it clack, and pulls a ball
## himself once it has stopped — `idle_use` is what declines while it swings. It quoted zero
## while swinging, so a cradle he set going on his last tick at it was still "nothing" the
## moment he looked round for a toy, and brain_check's return found he never came back.
func idle_appeal() -> float:
	var kept := clampf(restitution, 0.01, 0.99)
	var total := clack_value * (HIS_PULL / MAX_PULL) / (1.0 - kept)
	var clacks_long := log(STOP_ANGLE / HIS_PULL) / log(kept)
	return total / maxf(1.0, clacks_long * swing_seconds)

## He pulls the ball nearer him and lets it go, then watches. At Focus Off nothing on the desk
## moves that the player did not move (D36): the same rate, paid quietly per think tick.
func idle_use(him: Buddy) -> void:
	if is_swinging() or _pulling != 0:
		return
	if not animating():
		pay_sustained(idle_appeal() * IdleBrain.THINK_SECONDS, global_position)
		return
	var side := -1 if him.global_position.x < global_position.x else 1
	release(side, HIS_PULL, false)
