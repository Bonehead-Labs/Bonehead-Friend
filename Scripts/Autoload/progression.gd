extends Node

## What the player owns: unlocked items, augment levels, exclusive branch choices.
##
## Split from Economy because the two map 1:1 onto the Shop UI and the Tree UI. Economy
## owns money; Progression owns everything money has been turned into, and answers the one
## question the rest of the game asks: get_modifier().

## Multiplier lookups happen on every contact impulse, so the resolved value per
## (source_id, effect_key) is cached and invalidated on purchase rather than recomputed by
## walking the augment list sixty times a second.
var _modifier_cache: Dictionary = {}

var _unlocks: Dictionary = {}          ## StringName -> true
var _augment_levels: Dictionary = {}   ## StringName (node id) -> int
var _exclusive_choices: Dictionary = {}  ## "item_id/group" -> node id
var _mastery_xp: Dictionary = {}       ## StringName (item id) -> float
var _mastery_pool: int = 0

## Ranks are cached because mastery_multiplier() runs inside the payout pipeline, on every
## hit. Recomputing a pow() per item per payout would be paying for the cache miss sixty
## times a second in a game designed to idle for eight hours.
var _mastery_rank_cache: Dictionary = {}  ## StringName (item id) -> int

## Automation capstones the player has switched off. Absent means on, so a newly bought
## capstone starts running — and so a save written before this existed does not arrive with
## every automation disabled.
var _automation_off: Dictionary = {}   ## StringName (node id) -> true

## Rate per currency, cached. Economy asks for both every frame, and computing one walks
## every owned augment doing two dictionary lookups apiece — two array allocations and two
## full scans at 60 Hz, for the life of the process, even for a player who owns no capstone
## at all. Invalidated wherever ownership or the on/off state can change.
var _automation_rates: Dictionary = {}  ## StringName (currency) -> float

## Contract board state.
var _contract_progress: Dictionary = {}  ## StringName (contract id) -> int
var _contracts_claimed: Dictionary = {}  ## StringName -> true
var _active_contracts: Array[StringName] = []
var _contracts_refreshed_at: int = 0

## How often the contract board checks whether a period has turned over. The check itself is
## a couple of integer divisions that early-out, so this is cheap; it exists because the
## pitch is that the game stays open for eight hours, and a board that only rolls at boot
## means starting at 22:00 leaves yesterday's dailies on screen for the whole next day.
const CONTRACT_TICK_SECONDS := 60.0

func _ready() -> void:
	SaveManager.register_provider(self)
	# Mastery is earned by *using* a thing, so it accrues from the same two events the
	# payout pipeline runs on. Progression is an autoload and connects before any scene
	# node, which matters: Economy pays at the multipliers in force when the event fired.
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kindness_given.connect(_on_kindness)
	EventBus.kindness_sustained.connect(_on_kindness)
	EventBus.contract_event.connect(_on_contract_event)

	var board_timer := Timer.new()
	board_timer.wait_time = CONTRACT_TICK_SECONDS
	board_timer.autostart = true
	board_timer.timeout.connect(func() -> void: refresh_contracts())
	add_child(board_timer)

# --- items -----------------------------------------------------------------

func is_unlocked(item_id: StringName) -> bool:
	return _unlocks.has(item_id)

func owned_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in ItemDB.all_items():
		if is_unlocked(item.id):
			out.append(item)
	return out

## Prerequisites met and not already owned. Affordability is deliberately NOT part of
## this — the shop shows things you cannot yet afford, that is the point of a shop.
func can_purchase(item_id: StringName) -> bool:
	var item := ItemDB.get_item(item_id)
	if item == null or is_unlocked(item_id):
		return false
	for req in item.requires:
		if not is_unlocked(req):
			return false
	return true

func purchase_item(item_id: StringName) -> bool:
	var item := ItemDB.get_item(item_id)
	if item == null or not can_purchase(item_id):
		return false
	if not Economy.spend(item.currency_id(), float(item.cost)):
		return false
	_unlock(item_id)
	EventBus.item_purchased.emit(item_id)
	EventBus.contract_event.emit(&"purchase", 1)
	EventBus.save_requested.emit()
	return true

## Free starters are granted rather than bought, on every load — including saves written
## before the item existed, so adding a new free item never needs a save migration.
func grant_starters() -> void:
	for item in ItemDB.starter_items():
		if not is_unlocked(item.id):
			_unlock(item.id)

func _unlock(item_id: StringName) -> void:
	_unlocks[item_id] = true

# --- augments --------------------------------------------------------------

func augment_level(node_id: StringName) -> int:
	return int(_augment_levels.get(node_id, 0))

## Cost of the next level. Returns -1 when the node is maxed, so callers cannot
## accidentally charge for a level that does not exist.
func next_augment_cost(node_id: StringName) -> float:
	var node := ItemDB.get_augment(node_id)
	if node == null:
		return -1.0
	var owned := augment_level(node_id)
	if owned >= node.max_levels:
		return -1.0
	return EconomyMath.augment_cost(_discounted_base(node), node.cost_growth, owned)

## The node's base price after Mastery Pool discounts. Everything that quotes or charges for
## an augment goes through this — a discount applied in one place and not the other is a
## button that quotes one number and takes another.
func _discounted_base(node: AugmentNode) -> float:
	return float(node.cost_base) * augment_cost_multiplier()

## Cost of buying `levels` more, from where the player is now — the discounted price, which
## is the one they will actually be charged. The tree quoted `node.cost_base` directly and
## therefore printed the *undiscounted* bulk price: every pool checkpoint made the button
## lie by a little more, always in the direction of asking for money it was not going to
## take. Clamped to what is left, so a x10 on a node with three levels remaining quotes
## three.
func augment_bulk_cost(node_id: StringName, levels: int) -> float:
	var node := ItemDB.get_augment(node_id)
	if node == null or levels <= 0:
		return 0.0
	var owned := augment_level(node_id)
	var count := mini(levels, maxi(0, node.max_levels - owned))
	return EconomyMath.bulk_cost(_discounted_base(node), node.cost_growth, owned, count)

## Everything that gates a node except money: the owning item, prerequisite nodes, an
## already-taken exclusive branch, mastery and prestige. Reasons are returned as text so
## the UI can say *why* a node is locked instead of just greying it out.
func augment_lock_reason(node_id: StringName) -> String:
	var node := ItemDB.get_augment(node_id)
	if node == null:
		return "unknown augment"
	if node.item_id != AugmentNode.GLOBAL and not is_unlocked(node.item_id):
		return "requires the item"
	for req in node.requires:
		if augment_level(req) <= 0:
			return "requires an earlier node"
	if node.requires_mastery > mastery_rank(node.item_id):
		return "requires mastery %d" % node.requires_mastery
	if node.requires_prestige > Economy.prestige_count:
		return "requires reincarnation %d" % node.requires_prestige
	if node.exclusive_group != &"":
		var chosen := exclusive_choice(node.item_id, node.exclusive_group)
		if chosen != &"" and chosen != node.id:
			return "another branch is chosen"
	if augment_level(node_id) >= node.max_levels:
		return "maxed"
	return ""

func exclusive_choice(item_id: StringName, group: StringName) -> StringName:
	return _exclusive_choices.get(_exclusive_key(item_id, group), &"")

func purchase_augment(node_id: StringName, levels: int = 1) -> int:
	var node := ItemDB.get_augment(node_id)
	if node == null or levels <= 0:
		return 0
	if not augment_lock_reason(node_id).is_empty():
		return 0

	var owned := augment_level(node_id)
	var currency := node.currency_id()
	var base := _discounted_base(node)
	var affordable := AugmentMath.purchasable_levels(
		base, node.cost_growth, owned, node.max_levels,
		Economy.balance_of(currency), levels)
	if affordable <= 0:
		return 0

	var cost := EconomyMath.bulk_cost(base, node.cost_growth, owned, affordable)
	if not Economy.spend(currency, cost):
		return 0

	_augment_levels[node_id] = owned + affordable
	_automation_rates.clear()
	if node.exclusive_group != &"":
		_exclusive_choices[_exclusive_key(node.item_id, node.exclusive_group)] = node.id
	_modifier_cache.clear()
	EventBus.augment_purchased.emit(node_id, _augment_levels[node_id])
	EventBus.save_requested.emit()
	return affordable

## How many levels the player could buy right now with what they are holding.
func affordable_augment_levels(node_id: StringName) -> int:
	var node := ItemDB.get_augment(node_id)
	if node == null:
		return 0
	return AugmentMath.purchasable_levels(
		_discounted_base(node), node.cost_growth, augment_level(node_id), node.max_levels,
		Economy.balance_of(node.currency_id()))

# --- the question everything else asks -------------------------------------

## Combined multiplier for one effect on one source: the item's own nodes and every
## &"global" node, multiplied together. 1.0 when nothing applies.
func get_modifier(source_id: StringName, effect_key: StringName) -> float:
	var key := "%s/%s" % [source_id, effect_key]
	if _modifier_cache.has(key):
		return float(_modifier_cache[key])

	var entries: Array = []
	for node in ItemDB.augments_for(source_id):
		if node.effect_key == effect_key:
			entries.append([node.effect_per_level, augment_level(node.id)])
	if source_id != AugmentNode.GLOBAL:
		for node in ItemDB.augments_for(AugmentNode.GLOBAL):
			if node.effect_key == effect_key:
				entries.append([node.effect_per_level, augment_level(node.id)])

	var value := AugmentMath.total_modifier(entries)
	_modifier_cache[key] = value
	return value

# --- mastery ---------------------------------------------------------------

func mastery_xp(item_id: StringName) -> float:
	return float(_mastery_xp.get(item_id, 0.0))

## Highest rank whose XP threshold is met.
func mastery_rank(item_id: StringName) -> int:
	if _mastery_rank_cache.has(item_id):
		return int(_mastery_rank_cache[item_id])
	var b := ItemDB.balance
	var rank := MasteryMath.rank_for_xp(b.mastery_base, mastery_xp(item_id), b.mastery_exponent)
	_mastery_rank_cache[item_id] = rank
	return rank

## Fraction of the way to the next rank, for a progress bar.
func mastery_progress(item_id: StringName) -> float:
	var b := ItemDB.balance
	return MasteryMath.rank_progress(b.mastery_base, mastery_xp(item_id), b.mastery_exponent)

func mastery_pool() -> int:
	return _mastery_pool

## XP earned by using a thing, proportional to the value it delivered. A rank gained drops a
## point into the shared pool — that pool is the answer to the genre's oldest question, why
## you would ever use the shotgun once you own the rocket launcher.
func add_mastery_xp(item_id: StringName, amount: float) -> void:
	if item_id == &"" or amount <= 0.0 or not ItemDB.has_item(item_id):
		return
	var before := mastery_rank(item_id)
	_mastery_xp[item_id] = mastery_xp(item_id) + amount
	var after := MasteryMath.rank_for_xp(ItemDB.balance.mastery_base, _mastery_xp[item_id],
		ItemDB.balance.mastery_exponent)
	_mastery_rank_cache[item_id] = after
	if after <= before:
		return
	_mastery_pool += after - before
	_automation_rates.clear()
	EventBus.mastery_rank_up.emit(item_id, after)
	# Debounced, not immediate: rank 1 costs 100 XP, so early ranks land every few seconds
	# of active play and `save_requested` writes the whole file synchronously each time.
	SaveManager.request_autosave()

## The `x mastery` step of the payout pipeline: the shared pool's global bonus, times this
## item's own rank-50 bonus. One function so the two cannot be applied in different places
## and quietly double up.
func mastery_multiplier(source_id: StringName) -> float:
	var b := ItemDB.balance
	var pool := MasteryMath.pool_multiplier(_mastery_pool, b.mastery_pool_thresholds,
		b.mastery_pool_income_step)
	var item := MasteryMath.item_rank_multiplier(mastery_rank(source_id),
		b.mastery_bonus_rank, b.mastery_rank_payout_bonus)
	return pool * item

## Kept as the documented name for the pool half alone, for the UI.
func mastery_pool_bonus() -> float:
	var b := ItemDB.balance
	return MasteryMath.pool_multiplier(_mastery_pool, b.mastery_pool_thresholds,
		b.mastery_pool_income_step)

## Pool checkpoints make augments cheaper. Applied to the quoted price *and* the charge, so
## the button never quotes one number and takes another.
func augment_cost_multiplier() -> float:
	var b := ItemDB.balance
	return MasteryMath.pool_multiplier(_mastery_pool, b.mastery_pool_thresholds,
		b.mastery_pool_cost_step)

## Extra concurrent items from pool checkpoints. Read by ItemSpawner.
func item_limit_bonus() -> int:
	var b := ItemDB.balance
	return MasteryMath.pool_flat_bonus(_mastery_pool, b.mastery_pool_thresholds,
		b.mastery_pool_item_step)

func _on_damage_dealt(info: HitInfo) -> void:
	add_mastery_xp(info.source_id, info.amount * ItemDB.balance.mastery_xp_per_damage)

func _on_kindness(source_id: StringName, value: float, _world_pos: Vector2) -> void:
	add_mastery_xp(source_id, value * ItemDB.balance.mastery_xp_per_kindness)

# --- automation ------------------------------------------------------------

## Every automation capstone the player owns, whether or not it is switched on.
func automation_nodes() -> Array[AugmentNode]:
	var out: Array[AugmentNode] = []
	for node_id in _augment_levels:
		var node := ItemDB.get_augment(node_id)
		if node and node.is_automation and augment_level(node.id) > 0:
			out.append(node)
	return out

## Every automation has an on/off toggle. That is not a convenience — it is what the Focus
## Mode promise requires: a player in a meeting must be able to stop the desktop moving
## without giving up the income (docs/game-design.md).
func is_automation_enabled(node_id: StringName) -> bool:
	return not _automation_off.has(node_id)

func set_automation_enabled(node_id: StringName, enabled: bool) -> void:
	if enabled:
		_automation_off.erase(node_id)
	else:
		_automation_off[node_id] = true
	_automation_rates.clear()
	EventBus.save_requested.emit()

## Currency per second from every switched-on capstone of that currency. A weapon automates
## into Bones and a friendly item into Hearts, so the caller has to say which it wants.
func automation_rate_per_second(currency: StringName = &"bones") -> float:
	if _automation_rates.has(currency):
		return float(_automation_rates[currency])
	var total := _compute_automation_rate(currency)
	_automation_rates[currency] = total
	return total

func _compute_automation_rate(currency: StringName) -> float:
	var total := 0.0
	for node in automation_nodes():
		if not is_automation_enabled(node.id):
			continue
		if _automation_currency(node) != currency:
			continue
		total += node.automation_rate * float(augment_level(node.id))
	return total

## What a capstone pays out in: the owning item's own currency, so a weapon automates into
## Bones and a friendly item into Hearts. Resolved from the item rather than stored on the
## node, because a second field could disagree with the item it names.
func _automation_currency(node: AugmentNode) -> StringName:
	var item := ItemDB.get_item(node.item_id)
	return item.currency_id() if item else Economy.BONES

# --- contracts -------------------------------------------------------------

func active_contracts() -> Array[ContractData]:
	var out: Array[ContractData] = []
	for id in _active_contracts:
		var contract := ItemDB.get_contract(id)
		if contract:
			out.append(contract)
	return out

func contract_progress(contract_id: StringName) -> int:
	return int(_contract_progress.get(contract_id, 0))

func is_contract_complete(contract_id: StringName) -> bool:
	var contract := ItemDB.get_contract(contract_id)
	return contract != null and contract_progress(contract_id) >= contract.target

func is_contract_claimed(contract_id: StringName) -> bool:
	return _contracts_claimed.has(contract_id)

## Pays out a finished contract. Rewards are Ectoplasm, so a contract is never a faster way
## to buy the next toy — the shop ladder's pacing stays set by play rather than by the
## calendar (docs/game-design.md).
func claim_contract(contract_id: StringName) -> bool:
	var contract := ItemDB.get_contract(contract_id)
	if contract == null or not is_contract_complete(contract_id) or is_contract_claimed(contract_id):
		return false
	_contracts_claimed[contract_id] = true
	Economy.grant_ectoplasm(contract.reward_ectoplasm)
	if contract.reward_currency_amount > 0.0:
		Economy.grant(contract.currency_id(), contract.reward_currency_amount)
	EventBus.contract_claimed.emit(contract_id, contract.reward_ectoplasm)
	EventBus.save_requested.emit()
	return true

## Rolls a new board when a period has elapsed. Seeded by the period index rather than by
## chance, so the board is stable across a restart inside the same day — a shuffle on every
## boot would let a player reroll until they liked the offer.
##
## The two periods roll **independently**: crossing midnight redraws the dailies and leaves a
## weekly's progress alone, which is the entire difference between a daily and a weekly.
##
## Cheap to call and safe to call often — it early-returns unless a period has actually
## turned over.
func refresh_contracts(force: bool = false) -> void:
	var now := int(Time.get_unix_time_from_system())
	var day := int(floor(float(now) / 86400.0))
	var week := day / 7
	var last_day := int(floor(float(_contracts_refreshed_at) / 86400.0))
	var last_week := last_day / 7
	var fresh := _contracts_refreshed_at <= 0

	var roll_daily := force or fresh or day != last_day
	var roll_weekly := force or fresh or week != last_week
	if not roll_daily and not roll_weekly:
		return

	var b := ItemDB.balance
	if roll_daily:
		_reroll(ContractData.PERIOD_DAILY, b.contracts_daily_slots, day)
	if roll_weekly:
		_reroll(ContractData.PERIOD_WEEKLY, b.contracts_weekly_slots, week)
	_contracts_refreshed_at = now
	EventBus.contract_board_changed.emit()

## Replaces every contract of one period on the board, and wipes the progress and claim of
## **every contract of that period** — not just the ones leaving.
##
## Clearing only the departing ones was the original bug and it was invisible: with four
## dailies and three slots, a claimed daily comes back the next day about three times in
## four, still flagged claimed, rendering a full bar and paying nothing. One of three slots
## quietly dead, and worse every day.
func _reroll(period: int, slots: int, seed_value: int) -> void:
	for contract in ItemDB.contracts_for_period(period):
		_contract_progress.erase(contract.id)
		_contracts_claimed.erase(contract.id)

	var kept: Array[StringName] = []
	for id in _active_contracts:
		var existing := ItemDB.get_contract(id)
		if existing and existing.period != period:
			kept.append(id)
	_active_contracts = kept
	_active_contracts.append_array(_roll(period, slots, seed_value))

func _roll(period: int, slots: int, seed_value: int) -> Array[StringName]:
	var pool := ItemDB.contracts_for_period(period)
	var out: Array[StringName] = []
	if pool.is_empty() or slots <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/%d" % [period, seed_value])
	var indices: Array[int] = []
	for i in pool.size():
		indices.append(i)
	for i in mini(slots, pool.size()):
		var pick := rng.randi_range(0, indices.size() - 1)
		out.append(pool[indices[pick]].id)
		indices.remove_at(pick)
	return out

func _on_contract_event(key: StringName, count: int) -> void:
	if count <= 0:
		return
	for id in _active_contracts:
		var contract := ItemDB.get_contract(id)
		if contract == null or contract.goal_key != key or is_contract_claimed(id):
			continue
		var before := contract_progress(id)
		if before >= contract.target:
			continue
		_contract_progress[id] = mini(before + count, contract.target)
		if _contract_progress[id] >= contract.target:
			EventBus.contract_completed.emit(id)

# --- prestige --------------------------------------------------------------

## Wipes everything money has been turned into. Economy owns the currencies and the
## ectoplasm award; this is the other half of a Reincarnation.
##
## Contracts survive deliberately: they are a real-time hook, not a run-scoped one, and
## resetting them would let a player farm a daily by prestiging.
func reset_for_prestige() -> void:
	_unlocks.clear()
	_augment_levels.clear()
	_exclusive_choices.clear()
	_mastery_xp.clear()
	_mastery_rank_cache.clear()
	_automation_off.clear()
	_automation_rates.clear()
	_mastery_pool = 0
	_modifier_cache.clear()
	grant_starters()

# --- save ------------------------------------------------------------------

func to_save() -> Dictionary:
	var unlocks: Array = []
	for id in _unlocks:
		unlocks.append(String(id))
	unlocks.sort()  # Stable ordering keeps save diffs readable.

	# JSON object keys are strings; StringName keys would round-trip as strings anyway and
	# then silently miss every StringName lookup on load.
	var augments := {}
	for id in _augment_levels:
		augments[String(id)] = int(_augment_levels[id])
	var choices := {}
	for k in _exclusive_choices:
		choices[String(k)] = String(_exclusive_choices[k])
	var xp := {}
	for id in _mastery_xp:
		xp[String(id)] = float(_mastery_xp[id])

	var automation_off: Array = []
	for id in _automation_off:
		automation_off.append(String(id))
	automation_off.sort()

	var progress := {}
	for id in _contract_progress:
		progress[String(id)] = int(_contract_progress[id])
	var active: Array = []
	for id in _active_contracts:
		active.append(String(id))
	var claimed: Array = []
	for id in _contracts_claimed:
		claimed.append(String(id))
	claimed.sort()

	return {
		"unlocks": unlocks,
		"augments": augments,
		"exclusive_choices": choices,
		"mastery_xp": xp,
		"mastery_pool": _mastery_pool,
		"automation_off": automation_off,
		"contracts": {
			"active": active,
			"progress": progress,
			"claimed": claimed,
			"refreshed_at": _contracts_refreshed_at,
		},
	}

func from_save(root: Dictionary) -> void:
	_unlocks.clear()
	for id in root.get("unlocks", []):
		_unlocks[StringName(id)] = true

	_augment_levels.clear()
	var augments: Dictionary = root.get("augments", {})
	for id in augments:
		_augment_levels[StringName(id)] = int(augments[id])

	_exclusive_choices.clear()
	var choices: Dictionary = root.get("exclusive_choices", {})
	for k in choices:
		_exclusive_choices[String(k)] = StringName(choices[k])

	_mastery_xp.clear()
	var xp: Dictionary = root.get("mastery_xp", {})
	for id in xp:
		_mastery_xp[StringName(id)] = float(xp[id])

	_mastery_pool = int(root.get("mastery_pool", 0))
	_mastery_rank_cache.clear()
	_automation_rates.clear()

	_automation_off.clear()
	for id in root.get("automation_off", []):
		_automation_off[StringName(id)] = true

	var contracts: Dictionary = root.get("contracts", {})
	_active_contracts.clear()
	for id in contracts.get("active", []):
		_active_contracts.append(StringName(id))
	_contract_progress.clear()
	for id in contracts.get("progress", {}):
		_contract_progress[StringName(id)] = int(contracts["progress"][id])
	_contracts_claimed.clear()
	for id in contracts.get("claimed", []):
		_contracts_claimed[StringName(id)] = true
	_contracts_refreshed_at = int(contracts.get("refreshed_at", 0))

	_modifier_cache.clear()
	grant_starters()
	# After loading, not before: a board rolled against an empty save would be replaced by
	# the saved one a moment later, and a save from yesterday needs today's board.
	refresh_contracts()
	# Unconditional: the load replaced `_active_contracts` whether or not a period also
	# rolled, so anything holding a row keyed to a contract id is stale either way.
	EventBus.contract_board_changed.emit()

func _exclusive_key(item_id: StringName, group: StringName) -> String:
	return "%s/%s" % [item_id, group]
