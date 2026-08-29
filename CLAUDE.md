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
  and one `res://Data/balance.tres` holding every global tuning knob. Systems read `ItemDB`.
  Adding an item must never require editing a script.
- **Spelling**: it is "Missile", not "Missle". The prototype misspells it in filenames, class
  names and a user-facing label; correct it as you touch each.
- **Collision layers** (named in Project Settings — never use bare numbers):
  `1 world · 2 buddy · 3 item · 4 handle · 5 pickup · 6 sensor`.
  Handles collide with nothing. Sensors are Area2D-only.
- **Autoload boot order** is load-bearing:
  `EventBus → Settings → SaveManager → ItemDB → Economy → Progression → OverlayManager → AudioManager`.

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

# Can the player actually click the UI? Synthetic mouse events at the real widget rects
"$GODOT" --headless --path "$PROJ" res://tests/integration/ui_check.tscn

# Boot smoke test — catches broken @export refs and missing scene paths
"$GODOT" --headless --path "$PROJ" --quit-after 120

# Seed res://Data (writes only files that do not exist; add `-- --force` to overwrite)
"$GODOT" --headless --path "$PROJ" res://tools/seed_data.tscn
```

`--path` takes a **Windows** path because Godot is a Windows process. Adding `--editor --quit`
opens the project in the editor headlessly, which is how to verify an addon loads.

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
the UI check before any commit touching `Scripts/UI/`.
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

M2's systems are built, clicked and verified; the playtest half of its gate is not done. See
the M2 progress note in `docs/roadmap.md` for exactly what is and is not finished — it is the
handoff list, kept current.

There is **no settings menu**: Esc is Resume / Save now / Save and quit, and the window and
Focus Mode knobs are F3-overlay dev hotkeys until the M4 settings UI.

`Scripts/Globals/` is gone — the production layout is `Scripts/{Autoload,Bodies,Buddy,Combat,
Components,Data,Economy,Overlay,Progression,Save,UI,World}`. Remaining prototype surface worth
knowing about: the item scenes under `Scenes/Bodies/` still carry their prototype node names
(`_grenadeSprite`, `_handle`) and `Scenes/Bodies/base_body.tscn` is still the bat/mace base.

There is **no art and no `Theme`**. `Scripts/UI/ui_style.gd` is the single placeholder styling
file the art pass replaces; impact sounds are synthesised at boot in `AudioManager` rather than
loaded (docs/decisions.md D12).
