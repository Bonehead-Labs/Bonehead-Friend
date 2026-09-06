class_name CosmeticData
extends Resource

## One thing in the wardrobe: a finish for his bones or a set of headphones, bought with
## Dollars and worn for as long as you like (docs/game-design.md § Cosmetics, D31).
##
## No art. A cosmetic is a **tint** applied by the shader `EffectsPlayer` already puts on him,
## on the same pixel masks grime uses: the bone finish colours bright, low-saturation pixels
## and leaves the outline and the headphones alone; the headphone finish colours the teal.
## That is what lets a wardrobe ship before the art pass draws a single hat, and it is why a
## cosmetic can never touch a number — it is a colour, and nothing in the economy reads one.
##
## One slot per kind: he wears one bone finish and one pair of headphones at a time.

const SLOT_BONE := &"bone"
const SLOT_PHONES := &"phones"

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## `bone` or `phones`.
@export var slot: StringName = SLOT_BONE

## Dollars. Zero is the default look, which everyone owns.
@export var price_dollars: int = 0

## Multiplied into the slot's pixels. White is "as drawn".
@export var tint: Color = Color.WHITE

@export var sort_order: int = 0

func is_free() -> bool:
	return price_dollars <= 0

func validation_error() -> String:
	if id == &"":
		return "missing id"
	if display_name.is_empty():
		return "cosmetic '%s' has no display_name" % id
	if slot != SLOT_BONE and slot != SLOT_PHONES:
		return "cosmetic '%s' has slot '%s', which is neither bone nor phones" % [id, slot]
	if price_dollars < 0:
		return "cosmetic '%s' has a negative price" % id
	return ""
