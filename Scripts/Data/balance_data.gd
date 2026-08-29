class_name BalanceData
extends Resource

## Every global tuning knob in the game, in one resource: res://Data/balance.tres.
##
## Nothing else hard-codes a rate. Retuning the game must be editing this file, not
## hunting for a magic number in a script — the numbers in docs/economy.md are the
## explanation, this resource is the authority.

# --- damage -> Bones -------------------------------------------------------

## Contact impulses below this are ignored: resting contact, gentle nudges, and the
## per-frame gravity impulse of a body lying on the floor. Set it too low and a mace left
## leaning against Bonehead farms Bones forever.
@export var min_damage_impulse: float = 350.0

## Damage per unit of contact impulse, before the weapon's own damage_mult.
@export var damage_per_impulse: float = 0.01

## Bones per point of damage, before mood, augments, mastery and prestige.
@export var bones_per_damage: float = 0.5

## Per-source cooldown. One weapon cannot bank two hits closer together than this, which
## is what stops a body resting against him from farming the contact solver.
@export var damage_cooldown: float = 0.15

## Single hit cap, as a fraction of the knockout meter. Stops one pathological impulse
## spike (a tunnelling collision, a physics explosion) from paying out a whole round.
@export var max_hit_fraction: float = 0.5

# --- knockout --------------------------------------------------------------

## Damage that fills the meter and collapses him.
@export var knockout_damage: float = 400.0

## bonus = knockout_mult * round_damage ^ knockout_exponent.
## The sub-1 exponent is the soft cap that stops knockout-farming dominating.
@export var knockout_mult: float = 2.0
@export var knockout_exponent: float = 0.9

## Seconds he stays down before reassembling.
@export var knockout_downtime: float = 1.2

# --- mood ------------------------------------------------------------------

## Sampled at (mood + 100) / 200, so x=0 is despair, 0.5 neutral, 1.0 bliss.
## A U-curve: neutral is the worst possible play, which is what makes optimal play
## oscillate between cruelty and kindness (docs/game-design.md).
@export var mood_curve: Curve

## Mood points shed per second toward 0. The multiplier has to be actively maintained.
@export var mood_decay: float = 2.0

# --- kindness -> Hearts ----------------------------------------------------

@export var hearts_per_kindness: float = 1.0
## Repeat kindness inside this window compounds.
@export var kindness_combo_window: float = 1.5
@export var kindness_combo_step: float = 0.15
@export var kindness_combo_max: float = 3.0

# --- offline ---------------------------------------------------------------

## Idling with the game closed is deliberately worth less than idling with it open —
## the entire pitch is that it lives on your desktop.
@export var offline_efficiency: float = 0.5
## Base cap, upgradeable with Hearts to 8 then 24. The small sting of a hit cap is what
## drives the next session; an uncapped accumulator removes the reason to come back.
@export var offline_cap_hours: float = 2.0
@export var offline_cap_hours_per_level: float = 6.0

# --- prestige / mastery ----------------------------------------------------

@export var prestige_divisor: float = 1e12
@export var mastery_base: float = 100.0

# --- world -----------------------------------------------------------------

## Concurrent spawned items. Raised by Mastery Pool checkpoints.
@export var item_limit: int = 10

# --- presentation ----------------------------------------------------------

## Hit-stop, in frames, scaled by hit magnitude and gated by Focus Mode.
@export var hit_stop_min_frames: float = 2.0
@export var hit_stop_max_frames: float = 8.0
## Damage that earns the maximum hit-stop.
@export var hit_stop_full_damage: float = 120.0

## Falls back to a curve built in code if balance.tres somehow has none, so a missing
## sub-resource degrades the tuning rather than crashing the payout pipeline.
func sample_mood_curve(mood: float) -> float:
	if mood_curve == null:
		return 1.0
	return mood_curve.sample_baked(clampf((mood + 100.0) / 200.0, 0.0, 1.0))

func offline_cap_seconds(cap_level: int) -> float:
	return (offline_cap_hours + offline_cap_hours_per_level * float(maxi(0, cap_level))) * 3600.0
