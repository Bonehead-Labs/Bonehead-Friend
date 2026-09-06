extends Node

## Plays the whole game at speed and checks that it is paced the way the design says.
##
##   Godot --headless --path <project> res://tests/integration/pacing_sim.tscn
##   ... res://tests/integration/pacing_sim.tscn -- --csv       (dump the timeline)
##   ... res://tests/integration/pacing_sim.tscn -- --divisor 5e7   (try a prestige divisor)
##
## **Why this exists.** Every balance target in `docs/economy.md` is a statement about
## *hours* — first automation by 30 minutes, first Reincarnation between six and ten hours,
## no dead stretch in the first afternoon — and nothing in the project could check one of
## them. They were verified by reading the numbers and believing them, which is how the
## shipped prestige divisor came to be five orders of magnitude out of reach: 1e12 against
## a run that earns 2x10^7 in eight hours.
##
## A human playtest is still the ground truth for whether the game is *fun*. This is the
## instrument that says whether it is *reachable*, and it runs in about a second.
##
## **What it is not.** It is not the game. It is a model of a player, stated in constants
## below so that every number it produces can be argued with. When the sim and a CSV from a
## real session disagree, the session wins and the model gets fixed.
##
## It runs as a scene rather than under `-s` because it reads the real content out of
## `ItemDB` — the maths it runs on that content is the same autoload-free `EconomyMath` /
## `AugmentMath` / `MasteryMath` the game uses, which is exactly why those modules are pure.

# --- the simulated player --------------------------------------------------

## Seconds of hands-on play per hour. The pitch is a game that lives on a work desktop, so
## the player is *not* playing most of the time: twelve minutes an hour is a couple of
## minutes at the top of each hour and a longer session at lunch.
const ACTIVE_SECONDS_PER_HOUR := 12.0 * 60.0

## Of that active time, the share spent hitting him rather than being kind to him. The
## economy wants both — automation is Hearts-gated — and a real player leans on the half
## that pays for what they are saving for. 0.6 is the split the design assumes.
const DAMAGE_SHARE := 0.6

## Damage per second of swinging, before the weapon's own multiplier and its augments. A
## knockout is 400 damage, and the design wants a round to take 30-60 seconds of active
## play, so a base of 10 with the starter bat puts an unaugmented round at 40 seconds.
const BASE_DAMAGE_PER_SECOND := 10.0

## Kindness events per second while petting. `balance.pet_interval` is 0.25s, but nobody
## strokes a skeleton at a metronomic four times a second for twelve minutes.
const PETS_PER_SECOND := 3.0

## The mood he is kept at while being played with. The U-curve pays best at the extremes and
## worst in the middle; a player who has understood the mechanic parks him at one end, and
## one who has not sits near neutral. 70 is "has understood it, is not perfect at it".
const PLAY_MOOD := 70.0

## Mood decays to nothing while nobody is playing, and neutral is the bottom of the curve.
const IDLE_MOOD := 0.0

## Share of active time spent on the best toy on each side, with the rest spread evenly
## over everything else owned. Mastery is per item and rank 25 gates automation, so this
## single number decides whether the engine ever starts: at 1.0 only one device is ever
## bought, and at 0.0 none are.
const FOCUS_SHARE := 0.6

## Simulation step. One second is exact enough for purchase timing to the minute and cheap
## enough to run fifty hours of game in under a second of wall clock.
const STEP := 1.0

# --- the targets, from docs/economy.md -------------------------------------

const TARGET_FIRST_AUTOMATION_SECONDS := 30.0 * 60.0
const TARGET_FIRST_PRESTIGE_MIN := 6.0 * 3600.0
const TARGET_FIRST_PRESTIGE_MAX := 10.0 * 3600.0
## The longest a player may go, **with their hands on the game**, without being able to buy
## anything. Measured in active seconds rather than wall clock on purpose: this model plays
## twelve minutes an hour and walks away, and nobody is staring at a shop they are not
## looking at. A dead stretch only counts while somebody is there to feel it.
const TARGET_MAX_PURCHASE_GAP := 5.0 * 60.0
## Prestige N+1 may take at most this multiple of the run before it, for the first five.
const TARGET_PRESTIGE_RAMP := 2.0

## When the simulated player takes a reset: once it would add this share of the Marrow they
## already hold. A real player reads the Rebirth number and makes the same judgement — there
## is no threshold in the maths to read instead (D33).
const RESET_WHEN_WORTH := 0.5
## ...and never for less than this, so the first reset is not taken in the first minute.
const MINIMUM_RESET := 1.0
const HOURS_SIMULATED := 72.0

var _passed := 0
var _failed := 0

# --- the simulated save ----------------------------------------------------

var _bones := 0.0
var _hearts := 0.0
var _lifetime := 0.0
var _owned: Dictionary = {}          ## StringName -> true
var _levels: Dictionary = {}         ## augment id -> int
var _xp: Dictionary = {}             ## item id -> float
var _pool := 0
var _marrow := 0.0
var _prestiges := 0
var _round_damage := 0.0
## Earned since the last reset. Marrow is scaled by this and not by lifetime, which is the
## whole difference between cycles that stay the same length and cycles that grow eightfold.
var _run_earnings := 0.0

## Resolved multipliers and rosters, invalidated on every purchase — the same cache
## `Progression` keeps, and for the same reason: this is read on every tick of a
## forty-thousand-tick run.
var _mods: Dictionary = {}
var _sides: Dictionary = {}

var _time := 0.0
## Seconds with hands on the game, which is the clock the purchase-gap target is measured
## against.
var _active := 0.0
var _log: Array[String] = []
var _events: Array[Dictionary] = []
var _csv := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_csv = args.has("--csv")
	var divisor := ItemDB.balance.marrow_divisor
	var flag := args.find("--divisor")
	if flag >= 0 and flag + 1 < args.size():
		divisor = float(args[flag + 1])

	print("")
	print("Bonehead Friend — pacing simulator")
	print("==================================")
	print("  marrow_divisor %s   %d items   %.0f min/hour of play"
		% [_short(divisor), ItemDB.all_items().size(), ACTIVE_SECONDS_PER_HOUR / 60.0])

	_reset_run(true)
	_simulate(HOURS_SIMULATED * 3600.0, divisor)
	_report(divisor)

	print("")
	print("==================================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- the loop --------------------------------------------------------------

func _simulate(seconds: float, divisor: float) -> void:
	var active_left := ACTIVE_SECONDS_PER_HOUR
	var hour_mark := 3600.0
	while _time < seconds:
		# Play happens at the top of each hour, then the desk is left alone. Front-loading
		# it rather than spreading it evenly matters: automation income during the idle
		# stretch is what the whole engine is for, and a player who is always half-playing
		# would hide a broken idle curve.
		var playing := active_left > 0.0
		if playing:
			active_left -= STEP
			_active += STEP
		_earn(STEP, playing)
		_spend()

		_time += STEP
		if _time >= hour_mark:
			if int(hour_mark / 3600.0) % 6 == 0 or hour_mark <= 3600.0 * 8.0:
				_note("hour %d: lifetime %s, purse %s bones %s hearts, idle %.1f+%.1f/s"
					% [int(hour_mark / 3600.0), _short(_lifetime), _short(_bones), _short(_hearts),
						_automation_rate(&"bones"), _automation_rate(&"hearts")], "hour")
			hour_mark += 3600.0
			active_left = ACTIVE_SECONDS_PER_HOUR

		# A reset is taken the moment it is worth taking, which is the strategy the genre
		# teaches and the one the targets are written against.
		# No threshold: the simulated player resets when the run is worth a meaningful slice
		# of what they already hold, which is the judgement a real player makes when the
		# Rebirth page shows them a number (D33).
		var gain := EconomyMath.marrow_for_run(_run_earnings, divisor,
			ItemDB.balance.marrow_exponent)
		if gain >= maxf(RESET_WHEN_WORTH * _marrow, MINIMUM_RESET) and _prestiges < 5:
			_note("reincarnate %d  (+%.2f marrow, run %s)"
				% [_prestiges + 1, gain, _short(_run_earnings)], "prestige")
			_marrow += gain
			_prestiges += 1
			_reset_run(false)

func _earn(delta: float, playing: bool) -> void:
	var b := ItemDB.balance
	var mood := ItemDB.mood_multiplier_for(&"stoic", PLAY_MOOD if playing else IDLE_MOOD)
	var prestige := EconomyMath.marrow_multiplier(_marrow)
	var pool := MasteryMath.pool_multiplier(_pool, b.mastery_pool_thresholds,
		b.mastery_pool_income_step)

	if playing:
		# **A favourite, and everything else.** Two wrong models were tried first and both
		# taught something. Swinging only the best weapon masters only that weapon, so only
		# one capstone ever unlocks and idle income has a hard ceiling of one device. But
		# splitting time evenly across sixteen weapons masters *none* of them — rank 25 is
		# 16,440 XP, which is forty-five minutes of undivided play — so the sim bought eight
		# Hearts capstones, zero Bones ones, and ended twelve hours with 1,095 Hearts/s and
		# no Bones income whatsoever.
		#
		# Neither is a person. A player leans on a favourite and picks up the rest, which is
		# also the behaviour the Mastery Pool is designed to reward — so that is what this
		# models, at FOCUS_SHARE on the best toy and the remainder spread.
		var weapons := _side(false)
		for weapon in weapons:
			var share := delta * DAMAGE_SHARE * _attention(weapons, weapon)
			var damage := BASE_DAMAGE_PER_SECOND * _modifier(weapon, &"damage_mult") * share
			_round_damage += damage
			_grant(damage * b.bones_per_damage * mood * _modifier(weapon, &"payout_mult")
				* _mastery(weapon) * pool * prestige, true)
			_add_xp(weapon, damage * b.mastery_xp_per_damage)

		# The knockout beat: the round's climax, and a real slice of active income.
		if _round_damage >= b.knockout_damage:
			_round_damage -= b.knockout_damage
			_grant(EconomyMath.knockout_bonus(b.knockout_damage, b.knockout_mult,
				b.knockout_exponent) * mood * pool * prestige, true)

		var kinds := _side(true)
		for kind in kinds:
			var pets := PETS_PER_SECOND * delta * (1.0 - DAMAGE_SHARE) * _attention(kinds, kind)
			var value := pets * b.pet_value * _modifier(kind, &"damage_mult")
			# Petting inside the combo window is the point of petting, so the sim earns at
			# the middle of the ramp rather than at its floor.
			var combo := (1.0 + b.kindness_combo_max) * 0.5
			_grant(value * b.hearts_per_kindness * combo * mood
				* _modifier(kind, &"payout_mult") * _mastery(kind) * pool * prestige, false)
			_add_xp(kind, value * b.mastery_xp_per_kindness)

	# Automation runs whether or not anyone is watching — that is the whole engine.
	# Attributed to &"automation", so only global nodes reach it, exactly as in Economy.
	var global_payout := _modifier(&"global", &"payout_mult")
	_grant(_automation_rate(&"bones") * delta * mood * global_payout * pool * prestige, true)
	_grant(_automation_rate(&"hearts") * delta * mood * global_payout * pool * prestige, false)

func _grant(amount: float, bones: bool) -> void:
	if amount <= 0.0:
		return
	if bones:
		_bones += amount
	else:
		_hearts += amount
	_lifetime += amount
	_run_earnings += amount

# --- the greedy buyer ------------------------------------------------------

## Buys whatever it can, cheapest first, in the order a player actually reaches for:
## a new toy, then automation, then upgrades. Repeats until nothing is affordable, so a
## windfall is spent in the same tick it lands.
func _spend() -> void:
	while true:
		if _buy_item() or _buy_capstone() or _buy_node():
			continue
		return

func _buy_item() -> bool:
	var best: ItemData = null
	for item in ItemDB.all_items():
		if _owned.has(item.id) or item.cost <= 0:
			continue
		if not _requirements_met(item):
			continue
		if _balance(item.currency_id()) < float(item.cost):
			continue
		if best == null or item.cost < best.cost:
			best = item
	if best == null:
		return false
	_pay(best.currency_id(), float(best.cost))
	_owned[best.id] = true
	_sides.clear()
	_mods.clear()
	_note("bought %s (%s %d)" % [best.id, best.currency_id(), best.cost], "item")
	return true

## Capstones are all priced in Hearts whatever they produce, so "cheapest first" spends
## every Heart on whichever device happens to be cheap — which in practice meant eight
## Hearts generators and not one Bones device, and twelve simulated hours ending with no
## Bones income at all. A player balances their two economies; this buys for the side that
## is currently producing less.
func _buy_capstone() -> bool:
	var want_bones := _automation_rate(&"bones") <= _automation_rate(&"hearts")
	var best: AugmentNode = null
	var best_cost := 0.0
	for pass_wanted in [true, false]:
		for node in _available_nodes():
			if not node.is_automation:
				continue
			var item := ItemDB.get_item(node.item_id)
			var makes_bones := item == null or item.currency != ItemData.CURRENCY_HEARTS
			if pass_wanted and makes_bones != want_bones:
				continue
			var cost := _next_cost(node)
			if cost < 0.0 or _balance(node.currency_id()) < cost:
				continue
			if best == null or cost < best_cost:
				best = node
				best_cost = cost
		if best != null:
			break
	if best == null:
		return false
	_pay(best.currency_id(), best_cost)
	var level := int(_levels.get(best.id, 0)) + 1
	_levels[best.id] = level
	_mods.clear()
	if level == 1:
		_note("automation: %s" % best.id, "automation")
	return true

func _buy_node() -> bool:
	var best: AugmentNode = null
	var best_cost := 0.0
	for node in _available_nodes():
		if node.is_automation:
			continue
		# One branch per exclusive group, like the real gate.
		if node.exclusive_group != &"" and _has_branch(node):
			continue
		var cost := _next_cost(node)
		if cost < 0.0 or _balance(node.currency_id()) < cost:
			continue
		if best == null or cost < best_cost:
			best = node
			best_cost = cost
	if best == null:
		return false
	_pay(best.currency_id(), best_cost)
	_levels[best.id] = int(_levels.get(best.id, 0)) + 1
	_mods.clear()
	return true

## Every node the player could buy a level of right now, gates included.
func _available_nodes() -> Array[AugmentNode]:
	var out: Array[AugmentNode] = []
	for id in _owned:
		for node in ItemDB.augments_for(id):
			if _node_open(node):
				out.append(node)
	for node in ItemDB.augments_for(AugmentNode.GLOBAL):
		if _node_open(node):
			out.append(node)
	return out

func _node_open(node: AugmentNode) -> bool:
	if int(_levels.get(node.id, 0)) >= node.max_levels:
		return false
	if node.requires_mastery > _rank(node.item_id):
		return false
	if node.requires_prestige > _prestiges:
		return false
	for req in node.requires:
		if int(_levels.get(req, 0)) <= 0:
			return false
	return true

func _has_branch(node: AugmentNode) -> bool:
	for other in ItemDB.augments_for(node.item_id):
		if other.exclusive_group == node.exclusive_group and other.id != node.id \
				and int(_levels.get(other.id, 0)) > 0:
			return true
	return false

func _next_cost(node: AugmentNode) -> float:
	var owned := int(_levels.get(node.id, 0))
	if owned >= node.max_levels:
		return -1.0
	var b := ItemDB.balance
	var discount := MasteryMath.pool_multiplier(_pool, b.mastery_pool_thresholds,
		b.mastery_pool_cost_step)
	return EconomyMath.augment_cost(float(node.cost_base) * discount, node.cost_growth, owned)

func _requirements_met(item: ItemData) -> bool:
	for req in item.requires:
		if not _owned.has(req):
			return false
	return true

# --- state helpers ---------------------------------------------------------

func _balance(currency: StringName) -> float:
	return _hearts if currency == &"hearts" else _bones

func _pay(currency: StringName, amount: float) -> void:
	if currency == &"hearts":
		_hearts -= amount
	else:
		_bones -= amount

## The same product `Progression.get_modifier` computes: the item's own nodes and every
## global one.
func _modifier(source: StringName, key: StringName) -> float:
	var cache_key := "%s/%s" % [source, key]
	if _mods.has(cache_key):
		return float(_mods[cache_key])
	var entries: Array = []
	for node in ItemDB.augments_for(source):
		if node.effect_key == key and not node.is_automation:
			entries.append([node.effect_per_level, int(_levels.get(node.id, 0))])
	if source != AugmentNode.GLOBAL:
		for node in ItemDB.augments_for(AugmentNode.GLOBAL):
			if node.effect_key == key:
				entries.append([node.effect_per_level, int(_levels.get(node.id, 0))])
	var value := AugmentMath.total_modifier(entries)
	_mods[cache_key] = value
	return value

func _automation_rate(currency: StringName) -> float:
	var total := 0.0
	for id in _levels:
		var node := ItemDB.get_augment(id)
		if node == null or not node.is_automation:
			continue
		var item := ItemDB.get_item(node.item_id)
		if item == null or item.currency_id() != currency:
			continue
		total += node.automation_rate * float(int(_levels[id]))
	return total

func _add_xp(item_id: StringName, amount: float) -> void:
	var b := ItemDB.balance
	var before := _rank(item_id)
	_xp[item_id] = float(_xp.get(item_id, 0.0)) + amount
	var after := MasteryMath.rank_for_xp(b.mastery_base, _xp[item_id], b.mastery_exponent)
	if after > before:
		_pool += after - before

func _rank(item_id: StringName) -> int:
	var b := ItemDB.balance
	return MasteryMath.rank_for_xp(b.mastery_base, float(_xp.get(item_id, 0.0)), b.mastery_exponent)

func _mastery(item_id: StringName) -> float:
	var b := ItemDB.balance
	return MasteryMath.item_rank_multiplier(_rank(item_id), b.mastery_bonus_rank,
		b.mastery_rank_payout_bonus)

## How much of the side's time this item gets: `FOCUS_SHARE` for the best of them, the rest
## divided evenly. The best is by resolved multiplier, which is what "best" means to a
## player looking at their own damage numbers.
func _attention(side: Array[StringName], item_id: StringName) -> float:
	if side.size() == 1:
		return 1.0
	var best := _favourite(side)
	if item_id == best:
		return FOCUS_SHARE
	# The rest goes to the newest toys, not the whole cupboard. Spread over every owned item
	# it thinned to nothing as the roster grew: at 34 kind items each got 0.4 x 0.4 / 33 of
	# the time, no kind item reached rank 25 for nineteen hours, and every kind item added
	# pushed the first Reincarnation later — 7:03 at 80 items, 9:45 at 100, 10:02 at 106,
	# through a ceiling of 10:00. The Aug 31 session is what a person does: a favourite and
	# the last few things they bought.
	var recent := _recent(side, best)
	if not recent.has(item_id):
		return 0.0
	return (1.0 - FOCUS_SHARE) / float(recent.size())

## The `SPREAD_COUNT` most recently bought items on this side, favourite excluded. `_owned`
## is insertion-ordered and `_side()` preserves it, so the newest are at the end.
const SPREAD_COUNT := 5

func _recent(side: Array[StringName], best: StringName) -> Array:
	var key := "recent/%s/%d" % [side[0], side.size()]
	if _mods.has(key):
		return _mods[key]
	var out: Array = []
	var i := side.size() - 1
	while i >= 0 and out.size() < SPREAD_COUNT:
		if side[i] != best:
			out.append(side[i])
		i -= 1
	_mods[key] = out
	return out

func _favourite(side: Array[StringName]) -> StringName:
	var key := "fav/%s" % side.size() if side.is_empty() else "fav/%s" % side[0]
	if _mods.has(key):
		return _mods[key]
	var best := side[0]
	var best_value := 0.0
	for id in side:
		var value := _modifier(id, &"damage_mult") * _modifier(id, &"payout_mult")
		if value > best_value:
			best = id
			best_value = value
	_mods[key] = best
	return best

## Everything owned on one side of the economy. Rebuilt only when the roster changes —
## this is read every tick, and allocating an array per tick for twelve simulated hours is
## the difference between a one-second run and a thirty-second one.
func _side(hearts: bool) -> Array[StringName]:
	var key := &"hearts" if hearts else &"bones"
	if _sides.has(key):
		return _sides[key]
	var out: Array[StringName] = []
	for id in _owned:
		var item := ItemDB.get_item(id)
		if item and (item.currency == ItemData.CURRENCY_HEARTS) == hearts:
			out.append(id)
	_sides[key] = out
	return out

## A reset keeps the meta and wipes the run — the same split `Economy.perform_prestige` and
## `Progression.reset_for_prestige` make.
func _reset_run(first: bool) -> void:
	_bones = 0.0
	_hearts = 0.0
	_owned.clear()
	_levels.clear()
	_xp.clear()
	_pool = 0
	_round_damage = 0.0
	_mods.clear()
	_sides.clear()
	_run_earnings = 0.0
	if first:
		_lifetime = 0.0
	for item in ItemDB.starter_items():
		_owned[item.id] = true

# --- reporting -------------------------------------------------------------

func _note(what: String, kind: String) -> void:
	_events.append({"t": _time, "active": _active, "kind": kind, "what": what})
	_log.append("  %s  %s" % [_clock(_time), what])

func _report(divisor: float) -> void:
	if _csv:
		print("")
		print("seconds,kind,what")
		for e in _events:
			print("%.0f,%s,%s" % [e["t"], e["kind"], e["what"]])

	print("")
	print("  timeline")
	for line in _log:
		print(line)
	print("")
	print("  after %.0fh: lifetime %s   idle %.1f Bones/s + %.1f Hearts/s   %d items   %d prestiges"
		% [HOURS_SIMULATED, _short(_lifetime), _automation_rate(&"bones"),
			_automation_rate(&"hearts"), _owned.size(), _prestiges])
	print("")

	# Play time, not wall clock, and for the same reason the purchase gap is: a first
	# session is somebody sitting down with a new game, not somebody leaving it open for
	# half a day. The wall-clock stamp is printed beside it because it is what a returning
	# player would actually experience.
	var first_automation := _first("automation", true)
	_check("first automation inside 30 minutes of play (%s of play, %s in)"
		% [_clock(first_automation), _clock(_first("automation"))],
		first_automation >= 0.0 and first_automation <= TARGET_FIRST_AUTOMATION_SECONDS)

	var gap := _longest_gap(2.0 * ACTIVE_SECONDS_PER_HOUR)
	_check("nothing to buy for at most 5 minutes of play in the first two hours (worst %s)"
		% _clock(gap), gap <= TARGET_MAX_PURCHASE_GAP)

	var first_prestige := _first("prestige")
	_check("first Reincarnation between 6 and 10 hours (%s)" % _clock(first_prestige),
		first_prestige >= TARGET_FIRST_PRESTIGE_MIN and first_prestige <= TARGET_FIRST_PRESTIGE_MAX)

	# Each reset should come a little slower than the last, never several times slower: the
	# spec asks for 5-15 minutes early and 30-60 later, which is a gentle ramp, and a cube
	# root over unbounded income is what makes that possible at all.
	var runs := _prestige_runs()
	var ramp_ok := true
	var worst := 0.0
	for i in range(1, runs.size()):
		var ratio: float = runs[i] / maxf(runs[i - 1], 1.0)
		worst = maxf(worst, ratio)
		if ratio > TARGET_PRESTIGE_RAMP:
			ramp_ok = false
	_check("each Reincarnation is at most 2x the pacing of the last (worst %.1fx over %d runs)"
		% [worst, runs.size()], runs.size() < 2 or ramp_ok)

	if _failed > 0:
		print("")
		print("  the divisor that would land the first reset at 8 hours: %s"
			% _short(_divisor_for_target(divisor)))

## The Marrow divisor that would make a first reset worth one Marrow — a doubling — at the
## eight-hour mark. Marrow is `(run / divisor) ^ exponent`, so one Marrow at eight hours
## means the divisor is simply what a run earns by then.
func _divisor_for_target(_current: float) -> float:
	return _lifetime * (8.0 * 3600.0) / maxf(_time, 1.0)

func _first(kind: String, in_play_time: bool = false) -> float:
	for e in _events:
		if e["kind"] == kind:
			return float(e["active"] if in_play_time else e["t"])
	return -1.0

## The longest stretch of *play* without a purchase, up to `until` active seconds in.
func _longest_gap(until: float) -> float:
	var previous := 0.0
	var worst := 0.0
	for e in _events:
		var at := float(e["active"])
		if at > until:
			break
		if e["kind"] == "item" or e["kind"] == "automation":
			worst = maxf(worst, at - previous)
			previous = at
	return maxf(worst, minf(until, _active) - previous)

func _prestige_runs() -> Array[float]:
	var out: Array[float] = []
	var previous := 0.0
	for e in _events:
		if e["kind"] != "prestige":
			continue
		out.append(float(e["t"]) - previous)
		previous = float(e["t"])
	return out

func _clock(seconds: float) -> String:
	if seconds < 0.0:
		return "never"
	return "%02d:%02d:%02d" % [int(seconds) / 3600, (int(seconds) / 60) % 60, int(seconds) % 60]

func _short(value: float) -> String:
	if value >= 1e9:
		return "%.2fe9" % (value / 1e9)
	if value >= 1e6:
		return "%.2fe6" % (value / 1e6)
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%.0f" % value

func _check(what: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("    ok   %s" % what)
	else:
		_failed += 1
		printerr("    FAIL %s" % what)
