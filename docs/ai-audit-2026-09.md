# AI audit — 2026-09-25

Every mechanic that makes Bonehead or the things around him act on their own, tested one at a
time on a desk of its own (`tests/integration/brain_check.tscn`, D60) and graded by what can be
seen: the face he wears, the tag he plays, how far his drawing moves, where he ends up, who paid.
The owner's brief: "comprehensive isolated testing of each object and mechanic, including all ai
mechanics of the character and see if they actually operate as expected." Assumed some did not.
Eleven did not.

**Baseline after the fixes:** brain_check 305 / 0 in about six minutes (`-- --quick`, one toy
per routine, is about five); unit 242; loop 606; ui 485 of 487 (the two date-dependent Jobs
badge assertions belong to another stream); boot smoke clean. No save schema change, no
`balance.tres` change, no scene edit.

The one-paragraph version: the expression brain's table, arbitration, timing and Focus gates are
sound — every one of the 44 rows reaches the art as it declares and lets go completely. What was
broken was the wiring *between* systems: a kindness signal that meant two things, a face override
that meant two things, a push tuned for the floor applied in the air, a steering law with no
friction term, a damage number read off a falloff. None of those can be seen from one file, and
none of them failed a test, because every existing test called the handler directly.

---

## Findings, by severity

### Fixed — high

**1. One generator anywhere on the desk kept him in `cared_for` for the rest of the session.**
Ten items (boombox, bubble machine, chocolate fountain, fairy lights, fish tank, hot tub,
houseplant, lava lamp, record player, wind chimes) bank their *placed* rate where they stand and
flush it as `kindness_sustained` every half second, forever. `ExpressionBrain` held `cared_for` on
every flush. Everything at or below that row's priority — the mood face and idle, blink, fidget,
yawn, sleep, every idle-brain routine look — was masked for as long as a generator was out.
*Root cause:* `kindness_sustained` carries both "being kind to him" (a sponge, a hot tub he is in)
and "income" (a generator's placed rate), and the brain could not tell them apart. *Fix:*
`cared_for` requires the kindness to land within 24 px of his rect (`a9e0f5b`).

**2. The idle brain's routines were invisible, and the first interruption ended them.** Measured
on each toy's own row (`soaking`, `dancing`, `scrubbing`): 0 of 96 frames. The toy he was playing
with paid its own trickle, which replaced the routine row at equal priority; and a landing on the
trampoline or a rank-up ended `bouncing` for the rest of the dwell because nothing handed back.
*Root cause:* no notion of a routine being his background. *Fix:* his routine toy's trickle is the
routine; `_end_beat` resumes the routine hold after whatever interrupted it; a trickle can no
longer cut a one-shot of its own rank short (the last flush off a toy binned from under him had
been replacing the `toy_gone` surprise) (`a9e0f5b`).

**3. The gorilla never moved; the raccoon crawled at 4 px/s; at Focus Off no animal moved at all.**
*Root cause:* `NpcBase._steer` is a bare P-term on velocity against a floor that resists with
about `m g μ` (μ 0.95). The gorilla's gain of 2.6 made 7,100 N against 24,200 N of friction. This
is the defect plan-movement-hitboxes §1(d) fixed in the idle brain's walk; the NPC never got the
fix. At Off (speed × 0.3) the goose could not beat friction either, so the D21 "Off keeps
earning" contract failed for every walker. *Fix:* friction feed-forward on the ground, clamped at
2.5 g (`be452a9`). Crossing speed from rest, measured: gorilla 86 px/s (authored 105), raccoon 126
(190), goose 220–250 (330).

**4. Five of eight turrets have dealt no damage since D54.** D54 moved the impact 18 px off his
centre and billed him what the squared falloff left there. Against radii of 18–30 px that is under
the 350 damage floor. Shots landed before the fix: pellet turret 0/2, nail gun 0/2, flamethrower
0/2, rail gun 0/2, laser lattice 0/6 pellets, swarm launcher 2/12; tesla coil at 16.7 of 32.4,
mortar 164 of 234. *Fix:* a pellet that lands on his silhouette is worth its whole `blast_force`;
the push is D54's splash, unchanged (`12ec24f`). Every turret now lands every shot at design
damage (the mortar at the 200 per-hit cap). **Overlaps the item-isolation stream** — if it fixed
this too, keep one.

### Fixed — medium

**5. The Masochist never grinned at a bat.** `react_to_hit` passed the category face as an override
and weapons map to `shocked`, the generic face; `_personality_face` treats any override as more
specific than the tell. Masochist, Diva and Stone showed their hurt face only on heavy hits.
loop_check called `react(&"hit")` directly and could not see it. *Fix:* a generic category face
is not passed as an override (`60f2243`).

**6. A ball dropped from the shop onto his head cancelled its own offer.** The shop spawns where
he stands; the ball lands on him and pays a catch; `_on_kindness_given` read that as the player
arriving and put the wait back to 25 s — the owner's "spawn a ball and watch him play with it",
again. *Fix:* for the six seconds he is given to wait, the offered toy's own arrival is part of
the offer (`a4b65ad`).

**7. He never went to the beach ball or the bowling ball.** `_routine_for` gives them a bop;
`_appeal` quoted anything that is not a `FriendlyBase` at zero, and zero is skipped. *Fix:* the
lowest non-zero appeal (`a8298c7`). See open finding C: the bop does not pay for either.

**8. A hop at a box hung him on its side.** The walk pushes with up to 2.5 g, including a
feed-forward of his weight meant for floor friction. Airborne and pressed into a vertical face,
friction on that normal out-pulled gravity: on a 40 px box he rose 32 px and stopped dead in the
air until the stall gave up. *Fix:* in the air the push is ≤ 0.5 g with no feed-forward, and the
lean likewise (`8e198c4`). The step is now reached on the first climb.

**9. An animal whose time was up walked into him for fourteen seconds.** `_begin_leaving` chose the
nearer window edge, which is usually the one behind him (the last blow knocks him that way). Every
critter shoved him along the floor for the whole `LEAVE_TIMEOUT` and then vanished mid-desk.
*Fix:* it leaves by the side he is not on (`1afdbe7`). Hornet 3.3 s, goose 2.8, raccoon 5.1,
gorilla 10.9 — all off an edge.

**10. The raccoon's throw spent itself on the raccoon.** What it throws is what it has just shoved
across the desk, pressed against it when the velocity is set: 900 px/s left at about 200 and
dropped at its feet. *Fix:* a 0.4 s collision exception between thrower and thrown (`770dc56`).
The bowling ball now leaves at 960 px/s and lands for 21 damage.

### Fixed — low

**11. The reunion never reached its happy face.** The row names `tail_face: happy` and no `tail`,
and a tail face is entered at `seconds - tail`. *Fix:* a 0.4 s tail (`06be9a6`).

### Fixed in D70 — the loose ends (2026-09-26)

Every open item below except C and the smaller notes in G and H is fixed, each with a check that
fails without it; the numbers are in each entry and in docs/decisions.md D70. Two more came from
the D64 and D66 notes rather than from this audit:

**12. He never went back to the Newton's cradle or the pull-back car** (brain_check's two
failures at 208a8d1). Both quoted zero appeal while running — the cradle while it swung, the car
while it drove — and zero is the brain's "nothing to do here", so a toy he set going on his last
tick at it was never chosen again. *Fix:* a steady appeal; `idle_use` declines while busy, as every
D57 toy does (`2e19807`).

**13. His own bouncing billed Bones to an empty desk.** Since D64 billed the mat's landings, about
17.6 damage a second, on top of the Hearts the brain pays for the same bounce; the bowling ball
he bops onto his head billed too. *Fix:* while the brain has him at a toy, the toy and the world
are his own play and are not hits (`Buddy.begin_own_play`); his own bounces no longer count on
the "bounce him" board. The trampoline billed 2 hits in brain_check's 1.6 s window and 1 coming to
rest; 0 now (`1aba5e9`).

### Open — recommendations for the owner

**A. At Focus Off, 26 of the 33 routine toys earn nothing (medium).** Off skips the walk and marks
him `playing` where he stands. The trampoline and the nine generators are brain-paid and still
earn; every soak, scrub, nibble and bop toy pays only for real contact, which does not happen —
yet the dwell runs and the toy is then cooled for 60 s. The idle brain's header promises Off keeps
the income (D21). Either the brain pays the toy's presence rate on its behalf while Off, or at Off
he only chooses brain-paid toys. A design call, not a bug fix.
*Fixed (D70):* the first of the two. At Off the brain asks the toy to pay for his presence, as
itself and down its own roads (`FriendlyBase.pay_presence`), and a jack he wound laughs out of
earshot. Every routine toy, him 600 px off: 19 of the 40 that pay Hearts earned within a dwell
at Off; 40 of 40 now (`23537cb`).

**B. He leans against furniture rather than getting in (medium).** 0 of 9 soak toys ended with him
on or in them — beanbag, hot tub, recliner, hammock all included. "Reached" is rect overlap plus
20 px, the playing branch then leans, and the toy pays on side contact. That is what
plan-movement-hitboxes §10 designed, and the comments in `idle_brain.gd` still speak of climbing
into the tub. If he should sit *in* things, SOAK needs "reached" to mean on top.
*Fixed (D70):* he is let in. The toy hops him over its edge, the two pass through each other,
and he is pinned in a seat sunk into it (0.45 of its height, never over 0.4 of his), the toy
drawn over his legs; he hops out over the side when the dwell ends. 9 of 9 now, sat in for 39-61
of the 96 frames after arriving; `tools/soak_shots.tscn` shows each one (`50cc3ee`).

**C. Neither weapon ball can pay (low).** The bop lifts a ball 34 px beside him; toys are kind-side
and need the 1,500 fall floor. A 0.4 kg beach ball could not clear even the 350 swing floor. They
are now destinations of last resort, played with for their own sake. If the bowling ball should
pay, note that bopped onto his head it is ~8,000 of impulse — half a knockout a bop.
*Settled by D70, not changed:* his own play mints no Bones, so the bowling ball is played with
for its own sake at any Focus, as brain_check notes. The beach ball is a Hearts catch since D64.

**D. The gorilla's slam throws him at ~4,640 px/s (medium).** 26,000 × falloff ≈ 14,000 impulse on a
3 kg body — past the 4,500 px/s the drag joint is allowed (D54) and twice the fastest throw D54
measured. Damage is capped at 200 by `max_hit_fraction`; the push is not. The mortar's splash is
~1,850 px/s. Recommend capping the push, not the damage.
*Fixed (D70):* the slam's push is capped at 2,500 px/s (`slam_max_speed`, the blunderbuss's 2,536),
the damage is not: 140.1 from 14,015 as before, peak 4,636 -> 2,477 px/s. brain_check fails any
animal that throws him past the drag's backstop (`3b4e7d7`).

**E. Animals also hurt him by bumping into him (low).** Contact impulses from NPC bodies pay like a
weapon's: hornets ramming at speed, a goose arriving. They bypass the wind-up tell and the attack
period. D7-consistent physics; if every blow should be telegraphed, treat `NpcBase` contacts as
kind-side in `Buddy._min_impulse_for`.
*Fixed (D70), as recommended:* an `NpcBase` body faces the fall floor. The goose's bump before its
tell is gone, and a grapple is its 8 shakes rather than 16 hits; every blow is untouched
(`57728e3`).

**F. A toy outside the window is still a destination (low).** He walks into the wall, stalls eight
seconds, gives up, and retries every cooldown. `WorldBounds` keeps toys in the window, so it takes
a teleport or a tunnel. A filter on the visible rect is one line, but loop_check's whole desk sits
outside its 64x64 headless root viewport, so it was left for a change that moves that suite into a
SubViewport as this one does.
*Fixed (D70):* the brain asks its walls, not the window (`WorldBounds.arena()`, by group in its own
viewport); with no walls there is nothing to filter, so loop_check's desk is untouched (`259ffc7`).

**G. Smaller presentation notes (low).** The Nervous personality's early flinch preempts the
`fuse_lit` hold, so it loses the gasp-and-lean for the whole fuse. The rubber duck is a *nibble*
toy (he eats it) because `_routine_for` falls through to `hearts_per_contact`. With nothing loose
to throw, the raccoon's melee blow lands from its full 260 px reach. Hornet swarm children are
freed wherever they are when the lead hornet reaches its edge. `yawn` has no deadline of its own
and is noticed on the next ambient tick, up to nine seconds late. A purchase that completes a
milestone shows `claimed` a moment later, which is right.
*Fixed (D70):* the Nervous one's threat holds wait behind the flinch and take over after it
(`11c1d10`); he eats only food, and the duck is bopped (`3343002`). The rest stand.

**H. Two engine facts worth knowing (info).** `BaseDraggable.get_interaction_rect()` ignores a
collider's offset, and `IdleBrain` uses it for toys: the trampoline's rect sits 24 px below its
mat. `Buddy.is_grounded()` is stale while he sleeps. Autonomous damage (turrets, critters, the
trampoline) banks `dollars_per_hit` at full rate while automation banks at idle efficiency —
worth a look against D31's "Dollars count acts".
*Checked (D70), recorded, not changed:* by D31's letter it is right — every damaging hit pays the
flat Dollar amount. By its point it is not: "Dollars are earned by being present", and automation
and offline pay at `dollars_idle_efficiency` (0.15). A pellet turret firing every 1.1 s banks about
3,270 Dollars an hour at an empty desk, six times what an automation tick banks (1.0 x 0.15 a
second, 540 an hour); the trampoline no longer adds to it (D70's own play). The kind side has the
same leak by a different road: the toys he nibbles and bops pay as acts (`kindness_given`), so
their unattended pay counts on the combo, the contract board and the Dollars. A balance call for
the owner: bank an autonomous source's hits at `dollars_idle_efficiency`, and route a toy's pay
during his own routine through `kindness_sustained`.

**I. Melee animals cannot reach him in the furniture (low, new in D70).** Sat in a beanbag his
middle is about 116 px from a goose standing at its side, past the goose's 78 px reach, so it
waits there until the dwell ends and he hops out; turrets and thrown things still reach him.
brain_check's "a goose hitting him does not stand him down" now finds him at a boombox. Measuring
an animal's reach to his nearest edge rather than his middle would change every critter's pacing.

**J. Timing flakes seen while running the suites (info).** Three, all the suites' own, all fixed.
The critters' tell read 0.50 s once and 0.30 once for a 0.35 s wind-up: it paired a swing with the
nearest wind-up, which could be an earlier one the animal had abandoned, and measured on the wall
clock while the wind-up runs on the engine's; it takes the latest wind-up where the animal swung
from now, on the engine's clock. The personalities' "moves his
mood by the same amount" read real-time mood decay across the hit and failed once at a 0.23
spread against a 0.1 tolerance; decay is held still across the reading now, and all twelve read
-18.0000 exactly. And item_check's trickle "at exactly its rate" failed about one run
in five (a beanbag +0.031 on 0.782) because contact time was counted only on the ticks a driver
awaited, and a long frame runs two physics ticks inside the one process frame `_expect_trickle`
waits; it is counted on every tick now, and held through three runs alone and two under load.

---

## What was measured

| Mechanic | Verdict | Numbers |
|---|---|---|
| Reaction table | pass | 44 rows: face, tag, speed, amplitude, duration, tail, lapse all as declared |
| Arbitration | pass | 5 priority levels, every pair both ways; equal preempts; ambient never over ambient; damping extends without rewinding |
| Real triggers | pass | all 44 rows caught live off the signal the game fires them on, somewhere in the run |
| Focus Off | pass | reactive rows play with 0.000 px of motion; S/N/G/C rows refused; timer stops; no ambient in two skewed minutes |
| Attention / arousal / away | pass | arousal bump = priority/40 × 0.5; half-life ratio 0.500; gaze ±2.0 px inside his rect, 0 at Subtle; away clock exact |
| Wires | pass | 24 connects in `_ready`, every one proven by a real trigger |
| Idle start | pass | 24.5 s watching, 25.5 s off; offer 5.5 s watching, 6.5 s off; clock moves, never backdated |
| Every routine toy | pass | 33 toys walked to (~114 px in ~1.0 s, 0 hops, 0.0° tilt, 0 hits); the right party pays; leave at 20 s, 60 s cooldown, come back |
| Interruptions | pass | grab and bat stand him down; 12 autonomous sources and his own toy never do |
| Geometry | pass | 40 px step reached in 1 climb; 300 px shelf given up after 3; binned toy ends the trip; window shrink contains the toy |
| Walking | pass | 115.7 px/s both ways (derived 116.7); faces the way he walks |
| Body | pass | 200 px drop lands at 617 px/s (free fall 626), once, at his feet; rescue 1.87 s after falling off the desk; `hurt` 0.34–0.40 s on a 0.35 s tag |
| Knockout | pass | collapse 0.83 s (tag 0.84), pile 1.20 (1.20), reassemble 0.85 (0.84); pays once; no drag, no damage, no beats inside it |
| Mood | pass | every band edge both sides; decay 2.0/s; payout = the multiplier in force at the hit (stoic −100 ×2.00 … 0 ×0.60 … +100 ×2.00) |
| Grime | pass | +amount × 0.0008 per hit; patches at the grime level, never on the face; filthy earns ×0.650; sponge 0.49/s |
| Personalities | pass | all 12: hurt face, joy face, swaps, hop 5.0 px per unit of amplitude, fidget period, early flinch — and damage, Bones, Hearts, mood and grime identical under every one |
| Critters | pass | tells within 0.02 s of authored; blows central (0.00 rad/s after); grab cancels the swing; leave by an edge |
| Turrets | pass | acquire in reach and not out; lean within cap; mirror; cadence within one tick; every shot lands at design damage |

The full per-row and per-toy numbers are in `user://brain_check_report.md` after a run.

---

## Deferred visual checks

brain_check is headless. These want eyes on a real window (`tools/sandbox.tscn`, not headless):
a boombox on the desk while he idles (mood face and blinks visible, not a fixed happy face); a 40
px box in his way; a gorilla crossing the desk and leaving; a pellet turret and a mortar firing at
him. The soak look (finding B) is `tools/soak_shots.tscn`, which was run and looked at for D70:
him in each of the nine, and hopping out.
