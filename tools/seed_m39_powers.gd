extends Node

## Writes the seven supernatural cursor powers (docs/decisions.md D72): their scenes, their
## ItemData, their augment trees and their automation capstones.
##
##   Godot --headless --path <project> res://tools/seed_m39_powers.tscn [-- --force] [-- --only=smite,rainbow]
##
## Same rules as every seed tool, and the table follows `seed_m39_toys2.gd`'s: scenes are packed
## from script because hand-editing a `.tscn` is banned, only files that do not already exist are
## written (`--force` rewrites; `--only` limits it to some ids), and every number that can be
## derived is derived — tree prices from `seed_m35_trees.gd`'s rule, capstones from
## `seed_m35_engine.gd`'s, with the claw arm every cursor power's device stands on.
##
## Four are on the harm side, filed in the Cursor drawer and bought with Bones; three are on the
## kind side, filed with the hand and the brush in Care, bought with Hearts and equipped as a
## power (`equips_as_cursor_power`). `side` decides the currency, the tree's currency and the
## capstone's rate rule.
##
## A power has no body, so its scene is a bare `Node2D`: the script, its numbers, the cursor
## (`Assets/sprites/cursors/<id>.png`, drawn by `art/tools/pixel_cursor.py` from
## `art/pixel/cursors/`) with its hotspot at the canvas middle, and any picture it puts in the
## world (`Assets/sprites/items/<id>_<part>.png`, drawn by `pixel_sprite.py`). Everything else a
## spell shows it builds on first use.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const TelekinesisScript := preload("res://Scripts/Bodies/Powers/telekinesis_power.gd")
const TimeStopScript := preload("res://Scripts/Bodies/Powers/time_stop_power.gd")
const MeteorShowerScript := preload("res://Scripts/Bodies/Powers/meteor_shower_power.gd")
const SmiteScript := preload("res://Scripts/Bodies/Powers/smite_power.gd")
const BlessingScript := preload("res://Scripts/Bodies/Powers/blessing_power.gd")
const LevitationScript := preload("res://Scripts/Bodies/Powers/levitation_power.gd")
const RainbowScript := preload("res://Scripts/Bodies/Powers/rainbow_power.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const POWERS_DIR := "res://Scenes/Powers"
const SPRITES_DIR := "res://Assets/sprites/items"
const ICONS_DIR := "res://Assets/sprites/icons"
const CURSORS_DIR := "res://Assets/sprites/cursors"
## `pixel_cursor.py` puts the middle of every drawing here.
const HOTSPOT := Vector2(32, 32)

## Tier-1 tree pricing, identical to `tools/seed_m35_trees.gd`.
const TREE_FLOOR := 50.0
const TREE_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## Capstones by `tools/seed_m35_engine.gd`'s two rules, charged in Hearts whatever they make.
const CAPSTONE_RATE := {&"harm": [1.0, 1.0 / 500.0], &"kind": [0.5, 1.0 / 1500.0]}
const CAPSTONE_PRICE := {&"harm": 0.4, &"kind": 0.5}
const CAPSTONE_FLOOR := 800.0
const CAPSTONE_LEVELS := 30
const CAPSTONE_GROWTH := 1.10

## One row per power.
##
##   properties   the script's exports, as authored
##   textures     export -> a picture under `Assets/sprites/`, `items/` unless it says `cursors/`
##   tree         [damage, payout, third]; an empty third means no honest third lever (the
##                sponge's rule, `seed_m35_trees.gd`). The third is always `cooldown_mult`, read
##                by each power as the gap it means: a squeeze, a recharge, the next meteor, the
##                next blessing, the next rainbow
##
## The harm four sit on the Cursor ladder between the powers already there: missile 2,500 ·
## glass 4,000 · **telekinesis 6,000** · **time stop 12,000** · vortex 15,000 · **meteor shower
## 25,000** · lightning 40,000 · **smite 60,000**.
##
## **The kind three cost in Hearts what their harm-side twins cost in Bones** — blessing 6,000
## (telekinesis), levitation 12,000 (time stop), rainbow 25,000 (meteor shower) — the top of the
## Care drawer above the bubble blaster's 2,400 (D76, amended). D72 had to put them at 500,000 to
## 1,000,000: run one's Hearts side turned on the massage chair reaching rank 25 inside the
## hour-nine play window, and any Hearts item bought before it cost the run an hour. With the
## first Reincarnation at eight hours (`marrow_divisor` 5e6) the chair no longer decides run one,
## and every ladder from 900 to 400,000 lands it between 8:00:08 and 8:01:28.
const POWERS := {
	&"telekinesis": {
		"node": "TelekinesisPower", "script": TelekinesisScript, "side": &"harm",
		"name": "Telekinesis",
		"description": "Pick him up with your mind. Put him down with some force.",
		"controls": "Click anywhere to seize him · Move to carry him, let go to fling · Right-click while holding to crush",
		"cost": 6000, "sort": 27, "requires": [&"magnifying_glass"],
		"properties": {"spring": 7.0, "max_speed": 1500.0, "accel": 4800.0,
			"crush_impulse": 3200.0, "crush_seconds": 0.6, "claim_seconds": 2.0},
		"textures": {"grip_cursor_texture": "cursors/telekinesis_grip"},
		"tree": ["Iron Grip", "Poltergeist Fees", "Quicker Squeeze"],
		"device": [&"telekinesis_poltergeist", "Poltergeist",
			"Something unseen picks him up, shakes him about and puts him back. Mostly back."],
	},
	&"time_stop": {
		"node": "TimeStopPower", "script": TimeStopScript, "side": &"harm",
		"name": "Time Stop",
		"description": "Stop him mid-air, hit him ten times, and let time catch up all at once.",
		"controls": "Click him to stop time · Click him again to bank blows · Click away, or wait, and they all land at once",
		"cost": 12000, "sort": 32, "requires": [&"telekinesis"],
		"properties": {"stop_seconds": 4.0, "blow_impulse": 2600.0, "max_blows": 10,
			"blow_gap": 0.12, "shove_per_blow": 380.0, "max_shove": 3000.0,
			"recharge_seconds": 3.0, "bubble_radius": 78.0},
		"textures": {},
		"tree": ["Stored Momentum", "Borrowed Time", "Faster Rewind"],
		"device": [&"time_stop_clock", "Stopped Clock",
			"A clock that stops him twice a day, and a good deal more often than that."],
	},
	&"meteor_shower": {
		"node": "MeteorShowerPower", "script": MeteorShowerScript, "side": &"harm",
		"name": "Meteor Shower",
		"description": "Hold the button and the sky falls on the cursor. The sky is mostly rock.",
		"controls": "Hold the button and meteors rain down where you point",
		"cost": 25000, "sort": 38, "requires": [&"gravity_vortex"],
		"properties": {"interval": 0.25, "blast_radius": 70.0, "blast_force": 2400.0, "shove_share": 0.4,
			"spread": 46.0, "fall_speed": 1500.0, "slant": 0.35, "pool_size": 8},
		"textures": {"meteor_texture": "meteor_shower_rock"},
		"tree": ["Bigger Rocks", "Impact Fees", "Denser Shower"],
		"device": [&"meteor_shower_orbit", "Low Orbit",
			"A small rock in a low orbit around the desk. It comes down now and then."],
	},
	&"smite": {
		"node": "SmitePower", "script": SmiteScript, "side": &"harm",
		"name": "Smite",
		"description": "A pillar of holy light, straight down, on everything standing in its column.",
		"controls": "Click anywhere: light gathers, then a pillar comes down that whole column",
		"cost": 60000, "sort": 45, "requires": [&"lightning"],
		"properties": {"charge_seconds": 0.6, "column_width": 72.0, "smite_impulse": 11000.0,
			"slam_speed": 800.0, "quake_radius": 260.0, "quake_speed": 420.0,
			"recharge_seconds": 2.6},
		"textures": {},
		"tree": ["Righteous Fury", "Tithes", "Swifter Judgement"],
		"device": [&"smite_deity", "Personal Deity",
			"Something upstairs has taken a professional interest in him."],
	},
	&"blessing": {
		"node": "BlessingPower", "script": BlessingScript, "side": &"kind",
		"name": "Blessing",
		"description": "A halo that rains hearts on him. He has never felt so forgiven.",
		"controls": "Click him to crown him with a halo · It rains hearts on him while it lasts",
		"cost": 6000, "sort": 60, "requires": [&"soft_brush"],
		"properties": {"bless_value": 12.0, "halo_seconds": 8.0, "halo_rate": 2.0,
			"flush_seconds": 0.5, "recast_seconds": 2.5},
		"textures": {"halo_texture": "blessing_halo"},
		"tree": ["Brighter Halo", "Offerings", "Quicker Grace"],
		"device": [&"blessing_saint", "Patron Saint",
			"Someone is watching over him. They leave a heart now and then."],
	},
	&"levitation": {
		"node": "LevitationPower", "script": LevitationScript, "side": &"kind",
		"name": "Levitation",
		"description": "He floats up, gets comfortable, and falls asleep on nothing at all.",
		"controls": "Hold the button on him and he floats up and dozes off · Let go and he drifts down",
		"cost": 12000, "sort": 65, "requires": [&"blessing"],
		"properties": {"lift_value": 4.0, "float_rate": 3.0, "flush_seconds": 0.5,
			"lift_height": 130.0, "rise_speed": 120.0, "sink_speed": 120.0},
		"textures": {"z_texture": "levitation_z"},
		"tree": ["Softer Air", "Cloud Rates", ""],
		"device": [&"levitation_cloud", "Cloud Nine",
			"A cloud that follows him about and lets him nap on it."],
	},
	&"rainbow": {
		"node": "RainbowPower", "script": RainbowScript, "side": &"kind",
		"name": "Rainbow",
		"description": "Draw him a rainbow and he slides down it. Every single time.",
		"controls": "Press on him, drag to where he should land and let go · He slides down the rainbow",
		"cost": 25000, "sort": 70, "requires": [&"levitation"],
		"properties": {"ride_value": 14.0, "min_span": 90.0, "max_span": 900.0,
			"ride_speed": 520.0, "recast_seconds": 1.5},
		"textures": {},
		"tree": ["Brighter Colours", "Pot of Gold", "Quicker Arcs"],
		"device": [&"rainbow_machine", "Rainbow Machine",
			"It makes rainbows and he slides down them. Nobody has asked how it works."],
	},
}

var _force := false
var _only: PackedStringArray = []
var _written := 0
var _skipped := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_force = args.has("--force")
	for arg in args:
		if String(arg).begins_with("--only="):
			_only = String(arg).trim_prefix("--only=").split(",", false)
	for dir in [ITEMS_DIR, AUGMENTS_DIR, POWERS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)
	_seed_scenes()
	_seed_items()
	_seed_trees()
	_seed_capstones()
	print("seed_m39_powers: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _ids() -> Array:
	var out: Array = []
	for id in POWERS:
		if _only.is_empty() or _only.has(String(id)):
			out.append(id)
	return out

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	for id in _ids():
		var path := "%s/%s_power.tscn" % [POWERS_DIR, id]
		if not _should_write(path):
			continue
		var row: Dictionary = POWERS[id]
		var root := Node2D.new()
		root.name = row["node"]
		root.set_script(row["script"])
		root.set(&"item_id", id)
		var properties: Dictionary = row["properties"]
		for key in properties:
			root.set(StringName(key), properties[key])
		# Every cursor power has to change what the player sees (loop_check asserts it).
		root.set(&"cursor_texture", _require("%s/%s.png" % [CURSORS_DIR, id]))
		root.set(&"cursor_hotspot", HOTSPOT)
		var textures: Dictionary = row["textures"]
		for key in textures:
			var name := String(textures[key])
			var file := "res://Assets/sprites/%s.png" % name if name.begins_with("cursors/") \
				else "%s/%s.png" % [SPRITES_DIR, name]
			root.set(StringName(key), _require(file))
		var packed := PackedScene.new()
		if packed.pack(root) != OK:
			push_error("seed_m39_powers: failed to pack %s" % path)
			root.free()
			continue
		_save(packed, path)
		root.free()

# --- items -----------------------------------------------------------------

func _seed_items() -> void:
	for id in _ids():
		var row: Dictionary = POWERS[id]
		var path := "%s/%s.tres" % [ITEMS_DIR, id]
		if not _should_write(path):
			continue
		var kind: bool = row["side"] == &"kind"
		var item := ItemDataScript.new()
		item.id = id
		item.display_name = row["name"]
		item.description = row["description"]
		item.controls = row["controls"]
		# The kind three are filed where a player looking for kindness looks, and equip as a
		# power all the same — the open hand's arrangement (`equips_as_cursor_power`).
		item.category = ItemDataScript.CATEGORY_FRIENDLY if kind else ItemDataScript.CATEGORY_CURSOR_POWER
		item.equips_as_cursor_power = kind
		item.cost = row["cost"]
		item.currency = ItemDataScript.CURRENCY_HEARTS if kind else ItemDataScript.CURRENCY_BONES
		item.scene = _require("%s/%s_power.tscn" % [POWERS_DIR, id])
		item.sort_order = row["sort"]
		var gate: Array[StringName] = []
		gate.assign(row["requires"])
		item.requires = gate
		var icon := "%s/%s.png" % [ICONS_DIR, id]
		if ResourceLoader.exists(icon):
			item.icon = ResourceLoader.load(icon)
		else:
			push_error("seed_m39_powers: no icon at %s — run pixel_icon.py and the editor pass" % icon)
		_save(item, path)

# --- trees -----------------------------------------------------------------

## Tier-1 nodes, every one read by the power's own script — a node whose effect_key nothing reads
## is a placebo, and `item_check` fails one by name:
##
##   damage_mult    the harm four's impulse through `effective_damage_mult` (and so their claimed
##                  impacts); the kind three's kindness value, act and trickle alike
##   payout_mult    what is earned, applied by Economy to every source
##   cooldown_mult  the gap each one means — telekinesis's squeeze, time stop's recharge, the
##                  gap between meteors, smite's recharge, the next blessing, the next rainbow
func _seed_trees() -> void:
	for id in _ids():
		var row: Dictionary = POWERS[id]
		var names: Array = row["tree"]
		var kind: bool = row["side"] == &"kind"
		var currency := AugmentNodeScript.CURRENCY_HEARTS if kind else AugmentNodeScript.CURRENCY_BONES
		var base := TREE_FLOOR + float(row["cost"]) * TREE_SLOPE
		_tier_one("%s_damage" % id, id, names[0], &"damage_mult", 1.15, base, 1.12, 0, currency)
		_tier_one("%s_payout" % id, id, names[1], &"payout_mult", 1.12,
			base * PAYOUT_FRACTION, 1.10, 1, currency)
		if String(names[2]) != "":
			_tier_one("%s_pace" % id, id, names[2], &"cooldown_mult", 0.94,
				base * THIRD_FRACTION, 1.09, 2, currency)

func _tier_one(node_id: String, item_id: StringName, display_name: String,
		effect_key: StringName, effect_per_level: float, cost_base: float,
		cost_growth: float, sort_order: int, currency: int) -> void:
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
	node.cost_base = int(round(cost_base))
	node.cost_growth = cost_growth
	node.currency = currency
	node.sort_order = sort_order
	_save(node, path)

# --- capstones -------------------------------------------------------------

## One levelled device per power, by the engine's rule for its side, priced in Hearts, held out
## on the claw arm — `seed_m35_engine._mount_for` gives every cursor power the arm, because a
## power has no world sprite to stand on a tripod.
func _seed_capstones() -> void:
	for id in _ids():
		var row: Dictionary = POWERS[id]
		var device: Array = row["device"]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
		if not _should_write(path):
			continue
		var side: StringName = row["side"]
		var cost := float(row["cost"])
		var rate_rule: Array = CAPSTONE_RATE[side]
		var node := AugmentNodeScript.new()
		node.id = device[0]
		node.item_id = id
		node.display_name = device[1]
		node.description = device[2]
		node.tier = 3
		node.effect_key = &"payout_mult"
		node.effect_per_level = 1.0
		node.max_levels = CAPSTONE_LEVELS
		node.cost_base = int(round(CAPSTONE_FLOOR + cost * float(CAPSTONE_PRICE[side])))
		node.cost_growth = CAPSTONE_GROWTH
		node.currency = AugmentNodeScript.CURRENCY_HEARTS
		node.is_automation = true
		var rate := float(rate_rule[0]) + cost * float(rate_rule[1])
		node.automation_rate = round(rate * 100.0) / 100.0
		node.requires_mastery = ItemDB.balance.mastery_automation_rank
		node.device_mount = &"arm"
		_save(node, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m39_powers: cannot load %s — check the exact on-disk case, and that the editor has imported it" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m39_powers: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
