class_name BaseDraggable
extends RigidBody2D

## Anything the player can grab and fling. The drag works by pinning this body to an
## invisible StaticBody2D "handle" that chases the mouse — that joint is what gives the
## game its feel, so don't replace it with direct position setting.

## Content id, and the join key into ItemData, augments and mastery. Set on the scene
## root; ItemSpawner also stamps it from the ItemData it spawned from, so a scene that
## forgets it still attributes its damage correctly.
@export var item_id: StringName

@export var drag_area: Area2D
@export var handle: StaticBody2D
## Node2D, not AnimatedSprite2D: the rebuilt item scenes carry a plain `Sprite2D` (one
## frame, no animation), and a typed export they cannot satisfy is a null nobody notices —
## which is exactly what happened. Everything here only ever touches `visible` and
## `modulate`, both of which are CanvasItem's.
@export var sprite: Node2D
@export var collider: CollisionShape2D
@export var Effects_Player: EffectsPlayer

## Where the drag joint pins, in body-local pixels.
##
## The bat pins at its grip and carries its weight in the barrel (see `seed_bodies.gd`), so
## it hangs handle-up in your hand and swings with the head. Pinning at the origin — which
## is what the rebuilt scenes did — makes every weapon a plank on a string.
@export var grip_offset: Vector2 = Vector2.ZERO

@export var joint_softness: float = 1.0
@export var joint_bias: float = 0.2
@export var follow_lerp: float = 1.0

var dragging: bool = false
var mouse_joint: PinJoint2D

## Everything grabbable joins this group so the world bounds can find and contain it.
const GROUP_INTERACTIVE := &"interactive"
## Only what the spawner put on the desk can be thrown away. A whitelist, not a blacklist:
## the buddy is draggable too, and no gesture may ever delete him.
const GROUP_SPAWNED := &"spawned_item"

func _ready() -> void:
	custom_integrator = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	add_to_group(GROUP_INTERACTIVE)

## World-space rect worth treating as a click target. Derived from the actual collision
## shape where there is one, so a mace and a grenade get appropriately sized regions.
func get_interaction_rect() -> Rect2:
	var extent := Vector2(48, 48)
	if collider and collider.shape:
		var r := collider.shape.get_rect() if collider.shape.has_method("get_rect") else Rect2()
		if r.size.length() > 0.0:
			extent = (r.size * 0.5 * global_scale).abs()
		elif collider.shape is CircleShape2D:
			var radius: float = (collider.shape as CircleShape2D).radius
			extent = Vector2(radius, radius) * global_scale.abs()
	return Rect2(global_position - extent, extent * 2.0)

## Unhandled, not _input: UI must be able to consume a click before the world sees it,
## otherwise every panel the player opens also grabs whatever is behind it.
func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null:
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed and drag_area and drag_area.is_hovered:
			_start_drag()
			get_viewport().set_input_as_handled()
		elif not click.pressed and dragging:
			_end_drag()
		return
	# Right-click to throw one thing away.
	#
	# This replaces the trash bin, which was a 36x45 catch area under a 64px sprite,
	# positioned above the height at which a dropped item comes to rest — so in practice
	# nothing ever landed in it. Pointing at a thing and dismissing it needs no aim and no
	# explanation, and the HUD's desk counter clears all of them at once.
	if click.button_index == MOUSE_BUTTON_RIGHT and click.pressed and not right_click_is_mine() \
			and drag_area and drag_area.is_hovered and is_in_group(GROUP_SPAWNED):
		if dragging:
			_end_drag()
		EventBus.item_despawned.emit(self)
		queue_free()
		get_viewport().set_input_as_handled()

## Subclasses that already mean something by right-click say so here, and keep it.
##
## A grenade primes with right-click. When the despawn gesture above was added it ran first,
## because it lives in the base class and the subclass calls `super` — so right-clicking a
## grenade deleted it instead of arming it, and explosives silently stopped working
## altogether. A binned grenade is still reachable through the HUD's clear-desk button.
func right_click_is_mine() -> bool:
	return false

func _start_drag() -> void:
	if not handle:
		return
	dragging = true
	# Global space throughout. The old code mixed event.position (viewport space) here
	# with get_global_mouse_position() in _physics_process, which disagree the moment
	# any camera or stretch mode is introduced.
	handle.global_position = get_global_mouse_position()

	mouse_joint = PinJoint2D.new()
	mouse_joint.position = grip_offset
	mouse_joint.node_a = handle.get_path()
	mouse_joint.node_b = get_path()
	mouse_joint.softness = joint_softness
	mouse_joint.bias = joint_bias
	add_child(mouse_joint)

func _end_drag() -> void:
	dragging = false
	if mouse_joint:
		mouse_joint.queue_free()
		mouse_joint = null

func _physics_process(_delta: float) -> void:
	if dragging and handle:
		handle.global_position = handle.global_position.lerp(get_global_mouse_position(), follow_lerp)
