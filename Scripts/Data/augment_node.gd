class_name AugmentNode
extends Resource

## One node in an item's augment tree: a buyable stack of levels with an exponential cost
## curve and a multiplicative effect.
##
## Every weapon's tree has the same shape (docs/economy.md), so this one resource type and
## one UI serve the whole roster.

const CURRENCY_BONES := 0
const CURRENCY_HEARTS := 1

## Owning item id, or &"global" for a node that modifies everything.
const GLOBAL := &"global"

@export var id: StringName
@export var item_id: StringName = GLOBAL
@export var display_name: String
@export_multiline var description: String

## 1 = buyable levels, 2 = pick-one branch, 3 = capstone. Display grouping only; the
## actual gating is `requires` / `requires_mastery` / `requires_prestige`.
@export var tier: int = 1

## What this node multiplies. Progression.get_modifier() is keyed on this.
## Known keys: &"damage_mult", &"payout_mult", &"mass_mult", &"cooldown_mult".
@export var effect_key: StringName

## **A multiplier per level, not an addend.** 1.15 means +15% compounding; 0.95 means a
## 5% reduction per level. Levels stack as pow(effect_per_level, levels), which is one
## rule with no special cases for "good" and "bad" directions.
@export var effect_per_level: float = 1.0

@export var max_levels: int = 10

@export var cost_base: int = 100
## 1.07-1.15 is the band the genre has converged on. Low for cheap utility nodes (many
## small satisfying buys), high for headline damage nodes (each buy is an event).
@export var cost_growth: float = 1.10
@export_enum("Bones", "Hearts") var currency: int = CURRENCY_BONES

## Non-empty means pick ONE within (item_id, exclusive_group).
@export var exclusive_group: StringName

## Capstone automation node. Hearts by convention — Hearts gating automation is the
## economy's spine (docs/decisions.md D2).
@export var is_automation: bool = false

## Currency per second this capstone generates, per level owned. **A rate, not a
## multiplier** — which is why it is its own field rather than reusing `effect_per_level`.
## D11's "every effect is a multiplier" rule is what keeps `AugmentMath` four lines long,
## and an income rate is the one thing that genuinely is not one; folding it in would need
## a branch on effect_key somewhere, and that somewhere is always a script.
##
## The currency is the owning item's: a weapon automates into Bones, a friendly item into
## Hearts. Ignored unless `is_automation`.
@export var automation_rate: float = 0.0

@export var requires: Array[StringName] = []
@export var requires_mastery: int = 0
@export var requires_prestige: int = 0

@export var sort_order: int = 0

func currency_id() -> StringName:
	return &"hearts" if currency == CURRENCY_HEARTS else &"bones"

func validation_error() -> String:
	if id == &"":
		return "missing id"
	if effect_key == &"":
		return "augment '%s' has no effect_key" % id
	if max_levels <= 0:
		return "augment '%s' has max_levels %d" % [id, max_levels]
	if cost_growth <= 0.0:
		return "augment '%s' has cost_growth %f" % [id, cost_growth]
	# An automation capstone that generates nothing is a Hearts sink with no output, and it
	# would look identical to a working one in the UI.
	if is_automation and automation_rate <= 0.0:
		return "automation '%s' has no automation_rate" % id
	return ""
