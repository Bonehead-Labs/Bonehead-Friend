extends Node

## Currency balances and the single payout pipeline.
##
## Every Bone and every Heart in the game is created here and nowhere else. Damage and
## kindness take the identical path (docs/economy.md):
##
##   raw event -> base -> x mood -> x augments -> x mastery -> x prestige -> x timed -> payout
##
## The maths itself lives in EconomyMath, which is pure and unit-tested; this autoload is
## the state and the wiring around it.

const BONES := &"bones"
const HEARTS := &"hearts"
## The third currency (docs/decisions.md D31). Unlike the Ectoplasm it replaced, it is a
## real spendable balance and goes through `spend()` like the other two — what makes it
## different is where it comes from, not how it is held.
const DOLLARS := &"dollars"

## Mirrors of the buddy's own state, kept here only so the payout pipeline can multiply
## by them without Economy holding a reference to a scene node. MoodComponent and
## GrimeComponent are the owners; these follow them off the bus.
var mood: float = 0.0    ## -100..+100
var grime: float = 0.0   ## 0..1, suppresses Bones income

var _balances: Dictionary = {BONES: 0.0, HEARTS: 0.0, DOLLARS: 0.0}
var _lifetime: Dictionary = {BONES: 0.0, HEARTS: 0.0}

## Permanent income multiplier from Reincarnating, as `1 + marrow` (D33). A **stat, not a
## currency**: never spent, never in the purse, one effect.
var marrow: float = 0.0
## Bones and Hearts earned since the last reset. Marrow is scaled by this rather than by
## lifetime, which is the whole difference between a loop whose cycles stay the same length
## and one whose cycles grow eightfold.
var run_earnings: float = 0.0
var prestige_count: int = 0
var personality: String = "stoic"
var offline_cap_level: int = 0

## Damage banked since the last knockout. The knockout bonus is paid on this.
var round_damage: float = 0.0
var stats: Dictionary = {"damage_dealt": 0.0, "pets": 0, "knockouts": 0}

## Where the last payout happened, so the knockout fountain has somewhere to come from
## without Economy holding a reference to the buddy.
var _last_payout_pos: Vector2 = Vector2.ZERO

## Kindness combo state: consecutive events inside balance.kindness_combo_window.
var _combo_count: int = 0
var _combo_deadline_msec: int = 0

## Automation income banked between payouts, per currency. Banked rather than granted per
## frame for the same reason FriendlyBase banks its rate: a payout per frame is a floating
## number per frame and a bus signal per frame, for income the player reads as a trickle.
var _automation_banked: Dictionary = {BONES: 0.0, HEARTS: 0.0}
var _automation_timer: float = 0.0

func _ready() -> void:
	SaveManager.register_provider(self)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kindness_given.connect(_on_kindness_given)
	EventBus.kindness_sustained.connect(_on_kindness_sustained)
	EventBus.mood_changed.connect(_on_mood_changed)
	EventBus.grime_changed.connect(_on_grime_changed)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)

# --- balances --------------------------------------------------------------

## Every currency that appears on `currency_changed` must be readable here, or a UI that
## polls disagrees with the same UI when it listens.
func balance_of(currency: StringName) -> float:
	return float(_balances.get(currency, 0.0))

func lifetime_of(currency: StringName) -> float:
	return float(_lifetime.get(currency, 0.0))

func can_afford(currency: StringName, amount: float) -> bool:
	return balance_of(currency) >= amount

## Deducts if affordable. Returns false and changes nothing otherwise, so callers can
## treat it as the single purchase gate.
func spend(currency: StringName, amount: float) -> bool:
	if amount < 0.0 or not can_afford(currency, amount):
		return false
	_balances[currency] = balance_of(currency) - amount
	EventBus.currency_changed.emit(currency, balance_of(currency))
	return true

## Credits a currency and announces it. `world_pos` is where the floating number appears.
func grant(currency: StringName, amount: float, world_pos: Vector2 = Vector2.ZERO,
		source_id: StringName = &"") -> void:
	if amount <= 0.0:
		return
	_balances[currency] = balance_of(currency) + amount
	if currency != DOLLARS:
		# Dollars are not income: they are a count of acts, and Marrow is scaled by income.
		# Letting them into either total would make cosmetics pay for prestige.
		_lifetime[currency] = lifetime_of(currency) + amount
		run_earnings += amount
	# Only a payout that happened *somewhere* moves it. Contract claims and arcade wins are
	# granted from a panel and carry no world position at all, and letting their Vector2.ZERO
	# through parks the knockout fountain in the corner of the screen until the next hit.
	if world_pos != Vector2.ZERO:
		_last_payout_pos = world_pos
	EventBus.payout.emit(currency, amount, world_pos, source_id)
	EventBus.currency_changed.emit(currency, balance_of(currency))

## Per-act Dollars are banked and paid on the automation tick rather than granted per hit.
## A hit is the busiest event in the game (seven a second per source, twenty under a fast
## turret), and each grant is two bus signals every listener on the shell reacts to; the
## Dollar itself is a flat count of acts that nobody can act on within the second. Flushed by
## the tick, and by `flush_dollars()` for anything that needs the count to be exact right now.
var _dollars_banked := 0.0

func _bank_dollars(amount: float) -> void:
	_dollars_banked += amount

func flush_dollars() -> void:
	if _dollars_banked <= 0.0:
		return
	var amount := _dollars_banked
	_dollars_banked = 0.0
	grant(DOLLARS, amount, Vector2.ZERO, &"acts")

# --- payout pipeline -------------------------------------------------------

## Mood multiplier: a U-curve, worst at neutral. Sitting in the middle is the worst
## possible play, which is what makes the optimal rhythm oscillate.
func mood_multiplier() -> float:
	return ItemDB.mood_multiplier_for(StringName(personality), mood)

## The permanent half of the payout pipeline: everything earned is multiplied by this, and
## the only way it grows is Reincarnating.
func marrow_multiplier() -> float:
	return EconomyMath.marrow_multiplier(marrow)

## Bones only. Letting him get filthy costs damage income, and the sponge — the cheapest
## Hearts item in the game — is the only thing that removes it. That is the dual-currency
## spine in one multiplier: you cannot opt out of the kindness half for free (D2).
func grime_multiplier() -> float:
	return MoodMath.grime_penalty(grime, ItemDB.balance.grime_max_penalty)

## The one shared slot for a temporary multiplier, as `id -> [multiplier, deadline msec]`.
##
## **One slot, not one per feature.** The arcade's boosts (docs/decisions.md D32), the Dream
## Journal and Overtime Pay all want the same thing, and three multipliers applied in three
## places is how a pipeline drifts — this one is a product, `payout_for` multiplies by it, and
## nothing else in the game has to know any of those features exist.
##
## **Never saved.** A buff that survived a restart is a buff you farm by restarting. The
## deadlines are `Time.get_ticks_msec()` — engine ticks since boot — so it cannot be persisted
## even by accident, and `to_save()` does not mention it deliberately.
##
## **Expiry is read, not scheduled.** An entry dies when the clock passes it, whether or not
## anything is processing and whether or not any node is in the tree: there is no timer to
## leak and nothing to unregister when a page closes.
var _temp_effects: Dictionary = {}

## The product changed — added, replaced, or noticed expired. Local rather than on EventBus:
## the arcade page is the only thing that reads it, and a signal on the bus is a promise to
## every listener in the game that this is a thing they should care about.
signal temp_multiplier_changed(multiplier: float)

## Adds or refreshes a timed effect. `seconds` is wall-clock from now.
##
## An id is a slot, not a stack: a second win from the same machine refreshes its own effect
## rather than piling up. A weaker offer never replaces a stronger live one — a x1.1 from a
## spin must not cancel the x5 the player won a minute ago — and an equal one extends it, so
## a deadline can only ever move outward.
func add_temp_multiplier(id: StringName, multiplier: float, seconds: float) -> void:
	if id == &"" or multiplier <= 1.0 or seconds <= 0.0:
		return
	var now := Time.get_ticks_msec()
	var deadline := now + int(seconds * 1000.0)
	if _temp_effects.has(id):
		var live: Array = _temp_effects[id]
		if int(live[1]) > now:
			if float(live[0]) > multiplier:
				return
			deadline = maxi(deadline, int(live[1]))
	_temp_effects[id] = [multiplier, deadline]
	temp_multiplier_changed.emit(temp_multiplier())

## The product of every live effect, and 1.0 when there are none.
##
## Expired entries are dropped here and nowhere else, which is safe because `payout_for` calls
## this on every payout in the game — nothing accumulates for longer than the next hit.
func temp_multiplier() -> float:
	if _temp_effects.is_empty():
		return 1.0
	var now := Time.get_ticks_msec()
	var product := 1.0
	var expired: Array = []
	for id in _temp_effects:
		var effect: Array = _temp_effects[id]
		if int(effect[1]) <= now:
			expired.append(id)
			continue
		product *= float(effect[0])
	for id in expired:
		_temp_effects.erase(id)
	if not expired.is_empty():
		temp_multiplier_changed.emit(product)
	return product

## What is live, longest remaining first, for a UI printing a countdown:
## `[{"id": StringName, "multiplier": float, "seconds_left": float}]`.
func temp_effects() -> Array[Dictionary]:
	var now := Time.get_ticks_msec()
	var out: Array[Dictionary] = []
	for id in _temp_effects:
		var effect: Array = _temp_effects[id]
		var left := float(int(effect[1]) - now) / 1000.0
		if left <= 0.0:
			continue
		out.append({"id": id, "multiplier": float(effect[0]), "seconds_left": left})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["seconds_left"]) > float(b["seconds_left"]))
	return out

## Drops every live effect. For the suites, which compute an expected payout from the
## multipliers in force and cannot do that against a buff an earlier suite happened to win.
func clear_temp_multipliers() -> void:
	if _temp_effects.is_empty():
		return
	_temp_effects.clear()
	temp_multiplier_changed.emit(1.0)

## The pipeline, in one place so its order cannot drift between damage and kindness.
##
## The timed multiplier is applied here rather than inside `EconomyMath.payout_for`, which is
## pure, unit-tested against exactly five multipliers, and reachable from the `-s` runner that
## has no autoloads to hold a deadline. Multiplication commutes, so "last" is a matter of
## reading order and not of arithmetic.
##
## Dollars never come through here (D31), so a timed boost cannot multiply them — which is the
## point: a x5 that also paid Dollars would let the arcade print its own admission fee.
func payout_for(base: float, source_id: StringName) -> float:
	return EconomyMath.payout_for(
		base,
		mood_multiplier(),
		Progression.get_modifier(source_id, &"payout_mult"),
		Progression.mastery_multiplier(source_id),
		marrow_multiplier()) * temp_multiplier() * Milestones.income_multiplier()

## Consecutive hits inside `STREAK_WINDOW`, for presentation only: the tag beside the number
## and the pitch of the impact climb with it. It pays nothing — every multiplier in this game
## is data (D11), and a streak is deliberately not in the data, so the feeling of momentum
## costs the balance nothing. The kindness combo beside it does pay, by design (D14).
const STREAK_WINDOW := 1.5
var _streak_count := 0
var _streak_deadline_msec := 0

func damage_streak() -> int:
	return _streak_count if Time.get_ticks_msec() < _streak_deadline_msec else 0

## Set for the duration of a kind act's own payout emit (see `_on_kindness_given`).
var paying_kind_act := false

func _on_damage_dealt(info: HitInfo) -> void:
	var now := Time.get_ticks_msec()
	_streak_count = _streak_count + 1 if now < _streak_deadline_msec else 1
	_streak_deadline_msec = now + int(STREAK_WINDOW * 1000.0)
	round_damage += info.amount
	stats["damage_dealt"] = float(stats.get("damage_dealt", 0.0)) + info.amount
	var bones := payout_for(
		info.amount * ItemDB.balance.bones_per_damage * grime_multiplier(), info.source_id)
	grant(BONES, bones, info.position, info.source_id)
	# `damage:<item_id>`, which turns "deal N damage with the mace" into pure data for every
	# weapon in the game at once — HitInfo has always carried source_id and nothing read it
	# for this. Emitted with the damage as its count, so a contract counts damage rather
	# than swings; `use:<item_id>` counts the swings and the two are different questions.
	EventBus.contract_event.emit(&"damage:%s" % info.source_id, int(info.amount))
	# Flat, whatever the weapon and whatever the damage: Dollars count acts, not power
	# (docs/decisions.md D31). Banked, not granted: no floating number and no bus traffic per
	# hit — a "+1" beside every Bones payout would double the noise of the busiest event in
	# the game, and the count is paid on the automation tick.
	_bank_dollars(ItemDB.balance.dollars_per_hit)
	EventBus.contract_event.emit(&"deal_damage", int(info.amount))

## How many kind acts in a row are inside the combo window right now. Read-only, for the
## buddy's expression: a petting streak shows on him, not only on the payout.
func kindness_combo() -> int:
	return _combo_count if Time.get_ticks_msec() < _combo_deadline_msec else 0

func _on_kindness_given(source_id: StringName, value: float, world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var b := ItemDB.balance
	_combo_count = _combo_count + 1 if now < _combo_deadline_msec else 0
	_combo_deadline_msec = now + int(b.kindness_combo_window * 1000.0)

	var combo := EconomyMath.kindness_combo(_combo_count, b.kindness_combo_step, b.kindness_combo_max)
	var hearts := payout_for(value * b.hearts_per_kindness * combo, source_id)
	# True only while this act's payout is on the bus, so the FX layer can tag the combo on
	# the number that actually carried it and not on a hot tub's trickle arriving mid-streak.
	paying_kind_act = true
	grant(HEARTS, hearts, world_pos, source_id)
	paying_kind_act = false
	_bank_dollars(ItemDB.balance.dollars_per_kind_act)
	stats["pets"] = int(stats.get("pets", 0)) + 1
	EventBus.contract_event.emit(&"kindness", 1)

## Rate-paid kindness. The same pipeline, minus the combo — see the signal's note on the
## bus. It also leaves the combo *deadline* alone, so scrubbing him with a sponge does not
## silently keep a petting combo alive.
func _on_kindness_sustained(source_id: StringName, value: float, world_pos: Vector2) -> void:
	var hearts := payout_for(value * ItemDB.balance.hearts_per_kindness, source_id)
	grant(HEARTS, hearts, world_pos, source_id)
	# Deliberately no contract_event. A contract counting kindness counts *acts*, and a
	# generator is not acting — it flushes twice a second forever, so one boombox left on
	# the desk would finish a "be kind 150 times" contract in seventy-five seconds with
	# nobody at the keyboard. Same reasoning as skipping the combo, one line further on.

## The knockout bonus is the round's climax payout. Economy owns it rather than the buddy
## because Economy is the only thing in the game allowed to mint currency.
func _on_buddy_state_changed(state: StringName) -> void:
	if state != &"knockout":
		return
	var b := ItemDB.balance
	var bonus := payout_for(
		EconomyMath.knockout_bonus(round_damage, b.knockout_mult, b.knockout_exponent),
		&"knockout")
	grant(BONES, bonus, _last_payout_pos)
	stats["knockouts"] = int(stats.get("knockouts", 0)) + 1
	round_damage = 0.0
	EventBus.knockout_payout.emit(bonus)
	EventBus.contract_event.emit(&"knockout", 1)
	EventBus.save_requested.emit()

func _on_mood_changed(value: float) -> void:
	mood = value

func _on_grime_changed(value: float) -> void:
	grime = value

# --- automation ------------------------------------------------------------

## Automation while the game is open. Full rate here; offline is deliberately worth less
## (`offline_efficiency`), because the whole pitch is that it lives on your desktop.
func _process(delta: float) -> void:
	var bones_rate := Progression.automation_rate_per_second(BONES)
	var hearts_rate := Progression.automation_rate_per_second(HEARTS)
	var automating := bones_rate > 0.0 or hearts_rate > 0.0
	if not automating and _dollars_banked <= 0.0:
		return

	if automating:
		_automation_banked[BONES] = float(_automation_banked[BONES]) + bones_rate * delta
		_automation_banked[HEARTS] = float(_automation_banked[HEARTS]) + hearts_rate * delta

	_automation_timer += delta
	if _automation_timer < ItemDB.balance.automation_payout_interval:
		return
	_automation_timer = 0.0
	for currency in [BONES, HEARTS]:
		var banked := float(_automation_banked[currency])
		if banked <= 0.0:
			continue
		_automation_banked[currency] = 0.0
		# Through the pipeline like everything else, so mood, mastery and Marrow apply to
		# automated income exactly as they do to a swing. Attributed to &"automation" rather
		# than to an item, because several capstones pay into the same tick.
		grant(currency, payout_for(banked, &"automation"), _last_payout_pos, &"automation")
	# The devices' own trickle of Dollars, at a fraction of what a hand on the game earns —
	# the one deliberately idle-unfriendly rate in the economy — joins the acts banked since
	# the last tick, and the till is paid once.
	if automating:
		var b := ItemDB.balance
		_bank_dollars(b.dollars_per_hit * b.dollars_idle_efficiency * b.automation_payout_interval)
	flush_dollars()

# --- offline ---------------------------------------------------------------

## Accrual for time the game was closed. Only automation earns offline.
##
## **Offline pays the stable multipliers and not the volatile ones** — prestige and the
## Mastery Pool, never mood, a timed boost, per-item augments or an item's own mastery
## rank. That is a decision, not an omission (docs/economy.md): mood is a live value the
## player was not there to maintain, so paying eight hours of income at whatever mood he
## happened to be left in either rewards parking him at an extreme before quitting or
## punishes a session that ended mid-swing. Prestige and the pool are properties of the
## save, so they are honest to apply while nobody is watching. Until M3.5-A this called
## `grant()` directly and offline income got *none* of the four, while online automation
## got all of them.
##
## Returns {currency: amount} for what was earned, so the caller can show a summary.
func apply_offline_earnings(last_played_unix: int) -> Dictionary:
	var b := ItemDB.balance
	var cap := b.offline_cap_seconds(offline_cap_level)
	# Negative deltas are real — clock changes, timezone shifts, cloud-sync skew — and
	# must never pay out.
	var elapsed := SaveSchema.offline_seconds(last_played_unix, int(Time.get_unix_time_from_system()), cap)
	var stable := marrow_multiplier() * Progression.mastery_pool_bonus()
	var earned := {}
	for currency in [BONES, HEARTS]:
		var rate := Progression.automation_rate_per_second(currency)
		var amount := EconomyMath.offline_earnings(rate, elapsed, b.offline_efficiency) * stable
		earned[currency] = amount
		if amount > 0.0:
			grant(currency, amount)
	earned["seconds"] = elapsed
	# Whether the cap was the thing that decided the number — the welcome says so once.
	earned["capped"] = elapsed >= cap and elapsed > 0.0
	return earned

# --- prestige --------------------------------------------------------------

## What a reset would pay right now. There is no threshold — this is simply a number that
## climbs as the run does, and the Rebirth page states it (D33).
func pending_marrow() -> float:
	var b := ItemDB.balance
	return EconomyMath.marrow_for_run(run_earnings, b.marrow_divisor, b.marrow_exponent)

# --- the wardrobe ------------------------------------------------------------

## Cosmetics: owned ids and what he is wearing per slot. Meta, like Marrow — a Reincarnation
## does not undress him (docs/game-design.md § Cosmetics). Free cosmetics are owned by
## everyone without being listed; nothing here reads a colour, so a cosmetic cannot touch a
## payout (D31).
var _cosmetics_owned: Dictionary = {}     ## id -> true
var _cosmetics_worn: Dictionary = {}      ## slot -> id

func owns_cosmetic(id: StringName) -> bool:
	if _cosmetics_owned.has(id):
		return true
	var cosmetic := ItemDB.get_cosmetic(id)
	return cosmetic != null and cosmetic.is_free()

func buy_cosmetic(id: StringName) -> bool:
	var cosmetic := ItemDB.get_cosmetic(id)
	if cosmetic == null or owns_cosmetic(id):
		return false
	if not spend(DOLLARS, float(cosmetic.price_dollars)):
		return false
	_cosmetics_owned[id] = true
	EventBus.save_requested.emit()
	return true

## Wear something he owns. Returns false for a cosmetic he does not own or that does not exist.
func wear_cosmetic(id: StringName) -> bool:
	var cosmetic := ItemDB.get_cosmetic(id)
	if cosmetic == null or not owns_cosmetic(id):
		return false
	if _cosmetics_worn.get(cosmetic.slot, &"") == id:
		return true
	_cosmetics_worn[cosmetic.slot] = id
	EventBus.cosmetic_changed.emit(cosmetic.slot, id)
	EventBus.save_requested.emit()
	return true

func worn_cosmetic(slot: StringName) -> StringName:
	return _cosmetics_worn.get(slot, &"")

## An empty slot is drawn as drawn, so the free cosmetic of that slot is what he is wearing.
func is_wearing(id: StringName) -> bool:
	var cosmetic := ItemDB.get_cosmetic(id)
	if cosmetic == null:
		return false
	var worn := worn_cosmetic(cosmetic.slot)
	if worn == &"":
		return cosmetic.is_free()
	return worn == id

## How long he can sleep for, and what the next step costs. The cap is meta — it survives a
## Reincarnation like Marrow does — so it is not an augment node (those are the run's) and is
## sold beside Reincarnation instead. Hearts-priced, as docs/game-design.md says, and the price
## ladder is a balance knob. Returns a negative cost when he already sleeps as long as he can.
func offline_cap_cost() -> float:
	var ladder := ItemDB.balance.offline_cap_cost_hearts
	if offline_cap_level >= ladder.size():
		return -1.0
	return float(ladder[offline_cap_level])

func buy_offline_cap() -> bool:
	var cost := offline_cap_cost()
	if cost < 0.0 or not spend(HEARTS, cost):
		return false
	offline_cap_level += 1
	EventBus.save_requested.emit()
	return true

## Reincarnation. Wipes the run and keeps the meta: Marrow, Dollars, cosmetics, lifetime
## totals, the reset count and the offline cap.
##
## Returns the Marrow gained, or 0 if there was nothing to gain — resetting a run that has
## earned nothing is always a mistake and is refused rather than confirmed.
func perform_prestige() -> float:
	var gained := pending_marrow()
	if gained <= 0.0:
		return 0.0

	marrow += gained
	prestige_count += 1
	personality = _roll_personality()

	_balances[BONES] = 0.0
	_balances[HEARTS] = 0.0
	# Dollars survive: they are the meta currency now, and a reset that confiscated the
	# player's hat money would make Reincarnating something to avoid.
	run_earnings = 0.0
	round_damage = 0.0
	_combo_count = 0
	_automation_banked = {BONES: 0.0, HEARTS: 0.0}
	Progression.reset_for_prestige()

	EventBus.currency_changed.emit(BONES, 0.0)
	EventBus.currency_changed.emit(HEARTS, 0.0)
	EventBus.prestige_performed.emit(gained)
	EventBus.save_requested.emit()
	return gained

## A new personality every reset, never the one just played — the whole point is that the
## next run asks for a different rhythm, and rolling the same one twice reads as the feature
## being broken rather than as chance.
func _roll_personality() -> String:
	var choices: Array[String] = []
	for candidate in ItemDB.all_personalities():
		if String(candidate.id) != personality:
			choices.append(String(candidate.id))
	if choices.is_empty():
		return personality
	return choices[randi() % choices.size()]

# --- save ------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"currencies": {"bones": balance_of(BONES), "hearts": balance_of(HEARTS),
			"dollars": balance_of(DOLLARS)},
		"lifetime": {"bones": lifetime_of(BONES), "hearts": lifetime_of(HEARTS)},
		"prestige": {"marrow": marrow, "count": prestige_count, "personality": personality,
			"run_earnings": run_earnings},
		"offline_cap_level": offline_cap_level,
		"stats": stats.duplicate(),
		# The schema's own shape: owned ids, and the worn ids as a flat list (one per slot).
		"cosmetics": {"owned": _cosmetics_owned.keys().map(func(k: StringName) -> String: return String(k)),
			"equipped": _cosmetics_worn.values().map(func(v: StringName) -> String: return String(v))},
	}

func from_save(root: Dictionary) -> void:
	var currencies: Dictionary = root.get("currencies", {})
	_balances[BONES] = float(currencies.get("bones", 0.0))
	_balances[HEARTS] = float(currencies.get("hearts", 0.0))
	_balances[DOLLARS] = float(currencies.get("dollars", 0.0))

	var life: Dictionary = root.get("lifetime", {})
	_lifetime[BONES] = float(life.get("bones", 0.0))
	_lifetime[HEARTS] = float(life.get("hearts", 0.0))

	var prestige: Dictionary = root.get("prestige", {})
	marrow = float(prestige.get("marrow", 0.0))
	prestige_count = int(prestige.get("count", 0))
	personality = String(prestige.get("personality", "stoic"))
	run_earnings = float(prestige.get("run_earnings", 0.0))

	offline_cap_level = int(root.get("offline_cap_level", 0))
	stats = (root.get("stats", {}) as Dictionary).duplicate()
	round_damage = 0.0

	var cosmetics: Dictionary = root.get("cosmetics", {})
	_cosmetics_owned.clear()
	for id in cosmetics.get("owned", []):
		_cosmetics_owned[StringName(String(id))] = true
	_cosmetics_worn.clear()
	for id in cosmetics.get("equipped", []):
		var cosmetic := ItemDB.get_cosmetic(StringName(String(id)))
		# A cosmetic that no longer exists is simply not worn; he is drawn as drawn.
		if cosmetic:
			_cosmetics_worn[cosmetic.slot] = cosmetic.id
	for slot in [CosmeticData.SLOT_BONE, CosmeticData.SLOT_PHONES]:
		EventBus.cosmetic_changed.emit(slot, worn_cosmetic(slot))

	# All three, or a returning player sees a chip reading 0 until their next payout — the
	# HUD seeds its labels from this signal and nothing else.
	for currency in [BONES, HEARTS, DOLLARS]:
		EventBus.currency_changed.emit(currency, balance_of(currency))
