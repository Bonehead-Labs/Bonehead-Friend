# Test Strategy

Two halves: the maths is automated, the overlay is manual. Neither substitutes for the other.

## Automated

A plain GDScript test runner — no framework. GUT is overhead a solo dev doesn't need for what
is mostly pure-function testing.

```bash
GODOT="/mnt/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
PROJ='C:\Users\George\Godot Projects\Projects\bonehead-friend'
"$GODOT" --headless --path "$PROJ" -s tests/run_tests.gd   # pure-function asserts
"$GODOT" --headless --path "$PROJ" res://tests/integration/loop_check.tscn  # the whole loop
"$GODOT" --headless --path "$PROJ" res://tests/integration/ui_check.tscn    # can you click it
"$GODOT" --headless --path "$PROJ" --quit-after 120        # boot smoke test
```

All three test runs exit non-zero on failure.

(The doubled path segment is real — the release zip was extracted into a folder named like the
exe. `--path` must be a Windows path; Godot is a Windows process.)

**Run before any commit touching `Economy`, `Progression` or `SaveManager`.**

Coverage — these are pure functions with no excuse for being wrong:

- Augment cost curve `cost_base × growth^n`; bulk-buy closed form; max-affordable inverse.
  (Bulk-buy maths is the classic silent bug: the "Buy ×10" button quietly overcharges.)
- Mastery XP thresholds and rank boundaries; pool checkpoints.
- Prestige: `cbrt(lifetime / 1e12)`, gain-on-reset never negative, multiplier composition.
- Payout pipeline multiplier order and mood curve sampling at the extremes and at zero.
- Mood: decay toward zero without overshooting, both rails, the soft-rail asymmetry (deeper is
  harder, crossing back is full strength), and root-scaled kindness.
- Mastery: that `rank_for_xp` really is the inverse of `xp_to_rank` at every unlock threshold
  and one thousandth below it, that it is bounded against a corrupted save, and that the pool's
  checkpoints compound in both directions.
- Grime: penalty bounds, and that it can never zero out Bones income however it is tuned —
  there is no fail state, so grime must always be a cost and never a wall.
- Offline earnings: cap clamping, **negative elapsed clamped to zero** (clock changes and
  cloud-sync skew), efficiency factor.
- Save round-trip: every autoload's `to_save()` → `from_save()` preserves state exactly.
- **Every migration step**, against a committed fixture save of each prior version in
  `tests/fixtures/`. A schema change without a fixture is not finished.
- Corrupt-save recovery: truncated JSON falls back to `.bak`.

The boot smoke test exists to catch broken `@export` references and missing scene paths after
scene edits — the failure mode that produced the original export bug.

`loop_check` also asserts the **art wiring** against the real imported resources: every buddy
state has an animation, every expression the game can ask for exists, no one-shot loops, and
each animation's face-offset track is exactly as long as its frame count. That last one is
the important one — appending a frame in Aseprite silently stretches any tag that ends at the
last frame, which made `idle` import as 74 frames instead of 8 with no symptom other than the
buddy playing the whole file for every animation (`art-pipeline.md`). A length check against
the offsets those frames were measured from catches it on the next run.

### The loop check

`tests/integration/loop_check.tscn` is the second automated run, added in M2. It is a **scene**
rather than a `-s` script on purpose: `-s` cannot see autoload singletons, and `Economy`,
`Progression` and `ItemDB` are exactly where a regression in the payout chain would live.

It walks the M2 gate end to end — content loads, starters are owned, a hit pays Bones, an
augment makes the same hit pay more by exactly its multiplier, the shop refuses what you cannot
afford, the item limit holds, a knockout pays and resets, and the whole thing survives a save
and reload. It runs against its own save slot (`SaveManager.slot_name`) and deletes it
afterwards, so it never touches the save of whoever is running it.

The part worth keeping honest is the **contact impulse** section, which steps real physics and
asserts that a falling body produces a real `HitInfo`, that it is attributed to the right item
id, and that a body resting on him does not farm damage. Receiver-side damage (D7) is the
correction the whole combat model rests on; asserting it against the actual solver rather than a
synthetic signal is the only way to know it still works.

Two traps that cost time when writing it:

- **A headless viewport is 64x64**, not the project's 1280x720. Anything derived from the window
  size — `WorldBounds`, the trash bin anchor, the buddy's out-of-bounds rescue — is meaningless
  in a headless test. The loop check supplies its own floor instead of using `WorldBounds`.
- **Sections that never await a physics frame leave the world suspended.** Ten bats spawned by
  the item-limit section were still hanging in the air when the physics section started, and
  raining down mid-measurement knocked the buddy out. Physics phases have to clear the world
  and reset the meter first.

### The UI check

`tests/integration/ui_check.tscn` is the third automated run, added after M2's shell shipped
unclickable. The Esc menu's `CenterContainer` filled the window on the topmost `CanvasLayer`,
and on its default mouse filter it was therefore the control under **every** click in the game.
The dock, both panels and dragging the buddy all did nothing, and it drew nothing to explain
why. The screenshot audit could not see it — the pixels were correct.

So this one clicks. It loads the real `main.tscn`, pushes synthetic mouse events at the actual
on-screen rect of each widget, and asserts what came back:

- No control spans the window on any layer (the shape of the original bug).
- Each tab is the top control at its own centre, opens its page, and toggles it shut.
- **Every visible button on every page** is the control the cursor lands on. A sweep rather
  than a list, so the same class of bug is caught wherever it reappears.
- Clicking Spawn puts an item in the world.

Five suites were added after a review pass found the shell would not hold new content. Each
exists because the guard that *should* have caught a bug looked at the wrong thing:

- **`readable`** walks the **live tree** of every page and, for every visible word, resolves the
  font colour actually in effect and the fill of the box actually behind it. Grading `UIStyle`'s
  constants missed a colour overridden on one node; grading the `Theme` missed text that was
  simply absent. It also asserts each page rendered *something* — a blank page passes every
  contrast check ever written, and the Rebirth page shipped blank twice.
- **`geometry`** measures every picture against its **declared** box, not its realised one: a
  `Button` grows to fit an oversized icon, so measuring the result passes the exact bug. It also
  asserts every row in a shop category is one height, every card in a tier shares a baseline,
  and — separately — that nothing had to be *shrunk* to fit. Fitting is not enough; art has to
  fit at its own size, and a whole-number step down is a halving.
- **`closed pages`** asserts no page is left flagged visible under a shut card, and that twenty
  currency events with the card closed cost zero refreshes.
- **`hide and pin`** drives both auto-hiding halves of the shell by pushed motion: each parks
  off screen, leaves a mark that stays on screen, comes back on hover, leaves again, pins on a
  click and unpins on the next.
- **`purse`** asserts the formatter's boundaries and then checks the live card at nine digits —
  every figure's rendered text fits its line, and the card does not change width to hold them.

`tools/window_check.tscn` is the fourth run and needs a **real** `DisplayServer`. Its
`the shell fits the window` suite sweeps six play-area rungs against three UI scales and asserts
the panel column and the HUD are inside the window — the combination of the smallest play area
and a pinned 2x used to put the card, and the tabs that would have fixed it, off screen.
- The buddy's grab area still sees the cursor and a press still starts a drag — the blocker
  killed physics picking too, because the viewport marks a click handled the moment any control
  claims it, and `BaseDraggable` runs on *unhandled* input.
- The Esc menu blocks clicks while open and stops blocking when closed.

Two traps, on top of the loop check's:

- The scene runs inside a **SubViewport** at the play-area size, because a headless root
  viewport is 64x64 and every widget would be off-screen.
- **A SubViewport with no `SubViewportContainer` above it never learns the mouse is inside it**,
  and physics picking is gated on exactly that. Without a manual
  `notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)` the world silently ignores every
  synthetic click and the drag assertions fail for a reason that has nothing to do with the
  game.

GUI hit-testing is the same code path in a SubViewport as in the real window, but the window
itself is not — a real run was used to confirm the fix with `OverlayManager` actually applied.

### Visual audit

```bash
"$GODOT" --path "$PROJ" res://tools/audit_shots.tscn   # NOT headless
"$GODOT" --path "$PROJ" res://tools/audit_shots.tscn -- --screen 1 --overlay
```

Drives the game through boot, shop, tree, settings, play, a filthy-and-miserable HUD, a
blissful one, the knockout pile and the Esc menu, and writes a PNG of each to `user://audit/`.
Deliberately not headless: headless does not render and its viewport is 64x64.

It shoots at `Settings.play_area_size`, not a convenient size — a HUD that only fits in a
1280-wide capture is a HUD that does not fit. Each shot is composited onto a flat colour first,
because the window is transparent and the UI would otherwise be judged against whatever the
image viewer paints behind it. It runs against its own save slot and deletes it afterwards.

**Run it on at least two differently-shaped monitors.** `--screen N` picks the display and
`--overlay` runs the real fullscreen overlay instead of a play-area window; shots are suffixed
with the screen so two runs do not overwrite each other. The HUD and the panels anchor to
window corners that are far apart on a 3440x1440 ultrawide and much closer on a 2560x1440 16:9
panel, and a size that looks deliberate in one looks broken in the other. Three layout bugs in
M3 were found by exactly that comparison and by nothing else:

- the panel had a fixed 420 px scroll height, which overflowed a 960x640 play area and left
  900 px of empty screen under it on the overlay;
- the grime warning appeared at a penalty that rounds to "x1.00" on screen;
- the friendly shop tiles reserved no icon column, so the shop read as two misaligned lists.

Both new readouts are shot at values that actually exercise them, because **both are invisible
at their defaults** — a clean buddy shows no grime line and a neutral mood is a half-full grey
bar. That is precisely how the knockout meter's invisible track survived a whole milestone.

Overlay *behaviour* still has to be checked against a real window on a real desktop — this
catches layout and legibility, not always-on-top or click handling.

## M1 hands-on checklist

The overlay's gate cannot be automated — click-through and CPU cost need a real window over
real applications. Launch the game, then:

| Hotkey | Does |
|---|---|
| `F3` | stats readout (fps, cap, process/physics ms, node and body counts, window rect, monitor) |
| `F4` | switch fullscreen overlay ↔ play area |
| `F5` | cycle the play-area corner |
| `F6` | move to the next monitor |
| `F7` | toggle Low Power Mode |
| `F8` | turn the overlay off (normal window) — the escape hatch if anything misbehaves |

1. **Click-through.** Put a browser behind the game. Click empty space — the browser should
   receive it. Click Bonehead — the game should. Drag him to each screen edge.
2. **Both modes.** `F4` between them; `F5` around all four corners. Check the window stays on
   screen and the taskbar acts as the floor in fullscreen mode.
3. **Multi-monitor.** `F6` to move; confirm the position persists across a restart.
4. **Performance.** `F3` for in-game numbers, then Task Manager for the truth — watch
   **Desktop Window Manager**, not just the game process. Compare idle vs. ten spawned items,
   and default vs. `F7` Low Power. Record the numbers in `overlay-tech.md`.
5. **Recovery.** `F8`, sleep/wake, unplug a monitor while running.

Editor and debug-build numbers are indicative only; the budget is measured on an export.

## Manual overlay matrix

Run at the **M1, M2 and M4** gates. Overlay behaviour cannot be unit-tested; every row here
corresponds to a real complaint filed against a shipped game in this genre.

### Displays

| Case | Expect |
|---|---|
| 1080p @ 100% | Window fills usable area; taskbar is the floor |
| 4K @ 150% DPI | Correct scale, no blur, **CPU within budget** |
| Dual monitor, matched DPI | Opens on the saved monitor |
| Dual monitor, mixed DPI | Correct scale after moving between them |
| Ultrawide | Sane layout |
| Monitor unplugged while running | Falls back to primary, no crash, no off-screen window |
| Resolution changed while running | Re-derives size and bounds |
| Sleep / wake | No zoom corruption, no lost position |
| Monitor picker in Settings | Lists all monitors, switching works and persists |

### Click-through

| Case | Expect |
|---|---|
| Click empty area over a browser | Browser receives the click |
| Click the buddy | Game receives it, drag starts |
| Click a spawned item | Game receives it |
| Click with a UI panel open | Panel receives it; world does not |
| Drag the buddy to each screen edge | No lost grab, no stuck drag |
| Rapid click across the silhouette boundary | No dropped or double-handled input |
| Text selection in an app underneath | Unaffected |

### Foreground apps

| Case | Expect |
|---|---|
| Over a fullscreen browser video | Visible, still interactive |
| Over an exclusive-fullscreen game | Hibernates cleanly; offline income accrues; recovers on return |
| Over an elevated/admin window | No crash (input may be blocked by Windows — acceptable) |
| Alt-tab cycling | Window returns correctly, stays on top |
| Windows lock / unlock | Survives |

### Shell

| Case | Expect |
|---|---|
| Tray icon on Win10 and Win11 | Renders; left and right click both behave |
| Tray menu items | Show/Hide, Pause, Settings, Quit all work |
| Quit from tray while a panel is open | Saves, exits cleanly |
| Esc menu | Toggles when focused; pauses only the world |
| Streamer mode in OBS ("Capture specific window") | Captured; chroma-key background works |
| Both halves of the shell hidden (the default) | Only two small marks on screen; neither blocks a click on the desktop behind it |
| Hover a mark, then click it | Panel slides out; mark becomes a red pin; panel stays out with the cursor away |
| Pinned state after a restart | Still pinned — it is a decision, not a session mode |
| Marks over a *white* desktop and a *black* one | Visible in both (they are white with a dark halo) |

### Performance

Measured on an **exported build** with Task Manager and PresentMon — editor numbers lie.

| Scenario | Budget |
|---|---|
| Idle, nothing spawned | **< 3% CPU** |
| Idle at 4K | **< 3% CPU** |
| 10 items, active automation | **< 8% CPU** |
| Explosion cascade | No sustained spike above 15% |
| Low Power Mode | Measurably lower than default |
| 8-hour soak | No memory growth, no node leak, no audio-voice leak |

Record the numbers in `overlay-tech.md` at every gate. A regression is a failed gate, not a
known issue.

## Playtest gates

- **M2:** a non-developer plays five minutes with no instruction. Do they hit him, earn, and buy
  something without being told? If not, the first-run flow is wrong.
- **M3:** a 30-minute session with no dead ends. `TuningLog` writes the CSV automatically in
  debug builds (`user://logs/session_*.csv`) — sort by `t_sec`, find the longest stretch where
  nothing was affordable, and that gap is the tier to fix. Four questions the automated tests
  cannot answer:
  1. does the player work out on their own that the mood meter pays *at both ends*?
  2. do they repeat the knockout on purpose?
  3. do they find the Hearts half without being told, or do they only ever hit him?
  4. when they buy their first automation capstone, do they understand what they bought?
- **M4:** two machines, one of them 4K, full matrix, plus someone who has never seen the game
  finding the Settings panel unaided.
