# Worklist — September 2026

The working list for M3.8, the assessment's top ten (`assessment-2026-09.md`). One task per
row, in the order to do them. Written 2026-09-06 after a session hit its usage cap twice;
**everything here can be done from a fresh thread with this file and the two plan documents.**
Do tasks one at a time, on the cheapest model that can do them, and update the status column
as you go — this file is the handoff.

Status: ✅ done and verified · 🟡 started · ⬜ not started · 🚫 blocked (says on what)

## How to verify anything

```bash
G="/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
P='C:\Users\George\Godot Projects\Projects\Bonehead_Friend\interactive-buddy-2'
"$G" --headless --editor --quit --path "$P"                       # after any new class_name or asset
"$G" --headless --path "$P" -s tests/run_tests.gd                  # unit
"$G" --headless --path "$P" res://tests/integration/loop_check.tscn
"$G" --headless --path "$P" res://tests/integration/ui_check.tscn
"$G" --headless --path "$P" res://tests/integration/pacing_sim.tscn   # ~8 minutes now
```

**Baseline at the time of writing: unit 206 · loop 388 · ui 204 · pacing 4/4 (first
Reincarnation 9:16). All green. Nothing committed since `21adb6c` (2026-08-30).**

---

## 0. Commit what is green

✅ Committed 2026-09-06 as six units, `6d03864` → `c3f96e0` (docs · lambda/fades/drawers · kind side · sounds · HUD/onboarding · expressive Phase 0), suites at the baseline above. The plan that was followed:

The tree held about 90 changed or new files, all verified. Commit them in these units, in
this order, each with a message in the repo's style (what, why, what it turned up, the suite
counts). Run the suites once before the first commit; they do not need re-running per unit.

| # | Unit | Files |
|---|---|---|
| 0.1 | The assessment and the docs | `docs/assessment-2026-09.md`, `docs/README.md`, `docs/roadmap.md` (status table), `docs/worklist-2026-09.md`, `docs/research/movement-workflow-notes.md`, `docs/plan-expressive-buddy.md`, `CLAUDE.md` (current-state paragraph) |
| 0.2 | The explosion lambda, the white flash, the two fades, the drawers | `Scripts/Components/effects_player.gd`, `Scripts/UI/panel_layer.gd` (purse bind only — see 0.5), `Scripts/UI/ui_motion.gd`, `Scripts/UI/hud.gd` (toast only — see 0.5), `Scripts/UI/hover_drawer.gd` |
| 0.3 | Kind-side rates and the six hands-on items | `tools/seed_friendly.gd`, `tools/seed_m35_trees.gd`, `tools/seed_m35_engine.gd`, `Scenes/Friendly/*.tscn` (14 modified + 5 new), `Scenes/Powers/soft_brush_power.tscn`, `Data/Items/*` (6 new), `Data/Augments/*` (22 new), `Scripts/Bodies/friendly_base.gd` (`handheld`, `entry_sound`), `Scripts/Bodies/Powers/open_hand_power.gd` (`value_scale`), `Scripts/Buddy/idle_brain.gd` (handheld, scrub-before-soak), `art/tools/make_brush_icon.py`, `Assets/sprites/icons/soft_brush.png(+.import)`, `docs/economy.md`, `tests/integration/loop_check.gd` (the handheld assertions), `tests/integration/pacing_sim.gd` (SPREAD_COUNT) |
| 0.4 | Sounds | `Scripts/Autoload/audio_manager.gd`, `Scripts/Bodies/turret_base.gd`, `Scripts/Bodies/trampoline.gd`, `Scripts/World/npc_base.gd`, `Scripts/UI/Arcade/blackjack.gd` |
| 0.5 | HUD next-up and rate rows, onboarding | `Scripts/UI/hud.gd`, `Scripts/UI/panel_layer.gd` (`ui_show_item`, `pin_drawer`), `Scripts/Autoload/event_bus.gd`, `Scripts/main.gd`, `tests/integration/ui_check.gd` (next-up suite + the arcade mapping fix) |
| 0.6 | Expressive buddy Phase 0 | `Scripts/Buddy/buddy_art.gd`, `Scripts/Buddy/buddy.gd`, `Scripts/Components/grime_component.gd`, `Scripts/Components/effects_player.gd` (the grime uniform — if 0.2 was committed first, this is the second change to that file) |

If splitting a file between two units is more trouble than it is worth, fold 0.2 into 0.5.

---

## 1. The ten, as the owner decided them (2026-09-02)

| # | Task | Status | Where it stands |
|---|---|---|---|
| 1 | Fix the freed-lambda explosion error | ✅ | `effects_player.gd`: bound `queue_free`, sprite found by type. Loop suite no longer prints the error. |
| 2 | Perf: drawers, NPCs | ✅ / 🟡 | Drawers sleep between events (`hover_drawer.gd _wake()`). NPC steering left alone by owner choice ("working NPCs over perf"). The other perf items from the assessment are in §3 below. |
| 3 | Kind-side rate fixes | ✅ | Sponge touching 0.4, duck cooldown 2.0, pizza 45, boombox 1.5, comfort 14/22/45, ambience x2.5. Seed tool and scenes both updated; `economy.md` sponge paragraph rewritten. |
| 4 | Six hands-on kind items | ✅ (art 🚫) | feather_duster 90, tennis_ball 300, soft_brush 500 (cursor power, plotted icon), party_popper 800, warm_towel 1500, kite 4500. Scenes, items, trees, capstones seeded. Five ship on placeholder silhouettes: needs the Retro Diffusion MCP (§4). |
| 5 | HUD next-up + Bones/s · Hearts/s | ✅ | `hud.gd`: 10 s rolling rate row (self-stopping timer); "Next" row coalesced at 0.4 s, click → `EventBus.ui_show_item` → shop opens on the item. Six ui_check assertions. |
| 6 | Basic onboarding | ✅ | `main.gd _onboard()`: hints `welcome` / `first_bones`; pins both drawers, spawns the bat beside him, two toasts. Not yet seen by a human. |
| 7 | Sounds | ✅ | New voices upgrade/milestone/welcome/spawn; augment buys climb in pitch; orphaned voices wired (turret_fire, npc_roar by mass, card_deal, bounce, splash/impact_soft via `entry_sound`, explode_big by hint). `play()` gained a `pitch` argument. |
| 8 | Walk is broken; wall damage too easy; multi-hitbox plan | ✅ walk · ⬜ hitboxes | `docs/plan-movement-hitboxes.md` implemented: fall floor by source (1500), rect override, grounded from normals, impulses summed per collider, bounded central walk, rotation locked while driven, gated climbs, lean. Idle suite proves the walk (0 hits, 0 hops, upright, in contact). Hitboxes designed (plan §5), deferred to the art pass. Not yet watched by a human: **sandbox session on both monitors** (beanbag, hot tub, trampoline, a wall). |
| 9 | Fades, flash, fist icon | ✅ / 🚫 | Fades and white shader flash done. Fist icon needs the generator (§4). |
| 10 | Highly reactive, expressive buddy | ✅ Phase 1 · ⬜ Phases 2–3 | `docs/plan-expressive-buddy.md` Phases 0–1 built and green: `ExpressionBrain` (one arbitrated beat slot, D36), the `BuddyArt` accumulator, all eight reaction tables wired, four voices, F3 row, 80+ loop and 20 ui assertions. Phase 2 (personality on the surface, plan §5) and Phase 3 (art, needs the generator) remain. |

---

## 2. Next up, in order

### 2.1 Expressive buddy — Phase 1 (the mind, no new art) ✅ (2026-09-06, five commits `1931c33` → see log)

Plan: `docs/plan-expressive-buddy.md` §3.7 steps 8–15, tables in §2, tests in §6. About 14 h in
the plan's own estimate. Do it as five sequential pieces, suites after each:

1. ✅ **Step 8** — new `Scripts/Buddy/expression_brain.gd` (`class_name ExpressionBrain`): one
   arbitrated beat slot with priority and msec deadlines, 0.18 s re-trigger damping, arousal
   that decays, attention (cursor | toy | threat | none), `_away_since`, one re-armed `Timer`,
   no `_process`. `_amp()` / `_initiates()` / `_may_gaze()` off `Settings.intensity_scale()`.
   Built in `Buddy._ensure_components()` as an `@export` slot. **Beats never call
   `_set_state`.** Run the editor pass before any suite (new `class_name`).
2. ✅ **Step 9** — `buddy_art.gd`: `play_beat`, `hold_face`, `clear_beat`, `look`, `set_squash`,
   `beat_active`; the accumulator (recoil_x, hop_y, nod_y, look_x, squash with
   `_foot_fix = (1.0 - _squash_y) * 31.5 * _base_scale.y`) folded into the two existing
   body/face writes; connect `body.animation_finished`; the `set_process(false)` contract holds.
3. ✅ **Steps 10–11** — tables A, B, E (hits with the whole `HitInfo`, kindness with `source_id`,
   `kindness_sustained`, the six progression signals, `Economy.kindness_combo()`), then C, F
   (`DraggableArea.hover_changed`, app focus in/out, the reunion beat, the drag ladder).
4. ✅ **Steps 12–13** — `EventBus.threat_changed(kind, world_pos, level)` from throwables (prime
   and explode), NPC windup, turret fire; `IdleBrain.phase_changed` + `seconds_since_disturbance()`;
   table G; then table H (blink, fidget on the timer, mood-trough posture).
5. ✅ **Steps 14–15** — D36 into `docs/decisions.md`; the "expression" suite in `loop_check.gd`
   (every connect exists, a beat never changes state, Focus Off → zero amplitude and nothing
   initiated, face never detaches, art stops processing after a beat, `hover_changed` and
   `threat_changed` fire); four voices `oof`, `greet`, `yawn`, `gasp` in `audio_manager.gd`.

Then Phase 2 (personality on the surface, plan §5) and Phase 3 (art, plan §4) — Phase 3 needs
the generator.

### 2.2 Movement, wall damage, multi-hitbox — write the plan, then do it ✅ code (2026-09-06: `docs/plan-movement-hitboxes.md`, Commits A+B landed as one) · ⬜ the hitboxes themselves (plan §5, art pass) · ⬜ sandbox check on both monitors

The workflow's nine results are in `docs/research/movement-workflow-notes.md`: three readers
(how force is applied, the damage pipeline with quantities, the body and what a multi-hitbox
needs), three proposals (minimal / physics-first / hitbox-first, each with exact changes,
balance numbers, assertions and hours), three judges with scores and graft notes. **Write
`docs/plan-movement-hitboxes.md` from them** — winner by judge total, grafting the losers'
best ideas — in the shape of `docs/plan-expressive-buddy.md`: diagnosis, ordered steps by file
and function, calibration table (before/after/why), hitbox design (parts in art-pixel space,
multipliers, reactions, attribution, cost), tests in words, art dependencies, open decisions.
Then implement it in the same sequential, suite-after-each way as 2.1. The owner's report to
satisfy: he must walk, not hop; self-motion and settling must not pay or hurt; a throw, a
drop or a swing still must.

### 2.3 The rest of the assessment's code findings ✅ (2026-09-06, one commit; every item below done — `world_bounds` names its layer bit, `playtime_sec` dropped, 22 button icons through `UIStyle.set_icon`)

All in `docs/assessment-2026-09.md` §1, none started:

- `progression.gd:224` — nested StringName dict for the `get_modifier` cache key (hottest lookup).
- `milestones.gd:88-132` — index milestones by goal key instead of walking the board per event.
- `panel_page.gd:57` — coalesce `request_refresh` to once per frame; shop and tree inherit it.
- `friendly_base.gd:149` — skip `get_colliding_bodies()` when no touch/scrub/contact rate is set.
- `economy.gd:242,254` — bank Dollars into the automation tick instead of a grant per hit.
- Coroutine `await`s with dead `is_instance_valid(self)` guards (`throwable_base.gd:44`,
  `cluster_bomb.gd:88`, `npc_base.gd:417`, `missile.gd:85`, `buddy.gd:299`) → bound method or child Timer.
- `hud.gd` health meter polled per frame → `HealthComponent` signals.
- Tuning CSV `source` column: add `source_id` to `EventBus.payout` and write it in `tuning_log.gd`.
- Pacing sim speed: cache the affordable set per currency, invalidate on purchase (8 min → seconds).
- `loop_check.gd:204,206` — free the two `RigidBody2D.new()` (the exit-time leak report).
- Docs: `balance.tres` holds two values; the knobs are `balance_data.gd` defaults — say so in
  `economy.md` § Tuning and CLAUDE.md.
- Low: `save_schema.gd:22` dead `playtime_sec`; five copies of `effective_damage_mult()`;
  `world_bounds.gd:35` bare layers; nine direct `button.icon` writes; `trampoline.gd:412` unswept dict.

### 2.4 Playtest ⬜

The M2 five-minute stranger test, now that the next-up row, onboarding and spawn-on-purchase…
**note: spawn-on-purchase (assessment §4 item 9) is not done** — one line at
`shop_panel.gd:440-446` emitting `spawn_requested` after a successful buy. Do it before the test.
Log the session (`tuning_log.gd` writes `user://logs/session_*.csv` in debug builds) and read it
the way `assessment-2026-09.md` §2 read the Aug 31 one.

---

## 3. Blocked on the art generator 🚫

The Retro Diffusion MCP was not connected in the sessions that did this work (`docs/art-pipeline.md`
§1 says how; the key is `RD_API_KEY` in Claude settings, never the repo). When it is:

- Sprites for feather_duster (34x14 cell), tennis_ball (14), party_popper (18x24), warm_towel
  (38x22), kite (40x40): the M3.7 recipe in `art/prompts/items.md` (`rd_fast__low_res`, three
  takes, magenta + remove_bg, **state the viewing angle**), then `item_postprocess.py` with new
  rows in its scale table, editor pass, `tools/wire_icons.tscn`. About $0.30.
- A generated soft-brush icon to replace the plotted one (optional; the plotted one reads).
- The fist icon (`Assets/sprites/icons/fist.png` is the prototype's anti-aliased render).
- The walk cycle and the five animation families — `docs/plan-expressive-buddy.md` §4 has the
  twelve tags in build order with costs and the three tooling changes to make first.
- Visual findings from the assessment §3 that are art, not code: gorilla walk sheet, buddy
  frame litter (`idle_sad` f2/f6, `happy` f8), the headphones through the knockout beat, the
  ten near-black items, the five unreadable-at-32px explosives, the scale-table gaps.

---

## 4. Decisions only the owner can make

- **Four Bones-priced toys sit on the kind door** (`item_data.gd` maps `CATEGORY_TOY` to
  `SIDE_KIND`; beach_ball, bowling_ball, trampoline, desk_fan cost Bones) and the critters gate
  behind three of them. Move them to the harm door, price them in Hearts, or split Toy by currency?
- **Onboarding pins both drawers and persists the pin** (it goes through the drawer's own
  setter, so `Settings.hud_pinned`/`tabs_pinned` become true for a new player). Intended, but say so.
- The plan's **D36** wording ("at Focus Off he reacts; he does not initiate") — accept as written?
- The eight open decisions at the end of `docs/plan-expressive-buddy.md` §8.
- The arcade's five-minute x2 income boost and whether the arcade is in the demo (assessment §4).
- Whether the pacing simulator's new attention model (favourite + five newest toys) is the
  player you want it to model. It is what the Aug 31 session showed; it is not what the docs
  described before.
