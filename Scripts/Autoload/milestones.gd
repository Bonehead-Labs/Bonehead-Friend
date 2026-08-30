extends Node

## The milestone board: what the player has done, counted forever, and paid for in Dollars.
##
## Three jobs, and they are deliberately separate from Progression's contract board even
## though they watch the same key stream:
##
##   - **counting**, which is lifetime and never resets — not on a Reincarnation, not on a
##     new day. A contract is a period; a milestone is a biography.
##   - **paying**, in Dollars per rung claimed (docs/decisions.md D31, D34).
##   - **a compounding income bonus** of `income_bonus` per rung, which is the third income
##     axis the design has been missing: not damage, not kindness, but *breadth*.
##
## Claiming is automatic. A contract is a job you take and hand in; a milestone is something
## you notice you have done, and a board of forty unclaimed "collect" buttons is homework.
## The toast is the reward moment.
##
## Progress is stored per **goal key**, not per milestone, so twelve milestones watching
## `knockout` share one counter and a new milestone on an existing key arrives already
## partly earned — which is right, because the player did already do it.

## Counters this keeps itself, because they are totals rather than events and nothing on the
## bus carries them. Read on a timer rather than driven, since they change continuously.
const SELF_KEYS := {
	&"lifetime_bones": true,
	&"lifetime_hearts": true,
	&"lifetime_dollars": true,
	&"items_owned": true,
	&"augment_levels": true,
	&"automation_rate": true,
	&"mastery_pool": true,
	&"reincarnations": true,
	&"marrow": true,
}

## How often the self-counted totals are re-read. They drive ladders like "every 10x of
## lifetime Bones", which no player experiences as an instant — and a poll on every payout
## would put a dictionary sweep inside the hottest path in the game.
const POLL_SECONDS := 2.0

signal milestone_claimed(milestone_id: StringName, rungs: int, dollars: int)

## goal_key -> float. Lifetime, never reset.
var _progress: Dictionary = {}
## milestone id -> int rungs already paid.
var _claimed: Dictionary = {}

var _poll := 0.0
## Product of every claimed rung's income_bonus. Cached because `Economy.payout_for` asks
## for it on every single payout and recomputing it walks the whole board.
var _income := 1.0

func _ready() -> void:
	SaveManager.register_provider(self)
	EventBus.contract_event.connect(_on_contract_event)

func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_SECONDS:
		return
	_poll = 0.0
	_refresh_self_counters()
	_award()

## The third income axis, multiplied into every payout. One number, cached.
func income_multiplier() -> float:
	return _income

func progress_of(goal_key: StringName) -> float:
	return float(_progress.get(goal_key, 0.0))

func rungs_claimed(milestone_id: StringName) -> int:
	return int(_claimed.get(milestone_id, 0))

## Everything the player has finished at least one rung of, for a stats page.
func earned() -> Array[MilestoneData]:
	var out: Array[MilestoneData] = []
	for milestone in ItemDB.all_milestones():
		if rungs_claimed(milestone.id) > 0:
			out.append(milestone)
	return out

## What a milestone is worth right now: [rungs claimed, progress, the next rung's target].
func status(milestone: MilestoneData) -> Array:
	var claimed := rungs_claimed(milestone.id)
	return [claimed, progress_of(milestone.goal_key), milestone.next_target(claimed)]

func _on_contract_event(key: StringName, count: int) -> void:
	if count <= 0:
		return
	_progress[key] = progress_of(key) + float(count)
	_award()

## Totals rather than events. `automation_rate` is a rate rather than an accumulation, so it
## is the one counter that can go *down* — a player who switches a device off has not
## un-earned the rung, which is why claimed rungs are never taken back.
func _refresh_self_counters() -> void:
	_progress[&"lifetime_bones"] = Economy.lifetime_of(Economy.BONES)
	_progress[&"lifetime_hearts"] = Economy.lifetime_of(Economy.HEARTS)
	_progress[&"lifetime_dollars"] = maxf(progress_of(&"lifetime_dollars"),
		Economy.balance_of(Economy.DOLLARS))
	_progress[&"items_owned"] = float(Progression.owned_items().size())
	_progress[&"mastery_pool"] = float(Progression.mastery_pool())
	_progress[&"reincarnations"] = float(Economy.prestige_count)
	_progress[&"marrow"] = Economy.marrow
	_progress[&"automation_rate"] = maxf(progress_of(&"automation_rate"),
		Progression.automation_rate_per_second(Economy.BONES)
			+ Progression.automation_rate_per_second(Economy.HEARTS))

	_progress[&"augment_levels"] = float(Progression.total_augment_levels())

## Pays every rung the player has reached and not yet been paid for. Loops per milestone
## because a single event can cross several rungs at once — a knockout payout can carry
## lifetime Bones past two rungs of a x10 ladder in one tick, and paying one of them would
## quietly lose the other forever.
func _award() -> void:
	var dirty := false
	for milestone in ItemDB.all_milestones():
		var progress := progress_of(milestone.goal_key)
		var reached := milestone.rungs_at(progress)
		var claimed := rungs_claimed(milestone.id)
		if reached <= claimed:
			continue
		var rungs := reached - claimed
		_claimed[milestone.id] = reached
		var dollars := milestone.reward_dollars * rungs
		Economy.grant(Economy.DOLLARS, float(dollars))
		_income *= pow(milestone.income_bonus, float(rungs))
		milestone_claimed.emit(milestone.id, rungs, dollars)
		dirty = true
	if dirty:
		SaveManager.request_autosave()

func _recompute_income() -> void:
	_income = 1.0
	for milestone in ItemDB.all_milestones():
		var rungs := rungs_claimed(milestone.id)
		if rungs > 0:
			_income *= pow(milestone.income_bonus, float(rungs))

# --- save ------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"milestones": {"progress": _progress.duplicate(), "claimed": _claimed.duplicate()}}

func from_save(root: Dictionary) -> void:
	var block: Dictionary = root.get("milestones", {})
	_progress = (block.get("progress", {}) as Dictionary).duplicate()
	_claimed = (block.get("claimed", {}) as Dictionary).duplicate()
	# Rebuilt from the claim counts rather than saved: the multiplier is derived data, and a
	# saved multiplier is a number that can disagree with the board that produced it.
	_recompute_income()
