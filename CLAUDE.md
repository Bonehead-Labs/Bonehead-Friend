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
- **Some sessions run on Windows in Git Bash instead of WSL.** Then Godot is
  `"/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"`,
  `--path` takes `"$(cygpath -w "$PWD")"`, and Pillow exists **only** in WSL
  (`wsl.exe -e bash -lc 'cd "/mnt/c/..." && python3 ...'`) — Windows `python`/`python3` are
  Microsoft Store stubs. Don't rewrite UTF-8 source through PowerShell 5.1's `Get-Content` /
  `WriteAllText`: without a BOM it reads them as ANSI and mangles `·` and `—`.
- **The owner games on the same PC.** Any windowed Godot run (`ui_shots`, `window_check`,
  `sandbox`, the other capture tools) steals his focus. Default to `--headless`; batch the
  windowed checks and run them when he says the machine is free.
- **Parallel worktrees need their own `user://`.** Godot keys it by project name, so two
  checkouts running a suite at once share a save slot and a settings file. Put a (gitignored)
  `override.cfg` in each worktree with `config/use_custom_user_dir=true` and a distinct
  `config/custom_user_dir_name`. Keep worktrees under `.claude/worktrees/` (`.claude/.gdignore`
  stops the main project scanning them) and cut them from the working branch by hand — the
  Agent tool's own worktree option branched from the ancient `origin/main`. Kill a stray Godot
  by PID, never `taskkill /IM`, which kills every other worktree's run too.

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
- **The shell is scaled per CanvasLayer** (D23, `UIScale`) — by a whole number when the game
  chooses, and in quarter steps when the player pins one (D50); auto never picks a fraction,
  because a resampled pixel face is a cost only the player may opt into. Because of that,
  `get_global_rect()` on any shell Control is in canvas space and wrong by the scale factor:
  anything comparing a control to a mouse position uses `UIScale.screen_centre` /
  `screen_rect`. Each layer's root Control is sized explicitly rather than anchored full-rect.
- **No rounded corners, anywhere.** `StyleBoxFlat` anti-aliases only when a corner has a
  radius, so a radius is the one way to get a soft edge in this shell — and at the owner's own
  1.25x Menu size that is what read as "rounded boxes" (D58). loop_check fails any rounded box
  in the Theme. What 1.25x still costs is unevenness: a 3px rule renders as 3 or 4 screen px.
- **Arcade rooms are `Cabinet`s** (D58): marquee, stage, paytable strip, deck, one frame with
  rules between sections. A new machine picks an accent from `UIStyle.MARQUEES`; one drawn at a
  fixed size implements `_fit_stage(width)`. `_key_pressed` has 4px more content margin than
  `_key`, so a key's `custom_minimum_size` must cover the *pressed* height (44 at LABEL) or
  pressing it grows the key and its whole row.
- **`UIMotion.rise` fades, so it is for rows on a card only.** A card sitting straight on the
  transparent window *unrolls* (scale only) — the HUD toast faded in from alpha 0 and read as a
  ghost on a dark desk (D63). **Nothing on the FX layer fades out either; it leaves by scale**
  (D68) — a half-transparent number over the chroma backdrop is a grey smear. Headless has no
  motion at all; a check about an entrance sets `UIMotion.run_in_headless` for its duration.
- **StyleBox content margins are measured from the box's outer edge; the border is inside
  them**, not stacked on it like CSS padding. Every Button state must have the same minimum
  size as `normal` — build states with `UITheme._key_states` — or a key grows when pressed,
  hovered or disabled, and its row with it (D68 found 26 such states).
- **Rules are sized for the active Menu size**: `UIStyle.rule_width()` is 3px at whole factors
  and 4px at the quarter steps between, so a rule lands on whole screen pixels at 1.25x (D68).
  Size or draw a rule with it and re-read it on `theme_changed`, never `BORDER_WIDTH`. A strip of
  equal keys fits its captions with `UIStyle.fit_captions` (icon first, then icon-only with the
  word as a tooltip); `ui_check`'s "menu sizes" suite is the multi-scale check.
- **Floating text goes through `FXLayer.spawn_number`'s placement** (D63): each line reserves
  the space its whole rise passes through, so concurrent texts never overlap. Never position a
  world label directly; give a headline `RANK_HEADLINE`, and a key if a newer one should
  replace it.
- **An item's `controls` line is the how-to** (D57): shown in the shop's detail pane and taught
  once by toast when the item first lands. Every item with a non-default gesture fills it.

Two capture tools exist because the shell cannot be reviewed from source:

```bash
# The nine screens, as PNGs in user://ui_shots (NOT --headless: it has to draw)
"$GODOT" --path "$PROJ" res://tools/ui_shots.tscn

# Motion, as frame sequences in user://ui_motion. --fixed-fps is mandatory: without it each
# frame's delta is however long the previous PNG took to write.
"$GODOT" --fixed-fps 60 --path "$PROJ" res://tools/ui_motion_shots.tscn

# ui_shots also shoots the Arcade at 1.25x (the owner's Menu size) and 2x every run;
# `-- --arcade` shoots only the Arcade, at 1x, 1.25x, 2x and in the 640x480 play area.
# The fidget toys on the desk and the shop's how-to strip:
"$GODOT" --fixed-fps 60 --path "$PROJ" res://tools/fidget_shots.tscn
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

# Every item in ItemDB, alone on a desk of its own, used the way a player uses it (D59):
# its currency through the real pipeline, its contract event, its effect, binning, teardown,
# every augment key read by something. ~6.5 min for the roster. Drivers are picked by exact
# script class and a class with no driver fails by name. Open findings live in its KNOWN
# table (docs/item-audit-2026-09.md); a known finding that stops reproducing fails the suite,
# so delete its lines when you fix it.
"$GODOT" --headless --path "$PROJ" res://tests/integration/item_check.tscn
"$GODOT" --headless --path "$PROJ" res://tests/integration/item_check.tscn -- --only=fist,grenade --trace

# The held guns (D56), the fidget toys (D57, D66) and the verbs on everyday things (D67),
# against real physics and real input
"$GODOT" --headless --path "$PROJ" res://tests/integration/gun_check.tscn
"$GODOT" --headless --path "$PROJ" res://tests/integration/fidget_check.tscn
"$GODOT" --headless --path "$PROJ" res://tests/integration/toys2_check.tscn
"$GODOT" --headless --path "$PROJ" res://tests/integration/verbs_check.tscn

# Every held ability — the 35 melee weapons' (D74) and eleven more on toys, care, food and
# charges (D78) — and the cursor powers (D72): each driven with real input and measured. A new ability of an existing archetype is driven automatically; a hook of one brings
# `_drive_<ability id>` or `_drive_<item id>`, and a new archetype fails by name until it has one.
"$GODOT" --headless --path "$PROJ" res://tests/integration/ability_check.tscn
"$GODOT" --headless --path "$PROJ" res://tests/integration/powers_check.tscn

# Every behaviour of his, each on a desk of its own (D60): every ExpressionBrain row caught
# live off its real signal, every routine toy, movement, knockout, mood, grime, the
# personalities, the critters and the turrets. ~6.5 min; `-- --quick` does one toy per routine,
# `-- --only idle.toys` one section. Run it before touching Scripts/Buddy, npc_* or turret_base.
"$GODOT" --headless --path "$PROJ" res://tests/integration/brain_check.tscn

# Seeders rewrite single items with `-- --only id,id` (never `--force`, which churns every
# scene's unique ids and reverts later hand-tuned data): seed_m3_content, seed_m36_explosives,
# seed_m36_melee_blades, seed_m36_melee_blunt, seed_m36_turrets, and seed_m35_trees, which also
# takes node ids to re-seed one augment node. seed_bodies and seed_friendly have no flag: delete
# the one scene and re-run them, since they write only what is missing (D62). A new augment effect key is three edits — the seeder's EFFECT table,
# `AugmentPanel.EFFECT_WORDS` (loop_check fails a key with no words) and a verdict in
# item_check's `_judge_augments`. A verb on an everyday thing is a row in `tools/verb_table.gd`
# (D67): rebuild the scene through its seeder, then run `tools/seed_m310_verbs.tscn`;
# verbs_check fails if a scene and its row disagree.

# Author a weapon's physics row against its sprite (D61): coverage, overhang, grip and axis per
# body, overlays in user://collider_audit; then re-seed only that scene with `-- --only <id>` on
# its seeder, never `--force`. swing_rig sweeps the real drag joint through him before and
# after a physics change — compare its momentum column, not the billed hits.
"$GODOT" --headless --path "$PROJ" res://tools/collider_report.tscn -- --tables --only katana
"$GODOT" --headless --path "$PROJ" res://tools/swing_rig.tscn

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
  It happened again at a merge: eighteen synthesised voices were registered after a `return` in
  `AudioManager` and never played (D78); loop_check now fails any voice id nobody registered. Read
  the tail of a function a merge touched. Build UI nodes with an explicit `name`, too: `FXLayer.new()` came out as `@CanvasLayer@24`,
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
- **A test must point `Settings.config_path` at its own file, on its first line** (D51).
  Restoring at the end is not enough on its own: a timeout, a parse error, or a Ctrl-C skips
  it, and one killed run left Focus Mode Off in the owner's real settings — which silences the
  FX layer, so it presented as "the payout numbers have stopped working". The door is wider
  than the tools that obviously write: a one-off hint marks itself seen and calls
  `save_settings()`, so any run that puts an item on the desk writes the file.
  `_use_capture_slot()` does the redirect for the five capture tools at once.
- **A test that reads `Settings` must also pin what it reads and restore what it writes.** `ui_check`
  clicks a real Focus Mode button, whose handler calls `save_settings()` and serialises *every*
  field — so a run used to leave the developer's own Menu size wherever the test put it, and every
  screenshot taken afterwards was silently at the wrong scale. Capture on the first line of
  `_ready()`, before anything is stomped, and `save_settings()` again before quitting.
- **A headless viewport is 64x64**, not the project's 1280x720. Anything derived from the
  window size — `WorldBounds`, the trash bin anchor, the buddy's out-of-bounds rescue — is
  meaningless in a headless run, and a generated floor ends up inside the buddy rather than
  under him. Headless physics tests must supply their own geometry.
- **Never write a body's velocity back unconditionally.** `linear_velocity` reads a copy from
  the last step; assigning it erases every impulse applied since. D54's drag backstop did that
  every frame, so a held revolver's first recoil measured exactly 0° and a blast could not knock
  a held bat (fixed in D56: write only when the limit is actually exceeded). Same family as the
  fist that erased its own punch.
- **Contacts are reported a step late, and not always.** `get_contact_impulse()` carries the
  *previous* step's impulse, only if Godot re-matched the contact within 1 px on both bodies, and
  a body asleep when a step begins gets no callback for it at all. So a hit that parts in one
  step, slides, or lands on a dozing buddy reported 0 — the starter fist had never paid (item
  audit F1). **`Buddy` bills from his own momentum now** (D64's ledger: velocity read at step
  start by a `StepStart` child, the engine's report subtracted, the remainder split among
  colliders that touched him and reported nothing, capped by the mass and closing speed behind
  each). Anything else that needs the speed of an impact reads
  `get_contact_collider_velocity_at_position` — the speed before the collision was solved — as
  the trampoline does. In `body_entered` a thrown ball has already stopped: keep a decaying peak
  speed, not last frame's.
- **A field that moves him without touching him claims his impacts** (`Buddy.claim_impacts`,
  every frame it acts, D65), so the floor he is thrown into bills the vortex or the fan, not
  `world`.
- **`kindness_sustained` means both kindness to him and a generator's income.** Check that it
  lands on him before reacting as if he were being cared for (D60): one boombox anywhere on the
  desk held him in `cared_for` for the rest of the session.
- **A steering force needs a friction feed-forward on the ground and must not have one in the
  air** (D60): a velocity P-term with no `m·g·μ` never starts a heavy body (the gorilla could not
  walk), and pushing `≥ m·g` into a wall hangs a body on it by friction.
- **An override equal to the generic default is not a specific statement.** Passing the
  category's `shocked` face as an override locked out every personality's hurt face (D60).
- **A test that places a body by teleport must clear both colliders**, not just stay in reach:
  a flamethrower put down 8 px inside him was pushed over by the solver and looked like a
  collider regression (D61, amended).
- **SceneTreeTimer seconds are process time, not the wall clock.** Never check a timer callback
  against `Time.get_ticks_msec()`; count runs instead (D67 — emitters that never stopped).
- **A seed tool whose script fails to compile still writes the scene**, without that script's
  exports. Read the seeder's log for `SCRIPT ERROR`, not only "wrote". A method named
  `is_sleeping()` did it: it overrides `RigidBody2D`'s, and that warning is an error here.
- **At boot he is still falling in from his spawn point.** A suite stands him up before putting
  a toy "beside him", or the toy spawns in mid-air.
- **Python on Windows writes CRLF** unless it opens files with `newline='\n'`.
- **A canvas shader starts from `COLOR`, which is already the texture times the modulate.**
  `texture(TEXTURE, UV) * COLOR` squares every colour: his headphones drew at (8, 133, 126)
  instead of the palette's (46, 184, 179) and every upgraded item drew darker than a new one,
  until D75. `COLOR.a` likewise already carries the texture's alpha. A canvas shader also cannot
  pass `TEXTURE` to a function — sample it inline.
- **While the idle brain drives him, his toy and the world are his own play and never billed**
  (`Buddy.is_own_play`, D70): his idle bouncing minted Bones with nobody at the desk. Anything
  that moves or holds him without a hit or a pet calls `IdleBrain.notice_player()`, or a routine
  keeps steering him.
- **Ask a kind toy whether he is in it with `touches(him)`.** He passes through a soak toy while
  sitting in it, so `get_colliding_bodies()` says no. To pass him through props, clear his
  *layer* as well as his mask — two bodies collide if either one scans the other.
- **Every blast's push is capped at `ExplosionUtil.MAX_BLAST_SPEED`** (D70: a 0.3 kg prop left a
  black hole at 56,000 px/s); pass a smaller `max_speed` for a slam.
- **A hold-to-act toy ignores a `Gesture.cancelled` release** — alt-tab mid-draw used to fire the
  slingshot — and a live gesture listens in `_input` so a drag over a HUD panel keeps tracking.
- **Anything held lets go when the game loses the focus** (D70): the release goes to the other
  window. `CursorPowerBase.release_hold`, `SpellPower._hold_lost` (a release that is a cast
  cancels instead), `WeaponAbility._on_focus_lost`, `HeldGun`. D72's spells shipped without it and
  the meteor shower paid Bones at an empty desk; powers_check and ability_check each drive a
  focus-out with real presses, so a new held thing gets a line there.
- **A gap that gates a hit counts physics steps, never the wall clock** (`Buddy.cooldown_steps`).
  Steps run in bursts — two to a frame at the idle cap, more under load — so a 150 ms cooldown let
  through a different number of a sweep's contacts at 15 fps than at 30, and the cleaver measured
  17.3 or 20.7 for the same hit (D74, fixed). A suite that measures a gap on the wall clock flakes
  when other suites share the machine; slow `Engine.time_scale` or count frames instead.
- **An act is a hand's** (D76). `Economy.is_unattended(id)` is an `ItemData.is_autonomous` hit (a
  turret, an animal) or a `world` hit with no hand in the last 3 s (a knockout pauses that clock):
  it pays Bones, but no per-act Dollar and no contract or milestone count, and unattended damage
  earns automation's Dollar trickle once a tick. A toy paying him on touch goes through
  `FriendlyBase._pay_contact`, which is a trickle during his own routine; `pay_act` is always the
  hand's. A nail gun at an empty desk had been banking 20,000 Dollars an hour.
- **A held ability on anything is an `AbilityTable` row** (D78): `BaseDraggable._ready` attaches it,
  not `WeaponBase`. A kind row pays with `give()` / `give_sustained()` and stays under
  `AbilityTable.KIND_CEILING` (1.5 value a second, D67's); a charge's second press is a `fuse` hook; ability_check wants a `_drive_<ability id>`.
  After re-seeding an item, re-run `seed_m311_abilities` for its controls line.
- **Anything an ability or item applies to him happens in `_physics_process`, before
  `Buddy.StepStart`** (D74). From a timer or a deferred call, D64's ledger bills it a second time.
  A hit attributed in `_integrate_forces` is dealt on his next tick: a suite waits two or three
  frames before reading it. A thrown body's contact bills only a fraction of its speed (the
  engine's CCD slows it before contact), so a throw that must pay bills its own hit through
  `take_impulse`, with a collision exception with him for the flight.
- **He weighs 3 kg.** Per-tick impulses cannot hold him against a 14 kg weapon; to hold him still,
  freeze him the way a knockout does and bill the weapon's hits yourself (D74's Blue Screen).
- **Aim a projectile along the hand's velocity, never a heavy weapon's tip velocity** — the head
  turning on the grip flings it off-line (the scythe's ghost went at the ceiling). A hanging
  blade turned by PD goes up and over (`BladeAim`), or its point jams in the desk.
- **White or bone-coloured effects on him are invisible**; use soot or the tier colour.
- **`GPUParticles2D` updates at 30 fps by default**, so a moving emitter leaves clumps — set
  `fixed_fps = 0` on anything that travels.
- **A fast rotor strobes at the 30 fps idle cap** — a three-arm spinner at 73° a frame reads as
  turning backwards. Send anything that spins fast through `RotorBlur` (D75), and judge rotors on
  `fidget_shots`' motion sheets run at `--fixed-fps 30`.
- **`instantiate() as T` can come back null and the instance lives on** — free what you instanced
  (it leaked all ten cursor powers from loop_check for a week).
- **The pacing simulator's first run hinges on the massage chair reaching rank 25 inside the
  hour-9 play window**, with little to spare (D72; 9:20 after D78's cake): any Hearts purchase in
  run one pushes the first Reincarnation back ~20 minutes. An optional fix waits on the owner on
  branch `opt/d76-first-run-headroom` (`marrow_divisor` 5e6 lands it at 8:01 whatever run one
  buys, and the kind spells drop to Care prices). When pacing fails, check the trees before the prices
  (the modelled buyer levels every cheap node); `pacing_sim -- --price id=cost` tries a price in
  memory.
- **A perf number is the minimum of `perf_measure -Repeat 3`**, read with its "everything else"
  and `idle_cap` lines (D73). One run on a busy machine is not a measurement: tonight's single
  0.89 % read double the true 0.44 % because seven agents were running suites.
- **A timed gap is read against a timestamp taken before the press**, not after the handler's
  own work has run in between.
- **`set_default_cursor_shape` pushes a synthetic mouse-motion event** back through the game, so
  call it only on a change — and GDScript has no getter, so track what you set (D57).
- **Aim his hops straight up.** Sideways against a light toy just shoves it (490 px in three
  hops, measured while building the bubble wrap).
- **An explosive's blast area masks the item layer, so it catches its own casing** at zero
  distance, where `ExplosionUtil` falls back to straight up at full force — a spent grenade
  flew off invisibly at 6,878 px/s (D59). Take the casing out of the world before the blast.
- **A turret that mirrors to face him has colliders that do not**; make it solid only where its
  picture is there in both facings (D61). Mirroring the shapes at runtime teleports them into
  whatever the turret is touching, usually him.

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

**There is a second generator and it is reachable from this session** (docs/decisions.md D45).
The Codex CLI installed on this machine has a native `imagegen` tool. Do not repeat D44's
mistake of recording that no generator is available:

```bash
art/tools/codex_imagegen.sh art/raw/<id>_cx.png "<prompt>"   # one image, fresh Codex session
python3 art/tools/keyout.py art/raw/<id>_cx.png art/raw/<id>_keyed.png --size 48
python3 art/tools/item_postprocess.py art/raw/<id>_keyed.png <id> <height>
```

It runs `gpt-5.6-luna` at low effort, about 32k tokens an image, and does **not** disturb an
interactive Codex the owner has open. It is not a Retro Diffusion replacement: **no seed** (so
the prompt is the only record — write it out in full in `art/prompts/`), no `remove_bg` (that
is what `keyout.py` is), no `return_spritesheet` and none of the `rd_advanced_animation__*`
presets. **The animation families (dance, relax, eat, catch, sleep) still want Retro Diffusion**; the walk cycle did not, it was drawn from his own frames (D62).

Prompt tail that works with this generator, and every clause earns its place: `simple bold
shapes, thick dark outline, flat solid colours, centred with generous margin, on a plain solid
magenta background, no text, no shadow, no gradient`. Without `flat solid colours` it renders
soft shading that survives neither the palette snap nor an 11-pixel reduction; without
`no shadow` the cast shadow keys out as part of the subject.

Three things that cost time to find:
- **`keyout.py --keep-all` is a judgement, not a flag to ignore.** Its despeckle keeps only the
  largest connected mass, which is right for a party popper whose confetti is genuinely
  detached and wrong for a kite, whose tail is a separate blob and half the object. It prints
  what it dropped; read that number.
- **An accent has to be a third of the subject to exist at icon size.** A one-pixel stripe
  averages away in the reduction. This is the same lesson `items.md` records for the minigun.
- **`ImageChops.difference(a, b).getbbox()` on RGBA reads only alpha**, so a colour-only edit
  comes back as "no change". Compare pixel data when verifying an art change.

**Item art can also be drawn by hand, and the grid is the record** (D62). `art/pixel/<id>.txt`
is a text grid, one character per colour of the locked palette, with named parts for pieces
that move; `python3 art/tools/pixel_sprite.py art/pixel/<id>.txt` writes the sprite and a 6x
preview under `art/preview/pixel/`, and `--sheet <out.png> <ids…>` lays sprites against the
roster. Look at every preview before committing. Every M3.9 item (the guns, the fidget toys) and
fourteen redraws were made this way, and the walk cycle was drawn from his own body frames
(`art/tools/make_walk.py`) rather than waiting for a generator. Icons: `art/tools/pixel_icon.py`
for hand-drawn items (whole-number steps only); `make_icons.py` for the rest (a whole step when
it keeps 80% of the exact fit, otherwise the exact fit with majority-colour sampling so outlines
survive). If a redraw changes an item's size, delete that one scene and re-run its seeder with
`-- --only <id>`, never `--force`. `art/raw/` is gitignored: before `_build_body.lua`, export
every tag from `bonehead.aseprite` (`-b --tag <t> --sheet art\raw\body_<t>.png`), and append new
tags last. Aseprite is at `C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe`
and runs headless with `--batch`; nobody needs to open it.

## Current state

**M3.9, the toybox (branch `m3.9-toybox`, 2026-09-25).** Guns you hold (D56: `HeldGun` — left
carries, right fires, a torque controller aims it at him with weight, recoil kicks it off and it
settles back; five harm guns on a sixth harm tab, a water pistol and a bubble blaster on the kind
side; he cowers when one is aimed). Fidget toys (D57: `GestureZones` — zones in art pixels and a
gesture vocabulary per button, one input grammar for everything held: **left carries, right while
holding is the item's action, right on a zone is the zone's action, Shift+right bins**; bubble
wrap, fidget spinner, jack-in-the-box, fortune ball, stress ball, each of which he uses himself).
The Arcade rebuilt as cabinets (D58). Every item tested alone (D59, `item_check`) and every
multi-collider weapon re-authored against its art (D61). Fourteen sprites redrawn, a walk cycle
and headphones that fall (D62). Floating text that never overlaps (D63). The item audit's open
findings are in `docs/item-audit-2026-09.md` — read it before touching the damage model.

Then, overnight (D64–D75): hits the engine never reports are billed from his own momentum (D64 —
the starter fist had never paid); augments that did nothing now do (D65); five more toys and
thirteen everyday things with a right-button verb (D66, D67); the shell at 1.25x and 2x (D68);
**every gun is a gun you hold** — the pistol, shotgun and minigun kept their ids and left the
Cursor tab, sixteen guns in all (D71); **the Cursor tab is supernatural** — telekinesis, time stop,
meteors, smite, and blessing, levitation and a rainbow on the kind side (D72); **every one of the
35 melee weapons has an ability of its own on right-while-held** — an `AbilityTable` row
(`Scripts/Bodies/Abilities/ability_table.gd`) on one of eleven archetypes, with a hook script
where the archetype is not enough, and loop_check fails a melee weapon without one (D74); and the
art draws as authored now that the shaders stopped squaring every colour (D75). Tools for looking:
`tools/{fidget_shots,ability_shots,power_shots,gun_shots,soak_shots}.tscn`, all windowed.

The day after (D76–D78): **nobody at the desk is not an act** — turrets, animals and his own play
pay Bones and Hearts as before but earn Dollars like automation and count on no board (D76); the
right button reaches **eleven held things beyond the melee drawer** — a curveball, a serve, a
strike, keepy-uppy, a tickle, a swaddle, a wring, a wish on the cake, a donut toss, an airburst and
a sticky bomb on a remote — with a design sheet of the other 59 in D78 (eight marked next; a
turret Overdrive waits on the owner, since right on a placed turret bins it today). D77, a
readable effect for every ability (ready glint, callout, state on him, payoff), was in flight.

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
assessment (`docs/assessment-2026-09.md`): the five animation families and squash/stretch on
the buddy. The walk cycle exists (D62) and his headphones now fall onto the knockout heap. The five hands-on kind items and the fist icon are **generated**
(D45, Codex `imagegen`) and no longer plotted; `make_hands_on_items.py` now refuses to overwrite
them without `--force`. The soft brush is still plotted and is fine as it is. Eight items that
vanished on a dark desktop carry a bright second material as of D45, and the generator litter is
gone from `idle_sad` frames 2 and 6 and `happy` frame 8. Four gun turrets are
split into base and barrel sprites cut from the existing art (`split_turret_barrels.py`);
grime is a per-texel speckle in the shared shader; muzzle flash, beam and bolt are drawn by
`WorldFX`, not art.

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

**Test helper arity differs by suite, and the failure is a parse error that hangs the run.**
`ui_check`'s `_check(name, ok, detail)` takes three arguments; `loop_check`'s and
`window_check`'s take two. Passing three to the latter two fails to parse, which means the
scene never loads, nothing prints, and the run sits there until it is killed — it looks like
a hang, not a typo. Both suites have now cost a debugging round to this.
