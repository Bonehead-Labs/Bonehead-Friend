class_name MilestoneData
extends Resource

## One milestone: a thing the player did, noticed, and paid for.
##
## Milestones are the main source of **Dollars** (docs/decisions.md D31, D34), which makes
## the shape of this resource an economic decision rather than a bookkeeping one. A finite
## set of hand-written entries pays well for a week and then stops — and the arcade goes
## dark exactly when somebody has settled in. So there are two kinds, and the difference is
## one field:
##
##   `repeat_every == 0`  a **named** milestone. One-shot, hand-written, memorable, and the
##                        thing a player screenshots. These carry the first week.
##   `repeat_every > 0`   a **ladder**. Every 10x of lifetime Bones, every hundred
##                        knockouts, every twenty-five levels on a device. Each rung pays
##                        less than a named milestone and there is always another rung.
##
## They watch the same key stream contracts do (`EventBus.contract_event`), plus a handful
## of lifetime counters `Milestones` maintains itself. Reusing the contract keys is not
## laziness: it means a key that something emits is automatically available to both systems,
## and there is exactly one place where a new goal shape has to be plumbed in.

## Watched key. Either a contract key (`deal_damage`, `knockout`, `pet`, `purchase`,
## `bounce`, `use:<item_id>`) or one of `Milestones.SELF_KEYS` — the lifetime totals the
## bus does not carry, like Bones ever earned or items ever owned.
@export var goal_key: StringName

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## First rung. For a one-shot this is the whole requirement.
@export var target: float = 1.0

## Zero for a one-shot. Otherwise the step between rungs — **multiplicative if
## `repeat_multiplies`, additive if not.** "Every 10x of lifetime Bones" is a multiplying
## ladder and "every hundred knockouts" is an adding one, and a single field cannot express
## both without lying about one of them.
@export var repeat_every: float = 0.0
@export var repeat_multiplies: bool = false

## Paid per rung claimed. A named milestone pays a lump; a ladder rung pays less, and pays
## it again and again.
@export var reward_dollars: int = 500

## Compounding income bonus per rung, D11's one rule for every multiplier in the game. Kept
## small on purpose: forty of these at x1.01 is x1.49, which is a real reward for breadth
## and not a second economy.
@export var income_bonus: float = 1.01

## Hidden until earned — for the joke ones, where the surprise is the reward.
@export var hidden: bool = false

@export var sort_order: int = 0

## How many rungs `progress` has completed. One-shots answer 0 or 1; ladders count up
## forever, which is the point of them.
func rungs_at(progress: float) -> int:
	if target <= 0.0:
		return 0
	if progress < target:
		return 0
	if repeat_every <= 0.0:
		return 1
	if repeat_multiplies:
		# Every `repeat_every`-fold above the first rung. log-based rather than a loop: a
		# player forty doublings in should not cost forty iterations on every payout.
		var factor := maxf(1.0000001, repeat_every)
		return 1 + int(floor(log(progress / target) / log(factor) + 1e-9))
	return 1 + int(floor((progress - target) / repeat_every + 1e-9))

## What `progress` has to reach for the next rung after `claimed` of them.
func next_target(claimed: int) -> float:
	if claimed <= 0:
		return target
	if repeat_every <= 0.0:
		return target
	if repeat_multiplies:
		return target * pow(repeat_every, float(claimed))
	return target + repeat_every * float(claimed)

## Sanity check run by ItemDB at boot, so a malformed resource fails loudly at startup
## rather than as a silent milestone nobody can ever earn.
func validation_error() -> String:
	if id == &"":
		return "missing id"
	if display_name.is_empty():
		return "milestone '%s' has no display_name" % id
	if goal_key == &"":
		return "milestone '%s' has no goal_key" % id
	if target <= 0.0:
		return "milestone '%s' has target %f" % [id, target]
	# A multiplying ladder with a step of 1 never advances, and would pay its rung on every
	# single payout for the rest of the run.
	if repeat_multiplies and repeat_every > 0.0 and repeat_every <= 1.0:
		return "milestone '%s' multiplies by %f, which never advances" % [id, repeat_every]
	return ""
