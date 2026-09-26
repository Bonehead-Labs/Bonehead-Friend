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

## Which floor a contact has to clear, by who put the energy in. Something on the harm side —
## a weapon, a throwable, an animal, the trampoline's launch — means it, and a swing is enough.
## The world and kind-side items only hurt him if he *fell* onto them: a walk into a wall, a
## climb onto a beanbag or a tip-over is under the fall floor, a drop from above his head is
## over it. A cliff, not a knee: the grapple shake and the beam's per-tick impulse are sized
## against `min_impulse` exactly (docs/plan-movement-hitboxes.md §2). Never below the swing
## floor, so a misconfigured fall floor cannot make the world pay more easily than a bat.
static func contact_floor(harm_side: bool, min_impulse: float, fall_impulse: float) -> float:
	if harm_side:
		return min_impulse
	return maxf(min_impulse, fall_impulse)

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

# --- prestige: Marrow ------------------------------------------------------

## Marrow earned by resetting a run that made `run_earnings`.
##
## Scaled by the **run**, not by lifetime, and with no threshold to cross (D33). The old
## shape — a cube root of lifetime paying whole points — made every reset cost eight times
## the wall clock of the last and pay exactly one point for it, which the pacing simulator
## measured at five points across fifty-eight hours.
##
## The exponent is below 1, so a run that earns twice as much pays less than twice the
## Marrow: pushing further is always worth something and never worth waiting forever for.
static func marrow_for_run(run_earnings: float, divisor: float = 1e7, exponent: float = 0.5) -> float:
	if run_earnings <= 0.0 or divisor <= 0.0:
		return 0.0
	return pow(run_earnings / divisor, exponent)

## Income multiplier from Marrow held. Additive in the exponent's own units and therefore
## unbounded: this is the engine that makes the game endless, so it must not be capped or
## compounded into something that runs away.
static func marrow_multiplier(marrow: float) -> float:
	return 1.0 + maxf(0.0, marrow)

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

## Dollars for time the game was closed (docs/decisions.md D31: "automation and offline pay them
## at `dollars_idle_efficiency`"). Offline is automation left running, so it pays automation's own
## Dollar trickle — a flat `dollars_per_hit x idle_efficiency` a second, whatever the capstones'
## rate and however many of them there are — and, like every offline number, at the offline
## fraction: a closed game earns less than an open one, and Dollars are the currency most owed to
## being looked at. Nothing automated, nothing paid.
##
## **No multiplier of any kind**, not even the stable ones offline Bones and Hearts take: Dollars
## are never multiplied, by Marrow or the pool or anything else (D31's first property). The
## elapsed time is clamped by the caller, to zero below and the cap above, as it is for the rest.
static func offline_dollars(automating: bool, dollars_per_hit: float, idle_efficiency: float,
		elapsed_seconds: float, offline_efficiency: float = 0.5) -> float:
	if not automating:
		return 0.0
	return offline_earnings(maxf(0.0, dollars_per_hit) * clampf(idle_efficiency, 0.0, 1.0),
		elapsed_seconds, offline_efficiency)
