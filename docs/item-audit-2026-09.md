# Item audit — 2026-09-25 (D59)

Every item in the catalog, used one at a time on a desk of its own by
`tests/integration/item_check.tscn`, the way a player uses it, and then again with one level of
each of its augment keys and mastery 50. What it found is below, **findings first**. The
per-item table the suite writes is `user://item_check_report.md`; this file is the summary a
person reads.

```bash
"$G" --headless --path "$P" res://tests/integration/item_check.tscn          # ~6.5 min, 106 items
"$G" --headless --path "$P" res://tests/integration/item_check.tscn -- --only=grenade,fist --trace
```

**The count:** 106 items, 212 runs, 3,450 checks. 84 items pass every check. 22 carry an open
finding below, which the suite reports as `known` rather than failing (the `KNOWN` table at the
top of `item_check.gd`, 97 checks, each naming its finding). A known finding that stops
reproducing fails the suite, so the table cannot outlive the bug. Five item bugs were fixed on
the way, each with a check in the suite that fails without the fix, plus two in the tests and
tools. No body went faster than 6,277 px/s (him, off a demolition charge); the ceiling is 15,000.

---

## Fixed in this pass

| | What was wrong | Root cause | Regression check |
|---|---|---|---|
| X1 | A spent grenade left for its last half-second as an invisible projectile — **6,878 px/s** measured, still colliding with everything on the desk | The blast area masks the item layer, so it caught the charge that owns it at zero distance, where `ExplosionUtil` falls back to straight up at full `max_force`. Fifteen explosives; the concussion charge's arithmetic is 18,571 px/s, past the 250 px/frame a wall can hold | "the spent casing stays where it went off" |
| X2 | The nail bomb, cluster bomb and napalm charge never counted as a `use:` for the contract board, and a primed one left him staring at a charge that had already gone off | `ClusterBomb.explode()` replaces the base method instead of extending it and dropped its two emits. `fuse_lit` is a hold with no refresh, so nothing ever released it | "the detonation counts as a use", "the fuse he was watching is let go" |
| X3 | Every explosive's third node ("Heavier Casing" and fourteen more), the trampoline's "Steel Frame" and the fan's "Cast Base" sold a `mass_mult` that nothing read — 17 items | The Weight augment was applied by `WeaponBase` only. Moved to `BaseDraggable`, so every body wears its mass node; `ItemSpawner.refresh_augments` re-applies it to everything on the desk | "`mass_mult` is read by something: x1.08" on all 17 |
| X4 | A hornet's or goose's body-check ignored the "Sharper Sting" / "Meaner Streak" the player had bought: **x1.000 where the data says x1.150** | `Buddy._attribute` billed any `BaseDraggable` that is not a weapon or a throwable at a flat 1.0. Animals and turrets now bill at their own `effective_damage_mult()`, the one their blows and shots already carry | "every hit carries its damage multiplier" |
| X5 | A mine he was put down on went off **for 0 damage**; the oil drum the same | It fired the moment any part of him overlapped the blast area, and the blast falls off from its centre to *his* centre — so on the rim, at or past the radius, at almost exactly no force. It now waits until his centre is inside `trigger_fraction` (0.7) of the radius | "the blast hurts him" on the mine and the oil drum |
| X6 | `ui_check` "jobs badge" failed on 2026-09-25 and passed on 2026-09-07 | The contract board is a seeded draw by date. Today's draw put `daily_damage_burst` and `daily_damage_double` beside `daily_damage`; one emit finished all three, the badge read "3", one claim left it lit. The badge was right; the test now owns its board | the suite itself, 487/487 |
| X7 | `ui_shots` 03-toys-kind showed the Care tab lit over the Boombox | Not a shop bug. The tool asked for Care and selected an item M3.7-B moved to Mood; `ui_motion_shots` clicked three rows that had left the Care list. Both read the drawer off the item's data now; the one production caller (`PanelLayer._on_show_item`) was always right | `ui_check` "shop drawers" |

---

## Open — high

### F1. A hit that parts within one physics step is never billed

**Fixed in D64:** billed from his own momentum when the engine does not report it.

**Affects:** the fist (the starter power), any thrown ball or item that bounces off him, the
trampoline's landing, the raccoon's thrown props. Measured: the fist ran through him and launched
him at **1,653 px/s with nothing billed**; a bowling ball thrown into him at 900 px/s, **nothing**;
a bat thrown at the same speed was billed (1,189) only because it stayed pressed against him for
a second frame.

**Root cause.** D7 measures damage from `PhysicsDirectBodyState2D.get_contact_impulse()`. In
Godot 4.7 the contact list a body sees is built before the step is solved, so each contact carries
the impulse of the *previous* step — zero on the frame two bodies first touch. If they are still
touching next step, the previous step's impulse is reported and he is billed; if the collision
threw them apart, the impulse is never seen. Resting and pressing contacts (a swung weapon on
the drag joint, a dropped mace that stays on him, the floor) are fine, which is why every melee
weapon passes and nothing noticed. The per-step trace is in D59.

**Recommendation.** Keep D7's receiver-side principle and add the missing half: when a collider
appears in his contacts with a reported impulse of zero, remember his velocity; on the next step,
if that contact is gone, bill `mass × |Δv − g·dt|` to it through the same floor and cooldown. Owned
by whoever owns `Buddy` — this is the damage model, and the balance of every thrown thing moves with
it. The suite's `F1` lines will fail the day it lands.

### F2. Five of eight turrets deal no damage (since D54)

**Affects:** pellet turret, nail gun, rail gun, laser lattice; the flamethrower almost always.

**Root cause.** D54 moved the impact `IMPACT_INSET = 18` px back toward the muzzle so the shot has
a direction. `point_blast` falls off with the square of distance from that point to his centre,
so every shot now lands at 18 px — and for most turrets that is most of the blast radius. The
receiver discards anything under `min_damage_impulse` (350):

| turret | `blast_force` | radius | force at 18 px | billed? |
|---|---|---|---|---|
| pellet turret | 900 | 30 | 144 | no |
| nail gun | 420 | 18 | 0 | no |
| flamethrower | 400 | 44 | 140 | only when the 16 px spread lands closer |
| rail gun | 7,200 | 22 | 238 | no |
| laser lattice | 1,300 | 26 | 123 | no |
| swarm launcher | 1,800 | 34 | 399 | yes |
| tesla coil | 2,400 | 64 | 1,245 | yes |
| mortar | 9,000 | 110 | 6,300 | yes |

They fire, they draw a tracer from the muzzle and they shove him; they pay nothing, earn no
mastery, and their automation capstone (mastery 25) can never be reached.

**Recommendation.** Balance and model, so not fixed here. Either inset by a fraction of the radius
(a quarter keeps 56% of the force: pellet 506, rail 4,050, laser 731 all clear the floor) or bill
the target the undiminished `blast_force` along the shot and keep the falloff for the collateral.
The nail gun and the flamethrower (420 and 400) sit barely over the floor even at zero distance,
so they need their numbers raised under either model.

### F3. The gorilla cannot walk, and the raccoon crawls

**Affects:** gorilla (45,000 Bones), raccoon (14,000). Put down across the desk from him, the
gorilla closed **6 px in 2.5 s** and the raccoon 19 px; the goose and the hornets arrive.

**Root cause.** `NpcBase._steer` pushes with `mass × steer_gain × (desired − v)`, and
`seed_m36_npcs.gd` gives every animal a friction of 0.95 so nothing skates. The floor's friction
is `0.95 × mass × 980`, so an animal walks only if `steer_gain × move_speed > 931`:

| | `steer_gain × move_speed` | walks? |
|---|---|---|
| gorilla | 2.6 × 105 = 273 | no |
| raccoon | 5 × 190 = 950 | at ~4 px/s |
| goose | 6 × 330 = 1,980 | yes, at about half speed |
| hornet | flies — no normal force, no friction | yes |

Set down within reach, both attack correctly (the gorilla's slam and the raccoon's thrown bat are
both verified). A gorilla spawned more than 100 px from him stands there for its 90 seconds and
leaves.

**Recommendation.** NPC behaviour belongs to the brain stream. The smallest honest fix is to add
the friction the walker is standing on to its steering force (`+ friction × mass × g` along the
walk, grounded only), which keeps the heavy, planted feel the friction was chosen for.

---

## Open — medium

### F4. The pulls lose to his floor friction

**Affects:** black hole charge, implosion charge, gravity vortex. Standing on the desk he is held
by `1.0 × 3 kg × 980 = 2,940 N`. The black hole pulls with `6,000 × (1 − d/320)²` — 2,208 N at the
126 px it was put down at, so it moves him only inside ~96 px; the implosion charge's 3,200 never
exceeds his friction outside ~12 px; the vortex's 2,400 at the eye never does. Measured: **126 px
before the pull, 126 px after** (black hole), 197 → 197 (vortex). They do gather airborne and light
things, which is not what "drags him and every loose thing on the desk into one spinning knot" says.

**Recommendation.** Tuning: scale the pull by the body's mass (an acceleration, as gravity is), or
raise the forces. A balance call.

**Fixed (D65).** All three pull by the body's own mass times `pull_accel`. Measured: black hole
126 → 71 px (stopped against the charge), implosion 132 → 68, vortex 197 → 11; a 0.3 kg prop in the
vortex 155 → 42 px, peak 561 px/s (it was 155 → 106 at 1,137). Checks: "gathers", "pulls", "light".

### F5. The gravity vortex and the desk fan earn nothing under their own name

Neither class bills anything: the vortex's damage is the collisions it causes (billed to the floor
and the props), and the fan's is none. So each sells a payout node and a damage node that nothing
can read, earns no mastery, and has an automation capstone gated on mastery 25 that **can never be
bought**. (The fan's "Higher Setting" reads as wind strength; a damage key is the wrong key for it.)

**Recommendation.** Design: attribute vortex-driven collisions to the vortex, or give both a tree
that means something for what they do (pull strength, wind strength) and a capstone not gated on
mastery.

**Fixed (D65), both halves.** While the vortex's pull or the fan's wind is on him, an impact with
the world is billed to that item instead of to `world` (`Buddy.claim_impacts`) — who is billed,
never whether, so nothing pays twice. The vortex earns and ranks end to end (a slam into the desk:
10.5 Bones plain, 46.6 upgraded). The fan's "Higher Setting" is wind strength (`wind_mult`, ×1.10
measured on a probe). The fan's claim is checked directly; the suite's own drop bounces apart inside
one step, so its payout waits on F1 and carries `~F1` lines.

### F6. The trampoline returns less than it was given

**Fixed in D64:** lands 722, leaves 1,062, with a `max_launch` ceiling.

Measured: he lands at **722 px/s** and leaves at **303**. `Trampoline._physics_process` reads the
falling speed after the landing has already been solved, so `falling × bounce_gain` is almost
always under `minimum_launch` and every bounce is the 320 px/s minimum. "Everything that lands on
it leaves faster than it arrived" is never true. The landing itself is also unbilled (F1), so it
earns nothing and its tree is unreachable.

**Recommendation.** Read the arrival speed from the frame before contact. That makes the ×1.55 real,
and a ×1.55 per bounce is a runaway — so it needs a ceiling (`max_launch`) in the same change. The
idle brain's `ROUTINE_BOUNCE` was tuned around the current behaviour.

### F9. The beach ball earns nothing

**Fixed in D64:** a Hearts catch now; the bowling ball stays a Bones toy on the swing floor.

It is a `WeaponBase` filed in the Play drawer, which is the kind side, so `Buddy._min_impulse_for`
asks a 0.4 kg ball for the 1,500 fall-floor impulse — about 2,200 px/s. Dropped and thrown, it
never pays; its payout and damage nodes and its "Beach Day" capstone are unreachable. The
description ("it hurts nobody") agrees with the physics; the shop and the idle brain's `ROUTINE_BOP`
("pays Bones off the contact") do not.

**Recommendation.** Decide what it is: a Hearts toy (`FriendlyBase` with a catch, like the tennis
ball) fits the description.

---

## Open — low

- **F7. Two cooldown nodes with no cooldown.** The fist's "Faster Hands" and the vortex's "Faster
  Collapse" multiply `cooldown_seconds`, which is 0 on both. The fist's could mean follow speed.
  **Fixed (D65):** "Faster Hands" is the fist's chase speed (`speed_mult`, 1,997 → 2,116 px/s),
  "Faster Collapse" the vortex's pull (`pull_mult`, ×1.10 on a probe).
- **F8. Seven consumables sell a cooldown.** Pizza, cup of tea, donut box, ice cream, noodle bowl,
  birthday cake and party popper are `consume_on_use`: each pays once and is gone, so the gap their
  third node shortens never runs. A kindness-value or payout node would mean something.
  **Fixed (D65):** the third node is how much a helping lifts his mood (`mood_mult`), checked on
  every act to 1e-4 against `MoodMath`.
- **The donut box says "Six. He is going to have all six."** It is consumed on the first contact.
  **Fixed (D65):** six helpings of 5, half a second apart (`FriendlyBase.servings`).
- **Fixed in D64.** **The fist's damage node counts twice.** `FistPower.fire` scales the punch impulse by
  `effective_damage_mult()`, and the receiver scales the damage by the fist body's multiplier
  again, so one level is ×1.32 on a punch, not ×1.15. Balance call.
- **The nail gun and the flamethrower** barely clear the damage floor at zero distance (420 and 400
  against 350) — see F2.

### F10. The fortune ball's "Looser Dice" does nothing for four levels

**Affects:** the fortune ball's third node (`cooldown_mult`, x0.94 a level), sold as fewer shakes
before it can be read. Measured at level 1: ready after **4 reversals plain and 4 upgraded**.

**Root cause.** `MagicEightBall._shake_step` counts a shake as one whole reversal and the ball is
ready at `shakes_needed x 0.94^n` of them. That is 3.76, 3.53, 3.32 and 3.12 for levels 1–4 — all
still four reversals — then 2.94 at level 5, which is three, and still three at level 10 (2.15).
Across its ten levels the node takes off one shake, once. Any whole-number threshold moves with a
6% step only from 17 shakes up.

**Recommendation.** Design. Count a shake continuously (each reversal worth its vigour, so 6% less
shaking is felt as 6% less), or give the ball a node it has a continuous measure of — a yes a
little more often, say. Not fixed here: either is a change to how the toy feels.

---

## The held guns and the fidget toys (D56, D57)

Added to the suite on 2026-09-25, after the pass above: until then all twelve failed it by name
("no driver for HeldGun"). Each is now driven the way the grammar says — left carries, right
acts, Shift+right bins — and checked twice like everything else.

| Item | Driven | Verdict |
|---|---|---|
| Revolver, SMG, pump shotgun, hunting rifle, blunderbuss | grabbed, aims itself (0.25–0.35 s), tap, refused tap, second shot or a held stream | pass. Bones through the pipeline at `shot_mult`; tracer from the muzzle; he cowers; Steady x0.92, measured mass-normalised. Thrown into him, **not billed**: in his contact list one frame and gone (`~F1`) |
| Water pistol | as above, on a filthy skeleton | pass. Pay exact to the squirt; no threat, no hit, no act; thrown into him, bills nothing |
| Bubble blaster | as above | pass. Every bubble reaches him as one act of exactly `1.2 x value` |
| Bubble wrap | left-tap a bubble, right-stroke a run, regrow, dropped on it | pass. 2 a pop, exact; "amused"; regrow x0.94 |
| Stress ball | hold right to squeeze, throw at him | pass. Squeeze and catch exact; squashed face past 0.6; "catch" |
| Fidget spinner | right-swipe an arm, watch, run down | pass. Trickle exact to the tick; "entranced"; settles on a third, no frame at rest |
| Fortune ball | right-tap unshaken, shake, read until yes | pass but **F10** |
| Jack-in-the-box | right-circle the crank twice, right-tap the lid | pass. Pops at the tune's end, "startled" then "laugh", 30 exact; Shorter Tune x0.94 |

---

## What the suite checks, per item

For every item, on a fresh save and a fresh 1280x720 stage (the game's own `WorldBounds`, a real
`ItemSpawner`, one buddy, nothing else), bought through the shop's own path:

- **Used as a player uses it**, by synthetic input at real positions: weapons grabbed by the grab
  region and swung through him; explosives primed with a right-click while held and dropped beside
  him (the fuse skewed, its length reported); the mine put down and him carried onto it; the sticky
  bomb thrown at him; powers equipped from the shop and clicked on him (the beam held, the minigun's
  trigger held, the vortex held beside him); kind items dropped on his head, thrown at him, rubbed
  on him, or him carried over and put in them; generators left on the desk; turrets put down in
  range; critters put down across the desk; held guns grabbed, left to aim and fired with the right
  button; fidget toys worked through their own click zones (tapped, stroked, cranked, squeezed,
  shaken). Drivers are chosen by **exact script class**; a class with no driver fails by name.
- **The contract:** its own currency paid, **through the real pipeline** — every payout is checked
  inside Economy's grant against `payout_for(1, id)` times the event's base, so a multiplier that is
  skipped or doubled anywhere shows; none of the other currency; the family's contract event
  (`use:<id>` for harm, `kindness` for kind acts and never for a trickle, `pet`, `bounce`); mastery;
  every hit's multiplier read back off the hit; the effect drawn (tracer from the muzzle, bolt,
  beam and heat, the missile's blast on the marked spot, a swirl, hearts off him on entry, ambient
  life); a trickle paid to the frame (`rate × value × time`); what its switches promise (a catch
  pays nothing laid on him, food is eaten, a duck is not, a fountain runs out); for a toy, the
  row his face answers each of its fidget events with; for a gun, that he cowers while a harm one
  is on him.
- **Safety:** it and he stay inside the arena, no NaN, no speed past a wall's thickness per frame,
  nothing pushed to the error log (a `Logger` catches every `push_error` and `push_warning`), no
  orphaned nodes, nothing of it left once it is gone, Shift+right-click bins it.
- **Augments:** one level of each key and mastery 50, then each key measured against the plain run
  — damage off the hits, value off the acts and trickles, mass off the body, the gap off the item's
  own clock — and the aura it should wear. A key nothing reads is reported as a placebo.

What it does not cover: feel (swing weight, the look of an effect), the idle brain's use of toys
(loop_check), multi-collider geometry (the weapon-colliders stream), and anything a person has to
see (`ui_shots`, `audit_shots`).
