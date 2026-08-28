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

const SAVE_VERSION := 1

static func new_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at_unix": 0,
		"last_played_unix": 0,
		"playtime_sec": 0,
		"currencies": {"bones": 0.0, "hearts": 0.0},
		"lifetime": {"bones": 0.0, "hearts": 0.0},
		"prestige": {"ectoplasm": 0, "count": 0, "personality": "stoic"},
		"unlocks": [],
		"augments": {},
		"exclusive_choices": {},
		"mastery_xp": {},
		"mastery_pool": 0,
		"offline_cap_level": 0,
		"contracts": {"active": [], "progress": {}, "refreshed_at": 0},
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
		_:
			push_error("SaveSchema: no migration from version %d" % from_version)
			return d

## Seconds elapsed since the save was written, clamped to [0, cap].
## Negative deltas are real — clock changes, timezone shifts, cloud-sync skew — and must
## never pay out. See docs/economy.md.
static func offline_seconds(last_played_unix: int, now_unix: int, cap_seconds: float) -> float:
	return clampf(float(now_unix - last_played_unix), 0.0, cap_seconds)
