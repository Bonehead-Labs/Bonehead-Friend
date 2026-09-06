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

# --- the tell ---------------------------------------------------------------
#
# How this personality *shows* (docs/plan-expressive-buddy.md §5). D19 forbids a personality
# touching numbers — prices, damage, payouts — and these touch none: they multiply no payout,
# so they cannot become balance problems, and a thirteenth personality is still a `.tres`
# with no script edit (D8). All defaulted, so a file that says nothing about its tell reads
# as the honest baseline. Edit them through `tools/seed_m38_personality_tells.tscn`.

## The face he pulls when hit. A Masochist grins while you hit him — one field teaches the
## whole curve wordlessly.
@export var hurt_face: StringName = &"shocked"
## The face for a purchase, a rank up, a milestone. A Showman is smug about it.
@export var celebration_face: StringName = &"happy"
## Face -> face, applied to *every* expression he pulls, mood faces included. The Goth's
## `sad` is his contented face and his bliss reads as embarrassment.
@export var face_swaps: Dictionary = {}
## Multiplies every code motion (hop, recoil, squash, lean) — never a payout. 0.4 is a Stone,
## 1.6 is a Showman.
@export var reaction_amplitude: float = 1.0
## Seconds between fidgets while idle; 0 disables them. A Gremlin is never still.
@export var fidget_period: float = 12.0
## Flinches at a threat before it lands — the one who reacts to the wind-up, not the blow.
@export var flinches_early: bool = false

func validation_error() -> String:
	if id == &"":
		return "missing id"
	if display_name.is_empty():
		return "personality '%s' has no display_name" % id
	if mood_curve == null:
		return "personality '%s' has no mood_curve" % id
	return ""
