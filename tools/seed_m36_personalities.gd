extends Node

## Seven more personalities, taking the roster from five to twelve.
##
##   Godot --headless --path <project> res://tools/seed_m36_personalities.tscn
##
## A personality is one Curve and nothing else (docs/decisions.md D19) — no stat riders, no
## special cases, nothing a script has to branch on. That restraint is exactly why adding
## seven of them is a table rather than a feature: the whole mechanic is "the same actions
## are worth different amounts depending on where his mood is", and each curve is a
## different opinion about where the money is.
##
## They matter more now than they did. Reincarnation is free and has no threshold (D33), so
## a player resets far more often than the old cube-root curve ever allowed — and the roll
## never returns the one just played. Five curves meant a returning player saw a repeat
## every other life.
##
## The shape rules, learned from the five that exist:
##   - Neutral must be the worst point on almost every curve. The U is the game's rhythm
##     mechanic; a personality that pays well at neutral is a personality that tells the
##     player to stop playing.
##   - The two exceptions earn it. Zen is deliberately flat because "the run you can mostly
##     ignore" is a real thing to want, and Goth's peak is deliberately off-centre because
##     one curve in the set should break the habit the others teach.
##   - Nothing exceeds 3.0: that is the Curve's max_value, and a point above it is silently
##     clamped, which reads as the personality simply not working.

const PersonalityDataScript := preload("res://Scripts/Data/personality_data.gd")

const PERSONALITIES_DIR := "res://Data/Personalities"

## Sampled at (mood + 100) / 200 — despair at x=0, neutral at 0.5, bliss at 1.0.
## [id, name, description, five points, sort_order]
const PERSONALITIES := [
	[&"nervous", "Nervous", "Flinches at everything. Pays hugely for the first blow of a swing and tails off, so the profitable rhythm is short bursts with pauses in them rather than a sustained beating.",
		[2.4, 2.0, 0.7, 1.0, 1.3], 50],
	[&"gremlin", "Gremlin", "Thrives on chaos and hates being settled. Both extremes pay, and the trough is the deepest in the set — the purest version of the seesaw, and the least forgiving of a player who parks him.",
		[2.6, 1.4, 0.4, 1.4, 2.6], 60],
	[&"martyr", "Martyr", "Wants to suffer for someone. Misery pays, but only just — and bliss pays nothing at all, so kindness becomes purely about grime and automation rather than income.",
		[2.2, 1.8, 0.8, 0.7, 0.6], 70],
	[&"showman", "Showman", "Plays to a room that is not there. A tall, narrow peak at bliss: the highest ceiling of any personality and the hardest to hold, because mood decays the whole time.",
		[0.9, 0.8, 0.6, 1.4, 3.0], 80],
	[&"stone", "Stone", "Feels very little. Almost flat and slightly below the others everywhere — the run where mood stops being a lever at all and the answer is simply to buy more automation.",
		[1.1, 1.0, 0.9, 1.0, 1.1], 90],
	[&"pendulum", "Pendulum", "Only pays while he is moving between moods. Two peaks either side of neutral rather than at the extremes, so the optimal play is a fast oscillation that never quite arrives anywhere.",
		[1.2, 2.6, 0.5, 2.6, 1.2], 100],
	[&"tyrant", "Tyrant", "Rewards commitment and punishes hedging. Both ends pay well, the middle pays almost nothing, and the curve is steep enough that a half-hearted swing is worse than no swing at all.",
		[2.9, 1.0, 0.3, 1.0, 2.9], 110],
]

var _written := 0
var _skipped := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(PERSONALITIES_DIR)
	for entry in PERSONALITIES:
		_personality(entry[0], entry[1], entry[2], entry[3], entry[4])
	print("seed_m36_personalities: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _personality(id: StringName, display_name: String, description: String,
		points: Array, sort_order: int) -> void:
	var path := "%s/%s.tres" % [PERSONALITIES_DIR, id]
	if ResourceLoader.exists(path):
		_skipped += 1
		return
	var res := PersonalityDataScript.new()
	res.id = id
	res.display_name = display_name
	res.description = description
	res.mood_curve = _curve(points)
	res.sort_order = sort_order
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("seed_m36_personalities: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)

## Five evenly spaced points, baked. Baked because the payout pipeline samples this on every
## hit and sample_baked is a lookup where sample() is a solve.
func _curve(points: Array) -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 3.0
	for i in points.size():
		curve.add_point(Vector2(float(i) / float(points.size() - 1), float(points[i])))
	curve.bake()
	return curve
