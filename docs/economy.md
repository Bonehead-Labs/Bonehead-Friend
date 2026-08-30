# Economy

Every number in this document is a **starting point**, not a law. The authoritative values
live in `res://Data/balance.tres`; this doc explains the shapes and why they were chosen.
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

The sponge is the only thing that removes it, and it pays Hearts on grime *actually removed*
— scrubbing a clean skeleton earns nothing, which is the kindness-side twin of the
resting-contact cooldown on the damage path.

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

## Dollars

The third currency (docs/decisions.md D31). Earned from the two events that mark a player being
*present* — a kind act and a knockout — and spent only on cosmetics.

```
kind act:  dollars_per_kindness x value        (the same value the Hearts payout is computed on)
knockout:  dollars_per_knockout                (flat: the climax is the event, not its size)
automation / offline: x dollars_idle_efficiency
```

Three deliberate differences from Bones and Hearts:

- **No multipliers.** Dollars do not go through `payout_for` — not mood, not augments, not
  mastery, not prestige. They are a count of things done, not a yield, which is what stops
  cosmetics from arriving in a flood the moment the income multipliers stack up.
- **Idle earns a fraction** (`dollars_idle_efficiency`, first draft 0.15). The only place in the
  economy where idling is deliberately worse, and the reason it is here rather than anywhere
  else: cosmetics are the reward for being at the keyboard.
- **They buy no power, ever.** Enforced as a rule on content, not as code: nothing priced in
  Dollars may carry an `effect_key`, an `automation_rate`, or any other field the payout pipeline
  reads. A test asserts it, because the day one cosmetic quietly grants +2% Bones is the day the
  two-currency spine has a bypass.

Knobs live in `BalanceData` with the rest: `dollars_per_kindness`, `dollars_per_knockout`,
`dollars_idle_efficiency`.

## Contracts

Rotating objectives keyed on `EventBus.contract_event`. Three daily slots and one weekly, rolled
from a seed derived from the day index rather than from chance — a board reshuffled on every boot
would let a player reroll until they liked the offer.

Rewards are **Ectoplasm only** (`docs/decisions.md` D18). A daily that paid spendable currency
would set the pace of the shop ladder by the calendar instead of by play.

Two things deliberately do not count:

- **Sustained kindness is not a contract event.** A placed boombox flushes twice a second
  forever; on the shared `kindness` key it would finish a 150-target contract in seventy-five
  seconds with nobody at the keyboard. Contracts count *acts*.
- **Prestige does not reset the board.** Contracts are a real-time hook, not a run-scoped one,
  and resetting them would let a player farm a daily by reincarnating.

## Reincarnation (prestige)

```
ectoplasm_total = floor( cbrt( lifetime_earnings / 1e12 ) )
gain_this_reset = ectoplasm_total − ectoplasm_already_held
prestige_multiplier = 1 + 0.01 × ectoplasm_held
```

Cube-root on **lifetime** earnings, +1% per point — Cookie Clicker's ascension curve, chosen
because doubling your prestige requires roughly **8×** the previous run. That's the well-tested
middle ground: Realm Grinder's square-root needs only 4× (resets too often), Egg Inc's 0.14
exponent needs 128× (resets feel rare and precious). Lifetime-based rather than run-based
because it rewards going further each time and tolerates a player who idles across a reset.

Pacing target: first Reincarnation available after ~60–70% of first-run content; early resets
5–15 minutes apart, late-game 30–60.

Each reset re-rolls Bonehead's **personality**, which swaps his mood curve (see
`game-design.md`) — the same ectoplasm number, a different optimal rhythm. A personality is
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

**A reset keeps** ectoplasm, lifetime earnings (the cube root is taken of those, so resetting
must not touch them), the prestige count, the offline cap and the contract board. **It wipes**
both currencies, every unlock, every augment level, every exclusive choice and all mastery.

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

1. All knobs live in `res://Data/balance.tres` — never hard-code a rate.
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
