class_name ItemData
extends Resource

## One buyable thing: a weapon, a throwable, a cursor power, a friendly item or a toy.
##
## This is the whole definition. Adding an item to the game is adding a .tres file under
## res://Data/Items/ — no script edits anywhere (docs/decisions.md D8). The prototype
## needed three coordinated edits per item, which is why it stalled at seven and why one
## of those edits shipped a crash.

## Category constants rather than an enum: an enum used as a parameter type is a distinct
## type across script boundaries, so a caller passing ItemData.Category.WEAPON cannot
## satisfy a `Category` parameter declared in another script. Plain ints avoid the trap.
const CATEGORY_WEAPON := 0
const CATEGORY_THROWABLE := 1
const CATEGORY_CURSOR_POWER := 2
const CATEGORY_FRIENDLY := 3
const CATEGORY_TOY := 4

const CURRENCY_BONES := 0
const CURRENCY_HEARTS := 1

## The universal join key. Shared by AugmentNode, MasteryTrack, save data and analytics —
## renaming one without a save migration orphans a player's purchase.
@export var id: StringName

@export var display_name: String
@export_multiline var description: String

@export_enum("Weapon", "Throwable", "CursorPower", "Friendly", "Toy") var category: int = CATEGORY_WEAPON

## One-time, hand-authored price. **Zero or less means a free starter**, owned from the
## first boot — that is how the catalog's "free (starter)" entries are expressed.
@export var cost: int = 0
@export_enum("Bones", "Hearts") var currency: int = CURRENCY_BONES

## Spawned by ItemSpawner for weapons/throwables/toys; instanced once and kept alive for
## cursor powers.
@export var scene: PackedScene
@export var icon: Texture2D

## Item ids that must be owned first. Empty means always available.
@export var requires: Array[StringName] = []

## Ascending display order within a shop category.
@export var sort_order: int = 0

func is_starter() -> bool:
	return cost <= 0

## Cursor powers live for the whole session and toggle; everything else is spawned into
## the world and can be binned.
func is_cursor_power() -> bool:
	return category == CATEGORY_CURSOR_POWER

## StringName key into Economy's balance dictionary.
func currency_id() -> StringName:
	return &"hearts" if currency == CURRENCY_HEARTS else &"bones"

## Sanity check run by ItemDB at boot, so a malformed resource fails loudly at startup
## rather than as a null dereference twenty minutes into a session.
func validation_error() -> String:
	if id == &"":
		return "missing id"
	if display_name.is_empty():
		return "item '%s' has no display_name" % id
	if scene == null and not is_cursor_power():
		return "item '%s' has no scene" % id
	return ""
