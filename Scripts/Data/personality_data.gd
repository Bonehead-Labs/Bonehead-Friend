class_name PersonalityData
extends Resource

## Who Bonehead is this run. Rolled fresh on every Reincarnation.
##
## A personality is **one `Curve`**: it replaces the mood multiplier curve and nothing else.
## That is the whole trick — the same Marrow and the same roster, but a different
## optimal rhythm, so a second run is not the first run with bigger numbers
## (docs/game-design.md). Content variety out of a single stat table.
##
## Because it is only a curve, adding a personality is a `.tres` and no script edit (D8).

@export var id: StringName
@export var display_name: String
## Shown on the Reincarnate page. Say what it changes about how to *play* him, not what it
## does to a number — the player cannot see the curve.
@export_multiline var description: String

## Sampled at (mood + 100) / 200, exactly like `BalanceData.mood_curve`: x=0 is despair,
## 0.5 neutral, 1.0 bliss. Null falls back to the balance curve, so a malformed personality
## degrades to the default rhythm rather than zeroing every payout in the game.
@export var mood_curve: Curve

## Ascending display order on the Reincarnate page.
@export var sort_order: int = 0

func validation_error() -> String:
	if id == &"":
		return "missing id"
	if display_name.is_empty():
		return "personality '%s' has no display_name" % id
	if mood_curve == null:
		return "personality '%s' has no mood_curve" % id
	return ""
