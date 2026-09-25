extends Node

## M3.6's ten explosives: scenes, items, tier-1 trees, one exclusive branch and an automation
## capstone each. The Boom category goes from four rungs to fourteen.
##
##   Godot --headless --path <project> res://tools/seed_m36_explosives.tscn [-- --force | --only id,id]
##
## **The ladder is not "the same bang, bigger", and it cannot be.** A single hit is clamped at
## `knockout_damage x max_hit_fraction` — half a knockout — before it ever reaches the payout
## pipeline, so an explosive priced at 300,000 cannot buy its way past a grenade on damage
## alone. What it buys instead is *reach*, *number of blasts* and *where the blast happens*:
## a cluster of nine, a fire that keeps burning, a charge that sticks to him so falloff never
## applies, a well that drags the desk into the middle before it goes off. That constraint is
## the reason this category is interesting rather than a list of radii.
##
## Three of the ten need behaviour and have a class each (`ClusterBomb`, `StickyBomb`,
## `BlackHoleCharge`); three more are those same classes with different numbers, which is the
## point of D8. The rest are `ThrowableBase` and `ProximityMine` with a table entry — said
## out loud in the `script` column rather than given a class of their own to look busy.
##
## Same rules as every other seed tool: resources are generated from script because
## hand-editing `.tres` is banned, and only files that do not already exist are written.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const ThrowableBaseScript := preload("res://Scripts/Bodies/throwable_base.gd")
const ProximityMineScript := preload("res://Scripts/Bodies/proximity_mine.gd")
const ClusterBombScript := preload("res://Scripts/Bodies/cluster_bomb.gd")
const StickyBombScript := preload("res://Scripts/Bodies/sticky_bomb.gd")
const BlackHoleChargeScript := preload("res://Scripts/Bodies/black_hole_charge.gd")

const BODIES_DIR := "res://Scenes/Bodies"
const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const ICONS_DIR := "res://Assets/sprites/icons"

## Where the Boom ladder picks up. The catalog runs 0 / 800 / 2,500 / 6,000 and stopped; ten
## rungs at roughly x1.45 each carry it to 300,000 without ever asking for more than half a
## tier's income in one go (docs/economy.md's five-minute rule).
const FIRST_GATE := &"firework"
const FIRST_SORT_ORDER := 40
const SORT_STEP := 10

## Tier-1 tree, derived from the item's own price exactly as `seed_m35_trees.gd` derives it,
## so the two generations of tree sit in one shop without a visible seam.
const COST_FLOOR := 50.0
const COST_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## Capstones, derived from the item's price by `seed_m35_engine.gd`'s rule. Every one is
## priced in **Hearts** whatever it automates — D2's spine.
const AUTOMATION_LEVELS := 30
const AUTOMATION_GROWTH := 1.10
const AUTOMATION_BASE_RATE := 1.0
const AUTOMATION_RATE_SLOPE := 1.0 / 500.0
const AUTOMATION_PRICE_FLOOR := 800.0
const AUTOMATION_PRICE_SLOPE := 0.4

## The ten, in price order. Order is load-bearing three times over: it is the shop's
## `sort_order`, and it is the `requires` chain — each rung gated behind the one below it, so
## a fourteen-item Boom page arrives a row at a time instead of all at once on hour one.
##
##   script      the behaviour, named rather than invented: four of these are a table entry
##   mass        kilograms-ish. Damage is contact impulse and impulse is mass x velocity (D7)
##   blast       the ExplosionArea's radius, in world units. The grenade's is 120
##   shapes      art pixels, authored only where the silhouette genuinely is not a box (D25)
##   tree        [damage, payout, weight] node names — the flavour, and the only hand part
##   device      [augment id, device name, one line] for the automation capstone
##
## `damage_mult` stays modest across the whole ladder on purpose. It is multiplied by the
## damage tree (x4.0 maxed) and read at the epicentre of a quadratic falloff, so a base value
## that already sits on the per-hit clamp makes that tree a placebo. `max_force` is allowed to
## be enormous instead: it is the *knockback*, which is uncapped, and knockback is the joke.
const EXPLOSIVES := [
	{
		"id": &"concussion_charge",
		"name": "Concussion Charge",
		"description": "All shove and no bite. He travels further than he ever has and arrives more or less intact.",
		"cost": 9000,
		"script": ThrowableBaseScript,
		"mass": 1.4,
		"blast": 300.0,
		"properties": {"damage_mult": 0.3, "throwable_delay": 2.0, "max_force": 26000.0},
		"tree": ["Overpressure", "Insurance Claim", "Heavier Casing"],
		"device": [&"concussion_lobber", "Concussion Lobber",
			"A spring arm that pops one over the desk every few seconds. Nothing is ever where you left it."],
	},
	{
		"id": &"nail_bomb",
		"name": "Nail Bomb",
		"description": "A tin, some nails and a fuse. Nine small unpleasant things instead of one big one.",
		"cost": 13000,
		"script": ClusterBombScript,
		"mass": 1.6,
		"blast": 80.0,
		# A ball, and a box would catch on its corners and stop dead where a ball rolls to
		# his feet — which is where a nail bomb wants to be.
		"shapes": [{"circle": 11.0}],
		"properties": {
			"damage_mult": 1.0, "throwable_delay": 2.5, "max_force": 5000.0,
			"submunitions": 9, "submunition_interval": 0.03, "spread": 120.0,
			"submunition_radius": 64.0, "submunition_force": 4200.0,
		},
		"tree": ["Longer Nails", "Scrap Metal Rates", "Packed Tighter"],
		"device": [&"nail_hopper", "Nail Hopper",
			"It feeds itself from a bucket of nails. The bucket is never empty."],
	},
	{
		"id": &"sticky_bomb",
		"name": "Sticky Bomb",
		"description": "It goes where you throw it and then it stays there. He has noticed.",
		"cost": 19000,
		"script": StickyBombScript,
		"mass": 1.0,
		"blast": 150.0,
		"properties": {
			"damage_mult": 1.2, "throwable_delay": 2.2, "max_force": 14000.0,
			"contact_delay": 1.2,
		},
		"tree": ["Stronger Tack", "Adhesion Fees", "Denser Putty"],
		"device": [&"sticky_dispenser", "Tar Dispenser",
			"A nozzle that flicks a fresh one at him every time the last one stops sticking."],
	},
	{
		"id": &"oil_drum",
		"name": "Oil Drum",
		"description": "Leave it standing about. He will find it, the way he finds everything.",
		# ProximityMine, not a class of its own: what a drum does differently from a mine is
		# that it is heavy and the blast is bigger, and both of those are numbers.
		"cost": 28000,
		"script": ProximityMineScript,
		"mass": 18.0,
		"blast": 260.0,
		"properties": {
			"damage_mult": 1.1, "max_force": 20000.0, "arm_seconds": 0.7,
		},
		"tree": ["Full to the Brim", "Salvage Yard Rates", "Steel Banding"],
		"device": [&"drum_yard", "Drum Yard",
			"A pallet of drums, restocked overnight by somebody. He keeps walking into them."],
	},
	{
		"id": &"cluster_bomb",
		"name": "Cluster Bomb",
		"description": "The casing is the boring part. It opens on the way down.",
		"cost": 42000,
		"script": ClusterBombScript,
		"mass": 2.4,
		"blast": 130.0,
		"properties": {
			"damage_mult": 1.3, "throwable_delay": 2.6, "max_force": 9000.0,
			"submunitions": 5, "submunition_interval": 0.14, "spread": 155.0,
			"submunition_radius": 105.0, "submunition_force": 8000.0,
		},
		"tree": ["More Bomblets", "Area Coverage Fees", "Heavier Canister"],
		"device": [&"cluster_mortar", "Cluster Mortar",
			"A short tube that fires straight up. What comes down is the point."],
	},
	{
		"id": &"napalm_charge",
		"name": "Napalm Charge",
		"description": "Lights a patch of desk and keeps it lit. Standing in it is his decision.",
		"cost": 62000,
		"script": ClusterBombScript,
		"mass": 2.8,
		"blast": 150.0,
		# Fourteen blasts at almost no spread across six seconds: the same class as the
		# cluster bomb with the two knobs turned the other way, which is the only
		# damage-over-time on a placed area in the roster.
		"properties": {
			"damage_mult": 0.9, "throwable_delay": 2.4, "max_force": 3000.0,
			"submunitions": 14, "submunition_interval": 0.42, "spread": 42.0,
			"submunition_radius": 140.0, "submunition_force": 2800.0,
		},
		"tree": ["Thicker Jelly", "Burn Rates", "Fuller Canister"],
		"device": [&"napalm_pilot_light", "Pilot Light",
			"A burner that never goes out, on a supply line nobody has audited."],
	},
	{
		"id": &"satchel_charge",
		"name": "Satchel Charge",
		"description": "A canvas bag with far too much in it. Somebody has written a time on the side.",
		"cost": 90000,
		"script": ThrowableBaseScript,
		"mass": 6.0,
		"blast": 320.0,
		# The one silhouette here that is genuinely not a box: a bag with the charge standing
		# out of its mouth and a strap arched over both (D69). Weight in the bag and the pin at
		# the top of the strap, so it hangs the way a bag hangs from a hand and swings its own
		# weight when you throw it.
		"shapes": [
			{"rect": Vector2(42, 25), "at": Vector2(0, 7.5)},
			{"rect": Vector2(16, 9), "at": Vector2(-2, -9.5)},
			{"rect": Vector2(22, 5), "at": Vector2(0, -17.5)},
			{"capsule": Vector2(4.5, 12), "at": Vector2(-12, -10.5), "rot": 39.8},
			{"capsule": Vector2(4.5, 12), "at": Vector2(12, -10.5), "rot": -39.8},
		],
		"com": Vector2(0, 7),
		"grip": Vector2(0, -18.5),
		"grab": {"size": Vector2(30, 36), "at": Vector2(0, 0)},
		"properties": {"damage_mult": 1.5, "throwable_delay": 3.5, "max_force": 22000.0},
		"tree": ["Packed Full", "Courier Rates", "Reinforced Bag"],
		"device": [&"satchel_courier", "Courier Run",
			"A bag arrives on the hour. Nobody signs for it."],
	},
	{
		"id": &"implosion_charge",
		"name": "Implosion Charge",
		"description": "Collects the desk first, then goes off in the middle of it.",
		"cost": 130000,
		"script": BlackHoleChargeScript,
		"mass": 2.0,
		"blast": 230.0,
		"shapes": [{"circle": 14.0}],
		"properties": {
			"damage_mult": 1.6, "throwable_delay": 2.6, "max_force": 24000.0,
			"pull_accel": 10000.0, "pull_seconds": 1.3,
		},
		"tree": ["Deeper Collapse", "Vacuum Rates", "Denser Core"],
		"device": [&"implosion_compressor", "Compressor",
			"It gathers up the desk, holds it a moment, and gives most of it back."],
	},
	{
		"id": &"demolition_charge",
		"name": "Demolition Charge",
		"description": "Four bricks, a timer and a permit nobody checked. It clears the whole desk.",
		"cost": 200000,
		"script": ThrowableBaseScript,
		"mass": 9.0,
		"blast": 400.0,
		"properties": {"damage_mult": 1.8, "throwable_delay": 4.0, "max_force": 30000.0},
		"tree": ["Bigger Order", "Site Clearance Fees", "More Bricks"],
		"device": [&"demolition_permit", "Demolition Permit",
			"Signed, stamped, and renewed automatically."],
	},
	{
		"id": &"black_hole_charge",
		"name": "Black Hole Charge",
		"description": "Gathers up everything you own, holds it for a moment, then hands it all back at once.",
		"cost": 300000,
		"script": BlackHoleChargeScript,
		"mass": 3.0,
		"blast": 320.0,
		"shapes": [{"circle": 16.0}],
		"properties": {
			"damage_mult": 2.2, "throwable_delay": 3.0, "max_force": 34000.0,
			"pull_accel": 11000.0, "pull_seconds": 2.2,
		},
		"tree": ["Wider Horizon", "Spaghettification Fee", "Heavier Singularity"],
		"device": [&"black_hole_containment", "Containment Failure",
			"The word 'contained' was doing a great deal of work in the brochure."],
	},
]

## The one tier-2 branch in this batch, and the reason it is the only one: a cluster bomb has
## a genuine three-way identity — fewer and heavier, more and lighter, or not a weapon at all
## — while the other nine have one job each. `mass_mult` and `cooldown_mult` are not options
## here, because nothing on a thrown body reads either (see the notes on this milestone), so
## a branch built on them would be three pictures of the same node.
##
## Priced at half the canister's own shop price: a real decision, and still well under what
## maxing its damage node costs, because this is a choice rather than a ladder.
const CLUSTER_BRANCH := [
	[&"cluster_airburst", "Airburst", "It goes off before it lands, so everything is in the picture.",
		&"payout_mult", 1.8],
	[&"cluster_bunker_load", "Bunker Load", "Fewer bomblets. Each one considerably more serious.",
		&"damage_mult", 1.7],
	[&"cluster_confetti_load", "Confetti Load", "Streamers and a bang. He forgives you immediately.",
		&"damage_mult", 0.3],
]

var _force := false
## `--only id,id`: rewrite those ids' scenes and nothing else (D61). The way to re-seed a body
## after its physics row changes — `--force` would also rewrite every item and augment this tool
## owns, including the ones later milestones refined; D55 tried that and the suite caught it.
var _only := PackedStringArray()
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	var only_at := OS.get_cmdline_user_args().find("--only")
	if only_at >= 0 and only_at + 1 < OS.get_cmdline_user_args().size():
		_only = OS.get_cmdline_user_args()[only_at + 1].split(",", false)
	for dir in [BODIES_DIR, ITEMS_DIR, AUGMENTS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	_seed_scenes()
	_seed_items()
	_seed_trees()
	_seed_capstones()
	_seed_branch()

	print("seed_m36_explosives: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	for entry in EXPLOSIVES:
		var id: StringName = entry["id"]
		var path := "%s/%s.tscn" % [BODIES_DIR, id]
		if not _should_write(path):
			continue
		var spec := {
			"name": "_%s" % String(id).to_pascal_case(),
			"id": id,
			"script": entry["script"],
			"mass": entry["mass"],
			"blast_radius": entry["blast"],
			"properties": entry["properties"],
		}
		# Everything the table has no opinion about takes the factory's derived box around
		# the sprite's opaque bounds, which is the right shape for a canister, a drum and a
		# block of bricks — and deliberately so, rather than by omission.
		for authored in ["shapes", "com", "grip", "grab"]:
			if entry.has(authored):
				spec[authored] = entry[authored]
		var root := ItemBodyBuilder.build(spec)
		if root == null:
			continue
		if ItemBodyBuilder.save_scene(root, path):
			_written += 1
			print("  wrote %s" % path)

# --- items -----------------------------------------------------------------

func _seed_items() -> void:
	var previous := FIRST_GATE
	var sort_order := FIRST_SORT_ORDER
	for entry in EXPLOSIVES:
		var id: StringName = entry["id"]
		var path := "%s/%s.tres" % [ITEMS_DIR, id]
		# The gate is walked whether or not the file is written, so a re-run over a
		# half-seeded Data folder still chains the rungs it does write to the right parent.
		var gate := previous
		previous = id
		var order := sort_order
		sort_order += SORT_STEP
		if not _should_write(path):
			continue

		var item := ItemDataScript.new()
		item.id = id
		item.display_name = entry["name"]
		item.description = entry["description"]
		item.category = ItemDataScript.CATEGORY_THROWABLE
		item.cost = entry["cost"]
		item.currency = ItemDataScript.CURRENCY_BONES
		item.scene = _require("%s/%s.tscn" % [BODIES_DIR, id])
		item.sort_order = order
		var requires: Array[StringName] = [gate]
		item.requires = requires
		var icon := "%s/%s.png" % [ICONS_DIR, id]
		if ResourceLoader.exists(icon):
			item.icon = ResourceLoader.load(icon)
		else:
			push_warning("seed_m36_explosives: no icon at %s — run make_icons.py" % icon)
		_save(item, path)

# --- augments --------------------------------------------------------------

## Damage, payout and weight, at costs derived from the item's own price. Names are
## hand-written per item, because "Nail Bomb +15% damage" is a spreadsheet row.
func _seed_trees() -> void:
	for entry in EXPLOSIVES:
		var id: StringName = entry["id"]
		var names: Array = entry["tree"]
		var base := COST_FLOOR + float(entry["cost"]) * COST_SLOPE
		_augment_node("%s_damage" % id, id, names[0], &"damage_mult", 1.15,
			int(round(base)), 1.12, 0)
		_augment_node("%s_payout" % id, id, names[1], &"payout_mult", 1.12,
			int(round(base * PAYOUT_FRACTION)), 1.10, 1)
		_augment_node("%s_third" % id, id, names[2], &"mass_mult", 1.08,
			int(round(base * THIRD_FRACTION)), 1.09, 2)

func _augment_node(node_id: String, item_id: StringName, display_name: String,
		effect_key: StringName, effect_per_level: float, cost_base: int, cost_growth: float,
		sort_order: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, node_id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = StringName(node_id)
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

## One levelled device per item, priced and rated off the item's own price so the ladder
## stays monotonic without anybody maintaining a second ordering by hand. Every one is
## Hearts-priced whatever it automates: you cannot stop working for your money without
## having been kind to him (D2).
func _seed_capstones() -> void:
	for entry in EXPLOSIVES:
		var device: Array = entry["device"]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
		if not _should_write(path):
			continue
		var cost := float(entry["cost"])
		var node := AugmentNodeScript.new()
		node.id = device[0]
		node.item_id = entry["id"]
		node.display_name = device[1]
		node.description = device[2]
		node.tier = 3
		# A capstone's effect is its rate, not a multiplier, so effect_key is inert here and
		# effect_per_level stays 1.0 — see AugmentNode.automation_rate.
		node.effect_key = &"payout_mult"
		node.effect_per_level = 1.0
		node.max_levels = AUTOMATION_LEVELS
		node.cost_base = int(round(AUTOMATION_PRICE_FLOOR + cost * AUTOMATION_PRICE_SLOPE))
		node.cost_growth = AUTOMATION_GROWTH
		node.currency = AugmentNodeScript.CURRENCY_HEARTS
		node.is_automation = true
		# round(x * 100) / 100, not snappedf: snapping returns the double one ulp above the
		# value, which serialises as 2.8000000000000003. These files are read by people.
		var rate := AUTOMATION_BASE_RATE + cost * AUTOMATION_RATE_SLOPE
		node.automation_rate = round(rate * 100.0) / 100.0
		node.requires_mastery = ItemDB.balance.mastery_automation_rank
		# Every explosive is thrown, so every device stands on a tripod.
		node.device_mount = &"tripod"
		_save(node, path)

func _seed_branch() -> void:
	var owner_id := &"cluster_bomb"
	var price := 0
	for entry in EXPLOSIVES:
		if entry["id"] == owner_id:
			price = int(round(float(entry["cost"]) * 0.5))
			break
	for pick in CLUSTER_BRANCH:
		var path := "%s/%s.tres" % [AUGMENTS_DIR, pick[0]]
		if not _should_write(path):
			continue
		var node := AugmentNodeScript.new()
		node.id = pick[0]
		node.item_id = owner_id
		node.display_name = pick[1]
		node.description = pick[2]
		node.tier = 2
		node.effect_key = pick[3]
		node.effect_per_level = pick[4]
		node.max_levels = 1
		node.cost_base = price
		node.cost_growth = 1.0
		node.currency = AugmentNodeScript.CURRENCY_BONES
		node.exclusive_group = &"flavour"
		node.requires_mastery = 10
		_save(node, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if not _only.is_empty():
		if path.get_extension() == "tscn" and _only.has(path.get_file().get_basename()):
			return true
		_skipped += 1
		return false
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m36_explosives: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m36_explosives: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
