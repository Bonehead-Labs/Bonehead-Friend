class_name MasteryMath
extends RefCounted

## Mastery ranks and the shared pool, as pure functions.
##
## Dependency-free so the headless test runner can reach them — the same split as
## SaveSchema/SaveManager and EconomyMath/Economy.
##
## Mastery answers the genre's oldest question: *why would I ever use the shotgun once I own
## the rocket launcher?* Per-item ranks make an old toy keep improving, and the shared pool
## makes using a *variety* of toys worth more than grinding one — without it players
## correctly conclude that spreading mastery is wasted mastery (docs/economy.md).

## Preloaded rather than referenced by global class name: global names resolve through a
## cache only the editor regenerates, and a pure module the test runner imports must not
## depend on that cache being warm.
const Econ := preload("res://Scripts/Economy/economy_math.gd")

## Ranks stop here. A cap keeps rank_for_xp() bounded no matter what XP arrives — an
## unbounded while-loop over a corrupted save is a hang, not an error.
const MAX_RANK := 100

## Highest rank whose XP threshold is met.
##
## Solved rather than looped. xp_to_rank is base * rank^1.6, so the inverse is
## (xp/base)^(1/1.6); walking up from zero would be a hundred pow() calls on every payout,
## and this runs inside the payout pipeline.
static func rank_for_xp(base: float, xp: float) -> int:
	if xp <= 0.0 or base <= 0.0:
		return 0
	var rank := int(floor(pow(xp / base, 1.0 / 1.6) + Econ.EPSILON))
	return clampi(rank, 0, MAX_RANK)

## Progress toward the next rank, 0..1, for a progress bar. Returns 1.0 at the cap so a
## maxed track reads as complete rather than as never-quite-there.
static func rank_progress(base: float, xp: float) -> float:
	var rank := rank_for_xp(base, xp)
	if rank >= MAX_RANK:
		return 1.0
	var floor_xp := Econ.mastery_xp_for_rank(base, rank)
	var next_xp := Econ.mastery_xp_for_rank(base, rank + 1)
	if next_xp <= floor_xp:
		return 0.0
	return clampf((xp - floor_xp) / (next_xp - floor_xp), 0.0, 1.0)

# --- the shared pool -------------------------------------------------------

## How many pool checkpoints `points` has passed. `thresholds` is ascending.
static func checkpoints_reached(points: int, thresholds: Array) -> int:
	var reached := 0
	for t in thresholds:
		if points >= int(t):
			reached += 1
	return reached

## Compounding bonus per checkpoint passed: `step` 1.02 over three checkpoints is 1.061.
## Compounding rather than summing, to match D11's one rule for every multiplier in the
## game — including the ones that go down, which is why the cost step is 0.95 and not -5.
static func pool_multiplier(points: int, thresholds: Array, step: float) -> float:
	return pow(step, float(checkpoints_reached(points, thresholds)))

## Flat additive rewards — the item-limit checkpoints. Additive because "1.02 items" is not
## a thing; the multiplier rule applies to rates, not to counts.
static func pool_flat_bonus(points: int, thresholds: Array, per_checkpoint: int) -> int:
	return checkpoints_reached(points, thresholds) * per_checkpoint

# --- per-item rank rewards -------------------------------------------------

## The item's own payout bonus from its rank. One step at the top rank rather than a curve:
## ranks 10 and 25 already pay out as *unlocks* (the Tier 2 branch and the automation
## capstone), so rank 50 is the only one that needs to be worth something numerically.
static func item_rank_multiplier(rank: int, bonus_rank: int, bonus: float) -> float:
	return bonus if rank >= bonus_rank else 1.0
