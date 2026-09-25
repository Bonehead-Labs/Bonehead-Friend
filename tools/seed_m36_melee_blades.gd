extends Node

## Writes M3.6's edged half of the melee roster: fifteen weapons with a point or an edge,
## their bodies, their tier-1 trees, their automation capstones and two exclusive branches.
##
##   Godot --headless --path <project> res://tools/seed_m36_melee_blades.tscn [-- --force | --only id,id]
##
## The melee category shipped four items — bat, pan, mace, katana — and the ladder stopped
## at 3,500 Bones while the cursor page ran to 40,000. A player who liked hitting him with
## something they were holding ran out of things to hold first. These continue that ladder
## from 1,200 to 250,000, and the `requires` chain means the shop reveals them one rung at a
## time rather than dropping fifteen unaffordable rows on a player who has just bought a mace.
##
## Same rules as every other seed tool: scenes are packed from script because hand-editing
## `.tscn` is banned (D8), and only files that do not already exist are written.
##
## **The table below is the weapons.** Everything that makes a rapier feel unlike a cleaver
## is in it, and nothing that makes them feel different is recoverable from a sprite (D25).

const WeaponBaseScript := preload("res://Scripts/Bodies/weapon_base.gd")
const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")

const BODIES_DIR := "res://Scenes/Bodies"
const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const ICONS_DIR := "res://Assets/sprites/icons"

## Where this family sits in the Weapon category's ordering. M3's four occupy 0-15; the
## blunt half of M3.6 takes the round multiples of five above that, and the blades take the
## same rungs offset by two — so a blade lands immediately after the blunt weapon it is
## priced beside instead of the two families being listed one after the other. Both ladders
## climb by price, so the offset holds all the way up.
const SORT_BASE := 22
const SORT_STEP := 5

## Tier-1 tree costs, reproduced from `tools/seed_m35_trees.gd` rather than imported,
## because that tool skips items that already have a tier — it cannot write these. The
## numbers are that file's, and a retune there has to be repeated here.
const TREE_COST_FLOOR := 50.0
const TREE_COST_SLOPE := 0.045
const TREE_PAYOUT_FRACTION := 0.78
const TREE_THIRD_FRACTION := 0.61

## Automation, by the rule in `tools/seed_m35_engine.gd`. Only the Bones line appears here:
## every item in this file is a weapon bought with Bones, and carrying a Hearts constant
## nothing reads would be a second copy of a number to drift out of step.
const AUTO_MAX_LEVELS := 30
const AUTO_COST_GROWTH := 1.10
const AUTO_BASE_RATE := 1.0
const AUTO_RATE_SLOPE := 1.0 / 500.0
const AUTO_PRICE_FLOOR := 800.0
const AUTO_PRICE_SLOPE := 0.4

## A tier-2 branch costs about half the weapon again. The bat's three are hand-priced at
## 900 against a free bat, which gives no slope to copy; this is chosen so the choice lands
## a little after the weapon rather than with it.
const EXCLUSIVE_FRACTION := 0.45

## The weapons, in ladder order. Prices continue the melee ladder's 0 / 250 / 900 / 3,500
## at a ratio of about 1.45 — shallower than the catalog's usual tripling because fifteen
## rungs of tripling would end at nine figures, and docs/economy.md's rule is that no
## purchase is more than five minutes of income away at its own tier.
##
## **Physics is authored (D25).** Every entry below is in art pixels, measured from the
## sprite's centre with +Y down, and multiplied by ItemBodyBuilder.ART_SCALE exactly as the
## sprite is. `rot` is degrees, and 45 puts a shape's long axis on the lower-left to
## upper-right diagonal — the katana's convention, and the pose the art brief asks for on
## everything long enough to need one.
##
##   shapes  one entry per part: a capsule down a blade, a small rect on the grip
##   com     centre of mass — where the weight actually is when it swings
##   grip    where the drag joint pins, so it pivots around the hand and not the middle
##   grab    the click target, over the handle
##
## `mass` and `damage_mult` are the other half of the feel. Damage is contact impulse and
## impulse is mass x velocity (D7), so mass is how hard it lands and damage_mult is how much
## of that landing is sharpness. A rapier and a cleaver arrive with similar force and read
## as opposites because the split between the two numbers is opposite.
const BLADES := [
	{
		"id": &"boxcutter",
		"node": "_Boxcutter",
		"label": "Boxcutter",
		"description": "Office issue, resharpened by snapping bits off it. All edge and no weight.",
		"cost": 1200,
		"requires": [&"mace"],
		"mass": 2.5,
		"damage": 2.2,
		# Weight in the plastic body, not the blade — a snap-off knife that led with its
		# point would swing like a dart, and this one is meant to feel like nothing.
		"shapes": [
			{"capsule": Vector2(4, 14), "at": Vector2(5, -5), "rot": 45.0},
			{"rect": Vector2(8, 14), "at": Vector2(-6, 6), "rot": 45.0},
		],
		"com": Vector2(-5, 5),
		"grip": Vector2(-6, 6),
		"grab": {"size": Vector2(18, 18), "at": Vector2(-6, 6)},
		"tree": ["Fresh Segment", "Stationery Budget", "Metal Body"],
		"device": [&"boxcutter_score_line", "Score Line",
			"A rail that draws one perfect line across him, and then another."],
	},
	{
		"id": &"letter_opener",
		"node": "_LetterOpener",
		"label": "Letter Opener",
		"description": "Brass, dull along the edge and unforgivably pointed at the end.",
		"cost": 1800,
		"requires": [&"boxcutter"],
		"mass": 2.8,
		"damage": 2.3,
		# Balanced at the bolster, which is where a desk tool balances: it does not swing,
		# it goes in straight.
		"shapes": [
			{"capsule": Vector2(5, 22), "at": Vector2(6, -6), "rot": 45.0},
			{"rect": Vector2(8, 14), "at": Vector2(-8, 8), "rot": 45.0},
		],
		"com": Vector2(-1, 1),
		"grip": Vector2(-10, 10),
		"grab": {"size": Vector2(18, 18), "at": Vector2(-8, 8)},
		"tree": ["Honed Point", "Return to Sender", "Solid Brass"],
		"device": [&"opener_mail_slot", "Mail Slot",
			"Post arrives. Post is opened. He is standing where the post is."],
	},
	{
		"id": &"shears",
		"node": "_Shears",
		"label": "Tailor's Shears",
		"description": "Two levers and a screw. He is not fabric, and nobody has told them.",
		"cost": 2600,
		"requires": [&"letter_opener"],
		"mass": 3.4,
		"damage": 2.2,
		# The mass sits on the screw, so it tumbles about its middle instead of swinging
		# about a hand. The only weapon in the family with no head and no tail.
		"shapes": [
			{"capsule": Vector2(8, 16), "at": Vector2(0, -8)},
			{"circle": 3.5, "at": Vector2(0, 1)},
			{"rect": Vector2(13, 12), "at": Vector2(0, 10)},
		],
		"com": Vector2(0, 1),
		"grip": Vector2(0, 10),
		"grab": {"size": Vector2(18, 18), "at": Vector2(0, 8)},
		"tree": ["Ground Bevel", "Piecework Rates", "Forged Bows"],
		"device": [&"shears_pattern_cutter", "Pattern Cutter",
			"A table that cuts to a pattern all day. The pattern is him."],
	},
	{
		"id": &"sickle",
		"node": "_Sickle",
		"label": "Sickle",
		"description": "A crescent on a stick. Built for wheat, unfussy about the difference.",
		"cost": 3800,
		"requires": [&"shears"],
		"mass": 4.2,
		"damage": 2.2,
		# The hook puts the weight *off* the handle's line, so it swings wide and catches
		# rather than arriving flat. That offset is the whole character of a sickle.
		"shapes": [
			{"capsule": Vector2(6, 22), "at": Vector2(5, -9), "rot": 75.0},
			{"rect": Vector2(6, 8), "at": Vector2(-2, 2), "rot": 45.0},
			{"rect": Vector2(8, 14), "at": Vector2(-11, 11), "rot": 45.0},
		],
		"com": Vector2(6, -7),
		"grip": Vector2(-14, 14),
		"grab": {"size": Vector2(18, 18), "at": Vector2(-11, 11)},
		"tree": ["Keener Crescent", "Harvest Share", "Forged Hook"],
		"device": [&"sickle_harvester", "Harvester",
			"It works round the desk in slow circles, cutting whatever it finds there."],
	},
	{
		"id": &"katar",
		"node": "_Katar",
		"label": "Katar",
		"description": "A push dagger. You do not swing it at him, you arrive holding it.",
		"cost": 5500,
		"requires": [&"sickle"],
		"mass": 5.0,
		"damage": 2.4,
		# The one weapon here whose centre of mass is at your fist. A katar is punched, not
		# swung, and anything that made it lead with the blade would turn it into a knife.
		"shapes": [
			{"capsule": Vector2(9, 22), "at": Vector2(8, 0), "rot": 90.0},
			{"rect": Vector2(5, 20), "at": Vector2(-11, 0)},
		],
		"com": Vector2(-8, 0),
		"grip": Vector2(-11, 0),
		"grab": {"size": Vector2(18, 18), "at": Vector2(-8, 0)},
		"tree": ["Reinforced Tip", "Duellist's Purse", "Steel Rails"],
		"device": [&"katar_punch_frame", "Punch Frame",
			"A sprung frame that throws one straight jab a second, indefinitely."],
	},
	{
		"id": &"machete",
		"node": "_Machete",
		"label": "Machete",
		"description": "Long, flat and cheerful. Built to clear undergrowth, and since promoted.",
		"cost": 8000,
		"requires": [&"katar"],
		"mass": 6.5,
		"damage": 2.1,
		# Weight forward of the guard but not out at the tip: heavy enough to chop, light
		# enough to bring back for a second swing.
		"shapes": [
			{"capsule": Vector2(10, 36), "at": Vector2(11, -11), "rot": 45.0},
			{"rect": Vector2(9, 16), "at": Vector2(-18, 18), "rot": 45.0},
		],
		"com": Vector2(10, -10),
		"grip": Vector2(-21, 21),
		"grab": {"size": Vector2(18, 20), "at": Vector2(-18, 18)},
		"tree": ["Field Sharpening", "Clearing Contract", "Full Tang"],
		"device": [&"machete_clearing_rig", "Clearing Rig",
			"It sweeps the same arc across the desk all day. Something is always in it."],
	},
	{
		"id": &"rapier",
		"node": "_Rapier",
		"label": "Rapier",
		"description": "All point and no weight. It hurts far more than it moves him.",
		"cost": 11500,
		"requires": [&"machete"],
		"mass": 5.5,
		"damage": 2.8,
		# Balanced *behind* the guard, in the cup and the pommel, so the blade whips: high
		# tip speed on very little mass. A rapier balanced out in the blade is a thin sword.
		"shapes": [
			{"capsule": Vector2(4, 46), "at": Vector2(12, -12), "rot": 45.0},
			{"circle": 6.0, "at": Vector2(-13, 13)},
			{"rect": Vector2(5, 14), "at": Vector2(-22, 22), "rot": 45.0},
		],
		"com": Vector2(-9, 9),
		"grip": Vector2(-23, 23),
		"grab": {"size": Vector2(18, 18), "at": Vector2(-19, 19)},
		"tree": ["Needle Point", "Point of Honour", "Heavier Pommel"],
		"device": [&"rapier_fencing_post", "Fencing Post",
			"A sprung arm that lunges, recovers and lunges again. Its form is excellent."],
	},
	{
		"id": &"cleaver",
		"node": "_Cleaver",
		"label": "Meat Cleaver",
		"description": "A rectangle of steel with one edge. It chops because it is heavy.",
		"cost": 17000,
		"requires": [&"rapier"],
		"mass": 8.5,
		"damage": 2.0,
		# The mace of this family: a slab, all of it out at the far end, no finesse anywhere
		# in it. The blade rect is deeper along the swing than it is wide, which is what
		# makes a cleaver a cleaver rather than a short sword.
		"shapes": [
			{"rect": Vector2(18, 24), "at": Vector2(8, -8), "rot": 45.0},
			{"rect": Vector2(8, 15), "at": Vector2(-14, 14), "rot": 45.0},
		],
		"com": Vector2(9, -9),
		"grip": Vector2(-17, 17),
		"grab": {"size": Vector2(18, 18), "at": Vector2(-14, 14)},
		"tree": ["Ground Edge", "Butcher's Cut", "Thicker Stock"],
		"device": [&"cleaver_block", "Chopping Block",
			"A block, a cleaver and a very regular rhythm."],
	},
	{
		"id": &"fire_axe",
		"node": "_FireAxe",
		"label": "Fire Axe",
		"description": "Break glass in case of skeleton. Everything about it is in the head.",
		"cost": 24000,
		"requires": [&"cleaver"],
		"mass": 10.5,
		"damage": 1.9,
		# The bat's argument with a wedge on the end: all the mass at the top of a long
		# haft, so it arrives head-first whatever you did with the mouse on the way down.
		"shapes": [
			{"rect": Vector2(18, 13), "at": Vector2(0, -18)},
			{"rect": Vector2(6, 34), "at": Vector2(0, 7)},
		],
		"com": Vector2(0, -17),
		"grip": Vector2(0, 20),
		"grab": {"size": Vector2(18, 26), "at": Vector2(0, 14)},
		"tree": ["Ground Bit", "Emergency Callout", "Steel Haft"],
		"device": [&"axe_break_glass", "Break Glass",
			"The case reglazes itself every few seconds, which is more than the axe does."],
	},
	{
		"id": &"energy_sabre",
		"node": "_EnergySabre",
		"label": "Energy Sabre",
		"description": "A hilt and a rumour. Nothing to weigh, and it goes through him anyway.",
		"cost": 35000,
		"requires": [&"fire_axe"],
		"mass": 9.0,
		"damage": 3.0,
		# The only weapon that balances behind the hand and still out-reaches everything
		# around it: the blade has no mass, so all nine kilos are the power cell in the grip.
		# Sharpness at the roster's ceiling is what it is bought for, not impact.
		"shapes": [
			{"capsule": Vector2(6, 46), "at": Vector2(13, -13), "rot": 45.0},
			{"rect": Vector2(8, 20), "at": Vector2(-21, 21), "rot": 45.0},
		],
		"com": Vector2(-19, 19),
		"grip": Vector2(-22, 22),
		"grab": {"size": Vector2(18, 20), "at": Vector2(-20, 20)},
		"tree": ["Tighter Focus", "Novelty Premium", "Denser Emitter"],
		"device": [&"sabre_kata_rig", "Kata Rig",
			"The hilt runs its forms by itself. He is standing in one of them."],
	},
	{
		"id": &"war_pick",
		"node": "_WarPick",
		"label": "War Pick",
		"description": "A hammer that grew a beak. Everything it has, on one small spot.",
		"cost": 50000,
		"requires": [&"energy_sabre"],
		"mass": 12.0,
		"damage": 2.4,
		# Mass behind a single point, and slightly off the haft's line so it rolls into the
		# blow. It does not sweep; it lands.
		"shapes": [
			{"capsule": Vector2(6, 20), "at": Vector2(8, -14), "rot": 60.0},
			{"rect": Vector2(9, 9), "at": Vector2(-5, -16)},
			{"rect": Vector2(6, 30), "at": Vector2(0, 6)},
		],
		"com": Vector2(2, -14),
		"grip": Vector2(0, 17),
		"grab": {"size": Vector2(18, 24), "at": Vector2(0, 12)},
		"tree": ["Hardened Beak", "Armourer's Fee", "Lead Poll"],
		"device": [&"pick_pit_head", "Pit Head",
			"A winch that lifts the beak and lets go of it, on a schedule."],
	},
	{
		"id": &"scythe",
		"node": "_Scythe",
		"label": "Scythe",
		"description": "The traditional one. He has met it before and will not discuss it.",
		"cost": 72000,
		"requires": [&"war_pick"],
		"mass": 14.0,
		"damage": 2.2,
		# The blade is at right angles to the snath and a long way off its line, so the
		# centre of mass is nowhere near the handle. It will not swing straight — it
		# corkscrews, and it is the only weapon in the family that does.
		"shapes": [
			{"capsule": Vector2(7, 60), "at": Vector2(0, 6)},
			{"rect": Vector2(6, 9), "at": Vector2(-3, -28)},
			{"capsule": Vector2(6, 34), "at": Vector2(-16, -26), "rot": 100.0},
		],
		"com": Vector2(-12, -20),
		"grip": Vector2(0, 24),
		"grab": {"size": Vector2(18, 30), "at": Vector2(0, 22)},
		"tree": ["Peened Edge", "Reaper's Due", "Iron Snath"],
		"device": [&"scythe_reaping", "The Reaping",
			"It works its way across the desk in long, even strokes."],
	},
	{
		"id": &"halberd",
		"node": "_Halberd",
		"label": "Halberd",
		"description": "An axe, a hook and a spike on a very long stick. Any of them will do.",
		"cost": 105000,
		"requires": [&"scythe"],
		"mass": 16.0,
		"damage": 2.1,
		# A head on the end of the longest lever in the game: slow to bring round and very
		# hard to stop once it is coming. The three head pieces are separate because a
		# halberd that hits with one box hits the same however it is turned.
		"shapes": [
			{"capsule": Vector2(5, 16), "at": Vector2(0, -30)},
			{"rect": Vector2(17, 14), "at": Vector2(-9, -24)},
			{"rect": Vector2(9, 6), "at": Vector2(8, -23)},
			{"capsule": Vector2(6, 56), "at": Vector2(0, 10)},
		],
		"com": Vector2(-3, -24),
		"grip": Vector2(0, 26),
		"grab": {"size": Vector2(18, 30), "at": Vector2(0, 24)},
		"tree": ["Ground Bill", "Guard Duty", "Iron-Shod Shaft"],
		"device": [&"halberd_guard_post", "Guard Post",
			"It stands there for hours. Occasionally it does its job."],
	},
	{
		"id": &"greatsword",
		"node": "_Greatsword",
		"label": "Greatsword",
		"description": "Two hands and a long lever. Stopping it is harder than starting it.",
		"cost": 155000,
		"requires": [&"halberd"],
		"mass": 20.0,
		"damage": 2.2,
		# Balanced a third of the way up the blade: far enough out to carry through him,
		# far enough in that a player can still turn it. Out at the tip it is a wrecking
		# ball and at the hand it is a stick, and neither of those is a greatsword.
		"shapes": [
			{"capsule": Vector2(11, 46), "at": Vector2(0, -12)},
			{"rect": Vector2(28, 5), "at": Vector2(0, 14)},
			{"rect": Vector2(7, 16), "at": Vector2(0, 24)},
			{"circle": 4.5, "at": Vector2(0, 34)},
		],
		"com": Vector2(0, -8),
		"grip": Vector2(0, 24),
		"grab": {"size": Vector2(20, 26), "at": Vector2(0, 22)},
		"tree": ["Sharpened Ricasso", "Champion's Purse", "Steel Pommel"],
		"device": [&"greatsword_gantry", "Gantry Swing",
			"A gantry lifts it, aims it, and lets go. Then it does that again."],
	},
	{
		"id": &"chainsaw",
		"node": "_Chainsaw",
		"label": "Chainsaw",
		"description": "Two-stroke, badly maintained, and audible from the far side of the desk.",
		"cost": 250000,
		"requires": [&"greatsword"],
		"mass": 17.0,
		"damage": 2.9,
		# Backwards from every other blade here: the engine is the mass and it sits at your
		# hands, so the bar is nearly weightless and the thing bucks instead of swinging.
		# That is what a chainsaw does, and it is why it must not have a forward centre of
		# mass however much the silhouette suggests one.
		"shapes": [
			{"capsule": Vector2(8, 34), "at": Vector2(16, -16), "rot": 45.0},
			{"rect": Vector2(18, 18), "at": Vector2(-8, 8), "rot": 45.0},
			{"rect": Vector2(5, 14), "at": Vector2(-22, 22), "rot": 45.0},
		],
		"com": Vector2(-8, 8),
		"grip": Vector2(-11, 11),
		"grab": {"size": Vector2(22, 22), "at": Vector2(-10, 10)},
		"tree": ["Fresh Chain", "Timber Rights", "Bigger Engine"],
		"device": [&"chainsaw_mill", "Sawmill",
			"A bench, a feed rail, and a bar that is never switched off."],
	},
]

## Tier-2 branches, for the two weapons with a genuine three-way identity. Everywhere else
## a branch would be three names for the same swing, which is content that costs a player a
## decision and gives nothing back.
##
## `[id, name, description, effect_key, effect_per_level]`. Only the three keys WeaponBase
## actually reads appear here — damage, payout and mass. A node whose effect_key nothing
## reads is a placebo, and two of those have already shipped.
const EXCLUSIVES := {
	&"greatsword": [
		[&"greatsword_executioner", "Executioner",
			"One enormous swing, and no interest whatsoever in a second.",
			&"damage_mult", 1.8],
		[&"greatsword_heirloom", "Heirloom",
			"Somebody's family owned this. Somebody's family is being compensated.",
			&"payout_mult", 2.0],
		[&"greatsword_anvil", "Anvil-Forged",
			"Twice the steel in it. It moves like weather.",
			&"mass_mult", 1.6],
	],
	&"chainsaw": [
		[&"chainsaw_ripping", "Ripping Chain",
			"A chain filed for tearing along the grain. He has no grain.",
			&"damage_mult", 1.7],
		[&"chainsaw_scrap", "Scrap Merchant",
			"Every tooth is now billed separately.",
			&"payout_mult", 1.9],
		# The Pillow Bat's argument at the top of the ladder: a kind player who has bought
		# everything should still have something to hold that does not wreck his mood.
		[&"chainsaw_prop", "Prop Chain",
			"Rubber teeth and a lot of noise. It terrifies him and cannot cut butter.",
			&"damage_mult", 0.3],
	],
}

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

	for index in BLADES.size():
		_blade(BLADES[index], index)

	print("seed_m36_melee_blades: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

## Scene first, because the ItemData has to load it. An item whose scene could not be built
## is skipped whole — a `.tres` with a null scene fails ItemData.validation_error() at boot
## and takes the catalog down, and its tree and capstone would be orphans pointing at an id
## nothing owns.
func _blade(spec: Dictionary, index: int) -> void:
	var scene_path := "%s/%s.tscn" % [BODIES_DIR, spec["id"]]
	if not _ensure_scene(spec, scene_path):
		return
	_item(spec, index, scene_path)
	_tree(spec)
	_capstone(spec)
	_exclusives(spec)

# --- scenes ----------------------------------------------------------------

func _ensure_scene(spec: Dictionary, path: String) -> bool:
	if not _should_write(path):
		return true
	var root := ItemBodyBuilder.build({
		"name": spec["node"],
		"id": spec["id"],
		"script": WeaponBaseScript,
		"mass": spec["mass"],
		"properties": {"damage_mult": spec["damage"]},
		"shapes": spec["shapes"],
		"com": spec["com"],
		"grip": spec["grip"],
		"grab": spec["grab"],
	})
	if root == null:
		push_error("seed_m36_melee_blades: no body for '%s' — generate its sprite first"
			% spec["id"])
		return false
	if not ItemBodyBuilder.save_scene(root, path):
		return false
	_written += 1
	print("  wrote %s" % path)
	return true

# --- items -----------------------------------------------------------------

func _item(spec: Dictionary, index: int, scene_path: String) -> void:
	var path := "%s/%s.tres" % [ITEMS_DIR, spec["id"]]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = spec["id"]
	item.display_name = spec["label"]
	item.description = spec["description"]
	item.category = ItemDataScript.CATEGORY_WEAPON
	item.cost = spec["cost"]
	item.currency = ItemDataScript.CURRENCY_BONES
	item.scene = _require(scene_path)
	item.sort_order = SORT_BASE + index * SORT_STEP
	var gate: Array[StringName] = []
	gate.assign(spec["requires"])
	item.requires = gate
	var icon := "%s/%s.png" % [ICONS_DIR, spec["id"]]
	if ResourceLoader.exists(icon):
		item.icon = ResourceLoader.load(icon)
	_save(item, path)

# --- augments --------------------------------------------------------------

## The three tier-1 nodes, at `seed_m35_trees.gd`'s shape and costs. The third lever is
## weight, because every item in this file is a physical body and mass is the one upgrade
## a player can feel in the swing rather than only read in the payout.
func _tree(spec: Dictionary) -> void:
	var names: Array = spec["tree"]
	var base := TREE_COST_FLOOR + float(spec["cost"]) * TREE_COST_SLOPE
	_tier_one("%s_damage" % spec["id"], spec, names[0], &"damage_mult", 1.15,
		int(round(base)), 1.12, 0)
	_tier_one("%s_payout" % spec["id"], spec, names[1], &"payout_mult", 1.12,
		int(round(base * TREE_PAYOUT_FRACTION)), 1.10, 1)
	_tier_one("%s_third" % spec["id"], spec, names[2], &"mass_mult", 1.08,
		int(round(base * TREE_THIRD_FRACTION)), 1.09, 2)

func _tier_one(id: String, spec: Dictionary, display_name: String, effect_key: StringName,
		effect_per_level: float, cost_base: int, cost_growth: float, sort_order: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = StringName(id)
	node.item_id = spec["id"]
	node.display_name = display_name
	node.effect_key = effect_key
	node.effect_per_level = effect_per_level
	node.max_levels = 10
	node.cost_base = cost_base
	node.cost_growth = cost_growth
	node.currency = AugmentNodeScript.CURRENCY_BONES
	node.sort_order = sort_order
	_save(node, path)

## One levelled device per weapon, by `seed_m35_engine.gd`'s rule: rate and price both come
## from the item's own price, so the ladder stays monotonic without anyone maintaining a
## second ordering by hand. Priced in Hearts whatever it automates — D2's spine.
func _capstone(spec: Dictionary) -> void:
	var device: Array = spec["device"]
	var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = device[0]
	node.item_id = spec["id"]
	node.display_name = device[1]
	node.description = device[2]
	node.tier = 3
	# A capstone's effect is its rate, not a multiplier, so effect_key is inert here and
	# effect_per_level stays 1.0 — see AugmentNode.automation_rate.
	node.effect_key = &"payout_mult"
	node.effect_per_level = 1.0
	node.max_levels = AUTO_MAX_LEVELS
	node.cost_base = int(round(AUTO_PRICE_FLOOR + float(spec["cost"]) * AUTO_PRICE_SLOPE))
	node.cost_growth = AUTO_COST_GROWTH
	node.currency = AugmentNodeScript.CURRENCY_HEARTS
	node.is_automation = true
	# round(x * 100) / 100, not snappedf: snapping 2.8 returns the double one ulp above it,
	# which serialises into the .tres as 2.8000000000000003. These files are read by people.
	var rate := AUTO_BASE_RATE + float(spec["cost"]) * AUTO_RATE_SLOPE
	node.automation_rate = round(rate * 100.0) / 100.0
	node.requires_mastery = ItemDB.balance.mastery_automation_rank
	node.device_mount = &"tripod"
	_save(node, path)

func _exclusives(spec: Dictionary) -> void:
	if not EXCLUSIVES.has(spec["id"]):
		return
	var cost := int(round(float(spec["cost"]) * EXCLUSIVE_FRACTION))
	var branch: Array = EXCLUSIVES[spec["id"]]
	for index in branch.size():
		var entry: Array = branch[index]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, entry[0]]
		if not _should_write(path):
			continue
		var node := AugmentNodeScript.new()
		node.id = entry[0]
		node.item_id = spec["id"]
		node.display_name = entry[1]
		node.description = entry[2]
		node.tier = 2
		node.effect_key = entry[3]
		node.effect_per_level = entry[4]
		node.max_levels = 1
		node.cost_base = cost
		# Flat, because there is only ever one level to buy: a growth on a single level is
		# a number that never applies and reads as though it might.
		node.cost_growth = 1.0
		node.currency = AugmentNodeScript.CURRENCY_BONES
		node.exclusive_group = &"flavour"
		node.requires_mastery = ItemDB.balance.mastery_branch_rank
		node.sort_order = index
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
		push_error("seed_m36_melee_blades: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m36_melee_blades: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
