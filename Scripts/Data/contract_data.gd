class_name ContractData
extends Resource

## One objective on the contract board: "deal 10,000 damage", "pet him 200 times".
##
## The daily-return hook, replacing a login bonus with something that does not smell like
## free-to-play (docs/game-design.md). Rewards are **Ectoplasm** rather than Bones or
## Hearts on purpose: contracts must not be a faster way to buy the next toy, or the
## pacing of the shop ladder is set by the calendar instead of by play.

const PERIOD_DAILY := 0
const PERIOD_WEEKLY := 1

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## The `EventBus.contract_event` key this counts. Live keys:
##   &"deal_damage"  — count is damage, so targets are in damage points
##   &"kindness"     — a deliberate kind act. NOT generator ticks: a placed boombox would
##                     otherwise finish a 150-target contract in seventy-five seconds with
##                     nobody at the keyboard
##   &"pet"          — the open hand specifically
##   &"knockout"     — one per collapse
##   &"purchase"     — one per item bought
##   &"use:<item_id>"— one per use of a specific item
##
## A contract whose key nothing emits is dead weight the player can never finish, so
## ItemDB validates this against the list above at boot rather than at 3am on day four.
@export var goal_key: StringName

@export var target: int = 100

@export_enum("Daily", "Weekly") var period: int = PERIOD_DAILY

@export var reward_ectoplasm: int = 1

## Optional currency sweetener on top. Kept small for the reason in the class docs.
@export var reward_currency_amount: float = 0.0
@export_enum("Bones", "Hearts") var reward_currency: int = 0

@export var sort_order: int = 0

## Keys that something in the game actually emits. Extending the game with a new goal means
## adding the emit AND this entry, which is the point: the two must not drift.
const KNOWN_KEYS: Array[StringName] = [
	&"deal_damage", &"kindness", &"pet", &"knockout", &"purchase",
	# M3.5-A. The trampoline is the first thing in the roster that produces an event of its
	# own rather than damage or kindness, and a key nothing can watch is a mechanic nobody
	# will ever be asked to use.
	&"bounce",
]
const ITEM_KEY_PREFIX := "use:"

func currency_id() -> StringName:
	return &"hearts" if reward_currency == 1 else &"bones"

func period_seconds() -> float:
	return 604800.0 if period == PERIOD_WEEKLY else 86400.0

func validation_error() -> String:
	if id == &"":
		return "missing id"
	if display_name.is_empty():
		return "contract '%s' has no display_name" % id
	if target <= 0:
		return "contract '%s' has target %d" % [id, target]
	if goal_key == &"":
		return "contract '%s' has no goal_key" % id
	if not KNOWN_KEYS.has(goal_key) and not String(goal_key).begins_with(ITEM_KEY_PREFIX):
		return "contract '%s' watches '%s', which nothing emits" % [id, goal_key]
	return ""
