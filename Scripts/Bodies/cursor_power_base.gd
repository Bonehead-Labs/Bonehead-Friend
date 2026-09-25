class_name CursorPowerBase
extends Node2D

## A power the cursor becomes: fist, pistol, shotgun, magnifying glass, lightning.
##
## Replaces three copy-pasted activation implementations in the prototype, along with the
## three-way `if` chain in item_menu.gd that toggled them. Every power listens to
## `cursor_power_changed` and deactivates itself whenever the id on the bus is not its
## own, so "only one power at a time" is a property of this class rather than a rule the
## menu has to remember.

@export var item_id: StringName
@export var cursor_texture: Texture2D
## Hotspot offset of the cursor image, so the effect lands where the crosshair points.
@export var cursor_hotspot: Vector2 = Vector2.ZERO
@export var cooldown_seconds: float = 0.0
@export var damage_mult: float = 1.0

var active: bool = false

var _cooldown_until_msec: int = 0

func _ready() -> void:
	EventBus.cursor_power_changed.connect(_on_cursor_power_changed)
	# _on_deactivated() directly, not set_active(false): `active` already starts false, so
	# set_active would short-circuit and the subclass would never park itself. For the
	# fist that leaves a frozen, invisible collider sitting at the world origin — the
	# stranded-collider bug M0 removed from the prototype, reintroduced by a no-op guard.
	_on_deactivated()

## **A held button ends when the game loses focus** (D70). Four powers are held — the minigun's
## stream, the magnifying glass, the open hand's stroke, the vortex — and each watches for the
## release in `_input`. Alt-tab with the button down and the release goes to the other window,
## so the minigun kept firing, and paying Bones, at a desk nobody was at until the next click.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_hold()

## Override: stop whatever holding the button was doing. Nothing to stop by default.
func release_hold() -> void:
	pass

func _on_cursor_power_changed(id: StringName) -> void:
	if id == item_id and item_id != &"":
		set_active(true)
	elif active:
		# Only give the cursor back when nothing is replacing this power. Every power gets
		# this signal, and a deactivation arriving after the new power activated would
		# otherwise wipe the cursor image it had just set.
		set_active(false, id == &"")

func set_active(value: bool, restore_cursor: bool = true) -> void:
	if active == value:
		return
	active = value
	if active:
		if cursor_texture:
			Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, cursor_hotspot)
		_on_activated()
	else:
		if restore_cursor:
			Input.set_custom_mouse_cursor(null)
		_on_deactivated()

## **A power aims at him and at the desk. Your hands still work on your toys.** (D47)
##
## Until now an equipped power consumed every left click, so nothing could be picked up,
## moved or thrown while one was on, and the only way to touch a toy again was to open the
## panel and click the power off. The old comment here called that "a real design question"
## and left it for a playtest; the owner reached it first, from the other side: equipping
## and unequipping is annoying, and you cannot use anything else while armed.
##
## The rule that replaces it is one sentence long, which is the point:
##
## * Over a **spawned item** — a bat, a grenade, a teddy bear — the power declines. The
##   click falls through and you grab the thing, because that is what clicking a thing on a
##   desk means. Powers are for him, not for the props.
## * Over **him**, or over empty space, the power fires. He is what a weapon is pointed at,
##   and he is not a spawned item, so no special case is needed to say so.
## * **Shift suspends the power** for that click, so he can still be dragged, thrown and
##   played with without holstering. Shift already means "ignore the special behaviour and
##   do the plain thing" in this codebase — `BaseDraggable.click_would_bin` gives it exactly
##   that job on the right button — so it costs the player one idea, not two.
##
## A power that declines the click does NOT consume it, so the world still sees it. The open
## hand uses the same door to decline clicks that miss him.
func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed or event.is_echo():
		return
	if event.shift_pressed:
		return
	if _pointing_at_a_toy():
		return
	var at := get_global_mouse_position()
	if not can_fire_at(at):
		return
	if not _cooldown_ready():
		return
	fire(at)
	get_viewport().set_input_as_handled()

## Whether the cursor is over something the player put on the desk.
##
## Asked of the hover flags the areas already maintain from motion events rather than of the
## physics world: `get_mouse_position()` reads the OS cursor, which no synthetic event can
## move, so a version built on it could not be driven by `ui_check` — and this rule is worth
## a test. Spawned items only, which is what keeps him firing at the buddy: he is a
## `BaseDraggable` too, and is deliberately not in the spawned group.
func _pointing_at_a_toy() -> bool:
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		var body := node as BaseDraggable
		if body and body.drag_area and body.drag_area.is_hovered:
			return true
	return false

func _cooldown_ready() -> bool:
	var now := Time.get_ticks_msec()
	if now < _cooldown_until_msec:
		return false
	# Cooldown augments scale the gap between shots, so the effect_key reads the same way
	# for a pistol as it does for a mace's swing rate.
	var gap := cooldown_seconds * Progression.get_modifier(item_id, &"cooldown_mult")
	_cooldown_until_msec = now + int(gap * 1000.0)
	return true

func effective_damage_mult() -> float:
	return Progression.damage_mult_for(item_id, damage_mult)

# --- subclass hooks --------------------------------------------------------

## Called with the world position of the click. Override.
func fire(_at: Vector2) -> void:
	pass

## Whether a click here is this power's to take. Override to decline — declining leaves
## the click unhandled so dragging and the UI still work.
func can_fire_at(_at: Vector2) -> bool:
	return true

func _on_activated() -> void:
	pass

func _on_deactivated() -> void:
	pass
