class_name OpenHandPower
extends CursorPowerBase

## Petting. The free starter on the kindness side, and the only Hearts source a new player
## has — everything else in the friendly catalog is bought with Hearts, so this is where
## the second currency comes from before it can buy anything.
##
## Hold the left button on Bonehead and stroke: one kindness event every `pet_interval`,
## which is fast enough that Economy's combo multiplier actually engages. Unlike every
## other cursor power this one declines clicks that miss him, so equipping the open hand
## does not make the rest of the desktop undraggable.

## Extra reach around his grab region. Petting is meant to feel generous, and a pixel-exact
## hit test on a body that is being flung around reads as an unresponsive hand.
@export var reach_padding: float = 24.0

var _next_pet_msec := 0

## True only between a press this power actually claimed and its release.
##
## Polling `Input.is_mouse_button_pressed` instead would bypass the whole `_unhandled_input`
## chain that exists so the UI can consume a click first: with the shop panel open over the
## buddy, holding the button on a shop tile would pay Hearts at 4/s while the cursor was
## nowhere near him. A drag that began on a weapon and happened to pass over him would do
## the same. The claim flag is what ties petting to a press that was really meant for him.
var _stroking := false

func _on_activated() -> void:
	set_process(true)

func _on_deactivated() -> void:
	set_process(false)
	_stroking = false

## Releasing ends the stroke wherever it happens — including over a panel, and including
## when the release is consumed by something else, which is why this watches every release
## rather than only unhandled ones.
func _input(event: InputEvent) -> void:
	if not _stroking:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_stroking = false

func _process(_delta: float) -> void:
	if not active or not _stroking:
		return
	var at := get_global_mouse_position()
	# Still checked every tick: the stroke ends the moment the cursor leaves him, so
	# dragging off him and back on is two strokes rather than one uninterrupted payout.
	if not can_fire_at(at):
		return
	_pet_if_ready(at)

## The click that starts a stroke pays immediately, so a single tap is still a pet rather
## than nothing-until-you-hold-it.
func fire(at: Vector2) -> void:
	_stroking = true
	_pet_if_ready(at)

func _pet_if_ready(at: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_pet_msec:
		return
	_next_pet_msec = now + int(ItemDB.balance.pet_interval * 1000.0)
	_pet(at)

func can_fire_at(at: Vector2) -> bool:
	var buddy := _buddy()
	if buddy == null:
		return false
	return buddy.get_interaction_rect().grow(reach_padding).has_point(at)

func _pet(at: Vector2) -> void:
	EventBus.kindness_given.emit(item_id, ItemDB.balance.pet_value, at)
	EventBus.contract_event.emit(&"pet", 1)

## By group, never by path — the buddy lives in a different scene from this power
## (docs/decisions.md D9).
func _buddy() -> BaseDraggable:
	return get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as BaseDraggable
