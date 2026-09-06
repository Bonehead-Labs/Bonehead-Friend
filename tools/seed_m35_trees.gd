extends Node

## Writes the tier-1 augment tree for every item that has none.
##
##   Godot --headless --path <project> res://tools/seed_m35_trees.tscn
##
## M3 shipped trees for six items out of sixteen, so nine of them were a shop row and
## nothing else: bought once, used, and never improved again. A tree is the reason to keep
## using a toy after the next one is affordable, and an item without one silently drops out
## of the game the moment its successor is bought.
##
## Like `seed_m35_engine.gd`, the numbers are **derived from the item's own price** rather
## than authored one at a time, so retuning twenty-two trees is editing two constants here.
## Names are hand-written, because "Baseball +15% damage" is a spreadsheet row.
##
## Only writes what does not exist, so the six hand-tuned M3 trees are left exactly as they
## are.

const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")

const AUGMENTS_DIR := "res://Data/Augments"

## cost = FLOOR + item cost x SLOPE for the damage node; the other two are fractions of it.
## Reproduces M3's hand-picked mace tree (90 / 70 / 55 at a price of 900) closely enough
## that the two generations of tree sit in the same shop without a visible seam.
const COST_FLOOR := 50.0
const COST_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## The three shapes a tier-1 node comes in, matching what the item's own class actually
## reads. A node whose effect_key nothing reads is a placebo, and this milestone exists
## partly because two of those shipped (`open_hand_damage`, `open_hand_third`).
const KEY_MASS := &"mass_mult"
const KEY_COOLDOWN := &"cooldown_mult"

## `item id: [damage name, payout name, third name or ""]`.
##
## An empty third name is deliberate and means *this item has no honest third lever*. Pure
## generators — the sponge, the boombox, the fountain, the hot tub — have no rate to speed
## up and no weight that matters, so they get a two-node tier rather than a placebo. The
## tree UI draws a tier of two exactly as happily as a tier of three.
const TREES := {
	# --- weapons and throwables: the third node is weight, which is impulse ---
	&"dynamite": ["Bigger Charge", "Salvage Rights", "Denser Packing"],
	&"katana": ["Whetstone", "Trophy Cuts", "Heavier Tang"],
	&"mine": ["Wider Charge", "Scrap Rights", "Deeper Dish"],
	&"firework": ["More Powder", "Crowd Pleaser", "Heavier Head"],
	&"bowling_ball": ["Drilled Grip", "Strike Bonus", "Lead Core"],
	&"beach_ball": ["Firmer Inflation", "Party Rates", "Sand Filled"],
	&"trampoline": ["Tighter Springs", "Trick Bonus", "Steel Frame"],
	&"desk_fan": ["Higher Setting", "Wind Tax", "Cast Base"],
	# --- cursor powers: the third node is fire rate ---
	&"fist": ["Knuckle Duster", "Bare-Knuckle Purse", "Faster Hands"],
	&"shotgun": ["Tighter Choke", "Buckshot Bounty", "Pump Action"],
	&"missile": ["Bigger Warhead", "Salvage Contract", "Quicker Reload"],
	&"magnifying_glass": ["Sharper Focus", "Sunlight Tax", "Steadier Hand"],
	&"minigun": ["Heavier Rounds", "Volume Discount", "Spun Up"],
	&"gravity_vortex": ["Deeper Well", "Event Horizon Fees", "Faster Collapse"],
	&"lightning": ["Higher Voltage", "Storm Damages", "Shorter Recharge"],
	# --- friendly: damage_mult is the kindness value; the third is how often it lands ---
	&"pizza": ["Extra Toppings", "Delivery Tip", "Faster Service"],
	&"baseball": ["Better Throw", "Catch Bonus", "Quicker Return"],
	&"massage_chair": ["Deeper Kneading", "Spa Rates", "Shorter Cycle"],
	&"sponge": ["Coarser Pad", "Valet Rates", ""],
	&"boombox": ["Better Speakers", "Royalties", ""],
	&"chocolate_fountain": ["Richer Chocolate", "Fondue Rates", ""],
	&"hot_tub": ["Hotter Water", "Spa Membership", ""],

	# --- the M3.7 leisure roster ---
	# Comfort and ambience take two nodes, not three. The third lever is either weight or
	# rate, and a hammock has no meaningful amount of either — which is why the sponge, the
	# boombox and the hot tub have always stopped at two. An invented third node would be a
	# number nobody can feel, priced as though they could.
	&"beanbag": ["Deeper Fill", "Lounge Rates", ""],
	&"foot_spa": ["Hotter Jets", "Pedicure Rates", ""],
	&"hammock": ["Softer Weave", "Siesta Rates", ""],
	&"paddling_pool": ["Warmer Water", "Lido Rates", ""],
	&"heated_blanket": ["Higher Setting", "Tog Rating", ""],
	&"recliner": ["Deeper Recline", "Upholstery Rates", ""],

	&"cup_of_tea": ["Stronger Brew", "Service Charge", "Faster Steeping"],
	&"donut_box": ["Extra Glaze", "Baker's Dozen", "Quicker Boxing"],
	&"ice_cream": ["More Scoops", "Parlour Rates", "Faster Churn"],
	&"noodle_bowl": ["Richer Broth", "House Special", "Quicker Service"],
	&"birthday_cake": ["More Candles", "Party Rates", "Faster Baking"],

	&"houseplant": ["Better Soil", "Nursery Rates", ""],
	&"fairy_lights": ["Warmer Bulbs", "Festive Rates", ""],
	&"wind_chimes": ["Longer Tubes", "Tuning Fees", ""],
	&"lava_lamp": ["Thicker Wax", "Ambience Rates", ""],
	&"record_player": ["Better Stylus", "Pressing Royalties", ""],
	&"fish_tank": ["More Fish", "Aquarist Rates", ""],

	&"rubber_duck": ["Louder Squeak", "Bath Time Rates", "Faster Squeeze"],
	&"jigsaw_puzzle": ["More Pieces", "Completion Bonus", ""],
	&"bubble_machine": ["Bigger Bubbles", "Soap Rates", ""],

	# --- the hands-on kind items (assessment-2026-09) ---
	# Held things pay per second of touch and have no rate to speed up: two nodes. Thrown
	# things land on a cooldown, so their third lever is how soon they can land again.
	&"feather_duster": ["Fuller Plume", "Housekeeping Rates", ""],
	&"soft_brush": ["Softer Bristles", "Grooming Rates", "Quicker Strokes"],
	&"warm_towel": ["Fluffier Weave", "Turndown Rates", ""],
	&"tennis_ball": ["Fresher Felt", "Fetch Bonus", "Quicker Return"],
	&"party_popper": ["More Confetti", "Party Rates", "Shorter Fuse"],
	&"kite": ["Longer Tail", "Fair Weather Rates", "Faster Reel"],
}

## The items whose third lever is **weight**. Everything else with a third node gets a rate.
##
## Named outright rather than derived from the category, which is what this used to do and
## could not keep doing. M3.7 moved the massage chair into Comfort and the balls into Play,
## and any category rule then disagreed with the names already authored above: the chair's
## third node is called "Shorter Cycle" and would have been given mass, while the bowling
## ball's is "Lead Core" and would have been given a cooldown. The names are the design; a
## rule that contradicts them is wrong however tidy it looks.
const WEIGHTED := {
	&"dynamite": true, &"katana": true, &"mine": true, &"firework": true,
	&"bowling_ball": true, &"beach_ball": true, &"trampoline": true, &"desk_fan": true,
}

var _written := 0
var _skipped := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(AUGMENTS_DIR)
	for item in ItemDB.all_items():
		if not _has_tier_one(item.id):
			_tree_for(item)
	print("seed_m35_trees: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _has_tier_one(item_id: StringName) -> bool:
	for node in ItemDB.augments_for(item_id):
		if node.tier == 1:
			_skipped += 1
			return true
	return false

func _tree_for(item: ItemData) -> void:
	if not TREES.has(item.id):
		# Loudly, and without inventing a name: an item with no tree is an item nobody has a
		# reason to keep using, which is invisible in play and obvious six weeks later.
		push_error("seed_m35_trees: no tier-1 tree authored for '%s'" % item.id)
		return
	var names: Array = TREES[item.id]
	var currency := AugmentNodeScript.CURRENCY_HEARTS if item.currency == ItemData.CURRENCY_HEARTS \
		else AugmentNodeScript.CURRENCY_BONES
	var base := COST_FLOOR + float(item.cost) * COST_SLOPE

	_node("%s_damage" % item.id, item, names[0], &"damage_mult", 1.15,
		int(round(base)), 1.12, 0, currency)
	_node("%s_payout" % item.id, item, names[1], &"payout_mult", 1.12,
		int(round(base * PAYOUT_FRACTION)), 1.10, 1, currency)
	if String(names[2]).is_empty():
		return
	var third_key := KEY_COOLDOWN if _wants_rate(item) else KEY_MASS
	var third_effect := 0.94 if third_key == KEY_COOLDOWN else 1.08
	_node("%s_third" % item.id, item, names[2], third_key, third_effect,
		int(round(base * THIRD_FRACTION)), 1.09, 2, currency)

## Whether the item's third lever is a rate rather than a weight. A cursor power has no mass
## at all, and anything that pays on contact has a cooldown between helpings.
func _wants_rate(item: ItemData) -> bool:
	return not WEIGHTED.has(item.id)

func _node(id: String, item: ItemData, display_name: String, effect_key: StringName,
		effect_per_level: float, cost_base: int, cost_growth: float, sort_order: int,
		currency: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, id]
	if ResourceLoader.exists(path):
		return
	var node := AugmentNodeScript.new()
	node.id = StringName(id)
	node.item_id = item.id
	node.display_name = display_name
	node.effect_key = effect_key
	node.effect_per_level = effect_per_level
	node.max_levels = 10
	node.cost_base = cost_base
	node.cost_growth = cost_growth
	node.currency = currency
	node.sort_order = sort_order
	var err := ResourceSaver.save(node, path)
	if err != OK:
		push_error("seed_m35_trees: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
