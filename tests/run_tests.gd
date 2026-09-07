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
const Mood := preload("res://Scripts/Buddy/mood_math.gd")
const Mastery := preload("res://Scripts/Progression/mastery_math.gd")
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
	_test_marrow_scales_with_the_run()
	_test_marrow_multiplies_income()

	_suite("mastery")
	_test_mastery_curve_is_superlinear()
	_test_rank_matches_the_threshold_it_inverts()
	_test_rank_is_bounded_and_safe()
	_test_rank_progress_spans_a_rank()
	_test_pool_checkpoints_compound()
	_test_pool_flat_bonus()
	_test_item_rank_bonus_is_a_step()
	_test_juice_tier_ladders()

	_suite("damage and payout")
	_test_impulse_below_threshold_is_free()
	_test_damage_scales_with_weapon()
	_test_contact_floor_by_source()
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
	_test_v1_fixture_migrates()
	_test_v2_fixture_migrates()
	_test_v3_fixture_migrates()

	_suite("mood")
	_test_mood_decays_toward_zero_without_overshooting()
	_test_mood_is_railed()
	_test_pushing_deeper_gets_harder()
	_test_swinging_the_other_way_is_full_strength()
	_test_kindness_mood_is_root_scaled()

	_suite("grime")
	_test_grime_penalty_is_bounded()
	_test_grime_only_ever_costs()

	_suite("play area ladder")
	_test_size_ladder_steps_and_clamps()
	_test_size_ladder_snaps_from_an_off_ladder_size()

	_suite("window layout")
	_test_fullscreen_uses_usable_rect()
	_test_play_area_snaps_to_corners()
	_test_play_area_clamped_to_screen()
	_test_play_area_has_a_floor_size()
	_test_oversized_window_stays_on_screen()
	_test_revalidation_detects_stale_rect()

	_suite("window layout across screens")
	_test_the_desktop_is_more_than_one_monitor()


	print("")
	print("==========================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# --- mastery ---------------------------------------------------------------

## rank_for_xp is the solved inverse of mastery_xp_for_rank — it has to be, because it runs
## inside the payout pipeline and a loop of pow() calls per payout is not affordable. Solved
## inverses are also exactly where the floating-point slack bites: at a threshold the player
## has *just* reached, which is the moment they are watching.
func _test_rank_matches_the_threshold_it_inverts() -> void:
	var base := 100.0
	for rank in [1, 2, 5, 10, 25, 50]:
		var exact: float = Math.mastery_xp_for_rank(base, rank)
		_check("exactly enough XP is rank %d" % rank, Mastery.rank_for_xp(base, exact) == rank)
		_check("a hair under is still rank %d" % (rank - 1),
			Mastery.rank_for_xp(base, exact - 0.001) == rank - 1)

func _test_rank_is_bounded_and_safe() -> void:
	_check("no XP is rank 0", Mastery.rank_for_xp(100.0, 0.0) == 0)
	_check("negative XP is rank 0", Mastery.rank_for_xp(100.0, -50.0) == 0)
	_check("a zero base does not divide by zero", Mastery.rank_for_xp(0.0, 500.0) == 0)
	# A corrupted save must not become an unbounded loop or an absurd multiplier.
	_check("absurd XP is capped", Mastery.rank_for_xp(100.0, 1e30) == Mastery.MAX_RANK)

func _test_rank_progress_spans_a_rank() -> void:
	var base := 100.0
	var at_rank: float = Math.mastery_xp_for_rank(base, 4)
	var next_rank: float = Math.mastery_xp_for_rank(base, 5)
	_check("progress is 0 at the rank floor", is_zero_approx(Mastery.rank_progress(base, at_rank)))
	_check("progress is near 1 just below the next",
		Mastery.rank_progress(base, next_rank - 0.001) > 0.99)
	_check("progress is in range halfway",
		Mastery.rank_progress(base, (at_rank + next_rank) * 0.5) > 0.4)

func _test_pool_checkpoints_compound() -> void:
	var thresholds: Array = [10, 25, 50]
	_check("no checkpoints below the first", Mastery.checkpoints_reached(9, thresholds) == 0)
	_check("exactly on a threshold counts", Mastery.checkpoints_reached(10, thresholds) == 1)
	_check("all three at the top", Mastery.checkpoints_reached(999, thresholds) == 3)
	_check("bonus is 1.0 with none", is_equal_approx(Mastery.pool_multiplier(0, thresholds, 1.02), 1.0))
	# Compounding, not summing — D11's one rule for every multiplier in the game.
	_check("three checkpoints compound", is_equal_approx(
		Mastery.pool_multiplier(50, thresholds, 1.02), pow(1.02, 3)))
	# The same rule has to work for a multiplier that goes down.
	_check("a reduction step compounds the same way", is_equal_approx(
		Mastery.pool_multiplier(50, thresholds, 0.95), pow(0.95, 3)))

func _test_pool_flat_bonus() -> void:
	var thresholds: Array = [10, 25, 50]
	_check("no slots with no checkpoints", Mastery.pool_flat_bonus(0, thresholds, 1) == 0)
	_check("one slot per checkpoint", Mastery.pool_flat_bonus(30, thresholds, 1) == 2)
	_check("scaled by the step", Mastery.pool_flat_bonus(999, thresholds, 2) == 6)

func _test_item_rank_bonus_is_a_step() -> void:
	_check("below the bonus rank is unmultiplied",
		is_equal_approx(Mastery.item_rank_multiplier(49, 50, 1.5), 1.0))
	_check("at the bonus rank it applies",
		is_equal_approx(Mastery.item_rank_multiplier(50, 50, 1.5), 1.5))
	_check("and does not keep growing above it",
		is_equal_approx(Mastery.item_rank_multiplier(90, 50, 1.5), 1.5))

# --- mood ------------------------------------------------------------------

func _test_mood_decays_toward_zero_without_overshooting() -> void:
	_check("despair decays upward", Mood.decay(-40.0, 2.0, 1.0) == -38.0)
	_check("bliss decays downward", Mood.decay(40.0, 2.0, 1.0) == 38.0)
	# Overshoot would flip a despairing buddy into a happy one on a long frame, handing the
	# player a different multiplier than the one they were maintaining.
	_check("a long frame lands on zero, not past it", Mood.decay(1.0, 2.0, 1.0) == 0.0)
	_check("and from the other side too", Mood.decay(-1.0, 2.0, 1.0) == 0.0)
	_check("zero stays zero", Mood.decay(0.0, 2.0, 1.0) == 0.0)

func _test_mood_is_railed() -> void:
	_check("cannot exceed bliss", Mood.nudge(99.0, 1000.0) <= Mood.MAX_MOOD)
	_check("cannot exceed despair", Mood.nudge(-99.0, -1000.0) >= Mood.MIN_MOOD)
	_check("clamp is symmetric", Mood.clamp_mood(500.0) == -Mood.clamp_mood(-500.0))

func _test_pushing_deeper_gets_harder() -> void:
	var from_neutral := Mood.nudge(0.0, 10.0)
	var from_high := Mood.nudge(80.0, 10.0) - 80.0
	_check("a nudge from neutral lands in full", is_equal_approx(from_neutral, 10.0))
	_check("the same nudge near the rail lands short", from_high < from_neutral)
	_check("but still moves him", from_high > 0.0)

func _test_swinging_the_other_way_is_full_strength() -> void:
	# The seesaw only works if crossing the middle is fast: the U-curve pays at both ends
	# and the whole rhythm is getting from one to the other.
	var recovery := Mood.nudge(-80.0, 10.0) - -80.0
	_check("a nudge back toward the other rail is full strength", is_equal_approx(recovery, 10.0))

func _test_kindness_mood_is_root_scaled() -> void:
	var pet := Mood.kindness_mood(1.0, 4.0)
	var pizza := Mood.kindness_mood(25.0, 4.0)
	_check("a pet is worth its full rate", is_equal_approx(pet, 4.0))
	_check("a 25x payout is worth 5 pets, not 25", is_equal_approx(pizza, pet * 5.0))
	_check("nothing is worth nothing", Mood.kindness_mood(0.0, 4.0) == 0.0)

# --- grime -----------------------------------------------------------------

func _test_grime_penalty_is_bounded() -> void:
	_check("clean is unpenalised", Mood.grime_penalty(0.0, 0.35) == 1.0)
	_check("filthy pays the full penalty", is_equal_approx(Mood.grime_penalty(1.0, 0.35), 0.65))
	_check("half grime is half the penalty", is_equal_approx(Mood.grime_penalty(0.5, 0.35), 0.825))

## No fail state (docs/game-design.md pillar 1): grime is a cost, never a wall. It must not
## be able to zero out damage income however filthy he gets or however the knob is tuned.
func _test_grime_only_ever_costs() -> void:
	_check("a penalty over 1.0 cannot pay negative", Mood.grime_penalty(1.0, 5.0) >= 0.0)
	_check("out-of-range grime is clamped", Mood.grime_penalty(9.0, 0.35) == Mood.grime_penalty(1.0, 0.35))
	_check("income is never zeroed at the documented tuning", Mood.grime_penalty(1.0, 0.35) > 0.0)

# --- play area ladder ------------------------------------------------------

func _test_size_ladder_steps_and_clamps() -> void:
	var ladder: Array[Vector2i] = WindowLayout.SIZE_LADDER
	_check("stepping up moves one rung",
		WindowLayout.step_size(ladder[2], 1) == ladder[3])
	_check("stepping down moves one rung",
		WindowLayout.step_size(ladder[2], -1) == ladder[1])
	_check("the smallest size cannot step down",
		WindowLayout.step_size(ladder[0], -1) == ladder[0])
	_check("the largest size cannot step up",
		WindowLayout.step_size(ladder[ladder.size() - 1], 1) == ladder[ladder.size() - 1])

## A saved size need not be on the ladder: it may come from an older build, or from a
## monitor that clamped it. Stepping from one must still land somewhere sensible.
func _test_size_ladder_snaps_from_an_off_ladder_size() -> void:
	var ladder: Array[Vector2i] = WindowLayout.SIZE_LADDER
	_check("an odd size steps from its nearest rung",
		WindowLayout.step_size(Vector2i(963, 641), 1) == ladder[4])
	_check("a huge size clamps to the top rung",
		WindowLayout.step_size(Vector2i(9999, 9999), 1) == ladder[ladder.size() - 1])

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

# --- prestige: Marrow ------------------------------------------------------

## Marrow scales with the **run**, with no threshold to cross (docs/decisions.md D33). The
## shape these assertions pin is: a bigger run always pays more, twice the run pays less than
## twice the Marrow, and nothing pays for a run that earned nothing.
func _test_marrow_scales_with_the_run() -> void:
	_check("a run that earned nothing pays nothing", is_zero_approx(Math.marrow_for_run(0.0)))
	_check("a negative run pays nothing", is_zero_approx(Math.marrow_for_run(-500.0)))
	_check("a run at the divisor is worth one Marrow",
		is_equal_approx(Math.marrow_for_run(1e7, 1e7), 1.0))
	# The exponent is below 1, so pushing a run further always pays and never pays
	# proportionally — which is what stops one enormous run beating several good ones and
	# emptying the loop of its loops.
	_check("four times the run is twice the Marrow, not four times",
		is_equal_approx(Math.marrow_for_run(4e7, 1e7), 2.0))
	_check("and two runs of one beat one run of two",
		Math.marrow_for_run(1e7, 1e7) * 2.0 > Math.marrow_for_run(2e7, 1e7))
	_check("the exponent is a balance number, not a baked-in root",
		is_equal_approx(Math.marrow_for_run(1e8, 1e7, 1.0), 10.0))

func _test_marrow_multiplies_income() -> void:
	_check("no Marrow is 1x", is_equal_approx(Math.marrow_multiplier(0.0), 1.0))
	_check("one Marrow is a doubling", is_equal_approx(Math.marrow_multiplier(1.0), 2.0))
	_check("it is additive and therefore unbounded",
		is_equal_approx(Math.marrow_multiplier(37.5), 38.5))
	_check("a negative total cannot make income vanish",
		is_equal_approx(Math.marrow_multiplier(-4.0), 1.0))

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

## The fall floor (docs/plan-movement-hitboxes.md). Who put the energy in decides which floor a
## contact has to clear: a swing for the harm side, a fall for the world and kind items.
func _test_contact_floor_by_source() -> void:
	_check("the harm side needs a swing", Math.contact_floor(true, 350.0, 1500.0) == 350.0)
	_check("the world and kind items need a fall", Math.contact_floor(false, 350.0, 1500.0) == 1500.0)
	_check("the fall floor is never below the swing floor", Math.contact_floor(false, 350.0, 100.0) == 350.0)
	_check("a self-landing is under the fall floor", Math.damage_from_impulse(703.0, Math.contact_floor(false, 350.0, 1500.0), 0.01, 1.0) == 0.0)
	_check("a drop from above his head is over it", Math.damage_from_impulse(1878.0, Math.contact_floor(false, 350.0, 1500.0), 0.01, 1.0) > 0.0)
	_check("a bat lay-on still pays at the swing floor", Math.damage_from_impulse(350.0, Math.contact_floor(true, 350.0, 1500.0), 0.01, 1.0) > 0.0)

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
	# The ladder the docs promised: 2 h, then 8, then 24, and a level past the ladder still grows.
	_check("the first step is eight hours", is_equal_approx(balance.offline_cap_seconds(1), 8.0 * 3600.0))
	_check("the second is a full day", is_equal_approx(balance.offline_cap_seconds(2), 24.0 * 3600.0))
	_check("and a level past the ladder still extends it",
		balance.offline_cap_seconds(3) > balance.offline_cap_seconds(2))
	_check("each step costs more Hearts than the last",
		balance.offline_cap_cost_hearts.size() == 2
		and balance.offline_cap_cost_hearts[1] > balance.offline_cap_cost_hearts[0])

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
	# A free window has no anchor, so this is only reached to invent a *first* home: a fresh
	# install, or a saved rect that no longer fits its monitor. It must not be the top-left,
	# which is where most people keep the thing they are actually working on — and which is
	# what this returned before the window became draggable (D49).
	var free_home: Vector2i = WindowLayout.corner_position(
		WindowLayout.Corner.FREE, size, usable, m)
	_check("a free window's first home is out of the way, not under the work",
		free_home == Vector2i(1920 - 480 - m, 1040 - 360 - m))

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

## The whole desktop, not one monitor (D52).
##
## Written against synthetic screen lists rather than the machine's real ones, so it says the
## same thing on a single-monitor CI box as on the developer's two — and so it can include the
## layout that actually breaks naive code: **a monitor to the LEFT of the primary**, whose
## usable rect has a negative x. Anything that assumes the desktop starts at (0,0) is correct
## on the developer's setup and wrong on a very common one.
func _test_the_desktop_is_more_than_one_monitor() -> void:
	var side_by_side: Array[Rect2i] = [
		Rect2i(0, 0, 1920, 1040),
		Rect2i(1920, -200, 2560, 1400),   # taller, mounted higher, to the right
	]
	var to_the_left: Array[Rect2i] = [
		Rect2i(-1920, 0, 1920, 1080),
		Rect2i(0, 0, 2560, 1400),
	]
	var size := Vector2i(1180, 760)

	_check("a window on the second monitor is left where it is",
		WindowLayout.clamp_to_desktop(Vector2i(2200, 100), size, side_by_side)
			== Vector2i(2200, 100))
	_check("a window straddling the seam is left alone rather than snapped to one side",
		WindowLayout.clamp_to_desktop(Vector2i(1500, 100), size, side_by_side)
			== Vector2i(1500, 100))
	_check("and a monitor left of primary works the same, negative coordinates and all",
		WindowLayout.clamp_to_desktop(Vector2i(-1800, 40), size, to_the_left)
			== Vector2i(-1800, 40))

	# Only a window that has escaped every screen is touched.
	var lost := WindowLayout.clamp_to_desktop(Vector2i(9000, 9000), size, side_by_side)
	_check("a window off every screen is pulled back onto one",
		WindowLayout.screen_for_rect(Rect2i(lost, size), side_by_side) >= 0)
	_check("with no screens to consult it is left exactly as asked",
		WindowLayout.clamp_to_desktop(Vector2i(-5000, -5000), size, [] as Array[Rect2i])
			== Vector2i(-5000, -5000))

	_check("the screen a window is on is the one it overlaps most, not the one holding its corner",
		WindowLayout.screen_for_rect(Rect2i(1700, 100, 1180, 760), side_by_side) == 1)
	_check("and nothing owns a window that touches no screen",
		WindowLayout.screen_for_rect(Rect2i(9000, 9000, 100, 100), side_by_side) == -1)

	_check("a rect on the second monitor is not stale",
		not WindowLayout.needs_revalidation_across(Rect2i(2200, 100, 1180, 760), side_by_side))
	_check("a rect off every monitor is stale",
		WindowLayout.needs_revalidation_across(Rect2i(9000, 9000, 1180, 760), side_by_side))
	_check("an empty rect is stale whatever the screens say",
		WindowLayout.needs_revalidation_across(Rect2i(), side_by_side))

	# And the reason all of the above exists: target_rect must not re-home a free window.
	var free := WindowLayout.target_rect(WindowLayout.Mode.PLAY_AREA, side_by_side[0], size,
		WindowLayout.Corner.FREE, Vector2i(2200, 100), WindowLayout.DEFAULT_MARGIN,
		side_by_side)
	_check("a free window keeps the monitor it was dragged to across an apply",
		free.position == Vector2i(2200, 100))
	# Corners are still per-monitor. Snapping is what they are for.
	var snapped := WindowLayout.target_rect(WindowLayout.Mode.PLAY_AREA, side_by_side[0], size,
		WindowLayout.Corner.TOP_LEFT, Vector2i(2200, 100), WindowLayout.DEFAULT_MARGIN,
		side_by_side)
	_check("but a corner still snaps to its own monitor",
		side_by_side[0].encloses(snapped))

func _test_revalidation_detects_stale_rect() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)
	_check("empty rect needs revalidation", WindowLayout.needs_revalidation(Rect2i(), usable))
	_check("off-screen rect needs revalidation", WindowLayout.needs_revalidation(Rect2i(3000, 0, 480, 360), usable))
	_check("contained rect is fine", not WindowLayout.needs_revalidation(Rect2i(10, 10, 480, 360), usable))

## The real thing the migration chain exists for: a save file written by the shipped M2
## build, loaded by this one. A fixture rather than a synthesised dictionary, because what
## breaks a migration is the shape of a file someone actually has.
func _test_v1_fixture_migrates() -> void:
	var f := FileAccess.open("res://tests/fixtures/save_v1.json", FileAccess.READ)
	if f == null:
		_check("v1 fixture is present", false)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_check("v1 fixture is valid JSON", false)
		return

	var old_save: Dictionary = parsed
	var out: Dictionary = Schema.migrate(old_save)
	_check("fixture arrives at the current version", int(out["version"]) == Schema.SAVE_VERSION)
	_check("the buddy block was added", out.has("buddy"))
	_check("a fresh buddy starts neutral", float(out["buddy"]["mood"]) == 0.0)
	_check("and clean", float(out["buddy"]["grime"]) == 0.0)

	# Nothing the player earned may be lost on the way through.
	_check("bones survived", is_equal_approx(float(out["currencies"]["bones"]), 1875.5))
	_check("lifetime survived", is_equal_approx(float(out["lifetime"]["bones"]), 4310.25))
	_check("unlocks survived", (out["unlocks"] as Array).size() == 5)
	_check("augment levels survived", int(out["augments"]["bat_damage"]) == 3)
	_check("mastery xp survived", is_equal_approx(float(out["mastery_xp"]["baseball_bat"]), 640.0))
	_check("knockout count survived", int(out["stats"]["knockouts"]) == 11)
	_check("migrating did not mutate the fixture", int(old_save["version"]) == 1)

## The v2 fixture is a save from the middle of M3 — mood and grime recorded, but no
## mastery pool, no automation and no contract board. It has to arrive at v3 with the
## automation defaulting to *running*, which is the one thing the migration could plausibly
## get backwards.
func _test_v2_fixture_migrates() -> void:
	var f := FileAccess.open("res://tests/fixtures/save_v2.json", FileAccess.READ)
	if f == null:
		_check("v2 fixture is present", false)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_check("v2 fixture is valid JSON", false)
		return

	var out: Dictionary = Schema.migrate(parsed)
	_check("v2 fixture reaches the current version", int(out["version"]) == Schema.SAVE_VERSION)
	_check("automation_off exists", out.has("automation_off"))
	# Absence means running. The inverse spelling would arrive with every future capstone
	# switched off and no way for the player to know why.
	_check("and is empty, so nothing arrives disabled", (out["automation_off"] as Array).is_empty())
	_check("the contract board gained a claimed list", (out["contracts"] as Dictionary).has("claimed"))
	_check("and is marked for a fresh roll", int(out["contracts"]["refreshed_at"]) == 0)

	# The M3 state a v2 save already had must survive untouched.
	_check("his mood survived", is_equal_approx(float(out["buddy"]["mood"]), -37.5))
	_check("his grime survived", is_equal_approx(float(out["buddy"]["grime"]), 0.42))
	_check("mastery xp survived", is_equal_approx(float(out["mastery_xp"]["baseball_bat"]), 5200.0))
	_check("hearts survived", is_equal_approx(float(out["currencies"]["hearts"]), 312.5))
	_check("nine unlocks survived", (out["unlocks"] as Array).size() == 9)

## The v3 fixture is a save from the end of M3.5-A: three Reincarnations under the old
## Ectoplasm curve, a chosen exclusive branch, a switched-off capstone, and a contract board
## mid-week. It has to arrive at v4 with the same income multiplier it had — the first
## non-additive migration in the project, and the one that could most easily rob somebody.
func _test_v3_fixture_migrates() -> void:
	var f := FileAccess.open("res://tests/fixtures/save_v3.json", FileAccess.READ)
	if f == null:
		_check("v3 fixture is present", false)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_check("v3 fixture is valid JSON", false)
		return

	var out: Dictionary = Schema.migrate(parsed)
	_check("v3 fixture reaches the current version", int(out["version"]) == Schema.SAVE_VERSION)

	# Three Ectoplasm was +3% income. Three hundredths of Marrow is +3% income. The player
	# wakes up with a differently-named stat and the same numbers, which is the only version
	# of this change that is not a nerf delivered by patch notes.
	_check("Ectoplasm became exactly the Marrow it was worth",
		is_equal_approx(float(out["prestige"]["marrow"]), 0.03))
	_check("and the word is gone", not (out["prestige"] as Dictionary).has("ectoplasm"))
	_check("the reset count survived", int(out["prestige"]["count"]) == 3)
	_check("Dollars start at zero, not at a windfall",
		is_zero_approx(float(out["currencies"]["dollars"])))
	# Marrow is scaled by the *run*, so crediting a whole history as one unreset run would
	# pay a first Reincarnation worth more than the rest of the game.
	_check("and the run starts fresh rather than claiming a whole history",
		is_zero_approx(float(out["prestige"]["run_earnings"])))

	# Everything a v3 player owned is still theirs.
	_check("his personality survived", String(out["prestige"]["personality"]) == "goth")
	_check("bones survived", is_equal_approx(float(out["currencies"]["bones"]), 184320.5))
	_check("the exclusive branch survived",
		String(out["exclusive_choices"]["baseball_bat/flavour"]) == "bat_slugger")
	_check("the switched-off capstone stayed off",
		(out["automation_off"] as Array).has("boombox_playlist"))
	_check("sixteen unlocks survived", (out["unlocks"] as Array).size() == 16)
	_check("the mastery pool survived", int(out["mastery_pool"]) == 31)

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

## The juice tier (D41) is presentation only, and either ladder reaches a tier on its own:
## the ranks the economy already treats as beats, or a first / committed / finished build.
func _test_juice_tier_ladders() -> void:
	_check("nothing is tier 0", Mastery.juice_tier(0, 0) == 0)
	_check("a first augment is tier 1", Mastery.juice_tier(0, 1) == 1)
	_check("rank 3 is tier 1", Mastery.juice_tier(3, 0) == 1)
	_check("rank 9 with five levels is still tier 1", Mastery.juice_tier(9, 5) == 1)
	_check("rank 10 is tier 2", Mastery.juice_tier(10, 0) == 2)
	_check("ten levels is tier 2", Mastery.juice_tier(0, 10) == 2)
	_check("rank 25 is tier 3", Mastery.juice_tier(25, 0) == 3)
	_check("twenty levels is tier 3", Mastery.juice_tier(0, 20) == 3)
	# The half that D53 fixed. The ladder used to stop at rank 25 — 10.9% of the XP needed to
	# cap an item, and about ten minutes of play — so the remaining 89% of the grind changed
	# nothing at all. These two assertions are the whole point: there is something left to
	# earn after the automation capstone, and the top look is on the cap itself.
	_check("rank 50 is tier 4, so the payout bonus is visible too", Mastery.juice_tier(50, 0) == 4)
	_check("and the cap is the top tier", Mastery.juice_tier(Mastery.MAX_RANK, 0) == Mastery.JUICE_TIERS)
	_check("a finished augment tree reaches the top on its own",
		Mastery.juice_tier(0, 55) == Mastery.JUICE_TIERS)
	_check("nothing exceeds the top, however far past the ladder it goes",
		Mastery.juice_tier(9999, 9999) == Mastery.JUICE_TIERS)
	# Both ramps are indexed by tier and read with a clamp, but they must still be long
	# enough — an array a rung short is an out-of-range on every item spawn in the game.
	_check("the glow ramp covers every tier",
		BaseDraggable.GLOW_STRENGTH.size() >= Mastery.JUICE_TIERS + 1)
	_check("and so does the aura ramp",
		BaseDraggable.AURA_AMOUNT.size() >= Mastery.JUICE_TIERS + 1)
	_check("the two ladders have one entry per tier",
		Mastery.JUICE_RANKS.size() == Mastery.JUICE_TIERS
		and Mastery.JUICE_LEVELS.size() == Mastery.JUICE_TIERS)
