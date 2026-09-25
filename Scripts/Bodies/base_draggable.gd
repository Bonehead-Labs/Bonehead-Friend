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
	apply_juice()

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
	# explanation, and the HUD's clear-desk button does all of them at once.
	if click.button_index != MOUSE_BUTTON_RIGHT or not click.pressed:
		return
	if not (drag_area and drag_area.is_hovered and is_in_group(GROUP_SPAWNED)):
		return
	if not click_would_bin(click.shift_pressed):
		return
	bin_myself()
	get_viewport().set_input_as_handled()

## Whether a right-click with or without Shift means "get rid of this".
##
## **Shift is the override, and nothing may claim it.** Plain right-click is legitimately
## taken by anything that primes — and by the time the roster held fourteen explosives, that
## meant a sixth of everything spawnable could not be dismissed by the one gesture for
## dismissing things. Spawn a mine you did not want and the only way out was a button most
## players never found. So a subclass keeps right-click and gives up Shift.
##
## Split out from the input handler so the rule can be asserted without synthesising a click
## with a modifier held, which no headless suite can do.
func click_would_bin(shift_held: bool) -> bool:
	if not is_in_group(GROUP_SPAWNED):
		return false
	return shift_held or not right_click_is_mine()

## Take myself off the desk. Public and used by both routes, so that the clear-desk button
## and the right-click gesture cannot drift apart — they were two copies of "emit and free",
## and the next thing either of them needs to do on the way out (cancel a running fuse, let
## an NPC drop its target) would have been written into only one of them.
func bin_myself() -> void:
	if dragging:
		_end_drag()
	EventBus.item_despawned.emit(self)
	queue_free()

## Subclasses that already mean something by right-click say so here, and keep it — but only
## for the unmodified click. Shift+right-click is not theirs to take (see above).
##
## A grenade primes with right-click. When the despawn gesture was added it ran first,
## because it lives in the base class and the subclass calls `super` — so right-clicking a
## grenade deleted it instead of arming it, and explosives silently stopped working
## altogether.
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

## Maximum speed and spin a dragged body may be given by the joint (D54). Not a leash — at a
## fast 1200 px/s hand the bat peaks around 1,600 px/s, so this never fires in normal play. It
## is a backstop for the next thing nobody predicted: the joint is a spring, and a spring with
## no ceiling is one solver surprise away from launching a 26 kg gorilla off the desk.
@export var max_drag_speed: float = 4500.0
@export var max_drag_spin: float = 40.0

## True while the hit-stop has the 2D physics server switched off (D54).
##
## Set by `FXLayer`, which owns the freeze. A static flag rather than a query because
## `PhysicsServer2D` has no `is_active()` to ask — `set_active` is write-only — and rather
## than a signal because every draggable on the desk would have to connect to it to answer a
## question that is the same for all of them.
static var physics_frozen := false

func _physics_process(_delta: float) -> void:
	# Not while the world is stopped. `_physics_process` is still called during a hit-stop
	# (`PhysicsServer2D.set_active(false)`), so without this guard the handle teleports to the
	# real cursor on every frozen frame and hands the joint all of that error at once the
	# instant physics resumes — which is the bug the freeze was introduced to fix, arriving by
	# the other door. Measured: eight frozen frames, eight teleports.
	if dragging and handle and not physics_frozen:
		handle.global_position = handle.global_position.lerp(get_global_mouse_position(), follow_lerp)
		# Written only when over the ceiling (D56). The getters return what the server reported
		# after the last step, so writing them back unconditionally every frame replaced the
		# body's real velocity with that stale copy — erasing any impulse applied since, which is
		# the fist's bug from D54 again: a held gun's recoil measured exactly 0.0 degrees.
		if linear_velocity.length_squared() > max_drag_speed * max_drag_speed:
			linear_velocity = linear_velocity.limit_length(max_drag_speed)
		if absf(angular_velocity) > max_drag_spin:
			angular_velocity = clampf(angular_velocity, -max_drag_spin, max_drag_spin)
	_trail_step()

# --- the trail --------------------------------------------------------------
#
# A line behind anything moving fast: the swing of a bat in the hand, a grenade in flight,
# him flung across the desk (docs/decisions.md D39). A `Line2D` in world space, fed the tip's
# position on every physics frame the body is moving fast enough, tapered from the tail; when
# it slows, the oldest points fall off two a frame so the trail catches up with the body and
# is gone. Built on first use, so a body that never moves fast never pays for one, and freed
# with the body. Off at Focus Off like every other moving thing.

const TRAIL_SPEED := 550.0
const TRAIL_POINTS := 10
const TRAIL_WIDTH := 7.0

var _trail: Line2D
## Where the line is drawn from, in body-local pixels: the corner of the collision shape
## farthest from the grip, which on a bat is the end of the barrel. The centre otherwise.
var _trail_tip := Vector2.ZERO

## Gold for a weapon, heating with its tier; the kind items and the buddy say otherwise.
func trail_colour() -> Color:
	return WorldFX.harm_colour(juice_tier)

func _trail_step() -> void:
	var fast := Settings.focus_intensity != Settings.Intensity.OFF \
		and linear_velocity.length_squared() > TRAIL_SPEED * TRAIL_SPEED
	if fast:
		if _trail == null:
			_build_trail()
		_trail.add_point(to_global(_trail_tip))
		while _trail.get_point_count() > TRAIL_POINTS + 3 * juice_tier:
			_trail.remove_point(0)
		_trail.visible = true
	elif _trail != null and _trail.get_point_count() > 0:
		for i in 2:
			if _trail.get_point_count() > 0:
				_trail.remove_point(0)
		if _trail.get_point_count() < 2:
			_trail.clear_points()
			_trail.visible = false

func _build_trail() -> void:
	_trail = Line2D.new()
	_trail.name = "Trail"
	# World space: the points are global, so the line must not inherit the body's spin.
	_trail.top_level = true
	_trail.show_behind_parent = true
	_trail.antialiased = false
	_trail.joint_mode = Line2D.LINE_JOINT_BEVEL
	_trail.default_color = trail_colour()
	_trail.width = TRAIL_WIDTH + TRAIL_TIER_WIDTH * juice_tier
	# Thin at the tail, full at the head — the whole reason it reads as motion.
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.1))
	taper.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = taper
	_trail.visible = false
	add_child(_trail)
	_trail_tip = _find_tip()

func _find_tip() -> Vector2:
	if collider == null or collider.shape == null or not collider.shape.has_method("get_rect"):
		return Vector2.ZERO
	var rect: Rect2 = collider.shape.get_rect()
	if rect.size.length() <= 0.0:
		return Vector2.ZERO
	var best := Vector2.ZERO
	var far := -1.0
	for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y),
			Vector2(rect.end.x, rect.position.y)]:
		var local: Vector2 = collider.transform * corner
		var distance := local.distance_to(grip_offset)
		if distance > far:
			far = distance
			best = local
	return best

# --- how upgraded it looks -------------------------------------------------------
#
# A level-three bat has to look like a level-three bat (docs/decisions.md D41). The art is
# one sprite per item, so the upgrade is worn as light and motion: a breathing outline in the
# tier's colour (`ItemGlow`), a wider and longer trail, and from the second tier an aura of
# chips rising off the thing. Read from Progression on spawn and again whenever a purchase, a
# rank or a Focus change lands (`ItemSpawner.refresh_augments`). Nothing here is a number in
# the economy; it is only what the number looks like.

## Per tier. Reduced from 2.5 when the ladder went from 3 rungs to 5 (D53): the widest trail
## is the same 15px it always was, rather than growing by two thirds because there are more
## steps to climb.
const TRAIL_TIER_WIDTH := 1.5
## Indexed by juice tier, so both must have `MasteryMath.JUICE_TIERS + 1` entries — index 0
## is a plain, unupgraded item. Read with a clamp rather than raw: an array a tier shorter
## than the ladder is an out-of-range on the item-spawn path, which is every item in the game,
## and it would land the moment someone adds a rung without scrolling down here.
##
## The ramp is deliberately slow at the bottom and steep at the top (D53). The first two tiers
## arrive in the first four minutes of play and must read as "this is yours now", not as a
## light show; the aura is held back until tier 3, which is rank 50, so the thing that makes a
## weapon look finished is genuinely rare.
const GLOW_STRENGTH: Array[float] = [0.0, 0.35, 0.5, 0.68, 0.85, 1.0]
const AURA_AMOUNT: Array[int] = [0, 0, 0, 4, 7, 9]

var juice_tier := 0
var _aura: GPUParticles2D

## What the aura is made of: chips for a weapon, hearts for a kind item.
func aura_glyph() -> StringName:
	return &"chip"

func apply_juice() -> void:
	juice_tier = Progression.juice_tier(item_id) if item_id != &"" else 0
	var colour := trail_colour()
	var moving := Settings.focus_intensity != Settings.Intensity.OFF
	if _trail:
		_trail.default_color = colour
		_trail.width = TRAIL_WIDTH + TRAIL_TIER_WIDTH * juice_tier
	# Clamped, not raw. These arrays are sized to the ladder and the ladder has moved once
	# already; an off-by-one here is an out-of-range on every item spawn in the game.
	var step := clampi(juice_tier, 0, GLOW_STRENGTH.size() - 1)
	if sprite is CanvasItem:
		ItemGlow.apply(sprite, colour, GLOW_STRENGTH[step], moving)
	var amount: int = AURA_AMOUNT[clampi(juice_tier, 0, AURA_AMOUNT.size() - 1)]
	if amount > 0:
		if _aura == null or not is_instance_valid(_aura):
			var fx := WorldFX.of(self)
			if fx:
				_aura = fx.aura(self, aura_glyph(), colour, amount, "Aura", _aura_box())
		if _aura:
			_aura.amount = amount
			_aura.modulate = colour
			_aura.emitting = moving
	elif _aura and is_instance_valid(_aura):
		_aura.emitting = false

## Half the collision shape, so the aura rises off the whole thing rather than its centre.
func _aura_box() -> Vector2:
	if collider and collider.shape and collider.shape.has_method("get_rect"):
		var rect: Rect2 = collider.shape.get_rect()
		if rect.size.length() > 0.0:
			return (rect.size * 0.5 * collider.scale.abs()).clamp(Vector2(4, 4), Vector2(60, 60))
	return Vector2(10, 10)
