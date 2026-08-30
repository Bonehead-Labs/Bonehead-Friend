extends Node

## Currency balances and the single payout pipeline.
##
## Every Bone and every Heart in the game is created here and nowhere else. Damage and
## kindness take the identical path (docs/economy.md):
##
##   raw event -> base value -> x mood -> x augments -> x mastery -> x prestige -> payout
##
## The maths itself lives in EconomyMath, which is pure and unit-tested; this autoload is
## the state and the wiring around it.

const BONES := &"bones"
const HEARTS := &"hearts"
## Not in `_balances`: Ectoplasm is prestige-only and never spent through `spend()`, so it
## lives as a plain int. It rides the currency_changed signal so the HUD can show it.
const ECTOPLASM := &"ectoplasm"

## Mirrors of the buddy's own state, kept here only so the payout pipeline can multiply
## by them without Economy holding a reference to a scene node. MoodComponent and
## GrimeComponent are the owners; these follow them off the bus.
var mood: float = 0.0    ## -100..+100
var grime: float = 0.0   ## 0..1, suppresses Bones income

var _balances: Dictionary = {BONES: 0.0, HEARTS: 0.0}
var _lifetime: Dictionary = {BONES: 0.0, HEARTS: 0.0}

var ectoplasm: int = 0
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
## polls disagrees with the same UI when it listens. Ectoplasm lives outside `_balances`
## (it is never spent through `spend()`), so it is answered explicitly rather than falling
## through to the zero default — that fall-through made the HUD's ghost chip read 0.
func balance_of(currency: StringName) -> float:
	if currency == ECTOPLASM:
		return float(ectoplasm)
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
func grant(currency: StringName, amount: float, world_pos: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0.0:
		return
	_balances[currency] = balance_of(currency) + amount
	_lifetime[currency] = lifetime_of(currency) + amount
	_last_payout_pos = world_pos
	EventBus.payout.emit(currency, amount, world_pos)
	EventBus.currency_changed.emit(currency, balance_of(currency))

# --- payout pipeline -------------------------------------------------------

## Mood multiplier: a U-curve, worst at neutral. Sitting in the middle is the worst
## possible play, which is what makes the optimal rhythm oscillate.
func mood_multiplier() -> float:
	return ItemDB.mood_multiplier_for(StringName(personality), mood)

func prestige_multiplier() -> float:
	return EconomyMath.prestige_multiplier(ectoplasm)

## Bones only. Letting him get filthy costs damage income, and the sponge — the cheapest
## Hearts item in the game — is the only thing that removes it. That is the dual-currency
## spine in one multiplier: you cannot opt out of the kindness half for free (D2).
func grime_multiplier() -> float:
	return MoodMath.grime_penalty(grime, ItemDB.balance.grime_max_penalty)

## The pipeline, in one place so its order cannot drift between damage and kindness.
func payout_for(base: float, source_id: StringName) -> float:
	return EconomyMath.payout_for(
		base,
		mood_multiplier(),
		Progression.get_modifier(source_id, &"payout_mult"),
		Progression.mastery_multiplier(source_id),
		prestige_multiplier())

func _on_damage_dealt(info: HitInfo) -> void:
	round_damage += info.amount
	stats["damage_dealt"] = float(stats.get("damage_dealt", 0.0)) + info.amount
	var bones := payout_for(
		info.amount * ItemDB.balance.bones_per_damage * grime_multiplier(), info.source_id)
	grant(BONES, bones, info.position)
	EventBus.contract_event.emit(&"deal_damage", int(info.amount))

func _on_kindness_given(source_id: StringName, value: float, world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var b := ItemDB.balance
	_combo_count = _combo_count + 1 if now < _combo_deadline_msec else 0
	_combo_deadline_msec = now + int(b.kindness_combo_window * 1000.0)

	var combo := EconomyMath.kindness_combo(_combo_count, b.kindness_combo_step, b.kindness_combo_max)
	var hearts := payout_for(value * b.hearts_per_kindness * combo, source_id)
	grant(HEARTS, hearts, world_pos)
	stats["pets"] = int(stats.get("pets", 0)) + 1
	EventBus.contract_event.emit(&"kindness", 1)

## Rate-paid kindness. The same pipeline, minus the combo — see the signal's note on the
## bus. It also leaves the combo *deadline* alone, so scrubbing him with a sponge does not
## silently keep a petting combo alive.
func _on_kindness_sustained(source_id: StringName, value: float, world_pos: Vector2) -> void:
	var hearts := payout_for(value * ItemDB.balance.hearts_per_kindness, source_id)
	grant(HEARTS, hearts, world_pos)
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
	if bones_rate <= 0.0 and hearts_rate <= 0.0:
		return

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
		# Through the pipeline like everything else, so mood, mastery and prestige apply to
		# automated income exactly as they do to a swing. Attributed to &"automation" rather
		# than to an item, because several capstones pay into the same tick.
		grant(currency, payout_for(banked, &"automation"), _last_payout_pos)

# --- offline ---------------------------------------------------------------

## Accrual for time the game was closed. Only automation earns offline, so this is zero
## until the first capstone is bought in M3 — the plumbing is here now so the clamping
## and the cap are exercised from the start rather than bolted on later.
##
## Returns {currency: amount} for what was earned, so the caller can show a summary.
func apply_offline_earnings(last_played_unix: int) -> Dictionary:
	var b := ItemDB.balance
	var cap := b.offline_cap_seconds(offline_cap_level)
	# Negative deltas are real — clock changes, timezone shifts, cloud-sync skew — and
	# must never pay out.
	var elapsed := SaveSchema.offline_seconds(last_played_unix, int(Time.get_unix_time_from_system()), cap)
	var earned := {}
	for currency in [BONES, HEARTS]:
		var rate := Progression.automation_rate_per_second(currency)
		var amount := EconomyMath.offline_earnings(rate, elapsed, b.offline_efficiency)
		earned[currency] = amount
		if amount > 0.0:
			grant(currency, amount)
	earned["seconds"] = elapsed
	return earned

# --- prestige --------------------------------------------------------------

func pending_ectoplasm() -> int:
	return EconomyMath.prestige_gain(lifetime_of(BONES) + lifetime_of(HEARTS), ectoplasm, ItemDB.balance.prestige_divisor)

## Contracts pay in Ectoplasm directly rather than through the payout pipeline — it is a
## prestige currency, not an income one, so no multiplier applies to it.
func grant_ectoplasm(amount: int) -> void:
	if amount <= 0:
		return
	ectoplasm += amount
	EventBus.currency_changed.emit(ECTOPLASM, float(ectoplasm))

## Reincarnation. Resets the run and keeps the meta: Ectoplasm, lifetime totals (the
## prestige curve is built on them), the prestige count and the offline cap.
##
## Returns the Ectoplasm gained, or 0 if there was nothing to gain — resetting for zero is
## always a mistake and is refused rather than confirmed.
func perform_prestige() -> int:
	var gained := pending_ectoplasm()
	if gained <= 0:
		return 0

	ectoplasm += gained
	prestige_count += 1
	personality = _roll_personality()

	_balances[BONES] = 0.0
	_balances[HEARTS] = 0.0
	round_damage = 0.0
	_combo_count = 0
	_automation_banked = {BONES: 0.0, HEARTS: 0.0}
	Progression.reset_for_prestige()

	EventBus.currency_changed.emit(BONES, 0.0)
	EventBus.currency_changed.emit(HEARTS, 0.0)
	EventBus.currency_changed.emit(ECTOPLASM, float(ectoplasm))
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
		"currencies": {"bones": balance_of(BONES), "hearts": balance_of(HEARTS)},
		"lifetime": {"bones": lifetime_of(BONES), "hearts": lifetime_of(HEARTS)},
		"prestige": {"ectoplasm": ectoplasm, "count": prestige_count, "personality": personality},
		"offline_cap_level": offline_cap_level,
		"stats": stats.duplicate(),
	}

func from_save(root: Dictionary) -> void:
	var currencies: Dictionary = root.get("currencies", {})
	_balances[BONES] = float(currencies.get("bones", 0.0))
	_balances[HEARTS] = float(currencies.get("hearts", 0.0))

	var life: Dictionary = root.get("lifetime", {})
	_lifetime[BONES] = float(life.get("bones", 0.0))
	_lifetime[HEARTS] = float(life.get("hearts", 0.0))

	var prestige: Dictionary = root.get("prestige", {})
	ectoplasm = int(prestige.get("ectoplasm", 0))
	prestige_count = int(prestige.get("count", 0))
	personality = String(prestige.get("personality", "stoic"))

	offline_cap_level = int(root.get("offline_cap_level", 0))
	stats = (root.get("stats", {}) as Dictionary).duplicate()
	round_damage = 0.0

	EventBus.currency_changed.emit(BONES, balance_of(BONES))
	EventBus.currency_changed.emit(HEARTS, balance_of(HEARTS))
	# Ectoplasm too, or a returning player with 12 of it sees a chip reading 0 until their
	# next contract claim — the HUD seeds its labels from this signal and nothing else.
	EventBus.currency_changed.emit(ECTOPLASM, float(ectoplasm))
