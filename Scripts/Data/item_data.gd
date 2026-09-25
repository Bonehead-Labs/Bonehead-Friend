class_name ItemData
extends Resource

## One buyable thing. Ten categories across two sides: five ways to hurt him (melee,
## explosives, cursor powers, turrets, critters) and five to be good to him (care, play,
## comfort, food, ambience).
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
## A gun you place on the desk that fires by itself while the game is open. It is a shop
## category rather than a flag on a weapon because the two are bought for different reasons
## and belong on different tabs: a weapon is a thing you swing, a turret is a thing you set
## down and walk away from. See `Scripts/Bodies/turret_base.gd` for why the item is priced
## in Bones while its automation capstone is priced in Hearts.
const CATEGORY_TURRET := 5
## Something alive that turns up and goes for him on its own. Filed apart from Toy, where
## the gorilla, the goose and the hornet used to sit beside the beach ball and the
## trampoline — which made "is this thing on his side" unanswerable from the data, and put
## four things that attack him in the same drawer a player opens looking for something nice.
const CATEGORY_CRITTER := 6
## The kind half's own drawers. Before these, everything nice was Friendly or Toy — two
## buckets for a side of the game that is meant to grow, next to five for the other side.
const CATEGORY_COMFORT := 7
const CATEGORY_FOOD := 8
const CATEGORY_AMBIENCE := 9

## The two halves of the game. Every category belongs to exactly one, which is the whole
## reason `CATEGORY_CRITTER` had to exist: while the critters lived under Toy, no rule over
## categories could sort the shop, and the shop is where a player decides what kind of
## session they are having.
const SIDE_HARM := 0
const SIDE_KIND := 1

## Which half each category sits in. A table rather than a `category >= N` test, because the
## constants are append-only ints and any ordering rule breaks the first time a category is
## added to the middle of the list.
const CATEGORY_SIDE := {
	CATEGORY_WEAPON: SIDE_HARM,
	CATEGORY_THROWABLE: SIDE_HARM,
	CATEGORY_CURSOR_POWER: SIDE_HARM,
	CATEGORY_TURRET: SIDE_HARM,
	CATEGORY_CRITTER: SIDE_HARM,
	CATEGORY_FRIENDLY: SIDE_KIND,
	CATEGORY_TOY: SIDE_KIND,
	CATEGORY_COMFORT: SIDE_KIND,
	CATEGORY_FOOD: SIDE_KIND,
	CATEGORY_AMBIENCE: SIDE_KIND,
}

const CURRENCY_BONES := 0
const CURRENCY_HEARTS := 1

## The universal join key. Shared by AugmentNode, MasteryTrack, save data and analytics —
## renaming one without a save migration orphans a player's purchase.
@export var id: StringName

@export var display_name: String
@export_multiline var description: String

@export_enum("Weapon", "Throwable", "CursorPower", "Friendly", "Toy", "Turret", "Critter", "Comfort", "Food", "Ambience") var category: int = CATEGORY_WEAPON

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

## Equips as a cursor power even though it is filed elsewhere in the shop. The open hand
## is mechanically a cursor power and catalogued under Friendly, and a player looking for
## the kindness half of the game must find it next to the sponge rather than filed with
## the pistol. Shop grouping and equip behaviour are two different questions, so this is
## the second one — as a data field, so it never becomes a per-item branch in a script.
@export var equips_as_cursor_power: bool = false

## Acts on its own once placed, rather than being swung, thrown or aimed by the player. A
## turret firing and a gorilla swinging are the item working; a bat landing is the player
## being at the desk. **Nothing can tell those apart from the damage event** — `HitInfo`
## carries an item id and no more — so the distinction has to live here.
##
## Category cannot answer it: the gorilla, the goose and the hornet are all filed as Toy
## next to the trampoline and the beach ball, because that is where a player looks for
## them. Where a thing sits in the shop and whether it has a mind of its own are two
## different questions.
##
## What reads it is `IdleBrain`, which treats damage as the player arriving and stands him
## up. Before this existed, one pellet turret on the desk meant he could never be idle for
## the twenty-five seconds his routines need — so he never touched a toy again, for as long
## as that turret ran.
@export var is_autonomous: bool = false

## How to work it, in the player's hands: "Hold · Right-click to fire", "Right-drag the
## crank". One short line, shown with the item and taught once when it first lands on the
## desk. Empty means the default gesture (grab it, swing it, throw it) and says nothing.
##
## Data, not a per-class string, because the same class can be worked two ways — a fidget
## spinner and a bubble wrap sheet are both zone toys — and because the line is written for
## the player, which is the shop's business rather than the body's.
@export var controls: String = ""

## Harm or kind. Read from the category, so an item is filed once and every system that
## cares — the shop's two front doors, the idle brain deciding what he would enjoy — agrees
## by construction rather than by two lists kept in step by hand.
func side() -> int:
	return int(CATEGORY_SIDE.get(category, SIDE_HARM))

func is_kind() -> bool:
	return side() == SIDE_KIND

func is_starter() -> bool:
	return cost <= 0

## Cursor powers live for the whole session and toggle; everything else is spawned into
## the world and can be binned.
func is_cursor_power() -> bool:
	return category == CATEGORY_CURSOR_POWER or equips_as_cursor_power

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
