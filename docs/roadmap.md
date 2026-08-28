# Roadmap

Sizes are rough solo-dev-with-AI estimates, not commitments. **Gates are commitments** — don't
start the next milestone until the current gate passes.

| Milestone | Size | Status |
|---|---|---|
| M0 — Cleanup & foundations | ~1 wk | ✅ **complete** (2026-08-28) |
| M1 — Overlay spike | 1–2 wk | 🟡 **code complete** — manual gate pending |
| M2 — Vertical slice | 3–4 wk | ⬜ |
| M3 — Systems & buddy uplift | 4–6 wk | ⬜ |
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
- Two window modes (D10): fullscreen overlay, and a small play area snapped to a corner.
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

---

## M4 — Demo / Next Fest

- Settings UI complete: Focus Mode slider, Low Power Mode, monitor picker, streamer mode,
  volumes, hibernate-on-fullscreen.
- Full manual test matrix on two machines, including a 4K one.
- Performance hardening against the budget.
- Demo content cut (through roughly the first automation unlock), Steam page, capsule, trailer.

**Gate:** test matrix green on both machines; CPU budget met at 4K; zero known save-loss bugs.

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
