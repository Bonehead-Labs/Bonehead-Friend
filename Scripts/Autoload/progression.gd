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

func _ready() -> void:
	SaveManager.register_provider(self)

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
	return EconomyMath.augment_cost(float(node.cost_base), node.cost_growth, owned)

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
	var affordable := AugmentMath.purchasable_levels(
		float(node.cost_base), node.cost_growth, owned, node.max_levels,
		Economy.balance_of(currency), levels)
	if affordable <= 0:
		return 0

	var cost := EconomyMath.bulk_cost(float(node.cost_base), node.cost_growth, owned, affordable)
	if not Economy.spend(currency, cost):
		return 0

	_augment_levels[node_id] = owned + affordable
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
		float(node.cost_base), node.cost_growth, augment_level(node_id), node.max_levels,
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

# --- mastery (M3) ----------------------------------------------------------

func mastery_xp(item_id: StringName) -> float:
	return float(_mastery_xp.get(item_id, 0.0))

## Highest rank whose XP threshold is met. Mastery gameplay lands in M3; the read side
## exists now so augment gating is written against its final shape rather than a stub.
func mastery_rank(item_id: StringName) -> int:
	var xp := mastery_xp(item_id)
	if xp <= 0.0:
		return 0
	var base := ItemDB.balance.mastery_base
	var rank := 0
	while rank < 100 and EconomyMath.mastery_xp_for_rank(base, rank + 1) <= xp:
		rank += 1
	return rank

## Shared Mastery Pool bonus applied to every payout. Flat until the pool exists.
func mastery_pool_bonus() -> float:
	return 1.0

## Bones per second from automation capstones. Zero until the first capstone ships in M3;
## Economy's offline path already calls it so the accrual is wired end to end.
func automation_rate_per_second() -> float:
	return 0.0

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

	return {
		"unlocks": unlocks,
		"augments": augments,
		"exclusive_choices": choices,
		"mastery_xp": xp,
		"mastery_pool": _mastery_pool,
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
	_modifier_cache.clear()
	grant_starters()

func _exclusive_key(item_id: StringName, group: StringName) -> String:
	return "%s/%s" % [item_id, group]
