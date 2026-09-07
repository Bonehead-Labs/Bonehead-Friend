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

**As of 2026-09-06 evening: unit 212 · loop 551 · ui 227 · pacing 4/4 (9:16, now ~2 min to run).
Everything through §2.4's spawn-on-purchase is committed; the tree is clean. What is left needs a
human (the playtest, the sandbox walk on two monitors), the owner (§4) or the art generator (§3).**


**As of 2026-09-06 late (end of session 4): unit 225 · loop 595 · ui 455 · pacing 4/4; release build
measured at 0.44 / 0.42 / 0.69 % of the machine. §7–§13 below record the day; everything still
outstanding is consolidated in `handoff-2026-09-06.md` — read that first.**
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
| 10 | Highly reactive, expressive buddy | ✅ Phases 1–2 · ⬜ Phase 3 (art) | `docs/plan-expressive-buddy.md` Phases 0–1 built and green: `ExpressionBrain` (one arbitrated beat slot, D36), the `BuddyArt` accumulator, all eight reaction tables wired, four voices, F3 row, 80+ loop and 20 ui assertions. Phase 2 (personality on the surface: six tell fields on `PersonalityData`, nine `.tres` seeded by `tools/seed_m38_personality_tells.tscn`, the mood row names him) done 2026-09-06; Phase 3 (art) needs the generator. |

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

### 2.4 Playtest ⬜ (needs a human) — spawn-on-purchase ✅ (2026-09-06)

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

---

## 5. The stickiness pass (2026-09-06, evening) ✅

Done after §0–§2.4 on the owner's standing instruction to act as project lead. Four commits,
each closing an open item from `assessment-2026-09.md` §4's "ten changes by impact per effort",
all code, no art, suites green after each:

| # | What | Where | Commit |
|---|---|---|---|
| 5.1 | **Streak and combo drawn and heard.** `Economy.damage_streak()` (presentation only — pays nothing, asserted); FXLayer tags `x7` / `x1.3` above the number; impact pitch +3%/hit, kindness chime +5%/act | `economy.gd`, `fx_layer.gd`, `audio_manager.gd` | `b51e148` |
| 5.2 | **Deeds page** (sixth tab: every milestone with its next rung, secrets masked, the record) and the HUD's **"Reincarnate for +N Marrow"** link (opens the Arcade scrolled to Rebirth, never resets) | `deeds_panel.gd`, `hud.gd`, `panel_layer.gd`, `EventBus.ui_show_panel` | `0ef373a` |
| 5.3 | **Personality on the surface** (expressive plan Phase 2): six tell fields on `PersonalityData`, nine `.tres` written by `tools/seed_m38_personality_tells.tscn`, the mood row names him | `personality_data.gd`, `expression_brain.gd`, `buddy_art.gd`, `hud.gd` | `b3b7bc6` |
| 5.4 | **Dream Journal** welcome (`Data/dreams.txt`, x1.15 for 5 min, the cap sting said once) and the **offline cap for sale** on the Reincarnation page (2 h → 8 h → 24 h for 4,000 / 40,000 Hearts) | `main.gd`, `economy.gd`, `balance_data.gd`, `prestige_panel.gd` | `19df327` |

Counts after: **unit 216 · loop 571 · ui 250 · pacing 4/4 (9:16)**. Tree clean.

Still open from the assessment's list, and why: music (audio pass); a cosmetics store (hat art,
§3); the idle mood floor, the arcade boost and whether the arcade is in the demo (owner, §4);
Martyr/Tyrant/Stoic tells (owner, plan §8 item 4). New owner decisions this pass added: the
Dream buff's size (x1.15 / 5 min is a knob), the sleep prices (knobs), and whether a damage
streak should ever pay (it deliberately does not).

## 6. The second stickiness pass (2026-09-06, night) ✅

Same brief, same method: the docs' own unbuilt promises, chosen for stickiness, no art.

| # | What | Where | Commit |
|---|---|---|---|
| 6.1 | **The Wardrobe.** `CosmeticData` (slot bone/phones, Dollar price, tint) on the shader's masks; ten finishes seeded by `tools/seed_m38_finishes.tscn`; owned/worn in `Economy`, saved in the schema's existing `cosmetics` shape; a rail on the Arcade page | `cosmetic_data.gd`, `effects_player.gd`, `economy.gd`, `item_db.gd`, `buddy_art.gd`, `arcade_panel.gd` | `cff7b32` |
| 6.2 | **Jobs badge** (claimable count on the tab) and the **streak's record**: `stats.best_streak`, "x12 best" tag from six, Deeds shows best streak and a never-saved "This session" receipt; cursor outranks toy for his attention | `panel_layer.gd`, `economy.gd`, `fx_layer.gd`, `deeds_panel.gd`, `expression_brain.gd` | `741cd68` |
| 6.3 | **Round score.** `Economy.last_round` (number, damage, seconds from first hit, Bones incl. bonus, record vs `stats.best_round_bones`); one-line toast; Deeds shows best round | `economy.gd`, `main.gd`, `deeds_panel.gd` | `a0249a1` |

Counts after: **unit 216 · loop 595 · ui 263 · pacing 4/4** (unchanged; nothing here touches a rate).

Decisions this pass made that the owner may revisit: finish prices (600–3,500 Dollars, headphones
800–2,500 — knobs in the seeder table); "best" shown on the streak tag from six; the round clock
starts at the first hit. Still open and why: music (assets); hats and alternate-headphone *shapes*
(art — the wardrobe's tint slots are where they plug in); Working Hours / Overtime (needs global
input or a policy call); Lunch Break, Insurance Fraud, Loyalty (design calls, some need art).

## 7. The visual uplift (2026-09-06, late) ✅

Brief: every feature from §5–§6 and the Arcade get animation and particles; the Arcade gives
each game the real estate of a proper mini game. Recorded as **D37**.

| # | What | Where |
|---|---|---|
| 7.1 | **Arcade rooms.** One machine on screen behind a five-tab `IconTab` strip (Wheel, Three Ghosts, Blackjack, Wardrobe, Rebirth); one 270px stage for every machine; wheel 132→262, reels 32→96, cards 30x46→60x92 with a hero rank and 32px pips; Play key 150x44; page chrome cut to one line each | `arcade_panel.gd`, `spin_wheel.gd`, `slot_machine.gd`, `blackjack.gd`, `panel_layer.gd` |
| 7.2 | **`UIMotion.sparkle` / `UIMotion.fill`.** Pixel-chip particle burst on a control; tweened progress bars | `ui_motion.gd` |
| 7.3 | **Celebrations.** Arcade win/jackpot chips in the prize's colour; deed claimed (row confirm + chips, bars tween); finish worn (swatch chips + `WorldFX` stars on him); next toy affordable; rebirth row's first appearance; Jobs badge appearance; record round → chipped toast and a "NEW BEST ROUND" line under the knockout headline | `arcade_panel.gd`, `deeds_panel.gd`, `hud.gd`, `panel_layer.gd`, `fx_layer.gd`, `main.gd` |
| 7.4 | **Proof.** `ui_check` `rooms` suite (29 assertions: five rooms, tabs at real rects, one view visible, wells equal and ≥280, prestige flag follows the room); `ui_shots` gains one shot per room and a Deeds shot | `ui_check.gd`, `ui_shots.gd` |

Counts after: **unit 216 · loop 595 · ui 292 · pacing 4/4** (nothing here touches a rate).

Seen in the shots and fixed before commit: the first cut's 300px stage put the Play key under the
fold on every machine (page eyebrow, two-line intro and a duplicated machine name were the cost);
the face-down card at 60x92 was a black slab and is now a double frame.

## 8. Backdrops (2026-09-06, late) ✅

Owner's idea, same session: "the option of selecting different backgrounds, not forcing the
transparent one … a basic solid grey, and then other colours and scenes that don't conflict …
ensuring they work with the various scales, fullscreen on various monitors". Recorded as **D38**.

| # | What | Where |
|---|---|---|
| 8.1 | **`Backdrop`** layer under the world: Desktop (transparent, default), six flat colours incl. Chroma key green, five drawn scenes (Night sky, Dusk, Hills, Graph paper, Desk) painted to the window rect in whole blocks sized from the window height | `Scripts/World/backdrop.gd`, `main.gd` |
| 8.2 | **Setting.** `Settings.backdrop` in `settings.cfg`; `OverlayManager.set_backdrop()`; `EventBus.backdrop_changed`; a BACKDROP section of two choice rows on the Settings page, built from `Backdrop.CHOICES` | `settings.gd`, `overlay_manager.gd`, `event_bus.gd`, `settings_panel.gd` |
| 8.3 | **Proof.** `ui_check` `backdrop` suite (66 assertions: every choice clicked at its real rect, layer shown/hidden, canvas equals the viewport, canvas ignores the mouse, save/load round trip, unknown id falls back); `ui_shots` adds the settings rows and three scenes, restoring the player's choice | `ui_check.gd`, `ui_shots.gd` |

Counts after: **unit 216 · loop 595 · ui 358 · pacing 4/4**.

Not done and why: a scene per monitor (the setting is one value; the window is on one monitor at
a time); animated scenes (the budget is < 3% idle — a static repaint on resize costs nothing, a
drifting sky would not); art-generated backdrops (§3, the generator). The scene palette is a
first pass by eye and is the kind of thing a playtest should look at on a real ultrawide.

## 9. The world has juice (2026-09-06, late) ✅

Owner's brief: "another visual deep dive game wide, consider animations for things that dont have
them consider particle effects and addictive dopamine triggering special effects where possible".
The shell already moved (§7); this pass is the world. Recorded as **D39**.

| # | What | Where |
|---|---|---|
| 9.1 | **`WorldFX` vocabulary.** `puff` (dust/soot/smoke/heat), `ring` (drawn shockwave, pooled `Ring` Node2D), `tracer`, `bolt` (jagged), `shot`, `heat`, `boom`, `shake` (viewport canvas transform, Normal+ only, ≤9px, 220 ms); `WorldFX.of(node)` finds it by group | `Scripts/World/world_fx.gd` |
| 9.2 | **Wired to the world.** Landing dust (`EventBus.buddy_landed`, from his feet); spawn pop + puff and despawn puff; explosion boom; pistol/shotgun/minigun sparks; turret tracer; lightning bolt from above along the chain; sunbeam heat; trampoline dust; missile smoke trail; hit chips heat up with the streak; one heart every 1.4 s from a kind item in use; mood band crossings; grime stages and a white burst at clean; stars at a rank; three rings + stars + jolt at Reincarnation; ring + jolt at knockout | `buddy.gd`, `event_bus.gd`, `effects_player.gd`, `gun_power.gd`, `turret_base.gd`, `lightning_power.gd`, `beam_power.gd`, `trampoline.gd`, `missile.gd`, `world_fx.gd` |
| 9.3 | **Over his head.** `FXLayer` prints "MACE  RANK 4", "REINCARNATED / +2.50 MARROW" (centre, top tier, Ectoplasm), "SQUEAKY CLEAN"; `welcome_shower` throws offline Bones and Hearts off him as coins a second after boot | `fx_layer.gd`, `main.gd` |
| 9.4 | **The shell's last gaps.** Knockout meter glows (looping modulate) from 85% and punches the card on entry; rank, contract-ready, rebirth and offline toasts are `celebrate_toast`s in their currency's colour | `hud.gd`, `main.gd` |
| 9.5 | **The bug it found.** `WorldFX`'s `CPUParticles2D` pool never drew a pixel in this project — every hit chip and pet heart since D30 was invisible. Pool is now `GPUParticles2D` with cached materials | `world_fx.gd`, CLAUDE.md gotcha |
| 9.6 | **Proof.** `ui_check` `juice` suite (37 assertions: pools named, listeners wired, nothing at Focus Off, rings/lines/jolt put away, landing dust, rank line + stars, clean line, rebirth headline + Marrow line + jolt, meter glow on/off); `ui_shots` `16/16b/16c-juice` at 2/6/12 frames | `ui_check.gd`, `ui_shots.gd` |

Counts after: **unit 216 · loop 595 · ui 395 · pacing untouched** (nothing here changes a rate).

Not done and why: a motion trail on him when flung and a swing trail on melee weapons (both need a
per-frame process on a body — worth it, but it is the one per-frame cost this pass refused to add
without measuring on an exported build); a vortex swirl (same); NPC arrival beats beyond the spawn
puff (the art pass owns their animation); screen flash on a knockout (a white flash over a
transparent window tints the player's whole desktop).

## 10. The rhythm on the card, life on the desk (2026-09-06, late) ✅

Owner's brief: "AGAIN MORE ADDICTION MORE BEAUTIFUL". Recorded as **D40**.

| # | What | Where |
|---|---|---|
| 10.1 | **Streak row on the HUD.** `x12 STREAK` and `x2.4 COMBO` cells with a bar draining to the lapse; colour heats bone→orange over twenty hits; punch per step, gold flash at a new best; a 20 Hz timer alive only while a streak is | `hud.gd` (`_build_streak_row`, `_tick_streak`), `economy.gd` (`streak_seconds_left`, `combo_seconds_left`) |
| 10.2 | **On him.** Embers from a streak of ten (`EmberTimer` at 10 Hz while alive), a gold star sparkle while blissful (mood ≥ 80); both parented to his body, both off at Focus Off | `world_fx.gd` (`_set_ambient`, `_gate_ambient`) |
| 10.3 | **Trails.** Every `BaseDraggable` leaves a tapered world-space `Line2D` above 550 px/s from the collision shape's corner farthest from the grip; gold / rose (`FriendlyBase`) / white (`Buddy`) via `trail_colour()`; built on first use | `base_draggable.gd`, `friendly_base.gd`, `buddy.gd` |
| 10.4 | **Ambient life.** `FriendlyBase.AMBIENT` by id: steam (hot tub, foot spa, tea, noodles, pizza, fountain), bubbles (bubble machine, fish tank, paddling pool), twinkle (fairy lights, lava lamp, cake, chimes), notes (boombox, record player); one GPU emitter per item, materials cached per kind | `friendly_base.gd` |
| 10.5 | **Small ones.** Ring at the contact on a hit ≥ 60% of the hit-stop scale; a deed claimed throws its coin at the purse | `world_fx.gd`, `deeds_panel.gd` |
| 10.6 | **Proof.** `juice` suite grows by 13 (row hidden → x3 → lapses; embers/bliss on and off with Focus; trail world-space, hidden, white; hot tub steams and stops); `16-juice` shots stage a 12-streak and a hot tub | `ui_check.gd`, `ui_shots.gd` |

Counts after: **unit 216 · loop 595 · ui 408 · pacing untouched**.

Not done and why: a swing *sound* pitched to speed (the synth has no whoosh voice yet); afterimage
ghosts of the puppet when flung (the trail covers it at a tenth of the cost); a streak-lost
sting (the genre punishes enough — the bar draining is the whole warning).

## 11. Every item, juiced by its level (2026-09-06, late) ✅

Owner's brief: "go through every single item one by one and juice them up … as they are upgraded,
making them even more juiced up, for instance a level 3 baseball bat … looks much cooler than the
base one, or at least emits more effects". Recorded as **D41**.

| # | What | Where |
|---|---|---|
| 11.1 | **The tier.** `MasteryMath.juice_tier(rank, levels)` (rank 3/10/25 or levels 1/6/15 → tier 1/2/3); `Progression.juice_tier(item_id)` cached and invalidated on purchase / rank / reset / load | `mastery_math.gd`, `progression.gd` |
| 11.2 | **Worn on every body.** `ItemGlow` outline shader (one texel, breathing via `TIME`, stilled at Focus Off); trail width +2.5/tier and +3 points/tier; `Aura` emitter from tier 2 (chips / hearts); `apply_juice()` on spawn and from `ItemSpawner.refresh_augments` on purchase, rank and Focus change; colour ramps `WorldFX.harm_colour` / `kind_colour` | `item_glow.gd` (new), `base_draggable.gd`, `friendly_base.gd`, `item_spawner.gd`, `world_fx.gd` |
| 11.3 | **Per family.** Hits: chips ×(1+0.35·tier) in the tier colour, ring every hit from tier 2, white sparks at 3. Explosions: art and boom ×(1+0.25·tier), fuse sparks while primed. Guns: sparks +2/tier, ring from tier 2. Sunbeam: a visible beam from above, width 1.5+tier, heat +2/tier. Lightning: width 3+tier, `tier` forks. Vortex: orbiting `Swirl` at the cursor, 10+6·tier chips. Fist: sparks on a punch, ring from tier 2. Turrets: tracer 2+0.7·tier wide in the tier colour, muzzle puff from tier 2. Kind items: ambience ×(1+0.5·tier), heart burst 5+3·tier when he gets in. Trampoline: ring from tier 2 | `world_fx.gd`, `effects_player.gd`, `throwable_base.gd`, `missile.gd`, `cluster_bomb.gd`, `gun_power.gd`, `beam_power.gd`, `lightning_power.gd`, `vortex_power.gd`, `fist_power.gd`, `turret_base.gd`, `friendly_base.gd`, `trampoline.gd` |
| 11.4 | **Proof.** 9 unit assertions on the ladders; `ui_check` spawns a rank-capped bat (tier 3, glow > 0.9, aura emitting, Focus Off stills it, Focus on wakes it); `16-juice` shots stage a rank-40 bat beside a rank-8 mace | `run_tests.gd`, `ui_check.gd`, `ui_shots.gd` |

Counts after: **unit 225 · loop 595 · ui 416 · pacing untouched** (the tier is presentation; no rate moved).

Not done and why: per-item bespoke effects beyond the family (a chainsaw's sawdust, a katana's
clean cut, a rubber duck's squeak ring) — the family treatment covers all hundred today and a
per-id table is the next step once the art pass fixes which items are hero items; a tier-4
"mastered" look at rank 50 (the economy's rank-50 bonus) — worth adding when a playtest reaches it.

## 12. Measured on a build, and heard (2026-09-06, late) ✅ · turrets look at him ✅

Owner's brief: "address item 2 and 3" of the sellability assessment — measure CPU on an exported
build; real sounds from free libraries. Then, mid-pass: "the turret's sprite is static and doesn't
rotate and flip to look at the player, its projectile comes from the center". Recorded as
**D42** and **D43**.

| # | What | Where |
|---|---|---|
| 12.1 | **A release build, measured.** 4.7.2 export templates installed; `main.gd` accepts `-- --perf-stage=empty\|idle\|load` (own save slot, no settings writes, stage report to `user://perf_<mode>.txt`); `tools/perf_measure.ps1` runs the exe and reads CPU (one core and machine-wide), GPU 3D and working set. **Result: 0.44 / 0.42 / 0.69 % of the machine; 7 / 7 / 11 % of one core; 310–420 MB.** Budget is < 3 % idle, < 8 % load | `main.gd`, `tools/perf_measure.ps1`, D42 |
| 12.2 | **Recorded sounds.** 71 CC0 files from six Kenney packs under `Assets/audio/<id>_<nnn>.ogg`; `AudioManager.ASSETS` lists them, `_load_assets` resolves through the import remap, `play` picks a random variant, synthesis stays as the fallback and for every chime, breath, roar and clatter; per-id gain table; new `land` thud on `buddy_landed` | `audio_manager.gd`, `Assets/audio/`, `Assets/audio/CREDITS.txt` |
| 12.3 | **Turrets look at him.** `muzzle` / `faces` / `flips` per turret from a pixel probe of the art; the sprite mirrors to face him and turns within its cap; tracer, sparks and smoke leave `muzzle_position()`; scenes regenerated from the seed | `turret_base.gd`, `seed_m36_turrets.gd`, `Scenes/Turrets/*` |
| 12.4 | **Proof.** `ui_check` `audio` suite (31: every listed file imported, synth kept where meant); turret assertions in `juice` (mirror on his right, art-facing on his left, nozzle side, cap overhead); `16-juice` shots stage two turrets on the side their art does not face | `ui_check.gd`, `ui_shots.gd` |

Counts after: **unit 225 · loop 595 · ui 454 · pacing untouched**.

Needs a person: the recorded levels (`ASSET_GAIN_DB`) were set by reasoning about peak levels, not
by ear — listen with headphones and adjust. Working set (~320 MB) is the next performance number
to look at. The mortar's barrel rests at 45° in its art, so its "aim" is a tip rather than a turn;
a two-part sprite (base + barrel) is the art-pass fix for every turret.

## 13. The art pass, as far as it goes without a generator (2026-09-06, late) ✅ / 🚫

Owner's brief: "okay do the art pass now", with a note that a Codex session via plugin could
generate pixel art. **Neither Codex nor Retro Diffusion is exposed to this session** (no tool, no
`RD_API_KEY` in the environment), so this is the half that can be drawn by hand in code. Recorded
as **D44**.

| # | What | Where |
|---|---|---|
| 13.1 | **Five plotted kind items** at scale-table size in the palette, outlined: feather duster, tennis ball, party popper, warm towel, kite; scenes regenerated so they are sprites, not polygons; icons rebuilt and wired | `art/tools/make_hands_on_items.py`, `Assets/sprites/items/`, `Assets/sprites/icons/`, `Scenes/Friendly/*` |
| 13.2 | **Fist icon** replaced with a bone-cream fist in the same idiom | `make_hands_on_items.py`, `Assets/sprites/icons/fist.png` |
| 13.3 | **Turret barrels.** Pellet turret, nail gun, rail gun and flamethrower split into `_base` and `_barrel` sprites; seed hangs a `Barrel` node at the pivot; `TurretBase` turns the barrel on the mount (cap 30–40°), mirrors pivot and offset with the flip, fires from the barrel\'s muzzle; mortar keeps one sprite (its tube runs through its tripod) | `art/tools/split_turret_barrels.py`, `seed_m36_turrets.gd`, `turret_base.gd` |
| 13.4 | **Pixel grime.** Soot speckles per texel that thicken with the value over a deepening wash, in the shared flash shader | `effects_player.gd` |
| 13.5 | **Proof.** Turret assertions read the barrel; all suites green | `ui_check.gd` |

🚫 **Blocked on the generator:** the walk cycle and the animation families (`dance`, `relax`,
`eat`, `catch`, `sleep`), proper two-part turret art, and a generated replacement for the five
plotted items. To unblock: set `RD_API_KEY` (docs/art-pipeline.md) or expose the Codex plugin in
the session, then follow `art/prompts/items.md` — the seeds and prompts for the batch are there.

> **Corrected 2026-09-07 (D45).** "Neither Codex nor Retro Diffusion is exposed to this
> session" was false. The Codex CLI on this machine has a native `imagegen` tool and
> `codex exec` drives it headlessly; `art/tools/codex_imagegen.sh` wraps it. The five plotted
> items and the fist icon have been regenerated, and eight near-black items from the
> assessment given the dual-tone treatment. Still genuinely blocked on Retro Diffusion: the
> walk cycle and the animation families, because Codex returns no spritesheet and has no
> walking preset. The two-part turret art is undone by choice, not by blocking — see D45.
