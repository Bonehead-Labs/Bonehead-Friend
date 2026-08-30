extends Node

## The milestone board: fifty named milestones and twelve endless ladders.
##
##   Godot --headless --path <project> res://tools/seed_m36_milestones.tscn
##
## Milestones are the main source of Dollars (docs/decisions.md D31, D34), and the split
## between the two kinds is the whole design. A finite set pays well for a week and then
## stops — and the arcade goes dark exactly when somebody has settled in. So the named ones
## carry the first week and the ladders never run out.
##
## Rewards are sized against the arcade and the cosmetics counter, not against the shop: a
## named milestone is worth a spin or two, a late ladder rung is worth a hat, and none of it
## buys a toy, because Dollars cannot.
##
## `income_bonus` is x1.01 almost everywhere. Fifty of them is x1.64, which is a real reward
## for breadth and not a second economy — D11's one rule, applied to the third income axis.
##
## Format: [id, name, description, key, target, repeat_every, multiplies, dollars, bonus,
##          sort_order, hidden]

const MilestoneDataScript := preload("res://Scripts/Data/milestone_data.gd")

const MILESTONES_DIR := "res://Data/Milestones"

const NAMED := [
	# --- the first hour: things that happen whether or not anyone is trying ---
	[&"first_blood", "First Blood", "Hit him. That is the whole game, and you have found it.",
		&"deal_damage", 1.0, 250, 1.01, 0],
	[&"first_pet", "There, There", "Be kind to him once. The other half of the game, and the half most people find second.",
		&"kindness", 1.0, 250, 1.01, 10],
	[&"first_knockout", "Lights Out", "Knock him down for the first time.",
		&"knockout", 1.0, 400, 1.01, 20],
	[&"first_purchase", "Retail Debut", "Buy something. Anything.",
		&"purchase", 1.0, 300, 1.01, 30],
	[&"first_thousand", "Four Figures", "Earn a thousand Bones.",
		&"lifetime_bones", 1000.0, 400, 1.01, 40],
	[&"first_hearts", "Bedside", "Earn a thousand Hearts.",
		&"lifetime_hearts", 1000.0, 400, 1.01, 50],

	# --- damage, at every order of magnitude worth naming ---
	[&"damage_10k", "Occupational Hazard", "Deal ten thousand damage.",
		&"deal_damage", 10000.0, 500, 1.01, 100],
	[&"damage_1m", "Structural Concerns", "Deal a million damage. He is fine. He is always fine.",
		&"deal_damage", 1000000.0, 900, 1.01, 110],
	[&"damage_100m", "Bone Meal", "Deal a hundred million damage.",
		&"deal_damage", 100000000.0, 1800, 1.02, 120],
	[&"knockouts_10", "Ten Count", "Knock him out ten times.",
		&"knockout", 10.0, 400, 1.01, 130],
	[&"knockouts_100", "Century", "Knock him out a hundred times.",
		&"knockout", 100.0, 800, 1.01, 140],
	[&"knockouts_1000", "Repeat Offender", "Knock him out a thousand times. He keeps getting up.",
		&"knockout", 1000.0, 2000, 1.02, 150],

	# --- kindness, which pays worse and is the point ---
	[&"pets_100", "Good Boy", "Pet him a hundred times.",
		&"pet", 100.0, 400, 1.01, 200],
	[&"pets_10k", "Devoted", "Pet him ten thousand times. That is a real number of times.",
		&"pet", 10000.0, 1400, 1.02, 210],
	[&"kindness_1k", "Bedside Manner", "A thousand kind acts.",
		&"kindness", 1000.0, 700, 1.01, 220],
	[&"hearts_1m", "Beloved", "Earn a million Hearts.",
		&"lifetime_hearts", 1000000.0, 1600, 1.02, 230],

	# --- the shop ---
	[&"items_5", "Starting a Collection", "Own five toys.",
		&"items_owned", 5.0, 400, 1.01, 300],
	[&"items_15", "Cluttered Desk", "Own fifteen toys.",
		&"items_owned", 15.0, 700, 1.01, 310],
	[&"items_30", "Armoury", "Own thirty toys.",
		&"items_owned", 30.0, 1200, 1.02, 320],
	[&"items_50", "Occupational Overkill", "Own fifty toys. There is a person under there somewhere.",
		&"items_owned", 50.0, 2500, 1.02, 330],
	[&"purchases_25", "Retail Therapy", "Buy twenty-five things.",
		&"purchase", 25.0, 600, 1.01, 340],

	# --- upgrades and mastery ---
	[&"levels_50", "Tinkerer", "Buy fifty upgrade levels.",
		&"augment_levels", 50.0, 500, 1.01, 400],
	[&"levels_250", "Engineer", "Buy two hundred and fifty upgrade levels.",
		&"augment_levels", 250.0, 1000, 1.01, 410],
	[&"levels_1000", "Over-Engineered", "A thousand upgrade levels.",
		&"augment_levels", 1000.0, 2200, 1.02, 420],
	[&"pool_10", "Broad Interests", "Reach ten Mastery Pool points.",
		&"mastery_pool", 10.0, 500, 1.01, 430],
	[&"pool_50", "Well Rounded", "Fifty Mastery Pool points — the reward for using a variety rather than grinding one.",
		&"mastery_pool", 50.0, 1000, 1.01, 440],
	[&"pool_200", "Renaissance", "Two hundred Mastery Pool points.",
		&"mastery_pool", 200.0, 2400, 1.02, 450],

	# --- automation ---
	[&"first_device", "It Does It Itself", "Buy your first automation capstone. The desk starts working without you.",
		&"automation_rate", 0.5, 800, 1.02, 500],
	[&"automation_50", "Night Shift", "Reach fifty per second of automated income.",
		&"automation_rate", 50.0, 1200, 1.01, 510],
	[&"automation_1000", "Fully Staffed", "A thousand per second, while you are not even here.",
		&"automation_rate", 1000.0, 2600, 1.02, 520],

	# --- reincarnation ---
	[&"first_reset", "Second Life", "Reincarnate once.",
		&"reincarnations", 1.0, 1000, 1.02, 600],
	[&"resets_5", "Serial Reincarnator", "Reincarnate five times.",
		&"reincarnations", 5.0, 1800, 1.02, 610],
	[&"resets_25", "He Has Been Everyone", "Reincarnate twenty-five times.",
		&"reincarnations", 25.0, 4000, 1.03, 620],
	[&"marrow_1", "In The Bone", "Earn your first whole point of Marrow — a doubling of everything, permanently.",
		&"marrow", 1.0, 1200, 1.02, 630],
	[&"marrow_10", "Dense", "Ten Marrow.",
		&"marrow", 10.0, 2600, 1.02, 640],
	[&"marrow_100", "Fossilised", "A hundred Marrow.",
		&"marrow", 100.0, 6000, 1.03, 650],

	# --- money ---
	[&"dollars_1k", "Pocket Money", "Hold a thousand Dollars.",
		&"lifetime_dollars", 1000.0, 300, 1.01, 700],
	[&"dollars_100k", "Comfortable", "Hold a hundred thousand Dollars.",
		&"lifetime_dollars", 100000.0, 1500, 1.02, 710],
	[&"bones_1m", "Seven Figures", "Earn a million Bones.",
		&"lifetime_bones", 1000000.0, 1000, 1.01, 720],
	[&"bones_1b", "Nine Figures", "Earn a billion Bones.",
		&"lifetime_bones", 1000000000.0, 3000, 1.03, 730],

	# --- the desk, and the jokes ---
	[&"bounces_100", "Air Time", "Bounce him a hundred times.",
		&"bounce", 100.0, 500, 1.01, 800],
	[&"bounces_1000", "Frequent Flyer", "Bounce him a thousand times.",
		&"bounce", 1000.0, 1200, 1.01, 810],
	[&"use_bat_100", "Old Faithful", "Use the baseball bat a hundred times. The first toy is still a good toy.",
		&"use:baseball_bat", 100.0, 500, 1.01, 820],
	[&"use_hand_500", "Hands On", "Use the open hand five hundred times.",
		&"use:open_hand", 500.0, 600, 1.01, 830],
	[&"damage_1", "Curiosity", "You hit a skeleton on your desktop to see what would happen.",
		&"deal_damage", 1.0, 100, 1.0, 840, true],
	[&"kind_first_500", "Softie", "Five hundred kind acts and counting. Somebody had to.",
		&"kindness", 500.0, 600, 1.01, 850],
	[&"pool_1", "First Rank", "Master anything at all, once.",
		&"mastery_pool", 1.0, 250, 1.01, 860],
	[&"items_all_kind", "Everything He Likes", "Own ten kind things at once.",
		&"items_owned", 10.0, 600, 1.01, 870],
	[&"knockouts_500", "Attrition", "Five hundred knockouts.",
		&"knockout", 500.0, 1400, 1.01, 880],
	[&"damage_10m", "Load Bearing", "Ten million damage. Structurally, he should not still be here.",
		&"deal_damage", 10000000.0, 1400, 1.02, 890],
]

## The ladders. Each rung pays less than a named milestone and there is always another rung,
## which is the entire answer to "milestones are finite and Dollars come from milestones".
## Multiplying ladders (x10 of a lifetime total) keep pace with an economy that compounds;
## adding ladders (+100 knockouts) keep pace with an activity that does not.
const LADDERS = [
	[&"ladder_bones", "Bone Market", "Every tenfold of Bones ever earned.",
		&"lifetime_bones", 10000.0, 10.0, true, 600, 1.01, 1000],
	[&"ladder_hearts", "Growing Fondness", "Every tenfold of Hearts ever earned.",
		&"lifetime_hearts", 5000.0, 10.0, true, 600, 1.01, 1010],
	[&"ladder_damage", "Escalation", "Every tenfold of damage dealt.",
		&"deal_damage", 50000.0, 10.0, true, 500, 1.01, 1020],
	[&"ladder_knockouts", "Rounds Fought", "Every hundred knockouts.",
		&"knockout", 100.0, 100.0, false, 350, 1.01, 1030],
	[&"ladder_pets", "Attentive", "Every thousand pets.",
		&"pet", 1000.0, 1000.0, false, 300, 1.01, 1040],
	[&"ladder_kindness", "Kept Up", "Every thousand kind acts.",
		&"kindness", 1000.0, 1000.0, false, 300, 1.01, 1050],
	[&"ladder_levels", "Deeper Trees", "Every twenty-five upgrade levels, anywhere in the game.",
		&"augment_levels", 25.0, 25.0, false, 250, 1.01, 1060],
	[&"ladder_items", "Wider Desk", "Every five toys owned.",
		&"items_owned", 5.0, 5.0, false, 400, 1.01, 1070],
	[&"ladder_automation", "Compounding", "Every doubling of automated income.",
		&"automation_rate", 10.0, 2.0, true, 400, 1.01, 1080],
	[&"ladder_pool", "Broadening", "Every twenty-five Mastery Pool points.",
		&"mastery_pool", 25.0, 25.0, false, 450, 1.01, 1090],
	[&"ladder_resets", "Lives Lived", "Every five Reincarnations.",
		&"reincarnations", 5.0, 5.0, false, 900, 1.01, 1100],
	[&"ladder_marrow", "Denser Still", "Every doubling of Marrow.",
		&"marrow", 1.0, 2.0, true, 800, 1.01, 1110],
]

var _written := 0
var _skipped := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(MILESTONES_DIR)
	for entry in NAMED:
		_write(entry[0], entry[1], entry[2], entry[3], float(entry[4]), 0.0, false,
			int(entry[5]), float(entry[6]), int(entry[7]),
			entry.size() > 8 and bool(entry[8]))
	for entry in LADDERS:
		_write(entry[0], entry[1], entry[2], entry[3], float(entry[4]), float(entry[5]),
			bool(entry[6]), int(entry[7]), float(entry[8]), int(entry[9]), false)
	print("seed_m36_milestones: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _write(id: StringName, display_name: String, description: String, goal_key: StringName,
		target: float, repeat_every: float, multiplies: bool, dollars: int, bonus: float,
		sort_order: int, hidden: bool) -> void:
	var path := "%s/%s.tres" % [MILESTONES_DIR, id]
	if ResourceLoader.exists(path):
		_skipped += 1
		return
	var res := MilestoneDataScript.new()
	res.id = id
	res.display_name = display_name
	res.description = description
	res.goal_key = goal_key
	res.target = target
	res.repeat_every = repeat_every
	res.repeat_multiplies = multiplies
	res.reward_dollars = dollars
	res.income_bonus = bonus
	res.sort_order = sort_order
	res.hidden = hidden
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("seed_m36_milestones: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
