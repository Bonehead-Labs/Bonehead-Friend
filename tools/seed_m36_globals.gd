extends Node

## Writes the whole global tree — the "Everything" page — as twenty-four nodes.
##
##   Godot --headless --path <project> res://tools/seed_m36_globals.tscn
##
## **This supersedes the `GLOBALS` table in `tools/seed_m35_engine.gd`**, which wrote the
## first four of these ids. That block has to go: two tools writing the same four `.tres`
## files makes the shipped numbers a question of which one ran last.
##
## The four ids it wrote — `global_technique`, `global_showmanship`, `global_momentum`,
## `global_devotion` — are kept exactly as they are spelled. An augment id is a save join
## key, and a player mid-run has levels banked against those four strings.
##
## Like every other seed tool here, this one **rewrites** rather than skipping. The table
## below is the authority on the whole tree, and a tree half-written by an older version of
## itself is the failure this is meant to prevent.
##
##
## ## Why twenty-four small nodes and not four large ones
##
## The four that existed were 1.06 and 1.08 over ten levels apiece. Their first draft was
## 1.10 and 1.12 over ten to fifteen, which reads modest and is not: every global node
## multiplies *every* payout in the game, so the four together came to **x169** and
## `pacing_sim` bought the entire 28-item catalog out in sixty-six minutes. The lesson is
## not "fewer nodes", it is **smaller ones** — a page of choices is worth having, and each
## individual choice has to be nearly invisible on its own.
##
## Targets, and the arithmetic that hits them. A node's contribution is
## `effect_per_level ^ max_levels`; a `cooldown_mult` node's is the reciprocal of that,
## because 0.98 per level for ten levels is 22% *more* acts per second. An exclusive row
## contributes one node, not three.
##
## | Row | Shape | Per node | Row |
## |---|---|---|---|
## | 1 basics | 3 x 1.02^10 | 1.2190 | **1.8114** |
## | 2 habits | 2 x 1.02^10, 1 x (1/0.98^10) | 1.2190 / 1.2239 | **1.8186** |
## | 3 stance | pick one of three | ~1.10 | **1.1000** |
## | 4 standing | 3 x 1.025^10 | 1.2801 | **2.0976** |
## | 5 vocation | pick one of three | ~1.08 | **1.0800** |
## | 6 first life | 3 x 1.03^6 | 1.1941 | **1.7024** |
## | 7 second life | 3 x 1.03^6 | 1.1941 | **1.7024** |
## | 8 third life | 2 x 1.03^6, 1 x (1/0.97^6) | 1.1941 / 1.2005 | **1.7117** |
##
## Which multiply out to:
##
##   first run, no Reincarnation (rows 1-5)   1.8114 x 1.8186 x 1.10 x 2.0976 x 1.08 = **x8.2**
##   after one  (+ row 6)                     x8.2  x 1.7024                        = x14.0
##   after two  (+ row 7)                     x14.0 x 1.7024                        = x23.8
##   the whole tree (+ row 8)                 x23.8 x 1.7117                        = **x40.7**
##
## x8 on a first run and x40 across the cross-run ladder — against the x3.2 / x15 the four
## nodes gave, and nowhere near the x169 that broke the pacing simulator. Each Reincarnation
## opens exactly one more row of three worth about x1.70, which is the shape the ladder is
## for: a first run cannot max it, and a fourth run has nothing left to want from it.
##
##
## ## Why the rows are not three tiers
##
## `AugmentNode.tier` is documented as display grouping, and `AugmentPanel._rebuild_tree`
## draws **one row per distinct tier value**. Eight nodes sharing a tier would be one
## `HBoxContainer` eight cards wide inside a card that is 480 px at 1x. So a row here *is*
## a tier, numbered 1-8, and the semantic tiers the design talks about are expressed by the
## gates instead — which is where they actually live: `requires` for rows 2-5,
## `requires_prestige` for rows 6-8, `exclusive_group` for rows 3 and 5.
##
## Two consequences worth knowing. Each exclusive triad needs a tier of its own, because the
## panel reads `tier[0].exclusive_group` for the whole row and draws one "PICK ONE" strip
## from it. And `global_technique` must stay tier 1, sort order 0, ungated and
## `payout_mult`: `loop_check` grabs `augments_for(&"global")[0]`, buys one level of it and
## asserts that automation income moved by exactly `effect_per_level`.
##
##
## ## Why the effects are not all payout
##
## `Progression.get_modifier` folds every global node into *every* source's lookup, so all
## four effect keys work globally and they reach different halves of the game:
##
## - `payout_mult` is the only one that reaches **automation income**, which is attributed
##   to source `&"automation"` and therefore sees no item's own nodes.
## - `damage_mult` is every act you actually perform — and on the kindness side it is the
##   *value of the kindness* (`friendly_base.effective_damage_mult`), so one node is worth
##   the same to a sponge as to a mace.
## - `mass_mult` is read by `weapon_base` only, so it is the physical half of the roster:
##   heavier bodies, larger contact impulses.
## - `cooldown_mult` is read by cursor powers, beams, the open hand's pet interval and
##   friendly items' contact cooldown — so it is the half of the roster that has a rate.
##
## Twenty-four payout multipliers in a row would be a spreadsheet. Sizes across the four
## keys are **not** equal, deliberately: a node that reaches less of the game is worth more
## per level than one that reaches all of it.
##
##
## ## Why every row costs both currencies
##
## Thirteen nodes are priced in Bones and eleven in Hearts, and no row is single-currency
## except where the row is a choice. A tree a damage-only player could buy out is a tree
## that quietly repeals D2 — the whole point of which is that you cannot get the good things
## without having been kind to him.
##
## Growth runs 1.16 at the top of the page to 1.28 at the bottom, above the 1.07-1.15 band
## `economy.md` sets for item nodes. That is on purpose and it is the same reason the four
## originals used 1.25: an item node multiplies one toy, a global node multiplies the entire
## game including everything bought after it, so its second level has to cost meaningfully
## more than its first or the tree outruns the shop it is supposed to be decorating.

const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")

const AUGMENTS_DIR := "res://Data/Augments"

const BONES := AugmentNodeScript.CURRENCY_BONES
const HEARTS := AugmentNodeScript.CURRENCY_HEARTS

## The page, top to bottom. One entry per row; `tier` is the row's index + 1 and each node's
## `sort_order` is its column, so the columns read left to right as written.
##
## Row fields are the ones that are a property of the *rung* rather than of the node:
## how many levels it has, what a level costs to escalate, and what opens it. Node fields
## are the ones that are genuinely per node: what it is called, what it multiplies, what it
## costs and in which currency, and which earlier node it hangs from.
##
## `growth` is 1.0 on the two exclusive rows because a one-level node never escalates;
## `EconomyMath.bulk_cost` special-cases it, and it is what every existing exclusive branch
## in `Data/Augments` already carries.
const ROWS := [
	# --- 1. No gate at all. The three you can buy the moment you can afford them, and the
	# only row that does not hang off something else. Cheapest in the tree, and still four
	# times the price of the first weapon: a global node should never be a first purchase.
	{
		"levels": 10, "growth": 1.16, "prestige": 0, "group": &"",
		"nodes": [
			{
				"id": &"global_technique", "name": "Technique",
				"text": "You have done this a lot. Everything lands better.",
				"effect": &"payout_mult", "per_level": 1.02,
				"cost": 2500, "currency": BONES, "requires": [],
			},
			{
				"id": &"global_showmanship", "name": "Showmanship",
				"text": "He plays to the crowd. There is no crowd.",
				"effect": &"payout_mult", "per_level": 1.02,
				"cost": 1200, "currency": HEARTS, "requires": [],
			},
			{
				"id": &"global_follow_through", "name": "Follow-Through",
				"text": "You have stopped stopping at the moment of contact.",
				"effect": &"damage_mult", "per_level": 1.02,
				"cost": 3000, "currency": BONES, "requires": [],
			},
		],
	},
	# --- 2. One rung up, each hanging off the node directly above it, so the page reads as
	# three columns rather than as a heap. Momentum and Devotion lose the Reincarnation gate
	# they used to carry: with rows 6-8 below them there is a real cross-run ladder now, and
	# these two were only ever standing in for one.
	{
		"levels": 10, "growth": 1.18, "prestige": 0, "group": &"",
		"nodes": [
			{
				"id": &"global_momentum", "name": "Momentum",
				"text": "Nothing about this is a hobby any more.",
				"effect": &"payout_mult", "per_level": 1.02,
				"cost": 9000, "currency": BONES, "requires": [&"global_technique"],
			},
			{
				"id": &"global_devotion", "name": "Devotion",
				"text": "He would do this for free. You are paying him in attention.",
				"effect": &"payout_mult", "per_level": 1.02,
				"cost": 4500, "currency": HEARTS, "requires": [&"global_showmanship"],
			},
			{
				"id": &"global_second_nature", "name": "Second Nature",
				"text": "You reach for the next thing before you have finished the last one.",
				"effect": &"cooldown_mult", "per_level": 0.98,
				"cost": 5000, "currency": HEARTS, "requires": [&"global_follow_through"],
			},
		],
	},
	# --- 3. The first permanent choice. All three require one Bones node and one Hearts
	# node, so nobody picks an identity before they have touched both halves of the economy.
	#
	# The three are **not** the same size, because they do not reach the same amount of the
	# game: Standing Order is the smallest number and the only one that pays while you are
	# not at the desk, and Steady Hands is the largest and reaches only the half of the
	# roster that has a rate at all.
	{
		"levels": 1, "growth": 1.0, "prestige": 0, "group": &"stance",
		"nodes": [
			{
				"id": &"global_bad_intentions", "name": "Bad Intentions",
				"text": "You are not doing this to find out what happens. You know what happens.",
				"effect": &"damage_mult", "per_level": 1.14,
				"cost": 20000, "currency": BONES,
				"requires": [&"global_technique", &"global_showmanship"],
			},
			{
				"id": &"global_standing_order", "name": "Standing Order",
				"text": "It pays whether or not you are at the desk. Mostly it is not you.",
				"effect": &"payout_mult", "per_level": 1.10,
				"cost": 15000, "currency": HEARTS,
				"requires": [&"global_technique", &"global_showmanship"],
			},
			{
				"id": &"global_steady_hands", "name": "Steady Hands",
				"text": "Nothing hurried, nothing wasted. Everything simply comes round sooner.",
				"effect": &"cooldown_mult", "per_level": 0.87,
				"cost": 12000, "currency": HEARTS,
				"requires": [&"global_technique", &"global_showmanship"],
			},
		],
	},
	# --- 4. The back half of the levelled tree, and the only row with a weight node: by the
	# time a player is here they own enough physical bodies for "everything is heavier" to be
	# felt across the desk rather than on one bat.
	{
		"levels": 10, "growth": 1.20, "prestige": 0, "group": &"",
		"nodes": [
			{
				"id": &"global_reputation", "name": "Reputation",
				"text": "People have started asking what it is you do all day.",
				"effect": &"payout_mult", "per_level": 1.025,
				"cost": 30000, "currency": BONES, "requires": [&"global_momentum"],
			},
			{
				"id": &"global_the_arrangement", "name": "The Arrangement",
				"text": "Neither of you calls it a job. It is a job.",
				"effect": &"payout_mult", "per_level": 1.025,
				"cost": 15000, "currency": HEARTS, "requires": [&"global_devotion"],
			},
			{
				"id": &"global_dead_weight", "name": "Dead Weight",
				"text": "Everything on the desk has quietly got heavier. He has noticed.",
				"effect": &"mass_mult", "per_level": 1.025,
				"cost": 25000, "currency": BONES, "requires": [&"global_second_nature"],
			},
		],
	},
	# --- 5. The second permanent choice, and the last thing a first run can reach. Same
	# structure as row 3 one tier up: one Bones prerequisite and one Hearts prerequisite,
	# three sizes chosen for how much of the game each one touches.
	{
		"levels": 1, "growth": 1.0, "prestige": 0, "group": &"vocation",
		"nodes": [
			{
				"id": &"global_house_rules", "name": "House Rules",
				"text": "There are rules now. Most of them are about how hard.",
				"effect": &"damage_mult", "per_level": 1.10,
				"cost": 45000, "currency": BONES,
				"requires": [&"global_reputation", &"global_the_arrangement"],
			},
			{
				"id": &"global_day_job", "name": "Day Job",
				"text": "You clock on. He clocks on. Nobody ever discussed it.",
				"effect": &"payout_mult", "per_level": 1.08,
				"cost": 60000, "currency": BONES,
				"requires": [&"global_reputation", &"global_the_arrangement"],
			},
			{
				"id": &"global_bedside_manner", "name": "Bedside Manner",
				"text": "He has stopped bracing. That saves the pair of you a great deal of time.",
				"effect": &"cooldown_mult", "per_level": 0.90,
				"cost": 30000, "currency": HEARTS,
				"requires": [&"global_reputation", &"global_the_arrangement"],
			},
		],
	},
	# --- 6, 7 and 8. The cross-run ladder, one row per Reincarnation. Six levels rather than
	# ten, so a row is a short sharp climb you finish inside the run that opened it, and each
	# row is worth about x1.70 — the same rung three times, so the tenth reset is still
	# reading the same tree the second one was.
	#
	# These are `requires_prestige`'s content. It has been implemented since M2 and had two
	# users before this file.
	{
		"levels": 6, "growth": 1.24, "prestige": 1, "group": &"",
		"nodes": [
			{
				"id": &"global_past_lives", "name": "Past Lives",
				"text": "You have done all of this before. He has not.",
				"effect": &"payout_mult", "per_level": 1.03,
				"cost": 40000, "currency": BONES, "requires": [],
			},
			{
				"id": &"global_carried_over", "name": "Carried Over",
				"text": "Some of the affection survived the reset. Not all of it.",
				"effect": &"payout_mult", "per_level": 1.03,
				"cost": 20000, "currency": HEARTS, "requires": [],
			},
			{
				"id": &"global_old_habits", "name": "Old Habits",
				"text": "The first swing of a new run is not a beginner's swing.",
				"effect": &"damage_mult", "per_level": 1.03,
				"cost": 50000, "currency": BONES, "requires": [],
			},
		],
	},
	{
		"levels": 6, "growth": 1.26, "prestige": 2, "group": &"",
		"nodes": [
			{
				"id": &"global_bone_deep", "name": "Bone Deep",
				"text": "Two lifetimes of practice, in a body that keeps being replaced.",
				"effect": &"damage_mult", "per_level": 1.03,
				"cost": 120000, "currency": BONES, "requires": [&"global_old_habits"],
			},
			{
				"id": &"global_word_of_mouth", "name": "Word of Mouth",
				"text": "Somebody out there has heard about the two of you.",
				"effect": &"payout_mult", "per_level": 1.03,
				"cost": 60000, "currency": HEARTS, "requires": [&"global_carried_over"],
			},
			{
				"id": &"global_settled_weight", "name": "Settled Weight",
				"text": "Everything sits a little more firmly than it did. Including him.",
				"effect": &"mass_mult", "per_level": 1.03,
				"cost": 100000, "currency": BONES, "requires": [&"global_past_lives"],
			},
		],
	},
	{
		"levels": 6, "growth": 1.28, "prestige": 3, "group": &"",
		"nodes": [
			{
				"id": &"global_tenure", "name": "Tenure",
				"text": "Three deaths in, and nobody has asked either of you to stop.",
				"effect": &"payout_mult", "per_level": 1.03,
				"cost": 250000, "currency": BONES, "requires": [&"global_settled_weight"],
			},
			{
				"id": &"global_understanding", "name": "Understanding",
				"text": "Neither of you needs telling what happens next.",
				"effect": &"payout_mult", "per_level": 1.03,
				"cost": 125000, "currency": HEARTS, "requires": [&"global_word_of_mouth"],
			},
			{
				"id": &"global_no_wasted_motion", "name": "No Wasted Motion",
				"text": "Nothing takes as long as it used to. Nothing ever will again.",
				"effect": &"cooldown_mult", "per_level": 0.97,
				"cost": 150000, "currency": HEARTS, "requires": [&"global_bone_deep"],
			},
		],
	},
]

var _written := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(AUGMENTS_DIR)
	for index in ROWS.size():
		_seed_row(index, ROWS[index])
	print("seed_m36_globals: %d resources written" % _written)
	get_tree().quit()

func _seed_row(index: int, row: Dictionary) -> void:
	var column := 0
	for entry in row["nodes"]:
		var node := AugmentNodeScript.new()
		node.id = entry["id"]
		node.item_id = AugmentNodeScript.GLOBAL
		node.display_name = entry["name"]
		node.description = entry["text"]
		node.tier = index + 1
		node.effect_key = entry["effect"]
		node.effect_per_level = entry["per_level"]
		node.max_levels = row["levels"]
		node.cost_base = entry["cost"]
		node.cost_growth = row["growth"]
		node.currency = entry["currency"]
		node.exclusive_group = row["group"]
		# `requires` is typed on the resource, and a plain Array assigned straight into a
		# typed export is a runtime error rather than a conversion.
		var requires: Array[StringName] = []
		requires.assign(entry["requires"])
		node.requires = requires
		node.requires_prestige = row["prestige"]
		# There is no mastery track for the global tree — `mastery_rank(&"global")` is 0
		# forever, so a requires_mastery here would be a node nobody can ever buy.
		node.requires_mastery = 0
		node.sort_order = column
		_save(node, "%s/%s.tres" % [AUGMENTS_DIR, entry["id"]])
		column += 1

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m36_globals: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
