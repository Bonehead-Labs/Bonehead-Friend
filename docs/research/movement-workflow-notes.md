# Movement, wall damage and multi-hitbox — raw workflow notes (2026-09-06)

Nine agent results from the `buddy-movement-and-damage` workflow (three readers, three
proposals, three judges). The synthesis step that would have written
`docs/plan-movement-hitboxes.md` was cut off by a usage cap. Write that plan from these
notes — do not re-run the agents. Judge totals decide the winner; graft from the losers.

---

## Reader — movement (how the walk applies force)

# Movement findings — why the walk reads as repeated jumps

## How the walk actually applies force

**Body.** `Scenes/Buddy/buddy.tscn:58-83` — `RigidBody2D`, `mass = 3.0`, custom `center_of_mass = (0, 10)`, one `RectangleShape2D` 44×60 at `scale (2,2)` offset `(0,2)` → an **88×120 box** whose bottom is 62 px below the origin. No `lock_rotation`, no `physics_material_override`, no damp overrides. `project.godot` has no `[physics]` section at all (only layer names, lines 65-70), so everything is Godot default: gravity 980, friction 1.0, bounce 0, linear_damp 0.1, angular_damp 1.0, 60 Hz. `base_draggable.gd:45` sets `continuous_cd = CCD_MODE_CAST_RAY`. Floor is a `StaticBody2D` with no material (`world_bounds.gd:31-41`), so μ = 1.0.

**Force, every physics tick** — `idle_brain.gd:349-363`:
```gdscript
var gap := direction * _walk_speed() - _buddy.linear_velocity.x
if absf(gap) < 1.0: return
_buddy.apply_force(Vector2(gap * _buddy.mass * WALK_GAIN, 0.0), _foot_offset())
```
- `_walk_speed()` = `min_damage_impulse / mass` = 350 / 3 = **116.7 px/s** (`idle_brain.gd:370-371`, `balance_data.gd:15`; `balance.tres` does not override it).
- `WALK_GAIN = 30` (`idle_brain.gd:127`). Peak force from rest = 116.7 × 3 × 30 = **10,500**. Friction cap = μ·m·g = 2,940. Net kick ≈ 7,560 → **2,520 px/s²** for the first ticks.
- On a **reversal** (wander turn at `idle_brain.gd:398-405`, or the sign flip at `:326`/`:337` when he crosses the target's centre) `gap` is up to 2× walk speed → **21,000**, a ≈ 6,000 px/s².
- It is a pure P-controller against a constant friction disturbance, so cruise is where push = friction: gap = 2940/(3·30) = 32.7 → he actually cruises at **~84 px/s**, never 116.7 (this also caps `effort` at `:358` to ~0.72).
- `_foot_offset()` = `(0, 60)` in global axes (`idle_brain.gd:410-411`), i.e. 50 px below the CoM. The comment at `:346-348` says pushing at the feet avoids tipping him; see hypothesis 2 for why the opposite happens on kick-off.
- No `delta` scaling, force not impulse — continuous while `_physics_process` is on, which is only while travelling/playing/wandering (`:233`, `:595`).

**The hop** — `idle_brain.gd:376-386`:
```gdscript
if absf(_buddy.linear_velocity.y) > GROUNDED_SPEED: return   # 50 px/s, velocity not contact
_climb_timer = CLIMB_INTERVAL                                 # 0.55 s
var rise := maxf(0.0, feet - top) + CLIMB_CLEARANCE           # +28 px always
var speed := minf(sqrt(2.0 * _gravity * rise), MAX_CLIMB_SPEED)  # cap 640
_buddy.apply_central_impulse(Vector2(0.0, -_buddy.mass * speed))
```
Called from three places:
- TRAVELLING, every tick once `_stalled_seconds > 0.0` (`:330-331`) — i.e. after **one** 2-s think window without 16 px of progress (`:283-287`).
- PLAYING, every tick whenever `not reached`, **with no stall gate** (`:336-338`).
- PLAYING + `ROUTINE_BOUNCE`, every tick (`:339-342`).
The walk force keeps being applied on the same tick (`:337` then `:338`), so each hop is a forward leap — "jumps toward things".

## Why it damages him

`buddy.gd:164-178` reads every contact impulse ≥ 350, bills anything without a script to `&"world"` (`:224`), and `_queue_hit` pays `impulse × 0.01` damage (`economy_math.gd:47-50`). Economy pays Bones on it regardless of source (`economy.gd:228-233`), mood drops (`mood_component.gd:51-52`), and he pulls the hurt face (`buddy.gd:207`). The brain then **exempts** `world` and the current toy from interrupting him (`idle_brain.gd:528`), so the loop never stands down — it repeats until stall/dwell or knockout.

Numbers (3-mass, landing impulse ≈ m·v, floor cooldown 0.15 s < 0.55 s hop cadence so every landing pays):
- The damage threshold in speed terms is 350/3 = **117 px/s = a 7 px drop**. No climb can be damage-free: the floor of `rise` is 28 px → 234 px/s → impulse 702 → **7 damage minimum per hop**.
- Beanbag (collider 44×30 unscaled, `beanbag.tscn:8,29-30`): rise = 13 + 28 = 41 → 283 px/s → **≈850 impulse, 8.5 damage** per hop.
- Hot tub side (144×140, `hot_tub.tscn:8`): rise = 68 + 28 = 96 → 434 px/s → **≈1,300, 13 damage**.
- Capped climb: 640 → 1,920 → 19 damage. An 8-s stall (`STALL_SECONDS`, `:87`) is ~14 hops → 120-270 damage; `knockout_damage` is 400 (`balance_data.gd:34`), so two stalls in a row is a knockout attributed to the floor.

## Why the test is green while a human sees it broken

`loop_check.gd:1352-1454` (suite "idle brain — he goes and plays"):
- Asserts only `closest < start − 40` (40 of 260 px closed, `:1432-1433`), `phase == playing` after 7 s (`:1434-1435`), Hearts up (`:1436-1438`, paid by the beanbag's own `hearts_per_second_touching`, not by the walk), and `flip_h` seen on **one** frame (`:1425-1427`, `:1441`). Nothing on `linear_velocity.y`, `global_rotation`, `health.damage`, `damage_dealt` count, or `source_id == &"world"` — `_observe` is not connected in this suite (it is only in "contact impulse", `:1469`).
- The geometry is the most forgiving possible: one light dynamic beanbag (mass 1.2) on a flat 1600 px floor (`loop_check.tscn` Floor at (320,600), 1600×200), no walls (`WorldBounds` deliberately absent, `loop_check.gd:1471-1473`), nothing between him and it. The stall branch (`:330`) is unreachable, so the travel-phase `_climb()` never runs; a tumbling, corner-rocking arrival still gets within `ARRIVE_SLACK` and flips to PLAYING.
- 260 px at ~84 px/s is 3 s of a 7 s window, so even a hop-and-stumble gait passes the distance check.

## Hypotheses, ranked

**1. (Most likely) The `_climb()` hop loop is the "jumping", and its landings are the damage.** Triggers: any real obstruction while travelling (a boombox mass 4 or hot tub mass 14 in the way — pushing a 14-mass body needs 13.7k > his 10.5k max), a toy on top of another toy, or in PLAYING any moment the target rect stops overlapping (`:336-338` has no stall gate and `_enter()` zeroes `_climb_timer` at `:593`, so the first frame of "not reached" hops immediately). Trampoline routine hops every 0.55 s by design (`:339-342`).
Change: gate `_climb()` on a real ground contact (see 4), only after a *full* stall window in PLAYING as well as TRAVELLING, and only when the target's top is actually above his feet by more than a step (a beanbag 13 px above his feet does not need a 28-px clearance leap). Lengthen `CLIMB_INTERVAL` to ≥ 1.5 s. Given a 7-px drop already registers as a hit, ballistic climbing cannot be made damage-free under the current threshold — either accept (3) or replace the hop with a non-ballistic step (e.g. a brief, small upward force only while a side contact with the target exists).

**2. The kick-off/reversal torque tips him onto a corner, and the corner slams down.** With rotation free, a box on a floor pivots on its rear bottom corner when the CoM's horizontal acceleration exceeds g·(half-width / CoM height) = 980 × 44/52 ≈ **829 px/s²**. The walk's first tick gives 2,520 px/s² (three times that) and a reversal ~6,000; friction stopping is 980 (also over). So every start, stop and turn rocks him onto a corner and drops the other corner — an 88-px lever, so the corner lands fast enough to read as a hop and often to clear 350. The `:346-348` rationale about pushing at the feet does not help here: about the pivot corner a floor-level push has no lever arm, the tipping comes from the CoM's inertia. `npc_base.gd:250` already does `lock_rotation = true` for the gorilla with exactly this reasoning ("what separates a character from a prop"); the buddy never gets it (only `global_rotation = 0.0` at `buddy.gd:294` and `:354` during knockout/rescue).
Change: `lock_rotation = true` while the brain drives him (set in `_enter` for TRAVELLING/WANDERING/PLAYING, cleared in `_stand_down`/`_finish`), or always; cap the push at ~1.5× friction (≤ 4,400 → a ≤ 500 px/s² < 829) and ramp the velocity target instead of stepping it; with rotation locked apply the force centrally (the foot offset is moot). Consider a capsule/rounded bottom on the collider so corners cannot catch.

**3. The damage threshold is walking-scale, so anything he does on his own feet is a hit** — this is the "calibrate wall damage" ask. 350 impulse at mass 3 is a 117 px/s impact, a 7-px drop; stepping off a beanbag (30 px) is 242 px/s → 727 impulse → 7 damage. `damage_cooldown` 0.15 s (`balance_data.gd:25`) lets the single floor pay 6.7 Hz.
Change (cheap, no second body, D4 intact): in `buddy.gd:168-178` read `state_.get_contact_local_normal(i)` and apply a higher `min_landing_impulse` (≈3-4×, i.e. an 80-100 px fall) when the normal is within ~30° of up **and** the collider is not a `WeaponBase`/`ThrowableBase`; keep 350 for side/top hits and for thrown things. The multi-hitbox version: add a second `CollisionShape2D` (feet) to the same `RigidBody2D` and key thresholds off `state_.get_contact_local_shape(i)` — this keeps him one body and lets a foot landing and a bat to the head be judged differently. Add a separate, longer per-`world` cooldown (~1 s) so a hop chain cannot farm Bones. Keep `loop_check` "contact impulse" (`:1470-1484`, a 440-px drop → ≈2,800 impulse) green; add an assertion to the idle-brain suite that `health.damage == 0` and no `&"world"` `HitInfo` fires during the trip.

**4. "Grounded" is a velocity test, not a contact test (`:379`), so he can climb again at the apex.** For a hop ≥ 539 px/s (rise ≥ 148 px, or a trampoline launch) the 0.55 s timer expires before the apex and |v.y| < 50 there → a second impulse mid-air (28-px `rise` above the target → +234 px/s), then a harder landing. Lower frequency than 1-2 but it stacks on them.
Change: derive grounded from a contact with an upward normal this tick (cache it in `_integrate_forces`, `contact_monitor` is already on at `buddy.gd:64`), as `npc_base.gd:389-394` should too.

**5. It never looks like a stride because there is no stride.** Cruise is ~84 px/s of pure sliding, the only motion cue is a 1.5-px bob at 9 Hz (`buddy_art.gd:88-89`, `:166-167`), already logged at `docs/assessment-2026-09.md:223`. Low relevance to the damage, high relevance to "doesn't appear to function".
Change: friction feed-forward (`+ direction * mass * g * μ`) so he reaches the intended 117 px/s, and a walk tag; both independent of 1-4.

## CPU note
None of the above changes the on/off structure (`_physics_process` stays disabled while WATCHING, `:233`/`:595`). A per-contact normal read only runs on ticks with contacts; `lock_rotation` toggles are free.

Files: `C:\Users\George\Godot Projects\Projects\bonehead-friend\Scripts\Buddy\idle_brain.gd`, `...\Scripts\Buddy\buddy.gd`, `...\Scripts\Buddy\buddy_art.gd`, `...\Scenes\Buddy\buddy.tscn`, `...\tests\integration\loop_check.gd`, `...\tests\integration\loop_check.tscn`, `...\Scripts\Data\balance_data.gd`, `...\Scripts\World\npc_base.gd`, `...\Scripts\Overlay\world_bounds.gd`, `...\Scenes\Friendly\beanbag.tscn`, `...\Scenes\Friendly\hot_tub.tscn`.

---

## Reader — damage pipeline

# Damage pipeline — findings (read-only; no Godot run)

## 1. The pipeline, end to end

1. **Measure** — `Scripts/Buddy/buddy.gd:164-178` `_integrate_forces`: every physics tick (60 Hz, project.godot sets no `physics_ticks_per_second`), for each of up to 8 contacts (`MAX_CONTACTS`, buddy.gd:25) reads `state_.get_contact_impulse(i).length()`. In Godot 4 that is the accumulated impulse for **that tick** at that manifold point, normal + friction components together, so a landing while sliding reports more than `m·v_normal`.
2. **Floor** — buddy.gd:170 `if impulse < b.min_damage_impulse: continue`. `min_damage_impulse = 350.0` (`Scripts/Data/balance_data.gd:15`; `Data/balance.tres` does not override it). Strict `<`, so exactly 350 passes.
3. **Cooldown** — buddy.gd:173/233-241: per **collider instance id**, `damage_cooldown = 0.15 s` (balance_data.gd:25). The floor, each wall, and each item are separate buckets; the floor alone can pay 6.67 hits/s. The cooldown is stamped as soon as a contact clears the floor, before amount is computed.
4. **Attribute** — buddy.gd:212-224 `_attribute`: `WeaponBase` → `[item_id, effective_damage_mult]` (+`register_use()`); `ThrowableBase` → same; any other `BaseDraggable` (every friendly/comfort/food item, `FriendlyBase extends BaseDraggable`) → `[item_id, 1.0]`; **anything else (the four `WorldBounds` `StaticBody2D`s, `Scripts/Overlay/world_bounds.gd:31-41`, or the test scene's Floor) → `[&"world", 1.0]`**.
5. **Formula** — buddy.gd:189-197 `_queue_hit` → `Scripts/Economy/economy_math.gd:47-50`: `damage = impulse × damage_per_impulse(0.01, balance_data.gd:18) × mult`, then clamped to `knockout_damage(400) × max_hit_fraction(0.5) = 200` (buddy.gd:196). **No subtraction of the floor** — a 351 impulse pays 3.51 damage, a 349 pays 0; the threshold is a cliff, not a knee.
6. **Dispatch** — buddy.gd:153-160 flushes `_pending_hits` in `_physics_process`; `_deal` (199-208) emits `EventBus.damage_dealt`, plays `hit_effect`, `_react(&"hurt")` (0.45 s hurt state → BuddyArt crouch), then `health.apply_damage` (`Scripts/Components/health_component.gd:27-36`; knockout at 400).
7. **Consumers of every hit, world included** (autoloads first, per the connect-order note):
   - `Scripts/Autoload/economy.gd:228-243`: Bones = `amount × bones_per_damage(0.5) × grime_mult × mood × augments × mastery × marrow × temp × milestones`; `contract_event("damage:world")`; **`grant(DOLLARS, dollars_per_hit)` at line 242 for every hit, including `&"world"`** — self-inflicted floor hits mint Dollars, which D31 says are "earned by being present".
   - `Scripts/Autoload/progression.gd:313-314`: mastery XP = `amount × 4.0` (balance.tres overrides `mastery_xp_per_damage` to 4). `add_mastery_xp` (266-267) drops `&"world"` because `ItemDB.has_item` fails, **but a landing on the beanbag is attributed `&"beanbag"` and does grant that comfort item damage-mastery XP and `damage:beanbag` contract counts.**
   - `Scripts/Components/mood_component.gd:51-52`: `−amount × 0.30` mood per hit. `grime_component.gd:48-49`: `+amount × 0.0008` grime.
   - `Scripts/Buddy/idle_brain.gd:528`: `&"world"` and the current toy are **exempt from interrupting him**, so self-damage never stops the loop that causes it.

## 2. Quantities (buddy mass 3.0, `Scenes/Buddy/buddy.tscn` `mass = 3.0`; gravity 980; no `PhysicsMaterial` on the buddy → friction 1.0, bounce 0)

| Event | Impulse on him | Damage | Bones (base, ×0.5) |
|---|---|---|---|
| Resting on floor, per tick (`m·g·dt`) | 49 | 0 | — |
| Threshold 350 in his own terms | a vertical speed of **116.7 px/s = a fall of 6.9 px** | — | — |
| Walking into a wall at derived `_walk_speed()` (idle_brain.gd:353-354 = 350/3 = 116.7) | `m·v` 350 **+ the walk push integrated that tick** `F·dt = (116.7×3×30)/60 = 175` → **~525** | 5.3 | 2.6 |
| Smallest climb (`rise = 0 + CLIMB_CLEARANCE 28`, idle_brain.gd:307-309 → v = √(2·980·28) = 234) landing | 703 normal (+49 gravity, + up to ~700 friction if sliding) → 700–1000 | 7–10 | 3.5–5 |
| Climb over a 30 px beanbag (rise 58 → v 337) | 1011+ | 10 | 5 |
| Max climb (`MAX_CLIMB_SPEED 640`) | 1920 | 19 | 9.6 |
| Tipping over from standing (COM drops ~38 px → v≈273) | ~820 | 8 | 4 |
| Trampoline `minimum_launch 320` (`Scripts/Bodies/trampoline.gd:16`) landing | 960 | 9.6 | 4.8 |
| Player drops him from 100 px / 300 px | 1330 / 2300 | 13 / 23 | 6.7 / 11.5 |
| Baseball bat (mass 8, ×1.0) at 1500 / 2500 px/s (reduced mass 8·3/11 = 2.18) | 3270 / 5450 | 33 / 55 | 16 / 27 |
| Mace (mass 12, ×1.4) at 2000 px/s | 4800 | 67 | 34 |
| Grenade at centre (`max_force 10000`, seed_bodies.gd:94) | 10000 | 100 | 50 |
| Single-hit cap | 20000 | 200 | 100 |

So: **an ordinary self-propelled landing is 15–60% of a real bat swing**, and the floor is set at roughly a 7 px fall. The bat needs only ~160 px/s to register (350/2.18) — a lay-on, not a swing.

## 3. Why "hitting the walls" and the jump loop are too easy

- **The derived safe walk speed is wrong by the push term.** `_walk_speed()` (idle_brain.gd:349-354) assumes contact impulse = `m·v`. But `apply_force` (idle_brain.gd:290) is integrated into velocity *before* the contact solve in the same tick, so the wall must cancel `m·v + F·dt`. At full gap that is 350 + 175 = 525 (see table); after a rebound (`gap` = walk speed + rebound speed, up to 233 → F = 21,000 N → 350/tick from force alone) it is worse. Every arrival at a wall, a heavy toy (hot tub, mass 14, floor friction 13,720 N — he cannot shove it) or a stacked item is a hit, attributed to `&"world"` or the toy. And even the bare `m·v` = 350.0 is not below a strict `<`.
- **Every climb is a paid hit, by design admission.** idle_brain.gd:322-324 says a climb "costs him a landing"; the minimum climb lands at 2× the floor. In `PHASE_PLAYING` with `not reached` (idle_brain.gd:334-336), `_climb()` fires every `CLIMB_INTERVAL 0.55 s` **with no stall gate at all**; in `PHASE_TRAVELLING` it fires every 0.55 s for the whole 8 s after a single 2 s think tick without 16 px of progress (idle_brain.gd:322-325, `_tick_travel` 253-263). Flight time for the minimum climb is 0.48 s, so this is ~1.7 landings/s × 7–10 damage ≈ 12–17 damage/s: **knockout in ~25–35 s of "walking", ~200 Bones + a 438-Bones knockout bonus (`2×400^0.9`), plus ~1.7 Dollars/s, all unattended**, and −2 to −3 mood per landing driving him into the 2× despair end of the U-curve. The visible result is exactly the report: jump, land, `hurt` crouch, jump.
- **Why he ends up "not reached" next to a light toy:** he is pushed at his feet (idle_brain.gd:290, `_foot_offset` 372-373) into a 1.2-mass beanbag whose floor friction is only 1,176 N against his ~10,500 N push; the toy scoots, `_touching_target()` (idle_brain.gd:589-590, rect overlap + 20 px) flips false, and the shove + climb loop restarts. Landing on the toy also shoves it. `_foot_offset` is also unrotated (world +60 px below his centre), so once he has tipped (~820 impulse on its own) the push point is below the floor and torques him into a roll — more floor impulses, each ≥ 350, 6.67/s max per the floor's cooldown bucket.
- **Nothing tests any of this.** `loop_check.tscn` has no `WorldBounds` (loop_check.gd:1471-1474) and one flat Floor (`loop_check.tscn:18-23`); the idle suite (loop_check.gd:1353-1438) asserts he *arrives* and that Hearts rose, never that `damage_dealt` stayed empty during the walk. "Resting contact does not farm" (1525) allows `<= 1` hit in 120 frames — which is 7 damage per 2 s if it were farming.

## 4. Calibration proposals (values with reasoning)

**A. Split the floor by source, in `BalanceData`.** Keep `min_damage_impulse = 350` for item/weapon/NPC contacts (a bat at 160 px/s is already generous; lowering it would change the harm ladder the assessment says needs CSV measurement). Add `world_damage_impulse ≈ 1200` for `&"world"` attribution (buddy.gd:170 reads the right floor after `_attribute`, so move the attribution call above the threshold check). 1200 on a 3-mass body = 400 px/s = a **82 px fall**: the largest self-climb (rise 58 → 1011) and a tip-over (~820) are under it; a hand-drop from 100 px (1330), a trampoline (960 — see C), and any bat-into-wall carry-through (thousands) are over it. Also make the comparison `<=` or give `_walk_speed()` a 0.8 factor so the derived number has a margin.

**B. Subtract the floor in the formula (knee, not cliff).** `damage = (impulse − floor) × 0.01 × mult` in `economy_math.gd:47-50`. A 351 no longer pays 3.5; a 5,000 bat hit drops from 50 to 46.5, which is inside the retune the assessment already schedules. Gentle settling and near-threshold scuffs become fractions that `amount <= 0` (buddy.gd:192) or a `min_hit_damage ≈ 1` discards. Unit-tested in `tests/run_tests.gd` next to the existing damage tests.

**C. A "launched" flag on the buddy, so deliberate throws keep paying while self-motion does not.** Set `_launched_until_rest = true` in `_end_drag()` when he was dragging (buddy.gd:147-151), on any non-`&"world"` hit in `_deal`, on `take_impulse` (blasts/turrets/NPC blows) and from `Trampoline` (trampoline.gd:49 already has the body; emit or call `mark_launched()`); clear it when `linear_velocity.length() < ~60` for 0.3 s. While the flag is **clear**, `&"world"` contacts use the higher floor from A (or are dropped outright); while set, they use 350 as today. Self-propulsion never sets it (IdleBrain only uses `apply_force`/`apply_central_impulse`, idle_brain.gd:290, 311, 320), so climbs and tips cost nothing; a player drop, a bat that sends him into the wall, a blast that bounces him off the ceiling, and a trampoline all still pay their landings. This is cheaper than a multi-hitbox and catches the actual discriminator — *who put the energy in* — which a head/feet split cannot (a landing after a climb arrives on the feet; a bat to the shins should still pay).

**D. Stop the loop at the source, independent of the money.** In `PHASE_PLAYING`, gate `_climb()` on `_stalled_seconds > 0.0` exactly as travelling does (idle_brain.gd:334-336), cap climbs per dwell (e.g. 3), and skip the climb entirely when `rise <= CLIMB_CLEARANCE + toy height he can simply walk into` (a 30 px beanbag needs no jump). Raise the minimum toy mass he will shove or push at the toy's centre rather than his feet — or better, treat "rects overlap at any point in the last 0.5 s" as reached so a scooting beanbag does not un-arrive him.

**E. Close the D31 leak.** `economy.gd:242` should not grant `dollars_per_hit` for `info.source_id == &"world"` (and arguably not for hits whose source is the buddy's own current toy while `IdleBrain` is in `PHASE_PLAYING` — `_is_current_toy` logic already exists at idle_brain.gd:611-612).

**F. Assert it.** In the idle-brain suite (loop_check.gd:1353-1438): connect `_observe` for the 420-frame walk and `_check("walking to a toy costs him nothing", _observed.is_empty())`; add a walled variant (a StaticBody2D wall at `toy_x − 60`) and assert no `&"world"` hit above `min_damage_impulse` while `brain.phase_name()` is travelling. Add one test that a hand-drop from 150 px **does** still pay, so A/C cannot silently turn throws off.

On the owner's multi-hitbox idea: a second shape (head vs body) would let the pipeline pay more for a head hit, which is a *juice* feature; it does not address the reported bug, because self-landing and wall-walking arrive on the same shapes a legitimate shove does. Source identity + energy provenance (A + C) is the fix; hitboxes can layer on top later without touching it.

---

## Reader — the body and a multi-hitbox survey

FINDINGS — THE BODY (read-only survey; no Godot run)

## 1. The collider as it stands

- One `RigidBody2D`, one physics shape. `Scenes/Buddy/buddy.tscn:52-53,80-83`: `RectangleShape2D` 44x60 on a `CollisionShape2D` at `position (0,2)`, `scale (2,2)` → **88x120 world px, spanning y −58..+62** about the body origin. D4 (`docs/decisions.md:61-75`) is explicit that he is a single body; `buddy.gd:4-5` restates it.
- `mass = 3.0`, custom centre of mass `(0,10)` (`buddy.tscn:61-63`). `contact_monitor = true`, `max_contacts_reported = 8` (`buddy.tscn:64-65`, re-asserted `buddy.gd:25,64-65`).
- Layers: `collision_layer = 2` (buddy), `collision_mask = 5` (world|item) (`buddy.tscn:59-60`). Items are layer 4 / mask 7 (`tools/seed_bodies.gd:79-80,126-127`; `Scenes/Friendly/beanbag.tscn` `collision_layer = 4`, `collision_mask = 7`); walls layer 1 / mask 0 (`Scripts/Overlay/world_bounds.gd:34-36`); blast areas mask 2|4 (`seed_bodies.gd:81-82,228-229`). The fist is a rigid body, layer 4 / mask 7 / mass 11.5 (`Scenes/Powers/fist_power.tscn:17-19`).
- **No `lock_rotation`, no `PhysicsMaterial`, no damping overrides** anywhere on him (grep of `Scripts`, `Scenes/Buddy`: only NPCs lock rotation, `Scripts/World/npc_base.gd:247-250`). `project.godot` has no `[physics]` section, so gravity 980, friction 1.0, bounce 0.
- Grab region: `DraggableArea` (Area2D, `monitoring = false`, picks by mouse only — `Scripts/Bodies/draggable_area.gd:9-13`) with a 45x59 rect at `(0.5,2.5)` scale 2 → 90x118 (`buddy.tscn:85-91`). Drag is a `PinJoint2D` to the invisible `Handle` at `grip_offset` = origin (`Scripts/Bodies/base_draggable.gd:124-139`).
- Sprite: `Puppet` at scale 2, prototype 64-cell frames in the tscn (`buddy.tscn:74-78`) which `BuddyArt._ready` replaces with the 96-cell `bonehead.aseprite` frames (`Scripts/Buddy/buddy_art.gd:99-108`). `Face` is a code-built sibling `AnimatedSprite2D` at the same scale/position (`buddy.gd:97-104`).

**Registration bug worth knowing before placing parts.** Measured `art/src/bonehead_neutral_96.png`: opaque content is 48x63 at cell x 24..71, y 21..83, i.e. art px −27..+35 about the cell centre → **world y −54..+70**. The collider ends at +62, so the new art's feet draw 8 px below the collider bottom (he stands 8 px into the floor). The prototype 64-cell sprite (`Assets/base-bonehead.png`, 63 px in a 64 cell) was −62..+62 and did line up. Anything authored per-part must pick one registration (move shapes down 8 or `Puppet.offset` up 8) — the DraggableArea makes the same prototype assumption.

## 2. How hits reach him

- **Contact path** (the D7 model, `docs/decisions.md:105-118`): `buddy.gd:164-178` reads every contact in `_integrate_forces`, gates on `impulse < min_damage_impulse` (`:170` — note equality passes), per-source cooldown keyed by collider instance id (`:233-241`), attributes via `_attribute` (`:212-224`): `WeaponBase` → id+mult, `ThrowableBase`, `BaseDraggable` → id, **anything else → `&"world"`** (the four walls and the loop_check floor are scriptless `StaticBody2D`s). Position is `get_contact_local_position` (global). Hits are queued and dealt from `_physics_process` (`:153-160,199-208`).
- **Non-contact path** `take_impulse(impulse, source_id, mult, at)` (`buddy.gd:182-187`): throwable blasts (`Scripts/Bodies/throwable_base.gd:57-61`, `missile.gd:72-75`, `cluster_bomb.gd:99-100`, `proximity_mine.gd:58-59`), point blasts for guns/lightning (`Scripts/Bodies/Powers/gun_power.gd:69-72`, `lightning_power.gd:34-38`), beam (`beam_power.gd:81`), turrets (`Scripts/Bodies/turret_base.gd:149-150`), NPC blows/grapple (`Scripts/World/npc_base.gd:467,532`, `npc_gorilla.gd:54`). Every caller passes the blast origin, the click point or `buddy.global_position` — none knows a body part. `ExplosionUtil` directions and falloff are from `body.global_position` (`Scripts/Combat/explosion_util.gd:47-51,99-102`).
- Friendly items and the trampoline find him with `get_colliding_bodies()` (`Scripts/Bodies/friendly_base.gd:154-157`, `trampoline.gd:35`); the open hand and beam use `get_interaction_rect().grow(reach_padding).has_point(at)` (`open_hand_power.gd:84`, `beam_power.gd:90`).
- Damage: `impulse * 0.01 * mult` when `impulse >= 350` (`Scripts/Economy/economy_math.gd:47-50`; defaults `Scripts/Data/balance_data.gd:15-34`; `Data/balance.tres` overrides only `mastery_xp_per_damage`), capped at `0.5 * 400` (`buddy.gd:196`).
- `HitInfo` is `{amount, source_id, position, raw_impulse}` (`Scripts/Combat/hit_info.gd:7-10`). Eight consumers connect to `damage_dealt`: `audio_manager.gd:37`, `economy.gd:60`, `progression.gd:53`, `idle_brain.gd:219`, `grime_component.gd:28`, `mood_component.gd:24`, `fx_layer.gd:140`, `world_fx.gd:64`. Economy pays Bones **and a Dollar per hit and a `damage:world` contract event** regardless of source (`Scripts/Autoload/economy.gd:228-243`); mastery ignores `&"world"` because it is not an item (`progression.gd:266-268`).

## 3. Why the walk reads as "jumps over and over and takes damage"

The threshold in kinematic terms: 350 impulse at mass 3 = **116.7 px/s = a free fall of 7 px**. Anything that lands him from more than 7 px pays. That is the "too easy to trigger" half. The walk half is a chain of four things:

1. **`BaseDraggable.get_interaction_rect()` returns half his real collider.** `base_draggable.gd:50-59` scales `shape.get_rect()` by the *body's* `global_scale` (1) and ignores the `CollisionShape2D` node's own `(2,2)` scale and `(0,2)` offset. Items bake size into the shape (`seed_bodies.gd:146-156`, beanbag 44x30 unscaled) so they are right; the buddy alone comes out **44x60 instead of 88x120**. Everything the brain does with his body flows through that:
   - `_foot_offset()` = `(0,30)` (`idle_brain.gd:410-411`): the "push at his feet" lands 20 px below the COM and **32 px above the real feet**. With `WALK_GAIN` 30 the start-up force is ~3x the friction limit (`idle_brain.gd:118-127`), and a 3x-friction push 32 px above the contact on an 88-wide unlocked box exceeds the tipping torque (F*32 vs mg*44) — nothing keeps him upright (no `lock_rotation`), so he can go over onto his face, which is a `&"world"` contact.
   - `_climb()` feet = centre + 30 (`idle_brain.gd:382-386`): the rise is understated by 30 px, then floored at `CLIMB_CLEARANCE` 28, so **every hop is at least sqrt(2·980·28) = 234 px/s → a landing impulse of ~700, 2x the damage floor, ~7 damage attributed to `&"world"`** (bone burst, Bones, Dollar, −2.1 mood each). A hot-tub climb (collider 144x140, `Scenes/Friendly/hot_tub.tscn:8`) lands at ~1,500 impulse.
   - `_touching_target()` (`idle_brain.gd:656-657`) needs the toy's rect (+20 slack) to reach within 22 px of his centre, but his real half-width is 44 — **a toy resting against his side is 2 px outside "touching"** (beanbag: 44+22 = 66 > 22+22+20 = 64), and standing on top of it is not touching either (rect bottom +30 vs toy top at +62−20). Arrival is only ever reached by hopping into/onto the toy.
2. **Stall → hop loop.** `_tick_travel` marks a stall after one 2-s think without 16 px of progress (`idle_brain.gd:278-289`); from then `_climb()` fires every 0.55 s whenever |vy| < 50 (`:330-331,376-381`). Walking into a 1.2-mass beanbag (`beanbag.tscn`) pushes it along at walking speed, so the distance never closes → stall → hops. In `PHASE_PLAYING`, `not reached` walks and climbs every 0.55 s (`:336-338`) — with the 2-px gap that is a perpetual hop.
3. **The brain exempts `&"world"` from disturbing him** (`idle_brain.gd:517-532`), so the self-inflicted landings never stand him down; the loop persists until the knockout meter fills (~28 s at 14 damage/s). The trampoline comment already admits bounce landings pay Bones and knock him out every ~25 s (`idle_brain.gd:92-100`).
4. Wall contact at walking speed is exactly 350 (`_walk_speed` = min/mass, `idle_brain.gd:370-371`) and `impulse < min` lets equality through (`buddy.gd:170`) — marginal, but the wander turnaround at 120 px (`:151,398-405`) is what mostly saves it. `_walk` applies force mid-air too (no grounded gate, `:349-363`).

`loop_check`'s suite does not catch any of this: it asserts only 40 px of progress and `phase == playing` (`tests/integration/loop_check.gd:1432-1435`), which the hop path satisfies; nothing asserts zero `damage_dealt` during a walk to a floor toy. The contact suite drops him 300+ px to prove hits happen (`:1465-1476`) and only checks resting contact stays ≤ 1 hit (`:1514`).

## 4. What a multi-hitbox approach needs

- **Mechanism: more `CollisionShape2D`s on the same `RigidBody2D`, not child Areas.** `PhysicsDirectBodyState2D.get_contact_local_shape(i)` returns the owner shape index of each contact, so the existing loop in `buddy.gd:168-178` can map shape index → part with no new nodes; `intersect_shape` results also carry a `shape` index, so `point_blast` (`explosion_util.gd:95-103`) can attribute a pellet to a part if it returns it. The `HitBox (Area2D)` in `docs/architecture.md:320` was never built and is the wrong tool under D7: an Area has no contact impulse and would cost per-frame overlap monitoring. Shapes must be convex (circle + rects are fine) and should bake size rather than node scale, which also kills the `get_interaction_rect` bug once that helper unions all shapes.
- **Cost per physics frame:** three shapes vs one adds a few broadphase pairs and contact manifolds per tick — microseconds, well inside the 3% budget. The thing that actually pins CPU is any active body keeping the FPS governor awake (`Scripts/Autoload/overlay_manager.gd:53-56`); shape count does not change sleeping. `max_contacts_reported = 8` is enough; a resting three-shape body reports the feet shape's floor contacts, all under threshold.
- **Attribution:** add `part: StringName` to `HitInfo` (`hit_info.gd:7-13`), default `&"body"`. Fold the per-part multiplier into `amount` in `_queue_hit` (`buddy.gd:189-197`, before the cap) so the eight consumers need no change; `damage:<id>:<part>` contract keys can come later. Cooldown key becomes `(source id, part)` if a swing that clips skull then ribs should pay twice (`buddy.gd:233-241`). `take_impulse` callers (turrets, blasts, beam, NPCs) pass no part: pick the shape nearest `at`, or default `&"body"`.
- **Per-part reactions:** `_react()` (`buddy.gd:255-259`) drives `BuddyArt.STATE_ANIMATION`/`STATE_FACE` (`buddy_art.gd:25-43`). The face `dizzy` exists (used for knockout); the body `dizzy` tag (4 frames) is planned but unbuilt (`docs/art-direction.md:118`). A head hit can use face `dizzy` plus a longer `REACTION_SECONDS` today; a leg wobble is either a new tag or a code-side skew that must move face and body together (`buddy_art.gd:84-87,137-142`). Knockout is frozen choreography and untouched (`buddy.gd:288-294`).
- **Walk and drag:** with parts, the walk must push at the real feet (needs the rect fix) and should `lock_rotation = true` like NPCs (`npc_base.gd:247-250`) — otherwise a body on its side puts the skull shape at floor level and every landing becomes a head hit. `apply_force`'s unrotated offset (`idle_brain.gd:407-409`) is then exact. The drag joint and the DraggableArea are independent of physics shapes (`base_draggable.gd:131-139`). The calibration lever the owner is asking for falls out naturally: a **feet multiplier < 1** makes drops and hop landings cheap without lowering weapon damage, and `min_damage_impulse` can stay where weapons need it. The walk itself also needs the climb to be the exception (rise floor 28 → 0 when feet are already above the toy, and never while pushing a light toy).
- Passthrough polygon was removed (`overlay_manager.gd:259-277`), so extra shapes feed nothing else.

## 5. Art constraints on part placement (art px about the 96-cell centre; ×2 for world)

Row profile of `bonehead_neutral_96.png`: skull incl. headphones y −27..+5 (44–48 wide from −16 to +4; headband teal −23..−19; ear cups −9..+4 both sides); torso/pelvis +5..+21, only 28 wide; feet +22..+35, 34–38 wide. A first cut: skull circle r≈24 at (0,−11) art → r 48 at (0,−22) world; torso rect 28x16 at (0,+13) → 56x32 at (0,+26); feet rect 38x14 at (0,+28.5) → 76x28 at (0,+57). The face sits in the lower half of the skull (face png opaque y 45..58 → art −3..+10); `postprocess.head_anchor` takes the first row with ≥12 white px (`art/tools/postprocess.py:154-160`), i.e. −14, below the headband.

The idles **translate** rather than deform — head and feet move together, body stays 63 px (`docs/roadmap.md:603-606`); per-frame offsets reach −11 (`idle`, `happy`), −13 (`hurt`), +5 (`idle_sad`) in `Data/buddy_face_offsets.json`, i.e. the drawn skull is up to 26 world px above a static skull shape at the top of a bob, and the whole sprite is 8 px low against the collider today (§1). Shapes should stay static (physics must not chase animation) and the skull shape should be sized for the excursion; `travel()`'s bob is only 1.5 px (`buddy_art.gd:88`). Hats are planned to ride the same offsets (`docs/game-design.md:253`), so the head anchor is already the agreed "where the head is". `buddy.tscn` has not been opened in the editor (`buddy.gd:78-81`; CLAUDE.md), so authoring shapes is a scene edit the art pass has to own.

---

## Proposal A — minimal change

# Physics-first proposal: give him legs, and bill only external energy

Read-only; nothing run. Every number below is either read from source (cited) or computed from those values; the two things I could not verify without a run are flagged in §7.

## 1. Diagnosis I am acting on

Four verified defects compound into "he jumps toward things and gets hurt". Two of the three readers' reports contain an error each; corrected here.

**(a) His own rect is half his real size.** `BaseDraggable.get_interaction_rect()` (`Scripts/Bodies/base_draggable.gd:50-59`) multiplies `shape.get_rect()` by the *body's* `global_scale` and ignores the `CollisionShape2D` node's own transform. The buddy's shape is 44x60 on a node at `position (0,2)`, `scale (2,2)` (`Scenes/Buddy/buddy.tscn:52-53,80-83`), so the real collider is 88x120 spanning y −58..+62 but the rect reports 44x60 about the origin. Every item bakes size into the shape (beanbag: 44x30, no node scale, `Scenes/Friendly/beanbag.tscn:8-9,29-30`), so he is the only body this is wrong for. Consequences, all in `Scripts/Buddy/idle_brain.gd`:
- `_foot_offset()` (`:410-411`) is `(0,30)`, not `(0,60)` as the movement reader states — 20 px below the CoM at `(0,10)` (`buddy.tscn:63`) and 32 px *above* the real feet.
- `_climb()` (`:382-384`) measures "feet" at `y+30`; with real feet at `y+62`, `feet − top` is negative for any floor toy, floors at 0, and every climb is the `CLIMB_CLEARANCE` 28 px minimum: v = √(2·980·28) = 234 px/s, landing impulse ≈ 3·234 = **702**, twice the 350 floor (`Scripts/Data/balance_data.gd:15`), 7 damage.
- `_touching_target()` (`:656-657`) with a beanbag: contact side-by-side needs |dx| < 22+22+20 = 64, but the real bodies touch at |dx| = 44+22 = 66. Standing on top of it: his rect bottom is at y+30 = floor−92+30 = floor−62; the grown beanbag rect top is floor−50 → no overlap. **Neither beside it nor on it counts as "reached"**, so `PHASE_PLAYING`'s `not reached` branch (`:336-338`) walks and climbs forever with no stall gate, and `_enter()` zeroes `_climb_timer` (`:599`) so the first such tick hops immediately.

**(b) Locomotion is a force fight, with rotation free.** `_walk()` (`:349-363`) applies `gap · mass · WALK_GAIN(30)` every physics tick, no grounded gate, no ramp. From rest that is 10,500 N against 2,940 N of floor friction; on a sign flip (`:326,:337` when he crosses the target's centre, `:398-405` wander) the gap doubles to 21,000 N. Nothing locks rotation (grep: only NPCs do, `Scripts/World/npc_base.gd:247-250`; the buddy only zeroes it in knockout and rescue, `Scripts/Buddy/buddy.gd:294,354`). The tipping threshold for an 88-wide box with CoM 52 px above the floor is g·44/52 ≈ 829 px/s²; the first tick's net acceleration is (10500−2940)/3 = 2,520 px/s², so every start and reversal rocks him onto a corner (computed, not observed — §7). Steady-state cruise is where push = friction: gap = 2940/90 ≈ 33 → **he cruises at ~84 px/s, never the 117 the code derives** (`:370-371`), so `effort` (`:358`) never exceeds ~0.72.

**(c) The damage floor is a 7-px fall, and nothing asks who put the energy in.** `buddy.gd:164-178` bills every contact impulse ≥ 350 (`<` at `:170`, so equality pays) to whatever it touched; scriptless bodies → `&"world"` (`:224`); a landing on the beanbag → `&"beanbag"` (`:222-223`), which pays Bones (`Scripts/Autoload/economy.gd:228-233`), a Dollar (`:242`, a D31 leak for unattended play), beanbag mastery XP (`Scripts/Autoload/progression.gd:313-314`), −2.1 mood per hop (`Scripts/Components/mood_component.gd:51-52`), and the hurt crouch (`buddy.gd:207`). The brain then exempts `&"world"` and the current toy from standing him down (`idle_brain.gd:534`), so the loop runs until the 400-damage knockout (`balance_data.gd:34`). The damage reader is right that the walk force is integrated before the contact solve, so a wall at walking speed sees m·v plus F·dt ≈ 350+175 — the "wall damage is too easy" half of the report.

**(d) The test cannot see it.** `tests/integration/loop_check.gd:1352-1455` asserts 40 px of 260 closed, `phase == playing`, Hearts up (paid by the beanbag's own contact rate, not by the walk), and one flipped frame. `_observe` is connected only in the contact suite (`:1469`). A hop-and-stumble gait passes every line.

The owner's multi-hitbox instinct addresses a different problem (head vs shins pays differently — juice). A self-landing and a bat to the shins arrive on the same shape; only *provenance* separates them. Hitboxes can layer on later without touching anything below.

## 2. Exact changes

### `Scripts/Bodies/base_draggable.gd` — `get_interaction_rect()` (`:50-59`)
Use the shape node's transform: `extent = (r.size * 0.5 * collider.global_scale).abs()`, centre on `collider.global_position`. Items are unaffected (baked shapes, identity node transform); the buddy becomes 88x120 at (0,+2). Consumers to re-check: `open_hand_power.gd:84` and `beam_power.gd:90` (reach grows to the real body — correct), and the three brain call sites above.

### `Scripts/Buddy/buddy.gd` — new "legs" section; the buddy owns his locomotion
- `_ready()`: `lock_rotation = true`, unconditionally. Same reasoning as `npc_base.gd:247-250`; the knockout already forces rotation to 0 and the *art* topples him (`buddy.gd:288-299`), so nothing in the game wants him rotated.
- State: `var walk_dir := 0.0`, `var walk_speed := 0.0`, `var _grounded := false`, `var _blocked := false`, `var _launched := false`, `var _rest_since_msec := 0`.
- API: `set_walk(direction: float, speed: float)` (sets intent, `sleeping = false` when leaving 0 — a velocity write does not wake a sleeping body), `stop_walk()`, `step(rise_px: float)`, `mark_launched()`, `is_grounded() -> bool`, `is_blocked() -> bool`.
- `_integrate_forces(state_)`: **one pass over contacts** computing `_grounded` (any `get_contact_local_normal(i).y < -0.7`) and `_blocked` (any `normal.x * walk_dir < -0.7` whose collider is a `StaticBody2D` or a `RigidBody2D` with `mass >= 2 * mass`) — then, if `walk_dir != 0 and _grounded and not _blocked and not dragging and not freeze`: `v.x = move_toward(v.x, walk_dir * walk_speed, WALK_ACCEL * state_.step)`; write back via `state_.linear_velocity`. Then the existing damage loop, reordered: attribute → provenance gate (§3) → floor → cooldown. Moving `_cooldown_ready` last matters: today (`:173`) it stamps the floor's 0.15 s before the hit is even priced, so a discarded self-contact would otherwise eat the cooldown of a real one.
- `step(rise_px)`: only if `_grounded`; `v.y = -min(sqrt(2·g·rise_px), MAX_STEP_SPEED)` written in the same place. Ballistic, but now unpaid and rarely fired (below).
- `_launched` is set by: `_end_drag()` when `was_dragging` (`:147-151`); `take_impulse()` (`:182-187`, every blast/gun/beam/turret/NPC call site — all 11 already route through it); any contact hit that *passes* the gate; and `Trampoline` (`Scripts/Bodies/trampoline.gd:49` writes his velocity directly — add `if rigid is Buddy: (rigid as Buddy).mark_launched()`). Cleared when `_grounded and linear_velocity.length() < REST_SPEED` for `REST_SECONDS` continuously. `dragging` counts as launched (a hand is external).
- Delete nothing else. `MAX_CONTACTS` 8 is enough (`:25`).

### `Scripts/Buddy/idle_brain.gd`
- Rewrite the header paragraph at `:17-20`: the brain expresses *intent*, the buddy integrates it. The rule "never write `global_position`" stands; a velocity write inside `_integrate_forces` is the solver's own contract, not a teleport — contacts, the pin joint and the impulse model are all resolved after it.
- `_walk()` (`:349-363`): keep the `art.travel()` call, replace the force with `_buddy.set_walk(direction, _walk_speed())`. Delete `WALK_GAIN`, `_foot_offset()`.
- `_climb()` (`:376-386`) → `_step()`: fire only when `_buddy.is_blocked()`, `_buddy.is_grounded()`, `_step_timer <= 0`; rise = `_rect_of(_target).position.y` − (real feet: `_buddy.get_interaction_rect().end.y`) + `STEP_CLEARANCE`; skip if rise ≤ 0. Call sites: TRAVELLING keeps the `_stalled_seconds > 0.0` gate (`:330-331`) *and* the blocked gate; PLAYING `not reached` (`:336-338`) walks only, and steps only when blocked; `ROUTINE_BOUNCE` (`:339-342`) keeps a deliberate hop — the mat's launch is external and *should* pay, exactly as the comment at `:92-100` intends.
- `_touching_target()` (`:656-657`): fixed rect overlap **or** `_target in _buddy.get_colliding_bodies()` — real contact is what the toy pays on (`Scripts/Bodies/friendly_base.gd:154-157`), so reached and paid agree.
- `_stand_down()`, `_finish()`, and the `freeze or dragging` early-out (`:308-309`): call `_buddy.stop_walk()`.
- `_walk_speed()` (`:370-371`) stays derived from `min_damage_impulse / mass` = 116.7 px/s; with no force term, a wall now sees exactly m·v = 350, and the world floor below is 5x that.

### `Scripts/Data/balance_data.gd` + `Scripts/Economy/economy_math.gd`
- New knobs: `world_unflagged_min_impulse := 1800.0`, `thrown_item_speed := 250.0`, `walk_accel := 600.0`, `step_clearance := 12.0`, `step_interval := 1.0`, `rest_speed := 60.0`, `rest_seconds := 0.3`. `min_damage_impulse` 350 and `damage_cooldown` 0.15 unchanged.
- Pure `EconomyMath.contact_pays(impulse, is_weapon, other_speed, launched, min_impulse, unflagged_min, thrown_speed) -> bool`, unit-tested in `tests/run_tests.gd` beside `:405-412`.

### `Scripts/Autoload/economy.gd:242`
`if info.source_id != &"world": grant(DOLLARS, …)`. The floor is not an act (D31); with provenance, world hits are now only ever the tail of a player's throw, which already paid its Dollar on the weapon contact.

## 3. Balance numbers

| Knob | Value | Why |
|---|---|---|
| `min_damage_impulse` | 350 (keep) | Weapons/throwables/NPCs/blasts always mean it. A bat at 160 px/s registers today; lowering or raising it moves the harm ladder the assessment wants CSV-measured first. |
| Provenance gate (world + friendly-item contacts) | pays iff `launched`, or the other body is moving ≥ 250 px/s, or impulse ≥ 1800 | He cannot move a toy faster than his 117 px/s walk, so a toy at 250+ was thrown or dropped ≥ 32 px by a hand. 1800 at mass 3 = 600 px/s = a 184 px fall: no self-motion reaches it (largest self step lands from `step_clearance` 12 px → 153 px/s → 460; falling off the top of the hot tub, 140 px, → 524 px/s → 1570, still free). The loop_check drop (`loop_check.tscn:18-23`, floor top y=500; buddy from y=100, feet +62 → 276 px) → 735 px/s → 2,200, still pays. |
| Flagged world contact | 350 (today's floor) | A player-caused landing keeps paying exactly as now; the weapon-into-wall carry-through pays every 0.15 s as now. |
| `damage_cooldown` | 0.15 (keep) | No separate world cooldown needed once self-contacts are dropped rather than throttled. |
| `walk_accel` | 600 px/s² | 0→117 in 0.2 s ("starts him inside a fifth of a second", the intent at `:120-127`), under the 829 tipping figure even if rotation were free. Godot friction at μ=1 pulls 16 px/s per tick against the write; he settles ~8 px/s under target — negligible. |
| `step_clearance` / `step_interval` | 12 px / 1.0 s | 28 px was compensating for the 32-px feet error. One try a second: a stall (8 s, `:87`) is 8 tries, all free. |
| `rest_speed` / `rest_seconds` | 60 px/s / 0.3 s | Above `MOTION_FLOOR` 24, half walk speed, below any trampoline residual; 18 ticks of stillness. |

Net effect on the economy: the trampoline stays a Bones engine at the rate the header already accepts; every other idle activity stops minting Bones, Dollars, comfort-item mastery XP and `damage:beanbag` contract counts.

## 4. How the art plugs in

`BuddyArt.travel(direction, effort)` (`Scripts/Buddy/buddy_art.gd:150-153`) stays the seam, as `docs/uplift-m3.7.md:84-86` promises. Two things improve for free: `effort` becomes honest (velocity control reaches the full 117 px/s, so the bob hits 1.0 instead of capping at ~0.72), and stops are exact, so `TRAVEL_DECAY` (`:92`) fades the bob from a real halt rather than a friction slide.

When the `walk` tag lands: in `_advance_travel()` (`:158-174`), `if _travel > 0 and _state_of_body() == &"idle" and has_animation(&"walk"): _play_body(&"walk"); body.speed_scale = lerp(0.6, 1.0, _travel)`; when `_travel` reaches 0 go back through `_on_mood_changed(Economy.mood)` (`:214-229`) so the mood idle returns. Face offsets per walk frame come from `postprocess.py` into `buddy_face_offsets.json` like every other tag. `Buddy.is_grounded()` lets the art hold the walk frame during a step and, later, drive a landing squash; `hurt`/`happy`/knockout outrank it via the existing state check.

## 5. Per-frame cost and the idle budget

- Asleep buddy: `_integrate_forces` does not run; brain `_physics_process` is off while WATCHING (`idle_brain.gd:233,601`). **Zero change to the idle desk.**
- Awake buddy: the contact loop already runs every tick (`buddy.gd:168`); the grounded/blocked scan adds one `get_contact_local_normal` and two compares per contact, ≤ 8 contacts. One `move_toward` and one msec compare. No new nodes, Areas, timers or signals. `lock_rotation` is a solver flag.
- The FPS governor keys on active bodies (`Scripts/Autoload/overlay_manager.gd:53-56`); he is active while walking today and still will be, and sleeps sooner because he stops dead instead of dithering under a P-controller. Low Power caps `max_fps` (`overlay_manager.gd:241-242`), not the physics tick; `move_toward(…, accel * state_.step)` is tick-rate independent.

## 6. loop_check assertions that would prove it

In "idle brain — he goes and plays" (`loop_check.gd:1352-1455`), connect `_observe` for the 420-frame walk:
1. `walking to a toy costs him nothing` — `_observed.is_empty()`.
2. `he stays upright` — `absf(buddy.rotation) < 0.01` on every frame.
3. `he arrives and stays` — after `phase == playing`, `beanbag in buddy.get_colliding_bodies()` on ≥ 90% of remaining frames and `absf(linear_velocity.y) < 100` on ≥ 95% — a hop loop leaves contact every 0.55 s and fails both.
4. `a wall stops him without paying` — add a 20x200 `StaticBody2D` between him and a second toy; 600 frames; assert no `&"world"` `HitInfo`, then `phase == wandering` (the stall path, `:288-289`).
5. `he can step onto a low toy` — beanbag directly in his path with the target beyond it; assert he ends past it, still zero hits.

In "contact impulse" (`:1457-1527`): keep the 276-px drop (passes via the 1800 fallback); add a **100-px** drop twice — unflagged → `_observed.is_empty()`; after `buddy.mark_launched()` → one hit ≥ 350. That pins both sides of the gate. Add `is_grounded()` true after settling and false 5 frames into a `step(40)` — this is the assertion that catches the normal-sign question in §7.

Trampoline: spawn one under him, `pretend_idle()`, 600 frames; assert ≥ 1 world hit (bouncing must keep paying) and Dollars unchanged.

`run_tests.gd`: `contact_pays` truth table, six rows.

## 7. Risks, and what this does not solve

- **Cannot verify without a run:** the sign of `get_contact_local_normal()`. Godot's `GodotBodyPair2D` hands body A `−normal` and body B `+normal`, i.e. each body gets the normal pointing *toward itself*, so floor reads `(0,−1)` — assertion 6 above exists to prove it on first run. Second unknown: the exact residual of friction against the velocity write; harmless either way.
- `lock_rotation` removes the tumble after a bat hit. I think that is right (D4: expression is animation; NPCs already do it) — if it is missed, unlock only while `_launched`.
- The wider rect enlarges pet and beam reach to his real body; `ui_check` pet-at-point tests are a superset and should stay green — check.
- A step is still ballistic; unpaid, but a player watching sees a hop over a sponge. That is what a step *looks* like at this scale.
- Falling off a tall toy is free (≤ 1570 < 1800). Acceptable; document.
- **Not solved:** the stride itself (assessment item C1, `docs/assessment-2026-09.md:223`); the 8-px sprite-vs-collider registration the body reader found (art-pass item); "in" the hot tub vs "against" it (the `sit_in` family); the trampoline's unattended Bones rate (by design, `idle_brain.gd:92-100`); head/feet hit multipliers (layer later via `get_contact_local_shape(i)` in the same loop).

## 8. Effort

| Piece | Hours |
|---|---|
| `get_interaction_rect` fix + consumer check | 1 |
| Buddy legs: intent, contact scan, velocity write, rotation lock, launched flag, provenance gate, reorder | 4 |
| Flag call sites (`_end_drag`, `take_impulse`, trampoline) + Dollars line | 0.5 |
| Brain rewire (`set_walk`, `_step`, touching-by-contact, header) | 2 |
| Balance knobs + pure `contact_pays` + unit tests | 1 |
| loop_check: 7 new/changed assertions and getting them green against real physics (where the two unknowns land) | 4–6 |
| Sandbox play on both monitors, wall/hot tub/boombox/trampoline by hand | 1 |
| **Total** | **~14–16 h** |

Walk-tag art and its hook-up are outside this (hook-up ≈ 1 h once the tag exists).

Files: `C:\Users\George\Godot Projects\Projects\bonehead-friend\Scripts\Buddy\idle_brain.gd`, `…\Scripts\Buddy\buddy.gd`, `…\Scripts\Buddy\buddy_art.gd`, `…\Scripts\Bodies\base_draggable.gd`, `…\Scripts\Bodies\trampoline.gd`, `…\Scripts\Data\balance_data.gd`, `…\Scripts\Economy\economy_math.gd`, `…\Scripts\Autoload\economy.gd`, `…\Scenes\Buddy\buddy.tscn`, `…\tests\integration\loop_check.gd`, `…\tests\integration\loop_check.tscn`, `…\tests\run_tests.gd`.

---

## Proposal B — physics-first

# Hitbox-first proposal: Bonehead's body, and the walk that falls out of it

## 1. Diagnosis acted on (verified against source)

Three defects compound into "he jumps at things and gets hurt"; the multi-hitbox design fixes the first two as a by-product and gives the third a principled home.

1. **The brain does not know where his feet are.** `BaseDraggable.get_interaction_rect()` (`Scripts/Bodies/base_draggable.gd:50-59`) multiplies `shape.get_rect()` by the *body's* `global_scale` (1,1) and ignores the `CollisionShape2D` node's own `scale (2,2)` / `position (0,2)` (`Scenes/Buddy/buddy.tscn:80-83`). The physics box is 88x120 spanning y −58..+62; the brain sees 44x60. So `_foot_offset()` (`idle_brain.gd:410-411`) pushes at +30 (32 px above the real feet), `_climb()` measures rise from +30 instead of +62 (`idle_brain.gd:382-384`), and `_touching_target()` (`:656-657`) fails for a beanbag resting against his side (his half-width is taken as 22, not 44) and for him standing on top of one. Arrival is therefore only ever achieved by hopping, and every hop is `rise + 28` px at minimum (`:135`, `:384`) → v ≥ 234 px/s → landing impulse ≥ 700 → ~7 damage billed to `&"world"` (`buddy.gd:170,224`; `economy_math.gd:47-50`), with mood −2.1 (`mood_component.gd:51-52`) and Bones + a Dollar (`economy.gd:231-242`). The movement reader's "(0,60)" foot offset is wrong; the body reader's "(0,30)" is what the code does.
2. **He is a free-rotating box driven by a 3x-friction shove.** No `lock_rotation`, no material, default gravity/friction (`project.godot` has no `[physics]` section, only layer names at lines 63-70). `WALK_GAIN 30` (`idle_brain.gd:127`) gives 10,500 N from rest against 2,940 N of floor friction; he rocks onto a corner at every start, stop and reversal (`:326`, `:337`, `:398-405`). Godot's own precedent is `npc_base.gd:247-250` — "locking rotation is what separates a character from a prop" — and he never gets it; `buddy.gd:294,354` zero his rotation by hand instead.
3. **The damage floor is a 7 px fall.** `min_damage_impulse 350` (`balance_data.gd:15`) at mass 3 (`buddy.tscn:61`) is 117 px/s. Any self-propelled landing pays, the per-collider cooldown lets the floor pay 6.7 Hz (`balance_data.gd:25`, `buddy.gd:233-241`), `PHASE_PLAYING` climbs with no stall gate (`idle_brain.gd:336-338`), and the brain exempts `&"world"` from interrupting the loop (`:534`). Nothing asserts otherwise: the idle suite checks 40 px of progress and `phase == playing` (`loop_check.gd:1432-1435`) and never connects `_observe`.

Art registration (measured with System.Drawing, since the 96-cell sheet is what `BuddyArt._ready` loads, `buddy_art.gd:101-104`): `art/src/bonehead_neutral_96.png` is opaque at y 21..83 → world −54..+72 at 2x, versus the prototype `Assets/base-bonehead.png` at −62..+64. The new art draws **~9 px low** against the collider. Per-row widths: skull 20→48 art px (rows 21-54), torso 28 (rows 55-69), feet 34-38 (rows 70-83). Those rows are the hitboxes.

## 2. Exact changes

**`Scenes/Buddy/buddy.tscn` — opened in the editor for the first time (CLAUDE.md says the art pass owns this; this is it).**
- `Puppet.position = (0, -9)` so art spans −63..+63. `Face` copies `sprite.position` (`buddy.gd:101`) and `BuddyArt` bobs relative to `_body_home` (`buddy_art.gd:116,174`), so both follow for free.
- Replace the one `CollisionShape2D` with three, sizes **baked into the shape, no node scale** (the `seed_bodies.gd:140-156` convention):
  - `Skull`: `RectangleShape2D 88x64` at `(0,-31)` → y −63..+1
  - `Torso`: `RectangleShape2D 56x34` at `(0,18)` → y +1..+35 (art torso is 28 px = 56 world)
  - `Feet`: `RectangleShape2D 88x28` at `(0,49)` → y +35..+63
  Same 88 px footprint and wall behaviour as today; 1 px taller. Rects, not circles: a round skull under a locked rotation buys nothing, and rects stack with no seam.
- `lock_rotation = true`, `can_sleep = true` (default). Keep `center_of_mass (0,10)`.
- `DraggableArea` rect → 88x126 baked, position (0,0). Author `MoodComponent`, `GrimeComponent`, `Face`, `BuddyArt` as real nodes while the scene is open (the `_ensure_components()` fallback at `buddy.gd:82-110` stays for tests).
- New exports on the root: `skull_shape`, `torso_shape`, `feet_shape`.

**`Scripts/Combat/hit_info.gd`** — add `var part: StringName = &"torso"` as a fifth `_init` parameter with a default; the eight consumers (`audio_manager.gd:37`, `economy.gd:60`, `progression.gd:53`, `idle_brain.gd:219`, `grime_component.gd:28`, `mood_component.gd:24`, `fx_layer.gd:140`, `world_fx.gd:64`) compile unchanged.

**`Scripts/Data/balance_data.gd`** — add `world_damage_impulse: float = 1000.0`, `skull_damage_mult: float = 1.5`, `feet_damage_mult: float = 1.0`, `skull_daze_damage: float = 20.0`. `min_damage_impulse` stays 350 for weapons/throwables/NPCs. No `balance.tres` edit needed (defaults), but pacing_sim runs regardless.

**`Scripts/Economy/economy_math.gd:47-50`** — `damage_from_impulse` becomes a knee: `return maxf(0.0, impulse - min_impulse) * per_impulse * maxf(0.0, weapon_mult)`. With two different floors a cliff at 1000 would pay 10 damage for 1001 and nothing for 999. `tests/run_tests.gd:406` ("at the floor deals damage") flips to "at the floor deals nothing, one unit above pays"; the 4000-impulse tests at `:409-412` still hold.

**`Scripts/Buddy/buddy.gd`**
- `_ready`: build `_part_of_shape: Array[StringName]` indexed by body shape index via `get_shape_owners()` → `shape_owner_get_shape_index(owner, 0)` and the three exports; if the exports are null (unauthored scene) every shape is `&"torso"`. Also `lock_rotation = true` here so the code does not depend on the tscn having been saved.
- `_integrate_forces` (`:164-178`) reordered: **classify source without side effects → pick floor → cooldown → attribute**. Today `_attribute` calls `w.register_use()` (`:217`) *after* the 350 gate; the new floor must sit before it or a bat that grazes his feet at 400 would count as a landed swing while paying nothing. Add `_source_kind(src) -> int` (WORLD / FRIENDLY / TOY / WEAPON) with no side effects. Per contact: `part = _part_of_shape[state_.get_contact_local_shape(i)]`, `floor = _floor_for(kind, part)`, and `grounded = true` when `part == &"feet"` and the contact point is below the Feet centre (`get_contact_local_position(i).y > global_position.y + 49`, which is rotation-safe because rotation is locked; `get_contact_local_normal` is the proper version once loop_check has pinned its sign). Cache `_grounded_tick = Engine.get_physics_frames()` and expose `is_grounded()`.
- `_floor_for`: `WORLD` → `world_damage_impulse`; `FRIENDLY` (any `FriendlyBase`) and `part == feet` → `INF` ("kindness never hurts": landing on a beanbag is not a beanbag hitting him, and today that grants beanbag *damage* mastery XP at `progression.gd:313-314` and a `damage:beanbag` contract count at `economy.gd:239`); everything else → `min_damage_impulse`. Trampoline is a bare `BaseDraggable` (`trampoline.gd:2`), so the mat keeps 350 and stays the designed Bones engine (`idle_brain.gd:92-100`).
- `_queue_hit` folds `part` mult into `amount` before the cap at `:196`, and passes `part` into `HitInfo`.
- `take_impulse` (`:182-187`) gains `part_at(at)` — local y < +1 skull, < +35 torso, else feet — so blasts, turrets and NPC blows (`gun_power.gd:72`, `turret_base.gd:150`, `npc_base.gd:467`) attribute by where they landed with no caller change.
- `_deal` (`:199-208`): `_react(&"dazed")` instead of `&"hurt"` when `part == skull and amount >= skull_daze_damage`, with `_reaction_until` at 0.8 s instead of `REACTION_SECONDS 0.45`.
- Remove `global_rotation = 0.0` / `angular_velocity = 0.0` at `:293-294,354-356` (moot under lock).
- Override `get_interaction_rect()` on Buddy to return the union of the three shapes (88x126). Scoped to Buddy on purpose: fixing `BaseDraggable`'s version would also change the bat (whose grip shape is currently ignored, `seed_bodies.gd:140-150`) and with it `open_hand_power.gd:84` / `beam_power.gd:90` reach — a separate change.
- Cooldown stays keyed per collider (`:233-241`). A swing that clips skull then torso in 0.15 s pays once; the part recorded is the first contact that cleared its floor. Keying by (collider, part) needs a composite key allocation per contact and buys nothing yet.

**`Scripts/Buddy/idle_brain.gd`**
- `_walk` (`:349-363`): `if not _buddy.is_grounded(): return` (no air control — the "forward leap" is the walk force applied on the same tick as the hop, `:337-338`). Force = friction feed-forward plus a gentler P term: `apply_central_force(Vector2(direction * mass * gravity + gap * mass * WALK_GAIN, 0))` with `WALK_GAIN` 30 → 12. Central, because with rotation locked the foot offset does nothing; `_foot_offset()` is deleted.
- `_walk_speed` (`:370-371`): `minf(WALK_SPEED_MAX 120, 0.5 * world_damage_impulse / mass)` = 120 px/s — derived from the *wall's* floor now, with a 2x margin instead of none.
- `_climb` (`:376-386`): grounded from `is_grounded()` not `|v.y| < 50` (`:379`, which re-fires at the apex of any hop ≥ 539 px/s); `feet` from the corrected rect; `CLIMB_CLEARANCE` 28 → 12; skip entirely when `rise <= 0`; `CLIMB_INTERVAL` 0.55 → 1.5; `MAX_CLIMBS_PER_TRIP = 3` reset in `_enter`.
- `_physics_process` playing branch (`:336-338`): climb only after `_unreached_seconds > 1.0` (accumulated in the same function), i.e. the same "walking has stopped working" rule the travelling branch already states at `:327-331`.
- `_touching_target` (`:656-657`) is unchanged in code and now correct in effect: a beanbag against his side (44+22+20 ≥ 66) and under his feet both intersect.

**`Scripts/Buddy/buddy_art.gd`** — `STATE_ANIMATION[&"dazed"] = &"dizzy"`, `STATE_FACE[&"dazed"] = &"dizzy"`; `dizzy` is a 4-frame tag still unbuilt (`docs/art-direction.md:122`), and `_play_body` skips a missing animation (`buddy_art.gd:237-242`), so the face carries it until the body exists. Walk hook in §4.

**`Scripts/Autoload/economy.gd:242`** — leave `dollars_per_hit` alone. The leak (`&"world"` hits minting Dollars) closes itself because the walk no longer produces world hits; a player drop is presence and should pay.

## 3. Balance numbers

Impulse on him = 3 × Δv for a clean landing (mass 3), plus `F·dt` from any push on the same tick.

| Event | Impulse | Today | Proposed |
|---|---|---|---|
| Walk into wall at 120 px/s, plus 2,940 N feed-forward that tick | 360 + 49 ≈ 410 | 4.1 (exactly at/over 350) | 0 (floor 1000) |
| Minimum hop (rise 12 + 0) landing | 3·√(2·980·12) = 460 | 7 (rise 28) | 0 |
| Hop onto a 30 px beanbag, lands on beanbag | ~900 | 9, billed to `beanbag` | 0 (feet on friendly) |
| Missed hot-tub climb (rise 152 → 546 px/s) lands on floor | 1,638 | 16 | (1638−1000)×0.01 = 6.4, feet, ≤3 per trip |
| Player drop 100 / 300 / 600 px | 1,330 / 2,300 / 3,250 | 13 / 23 / 33 | 3.3 / 13 / 22.5 |
| Trampoline first landing (`minimum_launch 320`, `trampoline.gd:16`) | 960 | 9.6 | (960−350)×0.01 = 6.1 — mat keeps the 350 floor |
| Bat 8 kg at 2,500 px/s, torso / skull | 5,450 | 54.5 | 51 / 76.5 |
| Bat carries him into the wall at 500 px/s | 1,500 | 15 | 7.5 |

Reasoning:
- **World floor 1000 = 333 px/s = a 57 px fall.** Every free hop the brain needs (rise ≤ 57 px covers every floor toy but the hot tub, massage chair class) lands under it; a wall slam from a real swing is well over it. A wall hit is always the *second* payment for one swing, so it is right that it is the smaller half.
- **Weapon floor stays 350.** The bat registers at ~160 px/s (reduced mass 2.18); the assessment schedules that ladder for CSV retune, not this change.
- **Skull ×1.5, torso ×1.0, feet ×1.0.** The feet earn their keep through the floor and the friendly exemption, not a multiplier — a ×0.75 on top would triple-nerf drops (3.3 → 2.5 at 100 px). A headshot at 1.5x is the juice reason for the parts existing.
- **Cooldown** stays 0.15 s per collider; with the 1000 floor the floor cannot pay from anything the brain does, so a longer world cooldown is unnecessary.
- **Self-motion exemption is structural, not a flag:** IdleBrain only ever produces feet landings on world (< 1000) or on friendly items (INF). No "launched" bookkeeping.
- **Knee vs cliff:** the bat loses 3.5 damage of 54.5 (6%); mace 4.8 of 67. Inside the retune the assessment already schedules.

Pacing sim must be re-run (CLAUDE.md rule on balance numbers); the trampoline change is the one it may notice.

## 4. How the walk art plugs in

`BuddyArt.travel(direction, effort)` (`buddy_art.gd:150-153`) is already the seam. Add: in `_advance_travel`, when `_travel > 0`, `has_animation(&"walk")` and the buddy state is `&"idle"`, `_play_body(&"walk")` and set `body.speed_scale = maxf(0.35, _travel)`; when `_travel` decays to 0, hand back to `_on_mood_changed(Economy.mood)` for the mood idle. Bob height goes to 0 while the walk tag plays (the tag carries its own bob). Constraints for the tag (`uplift-m3.7.md:122`): 8 frames, 63 px body, feet drawn inside the Feet box (+35..+63, i.e. bottom 14 art px) so the plant reads at the collider bottom; fps chosen so `walk_speed × cycle_seconds ≈ 2 strides` — at 120 px/s an 8-frame tag at 10 fps is 96 px per cycle, 48 px per step, which is his leg length. `effort` is now `|v.x| / 120` and so ranges 0.35..1 honestly (today it caps at ~0.72 because he never reaches 116.7). `postprocess.py` writes `walk` face offsets like any tag (`art/tools/postprocess.py:171-201`). The shapes stay static; the head's ±11 px translation in the idles (`Data/buddy_face_offsets.json`) is inside the Skull rect's slack.

## 5. Per-frame cost

`_integrate_forces` runs only on an awake body; asleep on the floor it is never called and `_grounded` is stale but unread. Awake, the new work per contact is one `get_contact_local_shape` int read, one array index, one float compare — on the 1-2 floor manifold points the Feet box produces. Three shapes add ~2 broadphase pairs; `lock_rotation` removes a DOF from the solver. The brain's structure (`set_physics_process(false)` while watching, `idle_brain.gd:233,601`) is unchanged, and the FPS governor is already keyed on active bodies (`overlay_manager.gd:53-56`), so a walking buddy costs what it costs today. Nothing allocates per tick; `HitInfo` allocation is per hit as before, and there are now far fewer hits.

## 6. loop_check assertions

- **Idle suite** (`loop_check.gd:1352-1454`): connect `_observe` for the 420-frame walk; assert `_observed.is_empty()`, `buddy.health.damage == 0`, `max |v.y| < 200` while `travelling`, `global_rotation == 0` throughout.
- **Walled variant:** a `StaticBody2D` wall at `toy_x + 80` (between him and the toy); assert no `&"world"` hit, ≤ 3 upward launches (count `v.y < -150` edges), and `phase == wandering` after `STALL_SECONDS`.
- **Drop still pays:** place him 300 px above the floor; expect one hit with `source_id == &"world"`, `part == &"feet"`, `raw_impulse` ≈ 2300, amount ≈ 13. Guards the floor from silently turning drops off.
- **Friendly landing is free:** drop him 150 px onto a beanbag; `_observed` empty, Hearts rose.
- **Trampoline still pays:** drop onto a trampoline; a hit attributed `&"trampoline"`.
- **Parts:** `take_impulse(2000, &"baseball_bat", 1.0, pos + (0,-40))` yields `part == skull` and 1.5x the amount of the same call at `(0,+50)`; state goes `dazed` for the skull one.
- **Grounded sign check:** resting on the floor, `is_grounded()` true; mid-drop false — this pins the contact-normal convention once.
- **Resting suite** (`:1525`): tighten `<= 1` to `== 0`.
- `run_tests.gd:405-412`: knee tests as in §2.

## 7. Risks and what this does not solve

- **`lock_rotation` always-on removes the ragdoll tumble and the dangle.** The pin joint at `grip_offset` origin (`base_draggable.gd:131-139`) will translate him upright; the `dragged` tag's "dangling" reads from art alone. Drag feel is a by-hand check (`docs/test-matrix.md`), not a test. If the tumble is missed, the fallback is locking only in the brain's phases plus a righting torque — but a body on its side makes every landing a skull hit, which is why I recommend always-on.
- **Narrower torso (56 vs 88):** a horizontal bat at mid-height travels 16 px further before contact. Negligible, but visible in slow motion.
- **`buddy.tscn` in the editor** for the first time: the face/art/components authoring happens at the same time; the `_ensure_components` fallback must survive.
- **Trampoline first landing drops 9.6 → 6.1**; escalating bounces (1.55x gain) still pay and still knock him out on the `KNOCKOUT_COOLDOWN` schedule.
- **Not solved:** the stride itself (art); `BaseDraggable.get_interaction_rect()` for authored multi-shape items; a real non-ballistic "step" (the hop stays ballistic, it is just free under 57 px); shelves he cannot climb (stall → wander, as designed); pushing a 14-mass hot tub (he climbs instead); Dollars on player-caused world hits (left as designed).
- No save schema change.

## 8. Effort

- Scene authoring in the editor (shapes, offset, exports, components): 1.5 h
- `buddy.gd` parts / floors / grounded / react, `hit_info`, `balance_data`, `economy_math` + unit tests: 3 h
- `idle_brain.gd` walk/climb/grounded rewrite: 2 h
- `buddy_art.gd` walk hook and `dazed` mapping (code only): 1 h
- loop_check suites above: 2 h
- Suite runs, pacing_sim, by-hand drag/throw feel on two monitors: 2 h
- **≈ 11.5 h code.** Walk tag art (generate, postprocess, hand-finish): 3-4 h separately.

Files: `C:\Users\George\Godot Projects\Projects\bonehead-friend\Scripts\Buddy\buddy.gd`, `...\Scripts\Buddy\idle_brain.gd`, `...\Scripts\Buddy\buddy_art.gd`, `...\Scenes\Buddy\buddy.tscn`, `...\Scripts\Combat\hit_info.gd`, `...\Scripts\Data\balance_data.gd`, `...\Scripts\Economy\economy_math.gd`, `...\Scripts\Bodies\base_draggable.gd`, `...\tests\integration\loop_check.gd`, `...\tests\run_tests.gd`, `...\art\src\bonehead_neutral_96.png`.

---

## Proposal C — hitbox-first

# Proposal — minimal-change fix for the walk and the damage calibration

Verified against the working tree (idle_brain.gd carries an uncommitted diff at :459-480 — `handheld`, scrub-before-soak — that the other session should land first; nothing below touches those lines).

## 1. Diagnosis acted on

Four defects, one of which none of the three readers fully weighted:

**(a) His interaction rect is half his body.** `Scripts/Bodies/base_draggable.gd:50-59` scales `shape.get_rect()` by the *body's* `global_scale` and ignores the `CollisionShape2D` node's own `scale (2,2)` / `position (0,2)` (`Scenes/Buddy/buddy.tscn:80-83`). Every item bakes size into the shape, so only the buddy is wrong: **44x60 instead of 88x120**. Consequences, all in `idle_brain.gd`: `_foot_offset()` (:410-411) pushes 32 px *above* his real feet; `_climb()` (:382) measures rise from 32 px above his feet; `_touching_target()` (:656-657) needs the toy within 22 px of his centre while his real half-width is 44, so a beanbag resting against his side is 2 px outside "reached" and standing on top of it is not reached either. He arrives only by shoving into the toy or hopping onto it, and the light beanbag (mass 1.2, friction 1,176 N against his ≤10,500 N push) scoots, so distance never closes and the stall path fires.

**(b) The hop loop.** `_climb()` fires every 0.55 s from three places (:330-331 after one 2 s think without 16 px progress; :336-338 in PLAYING with *no* gate at all; :339-342 trampoline). Its own comment (:137) says a stall should be "four or five tries", but 8 s / 0.55 s is fourteen. Every hop lands at ≥ sqrt(2·980·28) = 234 px/s → 703 impulse → 7 damage, hurt face, mood −2.1, a Bone and a Dollar, and `_on_damage_dealt` (:534) exempts `&"world"` and the current toy so nothing ever stands him down. This is the "jumps toward things over and over and takes damage" verbatim.

**(c) The damage floor is a 7-px fall.** `min_damage_impulse = 350` (`balance_data.gd:15`) on a 3-mass body is 116.7 px/s. Nothing he can do on his own feet is under it, so no amount of brain tuning makes self-motion free: a step off a 30-px beanbag is 727. The floor is the right number for weapons (a bat at 160 px/s) and the wrong number for the floor and his own furniture.

**(d) Rotation is free.** No `lock_rotation`, no material (`buddy.tscn:58-83`; grep shows only `npc_base.gd:250` locks). With push moved to the real feet — 50 px below the CoM at (0,10) — the start-up torque `50·10,500` exceeds the corner-restoring `mg·44 = 129,360` and he tips backward on every start, so (a) cannot be fixed without also fixing (d).

Not acted on: the multi-hitbox. Self-landings and wall-walks arrive on the same shape a bat hit does; what discriminates them is the *source*, which the pipeline already carries (`buddy.gd:212-224`).

## 2. Exact changes

### `Scripts/Data/balance_data.gd` — one export, after line 15
```gdscript
## Contacts with the world and with kind-side items need a real fall before they hurt. 1500 on
## his 3-mass body is 500 px/s — a drop of about his own height (128 px). Everything he can do
## to himself lands under it; a throw, a drop from above his head, or a bat carrying him into
## the wall lands over it. Weapons keep `min_damage_impulse`.
@export var min_fall_impulse: float = 1500.0
```
`Data/balance.tres` needs no edit (it overrides only `mastery_xp_per_damage`).

### `Scripts/Buddy/buddy.gd` — `_integrate_forces` (:164-178), one new helper
Keep the order threshold → cooldown → attribute (so `register_use()` at :217 stays behind the cooldown); insert a side-effect-free classifier between the 350 check and the cooldown:
```gdscript
if impulse < b.min_damage_impulse:      # unchanged: cheapest reject, resting contact is 49
    continue
var src := state_.get_contact_collider_object(i)
if impulse < _min_impulse_for(src, b):  # new
    continue
if not _cooldown_ready(src, b.damage_cooldown):
    continue
...
## The world and kind-side items need a fall; harm-side items need a swing. Asked of the
## data (ItemData.is_kind), so the trampoline, a critter and a new comfort item are all
## classified by the seed tool that wrote them and never by an edit here.
func _min_impulse_for(src: Object, b: BalanceData) -> float:
    var body := src as BaseDraggable
    if body == null:
        return b.min_fall_impulse            # scriptless StaticBody2D: the walls, the test floor
    var item := ItemDB.get_item(body.item_id)
    if item != null and item.is_kind():
        return b.min_fall_impulse
    return b.min_damage_impulse              # WeaponBase, ThrowableBase, NpcBase, unknown ids
```
`take_impulse` (:182-187) is untouched: blasts, pellets, beam and NPC blows keep 350. `EconomyMath.damage_from_impulse` is untouched, so `tests/run_tests.gd:400-412` stay green. Unknown/empty ids fall to the harm floor deliberately — conservative.

### `Scripts/Bodies/base_draggable.gd` — `get_interaction_rect()` (:50-59)
Use the collider node's transform, not the body's:
```gdscript
var xf := collider.global_transform
extent = (r.size * 0.5 * xf.get_scale()).abs()      # was: * global_scale
...
return Rect2(xf.origin - extent, extent * 2.0)      # was: global_position - extent
```
(same for the circle branch). Every item's collider sits at identity, so only the buddy changes: 88x120 centred 2 px below his origin. Other callers — `open_hand_power.gd:84`, `beam_power.gd:90` — get his real body, which is a fix (a pet on his skull currently misses).

### `Scripts/Buddy/idle_brain.gd`
1. **Central push, bounded.** `_walk()` (:349-363): replace `apply_force(..., _foot_offset())` with `apply_central_force(Vector2(clampf(gap * mass * WALK_GAIN, -limit, limit), 0))` where `limit = WALK_PUSH_G * mass * _gravity`, `WALK_PUSH_G := 2.5`. Delete `_foot_offset()` (:407-411) and its comment. Rewrite the :346-348 comment: the push is central because rotation is locked (below); the offset trick was compensating for a torque that no longer exists.
2. **Lock rotation while he is driven.** In `_enter()` (:593-601): `_buddy.lock_rotation = phase != PHASE_WATCHING`. In `_exit_tree()` (:238-239): unlock if `is_instance_valid(_buddy)`. Drag → `buddy_state_changed(&"dragged")` → `_disturb` → `_stand_down` → `_enter(WATCHING)` runs synchronously in `_start_drag`, so the joint never swings a locked body; knockout goes through the same path before `freeze`. Nothing writes `rotation`, so the file's header rule (:17-20) holds.
3. **Climbs are the exception.** `CLIMB_INTERVAL` 0.55 → 1.5 (matches its own comment; a full 8 s stall is now 5 tries; and the longest flight, 2·640/980 = 1.31 s, is shorter than the interval, so the velocity-based grounded test at :379 can no longer fire at an apex — hypothesis 4 retires without contact tracking). New `CLIMB_PATIENCE := 1.5` and `var _lost_seconds`. PLAYING branch (:336-338): accumulate `_lost_seconds += delta` while `not reached`, zero it when reached, and call `_climb()` only when `_lost_seconds >= CLIMB_PATIENCE`. In `_climb()` early-return when `feet - top <= 0.0` (a hop cannot help when the toy is not above his feet). TRAVELLING's stall gate (:330) stays.
4. **Arrive, then lean in.** New `CONTACT_SLACK := 4.0`, `_in_contact()` = `_rect_of(_target).grow(CONTACT_SLACK).intersects(_buddy.get_interaction_rect())`, and `LEAN_G := 1.05`. PLAYING becomes:
```gdscript
if not reached:                      # full walk, patience-gated climb (item 3)
elif _routine == ROUTINE_BOUNCE:     _climb()          # as today
elif _routine == ROUTINE_PLAY:       _jig()            # as today
elif not _in_contact():              _lean(direction)  # SOAK / SCRUB / NIBBLE
```
`_lean` is `apply_central_force(Vector2(direction * mass * _gravity * LEAN_G, 0))` plus `art.travel(direction, 0.35)`. With the corrected rect, `reached` now fires 20 px *before* contact (he coasts 3.6 px on friction from 84 px/s), so the beanbag is never shoved by the full walk. The lean has to cross his own friction (1.0·mg = 2,940) and must not cross his friction plus the lightest toy he will walk to — rubber duck 0.3 → 3,234 (`Scenes/Friendly/rubber_duck.tscn:16`; the 0.2 duster is `handheld`, the 0.25 tennis ball has `min_contact_speed`). 1.05 → 3,087 N: he creeps 20 px in under a second and stops against anything, including a hot tub (13,720 N) and a toy pinned on a wall. `FriendlyBase._touching_buddy()` (`friendly_base.gd:154-157`) then sees a real collision and pays.

Nothing else moves: `WALK_GAIN`, `_walk_speed()`, `ARRIVE_SLACK`, `STALL_SECONDS`, the trampoline and jig routines, the exemptions at :534.

## 3. Balance numbers

| Event (mass 3, g 980) | Impulse | Floor applied | Pays? |
|---|---|---|---|
| Resting, per tick | 49 | any | no |
| Walking into a wall at cruise 84 px/s (+ that tick's push) | ~300 | 1500 (world) | no |
| Minimum hop landing (28 px clearance) | 703 | 1500 (world / kind) | no |
| Successful climb onto any toy — always a 28-px fall onto its top, by energy conservation | 703 | 1500 | no |
| Missed beanbag hop (58 px) | 1,011 | 1500 | no |
| Tip-over from standing | ~820 | 1500 | no |
| Missed hot-tub climb (168 px with the correct rect) | 1,722 | 1500 | yes, 17 — the one residual, rare once climbs are gated |
| Trampoline bounce 1 / 2 / 3 (320 → 496 → 769 px/s) | 960 / 1,488 / 2,307 | 1500 (toy = kind) | no / no / yes |
| Player drop from 100 / 128 / 200 px | 1,330 / 1,500 / 1,878 | 1500 | no / yes / yes (19) |
| Bat lay-on at 160 px/s (reduced mass 2.18) | 350 | 350 | yes, as today |
| Bat swing 1,500 px/s, mace, grenade, pellets | 3,270+ | 350 / take_impulse | unchanged |

- **`min_fall_impulse = 1500`**: the smallest number that clears every self-inflicted landing in the roster with margin (climbs onto a toy are all 703; the ceiling is set by the beanbag miss at 1,011 and a tip-over at 820), and it has a one-sentence rule the player can feel — *drop him from higher than he is tall and it hurts*. 1200 (the other number on the table) leaves the missed hot-tub climb and puts a 100-px drop within 10%. 2000 would make most casual drops free.
- **Cooldown stays 0.15 s**, no separate world cooldown: farming the fall floor requires a 128-px drop every 0.15 s, which nobody's furniture can produce. The per-instance-id key (`buddy.gd:233-241`) already isolates the floor from weapons.
- **No self-propelled flag.** Everything he can do to himself lands on the world or a kind item, so the source split *is* the self-motion exemption, with no brain→buddy coupling and no state to get stuck. A player who throws him at the wall still pays (the wall is world, but the impulse is thousands). D31's Dollar-per-hit at `economy.gd:242` becomes correct as a side effect: world hits are now only ever player-caused.
- **`WALK_PUSH_G = 2.5`** bounds the reversal kick (today 21,000 N when `gap` flips sign at the toy's centre) at 7,350 N; net of friction that is 1,470 px/s², start-to-cruise in 0.06 s, so the comment's "starts him inside a fifth of a second" still holds.
- Run `pacing_sim` before committing — a `BalanceData` default changed, and if it models bounce income the first two bounces are now free.

## 4. How the walk cycle plugs in

`BuddyArt.travel(direction, effort)` (`buddy_art.gd:150-153`) is already the seam and no caller changes. When a `walk` tag exists, `_advance_travel()` (:158-174) gains a `_walking` bool: on `_travel > 0` and `has_animation(&"walk")` and `_state_of_body() == &"idle"` → `_play_body(&"walk")`, `body.speed_scale = lerp(0.6, 1.0, _travel)`, bob 0; on `_travel` decaying to 0 → `speed_scale = 1.0` and `_on_mood_changed(Economy.mood)` returns him to the mood idle. `_on_state_changed` for hurt/happy/knockout already outranks it. The face follows for free: `_offsets.get(String(body.animation))` (:127) reads a per-tag track and `art/tools/postprocess.py` writes one per tag, so a `walk` track appears when the tag does. Facing is already `flip_h` (:172-173). Two things this proposal buys the art: `lock_rotation` means a walk drawn upright is always upright, and with the push central and the hop rare there is no tumble or crouch to draw over. Stride matching at cruise 84 px/s: a 6-frame cycle at 8 fps is 63 px per cycle, 16 art px per step at 2x — feasible in a 96 cell. The effort clamp at :358 (`0.35..1.0`) already gives the lean a visible shuffle.

## 5. Per-frame cost

- Brain: `_physics_process` is off in WATCHING (`idle_brain.gd:233, 601`); idle cost is still the 0.5 Hz think timer. Active: `_lean`/`_walk` are one `apply_central_force`; `_in_contact` is one more `Rect2.intersects`. `lock_rotation` is written on phase change only.
- Buddy: `_min_impulse_for` runs only for contacts already ≥ 350, which is zero per tick at rest (49) and at most `MAX_CONTACTS = 8` dictionary lookups under a pile-up. A sleeping body does not call `_integrate_forces` at all.
- Nothing adds a node, an Area, a timer or a per-frame allocation. Idle stays at whatever it is today; the 3% budget is untouched.

## 6. `loop_check` assertions

In `_he_goes_and_plays_with_his_toys()` (`tests/integration/loop_check.gd:1352-1454`), connect `_observe` before the 420-frame walk and add:
- "walking to a toy costs him nothing": `_observed.is_empty()` and `buddy.health.damage == 0.0`.
- "he walks, he does not hop": track `min(linear_velocity.y)` over the walk, assert `> -150.0`.
- "he arrives on his feet": `absf(wrapf(buddy.rotation, -PI, PI)) < 0.1` and `buddy.lock_rotation` true while `phase_name() == &"travelling"`.
- "he is actually in it": the beanbag's `get_colliding_bodies()` contains him at the end (the Hearts assertion at :1436 already implies it; make it explicit so the lean is what is being tested).
- "and being picked up unlocks him": after the bat interrupt at :1445, `buddy.lock_rotation == false`.
- A second placement: beanbag against a `StaticBody2D` wall (layer 1) — assert phase reaches `playing` and no `&"world"` `HitInfo`.

In `_real_physics_produces_hits()` (:1456-1527):
- Keep the 338-px drop (2,442 ≥ 1500) — still green.
- Add "a drop from below his own height is free": place him at floor top − 62 − 60 (v 343 → 1,029) and assert `_observed.is_empty()`.
- Add "the mace still pays at the swing floor" is :1495; add a beanbag dropped from 100 px onto him (kind, ~700) → no hit, to pin the classifier.

`ui_check`: `open_hand` reach now covers his real 88x120 — verify its pet assertions still pass (they become more permissive, not less).

## 7. Risks and what it does not solve

- **Missed hot-tub climbs still pay 17** (1,722 > 1500). Rare after gating; if it shows in playtest, the fix is `MAX_CLIMB_SPEED` 640 → 500 (rise 128 px, still clears the tub's 140 with the walk momentum carrying him forward) rather than moving the floor.
- **Drops from under ~128 px are free** — a feel change the playtest has to judge. The bat, mace and every blast are numerically identical to today.
- **Trampoline income drops** (first two bounces free). The brain's own header (:92-100) calls the bounce a Bones engine that needs bounding, so this is in the intended direction, but confirm with `pacing_sim`.
- **A skeleton starting on his side walks on his side**: `lock_rotation` freezes whatever he has. Pre-existing — nothing rights him today except an out-of-bounds rescue — but now visible for the length of a trip. Cheap follow-up: in `_consider_starting`, do not start unless `|rotation| < 20°`.
- **The 8-px art registration** (body reader §1: the 96-cell feet draw 8 px below the collider) is untouched; the lean and `_touching_target` measure the collider, not the sprite.
- **The bounce routine still hops beside the mat** rather than over it — `_touching_target` is a side test. Follow-up: for `ROUTINE_BOUNCE` require his x inside the mat's x-range before climbing.
- **No stride** (assessment item C1) — this only makes the walk something a stride can be drawn onto.
- **No head/feet distinction.** `_min_impulse_for` is the seam a later per-shape floor plugs into (`state_.get_contact_local_shape(i)` → part; `HitInfo` gains `part`); nothing here has to be undone for it.
- `idle_brain.gd` and `friendly_base.gd` are being edited concurrently; sequence this after that commit.

## 8. Effort

- balance_data + buddy classifier + base_draggable rect: 1 h.
- idle_brain (central push, lock, climb gating, lean): 2 h.
- loop_check additions and the wall variant, plus reruns of loop_check / ui_check / pacing_sim / boot smoke: 2-3 h.
- One sandbox session on both monitors to watch him go to a beanbag, a hot tub and a trampoline: 1 h.
- **Total 6-7 h**, one commit; the walk-tag hook in `BuddyArt` is 1 h more when the art exists.

Files: `C:\Users\George\Godot Projects\Projects\bonehead-friend\Scripts\Buddy\idle_brain.gd`, `...\Scripts\Buddy\buddy.gd`, `...\Scripts\Bodies\base_draggable.gd`, `...\Scripts\Data\balance_data.gd`, `...\Scripts\Buddy\buddy_art.gd`, `...\Scenes\Buddy\buddy.tscn`, `...\tests\integration\loop_check.gd`, `...\Scripts\Economy\economy_math.gd`, `...\Scripts\Autoload\economy.gd`, `...\Scripts\Bodies\trampoline.gd`, `...\Scripts\Bodies\friendly_base.gd`, `...\Scenes\Friendly\beanbag.tscn`, `...\Scenes\Friendly\hot_tub.tscn`, `...\Scenes\Friendly\rubber_duck.tscn`, `...\Scripts\World\npc_base.gd`.

---

## Judge 1 — senior physics-gameplay programmer

{
  "scores": [
    {
      "key": "minimal",
      "correctness": 8,
      "fixes_the_report": 8,
      "cost_vs_value": 9,
      "risk": 8,
      "total": 33,
      "note": "Every cited line checks out (base_draggable.gd:55,59; idle_brain.gd:336-338,382,410-411,599,656-657; buddy.gd:170-178,224; trampoline is Toy=SIDE_KIND so the 1500 floor really does reach it, item_data.gd:55). Drop math for loop_check is right (338 px, ~2,440). The classifier sits between the 350 check and the cooldown so a discarded self-contact does not stamp a real hit's cooldown, and register_use() at buddy.gd:217 stays behind both gates. Per-phase lock_rotation is safe because the dragged\u2192_stand_down\u2192_enter(WATCHING) chain is synchronous. Weak points: LEAN_G 1.05 is a 5% margin over mu=1 static friction and is the only thing that closes the last ~16 px to real contact (FriendlyBase._touching_buddy needs a collision to pay); the central P-controller still cruises at ~84 px/s not the 117 the code derives, and _walk still pushes in the air; missed hot-tub climb still pays 17; player drops under 128 px go free, a feel change the report did not ask for. Cheapest by far (6-7 h, no scene edit, no schema, no new Buddy API, one commit) and every change is a number or a one-function seam."
    },
    {
      "key": "physics-first",
      "correctness": 6,
      "fixes_the_report": 9,
      "cost_vs_value": 6,
      "risk": 5,
      "total": 26,
      "note": "The design is the cleanest of the three (velocity-controlled legs owned by Buddy, step only when blocked, provenance gate so player-caused damage is numerically unchanged, reached = real collision) but two stated numbers are wrong. walk_accel 600 adds 10 px/s per tick while floor friction at mu=1 can absorb 16.3 px/s per tick, so from rest he nets zero every tick and never moves; the '~8 px/s under target' analysis is incorrect. The loop_check drop is 338 px not 276 (conclusion survives). Contact-normal sign is admitted unverified. Always-on lock_rotation removes the throw tumble for the harm side. The _launched flag is a state machine with stuck/unset failure modes across 11 take_impulse sites plus drag and trampoline. Rewrites the idle_brain header invariant (:17-20). 14-16 h with most of it budgeted for getting assertions green against unknowns, and a large buddy.gd diff while another session edits Scripts/."
    },
    {
      "key": "hitbox-first",
      "correctness": 7,
      "fixes_the_report": 8,
      "cost_vs_value": 6,
      "risk": 5,
      "total": 26,
      "note": "Three shapes on one RigidBody2D stays inside D4, get_contact_local_shape/shape_owner_get_shape_index are the right API, Trampoline extends BaseDraggable (trampoline.gd:2) so the FriendlyBase test correctly keeps the mat at 350, and the friction feed-forward plus grounded gate in _walk is the best locomotion fix of the three (he actually reaches 120 px/s). But it changes damage_from_impulse into a knee for every weapon (-6% bat/mace, flips run_tests.gd:406), nerfs player drops hard (100 px: 13 -> 3.3) which is not what 'calibrate wall damage' asked, adds a dazed state and skull x1.5 the report did not ask for, leaves BaseDraggable.get_interaction_rect broken (Buddy-only override), still pays 6.4 x3 on missed hot-tub climbs, and its friendly+feet=INF opens a thrown-beanbag hole. Biggest process risk: opens buddy.tscn in the editor for the first time (Puppet offset, three shapes, components) while another session is running suites and editing Scripts/. 11.5 h code plus scene authoring. It is the only one that actually plans the multi-hitbox the owner named, and its part seam is small."
    }
  ],
  "winner": "minimal",
  "graft": "Ship minimal, sequenced after the uncommitted idle_brain.gd:459-480 diff lands, with these grafts:\n\n1. From physics-first: make `_touching_target()` (idle_brain.gd:656-657) return the corrected rect overlap OR `_target in _buddy.get_colliding_bodies()` (contact_monitor is already on, buddy.gd:64). Reached then agrees with what FriendlyBase._touching_buddy (friendly_base.gd:154-157) pays on, and the 1.05 lean is no longer the only thing standing between 'arrived' and 'paid'. Keep the lean, but raise LEAN_G to ~1.15 (still under 1.0 + duck 0.3/3 = 1.10? no: 3,087 vs 3,234 N \u2014 keep 1.05-1.09) and assert contact in loop_check rather than trusting the margin.\n\n2. From hitbox-first: in `_walk()` (idle_brain.gd:349-363) use friction feed-forward plus a gentler P term \u2014 `apply_central_force(direction * mass * g + gap * mass * 12)` clamped by minimal's WALK_PUSH_G \u2014 so steady state is push = friction at gap 0 and he cruises at the full `_walk_speed()` (117) instead of ~84; `effort` then honestly reaches 1.0 for the art. Gate `_walk` on grounded: expose `Buddy.is_grounded()` from the contact loop already running in `_integrate_forces` (buddy.gd:168 \u2014 physics-first's normal.y < -0.7 scan, or hitbox-first's contact-point test, one bool cached per tick) and use it in `_climb()` too, replacing the `|v.y| < 50` test at :379 that re-fires at an apex. Add physics-first's 'grounded true resting / false 5 frames into a step' assertion to pin the normal sign once.\n\n3. From hitbox-first: `MAX_CLIMBS_PER_TRIP = 3` reset in `_enter()` on top of CLIMB_PATIENCE, and make `MAX_CLIMB_SPEED` 640 -> 500 the default rather than the fallback, so a missed hot-tub climb (the one residual, 1,722 > 1500) lands under the floor.\n\n4. From physics-first: keep a way back to today's player-drop feel without touching the brain. Add the `_launched` mark on `_end_drag()` (buddy.gd:147-151) and in Trampoline (trampoline.gd:49) only \u2014 not the 11 take_impulse sites \u2014 and let `_min_impulse_for` return `min_damage_impulse` while launched. That makes 'drop him from 50 px' pay exactly as today while every self-landing stays on the 1500 floor. If the playtest prefers minimal's 'drop from above his height' rule, delete the flag; it is ~15 lines.\n\n5. From hitbox-first: add `part: StringName = &\"torso\"` as a defaulted fifth HitInfo._init parameter now (all eight consumers compile unchanged) and pass `state_.get_contact_local_shape(i)` through `_min_impulse_for`'s signature, so the later multi-hitbox pass is additive on the seam minimal already names. Do not take the knee, the skull multiplier, the dazed state, or the buddy.tscn editor session in this change \u2014 those belong to the art pass, which CLAUDE.md already says opens buddy.tscn.\n\n6. Adopt minimal's own listed follow-up immediately: `_consider_starting` refuses to start unless |wrapf(rotation)| < 20 deg, so per-phase lock never freezes him on his side for a whole trip.\n\n7. Tests: minimal's six idle-suite assertions plus physics-first's 'upright every frame', 'beanbag in get_colliding_bodies() on >= 90% of playing frames', and 'trampoline still pays a hit'; hitbox-first's 'drop from 300 px still pays, source world' guard; and note in the commit that pacing_sim has no impulse model (grep is empty) so it cannot see this change \u2014 the trampoline income shift is checked by the trampoline assertion instead."
}

---

## Judge 2 — the owner

{
  "scores": [
    {
      "key": "minimal",
      "correctness": 8,
      "fixes_the_report": 8,
      "cost_vs_value": 9,
      "risk": 8,
      "total": 33,
      "note": "Every load-bearing number checks out against source (rect 44x60 vs 88x120, foot offset +30, 2-px touching miss, 703 hop landing, 350 = 7-px fall, working-tree diff at idle_brain.gd:459-480). Source-keyed floor (world/kind 1500 vs harm 350) placed between the 350 reject and the side-effecting _cooldown_ready is the right ordering and needs no brain->buddy coupling or sticky state. lock_rotation only while driven, unlocked synchronously via dragged->_disturb->_enter(WATCHING), preserves today's throw/dangle feel. Keeps air control, so its gated hop is the only one of the three that can still carry him onto a hot tub. One factual error: 'every item collider sits at identity' is false (baseball_bat.tscn:39 (0,-20), fire_axe.tscn:40, chainsaw.tscn:44-45 rotated) \u2014 the BaseDraggable rect fix recentres every authored weapon's rect on its first piece; nothing reads those today so the consequence is nil, but scope it to a Buddy override. Also CLIMB_CLEARANCE 28 was compensating for the 32-px feet error and is left at 28. pacing_sim is inert for this change (no impulse model in pacing_sim.gd)."
    },
    {
      "key": "physics-first",
      "correctness": 7,
      "fixes_the_report": 8,
      "cost_vs_value": 5,
      "risk": 5,
      "total": 25,
      "note": "Most principled diagnosis and the best test design (contact >=90% of frames, launched/unlaunched 100-px drop pair, grounded sign-pin). Provenance gate (launched | other >=250 px/s | >=1800) is airtight against everything he can do to himself and still bills every player act. But it rebuilds locomotion as velocity control inside _integrate_forces (an unstoppable mover against any light body, and a new contract for a body the drag joint, CCD and contact model all assume is force-driven), adds a _launched flag that can stick (degrades to today's behaviour, not worse), always-on lock removes the tumble/dangle, and hinges on the unverified contact-normal sign \u2014 if wrong, _grounded is never true and the walk does nothing on first run. No air control: a blocked step rises and lands in place. Arithmetic slip (loop_check drop is 338 px not 276; 2,442 not 2,200), conclusion unaffected. 14-16 h and seven new knobs for a report that is a rect bug, a gate and a floor."
    },
    {
      "key": "hitbox-first",
      "correctness": 5,
      "fixes_the_report": 7,
      "cost_vs_value": 5,
      "risk": 3,
      "total": 20,
      "note": "Answers the owner's multi-hitbox instinct concretely (three baked shapes, get_contact_local_shape -> part, HitInfo.part with default, skull x1.5, dazed state) and correctly scoped the rect fix to a Buddy override. But the economy_math knee is a regression it does not see: npc_base.gd:526-527 sizes the grapple shake at min_damage_impulse*1.05 = 367.5, which the knee turns into 0.175 damage \u2014 the exact 'visibly does something, silently pays nothing' failure npc_base.gd:512-514 warns about; the beam (650/tick, beam_power.gd:18,23,81) loses 54%; every weapon loses 3.5. The is_grounded gate on _walk removes air control so the hot-tub climb becomes a vertical hop in place (MAX_CLIMBS_PER_TRIP merely bounds the futility). Opens buddy.tscn in the editor and authors Face/Art/Mood/Grime in the same change while another session edits Scripts/ concurrently \u2014 CLAUDE.md assigns that to the art pass. Always-on lock removes the pin-joint dangle. The 96-cell registration claim cites buddy_art.gd:101-104, which loads bonehead.aseprite, not the PNG; unverified. 11.5 h plus scene authoring for a change whose economy side needs its own retune."
    }
  ],
  "winner": "minimal",
  "graft": "Ship minimal, with these grafts:\n\nFrom hitbox-first:\n1. Scope the rect fix to an override on Buddy (union of his real shape: 88x120 at (0,+2)) instead of changing BaseDraggable.get_interaction_rect(). Minimal's premise that item colliders sit at identity is false (baseball_bat.tscn:39, fire_axe.tscn:40, chainsaw.tscn:44-45, seed_bodies.gd:44-75); nothing reads a weapon's rect today, but do not change it silently.\n2. CLIMB_CLEARANCE 28 -> 12 once feet are measured correctly. 28 was compensating for the 32-px feet error; every self-landing drops from 703 to ~460, which widens the margin under the 1500 floor and makes the residual missed hot-tub climb 1,638 instead of 1,722.\n3. MAX_CLIMBS_PER_TRIP = 3, reset in _enter(), alongside minimal's CLIMB_PATIENCE \u2014 a bounded count is a stronger guarantee than a timer against a toy pinned somewhere he can never reach.\n4. Add `part: StringName = &\"torso\"` as a fifth defaulted _init parameter on HitInfo now (all eight consumers compile unchanged). It costs nothing and gives the later per-shape floor its seam, as minimal's \u00a77 promises but does not create.\n5. Keep min_damage_impulse as a cliff, not a knee \u2014 the grapple shake at npc_base.gd:526-527 and the beam per-tick impulse are both sized against the cliff.\n\nFrom physics-first:\n6. _touching_target() = rect overlap OR `_target in _buddy.get_colliding_bodies()`. friendly_base.gd:154-157 pays on real contact, so 'reached' and 'paid' should be the same question; this also lets the lean stop the instant contact happens rather than on a 4-px slack.\n7. Replace the `|v.y| < GROUNDED_SPEED` test in _climb() with a grounded flag computed from contact normals in the existing _integrate_forces loop (one get_contact_local_normal per contact, <= 8) \u2014 minimal's 'interval longer than flight' argument holds only while MAX_CLIMB_SPEED stays 640. Pin the normal sign with physics-first's loop_check assertion (grounded true at rest, false 5 frames into a step) \u2014 this is the one unknown nobody can resolve without a run.\n8. Call `art.stop_travelling()` and drop any pending push from _stand_down()/_finish() and the freeze-or-dragging early-out, so a stand-down ends the stride the same frame.\n9. Take physics-first's loop_check assertions over minimal's: beanbag in get_colliding_bodies() on >= 90% of post-arrival frames and |v.y| < 100 on >= 95% (a hop loop fails both, a bob passes both), plus the walled variant asserting phase reaches wandering via the stall path with zero &\"world\" hits.\n10. Put the floor classifier in EconomyMath as a pure function taking (impulse, is_world, is_kind, min_impulse, fall_impulse) so run_tests.gd can table-test it under -s; Buddy._min_impulse_for becomes the adapter.\n11. If the owner misses the tumble after a bat hit under minimal's phase-scoped lock, physics-first's fallback (unlock only while launched) is the next step; do not go to always-on.\n\nAlso: drop the 'run pacing_sim' line from the plan's verification \u2014 pacing_sim.gd has no impulse model and cannot observe any of this; the checks that can are loop_check, ui_check (open-hand reach becomes a superset) and a sandbox session on both monitors watching a beanbag, a hot tub and a trampoline. Sequence after the uncommitted idle_brain/friendly_base/loop_check diff lands."
}

---

## Judge 3 — QA lead

{
  "scores": [
    {
      "key": "minimal",
      "correctness": 8,
      "fixes_the_report": 8,
      "cost_vs_value": 9,
      "risk": 8,
      "total": 33,
      "note": "Every load-bearing claim checks out against the working tree: base_draggable.gd:55,59 scale by the body's global_scale/global_position while buddy.tscn:81-83 puts scale (2,2)/pos (0,2) on the collider node, so the rect is 44x60 against a real 88x120; idle_brain.gd:336-338 climbs in PLAYING with no gate, :599 zeroes _climb_timer on every _enter, :138 CLIMB_INTERVAL 0.55 contradicts its own comment at :137, :534 exempts &\"world\" and the current toy; buddy.gd:170-175 is threshold->cooldown->attribute with register_use() at :217, so inserting the classifier before _cooldown_ready is the right slot; lock_rotation exists only at npc_base.gd:250. The unlock path (Buddy._start_drag -> _set_state(&\"dragged\") -> EventBus -> IdleBrain._on_buddy_state_changed -> _disturb -> _stand_down -> _enter(WATCHING)) is synchronous, so the pin joint never swings a locked body. It is the ONLY proposal that noticed the trap the rect fix springs: with an 88-wide rect, _touching_target (idle_brain.gd:657, ARRIVE_SLACK 20) fires at |dx|<86 while real contact with a 44-wide beanbag (beanbag.tscn:8) is at |dx|=66, and FriendlyBase pays only off get_colliding_bodies() (friendly_base.gd:154-157) - the lean (1.05 mg = 3087 N, net 147 N over his own 2940 N friction, under the 294 N friction of the lightest lean target at 0.3 mass: rubber_duck/ice_cream) is what keeps the existing 'being in it pays Hearts' assertion at loop_check.gd:1436 green. Arithmetic re-checked: 703 min-hop landing, 84 px/s cruise, 1.31 s max flight < 1.5 s interval, 2442 for the suite's 338 px drop (still >= 1500). Two dings: Data/Items/trampoline.tres is category 4 = CATEGORY_TOY, which item_data.gd:55 maps to SIDE_KIND, so the classifier as written silences bounces 1-2 (960, 1488 < 1500) and cuts the Bones engine idle_brain.gd:92-100 depends on - acknowledged but only deferred to pacing_sim; and balance.tres overrides mood_curve as well as mastery_xp_per_damage (harmless). Sequenced correctly after the uncommitted idle_brain.gd:462-475 diff, which is what is on disk."
    },
    {
      "key": "physics-first",
      "correctness": 6,
      "fixes_the_report": 7,
      "cost_vs_value": 5,
      "risk": 5,
      "total": 23,
      "note": "Diagnosis is the same verified set and the cruise-speed correction (84 px/s, not 117) is right. Velocity control plus 'step only when blocked by a static/heavy contact' is the most robust locomotion of the three, and the sleeping-body wake (sleeping=false on set_walk) is a real catch. But three things would show up on the first loop_check run: (1) walk intent persists after 'reached' - nothing calls stop_walk() in the PLAYING branch, and a 1.2-mass beanbag is below the 2x-mass blocked threshold, so he shoves it at 117 px/s under velocity control; in loop_check.tscn the floor spans x -480..1120 and the beanbag sits at -60, so in the 420-frame window he pushes it off the edge. Stopping intent on reached instead leaves him 13-20 px short of contact (friction stops him in ~7 px) and the beanbag never pays - either way the Hearts assertion and the proposal's own 'colliding >= 90%' assertion fail. (2) _launched clears only after 0.3 s under 60 px/s, but he walks at 117, so one autonomous take_impulse (turret, goose - the exact case idle_brain.gd:529-533 exists for) arms every wall bump (m*v = 350, equality pays at buddy.gd:170) and every 12 px step (460) for the rest of the trip. (3) The suite's drop is 338 px (floor top 500, buddy y=100, feet +62), not 276; 2442 still clears 1800 so the conclusion survives. Contact-normal sign is honestly flagged as unverified. Always-on lock_rotation removes the drag dangle and the bat tumble, which the report did not ask for. 14-16 h and a new stateful flag on the buddy for a report that is about the brain."
    },
    {
      "key": "hitbox-first",
      "correctness": 5,
      "fixes_the_report": 7,
      "cost_vs_value": 4,
      "risk": 4,
      "total": 20,
      "note": "The three-shape design is coherent and the source-kind classifier ordering (classify without side effects -> floor -> cooldown -> attribute) is the right observation about register_use() at buddy.gd:217. But it inherits the arrival gap unfixed: it says _touching_target is 'unchanged in code and now correct in effect', yet with the 88x126 override it fires 20 px before contact, the force walk is cut, friction stops him in 4-7 px, and FriendlyBase never sees him in get_colliding_bodies() - loop_check.gd:1436 goes red. Second, _walk is gated on is_grounded(), whose stamp is written only in _integrate_forces, which does not run for a sleeping body; the proposal itself says 'asleep on the floor it is never called and _grounded is stale' - so a buddy who has settled (the suite idles him 130 frames before the walk) never receives the first push and never wakes. Fixable, but unseen. Third, the knee in damage_from_impulse flips tests/run_tests.gd:406 and shaves ~6% off every weapon, dragging the harm ladder into a change that was about self-damage. Fourth, it opens Scenes/Buddy/buddy.tscn in the editor and moves Puppet by -9 px on a registration figure measured against art/src/bonehead_neutral_96.png, while BuddyArt actually loads art/src/bonehead.aseprite (buddy_art.gd:18) - plausible, unverified, and an editor session cannot run while another session is editing Scripts/. Trampoline-keeps-350 via the class check is correct (trampoline.gd:2 is a bare BaseDraggable). The hitboxes themselves are juice the owner said we 'may need to plan', not the bug he reported."
    }
  ],
  "winner": "minimal",
  "graft": "1) From hitbox-first, one line into minimal's _min_impulse_for: `if body is Trampoline: return b.min_damage_impulse` ahead of the is_kind() read. Data/Items/trampoline.tres is category 4 (TOY -> SIDE_KIND at item_data.gd:55), so without it bounces 1-2 (960, 1488) go free and the Bones engine idle_brain.gd:92-100 and KNOCKOUT_COOLDOWN are tuned around is cut; with it pacing_sim has nothing to notice and the brain's 'the mat pays' header stays true. 2) From physics-first, `_touching_target()` becomes rect-overlap OR `_target in _buddy.get_colliding_bodies()` so 'reached' and 'paid' can never disagree (contact_monitor is already on, buddy.gd:64). 3) From physics-first, a cheap 'blocked' gate on top of minimal's CLIMB_PATIENCE: only call _climb() when `absf(_buddy.linear_velocity.x) < MOTION_FLOOR` while a push is in force - he is pressed against something - so a slow walker is never hopped at; no contact-normal scan needed. 4) From hitbox-first's assertion list: pin the drop in the contact suite with `source_id == &\\\"world\\\"` and `raw_impulse` around 2442 (338 px: floor top 500, buddy y 100, feet +62) so the new floor can never silently switch drops off, and tighten the resting assertion at loop_check.gd:1557 from `<= 1` to `== 0` - resting contact (49) is 30x under the world floor. 5) From physics-first, the two-sided pin: a 100 px drop (1330) asserts `_observed.is_empty()` and the same drop after a bat hit still pays via the 350 path - keep it as 'a bat still pays at the swing floor' against a WeaponBase collider, not a launched flag. 6) Keep minimal's phase-scoped lock_rotation, but take hitbox-first's point about walking on his side: in _consider_starting refuse to start unless |wrapf(rotation)| < 20 deg, and add the 'he arrives on his feet' assertion to the idle suite as minimal proposes. 7) From hitbox-first, name the seam now: `_min_impulse_for(src, b)` is where `state_.get_contact_local_shape(i)` -> part plugs in later; add the fifth defaulted HitInfo parameter only when the parts exist."
}
