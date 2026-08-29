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
const Aug := preload("res://Scripts/Progression/augment_math.gd")
const Balance := preload("res://Scripts/Data/balance_data.gd")
const Item := preload("res://Scripts/Data/item_data.gd")
const Augment := preload("res://Scripts/Data/augment_node.gd")
const Blast := preload("res://Scripts/Combat/explosion_util.gd")
# Referenced by global class name rather than a preload alias: an enum reached through a
# preloaded script is treated as a DIFFERENT type from the same enum on the class itself,
# so `Alias.Corner.TOP_LEFT` will not satisfy a `Corner` parameter.

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

	_suite("damage and payout")
	_test_impulse_below_threshold_is_free()
	_test_damage_scales_with_weapon()
	_test_payout_applies_every_multiplier()
	_test_knockout_bonus_is_soft_capped()
	_test_kindness_combo_ceiling()

	_suite("blast falloff")
	_test_blast_radius_follows_scale()
	_test_blast_strength_falls_off()
	_test_blast_reaches_its_visible_edge()

	_suite("augment stacking")
	_test_augment_levels_compound()
	_test_reduction_effects_use_the_same_rule()
	_test_purchasable_levels_respects_max()
	_test_purchasable_levels_respects_wallet()

	_suite("content resources")
	_test_free_items_are_starters()
	_test_currency_key_matches_economy()
	_test_validation_rejects_broken_content()
	_test_mood_curve_is_a_u()
	_test_offline_cap_upgrades()

	_suite("save round trip")
	_test_stringname_keys_survive_json()

	_suite("window layout")
	_test_fullscreen_uses_usable_rect()
	_test_play_area_snaps_to_corners()
	_test_play_area_clamped_to_screen()
	_test_play_area_has_a_floor_size()
	_test_oversized_window_stays_on_screen()
	_test_revalidation_detects_stale_rect()


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

# --- damage and payout -----------------------------------------------------
# Damage is measured on the receiver from contact impulses (docs/decisions.md D7). These
# guard the two ends of that: the floor that stops a resting weapon farming Bones, and
# the multiplier chain a payout passes through.

func _test_impulse_below_threshold_is_free() -> void:
	# A body lying against him produces a small impulse every single physics tick. If this
	# floor ever slips below that, an idle desktop prints money overnight.
	_check("below the floor deals nothing", Math.damage_from_impulse(100.0, 350.0, 0.01, 1.0) == 0.0)
	_check("at the floor deals damage", Math.damage_from_impulse(350.0, 350.0, 0.01, 1.0) > 0.0)

func _test_damage_scales_with_weapon() -> void:
	var plain: float = Math.damage_from_impulse(4000.0, 350.0, 0.01, 1.0)
	var heavy: float = Math.damage_from_impulse(4000.0, 350.0, 0.01, 1.35)
	_check("weapon multiplier applies", is_equal_approx(heavy, plain * 1.35))
	_check("negative multiplier cannot pay", Math.damage_from_impulse(4000.0, 350.0, 0.01, -2.0) == 0.0)

func _test_payout_applies_every_multiplier() -> void:
	# base 10, x0.6 mood, x2 augments, x1.1 mastery, x1.5 prestige
	var out: float = Math.payout_for(10.0, 0.6, 2.0, 1.1, 1.5)
	_check("whole chain applied", is_equal_approx(out, 10.0 * 0.6 * 2.0 * 1.1 * 1.5))
	_check("negative base pays nothing", Math.payout_for(-5.0, 1.0, 1.0, 1.0, 1.0) == 0.0)

func _test_knockout_bonus_is_soft_capped() -> void:
	# Doubling the damage in a round must pay LESS than double, or knockout farming
	# becomes the only strategy worth playing.
	var single: float = Math.knockout_bonus(400.0, 1.0, 0.9)
	var double: float = Math.knockout_bonus(800.0, 1.0, 0.9)
	_check("more damage pays more", double > single)
	_check("but less than proportionally", double < single * 2.0)
	_check("no damage pays nothing", Math.knockout_bonus(0.0, 1.0, 0.9) == 0.0)

func _test_kindness_combo_ceiling() -> void:
	_check("first event has no combo", is_equal_approx(Math.kindness_combo(0, 0.15, 3.0), 1.0))
	_check("repeats compound", is_equal_approx(Math.kindness_combo(4, 0.15, 3.0), 1.6))
	_check("combo is capped", is_equal_approx(Math.kindness_combo(100, 0.15, 3.0), 3.0))

# --- blast falloff ---------------------------------------------------------
# The scale factor is the whole reason these exist. get_overlapping_bodies() reports what
# the SCALED area covers; computing falloff against the raw shape radius picks bodies up
# and then hands them exactly zero impulse. The prototype missile had a root scale of 3
# and a 166 px shape, so two thirds of its visible blast did nothing at all.

func _test_blast_radius_follows_scale() -> void:
	_check("unscaled radius passes through", is_equal_approx(Blast.blast_radius(300.0, 1.0), 300.0))
	_check("scale multiplies the reach", is_equal_approx(Blast.blast_radius(166.0, 3.0), 498.0))
	_check("negative scale is still a reach", is_equal_approx(Blast.blast_radius(100.0, -2.0), 200.0))
	_check("zero scale cannot divide by zero later", Blast.blast_radius(100.0, 0.0) > 0.0)

func _test_blast_strength_falls_off() -> void:
	_check("centre takes the full force", is_equal_approx(Blast.blast_strength(0.0, 300.0, 10000.0), 10000.0))
	_check("the rim takes nothing", is_equal_approx(Blast.blast_strength(300.0, 300.0, 10000.0), 0.0))
	_check("beyond the rim takes nothing", is_equal_approx(Blast.blast_strength(900.0, 300.0, 10000.0), 0.0))
	# Squared, not linear: half way out keeps a quarter, so near-misses still hurt.
	_check("falloff is quadratic", is_equal_approx(Blast.blast_strength(150.0, 300.0, 10000.0), 2500.0))
	_check("a radiusless blast does nothing", Blast.blast_strength(10.0, 0.0, 10000.0) == 0.0)

func _test_blast_reaches_its_visible_edge() -> void:
	# The regression itself: a 166 px shape drawn at scale 3 must still hurt something at
	# 400 px, which is inside what the player can see the blast cover.
	var radius: float = Blast.blast_radius(166.0, 3.0)
	_check("a scaled blast hurts at 400px", Blast.blast_strength(400.0, radius, 10000.0) > 0.0)
	# And the bug's signature: computed against the raw radius, that same body gets zero.
	_check("against the raw radius it would have been inert",
		Blast.blast_strength(400.0, 166.0, 10000.0) == 0.0)

# --- augment stacking ------------------------------------------------------

func _test_augment_levels_compound() -> void:
	_check("zero levels is neutral", is_equal_approx(Aug.node_modifier(1.15, 0), 1.0))
	_check("three levels compound", is_equal_approx(Aug.node_modifier(1.15, 3), pow(1.15, 3)))
	_check("nodes multiply together",
		is_equal_approx(Aug.total_modifier([[1.15, 2], [1.10, 3]]), pow(1.15, 2) * pow(1.10, 3)))
	_check("no nodes is neutral", is_equal_approx(Aug.total_modifier([]), 1.0))

func _test_reduction_effects_use_the_same_rule() -> void:
	# per_level is a multiplier, not an addend, so a cooldown node needs no special case.
	var cooldown: float = Aug.node_modifier(0.95, 5)
	_check("reductions shrink", cooldown < 1.0)
	_check("reductions compound too", is_equal_approx(cooldown, pow(0.95, 5)))

func _test_purchasable_levels_respects_max() -> void:
	# Cash for a hundred levels, but the node only has ten. A "Buy Max" that offers a
	# level which does not exist is a refund request.
	_check("clamped to remaining levels", Aug.purchasable_levels(10.0, 1.10, 8, 10, 1e9) == 2)
	_check("maxed node offers nothing", Aug.purchasable_levels(10.0, 1.10, 10, 10, 1e9) == 0)
	_check("explicit count is honoured", Aug.purchasable_levels(10.0, 1.10, 0, 10, 1e9, 3) == 3)

func _test_purchasable_levels_respects_wallet() -> void:
	var exact: float = Math.bulk_cost(100.0, 1.10, 0, 4)
	_check("buys exactly what is affordable", Aug.purchasable_levels(100.0, 1.10, 0, 10, exact) == 4)
	_check("broke buys nothing", Aug.purchasable_levels(100.0, 1.10, 0, 10, 0.0) == 0)

# --- content resources -----------------------------------------------------
# ItemData and AugmentNode are plain Resources with no engine coupling, so the rules the
# whole content pipeline leans on can be checked here rather than discovered at boot.

func _test_free_items_are_starters() -> void:
	var free: Resource = Item.new()
	free.cost = 0
	var paid: Resource = Item.new()
	paid.cost = 900
	_check("cost 0 is a starter", free.is_starter())
	_check("priced items are not", not paid.is_starter())

func _test_currency_key_matches_economy() -> void:
	# These strings are dictionary keys in Economy and in the save file. A typo here is a
	# silently unspendable currency.
	var bones: Resource = Item.new()
	bones.currency = Item.CURRENCY_BONES
	var hearts: Resource = Item.new()
	hearts.currency = Item.CURRENCY_HEARTS
	_check("bones key", bones.currency_id() == &"bones")
	_check("hearts key", hearts.currency_id() == &"hearts")

func _test_validation_rejects_broken_content() -> void:
	var nameless: Resource = Item.new()
	_check("item without an id is rejected", not nameless.validation_error().is_empty())

	var node: Resource = Augment.new()
	node.id = &"test"
	_check("augment without an effect_key is rejected", not node.validation_error().is_empty())
	node.effect_key = &"damage_mult"
	_check("complete augment validates", node.validation_error().is_empty())
	node.max_levels = 0
	_check("zero max_levels is rejected", not node.validation_error().is_empty())

func _test_mood_curve_is_a_u() -> void:
	# The U is the mechanic: neutral must be the WORST place to sit, or optimal play stops
	# oscillating and the whole cruelty/kindness rhythm collapses into a flat ramp.
	var balance: Resource = Balance.new()
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 2.0
	curve.add_point(Vector2(0.0, 2.0))
	curve.add_point(Vector2(0.5, 0.6))
	curve.add_point(Vector2(1.0, 2.0))
	balance.mood_curve = curve

	var despair: float = balance.sample_mood_curve(-100.0)
	var neutral: float = balance.sample_mood_curve(0.0)
	var bliss: float = balance.sample_mood_curve(100.0)
	_check("despair pays well", despair > 1.5)
	_check("bliss pays well", bliss > 1.5)
	_check("neutral is the worst", neutral < despair and neutral < bliss)
	_check("out-of-range mood is clamped, not extrapolated",
		is_equal_approx(balance.sample_mood_curve(-500.0), despair))

func _test_offline_cap_upgrades() -> void:
	var balance: Resource = Balance.new()
	_check("base cap is 2 hours", is_equal_approx(balance.offline_cap_seconds(0), 7200.0))
	_check("cap upgrades extend it", balance.offline_cap_seconds(1) > balance.offline_cap_seconds(0))
	_check("negative levels cannot shrink it", is_equal_approx(balance.offline_cap_seconds(-3), 7200.0))

# --- save round trip -------------------------------------------------------

func _test_stringname_keys_survive_json() -> void:
	# StringName dictionary keys come back from JSON as plain Strings, and a StringName
	# lookup then misses every one of them — the player loses every augment they bought.
	# Progression converts on the way out; this is the reason why.
	var raw := {StringName("bat_damage"): 4}
	var parsed = JSON.parse_string(JSON.stringify(raw))
	_check("json keys come back as strings", parsed.has("bat_damage"))

	var converted := {}
	for key in parsed:
		converted[StringName(key)] = int(parsed[key])
	_check("converted back to StringName", converted.get(&"bat_damage", 0) == 4)

# --- window layout ---------------------------------------------------------
# The overlay lives on someone else's desktop; getting these wrong puts the window
# off-screen or under the taskbar, which the genre's reviews are full of.

func _test_fullscreen_uses_usable_rect() -> void:
	# Usable rect excludes the taskbar — that is what makes the taskbar the floor.
	var usable := Rect2i(0, 0, 1920, 1040)
	var r: Rect2i = WindowLayout.target_rect(WindowLayout.Mode.FULLSCREEN_OVERLAY, usable, Vector2i(480, 360), WindowLayout.Corner.FREE, Vector2i.ZERO)
	_check("fullscreen fills usable rect", r == usable)

func _test_play_area_snaps_to_corners() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)
	var size := Vector2i(480, 360)
	var m: int = WindowLayout.DEFAULT_MARGIN
	var tl: Rect2i = WindowLayout.target_rect(WindowLayout.Mode.PLAY_AREA, usable, size, WindowLayout.Corner.TOP_LEFT, Vector2i.ZERO)
	var br: Rect2i = WindowLayout.target_rect(WindowLayout.Mode.PLAY_AREA, usable, size, WindowLayout.Corner.BOTTOM_RIGHT, Vector2i.ZERO)
	_check("top-left snaps with margin", tl.position == Vector2i(m, m))
	_check("bottom-right snaps with margin", br.position == Vector2i(1920 - 480 - m, 1040 - 360 - m))
	_check("corner snap keeps size", br.size == size)

func _test_play_area_clamped_to_screen() -> void:
	# A monitor offset matters: secondary screens do not start at 0,0.
	var usable := Rect2i(1920, 0, 1920, 1040)
	var r: Rect2i = WindowLayout.target_rect(WindowLayout.Mode.PLAY_AREA, usable, Vector2i(480, 360), WindowLayout.Corner.FREE, Vector2i(9999, 9999))
	_check("free position clamped onto monitor", usable.encloses(r))

func _test_play_area_has_a_floor_size() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)
	var r: Rect2i = WindowLayout.target_rect(WindowLayout.Mode.PLAY_AREA, usable, Vector2i(10, 10), WindowLayout.Corner.TOP_LEFT, Vector2i.ZERO)
	_check("tiny size raised to minimum", r.size == WindowLayout.MIN_PLAY_SIZE)

func _test_oversized_window_stays_on_screen() -> void:
	# Window bigger than the monitor: naive clamping would push it off the top-left.
	var usable := Rect2i(0, 0, 800, 600)
	var pos: Vector2i = WindowLayout.clamp_position(Vector2i(500, 500), Vector2i(1200, 900), usable)
	_check("oversized window pinned to origin", pos == Vector2i(0, 0))

func _test_revalidation_detects_stale_rect() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)
	_check("empty rect needs revalidation", WindowLayout.needs_revalidation(Rect2i(), usable))
	_check("off-screen rect needs revalidation", WindowLayout.needs_revalidation(Rect2i(3000, 0, 480, 360), usable))
	_check("contained rect is fine", not WindowLayout.needs_revalidation(Rect2i(10, 10, 480, 360), usable))

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
