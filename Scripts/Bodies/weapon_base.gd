class_name WeaponBase
extends BaseDraggable

## Melee weapons: bats, maces, pans. A weapon deals no damage itself — Bonehead measures
## the contact impulse he receives and asks the weapon only for its multiplier
## (docs/decisions.md D7). That is why this class is almost empty, and why a bowling ball
## with no script at all still hurts.

## Authored per weapon. Multiplied by the item's damage augments at spawn time.
@export var damage_mult: float = 1.0

## Applied to `mass` on spawn by the Weight augment. Mass is what turns a swing into an
## impulse, so this node is felt in the physics rather than only in the numbers.
var _spawn_mass: float = 0.0

func _ready() -> void:
	super._ready()
	_spawn_mass = mass
	apply_augments()

## Re-reads the player's augment levels. Called on spawn and whenever a tree purchase
## lands, so an upgrade bought with the bat already on screen takes effect immediately.
func apply_augments() -> void:
	if item_id == &"":
		return
	mass = maxf(0.01, _spawn_mass * Progression.get_modifier(item_id, &"mass_mult"))

## One swing that landed, reported to the contract board.
##
## Called by Bonehead from his attribution step, which is the only place in the game that
## knows a contact got past both gates — the minimum impulse and the per-source cooldown. A
## weapon left leaning against him therefore counts nothing, exactly as it earns nothing.
##
## Deliberately not folded into `effective_damage_mult()` below, even though he calls that
## on the same line: a getter that also emits is a trap for the first stat readout or test
## that reads it.
func register_use() -> void:
	if item_id == &"":
		return
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

## What Bonehead multiplies the raw contact impulse by.
func effective_damage_mult() -> float:
	if item_id == &"":
		return damage_mult
	return damage_mult * Progression.get_modifier(item_id, &"damage_mult")
