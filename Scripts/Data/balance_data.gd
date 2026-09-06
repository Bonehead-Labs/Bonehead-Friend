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

## Contacts with the world and with kind-side items need a real *fall* before they hurt, not
## a swing. 1500 on his 3-mass body is 500 px/s — a drop of about his own height (128 px).
## Everything he can do to himself (a step, a climb onto a toy, a tip-over) lands under it; a
## throw, a drop from above his head, or a bat carrying him into the wall lands over it.
## Weapons, throwables and animals keep `min_damage_impulse` (docs/plan-movement-hitboxes.md).
@export var min_fall_impulse: float = 1500.0

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

## The collapse beat, in seconds. He tips over, lies in a heap for `knockout_downtime`,
## then reassembles. Short on purpose: this is the round's climax and the player sees it
## every couple of minutes, so it has to read instantly and never outstay its welcome.
@export var knockout_collapse_time: float = 0.35
@export var knockout_reassemble_time: float = 0.45

## Coins in the payout fountain. Pooled labels, so this is a display count, not an alloc.
@export var knockout_fountain_coins: int = 10

# --- mood ------------------------------------------------------------------

## Sampled at (mood + 100) / 200, so x=0 is despair, 0.5 neutral, 1.0 bliss.
## A U-curve: neutral is the worst possible play, which is what makes optimal play
## oscillate between cruelty and kindness (docs/game-design.md).
@export var mood_curve: Curve

## Mood points shed per second toward 0. The multiplier has to be actively maintained.
@export var mood_decay: float = 2.0

## Mood points lost per point of damage. At 0.30 a full 400-damage round drives him from
## neutral to despair with room to spare, which is the pacing the U-curve wants: a round
## should be able to reach an extreme, not merely lean toward one.
@export var mood_per_damage: float = 0.30

## Mood gained per unit of kindness, applied to the square root of the payout's value
## (MoodMath.kindness_mood). A pet is worth 1.0, so this is "+4 mood per pet" — roughly
## twenty seconds of petting from neutral to bliss, before the soft rail in MoodMath.nudge
## slows the last stretch. A 25-value pizza is worth five pets, not twenty-five.
@export var mood_per_kindness: float = 4.0

# --- grime -----------------------------------------------------------------

## Grime accrued per point of damage. Explosions and beatings make a mess; the sponge is
## the only thing that cleans it, which is what makes hygiene an economic decision.
@export var grime_per_damage: float = 0.0008

## Bones income is multiplied by (1 - grime * this). A filthy buddy earns 0.65x — a real
## cost, never a block on play (docs/game-design.md pillar 1: no fail state).
@export var grime_max_penalty: float = 0.35

## Grime removed per second of sponge contact, and the Hearts paid per unit removed.
## Cleaning him from filthy to spotless is worth roughly 8 Hearts before combo and mood.
@export var sponge_clean_rate: float = 0.5
@export var hearts_per_grime_cleaned: float = 8.0

# --- kindness -> Hearts ----------------------------------------------------

@export var hearts_per_kindness: float = 1.0
## Repeat kindness inside this window compounds.
@export var kindness_combo_window: float = 1.5
@export var kindness_combo_step: float = 0.15
@export var kindness_combo_max: float = 3.0

## Petting: one kindness event every `pet_interval` seconds while the open hand is held on
## him. Fast enough that the combo multiplier actually engages, slow enough that a held
## mouse button is not a payout firehose.
@export var pet_interval: float = 0.25
@export var pet_value: float = 1.0

# --- offline ---------------------------------------------------------------

## Idling with the game closed is deliberately worth less than idling with it open —
## the entire pitch is that it lives on your desktop.
@export var offline_efficiency: float = 0.5
## Base cap, upgradeable with Hearts to 8 then 24. The small sting of a hit cap is what
## drives the next session; an uncapped accumulator removes the reason to come back.
@export var offline_cap_hours: float = 2.0
@export var offline_cap_hours_per_level: float = 6.0

# --- prestige / mastery ----------------------------------------------------

## marrow = (run earnings / marrow_divisor) ^ marrow_exponent, and income is x(1 + marrow).
##
## Set by `tests/integration/pacing_sim.tscn`, not by eye. The divisor is roughly what a
## first long run earns, so the first Reincarnation is worth about a doubling; the exponent
## is below 1 so that pushing a run further always pays, and never pays enough to be worth
## waiting all day for.
@export var marrow_divisor: float = 1e7
@export var marrow_exponent: float = 0.5

# --- Dollars ---------------------------------------------------------------

## Flat, per act, and **never multiplied by anything** (docs/decisions.md D31). Bones and
## Hearts inflate by design; Dollars must not, or a hat would cost an afternoon on day one
## and a second on day ninety. Kind acts pay less per act than hits because petting is four
## times a second and swinging is not.
@export var dollars_per_hit: float = 1.0
@export var dollars_per_kind_act: float = 0.4

## What automation pays, per second, as a fraction of one hit's worth. The only place in the
## economy deliberately worse when idle: Dollars buy the things you look at, so they should
## mostly be earned while looking.
@export var dollars_idle_efficiency: float = 0.15

## xp_to_rank(r) = mastery_base * r^mastery_exponent. Rank 1 costs 100 XP, rank 10 ~3,981.
@export var mastery_base: float = 100.0
@export var mastery_exponent: float = 1.6

## XP per point of damage dealt, and per unit of kindness value. Kindness values are an
## order of magnitude smaller than damage numbers, so the two rates differ by roughly that
## much — otherwise a friendly item could never be mastered in a human lifetime.
@export var mastery_xp_per_damage: float = 1.0
@export var mastery_xp_per_kindness: float = 12.0

## Ranks that unlock something. 10 opens an item's Tier 2 branch, 25 its automation
## capstone, 50 its personal payout bonus (docs/economy.md).
@export var mastery_branch_rank: int = 10
@export var mastery_automation_rank: int = 25
@export var mastery_bonus_rank: int = 50
@export var mastery_rank_payout_bonus: float = 1.5

## The shared Mastery Pool. One point per rank gained on any item; passing a threshold
## grants all three bonuses below. The pool is what makes breadth worth pursuing — without
## it players correctly conclude that spreading mastery is wasted mastery.
@export var mastery_pool_thresholds: Array[int] = [10, 25, 50, 100, 200]
## Compounding per threshold passed, matching D11's one rule for every multiplier.
@export var mastery_pool_income_step: float = 1.02
@export var mastery_pool_cost_step: float = 0.95
## Additive, because "1.02 items" is not a thing.
@export var mastery_pool_item_step: int = 1

# --- automation ------------------------------------------------------------

## How often banked automation income is paid out while the game is open. Banked rather
## than granted per frame: a payout per frame is a floating number per frame through the FX
## pool and a signal per frame on the bus, for income the player reads as a steady trickle.
@export var automation_payout_interval: float = 1.0

# --- contracts -------------------------------------------------------------

## How many contracts of each period are offered at once.
@export var contracts_daily_slots: int = 3
@export var contracts_weekly_slots: int = 1

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
