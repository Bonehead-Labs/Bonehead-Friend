extends Node

## Writes M3.5-A's engine: one **levelled** automation capstone per item.
##
## It used to own the global tree as well. `tools/seed_m36_globals.gd` took that over when
## the tree went from four nodes to twenty-four, and two tools writing `global_technique`
## would make the shipped numbers a question of which one ran last.
##
##   Godot --headless --path <project> res://tools/seed_m35_engine.tscn
##
## Why this exists as its own tool, and why it *rewrites* rather than skipping:
##
## M3 shipped two capstones, both `max_levels 1`. That makes automation a pair of one-time
## purchases and the game's idle income a flat line forever — and a flat line cannot reach a
## prestige threshold built on a cube root, at any divisor. The genre's answer is linear rate
## against exponential cost (AdVenture Capitalist's business shape), which here is a `.tres`
## edit: `Progression._compute_automation_rate` already pays `automation_rate x level`.
##
## Capstone numbers are therefore **derived from the item's shop price by a rule**, not
## authored one at a time — so a retune is an edit to two constants here rather than to
## twenty-eight resources. That is the whole reason this tool owns the class of node and
## rewrites every capstone on every run. The other seed tools skip what exists, because what
## they write is hand-tuned; nothing here is.
##
## What *is* hand-authored is the fiction: every capstone is a device with a name, because
## "Baseball Bat automation" is a spreadsheet row and "Bat Sentry" is a thing on your desk.

const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")

const AUGMENTS_DIR := "res://Data/Augments"

## Levels, and the cost curve across them. 1.10 is the middle of the band the genre has
## converged on: 30 levels of it is a 17x price rise from first to last, which is steep
## enough that the last level is an event and shallow enough that the first ten are a
## rhythm rather than a wall.
const MAX_LEVELS := 30
const COST_GROWTH := 1.10

## rate per level = BASE_RATE + item cost x RATE_SLOPE, per currency.
##
## Two separate rules because the two currencies are earned at different speeds: Bones
## arrive in the hundreds from a knockout round, Hearts in ones and twos from petting. A
## single rule would either make friendly automation pointless or weapon automation
## dominant. The Bones line reproduces M3's hand-picked Bat Sentry (2.5/s at the mace's
## price point) and the Hearts line reproduces Endless Playlist (0.8/s at 1,200).
const BASE_RATE := {&"bones": 1.0, &"hearts": 0.5}
const RATE_SLOPE := {&"bones": 1.0 / 500.0, &"hearts": 1.0 / 1500.0}

## Every capstone is priced in **Hearts**, whatever it automates. That is D2's spine: you
## cannot stop working for your money without having been kind to him. The slope differs by
## the item's own currency only because a Bones price and a Hearts price are not the same
## kind of number — a 2,500-Bone missile is a smaller ask than a 2,500-Heart anything.
const PRICE_FLOOR := 800.0
const PRICE_SLOPE := {&"bones": 0.4, &"hearts": 0.5}

## The devices. `item id: [augment id, name, description]`.
##
## `bat_sentry` and `boombox_playlist` keep the ids M3 gave them — an augment id is a save
## join key, and renaming one would silently orphan the capstone a player had already
## bought. Everything else is new.
const DEVICES := {
	&"baseball_bat": [&"bat_sentry", "Bat Sentry",
		"A bat on a tripod that swings at him while you work."],
	&"frying_pan": [&"pan_short_order", "Short Order",
		"A pan on a swivel arm, flipping him like a pancake."],
	&"mace": [&"mace_pendulum", "Pendulum",
		"The mace hangs from a gantry and never stops swinging."],
	&"grenade": [&"grenade_hopper", "Pin Hopper",
		"A hopper that pulls pins on a timer. It is not a safe device."],
	&"dynamite": [&"dynamite_fusebox", "Fuse Box",
		"A crate of dynamite wired to a very reliable clock."],
	&"fist": [&"fist_windup", "Wind-Up Fist",
		"A clockwork arm that punches on the hour. And the minute."],
	&"pistol": [&"pistol_turret", "Turret Mount",
		"The pistol on a tripod, taking one careful shot at a time."],
	&"shotgun": [&"shotgun_trap", "Trap Bench",
		"Bench-mounted, and it fires whenever he wanders in front of it."],
	&"missile": [&"missile_fire_control", "Fire Control",
		"A launcher that picks its own targets. There is only the one."],
	&"beach_ball": [&"beach_ball_day", "Beach Day",
		"The ball never quite settles, and he never quite ignores it."],
	&"bowling_ball": [&"bowling_ball_return", "Ball Return",
		"A rail that sends it back down the lane at him. Forever."],
	&"open_hand": [&"hand_petting_machine", "Petting Machine",
		"A mechanical hand on a rail, stroking him while you work."],
	&"sponge": [&"sponge_car_wash", "Car Wash",
		"Rollers, suds, and a skeleton who has stopped resisting."],
	&"baseball": [&"baseball_pitching_machine", "Pitching Machine",
		"It throws, he catches. Neither of them gets tired."],
	&"pizza": [&"pizza_delivery", "Delivery Route",
		"A slice arrives every so often, whether he asked for one or not."],
	&"boombox": [&"boombox_playlist", "Endless Playlist",
		"The boombox keeps itself going, and keeps paying, while the game is closed."],
	# --- M3.5-A's twelve ---
	&"katana": [&"katana_drill", "Iaido Drill",
		"A rack that draws, cuts and sheathes. Over, and over, and over."],
	&"mine": [&"mine_layer", "Minefield",
		"A hopper that lays them faster than he finds them."],
	&"firework": [&"firework_rack", "Display Rack",
		"A rack of rockets on a timer. It is not aimed at anything in particular."],
	&"magnifying_glass": [&"glass_sun_rig", "Sun Rig",
		"A lens on a gantry that follows the sun. And him."],
	&"minigun": [&"minigun_sentry", "Sentry Gun",
		"It has ammunition, a tripod, and no supervision whatsoever."],
	&"gravity_vortex": [&"vortex_singularity", "Singularity",
		"A small, permanent, mostly well-behaved hole in the desk."],
	&"lightning": [&"lightning_storm_cell", "Storm Cell",
		"A weather system that has taken a personal interest in one skeleton."],
	&"chocolate_fountain": [&"fountain_refill", "Refill Line",
		"A pipe from somewhere. Nobody has asked where."],
	&"hot_tub": [&"hot_tub_timer", "Jet Timer",
		"The jets come on by themselves now, whether or not he is in there."],
	&"massage_chair": [&"chair_full_program", "Full Program",
		"Cycle four. Indefinitely."],
	&"trampoline": [&"trampoline_spotter", "Spotter",
		"Catches him and puts him back on. All day."],
	&"desk_fan": [&"fan_oscillator", "Oscillator",
		"The fan sweeps on its own, and something is always going flying."],

	# --- the M3.7 leisure roster ---
	&"beanbag": [&"beanbag_settler", "Settler",
		"An arm that tips him back into it every time he gets up."],
	&"foot_spa": [&"foot_spa_circuit", "Circulator",
		"Keeps the jets running and his feet in them."],
	&"hammock": [&"hammock_rigger", "Rigger",
		"Slings him in and gives it a push whenever the swinging slows."],
	&"paddling_pool": [&"pool_filler", "Filler",
		"Tops it up, warms it, and nudges him back in."],
	&"heated_blanket": [&"blanket_tucker", "Tucker",
		"Tucks him in on a schedule. He has never asked it to stop."],
	&"recliner": [&"recliner_valet", "Valet",
		"Reclines the chair. Then reclines it a bit further."],

	&"cup_of_tea": [&"tea_urn", "Tea Urn",
		"Brews another the moment the last one is gone."],
	&"donut_box": [&"donut_conveyor", "Conveyor",
		"A belt of donuts running past him. It does not run out."],
	&"ice_cream": [&"ice_cream_van", "Van",
		"Parked on the desk with its jingle on a loop."],
	&"noodle_bowl": [&"noodle_kitchen", "Kitchen",
		"A tiny kitchen that makes one dish, extremely well."],
	&"birthday_cake": [&"cake_bakery", "Bakery",
		"Every day is his birthday now. Nobody has told him otherwise."],

	&"houseplant": [&"plant_waterer", "Waterer",
		"Waters it, turns it, and talks to it. The plant is thriving."],
	&"fairy_lights": [&"lights_timer", "Timer",
		"Switches them on at dusk, and dusk is whenever he wants."],
	&"wind_chimes": [&"chime_bellows", "Bellows",
		"A small bellows, because there is no wind indoors."],
	&"lava_lamp": [&"lamp_thermostat", "Thermostat",
		"Holds the wax at the exact temperature of the best blobs."],
	&"record_player": [&"record_changer", "Changer",
		"Drops the next record before the last one has finished."],
	&"fish_tank": [&"tank_feeder", "Feeder",
		"Feeds all four on a timer and reminds him of their names."],

	&"rubber_duck": [&"duck_squeaker", "Squeaker",
		"Squeezes it at a steady rate. He has not tired of it yet."],
	&"jigsaw_puzzle": [&"puzzle_sorter", "Sorter",
		"Sorts the edge pieces. He still insists on doing the sky."],
	&"bubble_machine": [&"bubble_compressor", "Compressor",
		"More bubbles per second than he can possibly chase."],

	# --- the hands-on kind items (assessment-2026-09) ---
	&"feather_duster": [&"duster_valet", "Valet Arm",
		"A duster on a slow arm that gives him a once-over every few minutes."],
	&"soft_brush": [&"brush_groomer", "Groomer",
		"A brush on a cam. It does one long stroke and resets, forever."],
	&"warm_towel": [&"towel_turndown", "Turndown Service",
		"A heated rail that hands him a fresh towel on the hour."],
	&"tennis_ball": [&"tennis_ball_launcher", "Ball Launcher",
		"A hopper that lobs one at him whenever he looks ready to fetch."],
	&"party_popper": [&"popper_cannon", "Confetti Cannon",
		"A rack of poppers on a timer. Every hour is somebody's birthday."],
	&"kite": [&"kite_winch", "Kite Winch",
		"A winch that keeps the kite flying past him on a loop of string."],
}

var _written := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(AUGMENTS_DIR)
	_seed_capstones()
	print("seed_m35_engine: %d resources written" % _written)
	get_tree().quit()

func _seed_capstones() -> void:
	for item in ItemDB.all_items():
		if not DEVICES.has(item.id):
			# Silently, since M3.5-C: the roster outgrew one table and every content tool
			# now writes the capstones for the items it owns, using the same rule. The guard
			# that matters is `loop_check`'s "every item has an automation capstone", which
			# is a claim about the *content* rather than about which file wrote it.
			continue
		var device: Array = DEVICES[item.id]
		_capstone(device[0], item, device[1], device[2])

## One levelled device. Rate and price both come from the item's own price, which is what
## keeps the ladder monotonic: a toy that costs more to buy automates harder and costs more
## to automate, without anyone maintaining a second ordering by hand.
func _capstone(id: StringName, item: ItemData, display_name: String, description: String) -> void:
	var currency := item.currency_id()
	var node := AugmentNodeScript.new()
	node.id = id
	node.item_id = item.id
	node.display_name = display_name
	node.description = description
	node.tier = 3
	# A capstone's effect is its rate, not a multiplier, so effect_key is inert here and
	# effect_per_level stays 1.0 — see AugmentNode.automation_rate.
	node.effect_key = &"payout_mult"
	node.effect_per_level = 1.0
	node.max_levels = MAX_LEVELS
	node.cost_base = int(round(PRICE_FLOOR + float(item.cost) * float(PRICE_SLOPE[currency])))
	node.cost_growth = COST_GROWTH
	node.currency = AugmentNodeScript.CURRENCY_HEARTS
	node.is_automation = true
	# round(x * 100) / 100, not snappedf: snapping 2.8 returns the double one ulp above it,
	# which serialises into the .tres as 2.8000000000000003. These files are read by people.
	var rate := float(BASE_RATE[currency]) + float(item.cost) * float(RATE_SLOPE[currency])
	node.automation_rate = round(rate * 100.0) / 100.0
	node.requires_mastery = ItemDB.balance.mastery_automation_rank
	node.device_mount = _mount_for(item)
	_save(node, "%s/%s.tres" % [AUGMENTS_DIR, id])

## What the device stands on, by what the item is. A weapon or a prop goes on a tripod, a
## kind thing on a pedestal, and a cursor power — which has no world sprite at all — is held
## out by a claw arm.
func _mount_for(item: ItemData) -> StringName:
	if item.is_cursor_power():
		return &"arm"
	if item.category == ItemData.CATEGORY_FRIENDLY:
		return &"pedestal"
	return &"tripod"

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m35_engine: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
