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

## Click-through

`WINDOW_FLAG_MOUSE_PASSTHROUGH` is all-or-nothing and therefore useless here. The working
approach is a **passthrough polygon**:

```gdscript
DisplayServer.window_set_mouse_passthrough(polygon: PackedVector2Array)
```

Clicks *inside* the polygon hit the game; everything outside falls through to whatever app is
underneath. The polygon must cover the buddy, every spawned item, and any open UI panel.

Implementation rules, all of them performance-driven:

- Rebuild at **10–15 Hz**, never per physics tick (physics runs at 60; a per-tick rebuild of a
  many-vertex polygon is pure waste).
- Rebuild only when `EventBus.interactive_shapes_dirty` fires, or on a slow timer — not
  unconditionally.
- Use **coarse convex hulls** per interactive node, not per-pixel silhouette tracing. A capsule
  around the buddy plus a box per item is plenty.
- Pad hulls generously (~8 px). A player who misses the grab because the polygon hugged the
  sprite too tightly will file it as "the game ignores my clicks".
- Cap total vertices (~64). Fallback if the union gets expensive: bounding-box union.
- When any UI panel is open, the polygon is just the panel rect(s) — no need to union the world.

**Known limitation, accepted for now:** `window_set_mouse_passthrough()` accepts exactly ONE
polygon, so genuinely disjoint regions cannot be expressed. `PassthroughBuilder` takes the
convex hull of everything interactive, which over-includes the empty space between scattered
items. Play-area mode makes this largely irrelevant — a small window has little area to get
wrong. If fullscreen mode needs true per-region masking, the options are a bridged polygon
(risky: Windows fills regions with the even-odd rule, so zero-width bridges may cancel) or a
real Win32 region via the same GDExtension that would unlock window colliders.

Two cases short-circuit the hull and make the whole window clickable, both deliberate:
a UI panel being open, and a cursor power being armed — when you are aiming a gun at the
desktop, every pixel is a valid target.

Edge case to test explicitly: dragging the buddy *to the very edge* of the screen, and
clicking in the gap between two nearly-touching hulls.

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

### ⚠️ M1 measurement: fullscreen overlay is expensive (2026-08-28)

Measured on this machine (RTX 4080 SUPER, 2560x1440 @ 60 Hz secondary), uncapped with VSync
off, on a nearly-empty scene — 91 nodes, one active body:

| Configuration | FPS |
|---|---|
| Overlay off, 1280x720 | **~3660** |
| Overlay on, play area 480x360 (transparent, borderless, always-on-top) | **~4140** |
| Overlay on, fullscreen 2560x1380 | **~20–58** (run to run) |

**The overlay flags are free. The cost scales with transparent window AREA.** Ruled out by
direct measurement, so don't re-investigate these:

- *Not transparency* — fullscreen with `transparent = false` performs the same (55 vs 57 fps).
- *Not the renderer* — `gl_compatibility`, `forward_plus` and `mobile` all land at ~20 fps
  fullscreen, so D5's choice is not the problem.
- *Not the passthrough polygon* — `window_set_mouse_passthrough()` costs ~1.3 ms per call and
  only runs at 12 Hz, and is now skipped entirely when the region is unchanged.
- *Not physics* — physics time is 0.13 ms.

This is the DWM compositing cost the genre research predicted, arriving exactly where it was
predicted: large always-on-top windows on a high-resolution display. Fullscreen mode is
therefore playable only because of the frame cap (30 idle / 60 active); it has little headroom
above that, and a 4K display will be worse.

**Consequences to decide before M4:** either make play-area the shipped default, restrict
fullscreen to a "performance mode" with a hard 30 fps cap and a warning, or find a cheaper
presentation path. Play-area mode is unaffected and comfortably exceeds the budget.

**Fixed alongside:** Windows returns a client area up to 2 px smaller than the requested
window size, and Godot then reported a window/viewport mismatch roughly 80 times a second.
`OverlayManager._reconcile_client_size()` corrects the window once so the storm stops.

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
