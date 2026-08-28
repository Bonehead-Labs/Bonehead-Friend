# Overlay Technology

Everything about living on someone else's desktop. This is the highest-risk area of the
project: it's what makes the game special, and it's what the genre's negative reviews are
almost entirely about.

## Implementation (M1)

| Piece | Where |
|---|---|
| Window flags, monitor validation, FPS governor, passthrough service | `Scripts/Autoload/overlay_manager.gd` |
| Mode / corner / clamping maths (pure, unit-tested) | `Scripts/Overlay/window_layout.gd` |
| Click region construction (pure, unit-tested) | `Scripts/Overlay/passthrough_builder.gd` |
| Runtime world walls | `Scripts/Overlay/world_bounds.gd` |
| F3 readout + developer hotkeys | `Scripts/Overlay/debug_overlay.gd` |

### Two window modes (D10)

- **Fullscreen overlay** (default) — the monitor's usable rect, so the taskbar is the floor.
- **Play area** — a small window (480x360 default) snapped to a corner or placed freely.
  Minimum 320x240. Corner snapping uses a 16 px margin and survives resolution changes,
  because the corner is stored rather than the absolute position.

### Running it

**The editor's embedded game window breaks the overlay.** Godot can run the game inside its
own Game tab, and an embedded window cannot be borderless, always-on-top or click-through.
`OverlayManager` detects this, skips overlay setup and pushes a warning rather than producing
a half-broken window. To test the overlay properly, either turn off
*Editor Settings > Run > Window Placement > Embed Game Window*, use the Game tab's **Make
Floating** button, or run an exported build.

**Content must not assume a window size.** The prototype authored the buddy at `(700, 72)`
and item spawns at `(600, 100)`, both of which are outside a 480x360 play area entirely — the
buddy started beyond the right wall, fell past the floor forever, and the player saw a
correctly-working but completely empty transparent window. Spawn points are now fractions of
the viewport, `WorldBounds` pulls stranded bodies back in whenever the window changes size,
and the buddy's out-of-bounds failsafe measures against the viewport rather than a fixed
distance. Anything positioned in world coordinates has to survive a 320x240 window.

### Developer hotkeys

`F3` stats · `F4` window mode · `F5` corner · `F6` monitor · `F7` low power · `F8` overlay off.

These exist so the overlay can be exercised before the real Settings UI lands in M4.

## Requirements

The window must be **transparent, borderless, always-on-top, click-through where the game
isn't, cheap, and well-behaved across monitors**. Prototype status: the transparency project
settings are correct, and *nothing else is implemented*. `Main.gd` contained 199 lines of
window-management code whose entry point was commented out; it is deleted in M0.

## Window setup

```gdscript
# OverlayManager._apply_window_flags()
var win := get_window()
win.transparent = true                                    # + per_pixel_transparency/allowed
DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
var usable := DisplayServer.screen_get_usable_rect(Settings.monitor_id)
DisplayServer.window_set_position(usable.position)
DisplayServer.window_set_size(usable.size)
```

Notes:
- `screen_get_usable_rect()` excludes the taskbar. Using it makes the **taskbar the floor**,
  which the design leans on (taskbar impacts, "Taskbar Piledriver" augment). An option to
  cover the taskbar instead should exist for players who want the whole screen.
- **Do not** set `WINDOW_FLAG_NO_FOCUS` — the game needs focus for its own UI panels.
- Project settings must change from the prototype's: `stretch/mode = "disabled"` (currently
  `viewport`/`expand`, which distorts input and physics mapping when the window is sized to an
  arbitrary monitor rect), and world bounds must be **generated at runtime** from the usable
  rect rather than the prototype's four hand-placed colliders around a 1280×720 box.
- Hiding from the taskbar has no direct Godot API on Windows. M1 spike item: test whether a
  borderless popup-style window achieves it; otherwise accept taskbar presence for 1.0 and
  provide the tray icon regardless.

## Click-through — REMOVED, deferred

**There is currently no click-through.** The window is transparent so you see through it,
but it takes every click inside its rect like a normal window. This was removed at the
user's request after two implementations failed.

**Do not reach for `window_set_mouse_passthrough(polygon)`.** On Windows it is implemented
as a window REGION, and a window region clips what the window *draws*, not just what it
receives clicks from. The consequences, all observed:

- The visible shape of the window followed the buddy's bounding box, so parts of him were
  sliced off as he moved.
- An empty region — which `PassthroughBuilder.nothing()` returned whenever no interactive
  node was found — blanked the window entirely.
- Region complexity cost frame time: rectangle free, 8-vertex hull 3x, 16-vertex 6.5x.

The viable approach is the all-or-nothing `WINDOW_FLAG_MOUSE_PASSTHROUGH`, toggled from the
OS cursor position (`DisplayServer.mouse_get_position()`, because `get_global_mouse_position()`
stops updating once the window is passing input through). Point-test it against the same
interaction rects the `interactive` group already provides. That does not clip rendering.

Whoever builds it: **verify it visually against a real running window before claiming it
works.** Frame counters and viewport sizes looked healthy through every one of the failures
above.

## Performance

**This is the genre's number-one complaint and the budget is a release gate.**

The closest comparable shipped with Desktop Window Manager CPU spiking to ~20% (occasionally
driving the machine to 100%), massively amplified on high-resolution monitors. A transparent,
always-on-top window is composited by DWM every single frame, so cost scales with window area,
not with how much is drawn.

**Budget: < 3% CPU idle, < 8% under heavy load, measured on an exported build.**

Mitigations, all shipped in v0.1 rather than retrofitted:

| Lever | Detail |
|---|---|
| VSync | **On.** The prototype ships with `vsync_mode=0`. Reported to cut CPU 2–3× in the comparable title. |
| Physics tick | 120 → **60**. The prototype's 120 Hz doubles physics cost for no visible gain. |
| FPS governor | 30 FPS idle, 60 while interacting/UI open. `Engine.max_fps` via `OverlayManager`. |
| Low Power Mode | Explicit user toggle in Settings: caps at 20 FPS, halves particles, disables non-essential animation. Ship it and *name* it — it gets quoted in reviews. |
| Idle redraw | Investigate `low_processor_usage_mode` for the fully-idle case. |
| Occlusion hibernate | When covered by a fullscreen app, stop rendering and switch to offline accrual. |
| Window area | If 4K measurements are bad, fall back to a smaller "play area" window instead of full-screen. |

### M1 measurement: the passthrough region must be a RECTANGLE (2026-08-28)

An earlier revision of this document claimed fullscreen overlay was inherently expensive and
suggested making play-area the shipped default. **That was wrong, and it was caused by a bug
in our own code.** The finding is recorded here because the wrong version was acted on.

The real cause: `PassthroughBuilder` built a convex hull. Measured at 2560x1378, uncapped:

| Passthrough region | FPS |
|---|---|
| No region | 3624 |
| **4-vertex rectangle** | **3635** — free |
| 8-vertex convex hull | 1253 |
| 16-vertex polygon | 553 |

A rectangular window region composites on a fast path; any non-rectangular polygon forces a
slow one, and the cost grows with vertex count. With the hull replaced by a bounding box,
fullscreen went from ~20 fps to **3598 fps uncapped** — a 180x improvement. Play area is
3946 fps. Both modes now sit comfortably at their frame cap.

Ruled out by direct measurement along the way, so nobody needs to re-investigate them:
per-pixel transparency (19.8 vs 19.6 fps with it off at creation), window area on its own
(a plain 2560x1378 window runs at 3591 fps), the borderless and always-on-top flags (all
~3600 fps), the renderer (`gl_compatibility`, `forward_plus` and `mobile` all identical),
and passthrough call *frequency* (free at 60 Hz with a rectangle).

**Rule: never hand `window_set_mouse_passthrough()` a non-rectangular polygon.**

A second bug found alongside — the "everything bouncing on the spot" report.

**Create the window borderless; do not flip the flag at runtime.** Turning `BORDERLESS` on
after the window exists leaves its outer size ~2 px larger than its client area. Every
passthrough call then makes Windows re-report the outer size, and the viewport flips between
the two values — measured at 159 of 165 frames, shifting the entire scene, UI included, by
two pixels every single frame.

```ini
[display]
window/size/borderless=true
window/size/always_on_top=true
window/size/transparent=true
window/per_pixel_transparency/allowed=true
```

With the window created that way, viewport flips drop from 58 to **0** in both window modes
and the window size matches the viewport exactly. `OverlayManager` now only sets those flags
if something has cleared them, and keeps `_reconcile_client_size()` as a deferred safety net
for the case where a mismatch appears anyway.

Trying to correct the mismatch at runtime instead does not hold — that was attempted first
and the oscillation came back.

**Measurement method:** Windows Task Manager and PresentMon against an **exported build** —
editor numbers are meaningless. Record baselines in this doc at each milestone gate; a
regression is a failed gate.

### Fullscreen occlusion

Godot has no occlusion API. Exclusive-fullscreen apps take exclusive GPU control and will cover
the overlay regardless of always-on-top. Don't fight it:

- **v1 heuristic:** on focus loss plus a period of no input, enter hibernate — stop rendering,
  accrue offline income at the reduced rate. Turn the technical necessity into the "hazard pay"
  mechanic from the design doc.
- **Proper detection** needs Win32 and joins the same GDExtension spike as OS-window colliders.

## Multi-monitor

The comparable title's specific reported failures, which are our regression tests: window opens
on the wrong monitor; zoom/scale corrupts after sleep/wake; the monitor-select dropdown loses
its options.

- Persist `monitor_id` **and** the expected rect in `settings.cfg`.
- On boot and on every `DisplayServer` configuration change, **revalidate**: if the saved
  monitor is gone or its rect changed, fall back to primary and re-apply.
- Handle DPI per monitor — a window dragged from 100% to 150% scaling must re-derive its size.
- Provide "Move to next monitor" in the tray menu and a hotkey.
- Test sleep/wake and monitor unplug **while running**, every milestone.

## System tray

`StatusIndicator` (Godot 4.2+) with menu items: Show/Hide, Pause Buddy, Settings, Quit. It's the
always-available escape hatch when the window is click-through and possibly hidden. Lightly used
API — verify icon rendering and left/right-click behaviour on Windows 10 and 11 during M1.
Fallback if it disappoints: keep taskbar presence and rely on the Esc menu.

## Streamer mode

Transparent borderless windows are captured reliably by OBS's "Capture specific window", not by
"Capture any fullscreen application", and third-party overlays (Discord, GeForce, Game Bar)
conflict with OBS hooks. Ship an explicit **Streamer Mode**: solid or chroma-key background
colour, a stable and documented window title that's easy to find in OBS's source list, and a
note in the settings panel explaining which capture method to use.

Worth knowing: in the comparable title most streams were categorised as "Just Chatting" because
the streamer was working with the game on screen, making discovery attribution invisible. A
subtle branded corner watermark (toggleable) is cheap insurance.

## Rendering

**Stay on GL Compatibility.** The game is 2D-only, GL Compatibility has lower idle GPU cost, and
it has the better track record with transparent windows. Revisit only if a shader requirement
appears that it can't serve.

## Salvaged from the deleted prototype `Main.gd`

Worth keeping as reference, since the code is being removed:

- Ultrawide detection compared the aspect ratio against 21:9, 32:9, 18:9 and 43:18 with a 0.1
  tolerance. If a "fit to a slice of an ultrawide" layout is ever offered, that list is the
  starting point.
- macOS Retina handling used `DisplayServer.screen_get_scale()` and sized the window to the
  *physical* pixel size. Irrelevant for the Windows-first release, relevant if macOS is ever
  attempted — and transparent-window behaviour differs enough per platform that macOS should be
  treated as a separate project, not a checkbox.
- `DisplayServer.screen_get_scale()` is the DPI hook to use for per-monitor scaling work.

## Open spikes

| Spike | Milestone | Question |
|---|---|---|
| DWM CPU | M1 | What does a full-screen transparent always-on-top window actually cost at 1080p and 4K? |
| Passthrough perf | M1 | Vertex budget and rebuild cost for the hull-union approach |
| Taskbar hiding | M1 | Achievable in pure Godot on Windows, or accept it for 1.0? |
| `StatusIndicator` | M1 | Does the tray menu behave on Win10/11? |
| Win32 GDExtension | post-M3 | `EnumWindows` for window colliders, real occlusion detection. GDExtension vs C# vs helper process — GDExtension preferred, since the same work unlocks the flagship post-launch feature |
