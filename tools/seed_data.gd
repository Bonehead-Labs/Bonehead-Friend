extends Node

## Writes the initial res://Data content: balance.tres, the M2 item roster and the baseball
## bat's augment tree.
##
##   Godot --headless --path <project> res://tools/seed_data.tscn [-- --force]
##
## **Seed, not source of truth.** It writes only files that do not exist yet, so retuning a
## number in the inspector is never silently reverted by re-running it. Adding an item is
## still adding a .tres — this exists because hand-writing resource files is banned
## (CLAUDE.md) and because the initial roster had to come from somewhere.
##
## A scene rather than a `-s` script: autoload singletons are not registered under `-s`,
## and loading an item scene compiles scripts that reference Progression and ItemDB.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const BalanceDataScript := preload("res://Scripts/Data/balance_data.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const BALANCE_PATH := "res://Data/balance.tres"

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	DirAccess.make_dir_recursive_absolute(ITEMS_DIR)
	DirAccess.make_dir_recursive_absolute(AUGMENTS_DIR)

	_seed_balance()
	_seed_items()
	_seed_augments()

	print("seed_data: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- balance ---------------------------------------------------------------

func _seed_balance() -> void:
	if not _should_write(BALANCE_PATH):
		return
	var balance := BalanceDataScript.new()
	balance.mood_curve = _mood_curve()
	_save(balance, BALANCE_PATH)

## The U-curve from docs/economy.md, sampled over (mood + 100) / 200:
## 2.0x at despair, 0.6x at neutral, 2.0x at bliss. Neutral being the worst possible play
## is the whole reason optimal play oscillates.
func _mood_curve() -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 2.0
	curve.add_point(Vector2(0.0, 2.0))
	curve.add_point(Vector2(0.25, 1.2))
	curve.add_point(Vector2(0.5, 0.6))
	curve.add_point(Vector2(0.75, 1.2))
	curve.add_point(Vector2(1.0, 2.0))
	curve.bake()
	return curve

# --- items -----------------------------------------------------------------

func _seed_items() -> void:
	# Prices are the catalog's (docs/game-design.md). They are reachable in the slice
	# because the knockout bonus roughly doubles a round; retune there, not here.
	_item(&"baseball_bat", "Baseball Bat", "The tutorial weapon. Grab it, swing it, watch him clatter.",
		ItemDataScript.CATEGORY_WEAPON, 0, "res://Scenes/Bodies/baseball_bat.tscn", "res://Assets/sprites/icons/baseball_bat.png", 0)
	_item(&"mace", "Mace", "Heavy, slow and extremely satisfying.",
		ItemDataScript.CATEGORY_WEAPON, 900, "res://Scenes/Bodies/mace.tscn", "res://Assets/sprites/icons/mace.png", 10)

	_item(&"grenade", "Grenade", "Right-click while holding it to pull the pin.",
		ItemDataScript.CATEGORY_THROWABLE, 0, "res://Scenes/Bodies/grenade.tscn", "res://Assets/sprites/icons/grenade.png", 0)
	_item(&"dynamite", "Dynamite", "A bigger radius and a much bigger shove.",
		ItemDataScript.CATEGORY_THROWABLE, 800, "res://Scenes/Bodies/dynamite.tscn", "res://Assets/sprites/icons/dynamite.png", 10)

	_item(&"fist", "Fist", "Your hand, made of physics. Chases the cursor; click to punch.",
		ItemDataScript.CATEGORY_CURSOR_POWER, 0, "res://Scenes/Powers/fist_power.tscn", "res://Assets/FIST.png", 0)
	_item(&"pistol", "Pistol", "One shot at the crosshair. Shoves anything nearby.",
		ItemDataScript.CATEGORY_CURSOR_POWER, 600, "res://Scenes/Powers/gun_power.tscn", "res://Assets/Crosshair Basic.png", 10)
	_item(&"missile", "Missile Strike", "Mark a spot and a missile flies in and detonates on it.",
		ItemDataScript.CATEGORY_CURSOR_POWER, 2500, "res://Scenes/Powers/missile_power.tscn", "res://Assets/sprites/icons/missile.png", 20)

func _item(id: StringName, display_name: String, description: String, category: int,
		cost: int, scene_path: String, icon_path: String, sort_order: int) -> void:
	var path := "%s/%s.tres" % [ITEMS_DIR, id]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = id
	item.display_name = display_name
	item.description = description
	item.category = category
	item.cost = cost
	item.currency = ItemDataScript.CURRENCY_BONES
	item.scene = _require(scene_path)
	item.icon = _require(icon_path)
	item.sort_order = sort_order
	_save(item, path)

# --- augments --------------------------------------------------------------

## The bat's tier-1 tree: Damage / Payout / Rate, the shape every weapon shares
## (docs/economy.md). Growth is 1.12 on the headline damage node and lower on the
## utility ones, which is the 1.07-1.15 band the genre has converged on.
func _seed_augments() -> void:
	_augment(&"bat_damage", &"baseball_bat", "Heavier Swing", &"damage_mult", 1.15, 60, 1.12, 0)
	_augment(&"bat_payout", &"baseball_bat", "Bone Collector", &"payout_mult", 1.12, 45, 1.10, 1)
	_augment(&"bat_weight", &"baseball_bat", "Lead Core", &"mass_mult", 1.08, 35, 1.09, 2)

func _augment(id: StringName, item_id: StringName, display_name: String, effect_key: StringName,
		effect_per_level: float, cost_base: int, cost_growth: float, sort_order: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = id
	node.item_id = item_id
	node.display_name = display_name
	node.effect_key = effect_key
	node.effect_per_level = effect_per_level
	node.max_levels = 10
	node.cost_base = cost_base
	node.cost_growth = cost_growth
	node.currency = AugmentNodeScript.CURRENCY_BONES
	node.sort_order = sort_order
	_save(node, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

## res:// paths are case-sensitive in exported builds and resolve fine in the editor on
## Windows, which is how a wrong-case path shipped a crash once already (CLAUDE.md).
## Failing loudly here is the cheapest place to catch the next one.
func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_data: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_data: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
