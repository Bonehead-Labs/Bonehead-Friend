extends Node

## Writes the tier-1 augment tree for every item that has none.
##
##   Godot --headless --path <project> res://tools/seed_m35_trees.tscn [-- --only id,id]
##
## `--only` rewrites what it names and nothing else, existing or not. An **item id** rewrites
## that item's whole tier-1 tree — how a tree is re-derived after its item changes currency or
## price (D64, the beach ball). A **node id** rewrites that node alone — how a node whose key,
## name or number changed here is re-seeded without churning its two siblings (D65 retargeted
## ten). Either way the ids themselves survive exactly: an id is a save key.
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
const KEY_DAMAGE := &"damage_mult"
const KEY_PAYOUT := &"payout_mult"
const KEY_MASS := &"mass_mult"
const KEY_COOLDOWN := &"cooldown_mult"
## D65's four. A field item's lever is its field; a fist's is how fast it chases; a treat's is
## how much it lifts his mood.
const KEY_PULL := &"pull_mult"
const KEY_WIND := &"wind_mult"
const KEY_SPEED := &"speed_mult"
const KEY_MOOD := &"mood_mult"

## Effect per level, by key. One number per lever rather than per node, so a retune is a line.
const EFFECT := {
	KEY_DAMAGE: 1.15, KEY_PAYOUT: 1.12, KEY_MASS: 1.08, KEY_COOLDOWN: 0.94,
	KEY_PULL: 1.10, KEY_WIND: 1.10, KEY_SPEED: 1.06, KEY_MOOD: 1.10,
}

## Items whose tree does not follow the damage / payout / rate-or-weight rule, as
## `[first, second, third]` keys. Each one is a node that used to be a placebo (D65):
##
##   desk_fan        "Higher Setting" is wind strength, as its name always said; a damage key
##                   on a thing that never hits him was the wrong key
##   gravity_vortex  "Faster Collapse" is the pull. It shortened a cooldown of 0
##   fist            "Faster Hands" is how fast it chases the cursor. Same cooldown of 0
const KEYS := {
	&"desk_fan": [KEY_WIND, KEY_PAYOUT, KEY_MASS],
	&"gravity_vortex": [KEY_DAMAGE, KEY_PAYOUT, KEY_PULL],
	&"fist": [KEY_DAMAGE, KEY_PAYOUT, KEY_SPEED],
}

## Eaten, drunk or popped on first contact, so the gap a rate node would shorten never runs —
## seven of them sold one. Their third lever is how much a helping lifts his mood instead:
## what food is *for*, and a real number in the pipeline, since mood is the U-curve every
## payout is multiplied by. A box of donuts is six helpings now and could have kept its
## rate, but one rule for the drawer is one sentence to learn.
const CONSUMED := {
	&"pizza": true, &"cup_of_tea": true, &"donut_box": true, &"ice_cream": true,
	&"noodle_bowl": true, &"birthday_cake": true, &"party_popper": true,
}

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
	&"trampoline": ["Tighter Springs", "Trick Bonus", "Steel Frame"],
	&"desk_fan": ["Higher Setting", "Wind Tax", "Cast Base"],
	# --- cursor powers: the third node is fire rate ---
	&"fist": ["Knuckle Duster", "Bare-Knuckle Purse", "Faster Hands"],
	&"missile": ["Bigger Warhead", "Salvage Contract", "Quicker Reload"],
	&"magnifying_glass": ["Sharper Focus", "Sunlight Tax", "Steadier Hand"],
	&"gravity_vortex": ["Deeper Well", "Event Horizon Fees", "Faster Collapse"],
	&"lightning": ["Higher Voltage", "Storm Damages", "Shorter Recharge"],
	# --- held guns since D71, cursor powers before: the third node is still the rate ---
	# Kept under the ids a player may have bought levels of. `seed_m39_guns` adds their Weight
	# and Steady. A double barrel has no pump, so "Pump Action" became "Snap Breech" (the
	# breech is what the rate node now shortens, with the gap between the barrels); the
	# minigun's "Spun Up" shortens its spin-up as well as its gap, which is what it said.
	&"shotgun": ["Tighter Choke", "Buckshot Bounty", "Snap Breech"],
	&"minigun": ["Heavier Rounds", "Volume Discount", "Spun Up"],
	# --- friendly: damage_mult is the kindness value; the third is how often it lands ---
	&"pizza": ["Extra Toppings", "Delivery Tip", "Comfort Food"],
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

	&"cup_of_tea": ["Stronger Brew", "Service Charge", "Calming Blend"],
	&"donut_box": ["Extra Glaze", "Baker's Dozen", "Sugar Rush"],
	&"ice_cream": ["More Scoops", "Parlour Rates", "Extra Sprinkles"],
	&"noodle_bowl": ["Richer Broth", "House Special", "Family Recipe"],
	&"birthday_cake": ["More Candles", "Party Rates", "Surprise Party"],

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
	# The beach ball was a weapon with a weight node ("Sand Filled") until D64 made it a catch; a
	# catch's third lever is how soon it pays again, the same as the tennis ball's.
	&"beach_ball": ["Firmer Inflation", "Party Rates", "Quicker Rallies"],
	&"tennis_ball": ["Fresher Felt", "Fetch Bonus", "Quicker Return"],
	&"party_popper": ["More Confetti", "Party Rates", "Best Day Ever"],
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
	&"bowling_ball": true, &"trampoline": true, &"desk_fan": true,
}

var _written := 0
var _skipped := 0
## `--only id,id`: item ids (a whole tier-1 tree) or node ids (one node). See the header.
var _only := PackedStringArray()

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only_at := args.find("--only")
	if only_at >= 0 and only_at + 1 < args.size():
		_only = args[only_at + 1].split(",", false)
	DirAccess.make_dir_recursive_absolute(AUGMENTS_DIR)
	for item in ItemDB.all_items():
		if not _only.is_empty():
			if _selects_item(item.id):
				_tree_for(item)
		elif not _has_tier_one(item.id):
			_tree_for(item)
	print("seed_m35_trees: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _has_tier_one(item_id: StringName) -> bool:
	for node in ItemDB.augments_for(item_id):
		if node.tier == 1:
			_skipped += 1
			return true
	return false

## Whether `--only` names this item or any node of its tree.
func _selects_item(item_id: StringName) -> bool:
	if _only.has(String(item_id)):
		return true
	for suffix in ["_damage", "_payout", "_third"]:
		if _only.has(String(item_id) + suffix):
			return true
	return false

func _tree_for(item: ItemData) -> void:
	if not TREES.has(item.id):
		if not _only.is_empty():
			return
		# Loudly, and without inventing a name: an item with no tree is an item nobody has a
		# reason to keep using, which is invisible in play and obvious six weeks later.
		push_error("seed_m35_trees: no tier-1 tree authored for '%s'" % item.id)
		return
	var names: Array = TREES[item.id]
	var currency := AugmentNodeScript.CURRENCY_HEARTS if item.currency == ItemData.CURRENCY_HEARTS \
		else AugmentNodeScript.CURRENCY_BONES
	var base := COST_FLOOR + float(item.cost) * COST_SLOPE
	var keys: Array = KEYS.get(item.id, [KEY_DAMAGE, KEY_PAYOUT, _third_key(item)])

	_node("%s_damage" % item.id, item, names[0], keys[0], EFFECT[keys[0]],
		int(round(base)), 1.12, 0, currency)
	_node("%s_payout" % item.id, item, names[1], keys[1], EFFECT[keys[1]],
		int(round(base * PAYOUT_FRACTION)), 1.10, 1, currency)
	if String(names[2]).is_empty():
		return
	_node("%s_third" % item.id, item, names[2], keys[2], EFFECT[keys[2]],
		int(round(base * THIRD_FRACTION)), 1.09, 2, currency)

## The third lever, when the item is not in `KEYS`: mood for a treat that is gone on first
## contact, weight for the named heavy things, and a rate for everything else — a cursor power
## has no mass at all, and anything that pays on contact has a cooldown between helpings.
func _third_key(item: ItemData) -> StringName:
	if CONSUMED.has(item.id):
		return KEY_MOOD
	return KEY_MASS if WEIGHTED.has(item.id) else KEY_COOLDOWN

func _node(id: String, item: ItemData, display_name: String, effect_key: StringName,
		effect_per_level: float, cost_base: int, cost_growth: float, sort_order: int,
		currency: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, id]
	if not _only.is_empty():
		if not (_only.has(id) or _only.has(String(item.id))):
			return
	elif ResourceLoader.exists(path):
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
