extends Node

## Read-only content index, built once at boot by scanning res://Data.
##
## Nothing else loads a .tres by path. Adding an item or an augment is dropping a file
## into res://Data — no script edit, no registration list to forget (docs/decisions.md D8).

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const CONTRACTS_DIR := "res://Data/Contracts"
const PERSONALITIES_DIR := "res://Data/Personalities"
const BALANCE_PATH := "res://Data/balance.tres"

## The personality a save with none recorded gets. Also the fallback when a save names one
## that no longer exists — a removed personality must not zero out every payout in the game.
const DEFAULT_PERSONALITY := &"stoic"

## Every global tuning knob. Never null after _ready(): if the file is missing we fall
## back to a default-constructed BalanceData so a bad checkout degrades the tuning
## instead of crashing every system that reads a rate.
var balance: BalanceData

var _items: Dictionary = {}             ## StringName -> ItemData
var _augments: Dictionary = {}          ## StringName -> AugmentNode
var _augments_by_item: Dictionary = {}  ## StringName -> Array[AugmentNode]
var _items_sorted: Array[ItemData] = []
var _contracts: Dictionary = {}         ## StringName -> ContractData
var _contracts_sorted: Array[ContractData] = []
var _personalities: Dictionary = {}     ## StringName -> PersonalityData
var _personalities_sorted: Array[PersonalityData] = []

func _ready() -> void:
	_load_balance()
	_load_items()
	_load_augments()
	_load_contracts()
	_load_personalities()

# --- lookup ----------------------------------------------------------------

func has_item(id: StringName) -> bool:
	return _items.has(id)

func get_item(id: StringName) -> ItemData:
	return _items.get(id)

func get_augment(id: StringName) -> AugmentNode:
	return _augments.get(id)

## All items, in shop display order. The returned array is the cached one — treat it as
## read-only; it is rebuilt only at boot.
func all_items() -> Array[ItemData]:
	return _items_sorted

func items_in_category(category: int) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in _items_sorted:
		if item.category == category:
			out.append(item)
	return out

## The augment tree for one item, in tier then sort order.
func augments_for(item_id: StringName) -> Array[AugmentNode]:
	var found: Array[AugmentNode] = []
	found.assign(_augments_by_item.get(item_id, []))
	return found

func get_contract(id: StringName) -> ContractData:
	return _contracts.get(id)

func all_contracts() -> Array[ContractData]:
	return _contracts_sorted

func contracts_for_period(period: int) -> Array[ContractData]:
	var out: Array[ContractData] = []
	for contract in _contracts_sorted:
		if contract.period == period:
			out.append(contract)
	return out

func get_personality(id: StringName) -> PersonalityData:
	return _personalities.get(id)

func all_personalities() -> Array[PersonalityData]:
	return _personalities_sorted

## The mood curve in force. A personality *is* its curve (docs/data), so this is the whole
## of what a personality changes. Falls back to balance.tres when the save names one that no
## longer exists, because a missing sub-resource must degrade the tuning rather than zero
## out every payout in the game.
func mood_multiplier_for(personality_id: StringName, mood: float) -> float:
	var personality := get_personality(personality_id)
	if personality and personality.mood_curve:
		return personality.mood_curve.sample_baked(clampf((mood + 100.0) / 200.0, 0.0, 1.0))
	return balance.sample_mood_curve(mood)

## Items that are free from the first boot — the catalog's "free (starter)" entries.
func starter_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in _items_sorted:
		if item.is_starter():
			out.append(item)
	return out

# --- loading ---------------------------------------------------------------

## Content directories that are allowed to be absent. Contracts and personalities were both
## added in M3; a checkout from before then, or a build that ships without them, should lose
## the contract board rather than fail to boot.
const OPTIONAL_DIRS := [CONTRACTS_DIR, PERSONALITIES_DIR]

func _load_balance() -> void:
	var res := ResourceLoader.load(BALANCE_PATH) if ResourceLoader.exists(BALANCE_PATH) else null
	if res is BalanceData:
		balance = res
		return
	push_error("ItemDB: %s missing or not a BalanceData; using built-in defaults" % BALANCE_PATH)
	balance = BalanceData.new()

func _load_items() -> void:
	for res in _load_directory(ITEMS_DIR):
		var item := res as ItemData
		if item == null:
			push_error("ItemDB: %s is not an ItemData" % res.resource_path)
			continue
		var err := item.validation_error()
		if not err.is_empty():
			push_error("ItemDB: %s — %s" % [item.resource_path, err])
			continue
		if _items.has(item.id):
			push_error("ItemDB: duplicate item id '%s' in %s" % [item.id, item.resource_path])
			continue
		_items[item.id] = item

	_items_sorted.assign(_items.values())
	_items_sorted.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		if a.category != b.category:
			return a.category < b.category
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return String(a.id) < String(b.id))

func _load_contracts() -> void:
	for res in _load_directory(CONTRACTS_DIR):
		var contract := res as ContractData
		if contract == null:
			push_error("ItemDB: %s is not a ContractData" % res.resource_path)
			continue
		var err := contract.validation_error()
		if not err.is_empty():
			push_error("ItemDB: %s — %s" % [contract.resource_path, err])
			continue
		if _contracts.has(contract.id):
			push_error("ItemDB: duplicate contract id '%s'" % contract.id)
			continue
		# A contract watching a specific item that does not exist can never be completed,
		# and it would sit on the board looking exactly like one that can.
		var key := String(contract.goal_key)
		if key.begins_with(ContractData.ITEM_KEY_PREFIX):
			var item_id := StringName(key.substr(ContractData.ITEM_KEY_PREFIX.length()))
			if not _items.has(item_id):
				push_warning("ItemDB: contract '%s' targets unknown item '%s'" % [contract.id, item_id])
		_contracts[contract.id] = contract

	_contracts_sorted.assign(_contracts.values())
	_contracts_sorted.sort_custom(func(a: ContractData, b: ContractData) -> bool:
		if a.period != b.period:
			return a.period < b.period
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return String(a.id) < String(b.id))

func _load_personalities() -> void:
	for res in _load_directory(PERSONALITIES_DIR):
		var personality := res as PersonalityData
		if personality == null:
			push_error("ItemDB: %s is not a PersonalityData" % res.resource_path)
			continue
		var err := personality.validation_error()
		if not err.is_empty():
			push_error("ItemDB: %s — %s" % [personality.resource_path, err])
			continue
		if _personalities.has(personality.id):
			push_error("ItemDB: duplicate personality id '%s'" % personality.id)
			continue
		_personalities[personality.id] = personality

	_personalities_sorted.assign(_personalities.values())
	_personalities_sorted.sort_custom(func(a: PersonalityData, b: PersonalityData) -> bool:
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return String(a.id) < String(b.id))

func _load_augments() -> void:
	for res in _load_directory(AUGMENTS_DIR):
		var node := res as AugmentNode
		if node == null:
			push_error("ItemDB: %s is not an AugmentNode" % res.resource_path)
			continue
		var err := node.validation_error()
		if not err.is_empty():
			push_error("ItemDB: %s — %s" % [node.resource_path, err])
			continue
		if _augments.has(node.id):
			push_error("ItemDB: duplicate augment id '%s' in %s" % [node.id, node.resource_path])
			continue
		# An augment pointing at an item that does not exist is dead weight in the UI and
		# almost always a typo in the join key.
		if node.item_id != AugmentNode.GLOBAL and not _items.has(node.item_id):
			push_warning("ItemDB: augment '%s' targets unknown item '%s'" % [node.id, node.item_id])
		_augments[node.id] = node
		if not _augments_by_item.has(node.item_id):
			_augments_by_item[node.item_id] = []
		_augments_by_item[node.item_id].append(node)

	for item_id in _augments_by_item:
		var list: Array = _augments_by_item[item_id]
		list.sort_custom(func(a: AugmentNode, b: AugmentNode) -> bool:
			if a.tier != b.tier:
				return a.tier < b.tier
			if a.sort_order != b.sort_order:
				return a.sort_order < b.sort_order
			return String(a.id) < String(b.id))

## Directory scan that survives export.
##
## An exported build rewrites this directory: "Convert Text Resources To Binary" turns
## .tres into .res, and remapped files appear as "<name>.tres.remap". Scanning for a
## literal ".tres" therefore finds every resource in the editor and none in the shipped
## game — a bug that cannot be reproduced without exporting.
func _load_directory(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(dir):
		if not OPTIONAL_DIRS.has(dir):
			push_error("ItemDB: content directory %s does not exist" % dir)
		return out

	var seen := {}
	for file in DirAccess.get_files_at(dir):
		var file_name := file
		if file_name.ends_with(".remap") or file_name.ends_with(".import"):
			file_name = file_name.get_basename()
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := dir.path_join(file_name)
		if seen.has(path):
			continue
		seen[path] = true
		var res := ResourceLoader.load(path)
		if res == null:
			push_error("ItemDB: failed to load %s" % path)
			continue
		out.append(res)
	return out
