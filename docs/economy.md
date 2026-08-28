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

**Kindness → Hearts.** Two shapes:
- *Event* kindness (a pet, a caught baseball, a slice of pizza): flat value per event, with a
  combo multiplier on repeats inside a short window.
- *Sustained* kindness (boombox, hot tub, chocolate fountain): Hearts per second while active.

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
├─ TIER 2 — pick ONE (exclusive_group), needs 3+ T1 levels and Mastery 10
│    ├─ e.g. Buckshot  +3 pellets, −30% each
│    ├─ e.g. Slug      one projectile, ×4 knockback
│    └─ e.g. Beanbag   0 damage — converts damage payout into Hearts
└─ CAPSTONE — AUTOMATION, costs Hearts, needs Mastery 25 + Reincarnation ≥ 1
```

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

Each rank also drops a point into the shared **Mastery Pool**. Pool checkpoints
(10 / 25 / 50 / 100 / 200 points) grant global bonuses — +2% all income, −5% all augment costs,
+1 item limit, and so on. The pool is what makes breadth worth pursuing; without it, players
correctly conclude that spreading mastery is wasted.

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
`game-design.md`) — the same ectoplasm number, a different optimal rhythm.

## Offline earnings

```
elapsed  = clamp(now − last_played, 0, cap_hours × 3600)     # negative deltas → 0, always
earnings = automation_rate_per_second × elapsed × balance.offline_efficiency
```

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
2. Debug builds log every payout and purchase to a local CSV.
3. Economy maths is unit-tested (`tests/run_tests.gd`): cost curves, bulk-buy, max-affordable,
   prestige, offline clamping. These are pure functions with no excuse for being wrong.
4. Retune against real playtest CSVs, not intuition.
