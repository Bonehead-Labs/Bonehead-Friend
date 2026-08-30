extends Node

## Writes M3.5-A's engine: one **levelled** automation capstone per item, and the global
## augment tree.
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
}

## The global tree: nodes that multiply **every** payout in the game, including automation
## income, which per-item payout nodes deliberately do not reach (see docs/economy.md).
##
## This is the cross-run ladder. Without it, a run's total multiplier is bounded by how many
## items are owned, and lifetime earnings grow linearly with time played — which is the
## shape that puts a cube-root prestige threshold out of reach forever. The hook has existed
## since M2 (`Progression.get_modifier` folds `&"global"` into every lookup) and had no
## content in it.
##
## [id, name, description, effect, levels, cost, growth, currency, tier, requires]
const GLOBALS := [
	[&"global_technique", "Technique",
		"You have done this a lot. Everything lands better.",
		1.10, 15, 3000, 1.13, AugmentNodeScript.CURRENCY_BONES, 1, []],
	[&"global_showmanship", "Showmanship",
		"He plays to the crowd. There is no crowd.",
		1.10, 15, 1500, 1.13, AugmentNodeScript.CURRENCY_HEARTS, 1, []],
	[&"global_momentum", "Momentum",
		"Nothing about this is a hobby any more.",
		1.12, 10, 25000, 1.18, AugmentNodeScript.CURRENCY_BONES, 2, [&"global_technique"]],
	[&"global_devotion", "Devotion",
		"He would do this for free. You are paying him in attention.",
		1.12, 10, 12000, 1.18, AugmentNodeScript.CURRENCY_HEARTS, 2, [&"global_showmanship"]],
]

var _written := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(AUGMENTS_DIR)
	_seed_capstones()
	_seed_globals()
	print("seed_m35_engine: %d resources written" % _written)
	get_tree().quit()

func _seed_capstones() -> void:
	for item in ItemDB.all_items():
		if not DEVICES.has(item.id):
			# Loudly, and without writing a nameless device: an item with no capstone is an
			# item that never contributes to idle income, which is invisible in play and
			# obvious in a spreadsheet six weeks later.
			push_error("seed_m35_engine: no automation device authored for '%s'" % item.id)
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
	_save(node, "%s/%s.tres" % [AUGMENTS_DIR, id])

func _seed_globals() -> void:
	for entry in GLOBALS:
		var path: String = "%s/%s.tres" % [AUGMENTS_DIR, entry[0]]
		if ResourceLoader.exists(path):
			continue
		var node := AugmentNodeScript.new()
		node.id = entry[0]
		node.item_id = AugmentNodeScript.GLOBAL
		node.display_name = entry[1]
		node.description = entry[2]
		node.tier = entry[8]
		node.effect_key = &"payout_mult"
		node.effect_per_level = entry[3]
		node.max_levels = entry[4]
		node.cost_base = entry[5]
		node.cost_growth = entry[6]
		node.currency = entry[7]
		var requires: Array[StringName] = []
		requires.assign(entry[9])
		node.requires = requires
		node.sort_order = _written
		_save(node, path)

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m35_engine: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
