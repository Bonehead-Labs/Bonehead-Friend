class_name VortexPower
extends CursorPowerBase

## The gravity vortex: hold the button and everything loose on the desk — Bonehead
## included — is dragged toward the cursor and wound around it.
##
## It deals no damage of its own. All of it is collateral: bodies accelerate, hit each
## other and hit him, and the contact solver reports those impulses through exactly the
## pipeline a bat swing uses. That is why this is a physics toy rather than a weapon with
## numbers — the funnier the pile-up, the better it pays, and nothing here had to be told
## how much a collision is worth.
##
## **What it earns under its own name is the world** (D65). A prop it throws into him is
## billed to the prop, as it always was; an impact with the floor or a wall while it has hold
## of him, or just after, is billed to the vortex — `Buddy.claim_impacts`. That is the
## difference between a power with a mastery track and a capstone, and one whose payout and
## damage nodes nothing could ever read.
##
## Bodies are found by **group**, not by a physics query: every draggable joins
## `GROUP_INTERACTIVE` on ready, the buddy joins `GROUP_BUDDY`, and the item limit caps the
## desk at a couple of dozen bodies — so a walk of two small groups is cheaper than a shape
## query every frame, and it cannot silently miss a body whose layer someone changed.

## Pull at the eye, as an **acceleration** in px/s² — every body in reach is pulled by its own
## mass times this, the way gravity pulls (D65). It was a force of 2,400, the same for a 0.3 kg
## prop and a 3 kg skeleton, so it hurled the props and never moved him: standing on the desk
## he is held by `1.0 x 3 x 980 = 2,940` of friction, which it never reached anywhere in its
## radius. In gravities this is about four at the eye.
@export var pull_accel: float = 4000.0

## How far the pull reaches.
@export var radius: float = 260.0

## Sideways pull as a fraction of the inward one. This is what turns a heap into a *spin*:
## pure attraction collapses everything onto one point and stops, which looks like a bug
## rather than a black hole.
@export var swirl: float = 0.55

## Drag inside the well, per second, strongest at the eye, on a body's speed *relative to the
## eye*. The swirl adds energy on every frame and nothing else takes it out, so without this
## an orbit only ever widens until the body leaves the rim at speed: a vortex that flings
## rather than gathers. With it, nothing spins faster than `pull_accel x swirl / drag`, the
## knot stays inside the well — and because it is measured against the eye rather than the
## desk, the knot travels with the cursor instead of being left behind by it.
@export var drag: float = 6.0

## How long after the pull lets go an impact with the world is still the vortex's doing: a fall
## of 1,900 px, the height of the tallest monitor it can be let go at the top of.
const CLAIM_SECONDS := 2.0

## The fastest the eye is taken to be moving, for the drag. A cursor that jumps — a window
## re-entered, a monitor crossed — would otherwise hand the knot its whole jump as velocity.
const EYE_SPEED_MAX := 1500.0

var _pulling := false
var _aim := Vector2.ZERO
var _last_aim := Vector2.ZERO
var _eye_velocity := Vector2.ZERO
var _swirl: GPUParticles2D

func _on_activated() -> void:
	set_physics_process(true)

func _on_deactivated() -> void:
	set_physics_process(false)
	_pulling = false
	if _swirl:
		_swirl.emitting = false

func release_hold() -> void:
	_pulling = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim = (event as InputEventMouseMotion).position
	if not _pulling:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_pulling = false

func fire(at: Vector2) -> void:
	_aim = at
	_last_aim = at
	_eye_velocity = Vector2.ZERO
	_pulling = true
	# The eye of it: chips circling the cursor while it pulls, more and hotter with the tier.
	if _swirl == null or not is_instance_valid(_swirl):
		var fx := WorldFX.of(self)
		if fx:
			var tier := Progression.juice_tier(item_id)
			_swirl = fx.aura(self, &"chip", WorldFX.harm_colour(tier), 10 + 6 * tier, "Swirl",
				Vector2(radius * 0.45, radius * 0.45), 2.2 + 0.4 * float(tier))
	if _swirl:
		_swirl.global_position = at
		_swirl.emitting = Settings.focus_intensity != Settings.Intensity.OFF

## The pull at the eye with the player's "Faster Collapse" levels in it.
func effective_pull() -> float:
	return pull_accel * Progression.get_modifier(item_id, &"pull_mult")

func _physics_process(delta: float) -> void:
	if not active or not _pulling:
		if _swirl:
			_swirl.emitting = false
		return
	if _swirl:
		_swirl.global_position = _aim
	# Smoothed over a couple of frames: motion events arrive when they arrive, not once a tick.
	var moved := (_aim - _last_aim) / maxf(delta, 0.0001)
	_last_aim = _aim
	_eye_velocity = _eye_velocity.lerp(moved.limit_length(EYE_SPEED_MAX), 0.5)
	var pull := effective_pull()
	for body in _bodies():
		var to_centre := _aim - body.global_position
		var distance := to_centre.length()
		if distance > radius or distance < 0.01:
			continue
		# Linear, not the square every blast uses. A blast is an instant; a well is held, and
		# under the square its outer half pulled at under a quarter of its strength — a vortex
		# held beside him was a suggestion.
		var falloff := 1.0 - distance / radius
		var inward := to_centre / distance
		var accel := (inward + inward.orthogonal() * swirl) * pull * falloff \
			- (body.linear_velocity - _eye_velocity) * drag * falloff
		# A force per physics step is already time-integrated by the solver; it is scaled by
		# the body's own mass so a skeleton and a pencil fall in together.
		body.apply_central_force(accel * body.mass)
		if body is Buddy:
			(body as Buddy).claim_impacts(item_id, effective_damage_mult(), CLAIM_SECONDS)

func _bodies() -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		var body := node as RigidBody2D
		# A body being dragged is pinned to its handle joint; pulling on it fights the
		# player's own mouse and reads as the toy being broken.
		if body and not body.freeze and not (body is BaseDraggable and (body as BaseDraggable).dragging):
			out.append(body)
	return out
