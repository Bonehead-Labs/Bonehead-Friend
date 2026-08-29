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
## Cube root: doubling your prestige takes roughly 8x the run. See docs/economy.md.
static func ectoplasm_for_lifetime(lifetime: float, divisor: float = 1e12) -> int:
	if lifetime <= 0.0 or divisor <= 0.0:
		return 0
	return int(floor(pow(lifetime / divisor, 1.0 / 3.0) + EPSILON))

## Ectoplasm gained by resetting now. Never negative.
static func prestige_gain(lifetime: float, already_held: int, divisor: float = 1e12) -> int:
	return maxi(0, ectoplasm_for_lifetime(lifetime, divisor) - already_held)

## Income multiplier from held ectoplasm: +1% per point.
static func prestige_multiplier(ectoplasm_held: int) -> float:
	return 1.0 + 0.01 * float(maxi(0, ectoplasm_held))

# --- mastery ---------------------------------------------------------------

## XP required to reach `rank`, superlinear so late ranks are a real commitment.
static func mastery_xp_for_rank(base: float, rank: int) -> float:
	if rank <= 0:
		return 0.0
	return base * pow(float(rank), 1.6)

# --- offline ---------------------------------------------------------------

## Automation income accrued while the game was closed.
## Offline is deliberately worth less than idling with the game open — the whole pitch is
## that it lives on your desktop.
static func offline_earnings(rate_per_second: float, elapsed_seconds: float, efficiency: float = 0.5) -> float:
	return maxf(0.0, rate_per_second) * maxf(0.0, elapsed_seconds) * clampf(efficiency, 0.0, 1.0)
