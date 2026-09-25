class_name StressBall
extends FidgetToy

## A stress ball (D57).
##
## - **Hold it, then hold right to squeeze.** It squashes as the charge builds — scaled a
##   little at first, then swapped for its own hand-drawn squashed frame, because a pixel face
##   stretched to 125% is mush. **Let go of right** and it springs back and pays by how hard
##   it was squeezed.
## - **Throw it at him and he catches it**: it sticks to him for a moment while he looks
##   pleased with himself, then he tosses it back up. Only a throw pays — the ball has to
##   have left the player's hand — so a ball that falls back on him is not an income.
## - Left alone with it, he gives it a squeeze himself.

## The squashed frame, hidden until a squeeze is most of the way there. Wired by the seed tool.
@export var squeeze_sprite: Sprite2D
## Kindness value of a full squeeze, before the item's own value node. A tap of a squeeze is a
## quarter of it.
@export var squeeze_value: float = 5.0
## Seconds of holding to reach a full squeeze, before the "time between uses" node.
@export var full_squeeze_seconds: float = 1.0
## A catch: its value, how fast it must be moving, and how long he holds on.
@export var catch_value: float = 10.0
@export var min_catch_speed: float = 240.0
@export var catch_seconds: float = 0.9

## The charge at which the drawn squashed frame takes over from the scaled round one.
const SWAP_AT := 0.6

var charge := 0.0
var _squeezing := false
## Set when the player lets go of it, cleared by a catch — the one flag between "thrown" and
## "fell on him".
var _thrown := false
var _catch_joint: PinJoint2D
var _base_scale := Vector2.ONE
var _squish: Tween

func _ready() -> void:
	super._ready()
	set_process(false)
	if sprite:
		_base_scale = sprite.scale
	if squeeze_sprite:
		squeeze_sprite.visible = false
	body_entered.connect(_on_body_entered)

func is_squeezing() -> bool:
	return _squeezing

func is_caught() -> bool:
	return _catch_joint != null

func _on_gesture(g: GestureZones.Gesture) -> void:
	match g.kind:
		GestureZones.ACTION:
			_squeezing = true
			charge = 0.0
			AudioManager.play(&"squeak", 0.1, -12.0, 0.8)
			set_process(true)
		GestureZones.ACTION_END:
			_let_go(g.seconds)

func _process(_delta: float) -> void:
	if not _squeezing or gestures == null:
		set_process(false)
		return
	charge = clampf(gestures.action_seconds() / _full_seconds(), 0.0, 1.0)
	_show_squash(charge)

func _full_seconds() -> float:
	return maxf(0.1, full_squeeze_seconds * upgrade(&"cooldown_mult"))

## How squashed it looks at a charge, 0..1. Scaled up to the swap, the drawn frame after it.
func _show_squash(amount: float) -> void:
	if sprite == null:
		return
	var drawn := squeeze_sprite != null and amount >= SWAP_AT
	sprite.visible = not drawn
	if squeeze_sprite:
		squeeze_sprite.visible = drawn
	var k := minf(amount, SWAP_AT) / SWAP_AT
	sprite.scale = _base_scale * Vector2(1.0 + 0.12 * k, 1.0 - 0.18 * k)

func _let_go(seconds: float) -> void:
	if not _squeezing:
		return
	_squeezing = false
	set_process(false)
	charge = clampf(seconds / _full_seconds(), 0.0, 1.0)
	var paid := squeeze_value * (0.25 + 0.75 * charge)
	pay_act(paid, global_position)
	AudioManager.play(&"squeak", 0.05, lerpf(-12.0, -4.0, charge), 1.0 + 0.4 * charge)
	chips(global_position + Vector2(0, -12), &"heart", 2 + int(round(4.0 * charge)), 80.0)
	_spring_back()

func _spring_back() -> void:
	if sprite == null:
		return
	if squeeze_sprite:
		squeeze_sprite.visible = false
	sprite.visible = true
	if _squish and _squish.is_valid():
		_squish.kill()
	if not animating():
		sprite.scale = _base_scale
		return
	sprite.scale = _base_scale * Vector2(0.9, 1.12)
	_squish = create_tween()
	_squish.tween_property(sprite, "scale", _base_scale, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# --- the catch ---------------------------------------------------------------------

func _end_drag() -> void:
	var was := dragging
	super._end_drag()
	# Dropping it mid-squeeze ends the squeeze where it was (GestureZones sends ACTION_END),
	# and letting go of it at all is what makes the next contact a throw.
	if was:
		_thrown = true

## How fast it has been going lately: the peak, fading by a third a frame.
##
## Not FriendlyBase's `_previous_speed`, one frame back. The contact monitor reports the
## buddy a physics step *after* the step that stopped the ball, so by the time `body_entered`
## fires the ball has been standing still for a frame and a one-frame memory reads a 900 px/s
## throw as 36. Measured, not guessed: that is exactly what the suite saw.
var _recent_speed := 0.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_recent_speed = maxf(linear_velocity.length(), _recent_speed * 0.66)

## He is hit by it at speed, after the player let go of it: he catches it.
func _on_body_entered(other: Node) -> void:
	var him := other as Buddy
	if him == null or not _thrown or dragging or _catch_joint != null:
		return
	if _recent_speed < min_catch_speed:
		return
	_thrown = false
	# Not inside the physics callback: a joint added mid-flush is a joint the solver has
	# half-heard of.
	_catch.call_deferred(him)

func _catch(him: Buddy) -> void:
	if not is_instance_valid(him) or _catch_joint != null or not is_inside_tree():
		return
	_catch_joint = PinJoint2D.new()
	_catch_joint.name = "Catch"
	_catch_joint.softness = 0.0
	add_child(_catch_joint)
	_catch_joint.node_a = get_path()
	_catch_joint.node_b = him.get_path()
	pay_act(catch_value, global_position, &"caught")
	AudioManager.play(&"squeak", 0.1, -8.0, 1.2)
	get_tree().create_timer(catch_seconds).timeout.connect(_toss)

## He lets go and lobs it up, a little to one side. It is no longer a throw, so it does not pay
## when it comes down on him.
func _toss() -> void:
	if _catch_joint == null:
		return
	_catch_joint.queue_free()
	_catch_joint = null
	if dragging:
		return
	var side := -1.0 if randf() < 0.5 else 1.0
	apply_central_impulse(Vector2(side * 90.0, -380.0) * mass)

# --- him ------------------------------------------------------------------------

func idle_appeal() -> float:
	return squeeze_value * 0.5 / IdleBrain.THINK_SECONDS

## A squeeze of his own: half strength, and the trickle rather than the act. At Focus Off it
## is paid without the ball visibly moving (D36).
func idle_use(_him: Buddy) -> void:
	pay_sustained(squeeze_value * 0.5, global_position)
	if not animating() or sprite == null:
		return
	AudioManager.play(&"squeak", 0.1, -14.0, 0.9)
	if _squish and _squish.is_valid():
		_squish.kill()
	_squish = create_tween()
	_squish.tween_property(sprite, "scale", _base_scale * Vector2(1.12, 0.82), 0.18)
	_squish.tween_property(sprite, "scale", _base_scale, 0.25) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
