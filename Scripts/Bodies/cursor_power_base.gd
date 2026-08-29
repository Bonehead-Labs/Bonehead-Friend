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

## An equipped power consumes left clicks, so dragging is unavailable while one is on —
## the same behaviour the prototype had. Whether a click on a grabbable object should
## grab instead of fire is a real design question; it is left for the M2 playtest rather
## than guessed at here.
func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed or event.is_echo():
		return
	if not _cooldown_ready():
		return
	fire(get_global_mouse_position())
	get_viewport().set_input_as_handled()

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
	if item_id == &"":
		return damage_mult
	return damage_mult * Progression.get_modifier(item_id, &"damage_mult")

# --- subclass hooks --------------------------------------------------------

## Called with the world position of the click. Override.
func fire(_at: Vector2) -> void:
	pass

func _on_activated() -> void:
	pass

func _on_deactivated() -> void:
	pass
