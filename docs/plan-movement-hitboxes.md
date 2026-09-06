# Movement, wall damage and the multi-hitbox — the plan

Synthesised 2026-09-06 from the nine results of the `buddy-movement-and-damage` workflow
(`research/movement-workflow-notes.md`: three readers, three proposals, three judges). The
judges scored the **minimal** proposal 33 / 33 / 33 against 26 / 25 / 23 (physics-first) and
26 / 20 / 20 (hitbox-first), and all three grafted the same handful of ideas from the losers.
This document is the winner with those grafts, in the shape of `plan-expressive-buddy.md`.

The owner's report to satisfy: **he must walk, not hop; self-motion and settling must not pay
or hurt; a throw, a drop or a swing still must.**

---

## 1. Diagnosis

Four verified defects compound into "he jumps toward things over and over and takes damage".
None of them is the multi-hitbox; that is a later, additive feature (§5).

**(a) His own rect is half his real size.** `BaseDraggable.get_interaction_rect()`
(`base_draggable.gd:50-59`) multiplies `shape.get_rect()` by the *body's* `global_scale` and
ignores the `CollisionShape2D` node's own `scale (2,2)` / `position (0,2)`
(`Scenes/Buddy/buddy.tscn:80-83`). Every item bakes size into its shape, so he is the only
body this is wrong for: the physics box is **88x120 spanning y −58..+62**, the brain sees
44x60. Everything the brain does with his body flows through that:

- `_foot_offset()` pushes at +30 — 32 px *above* his real feet.
- `_climb()` measures "feet" at +30, so `feet − top` is negative for any floor toy, floors at
  0, and **every hop is the 28 px `CLIMB_CLEARANCE` minimum**: v = √(2·980·28) = 234 px/s, a
  landing impulse of ≈ 3·234 = **703**, twice the 350 floor, 7 damage billed to `&"world"`.
- `_touching_target()` needs the toy within 22 + 22 + 20 px of his centre while his real
  half-width is 44: a beanbag resting against his side is **2 px outside "reached"**, and
  standing on top of it is not reached either. Arrival happens only by shoving or hopping.

**(b) The hop loop.** `_climb()` fires every 0.55 s from three places: travelling after one
2 s think without 16 px of progress; **playing, with no gate at all** (`not reached` →
walk + climb every tick); and the trampoline routine. `_enter()` zeroes `_climb_timer`, so the
first "not reached" tick hops immediately. Its own comment says a stall should be "four or
five tries"; 8 s / 0.55 s is fourteen. `_on_damage_dealt` exempts `&"world"` and the current
toy, so nothing ever stands him down: the loop runs until the 400-damage knockout, ≈ 25–35 s
of "walking", ~200 Bones + a 438-Bones knockout bonus + ~1.7 Dollars/s unattended, and
−2.1 mood per landing driving him into the U-curve's trough.

**(c) The damage floor is a 7 px fall.** `min_damage_impulse = 350` on a 3-mass body is
116.7 px/s. Nothing he can do on his own feet is under it: a step off a 30 px beanbag is 727.
The floor is right for weapons (a bat registers at 160 px/s) and wrong for the floor and his
own furniture. The walk's force is also integrated before the contact solve, so a wall at
walking speed sees m·v **plus** F·dt ≈ 350 + 175 — the "wall damage is too easy" half.

**(d) Rotation is free, and the push is a 3x-friction shove.** No `lock_rotation`, no
material (only `npc_base.gd:250` locks, "what separates a character from a prop").
`WALK_GAIN 30` gives 10,500 N from rest against 2,940 N of floor friction, 21,000 N on a
reversal; the tipping threshold for an 88-wide box with its CoM 52 px up is ≈ 829 px/s² and
the first tick delivers 2,520. He rocks onto a corner at every start, stop and turn. And a
P-controller against constant friction never reaches its target: **he cruises at ~84 px/s,
not the 117 the code derives**, so `effort` caps at ~0.72 for the art.

**(e) The test cannot see it.** The idle suite asserts 40 px of 260 closed, `phase ==
playing`, Hearts up (paid by the beanbag's own contact rate, not the walk) and one flipped
frame. `_observe` is connected only in the contact suite. A hop-and-stumble gait passes
every line.

Two things the readers got wrong and the judges corrected: the foot offset is `(0,30)`, not
`(0,60)`; the suite's drop is 338 px (≈ 2,442 impulse), not 276.

---

## 2. What changes, in order

Two commits, suites after each. No save schema change, no `balance.tres` edit (the new knob
is a `BalanceData` default), no scene edit — `buddy.tscn` stays for the art pass.

### Commit A — the floor knows who put the energy in

1. **`Scripts/Data/balance_data.gd`** — one export after `min_damage_impulse`:
   `min_fall_impulse := 1500.0`. On his 3-mass body that is 500 px/s, a drop of about his own
   height (128 px). Everything he can do to himself lands under it; a throw, a drop from above
   his head, or a bat carrying him into a wall lands over it.
2. **`Scripts/Economy/economy_math.gd`** — a pure classifier, so `run_tests.gd` can
   table-test it under `-s`:
   `static func contact_floor(harm_side: bool, min_impulse: float, fall_impulse: float) -> float`.
   The world and kind-side items need a fall; harm-side items need a swing. **The cliff stays
   a cliff** — the grapple shake (`npc_base.gd:526-527`) and the beam's per-tick impulse are
   both sized against it, and a knee would turn the grapple's 367.5 into 0.175 damage, the
   exact "visibly does something, silently pays nothing" failure that file warns about.
3. **`Scripts/Buddy/buddy.gd`**:
   - `_integrate_forces`: keep the order threshold → cooldown → attribute (so `register_use()`
     stays behind both gates) and insert a side-effect-free classifier between the 350 reject
     and the cooldown: `if impulse < _min_impulse_for(src, b): continue`. A discarded
     self-contact must never stamp the cooldown a real hit then eats.
   - `_min_impulse_for(src, b)`: scriptless body (the walls, the test floor) → fall floor;
     `Trampoline` → **swing floor** (it is `CATEGORY_TOY` → `SIDE_KIND` in the data, and
     without this line bounces 1–2 go free and the Bones engine the brain's header is tuned
     around is cut); any other `BaseDraggable` whose item `is_kind()` → fall floor; everything
     else (`WeaponBase`, `ThrowableBase`, `NpcBase`, unknown ids) → swing floor, conservatively.
     This function is **the seam** the later per-part floor plugs into (§5).
   - **Grounded**, from contact normals in the loop already running: `_grounded` true when
     any `get_contact_local_normal(i).y < -0.7` this tick, exposed as `is_grounded()`. The
     sign of that normal is the one thing nobody could verify without a run; a loop_check
     assertion pins it (§4).
   - `get_interaction_rect()` **overridden on Buddy** to return the collider node's real
     rect (88x120 at (0,+2)). Scoped to him on purpose: the minimal proposal's premise that
     every item collider sits at identity is false (`baseball_bat.tscn:39`, `fire_axe.tscn:40`,
     `chainsaw.tscn:44-45`), and nothing reads a weapon's rect today — do not change it silently.
   - `take_impulse` is untouched: blasts, pellets, beam and NPC blows keep 350.
4. **`Scripts/Combat/hit_info.gd`** — `part: StringName = &"torso"` as a fifth defaulted
   `_init` parameter. All eight consumers compile unchanged; the parts get their seam now.
5. **`tests/run_tests.gd`** — the classifier's truth table.
6. **`tests/integration/loop_check.gd`** contact suite — the drop still pays with
   `source_id == &"world"` and `raw_impulse` ≈ 2,442; a drop from below his own height is
   free; a beanbag dropped on him from 100 px is free (pins the kind side of the classifier);
   the mace still pays at the swing floor; resting contact tightened from `<= 1` to `== 0`;
   `is_grounded()` true at rest and false a few frames into a launch.

### Commit B — the brain walks him instead of throwing him

All in **`Scripts/Buddy/idle_brain.gd`** unless stated.

7. **Central, bounded push with friction feed-forward.** `_walk()`:
   `apply_central_force(clamp(direction·m·g + gap·m·WALK_GAIN, ±WALK_PUSH_G·m·g))` with
   `WALK_GAIN` 30 → **12** and `WALK_PUSH_G := 2.5`. Steady state is push = friction at
   gap 0, so he cruises at the full derived `_walk_speed()` (117 px/s) and `effort` honestly
   reaches 1.0; the reversal kick is bounded at 7,350 N (was 21,000). Delete `_foot_offset()`
   — with rotation locked the offset trick compensates for a torque that no longer exists.
   Air control stays: a gated hop must still be able to carry him onto a hot tub.
8. **Lock rotation while he is driven.** `_enter()`: `_buddy.lock_rotation = phase !=
   PHASE_WATCHING`; `_exit_tree()` unlocks. The unlock path on pick-up is synchronous
   (`_start_drag` → `_set_state(&"dragged")` → `_disturb` → `_stand_down` → `_enter(WATCHING)`),
   so the pin joint never swings a locked body and today's throw tumble and drag dangle are
   untouched. `_consider_starting()` refuses to start unless `|wrapf(rotation)| < 20°`, so a
   skeleton lying on his side is never locked there for a whole trip.
9. **Climbs are the exception.** `CLIMB_INTERVAL` 0.55 → **1.5** (its own comment's "four or
   five tries"; the longest flight at the new cap is under the interval). `CLIMB_CLEARANCE`
   28 → **12** — 28 was compensating for the 32 px feet error; every self-landing drops from
   703 to ≈ 460. `MAX_CLIMB_SPEED` 640 → **500**, so the one residual (a missed hot-tub climb,
   1,722 > 1,500) lands under the floor. `MAX_CLIMBS_PER_TRIP := 3`, reset in `_enter()`: a
   bounded count is a stronger guarantee than a timer against a toy pinned where he can never
   reach. New `CLIMB_PATIENCE := 1.5`: the playing branch accumulates `_lost_seconds` while
   `not reached` and climbs only past it — the same "walking has stopped working" rule the
   travelling branch already states. `_climb()` is grounded off `is_grounded()` (not
   `|v.y| < 50`, which re-fires at an apex), measures feet from the corrected rect, skips
   entirely when `feet − top <= 0` (a hop cannot help when the toy is not above his feet), and
   only fires while he is pressed against something — `|v.x| < MOTION_FLOOR` with a push in
   force — so a slow walker is never hopped at.
10. **Arrive, then lean in.** `_touching_target()` becomes rect overlap **or**
    `_target in _buddy.get_colliding_bodies()`, so "reached" and "paid"
    (`friendly_base.gd:154-157` pays on real collision) can never disagree. With the corrected
    rect, reached fires ~20 px before contact; for SOAK / SCRUB / NIBBLE the playing branch
    then `_lean()`s: `apply_central_force(direction · m · g · LEAN_G)` with `LEAN_G := 1.05`
    plus `art.travel(direction, 0.35)`. That crosses his own friction (2,940 N) and not his
    friction plus the lightest toy he walks to (rubber duck 0.3 → 3,234 N), so he creeps the
    last 20 px and stops against anything, including a hot tub or a toy pinned on a wall.
11. **A stand-down ends the stride the same frame.** `_stand_down()`, `_finish()` and the
    freeze-or-dragging early-out call `art.stop_travelling()`.
12. `WALK_GAIN`'s header paragraph and the `_foot_offset` comment are rewritten; the rule
    "the brain never writes `global_position`" stands.
13. **`loop_check.gd` idle suite** — the assertions in §4.

---

## 3. Calibration

Impulse on him ≈ 3 · Δv for a clean landing (mass 3, g 980), plus F·dt from any push that tick.

| Event | Impulse | Floor | Before | After |
|---|---|---|---|---|
| Resting on the floor, per tick | 49 | any | 0 | 0 |
| Walking into a wall at the old cruise (84 px/s + that tick's push) | ~300–525 | 1500 (world) | pays 3–5 on the bad ticks | 0 |
| Walking into a wall at the new cruise (117 px/s, push at friction) | ~400 | 1500 | — | 0 |
| Minimum hop landing | 460 (was 703 at clearance 28) | 1500 | 7 | 0 |
| Successful climb onto any toy (always a clearance-height fall onto its top) | 460 | 1500 (kind) | 7, billed to the toy | 0 |
| Missed beanbag hop (58 px) | 1,011 | 1500 | 10 | 0 |
| Tip-over from standing | ~820 | 1500 | 8 | 0 (and rotation is locked while driven) |
| Missed hot-tub climb at the new 500 cap (128 px) | 1,500 | 1500 | 17 | 0 (at the floor; `<` passes equality — see open decision 3) |
| Trampoline bounce 1 / 2 / 3 (320 → 496 → 769 px/s) | 960 / 1,488 / 2,307 | **350** (trampoline exempt) | 9.6 / 15 / 23 | unchanged — the mat stays the Bones engine |
| Player drop from 100 / 128 / 200 / 338 px | 1,330 / 1,500 / 1,878 / 2,442 | 1500 | 13 / 15 / 19 / 24 | 0 / 15 / 19 / 24 |
| Bat lay-on at 160 px/s (reduced mass 2.18) | 350 | 350 | 3.5 | 3.5 |
| Bat swing, mace, grenade, pellets, beam, NPC blows | 3,270+ / `take_impulse` | 350 | unchanged | unchanged |

Why these numbers:

- **1500** is the smallest fall floor that clears every self-inflicted landing in the roster
  with margin (the ceiling is set by a missed beanbag hop at 1,011 and a tip-over at 820) and
  has a one-sentence rule the player can feel: *drop him from higher than he is tall and it
  hurts.* 1200 leaves the missed hot-tub climb paying and puts a 100 px drop within 10% of the
  line; 2000 makes most casual drops free.
- **The cooldown stays 0.15 s**, and there is no separate world cooldown: farming the fall
  floor needs a 128 px drop every 0.15 s, which nobody's furniture can produce.
- **No "launched" flag.** Everything he can do to himself lands on the world or a kind item, so
  the source split *is* the self-motion exemption — no brain→buddy coupling, no state to get
  stuck. A player who throws him at the wall still pays: the wall is world but the impulse is
  thousands. The physics-first proposal's provenance flag is the fallback if the playtest
  wants sub-128 px drops to pay (open decision 1).
- **`WALK_PUSH_G` 2.5** bounds the reversal kick at 7,350 N; net of friction that is 1,470
  px/s², start-to-cruise in 0.08 s, so "starts him inside a fifth of a second" still holds,
  and it stays above the 829 tipping figure only while rotation is locked — which it is.
- **D31's Dollar-per-hit** at `economy.gd:242` becomes correct as a side effect: world hits
  are now only ever player-caused. It is left alone.
- **`pacing_sim` cannot observe any of this** — it has no impulse model. The checks that can
  are `loop_check` (the trampoline assertion covers the income shift), `ui_check` (open-hand
  and beam reach become a superset of today's) and a sandbox session on both monitors
  watching a beanbag, a hot tub and a trampoline.

---

## 4. Tests, in words

**`run_tests.gd`** — `contact_floor` truth table: harm side → swing floor, kind side → fall
floor, both floors passed through untouched, and the swing floor is never above the fall floor.

**`loop_check` contact suite** (`_real_physics_produces_hits`):
1. The 338 px drop still pays, attributed `&"world"`, `raw_impulse` within 15% of 2,442 —
   so the new floor can never silently switch drops off.
2. A drop from 60 px above his feet (≈ 1,029) is free: `_observed` empty, `health.damage` 0.
3. A beanbag dropped onto him from 100 px (≈ 700 on him) is free — pins the kind side.
4. The mace still pays at the swing floor (existing).
5. Resting contact: `== 0` hits in 120 frames, not `<= 1`; resting is 49, thirty times under.
6. `is_grounded()` true after settling, false five frames into a `apply_central_impulse`
   launch — this pins the contact-normal sign, the one unknown nobody could resolve on paper.

**`loop_check` idle suite** (`_he_goes_and_plays_with_his_toys`), with `_observe` connected
for the whole walk:
7. **Walking to a toy costs him nothing**: `_observed` empty and `health.damage == 0`.
8. **He walks, he does not hop**: min `linear_velocity.y` over the walk > −150.
9. **He arrives on his feet**: `|wrapf(rotation)| < 0.1` on every frame, `lock_rotation`
   true while `phase_name() == &"travelling"`.
10. **He is actually in it**: after arrival, the beanbag is in `get_colliding_bodies()` on
    ≥ 90% of the remaining frames and `|v.y| < 100` on ≥ 95% — a hop loop leaves contact
    every 0.55 s and fails both; a bob passes both.
11. **Being picked up unlocks him**: after the bat interrupt, `lock_rotation == false`.
12. **A wall stops him without paying**: a `StaticBody2D` between him and a second toy; no
    `&"world"` hit, at most three upward launches, and `phase == wandering` via the stall path.
13. **The trampoline still pays**: one under him, `pretend_idle()`, a hit attributed
    `&"trampoline"` inside 600 frames.
14. **He does not start on his side**: rotate him 45°, `think_now()`, phase stays watching.

`ui_check`: the open hand's reach now covers his real 88x120 — the pet assertions become
more permissive, not less; run it to prove that.

---

## 5. The multi-hitbox — designed, deferred to the art pass

The owner's instinct addresses a different problem from the report: a self-landing and a bat
to the shins arrive on the same shape, and only *provenance* separates them (§2). Parts are
**juice** — a head hit paying more, a leg wobble — and they layer on the seam Commit A names
without undoing anything.

**Mechanism.** More `CollisionShape2D`s on the same `RigidBody2D`, never child Areas (an Area
has no contact impulse and costs per-frame overlap monitoring; D7 measures on the receiver).
`PhysicsDirectBodyState2D.get_contact_local_shape(i)` gives the owner shape index per
contact, so the loop already in `_integrate_forces` maps shape → part with no new nodes.
Shapes bake their size (no node scale — the `seed_bodies.gd` convention), which also retires
the rect bug for good once `get_interaction_rect` unions them.

**Parts, in art pixels about the 96-cell centre (x2 for world).** Row profile of the neutral
frame: skull incl. headphones y −27..+5 (44–48 wide; headband −23..−19; ear cups −9..+4);
torso/pelvis +5..+21, 28 wide; feet +22..+35, 34–38 wide. A first cut, world px:

| Part | Shape | Position | Spans y | Damage mult | Floor |
|---|---|---|---|---|---|
| Skull | Rect 88x64 | (0, −31) | −63..+1 | **1.5** | swing / fall by source, as today |
| Torso | Rect 56x34 | (0, +18) | +1..+35 | 1.0 | same |
| Feet | Rect 88x28 | (0, +49) | +35..+63 | 1.0 | same; **kind item under the feet → never** (landing on a beanbag is not a beanbag hitting him) |

Rects, not circles: a round skull under a locked rotation buys nothing and rects stack with no
seam. Same 88 px footprint and wall behaviour; 1 px taller. The idles *translate* the drawn
skull up to 26 world px in a bob; shapes stay static (physics must not chase animation) and
the skull rect is sized for the excursion. Hats ride the same head anchor.

**Registration.** The 96-cell art's opaque rows sit ~8–9 px low against today's collider (feet
draw into the floor). `Puppet.position.y -= 9` (`Face` copies it, `BuddyArt` bobs relative to
`_body_home`) — but measure it against the frames `BuddyArt` actually loads
(`art/src/bonehead.aseprite`), not the PNG the reader measured.

**Attribution.** `HitInfo.part` (added in Commit A, default `&"torso"`). `_queue_hit` folds the
part multiplier into `amount` before the cap, so the eight consumers need no change.
`take_impulse` gains `_part_at(at)` — local y < +1 skull, < +35 torso, else feet — so blasts,
turrets and NPC blows attribute by where they landed with no caller change. Cooldown stays
keyed per collider; a swing that clips skull then torso pays once, the first part that
cleared its floor. `damage:<id>:<part>` contract keys can come later.

**Reactions.** A skull hit at or above `skull_daze_damage` (≈ 20) asks the expression brain
for a heavier row — `hit_heavy`'s dizzy tail already exists, and a `hit_head` row (face
`dizzy`, longer tail) is one line in `ExpressionBrain.ROWS`. Beats, not states (D36): no
`dazed` state is added. A leg wobble is either the `dizzy` body tag or a code motion in the
accumulator.

**Cost.** Two extra broadphase pairs and a contact manifold or two per awake tick —
microseconds. A sleeping body reports nothing. Nothing per frame while he idles.

**Dependencies.** `buddy.tscn` opened in the editor for the first time — CLAUDE.md assigns
that to the art pass, which authors `Face`, `BuddyArt`, `MoodComponent`, `GrimeComponent` and
`ExpressionBrain` as real nodes in the same session (the `_ensure_components()` fallback stays
for tests). The `dizzy` body tag (4 frames, unbuilt). The walk cycle itself (§6). About 4 h of
code plus the scene session; the calibration above (skull ×1.5, feet exempt on kind items)
should be judged on a real session before any of it is tuned further.

---

## 6. Art dependencies and how the walk plugs in

`BuddyArt.travel(direction, effort)` is already the seam and no caller changes. Two things
improve for free from Commit B: `effort` becomes honest (he reaches 117 px/s, so the bob hits
1.0 instead of ~0.72), and stops are exact, so `TRAVEL_DECAY` fades the bob from a real halt
rather than a friction slide.

When a `walk` tag exists: in `_advance_travel()`, on `_travel > 0` and `has_animation(&"walk")`
and `_state_of_body() == &"idle"` with no beat live → `_play_body(&"walk")`,
`body.speed_scale = lerp(0.6, 1.0, _travel)`, bob 0 (the tag carries its own); when `_travel`
decays to 0 → back through `_on_mood_changed(Economy.mood)` for the mood idle. Face offsets per
walk frame come from `postprocess.py` like every tag. Constraints for the tag: 8 frames, 63 px
body, feet drawn inside the future Feet box (bottom 14 art px) so the plant reads at the
collider bottom; at 117 px/s an 8-frame tag at 10 fps is 94 px per cycle, 47 px per step —
his leg length. `lock_rotation` while driven means a walk drawn upright is always upright,
and with the push central and the hop rare there is no tumble or crouch to draw over.

The stride itself is assessment item C1 and needs the generator (`worklist-2026-09.md` §3).

---

## 7. Open decisions

1. **Drops from under ~128 px are free.** A feel change the report did not ask for; the
   one-sentence rule is *drop him from higher than he is tall and it hurts*. If the playtest
   wants small drops to pay, the fallback is a `_launched` mark set only in `_end_drag()` and
   by the trampoline (never the eleven `take_impulse` sites), letting `_min_impulse_for` return
   the swing floor while it is set — about 15 lines, and it degrades to today's behaviour.
2. **Rotation is locked only while the brain drives him**, so the throw tumble and the drag
   dangle are exactly today's. If the tumble after a bat hit is ever missed under the lock,
   the next step is unlocking only while launched — never always-on.
3. **Equality at the floor.** `impulse < floor` lets exactly-at-the-floor through. The missed
   hot-tub climb at the new 500 cap lands at ≈ 1,500. Either make the comparison `<=`, or
   accept a rare 15-damage residual. Recommendation: `<=` for the fall floor only.
4. **Trampoline exempt by class.** A `Trampoline` is kind-side data but pays at the swing
   floor because the mat's launch is external energy and the brain's Bones engine is tuned
   around it. If the mat should instead be free for the first two bounces, delete one line.
5. **Whether the parts (§5) are wanted at all** before the walk cycle exists. They are juice;
   the report is fixed without them.
