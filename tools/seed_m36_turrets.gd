extends Node

## Writes the automatic turret category: eight placeable guns, their scenes, their trees and
## their Hearts-priced automation capstones.
##
##   Godot --headless --path <project> res://tools/seed_m36_turrets.tscn [-- --force | --only id,id]
##
## A turret is the first thing in the roster that is neither swung nor thrown nor equipped:
## you put it on the desk, it finds him, and it fires until you pick it up again. That is a
## different verb from everything else in the shop, which is why it is a category of its own
## rather than five more weapons.
##
## **The economy rule this category could have broken.** Automation is Hearts-priced,
## everywhere, always (docs/decisions.md D2) — a Bones-priced machine that earned while the
## player was away would walk straight around the game's spine. The split is in
## `Scripts/Bodies/turret_base.gd`'s class comment and is worth restating once here: the item
## costs Bones, a placed turret pays only while the game is open and banks nothing offline,
## and the capstone that makes it work while you are away costs Hearts like every other
## capstone in the game.
##
## Same rules as every other seed tool: scenes are packed from script because hand-editing a
## `.tscn` is banned, only files that do not already exist are written, and the numbers that
## can be derived are derived — a retune here is an edit to four constants rather than to
## forty resources.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const TurretBaseScript := preload("res://Scripts/Bodies/turret_base.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const TURRETS_DIR := "res://Scenes/Turrets"
const ICONS_DIR := "res://Assets/sprites/icons"

## Tier-1 tree pricing, identical to `tools/seed_m35_trees.gd` so a turret's tree and a
## katana's sit in the same panel without a visible seam.
const TREE_FLOOR := 50.0
const TREE_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## Capstone pricing, identical to `tools/seed_m35_engine.gd`'s Bones line. Every turret is a
## Bones item, so there is only the one line to reproduce: rate per level 1.0 + cost/500,
## price 800 + cost x 0.4, charged in **Hearts** whatever it automates.
const CAPSTONE_BASE_RATE := 1.0
const CAPSTONE_RATE_SLOPE := 1.0 / 500.0
const CAPSTONE_PRICE_FLOOR := 800.0
const CAPSTONE_PRICE_SLOPE := 0.4
const CAPSTONE_MAX_LEVELS := 30
const CAPSTONE_COST_GROWTH := 1.10

## A tier-2 pick, as a fraction of the item's own price. The M3 bat's branch is a flat 900
## against a free bat, which is not a rule anything can be derived from; a quarter of the
## price puts the choice a little under three tier-1 levels away and scales with the ladder.
const EXCLUSIVE_COST_FRACTION := 0.25

## The ladder's first rung hangs off the pistol rather than off nothing. A player should have
## shot him by hand before buying a machine that does it for them, and it keeps a sixth shop
## tab from turning up full of unaffordable hardware on the first afternoon.
const LADDER_ROOT := &"pistol"

## The category, in ladder order — the dictionary's own order is the shop's order and the
## `requires` chain, so a rung cannot be inserted in the wrong place.
##
## **Rhythm is the design, not force.** Eight turrets that differ only in `blast_force` are
## one turret with a price ladder attached, so every row here moves at least two of
## The `muzzle` is where the shot leaves, in the sprite's own pixels from its centre, read off
## the art with a probe of its opaque pixels (D43); `faces` is the way the art points and
## `flips` whether it mirrors to face him — a coil, a lattice and a rack do not. Aim caps are
## how far the whole sprite may turn toward him: a gun swings, a mortar tips, a rack barely.
## `fire_interval`, `pellets`, `spread` and `max_range` as well: a nail gun is a stream you
## can barely see the individual shots in, a mortar is one enormous thump every few seconds,
## a flamethrower has to be carried over and set down beside him, and a rail gun reaches
## across the whole desk. `max_range` is what makes *where you put it* a decision at all.
##
## Physics is authored (docs/decisions.md D25) and every number below is in art pixels, y
## down, with the sprite centred on the origin. The shape that matters is the same for all
## eight and is the opposite of the bat's: **centre of mass low, in the base; drag pin high,
## above it**. A body pinned above its own weight hangs the right way up, so a turret picked
## up off the desk swings back upright and lands standing, which is the one thing a machine
## on legs has to do.
##
## **A turret that `flips` is solid only where its picture is in both facings** (D61). It
## turns its sprite round to face him and its colliders do not turn with it, so a shape over
## a part drawn on one side only is a shape over empty desk half the time. The rail gun's
## stand and the nail gun's post are drawn off-centre and are therefore not solid; each still
## stands on a centred foot that is. The laser lattice does not flip, and only its frame is
## solid — the beams are light, which is the whole joke of walking into them.
const TURRETS := {
	&"pellet_turret": {
		"node": "_PelletTurret",
		"name": "Pellet Turret",
		"description": "Plinks away at him from the corner of the desk without being asked. It is not accurate. It does not need to be.",
		"cost": 4000,
		"turret": {
			"fire_interval": 1.1, "blast_radius": 30.0, "blast_force": 900.0,
			"damage_mult": 1.0, "pellets": 1, "spread": 0.0, "max_range": 340.0,
			"aim_lean_degrees": 40.0, "muzzle": Vector2(19, -3), "faces": 1.0, "flips": true, "barrel_pivot": Vector2(-1, 1), "recoil_pixels": 3.0,
		},
		"body": {
			"mass": 8.0,
			"shapes": [
				{"rect": Vector2(40, 5), "at": Vector2(0, -3)},
				{"rect": Vector2(18, 8), "at": Vector2(0, -4.5)},
				{"rect": Vector2(12, 6), "at": Vector2(0, 3)},
				{"capsule": Vector2(2.5, 10), "at": Vector2(-8, 10.5), "rot": 20.6},
				{"capsule": Vector2(2.5, 10), "at": Vector2(8, 10.5), "rot": -20.6},
			],
			"com": Vector2(0, 10), "grip": Vector2(0, -11),
			"grab": {"size": Vector2(30, 34), "at": Vector2(0, 0)},
		},
		"tree": ["Heavier Pellets", "Plink Bounty", "Faster Feed"],
		"device": [&"pellet_turret_night_shift", "Night Shift",
			"It keeps plinking long after you have shut the lid."],
	},
	&"nail_gun": {
		"node": "_NailGun",
		"name": "Nail Gun Stand",
		"description": "A nail gun clamped to a post, firing at whatever is in front of it. Usually him.",
		"cost": 9000,
		# The stream. Tiny per-shot force at seven shots a second, so it reads as a texture
		# rather than as a series of hits — and it is the only turret whose individual shots
		# nobody can count.
		"turret": {
			"fire_interval": 0.14, "blast_radius": 18.0, "blast_force": 420.0,
			"damage_mult": 0.9, "pellets": 1, "spread": 7.0, "max_range": 260.0,
			"aim_lean_degrees": 35.0, "muzzle": Vector2(12, -13), "faces": 1.0, "flips": true, "barrel_pivot": Vector2(-4, -3), "recoil_pixels": 2.0,
		},
		"body": {
			"mass": 9.0,
			"shapes": [
				{"rect": Vector2(24, 3), "at": Vector2(0, -12.5)},
				{"rect": Vector2(12, 10), "at": Vector2(0, -12.5)},
				{"rect": Vector2(8, 3), "at": Vector2(0, 10.5)},
				{"rect": Vector2(12, 4), "at": Vector2(0, 14)},
			],
			"com": Vector2(0, 11), "grip": Vector2(0, -13),
			"grab": {"size": Vector2(30, 38), "at": Vector2(0, 0)},
		},
		"tree": ["Longer Nails", "Piecework Rates", "Higher Pressure"],
		"device": [&"nail_gun_belt_feed", "Belt Feed",
			"A belt long enough that nobody has to be here to change it."],
	},
	&"tesla_coil": {
		"node": "_TeslaCoil",
		"name": "Tesla Coil",
		"description": "Hums for a second, then bites. Nobody has explained to it what a desk is for.",
		"cost": 20000,
		"turret": {
			"fire_interval": 1.6, "blast_radius": 64.0, "blast_force": 2400.0,
			"damage_mult": 1.35, "pellets": 1, "spread": 0.0, "max_range": 300.0,
			"aim_lean_degrees": 5.0, "muzzle": Vector2(-1, -21), "faces": 1.0, "flips": false, "recoil_pixels": 1.0,
		},
		"body": {
			"mass": 14.0,
			"shapes": [
				{"rect": Vector2(26, 15), "at": Vector2(-1, 14)},
				{"rect": Vector2(9, 16), "at": Vector2(-1.5, -1)},
				{"capsule": Vector2(14, 21), "at": Vector2(-1.5, -15.5), "rot": 90.0},
			],
			"com": Vector2(0, 15), "grip": Vector2(0, -16),
			"grab": {"size": Vector2(30, 48), "at": Vector2(0, 0)},
		},
		"tree": ["More Windings", "Shock Damages", "Shorter Charge"],
		"device": [&"tesla_coil_grid_tap", "Grid Tap",
			"Wired straight into the building. The building was not asked."],
	},
	&"flamethrower": {
		"node": "_Flamethrower",
		"name": "Flamethrower Nozzle",
		"description": "Short reach, long memory. Set it down next to him and leave the room.",
		"cost": 45000,
		# The one that has to be *placed*. 150 of reach is about two body widths, so this is
		# the turret you carry over and put beside him rather than one you leave in a corner.
		"turret": {
			"fire_interval": 0.1, "blast_radius": 44.0, "blast_force": 400.0,
			"damage_mult": 1.15, "pellets": 1, "spread": 16.0, "max_range": 150.0,
			"aim_lean_degrees": 35.0, "muzzle": Vector2(-27, -2), "faces": -1.0, "flips": true, "barrel_pivot": Vector2(-2, 4), "recoil_pixels": 1.0,
		},
		"body": {
			"mass": 11.0,
			"shapes": [
				{"rect": Vector2(54, 10), "at": Vector2(0, -1)},
				{"rect": Vector2(16, 5), "at": Vector2(0, -9)},
				{"rect": Vector2(9, 5), "at": Vector2(-21.5, -9)},
				{"rect": Vector2(9, 5), "at": Vector2(21.5, -9)},
				{"rect": Vector2(8, 7), "at": Vector2(0, 7.5)},
				{"rect": Vector2(18, 5), "at": Vector2(0, 13.5)},
			],
			"com": Vector2(0, 12), "grip": Vector2(0, -10),
			"grab": {"size": Vector2(34, 40), "at": Vector2(0, 0)},
		},
		"tree": ["Hotter Mix", "Scorch Fees", "Wider Valve"],
		"device": [&"flamethrower_pilot_light", "Pilot Light",
			"It never goes out. Neither, apparently, does he."],
	},
	&"rail_gun": {
		"node": "_RailGun",
		"name": "Rail Gun",
		"description": "Charges for a while, then removes him from wherever he was standing.",
		"cost": 90000,
		# Rare, pinpoint and enormous, and the only turret that reaches across a 3440px
		# overlay — so it is the one that can be left in a corner and forgotten.
		"turret": {
			"fire_interval": 2.8, "blast_radius": 22.0, "blast_force": 7200.0,
			"damage_mult": 2.2, "pellets": 1, "spread": 0.0, "max_range": 900.0,
			"aim_lean_degrees": 30.0, "muzzle": Vector2(45, -7), "faces": 1.0, "flips": true, "barrel_pivot": Vector2(-16, 2), "recoil_pixels": 6.0,
		},
		"body": {
			"mass": 20.0,
			"shapes": [
				{"rect": Vector2(92, 9), "at": Vector2(0, -8.5)},
				{"rect": Vector2(54, 3), "at": Vector2(0, -2.5)},
				{"rect": Vector2(14, 12), "at": Vector2(0, 5)},
				{"rect": Vector2(20, 7), "at": Vector2(0, 14.5)},
			],
			"com": Vector2(0, 16), "grip": Vector2(0, -13),
			"grab": {"size": Vector2(40, 52), "at": Vector2(0, 0)},
		},
		"tree": ["Denser Slug", "Demolition Rates", "Quicker Charge"],
		"device": [&"rail_gun_capacitor_bank", "Capacitor Bank",
			"Charges itself between shots, and between sessions."],
	},
	&"mortar": {
		"node": "_Mortar",
		"name": "Mortar",
		"description": "Lobs one shell every few seconds and takes most of the desk with it.",
		"cost": 160000,
		# Slow and enormous: the widest blast in the game, which means it also throws every
		# loose prop on the desk, itself included. That is the joke and the drawback at once.
		"turret": {
			"fire_interval": 3.6, "blast_radius": 110.0, "blast_force": 9000.0,
			"damage_mult": 2.6, "pellets": 1, "spread": 0.0, "max_range": 700.0,
			"aim_lean_degrees": 25.0, "muzzle": Vector2(11, -20), "faces": 1.0, "flips": true, "recoil_pixels": 7.0,
		},
		"body": {
			"mass": 18.0,
			"shapes": [
				{"rect": Vector2(30, 6), "at": Vector2(0, -10.5)},
				{"rect": Vector2(14, 3), "at": Vector2(0, -15)},
				{"rect": Vector2(6, 11), "at": Vector2(0, -0.5)},
				{"rect": Vector2(26, 9), "at": Vector2(0, 14)},
			],
			"com": Vector2(0, 13), "grip": Vector2(0, -12),
			"grab": {"size": Vector2(34, 44), "at": Vector2(0, 0)},
		},
		"tree": ["Bigger Shell", "Bombardment Rates", "Faster Crew"],
		"device": [&"mortar_fire_plan", "Fire Plan",
			"Coordinates worked out once, in advance, for one skeleton."],
	},
	&"laser_lattice": {
		"node": "_LaserLattice",
		"name": "Laser Lattice",
		"description": "A grid of beams he keeps walking into. He has not learned. He will not.",
		"cost": 260000,
		# Three thin beams scattered wide rather than one shot: it does not aim so much as
		# fill the space he is standing in, which is why its spread is the largest here.
		"turret": {
			"fire_interval": 0.45, "blast_radius": 26.0, "blast_force": 1300.0,
			"damage_mult": 1.6, "pellets": 3, "spread": 48.0, "max_range": 240.0,
			"aim_lean_degrees": 4.0, "muzzle": Vector2(0, 0), "faces": 1.0, "flips": false, "recoil_pixels": 0.0,
		},
		"body": {
			"mass": 22.0,
			"shapes": [
				{"rect": Vector2(54, 7), "at": Vector2(0, -23)},
				{"rect": Vector2(54, 7), "at": Vector2(0, 22.5)},
				{"rect": Vector2(7, 38), "at": Vector2(-22.5, 0)},
				{"rect": Vector2(7, 38), "at": Vector2(22.5, 0)},
			],
			"com": Vector2(0, 20), "grip": Vector2(0, -22),
			"grab": {"size": Vector2(38, 58), "at": Vector2(0, 0)},
		},
		"tree": ["Tighter Beams", "Grid Tariff", "More Emitters"],
		"device": [&"laser_lattice_lights_out", "Lights Out",
			"The grid stays live in the dark. That is the entire idea."],
	},
	&"swarm_launcher": {
		"node": "_SwarmLauncher",
		"name": "Swarm Launcher",
		"description": "Forty tubes, no aim, one skeleton. The arithmetic works out.",
		"cost": 400000,
		# The top of the ladder is a salvo, not a bigger bullet: six blasts scattered wide
		# enough that some miss, which is what makes it read as a volley.
		"turret": {
			"fire_interval": 0.9, "blast_radius": 34.0, "blast_force": 1800.0,
			"damage_mult": 1.9, "pellets": 6, "spread": 72.0, "max_range": 620.0,
			"aim_lean_degrees": 6.0, "muzzle": Vector2(0, -26), "faces": 1.0, "flips": false, "recoil_pixels": 4.0,
		},
		"body": {
			"mass": 26.0,
			"shapes": [
				{"rect": Vector2(49, 30), "at": Vector2(-0.5, 0)},
				{"rect": Vector2(39, 11), "at": Vector2(-5.5, -20.5)},
				{"rect": Vector2(40, 11), "at": Vector2(-2, 20.5)},
			],
			"com": Vector2(0, 17), "grip": Vector2(0, -14),
			"grab": {"size": Vector2(38, 56), "at": Vector2(0, 0)},
		},
		"tree": ["Bigger Warheads", "Volume Contract", "Rapid Salvo"],
		"device": [&"swarm_launcher_reload_crane", "Reload Crane",
			"It restocks itself. You are now the least busy thing on the desk."],
	},
}

## One tier-2 branch in the whole category, and it belongs to the mortar.
##
## A branch is only worth writing where the item has a genuine three-way identity, and eight
## of them would be twenty-four resources restating the same three multipliers. The mortar is
## the one turret whose shell is an actual choice: one that lands harder, one that is full of
## things worth collecting afterwards, and one that trades size for a shell every two seconds
## instead of every four. `cooldown_mult` rather than a damage penalty is what keeps the third
## option a different *shape* of turret rather than a worse one.
##
## [id, name, description, effect_key, effect_per_level]
const MORTAR_SHELLS := [
	[&"mortar_siege_shell", "Siege Shell", "One shell. It only has to land once.",
		&"damage_mult", 1.7],
	[&"mortar_scrap_shell", "Scrap Shell", "Packed with things worth picking up afterwards.",
		&"payout_mult", 1.9],
	[&"mortar_cluster_shell", "Cluster Shell", "Smaller charges, twice as often. He never gets to stand up.",
		&"cooldown_mult", 0.6],
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
	for dir in [ITEMS_DIR, AUGMENTS_DIR, TURRETS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	_seed_scenes()
	_seed_items()
	_seed_trees()
	_seed_capstones()
	_seed_shells()

	print("seed_m36_turrets: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	for id in TURRETS:
		var path := "%s/%s.tscn" % [TURRETS_DIR, id]
		# Checked before the build, not after: `save_scene` frees what it is handed, so a
		# root built for a file we then decline to write would leak a whole scene tree.
		if not _should_write(path):
			continue
		var root := ItemBodyBuilder.build(_spec(id, TURRETS[id]))
		if root == null:
			continue
		_split_barrel(root, id)
		if ItemBodyBuilder.save_scene(root, path):
			_written += 1
			print("  wrote %s" % path)

func _spec(id: StringName, row: Dictionary) -> Dictionary:
	var body: Dictionary = row["body"]
	return {
		"name": row["node"],
		"id": id,
		"script": TurretBaseScript,
		"mass": body["mass"],
		# Nothing bounces off a turret and nothing slides one across the desk. The material
		# exists at all only because ItemBodyBuilder writes one when `bounce` is given.
		"bounce": 0.0,
		"friction": 0.95,
		"shapes": body["shapes"],
		"com": body["com"],
		"grip": body["grip"],
		"grab": body["grab"],
		# The turret's own numbers go in `properties` and never as a top-level `blast_radius`.
		# That key is ItemBodyBuilder's, and passing it would hang an unused ExplosionArea and
		# a dangling `explosion_area` assignment off a class that queries the physics space
		# directly and owns no area at all.
		"properties": row["turret"],
	}

# --- items -----------------------------------------------------------------

## The ladder, gated rung by rung. Derived from the table's order rather than typed out
## eight times, so the chain cannot come apart when a turret is inserted or repriced.
func _seed_items() -> void:
	var previous := LADDER_ROOT
	var order := 0
	for id in TURRETS:
		order += 10
		_item(id, TURRETS[id], previous, order)
		previous = StringName(id)

func _item(id: StringName, row: Dictionary, requires: StringName, sort_order: int) -> void:
	var path := "%s/%s.tres" % [ITEMS_DIR, id]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = id
	item.display_name = row["name"]
	item.description = row["description"]
	item.category = ItemDataScript.CATEGORY_TURRET
	item.cost = row["cost"]
	# Bones, and only Bones. It is a gun: buying it with Hearts would read as affection.
	item.currency = ItemDataScript.CURRENCY_BONES
	item.scene = _require("%s/%s.tscn" % [TURRETS_DIR, id])
	item.sort_order = sort_order
	# It shoots by itself, so its damage is not the player being at the desk. See
	# `ItemData.is_autonomous` — without this a single running turret pins IdleBrain awake
	# forever and he never plays with anything again.
	item.is_autonomous = true
	var gate: Array[StringName] = []
	gate.assign([requires])
	item.requires = gate
	var icon := "%s/%s.png" % [ICONS_DIR, id]
	if ResourceLoader.exists(icon):
		item.icon = ResourceLoader.load(icon)
	_save(item, path)

# --- trees -----------------------------------------------------------------

## Three tier-1 nodes each, priced by `seed_m35_trees.gd`'s rule.
##
## The third node is **fire rate**, under `cooldown_mult`, and not the `mass_mult` that the
## rest of the physical roster gets. A turret is not swung, so its mass is felt only when it
## is thrown across the room, and nothing in `TurretBase` reads `mass_mult` at all — a node
## whose effect_key nothing reads is a placebo, and two of those shipped in M3 already. The
## gap between shots is what a turret actually is.
func _seed_trees() -> void:
	for id in TURRETS:
		var row: Dictionary = TURRETS[id]
		var names: Array = row["tree"]
		var base := TREE_FLOOR + float(row["cost"]) * TREE_SLOPE
		_tier_one("%s_damage" % id, id, names[0], &"damage_mult", 1.15,
			int(round(base)), 1.12, 0)
		_tier_one("%s_payout" % id, id, names[1], &"payout_mult", 1.12,
			int(round(base * PAYOUT_FRACTION)), 1.10, 1)
		_tier_one("%s_third" % id, id, names[2], &"cooldown_mult", 0.94,
			int(round(base * THIRD_FRACTION)), 1.09, 2)

func _tier_one(node_id: String, item_id: StringName, display_name: String,
		effect_key: StringName, effect_per_level: float, cost_base: int,
		cost_growth: float, sort_order: int) -> void:
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
	_save_if_new(node, "%s/%s.tres" % [AUGMENTS_DIR, node_id])

# --- capstones -------------------------------------------------------------

## One levelled device per turret, **priced in Hearts**.
##
## This is the half of the category that pays while the game is closed, and it is the half
## that costs kindness. The turret on the desk earns nothing offline by construction (see
## `TurretBase`); this is what turns it into an idle engine, and the price of that is having
## been good to him.
func _seed_capstones() -> void:
	for id in TURRETS:
		var row: Dictionary = TURRETS[id]
		var device: Array = row["device"]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
		if not _should_write(path):
			continue
		var cost := float(row["cost"])
		var node := AugmentNodeScript.new()
		node.id = device[0]
		node.item_id = id
		node.display_name = device[1]
		node.description = device[2]
		node.tier = 3
		# A capstone's effect is its rate, so effect_key is inert here and effect_per_level
		# stays 1.0 — see AugmentNode.automation_rate.
		node.effect_key = &"payout_mult"
		node.effect_per_level = 1.0
		node.max_levels = CAPSTONE_MAX_LEVELS
		node.cost_base = int(round(CAPSTONE_PRICE_FLOOR + cost * CAPSTONE_PRICE_SLOPE))
		node.cost_growth = CAPSTONE_COST_GROWTH
		node.currency = AugmentNodeScript.CURRENCY_HEARTS
		node.is_automation = true
		# round(x * 100) / 100 rather than snappedf: snapping returns the double one ulp
		# above the value, which serialises as 2.8000000000000003 into a file people read.
		var rate := CAPSTONE_BASE_RATE + cost * CAPSTONE_RATE_SLOPE
		node.automation_rate = round(rate * 100.0) / 100.0
		node.requires_mastery = ItemDB.balance.mastery_automation_rank
		# A turret already stands on its own legs, but the mount is what `DeviceLayer`
		# composites the item's sprite onto and every non-friendly, non-cursor item uses the
		# tripod. A turret on a tripod is the most honest picture in the set.
		node.device_mount = &"tripod"
		_save(node, path)

# --- the mortar's branch ---------------------------------------------------

func _seed_shells() -> void:
	var mortar: Dictionary = TURRETS[&"mortar"]
	var cost := int(round(float(mortar["cost"]) * EXCLUSIVE_COST_FRACTION))
	for shell in MORTAR_SHELLS:
		var node := AugmentNodeScript.new()
		node.id = shell[0]
		node.item_id = &"mortar"
		node.display_name = shell[1]
		node.description = shell[2]
		node.tier = 2
		node.effect_key = shell[3]
		node.effect_per_level = shell[4]
		# One level, no growth: this is a choice, not a ladder. `exclusive_group` is scoped
		# by item id in Progression, so &"flavour" is the same group name the bat's three
		# branches use and still a separate pick.
		node.max_levels = 1
		node.cost_base = cost
		node.cost_growth = 1.0
		node.currency = AugmentNodeScript.CURRENCY_BONES
		node.exclusive_group = &"flavour"
		node.requires_mastery = ItemDB.balance.mastery_branch_rank
		_save_if_new(node, "%s/%s.tres" % [AUGMENTS_DIR, String(shell[0])])

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

func _save_if_new(resource: Resource, path: String) -> void:
	if not _should_write(path):
		return
	_save(resource, path)

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m36_turrets: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m36_turrets: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)

## A gun that turns on its mount (D43). If `art/tools/split_turret_barrels.py` has cut this
## turret's sprite in two, the body's Sprite becomes the base and a second Sprite2D, "Barrel",
## is hung at the pivot — the point where the gun sits on the mount, given in the seed table in
## texture pixels from the texture's centre. The barrel's `offset` puts that pixel on the node's
## origin, so rotating the node turns the gun about its mount. `TurretBase` mirrors the offset
## and the position when the sprite flips.
func _split_barrel(root: Node, id: StringName) -> void:
	var base_path := "res://Assets/sprites/items/%s_base.png" % id
	var barrel_path := "res://Assets/sprites/items/%s_barrel.png" % id
	if not ResourceLoader.exists(base_path) or not ResourceLoader.exists(barrel_path):
		return
	var sprite := root.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var pivot: Vector2 = (TURRETS[id]["turret"] as Dictionary).get("barrel_pivot", Vector2.ZERO)
	sprite.texture = ResourceLoader.load(base_path)
	var barrel := Sprite2D.new()
	barrel.name = "Barrel"
	barrel.texture = ResourceLoader.load(barrel_path)
	barrel.scale = sprite.scale
	barrel.position = pivot * sprite.scale
	barrel.offset = -pivot
	root.add_child(barrel)
	root.set(&"barrel", barrel)
