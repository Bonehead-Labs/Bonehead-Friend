# Roadmap

Sizes are rough solo-dev-with-AI estimates, not commitments. **Gates are commitments** — don't
start the next milestone until the current gate passes.

| Milestone | Size | Status |
|---|---|---|
| M0 — Cleanup & foundations | ~1 wk | ✅ **complete** (2026-08-28) |
| M1 — Overlay spike | 1–2 wk | 🟡 **code complete** — manual gate pending |
| M2 — Vertical slice | 3–4 wk | 🟡 **systems complete** — playtest gate pending |
| M3 — Systems & buddy uplift | 4–6 wk | 🟡 **systems, art and shell complete** — playtest gate pending |
| M4 — Demo / Next Fest | 2–3 wk | ⬜ |
| M5 — 1.0 | 4+ wk | ⬜ |

---

## M0 — Cleanup & foundations

Make the repo safe to build on. No new features.

- Pin Godot 4.7.2-stable; commit `project.godot` and `.vscode`.
- Delete dead code: `backup_BaseLevel.gd` (registers a conflicting `class_name BaseLevel` and
  still contains the line that broke the export build), `backup_base_level.tscn`,
  `PROTOTYPE.tscn`, `test_body.tscn`, `PT-MainCharacter.gd`, `_Res_GunConfig.{gd,tres}`,
  `SoundPlayer.gd`, `Main.gd` autoload. Reopen the editor afterwards to catch broken references.
- Project settings: VSync **on**, physics 120 → 60 tps, `stretch/mode = "disabled"`,
  `snap_2d_transforms_to_pixel = true`, named collision layers.
- Fix the known prototype bugs while the codebase is still small: trash bin (erase-while-
  iterating, timer flag never reset, item count never decremented), `BaseDraggable`
  (`_input` → `_unhandled_input`, viewport-vs-global mouse position), replace
  `has_method("Character")` duck-typing with groups, free leaked explosion nodes, remove the
  fist's stranded invisible collider, strip stray `print()`s, normalise tabs.
- Build `EventBus`, `Settings`, `SaveManager` (schema v1) + the headless test runner.
- Art pipeline configured end-to-end; one test sprite generated, edited and imported as proof.

**Gate:** clean Windows export boots; headless smoke test passes; no orphaned-node warnings; one
asset has travelled the whole art pipeline.

### ✅ M0 outcome (2026-08-28)

Done: nine dead files deleted; engine pinned; VSync on, physics 120→60, stretch disabled, pixel
snap on, collision layers named (Godot then normalised `project.godot` by dropping the lines
whose values are engine defaults — the settings are still in effect); `EventBus`, `Settings`,
`SaveManager` built and wired; `SaveSchema` and `EconomyMath` extracted as pure, testable
modules; headless test runner added — **53 assertions passing**; boot smoke test clean.

Bugs fixed: trash bin (erase-while-iterating, never-reset timer, whitelist by group instead of
duck-typed markers); `BaseDraggable` (`_input`→`_unhandled_input`, consistent global mouse
space); item-count slots no longer permanently burned; cursor powers found by group rather than
absolute path; explosion nodes freed instead of leaked; the fist's stranded invisible collider;
`Character`'s out-of-bounds check (tested the one direction gravity can't take him); explosion
falloff deduplicated into `ExplosionUtil`; the shapeless `_attackPhysics` probe removed from both
weapon scenes; all `print()` spam gone; tabs normalised.

Two bugs the new tests caught immediately, both of which would have silently short-changed
players at exactly the round numbers they'd notice: `max_affordable` returning 4 when the player
could afford exactly 5, and `pow(64, 1/3)` flooring to 3 instead of 4. Both were floating-point
slack, both fixed with an epsilon in `EconomyMath`.

Deferred to M2 (documented, not forgotten): `EffectsPlayer.Character` export shadows the
`Character` class and is referenced by five scenes; `Missle` spelling; the `_input` handler in
`_gun.gd`.

*Art needed:* none.

---

## M1 — Overlay spike (front-loaded risk)

**Status: 🟡 partially delivered. Click-through is cut and deferred; everything else works.**

### What shipped and is stable

- Borderless, always-on-top, per-pixel-transparent window, set at **window creation** in
  `project.godot` — not toggled at runtime, which is what caused the 2 px viewport
  oscillation that made the whole scene judder.
- Two window modes (D10): fullscreen overlay, and a small play area snapped to a corner
  (resized from 480x360 to 960x640 during the M2 visual audit; F9/F10 step it at runtime).
- `WindowLayout` — mode, corner snapping, clamping onto offset monitors, minimum size,
  stale-rect revalidation. Pure and unit-tested.
- `WorldBounds` — walls regenerated at runtime; the prototype's were nailed to 1280x720.
  Also pulls stranded bodies back in when the window shrinks.
- Monitor persistence with fallback when a saved monitor disappears.
- FPS governor (30 idle / 60 while anything moves or on input) and Low Power Mode.
- F3 debug overlay with developer hotkeys: F3 stats, F4 mode, F5 corner, F6 monitor,
  F7 low power, F8 overlay off.
- Editor-embedded-window detection, since an embedded window cannot be an overlay.

### What was cut

**Click-through.** Two implementations failed and it was removed at the user's request; the
window is transparent but takes every click in its rect. `docs/overlay-tech.md` explains why
the polygon approach cannot work (it clips rendering) and what would work instead. Treat it
as unstarted design work, not a bug to patch.

### What the gate still needs

CPU measurement on an exported build, and the display matrix in `docs/test-matrix.md`
(sleep/wake, monitor unplug, DPI changes). Neither is automatable.

Headroom measured here is ~3575 fps uncapped at 2560x1378 with a near-empty scene, so there
is no known performance problem — but that is a debug build on one machine, not the gate.

### Lesson worth carrying

Frame counters, viewport sizes and assertion counts all looked healthy through every one of
this milestone's failures. Overlay work has to be checked against a real window on screen.

*Art needed:* none.

---

## M2 — Vertical slice

One weapon, all the way through the loop. This is the "is the game fun" milestone.

- `ItemDB` + `ItemData` + `ItemSpawner` + generic data-driven shop tiles; **delete
  `item_menu.gd`** and its seven hardcoded handlers.
- `CursorPowerBase` consolidation (the menu rewrite touches every activation path anyway).
- Contact-impulse combat rewrite; `WeaponBase`/`ThrowableBase`.
- `Economy` + payout pipeline: Bones, floating numbers, hit-stop, first sounds.
- Three items, one weapon's three-node augment tree, save/load, offline stub.
- Overlay code merged in from the M1 spike behind `OverlayManager`.

**Gate:** hit → earn → buy → augment → restart survives a full round-trip with correct state; a
non-developer plays for five minutes without being told what to do.

*Art needed:* buddy hurt + happy frames, three item sprites + icons, shop panel 9-slice, font
chosen, first impact sounds.

### 🟡 M2 progress (2026-08-28)

**The systems half is done and verified; the human half of the gate is not.**

Built: `ItemData` / `AugmentNode` / `BalanceData` as typed resources under `res://Data`;
`ItemDB`, `Economy`, `Progression` and `AudioManager` autoloads, wired in the documented boot
order; `ItemSpawner`; receiver-side contact-impulse damage on `Buddy`; `WeaponBase`,
`ThrowableBase` and `CursorPowerBase` with the fist and pistol on it; `FXLayer` (pooled floating
numbers, magnitude-scaled hit-stop, Focus-Mode gated); a code-built HUD, shop, augment tree and
Esc menu; `main.tscn` booting straight to the buddy.

Deleted, as the milestone called for: `item_menu.gd` and its seven hardcoded handlers, the three
copy-pasted cursor-power activation implementations, `AttackBoxClass`, `HitBoxComponent`, the
duplicate `Resources/ItemData.gd`, the prototype menus and `base_level.tscn`. `Scripts/Globals/`
is gone entirely.

Roster is **seven items, not three** — bat, mace, grenade, dynamite, fist, pistol and the
missile strike — because once the pipeline is data-driven the extras cost a `.tres` each, which
is the point. The bat has its three-node tier-1 tree (Heavier Swing / Bone Collector / Lead Core).

Verified: 103 pure-function assertions, plus a new 49-assertion `loop_check` scene that walks
hit → earn → buy → augment → save → reload against the real autoloads, and steps real physics to
prove the contact-impulse model attributes damage to the right item and that resting contact
does not farm. Boot smoke test clean headless and in a real window.

**Visual audit (2026-08-29).** `tools/audit_shots.tscn` drives the real game through boot,
shop, tree, play and the Esc menu and saves a PNG of each to `user://audit/`, composited onto a
flat colour because a transparent window otherwise gets judged against whatever is behind it.
Four things it caught:

- The knockout meter was invisible. The default theme's progress background is a dark grey on
  our dark panel, so an empty meter read as a stray nub and the player could not see how close
  he was to collapsing. Explicit track and fill styleboxes now.
- Panels were 96% opaque. Over a per-pixel-transparent window that is the player's wallpaper
  showing through the UI; D6 says opaque and now they are.
- The play area was unplayably small (see D10).
- **Sprite scales were inconsistent** — buddy 2x, bat and mace 4x, missile 3x, grenade and fist
  1x, exactly as `art-direction.md` describes. A mace was taller than Bonehead. Everything is
  standardised on 2x now, sprites and colliders together, so the change is visual and reach
  rather than mass: contact impulse is mass times velocity, so damage per hit is unaffected and
  the loop check confirms it.

**Click audit (2026-08-29).** The shell was screenshotted but never clicked, and it turned out
none of it was clickable. `EscMenu` built a `CenterContainer` at `PRESET_FULL_RECT` on the
topmost `CanvasLayer`; containers default to `MOUSE_FILTER_PASS` rather than `IGNORE`, and the
viewport marks a mouse event handled as soon as any control claims it. That one invisible,
empty container was therefore the control under every click in the game — the dock buttons,
both panels and dragging the buddy all silently did nothing, and it drew nothing to explain
why. It now blocks only while the menu is open, which is the one time blocking is correct.

`tests/integration/ui_check.tscn` was added so this cannot recur: 35 assertions that push real
mouse events at the real widget rects, including a sweep asserting that **every visible button
on every page** is the control the cursor actually lands on, and that the buddy still takes a
drag. Confirmed in a real window as well as headless.

What that pass exposed and did **not** fix: the grenade and dynamite art is drawn nearly filling
its 64x64 cell, so at a uniform 2x a grenade is almost as tall as the buddy. That is an asset
problem, not a scale problem — `art-direction.md` says to author at true pixel size rather than
scale in-engine, and a per-item scale override would just reintroduce the inconsistency. Redraw
them smaller within the cell in the art pass.

**Still open before the gate:**

- The playtest. A non-developer has not sat down with it, and that is half the gate.
- No art. Everything is prototype sprites and a code-styled placeholder UI; the `Theme`, the
  font and the shop 9-slice are unstarted. Impact sounds are **synthesised at boot** as
  placeholders, not assets.
- ~~No Hearts source yet~~ — **closed in M3**: open hand, sponge, pizza and boombox.
- ~~Mood is fixed at neutral~~ — **closed in M3**: `MoodComponent` and the mood meter.
- ~~Knockout is a payout and a reset~~ — **closed in M3**: the collapse beat and the fountain.
- Balance is a first draft. Catalog prices are unchanged; reachability comes from the knockout
  bonus roughly doubling a round. Retune from real play, not intuition.
- ~~There is no settings menu.~~ **Closed in M3** (D16): a Settings panel page covers window
  mode, play-area size, corner, monitor, Focus Mode, Low Power and volumes. Streamer mode and
  hibernate remain M4. The F3 dev hotkeys still work and change the same values.
- **An equipped cursor power consumes every left click**, so you cannot drag anything while the
  fist, pistol or missile is on. The prototype behaved the same way. Whether a click on
  something grabbable should grab rather than fire is a design question for the playtest.
- The missile's price (2,500 Bones), blast radius (300 px), flight speed and 1 s cooldown are a
  first guess added to the catalog in this milestone — all four are fields in
  `Data/Items/missile.tres` and `Scenes/Powers/missile_power.tscn`, not code.

---

## M3 — Systems & buddy uplift

Breadth. Everything that makes it a game rather than a toy.

- Full buddy animation set + face layer + grime overlay; knockout collapse / pile / reassemble.
- `MoodComponent` and the mood-multiplier curve.
- Hearts, friendly items, the first Hearts generators.
- Mastery (+ shared pool), contract board, Reincarnation + personalities.
- Roster to ~15 items. Audio pass 1.
- Balance tuning against playtest CSVs.

**Gate:** the knockout beat feels good enough to repeat on purpose; a 30-minute session has no
dead ends (never more than ~5 minutes from the next affordable thing); both currencies are
clearly understood by a fresh player.

*Art needed:* the bulk of it — full animation set, ~15 item sprites + icons, pile sprite,
contract board, VFX set, SFX batch.

### 🟢 M3 engineering closed (2026-08-30)

**Every system in the milestone is built, and the shell has been hardened against the content
still to come. What remains of M3 cannot be closed from a keyboard: the art pass and the two
playtests.**

The gate is deliberately *not* signed off here. Two of its three clauses — "the knockout beat
feels good enough to repeat on purpose" and "both currencies are clearly understood by a fresh
player" — are answerable only by watching someone play, and the third needs the 30-minute
session's CSV. See **Still open in M3** at the end of this section for the handoff list.

Done in two passes on the same day. The first took mood, Hearts and the knockout beat, because
those three were also what blocked the M2 playtest gate. The second took the progression depth —
mastery, automation, contracts and Reincarnation — plus the roster and the tuning instrument.

---

#### Pass one: mood, Hearts, the knockout beat

These were taken first because they are also the three things blocking the M2 playtest gate —
Hearts had no source, mood was pinned at the U-curve's 0.6x trough, and the knockout was a
teleport.

**Mood.** `MoodComponent` on the buddy, with `MoodMath` pure and unit-tested beside it.
Damage pushes him down linearly, kindness lifts him by the root of its value, and both decay
toward 0 without overshooting. The rails are soft in one direction only: pushing deeper into
an extreme scales by the remaining headroom, pushing back toward the other rail is full
strength — which is what keeps the seesaw fast across the middle and makes 2.0x earned rather
than parked at. `Economy` mirrors the value off the bus (D15); the buddy persists it.

**Hearts.** Four friendly items, and the second currency now has a source:

| Item | Cost | Shape |
|---|---|---|
| Open Hand | free | hold and stroke; one kindness event every 0.25 s. The only free Hearts source, so it has to be free |
| Sponge | 40 H | removes grime on contact, pays on what actually came off |
| Pizza | 400 H | 25 Hearts on touch, consumed |
| Boombox | 1,200 H | 0.6 Hearts/s while placed — the first Hearts generator, and the shape every automation capstone will take |

All four are one `FriendlyBase` class with different exported numbers, so the fifth is a
`.tres` and a scene, not a script. Sustained sources emit on a separate bus signal that skips
the combo (D14).

**Grime.** He gets filthy from being beaten; grime multiplies Bones income down to 0.65x and
only the sponge removes it. That makes the cheapest Hearts item in the game the thing that
protects the Bones economy — D2's dual-currency spine, finally load-bearing rather than
stated. Never a wall: a filthy buddy still earns.

**The knockout beat.** Tip over (frozen, so it is choreography rather than solver noise) →
lie in a heap → payout fountain of coins that sums to the headline number → tween back
upright. `FXLayer` delays the fountain by the collapse time so the coins burst out of the
*pile* rather than out of a skeleton still standing.

**Settings, pulled forward from M4** (D16). Window mode, play-area size, corner, monitor,
Focus Mode, Low Power and volumes, as a third panel page. This was the parked question from
M2 and the answer was yes: the window is borderless, so without it a playtester had no
discoverable way to resize the game at all.

Verified: **152** pure assertions (up from 103), **99** in `loop_check` (up from 49) including
the full knockout state sequence and a real sponge-on-buddy physics contact, **57** in
`ui_check` (up from 35) including the settings page in the every-visible-button sweep. Save
schema bumped to **v2** with a migration and a real v1 fixture under `tests/fixtures/`.

**Checked on the 2560x1440 secondary monitor**, in both fullscreen-overlay and play-area
modes — `audit_shots` now takes `--screen N` and `--overlay`, because the HUD anchors to
window corners that are much further apart on an ultrawide than on a 16:9 panel. Three
layout bugs came out of that pass and are fixed: the panel was a fixed 420 px whatever the
window was (overflowing a 960x640 play area, and scrolling with 900 px of empty screen
beneath it on the overlay); the grime warning fired at a penalty that rounds to "x1.00" on
screen, so it read as permanent nagging; and the friendly tiles had no icon column, which
made the shop read as two lists rather than one.

---

#### Pass two: mastery, automation, contracts, Reincarnation

**Mastery.** Per-item XP from using a thing, ranks solved rather than looped (`MasteryMath`
inverts the XP curve in closed form, because it runs inside the payout pipeline), and the shared
pool. Ranks 10 / 25 / 50 unlock the branch, the capstone and a ×1.5 payout. Every rank crossed
drops a point in the pool, whose five checkpoints compound three ways: ×1.02 income, ×0.95
augment cost, +1 item slot each. The cost discount reaches the *quote* as well as the charge,
which is the half that quietly goes wrong.

**Automation.** Capstones bought with Hearts, gated on Mastery 25 — **not** on a Reincarnation,
which is a deliberate amendment to `economy.md` recorded as D17: the spec's own balance target
puts the first automation at 30 minutes and the first Reincarnation at 6–10 hours, and those
cannot both be true. `AugmentNode.automation_rate` is a rate rather than a multiplier and
therefore its own field (D11's one-rule discipline is worth more than folding it in). Rates run
the same payout pipeline as a swing, feed online *and* offline accrual, and every capstone has an
on/off switch — the Focus Mode promise requires being able to stop the desktop moving without
giving up the income.

**Contracts.** Three daily and one weekly, rolled from a day-index seed so a restart cannot
reroll the board. Rewards are Ectoplasm only (D18): a daily that paid spendable currency would
set the shop ladder's pace by the calendar. Sustained kindness deliberately does not count toward
them, and prestige deliberately does not reset them.

**Reincarnation.** Wipes the run, keeps ectoplasm, lifetime earnings, the prestige count, the
offline cap and the board. Rolls one of five personalities, never the one just played. A
personality is *only* a mood curve (D19) — Masochist pays for cruelty, Diva for kindness, Zen for
neither, Goth for a mood nobody would otherwise sit at. The Rebirth page spells out both halves
of the trade and needs two presses.

**Roster is 16.** Added frying pan, shotgun (pellets + spread on the same `GunPower` class as the
pistol), bowling ball, beach ball and the baseball — which is the Interactive Buddy homage, and
is a `FriendlyBase` with a minimum approach speed, so only a real throw counts as a catch.
Augment trees for the mace, pistol, grenade, frying pan and open hand, plus the bat's three-way
exclusive branch.

**Tuning instrument.** `TuningLog` writes every payout and purchase to `user://logs/*.csv` in
debug builds, with mood, grime, both balances and the live multiplier on every row. The M3 gate
is a claim about pacing that nobody can check from memory; this is what makes it checkable.

**Audio.** Clatter, rattle, kindness, rank-up, contract and prestige sounds — all synthesised
placeholders like the rest (D12).

#### Review pass

A `/code-review high` over the first pass found six issues, all fixed before the second pass
started. Three were real bugs rather than polish, and all three are the same species — a thing
that looked correct in isolation and was wrong in company:

- Pressing on Bonehead mid-collapse pinned a drag joint to a frozen body, held it through the
  whole beat while the reassemble tween wrote his position, and snapped him to the cursor when
  the beat unfroze him — with `idle` on the bus while he was in fact being dragged. The
  `_in_knockout` guard was on `_process` but not on input.
- The settings steppers resized and moved the window while their own readouts kept showing the
  old value, because `_stepper` connected its action raw where `_choice` wrapped it in a refresh.
- Petting polled `Input.is_mouse_button_pressed` instead of going through the input chain, so
  holding the button on a shop tile drawn over the buddy paid Hearts at four a second.

Plus: a boombox on the desk was completing "be kind 150 times" unattended (sustained kindness now
emits no contract event), recycled FX pool labels kept their previous tween running so a fresh
damage number would fly off along a stale parabola, and the mood meter allocated a `StyleBoxFlat`
per change against an explicit 3% CPU budget.

**Verified across both passes:** **193** pure assertions (from 103), **149** in `loop_check`
(from 49), **72** in `ui_check` (from 35) — 414 total. Save schema at **v3**, with a migration
step and a committed fixture for each of v1 and v2. Boot clean. Checked in a real window on the
2560x1440 secondary in both overlay and play-area modes.

#### Art pass, part one: the buddy (2026-08-29)

**Bonehead is animated.** Nine body tags and all ten facial expressions, in the game, for
**$0.98** of a $10.25 Retro Diffusion balance.

The approach is generated body + hand-drawn face, composited. That split was forced by the
first test: sending his face through the animation generator destroys it — two-pixel eyes
wander and melt by the fourth frame, and the outline starts picking up teal
([the side-by-side](images/face-degradation.png)). Generating him
*faceless* and compositing solved it completely, and it is the same layered arrangement
`art-direction.md` already wanted so mood could read independently of pose. The face is one
sprite repositioned per frame from `Data/buddy_face_offsets.json`, not a track baked per
animation — otherwise ten expressions across nine animations would be ninety sheets.

Costed against the API rather than guessed (`art-pipeline.md` now carries the table): preset
animation styles are $0.14 where `custom_action` is $0.25, frame count is free, and reversal
is free. So `hurt` is a `crouch`, `happy` is a `jump`, `collapse` is a `destroy` at 16 frames,
`reassemble` is that collapse reversed, and `pile` is its last frame held — three tags from
one generation. `dragged` is hand-made; the pin joint does the real work.

The knockout beat now **plays the animation instead of tweening a still sprite**, and its
timing is read from the animation's own length so retiming a tag in Aseprite retimes the beat.
The payout fountain waits for the buddy to actually reach `pile` rather than for a fixed
timer. Mood drives posture as well as expression — `idle_sad` slumps, `idle_happy` bounces —
which is what actually reads from across a desk, where the face is four pixels.

Two traps found and written into `art-pipeline.md` so they are not rediscovered: a face cannot
go through the generator, and a multi-tag `.aseprite` must be built in one pass with tags
created last (appending a frame silently extends any tag that ends at the last frame, which
made `idle` import as 74 frames instead of 8 and played the whole file for every animation).

#### Second review pass (2026-08-29)

A `/code-review high` over the progression and art work found ten issues, all fixed. Four
were bugs that would only have shown up days into a real session, which is exactly the class
a 30-minute playtest does not catch:

- **The contract board never rotated in a running session.** `refresh_contracts()` was only
  called from `from_save()`. Start the game at 22:00 and at 00:01 it is still showing
  yesterday's dailies — in a game whose pitch is staying open for eight hours. Now on a
  60-second timer, and re-checked whenever the Jobs panel is opened.
- **A redrawn daily kept yesterday's claim flag.** The reset loop cleared progress only for
  contracts *leaving* the board. With four dailies and three slots, a claimed one comes back
  about three times in four — still flagged claimed, rendering a full bar and paying nothing.
  One slot permanently dead, and worse every day. Rerolling a period now clears every
  contract of that period, and the two periods roll independently so a weekly still carries.
- **`dragged` was entered but never left.** It was reachable only as a side effect of a
  reaction lapsing mid-drag, and nothing cleared it, so a hit taken while holding him left
  him stuck in the dragged pose with his mood idle unable to resume. Picking him up and
  putting him down are now explicit state transitions.
- **A Reincarnation wiped the wallet but not the desk.** The equipped cursor power kept
  firing at full damage and payout after the reset, and weapons already on screen stayed
  usable with pre-prestige augment multipliers, while the shop correctly re-priced them as
  unowned. `ItemSpawner` now clears itself on `prestige_performed`.

Plus one real perf fix — the automation rate table was rebuilt twice per frame *before* the
early-out, two array allocations and two full dictionary scans at 60 Hz even for a player who
owns no capstone — and five smaller ones: the Ectoplasm chip read 0 after a load, overlapping
toasts cut each other short, mastery rank-ups forced a full synchronous save each time,
banked kindness was dropped when a sponge was binned mid-scrub, and the contract panel
re-formatted every row on every hit while closed.

The four silent ones now have regression tests. Suites: **193 / 206 / 72 = 471 assertions.**

#### Art pass, part two: items and VFX (2026-08-29)

**Thirteen item sprites, thirteen icons and the explosion, in the game, for $0.86.**

The headline fix is scale. Every prototype sprite had been drawn to *fill* its 64x64 cell,
so a hand grenade rendered 55 px tall against a 63 px buddy. `art-direction.md` now carries
a scale table anchored on his 63 px body, and `art/tools/item_postprocess.py` resizes every
generated sprite to its entry — enforced mechanically rather than remembered, which is the
only reason it will stay true. The grenade is 14 px now.

The four prototype body scenes were hand-authored `.tscn` with one-frame `SpriteFrames` and
eyeballed colliders, so new art could not reach them. `tools/seed_bodies.gd` rebuilds them
from the scale table with colliders derived from the sprite's own opaque bounds. Masses are
carried over unchanged deliberately: damage is contact impulse and impulse is mass times
velocity (D7), so re-authoring visuals must not quietly re-tune combat.

The explosion was an untextured `CPUParticles2D` — a spray of white squares — and it is the
effect the grenade, dynamite and missile all share. The VFX style returned a *flicker loop*
rather than a blast, so `postprocess` scales and fades it into a proper bloom: free, and
more controllable than re-rolling.

Icons are downscaled from the sprites rather than generated, which is free and guarantees the
icon is the item it labels.

Two more things worth carrying forward, both in `art-pipeline.md`: passing `input_palette`
constrains colours at generation time and *wrecks the subject* (the first sponge came back a
gold rectangle with a green smear, because the palette had no dark yellow); and the stated
background must be a colour the project does not own — "on a plain white background" put
background removal in competition with a white sprite. Magenta, then snap the palette after.

#### Pass three: the shell

The look was picked before it was built. Four skins were mocked up as browser artifacts and
shown side by side, then the winning skin's two hardest screens — the shop and the upgrade
tree — were mocked again in four layouts each. What shipped is the chosen pair: **Bonecard**,
with the shop as icon-led category tabs ("Toys B") and the upgrades as a real tree ("Upgrades
B"). Doing it that way cost an afternoon of mockups and saved building three shops.

**The Theme.** `UITheme` builds the whole skin in code — surfaces, the type scale, and every
type variation the panels ask for (`Card`, `Tile`, `TileHot`, `TileDead`, `Sunk`, `Chip`,
`Badge`, `Gate`, `Capstone`, five button variations, four label variations). `UIStyle` is now
the palette and the numbers; it no longer assembles anyone's look. See D20.

**Two fonts, and a rule.** Silkscreen for display, Pixelify Sans for prose, and *every figure
in the game in Silkscreen* — Pixelify draws 5 as something that reads as 8 at 14 px, which the
first screenshot pass caught on the bat's "+15% damage" node. Both are OFL and committed with
their licences; both are loaded unhinted and unantialiased. Neither covers CJK, so the theme
attaches a `SystemFont` fallback until M4 picks a face that does.

**Fourteen hand-drawn glyphs** (`art/tools/make_ui_glyphs.py`), free and reproducible. They
carry the rule from `art-direction.md` that currencies must be separable by shape as well as
colour: a price is a bone or a heart plus a number, never a "B" or an "H".

**The two screens.** The shop is one category at a time, tabs led by the first item in each
category that has art, with a badge counting what is affordable inside — so the shop says where
to look before it is opened. The tree is drawn as a tree: three tier-1 nodes with their levels
as pips, wires fanning into a trunk, a black gate strip that says PICK ONE — PERMANENT and then
names the branch you took, the two branches you did not struck through and left on screen, and
the automation capstone alone at the bottom in teal.

**Motion, everywhere something happens.** `UIMotion` (D21): keys that depress and overshoot,
rows that lift and nudge the toy in them, cards that grow out of their own corner, rows that
deal in, a gold bloom on a purchase, a rotation buzz and a red wash on a refusal, a coin thrown
from the press into the purse, and figures that roll rather than snap. Six synthesised UI
sounds joined the placeholder set (hover tick, key, tab, denial buzz, open and close sweeps).

**Two capture tools**, because a menu cannot be reviewed from source and every attempt to
eyeball the theme by reasoning about stylebox margins was wrong. `tools/ui_shots.tscn` renders
the nine screens; `tools/ui_motion_shots.tscn` records the motion as frame sequences and *must*
be run with `--fixed-fps 60`, or each frame's delta is however long the previous PNG took to
write. Both host the game in the root viewport, centre a normal window so the run can be
watched, and use their own save slot — the first version wrote its staged test state into the
player's real save.

Four bugs the screenshots caught that nothing else would have: white glyphs invisible on cream
card stock (the theme's icon colour was the engine's default white), a zero-width scrollbar (a
scrollbar's thickness *is* its track stylebox's minimum size, and a `StyleBoxFlat` with no
content margins has none), category badges rendered as 8 px smudges (a child of a plain
`Control` is never laid out, so it keeps the zero size it was created with), and the digit
problem above. `loop_check` now has a **shell** suite that asserts every glyph, font, theme
variation, UI sound and the scrollbar's width, so none of them can come back silently.

#### Pass four: the shell, reworked from a review

The first Bonecard build was reviewed on screen and three things came back, all of them fair:
two tab rows for five pages, a panel that changed size on every tab click, and too much text
to read. A fourth turned up while fixing them — the trash bin had never worked.

- **One navigation.** The dock is gone; the tab strip owns the panel and never moves (D22).
- **One card size**, for every page, enforced by `ui_check` and structurally by
  `SCROLL_MODE_SHOW_NEVER` on every page's scroll.
- **The shop is master/detail** — a thin list and one detail pane. Thirteen stacked
  descriptions became one, set large.
- **The HUD is one box**: purse, knockout, mood. The item count and the grime warning only
  appear when they are true of something.
- **The UI scales in whole numbers** (D23). This was the actual cause of "hard to read even
  after I scaled up": the shell was drawn at a fixed pixel size, so a bigger play area made
  the game bigger and left the menus alone. Auto-picked from the window height, pinnable in
  Settings.
- **The trash bin is gone** (D24). Right-click an item, or clear the desk from the counter.

#### Pass five: hardening the shell against its own future

A comprehensive review was run against the shell — nine lenses, adversarially verified — after
a playtest note that "clipping, icon alignment, scaling and such" would make it hard to keep
adding items and features. It found eighteen confirmed defects, one of them a **blocker**: the
Rebirth page's two-stage confirm was only ever cleared by the reset itself, so arming it and
closing the card left the run one stray click from being deleted, hours later, from another
page.

Two findings were the same shape and account for most of the rest. **Nothing normalised an item's
picture to the box the UI reserved for it** (now D27), and **nothing owned "which page is live"**
(now D28) — five pages ran full refreshes on every hit with the card shut, because a page's own
`visible` flag is only written when the card *switches* pages, so `if visible:` passed forever.

Fixed, with the class closed rather than the instance:

- **The size contract** (D27). `UIStyle.boxed()` steps oversized art down by a whole number and
  centres it on a box-sized canvas, so a glyph fallback and full-bleed art occupy identical
  space. Adding an item can no longer move the UI. A follow-up correction mattered as much as
  the rule: the boxes were then *smaller than the art* — 32px icons asked for at 24 were being
  halved to 16 — so `boxed()` now records every shrink and `ui_check` asserts it never happens.
- **`PanelPage`** (D28), which every page extends. Closed pages do no work and replay what they
  deferred on open.
- **`hover_pressed` on every variation.** A button state the theme does not define falls through
  to Godot's *stock dark* theme, not to a neutral default — so hovering any toggled-on button put
  dark ink on a dark box and the label vanished. The contrast grid is now derived from the Theme
  itself, and a third grid reads the live tree.
- **One tab width**, derived from the card rather than from each caption, and identical whether
  or not the page is open.
- **A pinned UI scale is allowed to lose** to a play area too small to hold the card.
- **`export_presets.cfg` excluded `art/*`** — and the buddy animation and the explosion load from
  `res://art/src/`. Every build shipped so far had neither.

Two shell features came out of the same round. **Both halves of the shell now hide until hovered**
(D29), leaving a small outlined mark that becomes a pin on hover and turns red when clicked; and
**the purse is stacked one currency per line**, printing grouped digits — `987,652,252` — for as
long as they fit and abbreviating past a billion. Side by side, `157 ♥ 167` read as one quantity
with a symbol in the middle of it.

Assertions went from 414 to **660** across four suites (193 unit / 309 loop / 148 UI / 10 window).

**Still open in M3:**

- **Crosshairs and cursor art.** Pistol, shotgun and missile still use prototype cursor
  textures. They work, so they were left last. The **open hand now has a real icon**
  (seed 30036, $0.051) — and with it a finding worth the price: a skin-toned subject must be
  desaturated *before* `item_postprocess.py`, or the palette snap lands it on the yellow ramp
  with its finger creases on the reds, which reads as an injured hand. Greyed first, it snaps
  onto the bone ramp Bonehead himself is drawn in, which is the right answer for a cursor hand
  anyway. **`shotgun` is now the only item in the catalog with no art**, and `loop_check`'s
  content suite prints that backlog by name every run.
- **The rest of the art.** Grime is a tint on the puppet rather than a sprite layer; the rest
  of the VFX set (impact stars, bone chips,
  heart burst, coin fountain) and the remaining five buddy tags
  (`dizzy`, `dance`, `relax`, `eat`, `catch`, `sleep`) are unbuilt — deliberately, since
  nothing plays them yet. Budget remaining: **$8.43** — the shell cost nothing, since its
  glyphs are hand-plotted and its fonts are OFL.
- **Hand-finishing.** The generated bodies are a starting point, not a deliverable
  (`art-pipeline.md` step 8). Two mechanical defects were found by measurement and fixed in
  `postprocess.py` rather than by hand, so they stay fixed for every future generation: the
  outline came back open on 110-190 edge pixels per animation (he dissolved on a white
  desktop), and `idle_sad` carried floating litter above his head on two frames. What is
  left is genuinely artistic and wants a person: the silhouette has drifted slightly squarer
  than the original bone shape, and the idles *translate* rather than deform — he hops
  8-9 px instead of bobbing, because head and feet move together and the body height stays
  at 63 px throughout. Converting a hop into a real squash-and-stretch bob is a redraw, not
  a transform. The headphones floating above the bone pile are **kept deliberately**.
- **`buddy.tscn` has still not been opened in the editor**, so `MoodComponent`,
  `GrimeComponent`, the `Face` node and `BuddyArt` are all built in code. Authoring them
  properly is a job for whoever next opens the scene.
- **Automation has no visible device.** The design calls for a sentry bat on a tripod, a
  self-stirring chocolate fountain — "an idle desktop still looks alive". Today a capstone is an
  income rate and nothing on screen. That is an art-and-scene job, not an economy one.
- **The buddy animation set.** Still one idle loop. Hurt, happy, dance and sleep states exist on
  the bus and drive nothing; the face and grime layers in the architecture diagram are not in the
  scene yet.
- **Balance is a first draft with many more knobs in it.** Mastery XP rates, pool steps,
  automation rates, contract targets and every friendly price are first guesses. The CSV log
  exists specifically so the retune is done against data.
- **Both playtests.** M2's five-minute non-developer test and M3's 30-minute no-dead-ends
  session. Neither is done, and between them they are most of what is left before M4. They are
  also the only remaining blockers on the M3 gate — every automated check the milestone can
  have is green (660 assertions across four suites).

---

## M4 — Demo / Next Fest

Re-scoped 2026-08-30, after M3's shell work delivered more of this milestone than planned and
uncovered one item that has to come first.

**Already done, ahead of schedule** (struck from M4's list):

- Settings UI: window mode, play-area size and corner, monitor picker, Focus Mode, Low Power
  and volumes all shipped in M3 (D16). Whole-number UI scaling (D23) was not on any list.
- Auto-hide (D29) was built as a UX fix but is most of what *streamer mode* was for — the shell
  parks off screen and leaves a mark. What streamer mode still owes beyond it is the chroma-key
  background and hiding figures a viewer should not see.

**Do first, before anything is built for release:**

- **Export an actual build and check it.** `export_presets.cfg` excluded `art/*` while the buddy
  animation and the explosion load from `res://art/src/` — so every build produced so far has
  shipped without them. The preset is fixed; nothing has verified the fix in an exported `.exe`,
  and the whole performance budget is defined as *measured on an export*.

**Remaining:**

- Streamer mode proper (chroma-key background, hide-sensitive-figures) and
  hibernate-on-fullscreen. Both are the last two rows of the Settings panel.
- Full manual test matrix on two machines, including a 4K one. `docs/test-matrix.md` grew a
  shell section in M3 that has never been run by hand.
- Performance hardening against the budget, on an export. M3 added `PanelPage` specifically so
  closed pages cost nothing; that claim is asserted in a headless test and has never been
  measured with a profiler.
- Demo content cut (through roughly the first automation unlock), Steam page, capsule, trailer.

**Gate:** test matrix green on both machines; CPU budget met at 4K **on an exported build**;
zero known save-loss bugs; the export contains its art.

Sequencing note: build a wishlist audience *before* the festival — Next Fest roughly doubles
what you already have, and doubling zero is zero. Capsule art quality correlates with wishlist
conversion more than demo length does. Launching adjacent to a themed Steam sale is worth
planning around.

*Art needed:* key art, capsule, trailer capture, store screenshots on a realistic messy desktop.

---

## M5 — 1.0

- Remaining items to ~24, all augment trees, weekly contracts, cosmetics.
- Achievements (40–70), Steam Cloud, CJK localisation, audio pass 2, polish.

**Gate:** content complete; demo saves migrate cleanly; localisation verified in-game.

---

## Post-1.0

In priority order — the first item is the flagship free update and the best marketing asset the
game has:

1. **Occupational Hazard** — real OS windows as physics colliders (needs the Win32/GDExtension
   spike; start it during M3 so the option stays open).
2. Working Hours / Pomodoro integration.
3. Twitch integration.
4. Cosmetic supporter pack (~$4).
5. Bonehead's Workshop — visual scripting + Steam Workshop.
6. Skeleton crew — multiple buddies.
