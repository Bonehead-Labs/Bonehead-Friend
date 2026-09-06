# Bonehead Friend — Agent Guide

**Bonehead Friend** is a Windows desktop-overlay idle game: a transparent, always-on-top
window holding a physics skeleton ("Bonehead") you interact with using weapons and kind
items while you work. Damage earns **Bones**, kindness earns **Hearts**; both buy unlocks,
augments and automation. Interactive Buddy (2005) crossed with an incremental game.

Read `docs/README.md` first — it indexes the full spec. Design questions are answered in
`docs/game-design.md` and `docs/economy.md`, not by guessing.

---

## Environment (read this before running anything)

- **Engine is pinned to Godot 4.7.2-stable.** Do not open the project in another version;
  it rewrites `config/features` and `.tscn` formats. See `docs/decisions.md`.
- The repo lives on the Windows filesystem (`/mnt/c/...`) but agents run in **WSL**.
  **Godot must be run as the Windows executable**, never a Linux build. Note the doubled
  path segment — the release zip was extracted into a folder named like the exe:
  `"/mnt/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"`
  (use the `_console.exe` sibling to capture stdout from WSL)
- Any tool that is a Windows `.exe` (Godot, Aseprite) must receive **Windows-style paths**
  in its own arguments, even when you invoke it from WSL. Convert with `wslpath -w`.
- Never run `godot` from a Linux PATH — it is not installed and a Linux build would
  produce a broken export.

## Hard rules

1. **`res://` paths are case-sensitive in exported builds.** They resolve fine in the
   editor on Windows and then crash the shipped `.exe`. This has already shipped once as a
   bug (commit `4d831ab`: `res://Scenes/bodies/...` vs the real `res://Scenes/Bodies/...`).
   Always match the on-disk case exactly, including the extension.
2. **No absolute node paths across scenes.** `get_node("/root/BaseLevel/_Gun")` is banned —
   it is the coupling that produced the export bug above. Communicate with `EventBus`
   signals or node groups; use `@export` node references within a single scene.
3. **Tabs for indentation** in all `.gd` files (matches the existing code and
   `.editorconfig`). Two files in the old prototype use spaces; fix them when touched.
4. **No `print()` in committed code.** Use `push_warning()` / `push_error()`, or the F3
   debug overlay. The prototype printed every physics frame; that is a perf bug in a game
   designed to idle for eight hours.
5. **Never commit secrets.** The Retro Diffusion API key lives in the user's Claude settings
   env, not in the repo. `.env*` is gitignored.
6. **Don't hand-edit `.tscn`/`.tres` files** beyond trivial one-line diffs — make structural
   scene changes in the editor, or generate resources from script.
7. Scratch files go in the session scratchpad, never the repo root.

## Conventions

- **Scripts**: `snake_case.gd` filenames; `PascalCase` `class_name`; `snake_case` members and
  methods; `SCREAMING_SNAKE` constants. Private helpers prefixed `_`.
- **IDs**: content ids are `snake_case` `StringName`s (`&"baseball_bat"`) and are the join key
  between `ItemData`, `AugmentNode`, `MasteryTrack`, save data and analytics. Never rename an
  id without a save migration.
- **Data lives in resources**, not code: `res://Data/Items/*.tres`, `res://Data/Augments/*.tres`,
  and one `BalanceData` (`Scripts/Data/balance_data.gd` holds every global tuning knob as an export default; `res://Data/balance.tres` overrides just two). Systems read `ItemDB`.
  Adding an item must never require editing a script.
- **Spelling**: it is "Missile", not "Missle". The prototype misspells it in filenames, class
  names and a user-facing label; correct it as you touch each.
- **Collision layers** (named in Project Settings — never use bare numbers):
  `1 world · 2 buddy · 3 item · 4 handle · 5 pickup · 6 sensor`.
  Handles collide with nothing. Sensors are Area2D-only.
- **Autoload boot order** is load-bearing:
  `EventBus → Settings → SaveManager → ItemDB → Economy → Progression → OverlayManager → AudioManager`.

## UI

The shell is **Bonecard** (docs/decisions.md D20, docs/art-direction.md § UI). Three rules
that are not obvious from the code:

- **Panels never build their own look.** Set `theme_type_variation` and let
  `Scripts/UI/ui_theme.gd` answer. Adding a variation means adding it to `UITheme` *and* to
  the `shell` suite in `loop_check` — a misspelled variation silently falls back to the base
  type and merely looks wrong.
- **The type is Jersey 25 (display) and Jersey 15 (reading), with DotGothic16 behind them
  for CJK.** They replaced Silkscreen + Pixelify Sans, which a playtest found hard to read;
  Pixelify also drew 5 as something that read as 8. Sizes are chosen by *measured cap
  height* — see the ladder in `ui_style.gd`, and change it the same way.
- **No text may be dimmed with alpha.** `loop_check`'s `contrast` suite asserts every ink
  against every surface at 4.5:1, and a disabled control uses `UIStyle.DISABLED_INK`. The
  palette was picked by eye once and Bones came out at 2.97:1 on a sunk well.
- **All menu animation goes through `UIMotion`** (D21), which is off when Focus Mode is Off and
  always off in headless. Never tween `position` or `size` on a control inside a `Container`,
  and never fade a card — the window is transparent behind it.
- **There is one navigation and one card size** (D22). The tab strip owns the panel; the HUD
  has no dock. Every page is the same size and scrolls internally, with
  `SCROLL_MODE_SHOW_NEVER` rather than `SCROLL_MODE_DISABLED` — a disabled axis folds the
  child's minimum size into the ScrollContainer and one long line widens the card for every
  page.
- **Anything that pins `Settings.ui_scale` must restore it.** The screenshot tool did not,
  so every capture after it was silently at 2x — including the ones used to judge whether
  1x was readable.
- **Every picture is exactly the size of the box that holds it** (D27). Go through
  `UIStyle.icon()` / `sprite()` / `set_sprite()` / `set_icon(button, texture, box)` / `item_face(item, box)`, never `rect.texture`
  or `button.icon` directly — a Button *grows* to fit its icon, so one 64px PNG made a shop row
  nearly twice the height of the row under it and pushed that row's name 30px right. Oversized
  art is stepped down by a whole number and centred on a box-sized canvas; nothing is resampled
  at a fraction. `ui_check`'s `geometry` suite measures against the **declared** box, because
  measuring the realised size passes the very bug it exists to catch.
- **A page that is not on screen does no work** (D28). Pages extend `PanelPage` and call
  `request_refresh()` / `request_rebuild()`; deferred work replays on open. Never gate on
  `visible` — a page's own flag is written only when the card switches pages, so the last page
  opened stays flagged visible under a shut card and `if visible:` passes forever.
- **The shell is scaled by a whole number per CanvasLayer** (D23, `UIScale`). Because of that,
  `get_global_rect()` on any shell Control is in canvas space and wrong by the scale factor:
  anything comparing a control to a mouse position uses `UIScale.screen_centre` /
  `screen_rect`. Each layer's root Control is sized explicitly rather than anchored full-rect.

Two capture tools exist because the shell cannot be reviewed from source:

```bash
# The nine screens, as PNGs in user://ui_shots (NOT --headless: it has to draw)
"$GODOT" --path "$PROJ" res://tools/ui_shots.tscn

# Motion, as frame sequences in user://ui_motion. --fixed-fps is mandatory: without it each
# frame's delta is however long the previous PNG took to write.
"$GODOT" --fixed-fps 60 --path "$PROJ" res://tools/ui_motion_shots.tscn
```

Both run the real `main.tscn` against their **own save slot**, which `CaptureWindow` clears
before and after. Anything else that boots `main.tscn` outside the game must do the same — the
first version of these tools left staged test state in the player's save.

## Save data

- Versioned JSON at `user://save/slot_1.json`, written atomically (`.tmp` → rename, previous
  kept as `.bak`). `Settings` is separate (`user://settings.cfg`) and is **not** cloud-synced —
  it holds machine-specific monitor rects.
- **Changing the save schema requires all three**: bump `SAVE_VERSION`, add a
  `_migrate_N_to_N+1()` step, and commit a fixture save of the old version under
  `tests/fixtures/`. A schema change without a migration is a data-loss bug.
- Offline earnings use wall-clock deltas — always clamp negatives to zero (clock changes and
  cloud-sync skew are real).

## Verifying work

```bash
GODOT="/mnt/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
PROJ='C:\Users\George\Godot Projects\Projects\Bonehead_Friend\interactive-buddy-2'

# Economy math, save round-trips, every migration step
"$GODOT" --headless --path "$PROJ" -s tests/run_tests.gd

# The whole loop against the real autoloads, including stepped physics
"$GODOT" --headless --path "$PROJ" res://tests/integration/loop_check.tscn

# Is the game still paced the way docs/economy.md says? Plays 72 hours of a modelled
# player against the real content in about a second. `-- --csv` dumps the timeline;
# `-- --divisor 5e7` tries a prestige divisor without editing balance.tres.
"$GODOT" --headless --path "$PROJ" res://tests/integration/pacing_sim.tscn

# Can the player actually click the UI? Synthetic mouse events at the real widget rects
"$GODOT" --headless --path "$PROJ" res://tests/integration/ui_check.tscn

# Boot smoke test — catches broken @export refs and missing scene paths
"$GODOT" --headless --path "$PROJ" --quit-after 120

# Window modes, against a real DisplayServer. NOT headless — a headless run has no window,
# so apply_window_configuration() returns immediately and none of this is exercised. This
# exists because Overlay -> Play area silently stopped working and nothing could catch it.
"$GODOT" --path "$PROJ" res://tools/window_check.tscn

# Does the export still contain its art? Export a pack, then read its file table. Templates
# are NOT needed for --export-pack, which is why this is the check that runs from here.
"$GODOT" --headless --path "$PROJ" --export-pack "Windows Desktop" 'C:\path\to\check.pck'
python3 tools/pack_check.py /mnt/c/path/to/check.pck

# The performance budget, on a RELEASE BUILD (editor numbers lie). Needs the 4.7.2 export
# templates under %APPDATA%\Godot\export_templates\4.7.2.stable\ (installed 2026-09-06). The game
# stages its own desk from the flag, on its own save slot, and reports what it staged
# (docs/decisions.md D42). Modes: empty | idle | load.
"$GODOT" --headless --path "$PROJ" --export-release "Windows Desktop" 'C:\path\to\Bonehead Friend.exe'
powershell -File tools/perf_measure.ps1 -Exe 'C:\path\to\Bonehead Friend.exe' -Mode idle

# Seed res://Data (writes only files that do not exist; add `-- --force` to overwrite)
"$GODOT" --headless --path "$PROJ" res://tools/seed_data.tscn
"$GODOT" --headless --path "$PROJ" res://tools/seed_friendly.tscn
"$GODOT" --headless --path "$PROJ" res://tools/seed_m3_content.tscn

# A playable sandbox: the real game with everything unlocked and money to burn, on its own
# save slot so slot_1 is never touched. NOT headless — this one is for playing.
# `-- --keep` continues the last sandbox instead of staging a fresh one.
"$GODOT" --path "$PROJ" res://tools/sandbox.tscn

# Visual audit. NOT headless — headless does not render and its viewport is 64x64.
# --screen N picks the monitor, --overlay runs the real fullscreen overlay instead of a
# play-area window. Shots land in user://audit/ and are suffixed with the screen.
"$GODOT" --path "$PROJ" res://tools/audit_shots.tscn -- --screen 1 --overlay
```

Check layout on **more than one monitor**: the HUD anchors to window corners that are much
further apart on a 3440x1440 ultrawide than on a 2560x1440 16:9 panel, and a panel height
that looks right in one is wrong in the other. Three layout bugs came out of exactly that
comparison in M3.

`--path` takes a **Windows** path because Godot is a Windows process. Adding `--editor --quit`
opens the project in the editor headlessly, which is how to verify an addon loads.

A new PNG, `.aseprite` or font is invisible to `ResourceLoader.exists()` until the editor has
imported it, so a seed tool that wires art written in the same session silently skips it. Run the
editor pass after adding an asset, then re-run the tool.

**After adding any script with a new `class_name`, run the editor pass before anything else:**

```bash
"$GODOT" --headless --editor --quit --path "$PROJ"
```

Global class names are resolved through `.godot/global_script_class_cache.cfg`, which only
the editor regenerates. Create a `class_name` script from outside the editor and the runtime
cannot find the type — an autoload that references it fails to *instantiate*, which cascades
into "Identifier not found" errors in unrelated scripts and a game that boots into nothing.
It looks like a code bug and isn't.

GDScript quirks already paid for once each:
- `PackedVector2Array(...)` and similar constructors are **not constant expressions** — a
  `const` initialised with one fails to parse, taking the whole autoload chain with it.
- An **enum used as a parameter type is a distinct type across script boundaries**, so a
  caller passing `Foo.Corner.TOP_LEFT` will not satisfy a `corner: Corner` parameter in
  `Foo`. Type such parameters as `int`.
- `OS.get_environment()` does **not** see variables exported from WSL, because the game is a
  Windows process. Pass values as command-line args (`-- --flag`) instead.
- **A full-rect `Container` on a `CanvasLayer` eats every click in the game.** Containers
  default to `MOUSE_FILTER_PASS`, not `IGNORE`, and the viewport marks a mouse event handled
  as soon as any control claims it — so one invisible full-window container on the topmost
  layer killed the dock, both panels *and* dragging the buddy, while drawing nothing.
  Full-rect layout Controls must be `MOUSE_FILTER_IGNORE` unless they are a modal blocker,
  and `tests/integration/ui_check.tscn` sweeps for it.
- **A SubViewport with no `SubViewportContainer` above it never learns the mouse is inside
  it**, and physics picking is gated on that, so pushed input reaches GUI but never the
  world. Send `notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)` yourself in tests.
- **A solved inverse needs the same epsilon a `floor()` does.** `MasteryMath.rank_for_xp`
  inverts `base * rank^1.6`; without `EPSILON` before the floor, a player who has *exactly*
  reached rank 10 is told they are rank 9 — at precisely the threshold they are watching. Every
  `floor()` in `EconomyMath` exists for the same reason.
- **`_set` is `Object`'s own property-setter virtual.** A private helper named `_set(value)`
  fails to parse with "the function signature doesn't match the parent", and because it is a
  parse error it takes every dependent script down with it — the failure surfaces as
  `main.gd` failing to load, nowhere near the file at fault.
- **`get_meta(key, null)` does not suppress the error**, because a null default is
  indistinguishable from no default given — and `set_meta(key, null)` *removes* the key rather
  than storing a null. Guard every optional meta read with `has_meta()` first. This took out
  the whole upgrade panel on boot.
- **A `StyleBox` with no content margins has no minimum size**, and a scrollbar's thickness
  *is* its track stylebox's minimum size — so a themed `VScrollBar` came out zero pixels wide
  and a panel that scrolled perfectly looked like it was cut off.
- **A `connect()` that never runs is invisible.** Four `EventBus.connect` calls ended up after
  a `return` in the middle of `FXLayer._ready()` — no parse error, no warning, no missing node,
  and the game simply stopped showing payout numbers, taking hit-stops and playing its knockout
  fountain. `ui_check` now asserts the connections exist and that a payout draws something.
  Build UI nodes with an explicit `name`, too: `FXLayer.new()` came out as `@CanvasLayer@24`,
  which no test can find and nobody can read in the remote scene tree.
- **A child of a plain `Control` is never laid out**, so it keeps the zero size it was created
  with — and, just as importantly, keeps its *old* size when its minimum later shrinks. Own
  both halves of its rect (`size` **and** `position`) and `reset_size()` deferred as well as
  immediately, because the minimum it clamps to is recomputed later in the frame. A tab strip
  that had grown to 697px stayed 697px inside a 480px window when the play area stepped down.
  Anchoring is not enough; give it explicit offsets. (A `Container`, by contrast, lays
  out *every* child into the same rect — which is how a full-card strike-through overlay is
  built, deliberately.)
- **A GDScript lambda captures locals by value.** A counter incremented inside one leaves
  the outer variable at zero — which in a test means reporting a working mechanic as broken.
  Capture an `Array` or a member instead.
- **Looking a node up by name across a scene boundary is the same bug as an absolute node
  path.** `ExplosionUtil` required a child called `_explosionAreaShape`; when the item scenes
  were rebuilt from script the shape came out called `CollisionShape2D`, and *every explosion
  in the game applied no force at all* for the price of one `push_warning` nobody read. Find
  things by what they are.
- **The Aseprite importer marks every animation as looping**, so a one-shot effect replays
  for the life of its node. `set_animation_loop(name, false)` and free on `animation_finished`.
- **A `SubViewportContainer` competes with pushed input.** `tests/integration/ui_check.gd` uses
  a bare SubViewport for a reason; adding a container above one makes synthetic mouse events
  stop reaching buttons. Tools that push input host the scene in the **root** viewport instead.
- **A `Button` state the theme does not define falls through to Godot's stock dark theme**,
  not to a neutral default. Nothing in the shell defined `hover_pressed`, so hovering any
  toggled-on button — every page tab, every shop category, every selected list row — drew a
  dark stock box under our dark ink and the label vanished. `loop_check`'s contrast suite now
  walks the Theme itself and grades every (stylebox, font colour) pair it defines.
- **Never poll `get_mouse_position()` for hover logic.** It reads the OS cursor, which no
  synthetic event can move, so anything built on it cannot be driven by a test or a capture
  tool. Track `InputEventMouseMotion.position` instead (and treat `NOTIFICATION_WM_MOUSE_EXIT`
  as the cursor leaving, since no further motion arrives).
- **`size_changed` on the viewport is not enough after a window-mode change.** The window
  resize has not landed when the setting is applied, so a layout done then is against the
  previous window. `OverlayManager.window_rect_changed` fires once it has settled.
- **`Image.create()` is deprecated; `Image.create_empty()` is the current spelling.**
- **A `CPUParticles2D` emits and never draws in this project.** The world's burst pool sat
  "emitting" at the right place with the right texture for the whole of M3 and no chip ever
  reached the screen — every hit chip and pet heart since D30 was invisible, and only the shot
  tool showed it. Use `GPUParticles2D` with a `ParticleProcessMaterial` (as `FXLayer`, `UIMotion`
  and `WorldFX` do), and treat a particle effect as unfinished until a capture shows it.
- **A pinned `Settings.ui_scale` must be allowed to lose.** Play area size and menu size are two
  settings the player reaches independently, and the smallest rung at 2x leaves a 240x180 root —
  smaller than the card's own minimum in both axes, so the card clamps *up* past the window and
  takes the tab strip that would have fixed it off-screen with it. `UIScale.factor_for()` steps a
  pinned factor down until the shell fits; `window_check` asserts six rungs x three scales.
- **A test that reads `Settings` must pin what it reads and restore what it writes.** `ui_check`
  clicks a real Focus Mode button, whose handler calls `save_settings()` and serialises *every*
  field — so a run used to leave the developer's own Menu size wherever the test put it, and every
  screenshot taken afterwards was silently at the wrong scale. Capture on the first line of
  `_ready()`, before anything is stomped, and `save_settings()` again before quitting.
- **A headless viewport is 64x64**, not the project's 1280x720. Anything derived from the
  window size — `WorldBounds`, the trash bin anchor, the buddy's out-of-bounds rescue — is
  meaningless in a headless run, and a generated floor ends up inside the buddy rather than
  under him. Headless physics tests must supply their own geometry.

Two more constraints the test runner imposes, both already worked around:
- Autoload singletons are **not registered under `-s`**, so a script the tests import must
  not reference `EventBus` and friends. That is why `SaveSchema`, `EconomyMath` and
  `AugmentMath` are pure and separate from `SaveManager` / `Economy` / `Progression`. Keep new
  logic testable the same way. Anything that genuinely needs the autoloads runs as a **scene**
  instead (`tests/integration/loop_check.tscn`, `tools/seed_data.tscn`), which is also why
  loading an item scene under `-s` fails — its scripts reference `Progression`.
- `Unrecognized UID: "uid://..."` during a headless *editor* run is benign first-import
  noise, not a broken main scene.

Run the test suite before any commit touching `Economy`, `Progression` or `SaveManager`, and
the UI check before any commit touching `Scripts/UI/`. **Run the pacing simulator before any
commit touching `balance.tres`, an item price, or an augment's numbers** — it is the only
thing in the project that can check a target stated in hours, and every balance number it
prints can be argued with because the player it models is a page of named constants at the
top of the file.

**Signal handler order is load-bearing in the payout pipeline.** Autoloads connect to
`EventBus` before scene nodes do, so `Economy` pays at the mood and grime in force *when the
event fired*, and `MoodComponent` / `GrimeComponent` move them a moment later. Any test that
computes an expected payout must read the multipliers **before** emitting — three assertions
failed this way while M3 was being built.

Overlay behaviour cannot be unit-tested — work through `docs/test-matrix.md` by hand at the
M1, M2 and M4 gates, and measure CPU on an **exported build** (editor numbers lie).

Performance budget, enforced at every gate: **< 3% CPU idle, < 8% under load.** This is the
single most common complaint about the genre; treat a regression as a build failure.

## Art

All art goes through **Retro Diffusion → Aseprite → Godot (Aseprite Wizard)**. The full
workflow, prompt rules and cost discipline are in `docs/art-pipeline.md`; style, palette and
sizing rules are in `docs/art-direction.md`. Key points: record every generation's prompt,
style and seed in `art/prompts/` so assets are reproducible; keep `.aseprite` sources in
`art/src/`; never write "pixel art" in a generation prompt; never blind-retry a failed
generation (it can double-charge — recover the result by request id instead).

## Current state

**M3's engineering is closed. What remains of the milestone is the art pass and the two
playtests — neither of which can be done from a keyboard.** Mood, grime, the Hearts economy, the knockout beat, mastery and the shared pool,
automation capstones, the contract board, Reincarnation with five personalities, a 16-item
roster and the debug CSV tuning log are done and verified — 660 assertions across the four
suites (193 unit / 309 loop / 156 UI / 10 window), save schema at v3.

The shell was then hardened against the content still to come (roadmap M3 pass five): the art
size contract (D27), `PanelPage` (D28), auto-hide with pinning (D29), a `hover_pressed` state on
every button variation, one tab width, a stacked purse that prints grouped digits, and three
separate contrast grids — `UIStyle`'s constants, the `Theme`'s own states, and the **live tree**.
The third exists because the first two both missed a real bug.

Two playtests are outstanding and between them are most of what is left before M4: M2's
five-minute non-developer test and M3's 30-minute no-dead-ends session.

See the M3 and M2 progress notes in `docs/roadmap.md` for exactly what is and is not
finished — they are the handoff list, kept current.

The settings panel covers window mode, play-area size, corner, monitor, Focus Mode, UI size,
backdrop (D38: the desktop by default, or a flat colour or drawn scene painted to the window),
Low Power and volumes (docs/decisions.md D16). Streamer mode and hibernate are still M4 — though
auto-hide (D29) and the Chroma backdrop (D38) deliver most of what streamer mode was for. The F3
dev hotkeys still work and change the same `Settings` values, which is why the panel re-reads
them on every refresh instead of caching.

**Item physics is authored, not derived.** `tools/seed_bodies.gd` carries a `PHYSICS` table
— shapes, centre of mass, where the drag joint pins, and where the grab region sits — in the
same art-pixel space as the scale table. Rebuilding the prototype scenes from the sprite
alone replaced a capsule-and-grip bat that swung with weight in its head with a box pinned at
its centre, which is a plank on a string. Anything not in the table falls back to a box
around the sprite, which is right for a grenade and a ball and nothing else.

`Scripts/Globals/` is gone — the production layout is `Scripts/{Autoload,Bodies,Buddy,Combat,
Components,Data,Economy,Overlay,Progression,Save,UI,World}`. Remaining prototype surface worth
knowing about: the item scenes under `Scenes/Bodies/` still carry their prototype node names
(`_grenadeSprite`, `_handle`) and `Scenes/Bodies/base_body.tscn` is still the bat/mace base.

**The buddy is animated** — nine body tags in `art/src/bonehead.aseprite` plus ten facial
expressions in `bonehead_face.aseprite`, driven by `Scripts/Buddy/buddy_art.gd`. Body is
generated (Retro Diffusion), face is hand-drawn and composited, because a face does not
survive the generator. Regenerate previews with `python3 art/tools/preview.py` and look in
`art/preview/`. Read the gotchas in `docs/art-pipeline.md` before generating more — three of
them cost real time to find.

**The shell and the roster are drawn.** The Bonecard `Theme` (`Scripts/UI/ui_theme.gd`)
is finished to `docs/art-direction.md` § UI; all 100 M3.7 items have sprites and icons;
the explosion is a generated animation. Contacts, blasts, coins, keys, cards and landings are
CC0 recordings under `Assets/audio/` with the synthesised voice as the fallback (D42); the chimes,
his breaths, the roar and the knockout clatter are still synthesised at boot in `AudioManager`
(D12) on purpose. **The recorded levels have not been heard by a person yet.** Turrets mirror and
aim at him and fire from an authored muzzle (D43). What is *not* drawn, as of the September 2026
assessment (`docs/assessment-2026-09.md`): the walk cycle and the five animation families,
the fist icon (still the prototype render), sprites for five of the six hands-on kind
items added in M3.8 (on placeholder silhouettes; the soft brush has a plotted icon),
muzzle/beam/bolt art for cursor powers and turrets, the grime overlay (still a tint on
the puppet), and squash/stretch on the buddy.

**Item scale is enforced by a table**, not by eye: `docs/art-direction.md` anchors every item
on Bonehead's 63 px body and `art/tools/item_postprocess.py` resizes each sprite to its entry.
The prototype sprites were all drawn to fill their cell, which is how a hand grenade ended up
87% of his height. Regenerate scenes with `tools/seed_bodies.tscn`, `seed_friendly.tscn` and
`seed_m3_content.tscn`; wire icons with `tools/wire_icons.tscn`.

**The layout code is production and stays** (docs/decisions.md D13) — every shop tile, augment
row and contract card is generated from `ItemDB`. Only the look is placeholder.

`buddy.tscn` has **not** been opened in the editor since M3, so `MoodComponent`,
`GrimeComponent`, `BuddyArt` and `ExpressionBrain` are `@export` slots that `buddy.gd` fills in
at `_ready()` when the scene leaves them null. That is a tooling accommodation, not a design —
the art pass opens the scene and should author them properly.

**The buddy has a mind** (`Scripts/Buddy/expression_brain.gd`, docs/plan-expressive-buddy.md,
D36). Every reaction is a row in `ExpressionBrain.ROWS` — face, body tag, code motion, duration,
priority, Focus gate — arbitrated in one slot; **beats are not states**, and nothing in the brain
may call `_set_state`. Every `connect()` on the character lives in the brain's `_ready` and
`loop_check`'s `expression` suite asserts each by name, so a new trigger is a row plus a connect
there, never a `connect` somewhere else. All code motion is an accumulator folded into
`BuddyArt`'s one body write and one face write — a `Tween` on `body.position` or `body.scale` is
overwritten a frame later. At Focus Off he reacts as face and tag only, with zero amplitude, and
initiates nothing. The brain has no `_process`: one re-armed `Timer` and a `_clock_skew` the
suites advance instead of winding timestamps back past zero. F3 prints his beat, arousal,
attention and away clock. **Personality is on the surface too**: six tell fields on
`PersonalityData` (hurt face, celebration face, face swaps, amplitude, fidget period, early
flinch) that touch no number (D19); edit them through `tools/seed_m38_personality_tells.tscn`,
never by hand.

**An upgraded item looks upgraded** (D41, worklist §11): `Progression.juice_tier(item_id)` is 0..3 from rank or augment levels, worn by every body through `BaseDraggable.apply_juice()` — an `ItemGlow` outline, a wider trail, an aura — and read by every family's effects; anything spawning bodies outside `ItemSpawner` must call `apply_juice()` when upgrades land. **The rhythm is on the card** (D40, worklist §10): the HUD streak row drains toward the lapse, embers and a bliss sparkle ride on him, every body trails when fast, and kind items have ambient life by id in `FriendlyBase.AMBIENT`. **The world has juice** (D39, worklist §9): `WorldFX` is one GPU pool for everything physical — dust, rings, tracers, bolts, a viewport-transform shake — and every event on the desk calls it via `WorldFX.of(self)`; `ui_shots` `16-juice` catches it mid-flight. **The Arcade is rooms and the shell has particles** (D37, worklist §7): one machine on screen behind a tab strip at mini-game size, `UIMotion.sparkle` for the moments the player made happen. **The last mile is built** (worklist §5): the damage streak and kindness combo are drawn and
heard but the streak pays nothing; the Deeds tab lists every milestone with its next rung; the
HUD links to Reincarnation once a run is worth a Marrow; the welcome is a Dream Journal
(`Data/dreams.txt`) with a small timed buff; the offline cap is sold on the Reincarnation page.
Streak, buff and cap prices are `BalanceData` knobs. The wardrobe (`CosmeticData`, worklist §6) tints the
bone and headphone masks of the same shader; a Jobs badge, a best streak, a per-round score and a
session receipt round out the hooks.
