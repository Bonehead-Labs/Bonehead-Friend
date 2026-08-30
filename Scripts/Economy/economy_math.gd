class_name EconomyMath
extends RefCounted

## Pure economy formulas. No engine dependencies, so the headless test runner can reach
## them; Economy (M2) calls these rather than re-deriving the maths inline.
##
## Shapes and constants are documented in docs/economy.md.

## Floating point slack applied before flooring.
##
## Without it, values that are mathematically exact integers come back a hair under —
## pow(64, 1.0/3.0) is 3.9999999999999996, and flooring that pays the player 3 prestige
## points instead of 4. Every floor() in this file is a place the player can be silently
## short-changed at exactly the round numbers they are most likely to notice.
const EPSILON := 1e-9

# --- augment costs ---------------------------------------------------------

## Cost of the next level when `owned` are already bought: base * growth^owned.
static func augment_cost(base: float, growth: float, owned: int) -> float:
	return base * pow(growth, owned)

## Total cost of buying `count` more levels while owning `owned`.
## Closed form of the geometric series — never loop this, the UI calls it every frame.
static func bulk_cost(base: float, growth: float, owned: int, count: int) -> float:
	if count <= 0:
		return 0.0
	if is_equal_approx(growth, 1.0):
		return base * count
	return base * pow(growth, owned) * (pow(growth, count) - 1.0) / (growth - 1.0)

## How many levels `cash` can afford, owning `owned`. Inverse of bulk_cost.
static func max_affordable(base: float, growth: float, owned: int, cash: float) -> int:
	if cash <= 0.0 or base <= 0.0:
		return 0
	if is_equal_approx(growth, 1.0):
		return int(floor(cash / base + EPSILON))
	var inner := cash * (growth - 1.0) / (base * pow(growth, owned)) + 1.0
	if inner <= 1.0:
		return 0
	return int(floor(log(inner) / log(growth) + EPSILON))

# --- damage and payout -----------------------------------------------------

## Damage from a raw contact impulse. Below `min_impulse` nothing happens at all — that
## threshold is what separates a swing from a body resting against him.
static func damage_from_impulse(impulse: float, min_impulse: float, per_impulse: float, weapon_mult: float) -> float:
	if impulse < min_impulse:
		return 0.0
	return impulse * per_impulse * maxf(0.0, weapon_mult)

## The one payout pipeline, used by damage and kindness alike:
##   base -> x mood -> x augments -> x mastery -> x prestige
## Written out as a function so there is exactly one place the order can be wrong.
static func payout_for(base: float, mood_mult: float, augment_mult: float, mastery_mult: float, prestige_mult: float) -> float:
	return maxf(0.0, base) * mood_mult * augment_mult * mastery_mult * prestige_mult

## Knockout bonus. The sub-1 exponent is a soft cap: doubling the damage in a round pays
## less than double, so knockout-farming cannot become the only strategy worth playing.
static func knockout_bonus(round_damage: float, mult: float, exponent: float) -> float:
	if round_damage <= 0.0:
		return 0.0
	return mult * pow(round_damage, exponent)

## Kindness combo: each repeat inside the window is worth a little more, up to a ceiling.
static func kindness_combo(repeats: int, step: float, ceiling: float) -> float:
	return minf(1.0 + step * float(maxi(0, repeats)), maxf(1.0, ceiling))

# --- prestige --------------------------------------------------------------

## Total ectoplasm earned for a given lifetime income.
##
## A root, so each point costs more lifetime than the last: at the default exponent of 3
## doubling your ectoplasm takes roughly 8x the run. The exponent is a parameter rather
## than a literal because it is a *balance* number — `BalanceData.prestige_exponent` is the
## authority, and it lived in this file where nobody tuning the game would find it
## (M3.5-A).
static func ectoplasm_for_lifetime(lifetime: float, divisor: float = 1e12, exponent: float = 3.0) -> int:
	if lifetime <= 0.0 or divisor <= 0.0 or exponent <= 0.0:
		return 0
	return int(floor(pow(lifetime / divisor, 1.0 / exponent) + EPSILON))

## Ectoplasm gained by resetting now. Never negative.
static func prestige_gain(lifetime: float, already_held: int, divisor: float = 1e12, exponent: float = 3.0) -> int:
	return maxi(0, ectoplasm_for_lifetime(lifetime, divisor, exponent) - already_held)

## Income multiplier from held ectoplasm.
##
## **Compounding, not additive.** Every other multiplier in the game compounds per level
## (D11), and this one did not: at +1% a point, and a point count that grows as the *cube
## root* of lifetime, the fifth Reincarnation was worth 5% and each one cost eight times the
## run before it. The pacing simulator makes that visible as a ramp that never flattens.
## `pow(1 + per_point, points)` at the old 0.01 is within a hair of the old line for the
## first few points, so this is a change of shape rather than of early-game feel.
static func prestige_multiplier(ectoplasm_held: int, per_point: float = 0.01) -> float:
	return pow(1.0 + maxf(0.0, per_point), float(maxi(0, ectoplasm_held)))

# --- mastery ---------------------------------------------------------------

## XP required to reach `rank`, superlinear so late ranks are a real commitment.
## The exponent is `BalanceData.mastery_exponent`; the default keeps every existing call
## honest. `MasteryMath.rank_for_xp` inverts this and must be given the same value.
static func mastery_xp_for_rank(base: float, rank: int, exponent: float = 1.6) -> float:
	if rank <= 0:
		return 0.0
	return base * pow(float(rank), exponent)

# --- offline ---------------------------------------------------------------

## Automation income accrued while the game was closed.
## Offline is deliberately worth less than idling with the game open — the whole pitch is
## that it lives on your desktop.
static func offline_earnings(rate_per_second: float, elapsed_seconds: float, efficiency: float = 0.5) -> float:
	return maxf(0.0, rate_per_second) * maxf(0.0, elapsed_seconds) * clampf(efficiency, 0.0, 1.0)
