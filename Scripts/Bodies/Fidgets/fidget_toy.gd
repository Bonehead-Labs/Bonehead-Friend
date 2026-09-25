class_name FidgetToy
extends FriendlyBase

## A kind toy you work with your hands, and that he plays with when you are not
## (docs/decisions.md D57). The shared half of the five fidget toys, so each of them is only
## the thing that makes it different.
##
## This is a convenience, not the framework. The framework is `GestureZones`, a component any
## `BaseDraggable` can carry — a harm-side fidget extends `WeaponBase` and wires the component
## itself. What this adds on top, for the kind side:
##
## - **Two ways to pay, and the difference matters.** `pay_act()` is the player's hand: it
##   goes out as `kindness_given`, so the combo, the contract board and the per-act Dollars all
##   see it. `pay_sustained()` is him playing on his own, or a toy paying at a rate while it
##   runs: it is banked and flushed as `kindness_sustained`, for exactly the reasons
##   `IdleBrain` gives for paying that way — a routine nobody is watching must not sit at the
##   combo ceiling, finish a "be kind 150 times" daily overnight, or earn the Dollars that are
##   paid for being present (D14, D31). Both are a *value*; Economy is the only thing that
##   mints currency.
## - **The idle hooks `IdleBrain` asks of any fidget** (`ROUTINE_FIDGET`): `idle_appeal()` is
##   roughly what a second of it is worth to him right now — zero means "nothing to do here",
##   which is how a fully popped sheet stops being a destination — and `idle_use(buddy)` is
##   called on the brain's think tick while he is at it. Duck-typed on purpose: a harm-side
##   toy with these two methods is walked to and used exactly the same way.
## - **`fidget(event)`** says out loud that something happened, for his face to answer
##   (`EventBus.fidget_event`, mapped to rows in `ExpressionBrain.FIDGET_ROWS`).
##
## A toy script overrides `_on_gesture(g)` and, if he plays with it, the two idle hooks.

@export var gestures: GestureZones

var _buddy_ref: WeakRef = null

func _ready() -> void:
	super._ready()
	if gestures:
		gestures.gesture.connect(_on_gesture)

## Override: one gesture from the zones. See `GestureZones` for the kinds.
func _on_gesture(_g: GestureZones.Gesture) -> void:
	pass

## Override: what a second of him playing with this is worth, in kindness value. Zero means
## there is nothing for him to do with it right now.
func idle_appeal() -> float:
	return 0.0

## Override: he is at the toy; do what he does with it. Called on `IdleBrain`'s think tick,
## never per frame. At Focus Off he is "simply there" (D21) — pay, but do not move him.
func idle_use(_buddy: Buddy) -> void:
	pass

## The player did it. Kindness value, before this item's own value node — which is applied
## here, so every fidget's `damage_mult` augment is felt.
##
## `reaction` is the fidget event his face answers with, sent *after* the payment: the
## expression brain leaves a hand-worked toy's kindness to the toy (a bubble popping is not
## him catching a ball), so this is the only thing that reacts to it. Empty for silence.
func pay_act(value: float, at: Vector2, reaction: StringName = &"amused") -> void:
	_pay_event(value * value_multiplier(), at)
	if reaction != &"":
		fidget(reaction, at)

## He did it himself, or it is running on its own. Banked, and flushed with FriendlyBase's own cadence as sustained kindness.
func pay_sustained(value: float, at: Vector2) -> void:
	_bank(value * value_multiplier(), at)

## Tell his face.
func fidget(event: StringName, at: Vector2 = Vector2.INF) -> void:
	EventBus.fidget_event.emit(item_id, event, global_position if at == Vector2.INF else at)

## This item's own augment on `key`, 1.0 with none bought.
func upgrade(key: StringName) -> float:
	return Progression.get_modifier(item_id, key) if item_id != &"" else 1.0

## Him, found by group and remembered weakly: a toy must never keep a freed buddy alive, and
## never find him by path (D9).
func buddy() -> Buddy:
	if _buddy_ref:
		var known := _buddy_ref.get_ref() as Buddy
		if known and is_instance_valid(known):
			return known
	if not is_inside_tree():
		return null
	var found := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	_buddy_ref = weakref(found) if found else null
	return found

## Whether the moving parts should move at all. Focus Off stills everything that is not the
## player's own doing (D21, D36); the toys still work and still pay.
func animating() -> bool:
	return Settings.focus_intensity != Settings.Intensity.OFF

## One small chip-burst off the toy, if the world has effects. Optional, like every WorldFX
## call.
func chips(at: Vector2, glyph: StringName, count: int, speed: float = 90.0) -> void:
	var fx := WorldFX.of(self)
	if fx:
		fx.burst(at, glyph, trail_colour(), count, speed, 0.5)
