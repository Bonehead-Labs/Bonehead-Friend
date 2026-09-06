# Economy

Every number in this document is a **starting point**, not a law. The authoritative values
live in `Scripts/Data/balance_data.gd` as `BalanceData` defaults — `res://Data/balance.tres` overrides only two of them (`mastery_xp_per_damage`, `mood_curve`); this doc explains the shapes and why they were chosen.
When you retune, update both.

## Payout pipeline

One path, used by damage and kindness alike:

```
raw event ──► base value ──► × mood ──► × augments ──► × mastery ──► × prestige ──► payout
```

```gdscript
func payout_for(base: float, currency: StringName, source_id: StringName) -> float:
	return base \
		* balance.mood_curve.sample(mood / 100.0) \
		* Progression.get_modifier(source_id, &"payout_mult") \
		* Progression.mastery_pool_bonus() \
		* prestige_multiplier()
```

### Base values

**Damage → Bones.** Damage is the **contact impulse** the buddy actually receives
(`PhysicsDirectBodyState2D.get_contact_impulse()`), scaled per weapon:

```
damage = impulse × weapon.damage_mult
bones  = damage × balance.bones_per_damage        # start at 0.5
```

Impulses below `balance.min_damage_impulse` are ignored (resting contact, gentle nudges).
A per-source cooldown of ~0.1 s prevents a weapon left leaning against him from farming.

This replaces the prototype's velocity-probe hack, which read the velocity of a shapeless
nested rigid body and therefore measured *time since last hit*, not swing speed. The new model
also means **any** rigid body is a weapon — a bowling ball dropped from height pays properly
without special-casing.

**Kindness → Hearts.** Two shapes, and they are two different signals (`docs/decisions.md` D14):
- *Event* kindness — `EventBus.kindness_given`. A pet, a caught baseball, a slice of pizza:
  flat value per event, **with** a combo multiplier on repeats inside a short window.
- *Sustained* kindness — `EventBus.kindness_sustained`. Boombox, sponge, hot tub, chocolate
  fountain: Hearts per second while active, **without** the combo. A generator left switched
  on would otherwise park at the 3x ceiling forever.

Shipped kindness values (first draft, tune from play):

| Source | Shape | Value | Note |
|---|---|---|---|
| Open Hand (pet) | event | `pet_value` 1.0 every `pet_interval` 0.25 s while held on him | the only free Hearts source |
| Sponge | sustained | `hearts_per_grime_cleaned` 8.0 × grime actually removed | pays nothing on a clean skeleton |
| Pizza | event | 25, consumed on contact | active-play burst |
| Boombox | sustained | 0.6 / s while placed | the first Hearts generator |

**Knockout bonus.** On collapse, pay `balance.knockout_mult × (damage dealt this round)`, with
a soft cap so knockout-farming doesn't dominate:
`bonus = knockout_mult × round_damage^0.9`.

### Mood multiplier

A `Curve` in `balance.tres`, sampled from mood ∈ [−100, +100]:

| Mood | −100 | −50 | 0 | +50 | +100 |
|---|---|---|---|---|---|
| Multiplier | **2.0×** | 1.2× | **0.6×** | 1.2× | **2.0×** |

A U, not a ramp. Sitting at neutral is the worst possible play; the player is pushed to swing
him between misery and bliss. Mood decays toward 0 at `balance.mood_decay` per second, so the
multiplier must be actively maintained.

**How mood moves.** `MoodMath` owns the shape; `MoodComponent` owns the value.

```
damage   -> mood -= amount * balance.mood_per_damage          # 0.30, linear
kindness -> mood += mood_per_kindness * sqrt(value)           # 4.0, root-scaled
decay    -> toward 0 at mood_decay per second, never overshooting past it
```

Two shapes worth understanding before retuning either:

- **Kindness is root-scaled, damage is not.** Kindness values span two orders of magnitude
  across the roster (a pet is 1, a full sponge-down is 8, a pizza is 25) and a linear mapping
  would make whichever item has the biggest number the only one that moves his mood at all.
  Under a root, a pizza is worth five pets. Damage per hit is already capped at
  `knockout_damage × max_hit_fraction`, so it needs no second cap.
- **The rails are soft.** Pushing deeper into the extreme he is already at scales by the
  remaining headroom; pushing back toward the other rail is always full strength. That
  asymmetry *is* the seesaw — crossing the middle stays fast, which is the rhythm the U-curve
  is asking for, while the last few points at either end have to be worked for, so 2.0x is
  earned rather than parked at.

A full 400-damage round drives him from neutral to despair with room to spare, which is the
intended pacing: a round should be able to *reach* an extreme, not merely lean toward one.

### Grime

Grime is 0..1 and multiplies **Bones** income only:

```
bones_multiplier = 1 - grime × balance.grime_max_penalty     # 0.35, so filthy earns 0.65x
grime += damage × balance.grime_per_damage                   # 0.0008, ~0.3 per round
```

The sponge and the warm towel remove it, and they pay Hearts on grime *actually removed* —
the kindness-side twin of the resting-contact cooldown on the damage path. Since the
September 2026 assessment both also pay a small `hearts_per_second_touching` trickle, because
a Hearts-first player has no grime and the 40-Heart sponge otherwise paid nothing at all.

This is the dual-currency spine in one multiplier (D2): the cheapest Hearts item in the game
is what protects the Bones economy, so a player who only ever hits him pays for it. It is
never a wall — a filthy buddy still earns, because there is no fail state.

## Cost curves

**Two different curves for two different jobs** — this split is deliberate.

### Unlocks: flat, hand-authored, one-time

Items are bought once at an authored price (see the catalog in `game-design.md`). Interactive
Buddy's entire game was a $15→$400 ladder of ~25 one-time purchases, and that is exactly why
each purchase felt like an event rather than a tick. Prices roughly triple per tier.

### Augments: exponential levels

```
cost(n) = cost_base × growth^n          # n = levels already owned
```

`growth` defaults to **1.10**, per-node overridable in the 1.07–1.15 band that the genre has
converged on (AdVenture Capitalist 1.07–1.15, Clicker Heroes 1.07, Cookie Clicker 1.15). Lower
growth means many small satisfying purchases; higher means each purchase is an event. Use ~1.09
for cheap utility nodes and ~1.12 for headline damage nodes.

Bulk purchase maths — implement both from day one or the "Buy ×10 / Buy Max" buttons will be
subtly wrong:

```
cost of n more, owning k:   b · rᵏ(rⁿ − 1) / (r − 1)
max affordable with c:      ⌊ log_r( c(r−1)/(b·rᵏ) + 1 ) ⌋
```

### Augment tree shape

Every weapon owns a small tree; the shape is identical across weapons so it's one UI and one
data pattern:

```
WEAPON (flat unlock price, Bones)
├─ TIER 1 — buyable levels, growth 1.10, max 10
│    ├─ Damage        ×1.15 / level
│    ├─ Payout        ×1.12 / level
│    └─ Rate/Cooldown ×0.95 / level
├─ TIER 2 — pick ONE (exclusive_group), needs Mastery 10
│    ├─ e.g. Slugger     ×1.6 damage
│    ├─ e.g. Bone Cutter ×1.8 payout
│    └─ e.g. Pillow Bat  ×0.35 damage — the bat that is nice to him
└─ CAPSTONE — AUTOMATION, costs Hearts, needs Mastery 25
```

**The capstone does not require a Reincarnation** — see `docs/decisions.md` D17. The spec used to
say Mastery 25 + Reincarnation ≥ 1, which contradicted the balance target of a first automation
at 30 minutes against a first Reincarnation at 6–10 hours.

Exclusive branches give three flavours from one weapon at almost no content cost. Respec is
allowed for a Hearts fee.

Gating gradient across the game: **Cash → Cash + Mastery → Cash + Mastery + Prestige.** Three
escalating keys, so progress is never purely a money wall.

## Mastery

XP accrues per item, per use, proportional to value delivered (damage dealt or Hearts earned).

```
xp_to_rank(r) = balance.mastery_base × r^1.6
```

- **Rank 10** — unlocks the item's Tier 2 branch choice.
- **Rank 25** — unlocks the automation capstone.
- **Rank 50** — item's personal capstone bonus (typically ×1.5 payout).

Shipped rates: `mastery_xp_per_damage` 1.0 and `mastery_xp_per_kindness` 12.0. The two differ by
roughly an order of magnitude because damage numbers are an order of magnitude larger than
kindness values — at a shared rate a friendly item could never be mastered in a human lifetime.

`MasteryMath.rank_for_xp` is the **solved** inverse of `xp_to_rank`, not a loop. It runs inside
the payout pipeline on every hit, and a hundred `pow()` calls per payout is not affordable under
a 3% CPU budget. Ranks are cached per item in `Progression` and recomputed only when XP is added.

Each rank also drops a point into the shared **Mastery Pool** — one point per rank *crossed*, so
a single event spanning four ranks is worth four points. Pool checkpoints
(10 / 25 / 50 / 100 / 200 points) grant three global bonuses, all compounding per checkpoint:

| Knob | Per checkpoint | At all five |
|---|---|---|
| `mastery_pool_income_step` | ×1.02 all income | ×1.10 |
| `mastery_pool_cost_step` | ×0.95 augment costs | ×0.77 |
| `mastery_pool_item_step` | +1 concurrent item | +5 |

Compounding rather than summing, so the pool obeys D11's one rule for every multiplier in the
game — including the one that goes down. The pool is what makes breadth worth pursuing; without
it, players correctly conclude that spreading mastery is wasted.

**The cost discount must reach the quote as well as the charge.** `Progression._discounted_base`
is the single place it is applied and everything that prices or sells an augment goes through it
— a discount in one path and not the other is a button that quotes one number and takes another.

## Automation

An automation capstone generates its **owning item's** currency per second: a weapon automates
into Bones, a friendly item into Hearts. That rate is `AugmentNode.automation_rate` — a rate, not
a multiplier, and therefore its own field rather than a reuse of `effect_per_level`. D11's "every
effect is a multiplier" rule is what keeps `AugmentMath` four lines long, and income per second
is the one thing that genuinely is not one.

```
online:  rate × delta, banked and paid every automation_payout_interval (1 s)
offline: rate × clamp(elapsed, 0, cap) × offline_efficiency
```

Automated income runs the **same payout pipeline** as a swing, so mood, mastery and prestige all
apply to it. Every capstone has an on/off toggle, which is not a convenience: a player in a
meeting must be able to stop the desktop moving without giving up the income, and that is exactly
what the Focus Mode promise requires.

### Capstones are levelled — this is the game's exponential engine

Every capstone is `max_levels 30` at `cost_growth 1.10`, and the rate paid is
`automation_rate x levels owned`. **Linear rate against exponential cost** is the shape the genre
converged on (AdVenture Capitalist's businesses), and it is the only thing in this economy that
makes income grow without bound.

That matters more than it looks. M3 shipped two capstones, both single-level, so idle income was a
flat line no matter how long anyone played — and a flat line cannot reach a prestige threshold
built on a cube root of *lifetime* earnings, at any divisor. Levels, plus a capstone on every item,
plus the global tree below, are what give lifetime earnings the curvature the prestige formula
assumes (M3.5-A).

Numbers are **derived from the item's shop price**, in `tools/seed_m35_engine.gd`, so a retune is
two constants rather than twenty-eight resources:

```
rate per level  = 1.0 + cost/500     (a Bones item)
                = 0.5 + cost/1500    (a Hearts item)
price in Hearts = 800 + cost x 0.4   (a Bones item)
                = 800 + cost x 0.5   (a Hearts item)
```

Both currencies have their own line because they are earned at different speeds: Bones arrive in
the hundreds from a knockout round, Hearts in ones and twos from petting. Every capstone is priced
in **Hearts** whatever it automates — D2's spine, and the reason automation demand scales the
kindness half of the economy alongside the damage half.

### Two rules about what automation income is multiplied by

Both were accidents of implementation before M3.5-A and are now decisions:

- **Per-item payout augments do not reach automation income.** Automation pays as source
  `&"automation"`, so only global nodes, mood, mastery pool and prestige apply. Keep it: active
  play with a levelled item beats that item's own automation, which is what preserves the
  60/40 split the design wants between playing and idling.
- **Offline pays the stable multipliers only** — prestige and the Mastery Pool — never mood, item
  augments or an item's own rank. Mood is a live value the player was not there to maintain;
  paying eight hours at whatever mood he was left in either rewards parking him at an extreme
  before quitting, or punishes a session that ended mid-swing. Prestige and the pool are
  properties of the save, so they are honest to apply while nobody is watching.

### The global tree

Four `item_id = &"global"` nodes multiply **every** payout in the game, automation included
(`Progression.get_modifier` folds them into every lookup — the hook has existed since M2 and had
no content in it until M3.5-A). They are the cross-run ladder: without them a run's total
multiplier is bounded by how many items are owned.

| Node | Effect | Levels | Price | Gate |
|---|---|---|---|---|
| Technique | x1.10 payout | 15 | 3,000 Bones, growth 1.13 | — |
| Showmanship | x1.10 payout | 15 | 1,500 Hearts, growth 1.13 | — |
| Momentum | x1.12 payout | 10 | 25,000 Bones, growth 1.18 | Technique |
| Devotion | x1.12 payout | 10 | 12,000 Hearts, growth 1.18 | Showmanship |

They appear in the tree page under a chip of their own, last in the picker — the global tree is
not a toy, and putting it first made it the default selection for a player who had come to
upgrade their bat.

## The rest of the pipeline

Two multipliers were added after the five in the diagram above, and both are applied by
`Economy.payout_for` rather than by `EconomyMath.payout_for` — which stays pure and
five-argument so the headless `-s` runner can reach it:

- **the milestone bonus**, the product of `income_bonus` over every rung ever claimed
  (docs/decisions.md D34). It is the third income axis: not damage, not kindness, but
  breadth.
- **one shared timed slot**, `Economy.temp_multiplier()`. One slot and not one per feature:
  the arcade pays into it today and the Dream Journal and Overtime Pay both want the same
  thing, and three multipliers applied in three places is how a pipeline drifts. Its
  deadlines are engine ticks, so a buff cannot survive a restart even by accident, and a
  weaker offer can never cancel a stronger one.

Neither reaches Dollars, which do not go through the pipeline at all, and neither reaches
offline income, which pays the stable multipliers only.

## Dollars

The third and last currency (docs/decisions.md D31). **There is no Ectoplasm** — Dollars
replaced it.

```
each damaging hit: dollars_per_hit          (flat, whatever the weapon, whatever the damage)
each kind act:     dollars_per_kind_act     (flat, whatever the item)
milestones:        the reward on the MilestoneData
automation & offline: x dollars_idle_efficiency
```

Three properties, each load-bearing:

- **They are never multiplied.** Not by mood, not by augments, not by mastery, not by Marrow.
  Dollars do not go through `payout_for` at all. Bones and Hearts inflate by design and must;
  Dollars cannot, so a veteran with a x4,000 multiplier earns them at exactly the same rate as
  someone on their first afternoon. Cosmetics therefore arrive on a schedule of *attention*
  rather than of power, which is the only sane way to price a hat in a game whose other
  numbers grow without bound.
- **Idling earns a fraction** (`dollars_idle_efficiency`, first draft 0.15) — the one place in
  the economy that is deliberately worse when idle, and the reason it is here: Dollars buy the
  things you look at.
- **They buy nothing in the shop.** Cosmetics, the arcade, and Séance boons. Never a toy,
  never an upgrade, never a level of automation — and nothing they buy may pay out Hearts at a
  rate that competes with being kind to him, because automation is Hearts-priced everywhere
  and that bargain is the whole design (D2).

Knobs: `dollars_per_hit`, `dollars_per_kind_act`, `dollars_idle_efficiency`.

## Reincarnation and Marrow

```
marrow gained = (run earnings / marrow_divisor) ^ marrow_exponent
income multiplier = 1 + marrow (total)
```

No threshold: reset whenever you like, and the Rebirth page always states what you would get.
A reset wipes the run — both currencies, every unlock, every augment level, every exclusive
choice, all mastery — and keeps Marrow, Dollars, cosmetics, Séance boons, milestones and the
contract board. It also rolls a new personality.

**Why a reset loop exists at all**, given that the brief is an endless game rather than a
grindy one: an upgrade ladder's costs grow geometrically while any one device's output grows
linearly, so every individual track stalls. A loop that resets the costs and keeps the
multipliers is the only structure that does not, which is why the genre converged on it. The
previous shape — Ectoplasm at the cube root of *lifetime* earnings — failed for a different
reason: it made each reset cost eight times the last in wall clock, and paid one point of a
one-per-cent multiplier for it. Marrow scales with the *run*, so a faster run reaches further
and pays more, and cycle length stays roughly flat.

Marrow is a stat, not a currency. It is never spent and never appears in the purse.

## Contracts## Contracts

Rotating objectives keyed on `EventBus.contract_event`. Three daily slots and one weekly, rolled
from a seed derived from the day index rather than from chance — a board reshuffled on every boot
would let a player reroll until they liked the offer.

Rewards are **Dollars only** (`docs/decisions.md` D18, amended by D31 — they used to be
Ectoplasm, which no longer exists). The reason for the rule is unchanged and Dollars satisfy
it just as well: a daily that paid Bones or Hearts would set the pace of the shop ladder by
the calendar instead of by play, and Dollars buy nothing in the shop.

Two things deliberately do not count:

- **Sustained kindness is not a contract event.** A placed boombox flushes twice a second
  forever; on the shared `kindness` key it would finish a 150-target contract in seventy-five
  seconds with nobody at the keyboard. Contracts count *acts*.
- **Prestige does not reset the board.** Contracts are a real-time hook, not a run-scoped one,
  and resetting them would let a player farm a daily by reincarnating.

## Reincarnation (prestige)

```
marrow_gained = ( run_earnings / marrow_divisor ) ^ marrow_exponent
income multiplier = 1 + marrow_total
```

**Superseded 2026-08-30 (docs/decisions.md D33).** This was a cube root of *lifetime*
earnings paying Ectoplasm at +1% a point — Cookie Clicker's ascension curve — and the pacing
simulator showed what that shape actually does here: each reset needs eight times the lifetime
of the last, so each one takes eight times the wall clock, and every reset pays exactly **one
point** because the point count grows as the root of a threshold that grows as a cube. Five
resets, fifty-eight simulated hours, five per cent.

Marrow scales with the **run** instead, and there is no threshold at all — reset whenever you
like. A faster run reaches further, further pays more Marrow, more Marrow makes the next run
faster. Cycle length stays roughly flat rather than growing eightfold, which is what the
pacing target below was always asking for and never going to get.

Pacing target: the first Reincarnation worth taking inside a first long session; cycles that
stay within 2x of each other rather than doubling away. Both are asserted by
`tests/integration/pacing_sim.tscn`.

Each reset re-rolls Bonehead's **personality**, which swaps his mood curve (see
`game-design.md`) — the same Marrow, a different optimal rhythm. A personality is
*only* a curve (`docs/decisions.md` D19), and the roll never returns the one just played:
drawing the same personality twice reads as the feature being broken rather than as chance.

Shipped curves, sampled at despair / −50 / neutral / +50 / bliss:

| Personality | −100 | −50 | 0 | +50 | +100 | Plays like |
|---|---|---|---|---|---|---|
| Stoic | 2.0 | 1.2 | 0.6 | 1.2 | 2.0 | the honest seesaw; the first-run default |
| Masochist | 2.8 | 1.6 | 0.6 | 0.9 | 1.1 | keep him miserable; clean him only for the grime |
| Diva | 1.1 | 0.9 | 0.6 | 1.6 | 2.8 | mostly put the bat down |
| Zen | 1.4 | 1.2 | 1.0 | 1.2 | 1.4 | never 2x, never 0.6 — the idle-friendly run |
| Goth | 1.6 | 2.2 | 1.0 | 0.8 | 1.4 | the peak is off-centre and breaks every other habit |

**A reset keeps** Marrow, Dollars, cosmetics, Séance boons, lifetime totals, the reset count,
the offline cap, milestones and the contract board. **It wipes** Bones and Hearts, every
unlock, every augment level, every exclusive choice and all mastery.

## Offline earnings

```
elapsed  = clamp(now − last_played, 0, cap_hours × 3600)     # negative deltas → 0, always
earnings = automation_rate_per_second × elapsed × balance.offline_efficiency
```

- Offline pays `rate x elapsed x efficiency x prestige x pool` — the **stable** multipliers, and
  deliberately not mood, item augments or item rank (see Automation above).
- `offline_efficiency` starts at **0.5** — idle-while-closed should be worse than idle-while-open,
  or the game's own pitch (keep it on your desktop) is undermined.
- Cap starts at **2 hours**, upgradeable with Hearts to 8 then 24. Capping is load-bearing: an
  uncapped accumulator removes the reason to return, and the small sting of a hit cap is what
  drives the next session.
- Only automation earns offline. Active-play income does not accrue.
- **Always clamp negative elapsed to zero** — clock changes, timezone shifts and cloud-sync skew
  are all real and all exploitable.

## The pacing simulator

`tests/integration/pacing_sim.tscn` plays seventy-two hours of a modelled player against the
real content in about a second, and asserts the targets below. It exists because every one of
them is a statement about *hours* and nothing in the project could check one — which is how
`prestige_divisor` came to ship at 1e12, about forty years of play, with nobody noticing.

The player it models is a page of named constants: twelve minutes of play an hour, 60/40
between hitting and being kind, mood held at 70, and 60% of attention on a favourite toy with
the rest spread across the roster. **That last number decides whether the engine starts at
all** — mastery is per item and rank 25 gates automation, so a sim that swings one weapon buys
one device forever, and a sim that spreads evenly across sixteen weapons masters none of them
and buys nothing on the Bones side. Both were tried; the findings are in `roadmap.md`.

A human playtest remains the ground truth for whether the game is *fun*. This is the
instrument for whether it is *reachable*, and when the two disagree the session wins and the
model gets fixed.

Four numbers it set, none of which were arrived at by eye:

| Knob | Was | Is | Because |
|---|---|---|---|
| `prestige_divisor` | 1e12 | **1e7** | a first Reincarnation at 8:07 rather than never |
| `prestige_income_per_point` | +1% additive, hard-coded | **compounding**, in `BalanceData` | a linear multiplier cannot keep up with a threshold that grows as a cube |
| `mastery_xp_per_damage` | 1.0 | **4.0** | weapons never reached rank 25, so twelve hours ended with 1,095 Hearts/s of idle income and **zero Bones/s** |
| the global tree | four nodes stacking to x169 | x3.2 (x15 after a reset) | the whole 28-item catalog was bought out in sixty-six minutes |

## Balance targets

Rough shape of a healthy first session:

| Time | Player should have |
|---|---|
| 0–2 min | Hit him, seen numbers, earned first Bones, bought *something* |
| 5 min | 2–3 items owned, first augment purchased, first knockout seen |
| 15 min | First friendly item, first Hearts, understands the two currencies |
| 30 min | First automation running, understands why Hearts matter |
| 2 h | Mid-tier weapons, several trees in progress, first contract completed |
| ~6–10 h | First Reincarnation available |

No purchase should ever be more than ~5 minutes of active income away at the current tier. If
the next thing costs longer than that, the tier is mistuned — that gap is where players quit.

Stagger milestone thresholds so old items stay relevant (25/50/100/200 uses) and progression
feels bumpy rather than smooth. **Never let a new tier permanently obsolete an old one** —
that's what the Mastery Pool and the exclusive branches exist to prevent.

## Tuning workflow

1. All knobs are `BalanceData` exports with their defaults in `Scripts/Data/balance_data.gd`; `res://Data/balance.tres` holds only the two values that override a default. Change a default in the script, or override it in the resource — never hard-code a rate.
2. Debug builds log every payout and purchase to a local CSV — `Scripts/Economy/tuning_log.gd`,
   writing `user://logs/session_<timestamp>.csv`, installed by `main.gd` only under
   `OS.is_debug_build()`. Every row carries the full economic context (mood, grime, both
   balances, the mood multiplier in force), because "he earned 4 Bones" is unanalysable while
   "he earned 4 Bones at mood −80 with 0.4 grime, 200 seconds in" tells you which multiplier is
   mistuned. Look for the gap where nothing was affordable for more than five minutes — that gap
   is the tier to fix.
3. Economy maths is unit-tested (`tests/run_tests.gd`): cost curves, bulk-buy, max-affordable,
   prestige, offline clamping, mood decay and rails, grime penalty. These are pure functions
   with no excuse for being wrong.
4. Retune against real playtest CSVs, not intuition.
