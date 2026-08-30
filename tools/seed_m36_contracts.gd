extends Node

## Writes M3.6's contract board: forty-four more jobs, so three daily slots and one weekly
## slot are not the same six offers every morning.
##
##   Godot --headless --path <project> res://tools/seed_m36_contracts.tscn [-- --force]
##
## M3 shipped six contracts against `contracts_daily_slots` 3 and `contracts_weekly_slots`
## 1. Four of the six were on the board every single day and the weekly never changed at
## all, so the daily-return hook returned nothing to come back for — a static list with a
## progress bar on it. Forty-four is the number at which three drawn slots stop repeating
## inside a week.
##
## Only what does not already exist is written, like every other hand-authored seed tool.
## A contract id is a save join key — `contracts.progress`, `contracts.claimed` and
## `contracts.active` are all keyed by it — so the six M3 ids stay exactly as the owner
## named them, and `sort_order` starts at 100 to leave their 0..50 block alone.
##
## **A contract can only count what something emits.** `ContractData.KNOWN_KEYS` is a gate,
## and three of the keys used here had no emit behind them before this milestone: a melee
## weapon's `use:<item_id>` (a landed hit), an explosive's (a detonation), and `pick_up`
## (lifting Bonehead off the desk). Key and emit site landed in the same change, because a
## key nothing emits is a job the player can never finish and the gate exists to catch
## precisely that.
##
## **Why every item-keyed job names a cheap toy.** `Progression._roll` draws from the whole
## pool without asking what the player owns, so "land 120 hits with the mace" offered to
## somebody who has no mace is a dead slot — and with one weekly slot, a gated weekly is a
## dead *week*. Everything named here is a free starter or under 1,000 Bones, which is the
## first hour or two of play; the two item-keyed weeklies name starters only. Opening this
## up to the katana, the minigun and the rest of the roster wants an ownership filter in the
## roll first.
##
## **Why five tiers of the same key.** A player's Tuesday is not the length of their Monday,
## and a light damage job and a heavy one are two different offers rather than the same
## offer twice. Reward tracks the ask: 300 Dollars for twenty minutes, 900 for an evening,
## anchored on the six M3 contracts (400 for 5,000 damage, 2,500 for 100,000).

const ContractDataScript := preload("res://Scripts/Data/contract_data.gd")

const CONTRACTS_DIR := "res://Data/Contracts"

const DAILY := ContractDataScript.PERIOD_DAILY
const WEEKLY := ContractDataScript.PERIOD_WEEKLY

## Where this milestone's block of `sort_order` begins. The M3 six occupy 0..50 and the
## board's roll is seeded by the period index rather than shuffled, so the order is stable
## and worth not disturbing.
const SORT_BASE := 100
const SORT_STEP := 10

## `[id, display name, objective, goal key, target, period, Dollars]`.
##
## The objective is written as a figure — "Deal 5,000 damage." — because that is what the
## panel sets in the unambiguous face and what the player is actually reading for. The
## display name is the joke.
const CONTRACTS := [
	# --- damage, five lengths of day ---
	[&"daily_damage_light", "Light Duties",
		"Deal 1,500 damage.", &"deal_damage", 1500, DAILY, 300],
	[&"daily_damage_burst", "Stress Test",
		"Deal 3,000 damage.", &"deal_damage", 3000, DAILY, 350],
	[&"daily_damage_mid", "A Productive Morning",
		"Deal 8,000 damage.", &"deal_damage", 8000, DAILY, 500],
	[&"daily_damage_heavy", "Unpaid Overtime",
		"Deal 15,000 damage.", &"deal_damage", 15000, DAILY, 700],
	[&"daily_damage_double", "Time And A Half",
		"Deal 25,000 damage.", &"deal_damage", 25000, DAILY, 900],

	# --- knockouts. One round is `knockout_damage` 400, so these read across to the damage
	# jobs above: three rounds is a coffee break, forty is a whole evening.
	[&"daily_knockouts_few", "Best Of Three",
		"Knock him out 3 times.", &"knockout", 3, DAILY, 300],
	[&"daily_knockouts_mid", "Rematch",
		"Knock him out 6 times.", &"knockout", 6, DAILY, 400],
	[&"daily_knockouts_many", "Back To Back",
		"Knock him out 25 times.", &"knockout", 25, DAILY, 700],
	[&"daily_knockouts_card", "Full Card",
		"Knock him out 40 times.", &"knockout", 40, DAILY, 900],

	# --- kindness. Acts, not generator ticks: a placed boombox emits `kindness_sustained`
	# and deliberately no contract event, so these cannot be left running.
	[&"daily_kindness_small", "Duty Of Care",
		"Be kind to him 40 times.", &"kindness", 40, DAILY, 300],
	[&"daily_kindness_quick", "Small Mercies",
		"Be kind to him 90 times.", &"kindness", 90, DAILY, 350],
	[&"daily_kindness_mid", "Welfare Check",
		"Be kind to him 250 times.", &"kindness", 250, DAILY, 500],
	[&"daily_kindness_large", "Pastoral Care",
		"Be kind to him 400 times.", &"kindness", 400, DAILY, 650],
	[&"daily_kindness_huge", "Employee Wellbeing",
		"Be kind to him 750 times.", &"kindness", 750, DAILY, 850],

	# --- petting. One event every `pet_interval` 0.25 s while the hand is held on him, so
	# a thousand pets is about four minutes of holding and the cheapest job on the board in
	# real time. Priced as such.
	[&"daily_pet_small", "Hands On",
		"Pet him 60 times.", &"pet", 60, DAILY, 300],
	[&"daily_pet_quick", "Five Minutes Of Your Time",
		"Pet him 120 times.", &"pet", 120, DAILY, 350],
	[&"daily_pet_mid", "Positive Reinforcement",
		"Pet him 350 times.", &"pet", 350, DAILY, 500],
	[&"daily_pet_large", "Emotional Labour",
		"Pet him 500 times.", &"pet", 500, DAILY, 600],
	[&"daily_pet_huge", "Above And Beyond",
		"Pet him 1,000 times.", &"pet", 1000, DAILY, 800],

	# --- shopping. Kept to two, and to small targets, because `purchase` fires only for a
	# shop item: a player who owns all twenty-eight and has not Reincarnated cannot move
	# one of these at all. Low targets are what keep them clearable while the ladder lasts.
	[&"daily_purchase_one", "Procurement",
		"Buy 1 new toy.", &"purchase", 1, DAILY, 300],
	[&"daily_purchase_three", "Capital Expenditure",
		"Buy 3 new toys.", &"purchase", 3, DAILY, 700],

	# --- picking him up. The only key in the game that needs nothing bought and no aim, so
	# it is the board's floor: a job a player can finish on their first afternoon.
	[&"daily_pickup_small", "Manual Handling",
		"Pick him up 40 times.", &"pick_up", 40, DAILY, 300],
	[&"daily_pickup_large", "Health And Safety",
		"Pick him up 150 times.", &"pick_up", 150, DAILY, 500],

	# --- the trampoline. Gated on an 1,800-Bone toy, so both of these are dailies: a slot
	# lost for a day is survivable in a way a lost week is not.
	[&"daily_bounce_small", "Springboard",
		"Bounce him 100 times.", &"bounce", 100, DAILY, 450],
	[&"daily_bounce_large", "Team Building",
		"Bounce him 300 times.", &"bounce", 300, DAILY, 700],

	# --- named items. A melee "use" is a hit that got past the minimum impulse and the
	# per-source cooldown, so targets are landed swings rather than pick-ups; an explosive's
	# is a detonation, which is why twenty sticks of dynamite is a bigger ask than two
	# hundred bat hits.
	[&"daily_use_bat", "Batting Practice",
		"Land 200 hits with the baseball bat.", &"use:baseball_bat", 200, DAILY, 400],
	[&"daily_use_pan", "Kitchen Shift",
		"Land 150 hits with the frying pan.", &"use:frying_pan", 150, DAILY, 400],
	[&"daily_use_mace", "Blunt Instrument",
		"Land 120 hits with the mace.", &"use:mace", 120, DAILY, 500],
	[&"daily_use_bowling_ball", "Perfect Game",
		"Land 60 hits with the bowling ball.", &"use:bowling_ball", 60, DAILY, 400],
	[&"daily_use_grenade", "Controlled Demolition",
		"Set off 25 grenades.", &"use:grenade", 25, DAILY, 450],
	[&"daily_use_dynamite", "Site Clearance",
		"Set off 20 sticks of dynamite.", &"use:dynamite", 20, DAILY, 550],
	[&"daily_use_pistol", "Range Day",
		"Fire 200 pistol rounds.", &"use:pistol", 200, DAILY, 400],

	# --- weeklies. Seven days at one slot, so every one of these must be finishable by a
	# player who bought nothing this week: universal keys, plus the two free starters.
	[&"weekly_damage_light", "Quarterly Review",
		"Deal 40,000 damage.", &"deal_damage", 40000, WEEKLY, 2000],
	[&"weekly_damage_big", "Performance Review",
		"Deal 250,000 damage.", &"deal_damage", 250000, WEEKLY, 4000],
	[&"weekly_damage_huge", "Employee Of The Month",
		"Deal 500,000 damage.", &"deal_damage", 500000, WEEKLY, 5000],
	[&"weekly_knockouts", "Championship Season",
		"Knock him out 60 times.", &"knockout", 60, WEEKLY, 2500],
	[&"weekly_knockouts_big", "Undefeated",
		"Knock him out 150 times.", &"knockout", 150, WEEKLY, 4000],
	[&"weekly_kindness", "Care Plan",
		"Be kind to him 1,200 times.", &"kindness", 1200, WEEKLY, 2500],
	[&"weekly_kindness_big", "Carer's Allowance",
		"Be kind to him 3,000 times.", &"kindness", 3000, WEEKLY, 4000],
	[&"weekly_petting", "Long Service",
		"Pet him 2,500 times.", &"pet", 2500, WEEKLY, 2500],
	[&"weekly_petting_big", "Gold Watch",
		"Pet him 6,000 times.", &"pet", 6000, WEEKLY, 4000],
	[&"weekly_pickup", "Heavy Lifting",
		"Pick him up 600 times.", &"pick_up", 600, WEEKLY, 2500],
	[&"weekly_use_bat", "The Long Season",
		"Land 1,200 hits with the baseball bat.", &"use:baseball_bat", 1200, WEEKLY, 3000],
	[&"weekly_use_grenade", "Demolition Contract",
		"Set off 150 grenades.", &"use:grenade", 150, WEEKLY, 3000],
]

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	DirAccess.make_dir_recursive_absolute(CONTRACTS_DIR)
	for i in CONTRACTS.size():
		_contract(CONTRACTS[i], SORT_BASE + i * SORT_STEP)
	print("seed_m36_contracts: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _contract(entry: Array, sort_order: int) -> void:
	var path := "%s/%s.tres" % [CONTRACTS_DIR, entry[0]]
	if not _force and ResourceLoader.exists(path):
		_skipped += 1
		return

	var contract := ContractDataScript.new()
	contract.id = entry[0]
	contract.display_name = entry[1]
	contract.description = entry[2]
	contract.goal_key = entry[3]
	contract.target = entry[4]
	contract.period = entry[5]
	contract.reward_dollars = entry[6]
	contract.sort_order = sort_order

	# Refused here rather than at boot. ItemDB validates the same thing and drops what fails,
	# which means a typo in the table above ships as a contract that quietly is not there —
	# and the board is drawn from a pool nobody counts.
	var err: String = contract.validation_error()
	if not err.is_empty():
		push_error("seed_m36_contracts: %s" % err)
		return
	if not _names_a_real_item(contract.goal_key):
		return

	var save_err := ResourceSaver.save(contract, path)
	if save_err != OK:
		push_error("seed_m36_contracts: failed to write %s (error %d)" % [path, save_err])
		return
	_written += 1
	print("  wrote %s" % path)

## A `use:` key naming an item that does not exist passes `validation_error()` — the prefix
## is all that check knows about — and then never progresses, because nothing will ever emit
## that id. Catch the typo at authoring time.
func _names_a_real_item(goal_key: StringName) -> bool:
	var key := String(goal_key)
	if not key.begins_with(ContractDataScript.ITEM_KEY_PREFIX):
		return true
	var item_id := StringName(key.substr(ContractDataScript.ITEM_KEY_PREFIX.length()))
	if ItemDB.get_item(item_id) != null:
		return true
	push_error("seed_m36_contracts: '%s' names unknown item '%s'" % [goal_key, item_id])
	return false
