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
## Bodies are found by **group**, not by a physics query: every draggable joins
## `GROUP_INTERACTIVE` on ready, the buddy joins `GROUP_BUDDY`, and the item limit caps the
## desk at a couple of dozen bodies — so a walk of two small groups is cheaper than a shape
## query every frame, and it cannot silently miss a body whose layer someone changed.

## Pull at the centre, in force units. Falls off with distance like a blast does.
@export var pull_force: float = 2400.0

## How far the pull reaches.
@export var radius: float = 260.0

## Sideways force as a fraction of the inward pull. This is what turns a heap into a
## *spin*: pure attraction collapses everything onto one point and stops, which looks like
## a bug rather than a black hole.
@export var swirl: float = 0.55

var _pulling := false
var _aim := Vector2.ZERO
var _swirl: GPUParticles2D

func _on_activated() -> void:
	set_physics_process(true)

func _on_deactivated() -> void:
	set_physics_process(false)
	_pulling = false
	if _swirl:
		_swirl.emitting = false

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

func _physics_process(delta: float) -> void:
	if not active or not _pulling:
		if _swirl:
			_swirl.emitting = false
		return
	if _swirl:
		_swirl.global_position = _aim
	for body in _bodies():
		var to_centre := _aim - body.global_position
		var distance := to_centre.length()
		if distance > radius or distance < 0.01:
			continue
		# Squared falloff, the same shape every blast in the game uses — near the eye the
		# pull is violent, at the rim it is a suggestion.
		var falloff := 1.0 - distance / radius
		var inward := to_centre.normalized() * pull_force * falloff * falloff
		var tangent := to_centre.normalized().orthogonal() * pull_force * falloff * swirl
		body.apply_central_force((inward + tangent) * delta * 60.0)

func _bodies() -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		var body := node as RigidBody2D
		# A body being dragged is pinned to its handle joint; pulling on it fights the
		# player's own mouse and reads as the toy being broken.
		if body and not body.freeze and not (body is BaseDraggable and (body as BaseDraggable).dragging):
			out.append(body)
	return out
