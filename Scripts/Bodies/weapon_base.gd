class_name WeaponBase
extends BaseDraggable

## Melee weapons: bats, maces, pans. A weapon deals no damage itself — Bonehead measures
## the contact impulse he receives and asks the weapon only for its multiplier
## (docs/decisions.md D7). That is why this class is almost empty, and why a bowling ball
## with no script at all still hurts.

## Authored per weapon. Multiplied by the item's damage augments at spawn time.
@export var damage_mult: float = 1.0

# The Weight augment (`mass_mult`) is applied by BaseDraggable, to every body that has one:
# it lived here, and the fifteen explosives, the trampoline and the fan all sold a mass node
# that nothing read (D59).

## What right does while it is in your hand (D74) is `BaseDraggable.ability`: it lived here until
## D78 gave the same button to the balls, the care items and two explosives, and every line of it —
## the child built on `_ready`, the right press claimed first, the pick-up and the drop — moved up
## unchanged, so a weapon's ability behaves exactly as it did.

## One swing that landed, reported to the contract board.
##
## Called by Bonehead from his attribution step, which is the only place in the game that
## knows a contact got past both gates — the minimum impulse and the per-source cooldown. A
## weapon left leaning against him therefore counts nothing, exactly as it earns nothing.
##
## Deliberately not folded into `effective_damage_mult()` below, even though he calls that
## on the same line: a getter that also emits is a trap for the first stat readout or test
## that reads it. The ability hears of it here too, and only records it: the multiplier he reads
## next must still be the one this hit was armed with.
func register_use() -> void:
	if ability:
		ability.note_hit()
	if item_id == &"":
		return
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

## What Bonehead multiplies the raw contact impulse by — the ability's share included, which is
## one outside a charged hit, a daze or a throw.
func effective_damage_mult() -> float:
	var mult := Progression.damage_mult_for(item_id, damage_mult)
	if ability:
		mult *= ability.hit_multiplier()
	return mult
