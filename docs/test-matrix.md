# Test Strategy

Two halves: the maths is automated, the overlay is manual. Neither substitutes for the other.

## Automated

A plain GDScript test runner — no framework. GUT is overhead a solo dev doesn't need for what
is mostly pure-function testing.

```bash
GODOT="/mnt/c/Users/George/Godot Projects/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
PROJ='C:\Users\George\Godot Projects\Projects\Bonehead_Friend\interactive-buddy-2'
"$GODOT" --headless --path "$PROJ" -s tests/run_tests.gd   # asserts, non-zero exit on failure
"$GODOT" --headless --path "$PROJ" --quit-after 120        # boot smoke test
```

(The doubled path segment is real — the release zip was extracted into a folder named like the
exe. `--path` must be a Windows path; Godot is a Windows process.)

**Run before any commit touching `Economy`, `Progression` or `SaveManager`.**

Coverage — these are pure functions with no excuse for being wrong:

- Augment cost curve `cost_base × growth^n`; bulk-buy closed form; max-affordable inverse.
  (Bulk-buy maths is the classic silent bug: the "Buy ×10" button quietly overcharges.)
- Mastery XP thresholds and rank boundaries; pool checkpoints.
- Prestige: `cbrt(lifetime / 1e12)`, gain-on-reset never negative, multiplier composition.
- Payout pipeline multiplier order and mood curve sampling at the extremes and at zero.
- Offline earnings: cap clamping, **negative elapsed clamped to zero** (clock changes and
  cloud-sync skew), efficiency factor.
- Save round-trip: every autoload's `to_save()` → `from_save()` preserves state exactly.
- **Every migration step**, against a committed fixture save of each prior version in
  `tests/fixtures/`. A schema change without a fixture is not finished.
- Corrupt-save recovery: truncated JSON falls back to `.bak`.

The boot smoke test exists to catch broken `@export` references and missing scene paths after
scene edits — the failure mode that produced the original export bug.

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
- **M3:** a 30-minute session with no dead ends. Log payouts and purchases to CSV in debug
  builds and check that nothing is ever more than ~5 minutes from the next affordable thing.
- **M4:** two machines, one of them 4K, full matrix, plus someone who has never seen the game
  finding the Settings panel unaided.
