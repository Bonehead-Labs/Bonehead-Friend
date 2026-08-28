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
  **Godot must be run as the Windows executable**, never a Linux build:
  `"/mnt/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe"`
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
GODOT="/mnt/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe"

# Economy math, save round-trips, every migration step
"$GODOT" --headless --path . -s tests/run_tests.gd

# Boot smoke test — catches broken @export refs and missing scene paths
"$GODOT" --headless --path . --quit-after 300
```

Run the test suite before any commit touching `Economy`, `Progression` or `SaveManager`.
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

The repo is mid-migration from prototype to production. `docs/roadmap.md` tracks the
milestone; anything in `Scripts/Globals/` predates the architecture in `docs/architecture.md`
and is being replaced. When you touch a prototype file, bring it up to the conventions above
rather than matching its existing style.
