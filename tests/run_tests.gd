extends SceneTree

## Headless test runner. No framework — these are pure functions and plain asserts.
##
##   Godot --headless --path <project> -s tests/run_tests.gd
##
## Exits non-zero if anything fails, so it works as a pre-commit gate.
## Run it before any commit touching Economy, Progression or SaveManager.
##
## Only dependency-free scripts can be tested here: autoload singletons (EventBus and
## friends) are NOT registered under `-s`, so anything reaching for them fails to compile.
## That constraint is why SaveSchema and EconomyMath are separate from their autoloads.

const Schema := preload("res://Scripts/Save/save_schema.gd")
const Math := preload("res://Scripts/Economy/economy_math.gd")

var _passed := 0
var _failed := 0
var _current_suite := ""

func _initialize() -> void:
	print("")
	print("Bonehead Friend — test run")
	print("==========================")

	_suite("save schema")
	_test_new_save_shape()
	_test_migrate_is_identity_at_current_version()
	_test_migrate_fills_missing_keys()
	_test_migrate_preserves_existing_values()
	_test_migrate_tolerates_future_version()
	_test_migrate_does_not_mutate_input()
	_test_json_round_trip()

	_suite("offline earnings")
	_test_offline_clamps_negative()
	_test_offline_clamps_to_cap()
	_test_offline_normal_case()
	_test_offline_efficiency()

	_suite("augment costs")
	_test_augment_cost_curve()
	_test_bulk_cost_matches_sum()
	_test_max_affordable_inverse()
	_test_max_affordable_edges()

	_suite("prestige")
	_test_prestige_cube_root()
	_test_prestige_gain_never_negative()
	_test_prestige_multiplier()

	_suite("mastery")
	_test_mastery_curve_is_superlinear()

	print("")
	print("==========================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# --- save schema -----------------------------------------------------------

func _test_new_save_shape() -> void:
	var s: Dictionary = Schema.new_save()
	_check("new_save has version", s.get("version") == Schema.SAVE_VERSION)
	for key in ["currencies", "lifetime", "prestige", "unlocks", "augments",
			"mastery_xp", "contracts", "cosmetics", "stats"]:
		_check("new_save has '%s'" % key, s.has(key))
	_check("starts with zero bones", float(s["currencies"]["bones"]) == 0.0)
	_check("starts with zero hearts", float(s["currencies"]["hearts"]) == 0.0)

func _test_migrate_is_identity_at_current_version() -> void:
	var s: Dictionary = Schema.new_save()
	var out: Dictionary = Schema.migrate(s)
	_check("migrate keeps current version", out["version"] == Schema.SAVE_VERSION)
	_check("migrate preserves key count", out.size() == s.size())

func _test_migrate_fills_missing_keys() -> void:
	# A save written before a key existed must gain it rather than crashing a reader.
	var partial := {"version": 1, "currencies": {"bones": 5.0, "hearts": 2.0}}
	var out: Dictionary = Schema.migrate(partial)
	for key in ["stats", "contracts", "prestige", "cosmetics", "mastery_xp"]:
		_check("missing '%s' filled" % key, out.has(key))

func _test_migrate_preserves_existing_values() -> void:
	var partial := {"version": 1, "currencies": {"bones": 1234.5, "hearts": 9.0}}
	var out: Dictionary = Schema.migrate(partial)
	_check("existing bones preserved", float(out["currencies"]["bones"]) == 1234.5)
	_check("existing hearts preserved", float(out["currencies"]["hearts"]) == 9.0)

func _test_migrate_tolerates_future_version() -> void:
	# A save from a newer build (Steam Cloud from another machine) must not be mangled.
	var future := {"version": 999, "currencies": {"bones": 7.0}}
	var out: Dictionary = Schema.migrate(future)
	_check("future save left intact", out["version"] == 999)
	_check("future save keeps data", float(out["currencies"]["bones"]) == 7.0)

func _test_migrate_does_not_mutate_input() -> void:
	# migrate() must be safe to call on the in-memory save without corrupting it.
	var original := {"version": 1, "currencies": {"bones": 3.0, "hearts": 0.0}}
	var _out: Dictionary = Schema.migrate(original)
	_check("input dictionary untouched", original.size() == 2)

func _test_json_round_trip() -> void:
	var s: Dictionary = Schema.new_save()
	s["currencies"]["bones"] = 4242.0
	var parsed = JSON.parse_string(JSON.stringify(s))
	_check("round trip is a dictionary", typeof(parsed) == TYPE_DICTIONARY)
	_check("round trip preserves value", float(parsed["currencies"]["bones"]) == 4242.0)

# --- offline earnings ------------------------------------------------------

func _test_offline_clamps_negative() -> void:
	# Clock changes, timezone shifts and cloud-sync skew all produce negative deltas.
	# Paying out on those is both an exploit and a bug.
	_check("negative elapsed clamps to zero", Schema.offline_seconds(2000, 1000, 7200.0) == 0.0)

func _test_offline_clamps_to_cap() -> void:
	_check("elapsed clamps to cap", Schema.offline_seconds(0, 100000, 7200.0) == 7200.0)

func _test_offline_normal_case() -> void:
	_check("normal elapsed passes through", Schema.offline_seconds(1000, 4600, 7200.0) == 3600.0)

func _test_offline_efficiency() -> void:
	_check("offline pays at efficiency", is_equal_approx(Math.offline_earnings(10.0, 100.0, 0.5), 500.0))
	_check("negative rate pays nothing", Math.offline_earnings(-10.0, 100.0, 0.5) == 0.0)
	_check("efficiency clamps above 1", is_equal_approx(Math.offline_earnings(10.0, 10.0, 5.0), 100.0))

# --- augment costs ---------------------------------------------------------

func _test_augment_cost_curve() -> void:
	_check("level 0 costs base", is_equal_approx(Math.augment_cost(100.0, 1.10, 0), 100.0))
	_check("level 1 costs base*r", is_equal_approx(Math.augment_cost(100.0, 1.10, 1), 110.0))

func _test_bulk_cost_matches_sum() -> void:
	# The classic silent bug: a "Buy x10" button that quietly overcharges.
	var base := 100.0
	var growth := 1.10
	var owned := 3
	var count := 10
	var summed := 0.0
	for i in count:
		summed += Math.augment_cost(base, growth, owned + i)
	_check("bulk closed form == naive sum", abs(summed - Math.bulk_cost(base, growth, owned, count)) < 0.001)
	_check("buying zero costs nothing", Math.bulk_cost(base, growth, owned, 0) == 0.0)

func _test_max_affordable_inverse() -> void:
	var base := 100.0
	var growth := 1.10
	# Exactly enough for 5 levels. Without the epsilon in max_affordable this returns 4,
	# and the player watches their "Buy Max" button refuse money it should accept.
	var cash: float = Math.bulk_cost(base, growth, 0, 5)
	_check("max affordable matches bulk cost exactly", Math.max_affordable(base, growth, 0, cash) == 5)
	_check("slightly less buys fewer", Math.max_affordable(base, growth, 0, cash - 1.0) == 4)

func _test_max_affordable_edges() -> void:
	_check("no cash buys nothing", Math.max_affordable(100.0, 1.10, 0, 0.0) == 0)
	_check("negative cash buys nothing", Math.max_affordable(100.0, 1.10, 0, -50.0) == 0)
	_check("cash below first level buys nothing", Math.max_affordable(100.0, 1.10, 0, 99.0) == 0)
	_check("linear growth handled", Math.max_affordable(10.0, 1.0, 0, 55.0) == 5)

# --- prestige --------------------------------------------------------------

func _test_prestige_cube_root() -> void:
	# Doubling prestige should take ~8x the run.
	_check("below threshold yields nothing", Math.ectoplasm_for_lifetime(1e11) == 0)
	_check("1e12 yields 1", Math.ectoplasm_for_lifetime(1e12) == 1)
	_check("8e12 yields 2 (8x to double)", Math.ectoplasm_for_lifetime(8e12) == 2)
	# Exact cube: pow(64, 1/3) lands at 3.9999999999999996 in floating point.
	_check("64e12 yields 4 (exact cube)", Math.ectoplasm_for_lifetime(64e12) == 4)
	_check("zero lifetime yields nothing", Math.ectoplasm_for_lifetime(0.0) == 0)

func _test_prestige_gain_never_negative() -> void:
	_check("gain over held amount", Math.prestige_gain(8e12, 1) == 1)
	_check("no gain when already ahead", Math.prestige_gain(1e12, 5) == 0)

func _test_prestige_multiplier() -> void:
	_check("zero ectoplasm is 1x", is_equal_approx(Math.prestige_multiplier(0), 1.0))
	_check("100 ectoplasm is 2x", is_equal_approx(Math.prestige_multiplier(100), 2.0))

# --- mastery ---------------------------------------------------------------

func _test_mastery_curve_is_superlinear() -> void:
	var r10: float = Math.mastery_xp_for_rank(100.0, 10)
	var r20: float = Math.mastery_xp_for_rank(100.0, 20)
	_check("rank 0 needs nothing", Math.mastery_xp_for_rank(100.0, 0) == 0.0)
	_check("doubling rank more than doubles xp", r20 > r10 * 2.0)

# --- harness ---------------------------------------------------------------

func _suite(suite_name: String) -> void:
	_current_suite = suite_name
	print("")
	print("  %s" % suite_name)

func _check(what: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("    ok   %s" % what)
	else:
		_failed += 1
		printerr("    FAIL %s  [%s]" % [what, _current_suite])
