class_name SaveSchema
extends RefCounted

## The save format and its migrations, as pure functions with no engine dependencies.
##
## Deliberately separate from SaveManager (the autoload that does file IO and talks to
## EventBus): autoload singletons are not resolvable when a script is compiled under
## `godot -s`, so anything the headless test runner needs to reach must live here.
##
## CHANGING THE SCHEMA REQUIRES ALL THREE:
##   1. bump SAVE_VERSION
##   2. add a `case N: return _migrate_N_to_N_plus_1(d)` in _apply_migration
##   3. commit a fixture save of the old version under tests/fixtures/

const SAVE_VERSION := 4

static func new_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at_unix": 0,
		"last_played_unix": 0,

		"currencies": {"bones": 0.0, "hearts": 0.0, "dollars": 0.0},
		"lifetime": {"bones": 0.0, "hearts": 0.0},
		"prestige": {"marrow": 0.0, "count": 0, "personality": "stoic", "run_earnings": 0.0},
		"unlocks": [],
		"augments": {},
		"exclusive_choices": {},
		"mastery_xp": {},
		"mastery_pool": 0,
		"offline_cap_level": 0,
		"contracts": {"active": [], "progress": {}, "claimed": [], "refreshed_at": 0},
		"automation_off": [],
		"buddy": {"mood": 0.0, "grime": 0.0},
		"cosmetics": {"owned": [], "equipped": []},
		"stats": {"damage_dealt": 0.0, "pets": 0, "knockouts": 0},
	}

## Brings any older save up to SAVE_VERSION.
static func migrate(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	var from: int = int(out.get("version", 1))

	# A save from a newer build (Steam Cloud from another machine) must not be mangled.
	if from > SAVE_VERSION:
		push_warning("SaveSchema: save is from a newer version (%d > %d); loading as-is" % [from, SAVE_VERSION])
		return out

	while from < SAVE_VERSION:
		out = _apply_migration(from, out)
		from += 1
		out["version"] = from

	# Fill keys added since this save was written, without clobbering existing values.
	# This is what lets a purely additive schema change skip a hand-written migration.
	var defaults := new_save()
	for k in defaults:
		if not out.has(k):
			out[k] = defaults[k]
	return out

static func _apply_migration(from_version: int, d: Dictionary) -> Dictionary:
	match from_version:
		1:
			return _migrate_1_to_2(d)
		2:
			return _migrate_2_to_3(d)
		3:
			return _migrate_3_to_4(d)
		_:
			push_error("SaveSchema: no migration from version %d" % from_version)
			return d

## v3 -> v4: Ectoplasm becomes Dollars, and the prestige curve becomes Marrow.
##
## The first migration that is not additive, and the one the rule about writing a step per
## bump was waiting for (docs/decisions.md D31, D33).
##
## **A v3 player keeps exactly the multiplier they had.** Ectoplasm was worth +1% a point, so
## `marrow = ectoplasm x 0.01` leaves their income untouched to the decimal — they wake up
## with a differently-named stat and the same numbers, which is the only version of this that
## is not a nerf delivered by patch notes. They do *not* get Dollars for it: Ectoplasm bought
## nothing, so converting it into a spendable currency would hand out a windfall for having
## played before the change rather than after.
##
## `run_earnings` starts at zero rather than at their lifetime total. Marrow is scaled by the
## run, and crediting a v3 player's entire history as one unreset run would pay a first
## Reincarnation worth more than the rest of the game.
static func _migrate_3_to_4(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)

	var currencies: Dictionary = out.get("currencies", {})
	currencies["dollars"] = float(currencies.get("dollars", 0.0))
	out["currencies"] = currencies

	var prestige: Dictionary = out.get("prestige", {})
	var ectoplasm := float(prestige.get("ectoplasm", 0))
	prestige["marrow"] = float(prestige.get("marrow", ectoplasm * 0.01))
	prestige["run_earnings"] = float(prestige.get("run_earnings", 0.0))
	prestige.erase("ectoplasm")
	out["prestige"] = prestige
	return out

## v1 -> v2: the buddy's own state. M3 gave him a mood and a grime level, and both are the
## player's position in a loop rather than a derived number, so both persist.
##
## The fill-missing-keys pass at the end of migrate() would add this block on its own. It
## is written out anyway because the rule is a migration step per version bump (CLAUDE.md):
## the next schema change will not be purely additive, and a chain with a gap in it is
## worse than a chain with a trivial link.
static func _migrate_1_to_2(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if not out.has("buddy"):
		out["buddy"] = {"mood": 0.0, "grime": 0.0}
	return out

## v2 -> v3: mastery, automation and the contract board.
##
## `automation_off` lists the capstones the player has switched OFF, not the ones they have
## on. Absence therefore means running, which is what a save from before automation existed
## should mean — the inverse spelling would arrive from v2 with every future capstone
## disabled and no way for the player to know why.
static func _migrate_2_to_3(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if not out.has("automation_off"):
		out["automation_off"] = []
	var contracts: Dictionary = out.get("contracts", {})
	if not contracts.has("claimed"):
		contracts["claimed"] = []
	# A v2 board was never rolled, so force a fresh one on the next load rather than
	# leaving the player with an empty contract page until tomorrow.
	contracts["refreshed_at"] = 0
	out["contracts"] = contracts
	return out

## Seconds elapsed since the save was written, clamped to [0, cap].
## Negative deltas are real — clock changes, timezone shifts, cloud-sync skew — and must
## never pay out. See docs/economy.md.
static func offline_seconds(last_played_unix: int, now_unix: int, cap_seconds: float) -> float:
	return clampf(float(now_unix - last_played_unix), 0.0, cap_seconds)
