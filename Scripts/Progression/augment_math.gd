class_name AugmentMath
extends RefCounted

## Pure augment-stacking maths, kept dependency-free so the headless test runner can reach
## it — autoload singletons are not registered under `godot -s`, so Progression itself
## cannot be tested directly. Same split as SaveSchema/SaveManager and EconomyMath/Economy.

## Preloaded rather than referenced by global class name: global names resolve through a
## cache only the editor regenerates, and a pure module the test runner imports must not
## depend on that cache being warm.
const Econ := preload("res://Scripts/Economy/economy_math.gd")

## One node's contribution. `per_level` is a MULTIPLIER per level, not an addend: 1.15
## compounds to +15% each time, 0.95 to -5% each time. One rule, no special case for
## effects that are supposed to go down.
static func node_modifier(per_level: float, levels: int) -> float:
	if levels <= 0:
		return 1.0
	return pow(per_level, float(levels))

## Product of every owned level of every node in `entries`.
## Each entry is [per_level: float, levels: int] — deliberately not AugmentNode, so this
## stays free of the resource types and therefore testable.
static func total_modifier(entries: Array) -> float:
	var total := 1.0
	for e in entries:
		total *= node_modifier(float(e[0]), int(e[1]))
	return total

## Levels actually purchasable: bounded by cash, by max_levels, and by the requested count.
## The clamp is what stops a "Buy Max" button offering a level that does not exist.
static func purchasable_levels(cost_base: float, growth: float, owned: int, max_levels: int, cash: float, requested: int = -1) -> int:
	var headroom := maxi(0, max_levels - owned)
	if headroom == 0:
		return 0
	var affordable := Econ.max_affordable(cost_base, growth, owned, cash)
	var want := headroom if requested < 0 else requested
	return mini(mini(affordable, headroom), maxi(0, want))
