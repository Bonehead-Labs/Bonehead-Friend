class_name MoodMath
extends RefCounted

## Mood and grime formulas. Pure and dependency-free, so the headless test runner reaches
## them — autoload singletons are not registered under `-s`, which is why every formula in
## this project lives apart from the node that owns the state.
##
## Mood runs -100 (despair) to +100 (bliss) and decays toward 0. The payout multiplier it
## feeds is a U-curve sampled from balance.tres, so neutral is the *worst* place to be and
## optimal play oscillates between cruelty and kindness (docs/economy.md).

const MIN_MOOD := -100.0
const MAX_MOOD := 100.0

static func clamp_mood(value: float) -> float:
	return clampf(value, MIN_MOOD, MAX_MOOD)

## Sheds `per_second` points toward zero, never overshooting past it. Overshoot would flip
## a despairing buddy into a mildly happy one on a long frame, which reads as a bug and
## quietly hands the player a different multiplier than the one they were maintaining.
static func decay(mood: float, per_second: float, delta: float) -> float:
	var shed := absf(per_second) * maxf(0.0, delta)
	if absf(mood) <= shed:
		return 0.0
	return mood - signf(mood) * shed

## One mood event. Pushing further into the extreme you are already at is progressively
## harder; pushing back toward the other rail is always full strength.
##
## That asymmetry is the seesaw. Swinging him from misery to bliss stays fast — which is
## the rhythm the U-curve is asking for — while the last few points at either rail have to
## be worked for, so 2.0x is earned rather than parked at.
static func nudge(mood: float, amount: float) -> float:
	if is_zero_approx(amount):
		return clamp_mood(mood)
	var deeper := signf(amount) == signf(mood)
	var scale := 1.0 - absf(mood) / MAX_MOOD if deeper else 1.0
	return clamp_mood(mood + amount * maxf(0.0, scale))

## Mood gained from a kindness payout worth `value`.
##
## Square-rooted rather than linear. Kindness values across the roster span two orders of
## magnitude — a pet is 1, a full sponge-down is 8, a pizza is 25 — and a linear mapping
## would make whichever item has the biggest number the only one that moves his mood at
## all. Under a root a pizza is worth five pets instead of twenty-five, which is the
## relationship the catalog actually wants.
static func kindness_mood(value: float, per_kindness: float) -> float:
	return per_kindness * sqrt(maxf(0.0, value))

# --- grime -----------------------------------------------------------------

## Grime is 0..1. He gets filthy from being blown up and beaten, and the sponge is the only
## thing that cleans him — which is what makes hygiene an economic decision rather than a
## cosmetic one (docs/game-design.md).

static func clamp_grime(value: float) -> float:
	return clampf(value, 0.0, 1.0)

## Multiplier applied to Bones income. At `max_penalty` 0.35 a filthy buddy earns 0.65x,
## so ignoring him costs real money without ever blocking play.
static func grime_penalty(grime: float, max_penalty: float) -> float:
	return 1.0 - clamp_grime(grime) * clampf(max_penalty, 0.0, 1.0)
