extends Node

## Owns the game's relationship with the desktop: window flags, where the window sits,
## which clicks it accepts, and how much CPU it is allowed to spend.
##
## The performance budget is a release gate, not an aspiration: < 3% CPU idle, < 8% under
## load, measured on an exported build. A transparent always-on-top window is recomposited
## by the desktop compositor every frame, so cost scales with window AREA rather than with
## how much is actually drawn. That is the single most common complaint about this genre.
## See docs/overlay-tech.md.

## Interactive things register here so they can be included in the click region.
const GROUP_INTERACTIVE := &"interactive"

## Rebuild the passthrough polygon ~12x a second, not every frame. Physics runs at 60 and
## the polygon is a coarse hull; rebuilding it per tick is pure waste.
const PASSTHROUGH_HZ := 12.0

## Fallback half-extent for an interactive node that doesn't declare its own size.
const DEFAULT_INTERACTION_EXTENT := Vector2(48, 48)

signal window_rect_changed(rect: Rect2i)

var current_rect: Rect2i
var _passthrough_accumulator := 0.0
## Generous grab margin around interactive things, so a near-miss still counts.
const INTERACTION_PADDING := 12.0
var _passthrough_on := false
var _known_size := Vector2i.ZERO
## Seconds of no input before dropping back to the idle frame rate.
const INTERACTION_TIMEOUT := 2.0
var _idle_timer := 0.0
var _panel_open := false
var _cursor_power_active := false
var _interacting := false
var _applied := false

func _ready() -> void:
	# Applied deferred so the main scene's nodes exist before the first polygon build.
	call_deferred("apply_window_configuration")
	_install_debug_overlay()
	EventBus.ui_panel_changed.connect(_on_ui_panel_changed)
	EventBus.interactive_shapes_dirty.connect(_force_passthrough_rebuild)
	EventBus.cursor_power_changed.connect(_on_cursor_power_changed)
	get_tree().get_root().size_changed.connect(_on_window_size_changed)

func _process(delta: float) -> void:
	if not _applied:
		return
	# Stay at the active frame rate while anything is still moving, not just while the
	# player is touching it — a buddy falling at 30 fps looks choppy for no reason now
	# that there is plenty of headroom.
	if Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS) > 0:
		_idle_timer = 0.0
		if not _interacting:
			set_interacting(true)
	elif _interacting:
		_idle_timer += delta
		if _idle_timer >= INTERACTION_TIMEOUT:
			set_interacting(false)

## Any input means the player is engaged, so spend frames on them. Nothing else calls
## set_interacting(), which previously left the game pinned at the 30 fps idle cap forever.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		_idle_timer = 0.0
		if not _interacting:
			set_interacting(true)

# --- moving the window (D49) -----------------------------------------------

## How far the cursor must travel before a press becomes a window drag, in screen pixels.
## Without this every click on the backdrop nudges the window by a pixel or two, and a game
## about clicking things becomes a game about accidentally moving the window.
const WINDOW_DRAG_SLOP := 4.0

var _window_drag_armed := false
var _window_dragging := false
var _drag_mouse_start := Vector2i.ZERO
var _drag_window_start := Vector2i.ZERO

## Drag the background to move the window.
##
## The window is borderless, so it has no title bar and no OS grab handle: until now the
## only positions it could occupy were the four corners the game offered, and a desktop toy
## that cannot be put where its owner wants it is in the way rather than in the corner.
##
## `_unhandled_input`, so this is by definition a press nothing else wanted — not the buddy,
## not a toy, not a panel, not an armed cursor power. That one choice is what keeps this from
## fighting every other gesture in the game, and it is also why the rule is easy to say:
## drag the *background*.
##
## Screen coordinates from `DisplayServer`, not viewport coordinates, because the window
## moves out from under the cursor as it is dragged and the motion event's own position is
## then relative to a frame that is itself moving. It is the one place in this project that
## legitimately reads the OS cursor — and the reason this gesture cannot be driven by
## synthetic events, so it belongs to `docs/test-matrix.md` rather than to a suite.
func _unhandled_input(event: InputEvent) -> void:
	if not _can_move_window():
		return
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_window_drag_armed = true
			_window_dragging = false
			_drag_mouse_start = DisplayServer.mouse_get_position()
			_drag_window_start = DisplayServer.window_get_position()
		else:
			if _window_dragging:
				_commit_window_move()
			_window_drag_armed = false
			_window_dragging = false
		return
	if not _window_drag_armed or event is not InputEventMouseMotion:
		return
	var travelled := Vector2(DisplayServer.mouse_get_position() - _drag_mouse_start)
	if not _window_dragging and travelled.length() < WINDOW_DRAG_SLOP:
		return
	_window_dragging = true
	DisplayServer.window_set_position(
		_drag_window_start + Vector2i(travelled.round()))

## Whether a background drag should move the window at all.
##
## Not in fullscreen overlay: the window already covers the usable screen, so "moving" it
## only takes the game off the edge of the monitor.
func _can_move_window() -> bool:
	if not _applied or not Settings.overlay_enabled:
		return false
	if DisplayServer.get_name() == "headless" or get_window().is_embedded():
		return false
	return Settings.window_mode != WindowLayout.Mode.FULLSCREEN_OVERLAY

## Remember where it was put, once, on release rather than on every motion event.
##
## Dragging clears the corner anchor: putting the window somewhere by hand is a statement
## about where it should be, and leaving the anchor set would snap it back on the next
## apply. The four corners stay in Settings as a one-click tidy-up.
func _commit_window_move() -> void:
	var usable := DisplayServer.screen_get_usable_rect(_validated_monitor())
	var size := DisplayServer.window_get_size()
	var placed := WindowLayout.clamp_position(DisplayServer.window_get_position(), size, usable)
	DisplayServer.window_set_position(placed)

	Settings.play_area_corner = WindowLayout.Corner.FREE
	Settings.play_area_rect = Rect2i(placed, size)
	Settings.save_settings()

	current_rect = Rect2i(placed, size)
	_known_size = size
	_force_passthrough_rebuild()
	window_rect_changed.emit(current_rect)

# --- window configuration --------------------------------------------------

## Bumped on every apply so an in-flight `_reconcile_client_size` from the previous one
## knows to stand down.
var _apply_generation := 0

func apply_window_configuration() -> void:
	# Headless runs (tests, smoke tests, CI) have no screens and no window to configure.
	if DisplayServer.get_name() == "headless":
		return

	# The editor can embed the running game inside its own Game tab. An embedded window
	# cannot be made borderless, always-on-top or click-through, so configuring it produces
	# a confusing half-broken overlay. Skip it and say why.
	if get_window().is_embedded():
		push_warning("OverlayManager: game window is embedded in the editor, so overlay mode is disabled. "
			+ "Turn off Editor Settings > Run > Window Placement > Embed Game Window (or use the "
			+ "Game tab's Make Floating button) to test the overlay.")
		return
	if not Settings.overlay_enabled:
		_applied = false
		_clear_passthrough()
		return

	var screen := _validated_monitor()
	var usable := DisplayServer.screen_get_usable_rect(screen)

	# A saved rect from a monitor that has since changed is worse than no saved rect.
	if WindowLayout.needs_revalidation(Settings.play_area_rect, usable):
		Settings.play_area_rect = Rect2i(
			WindowLayout.corner_position(Settings.play_area_corner, Settings.play_area_size, usable),
			WindowLayout.clamp_play_size(Settings.play_area_size, usable))

	var target := WindowLayout.target_rect(
		Settings.window_mode,
		usable,
		Settings.play_area_size,
		Settings.play_area_corner,
		Settings.play_area_rect.position)

	# Borderless and always-on-top are set in project.godot so the window is CREATED that
	# way. Flipping them at runtime makes Windows leave the outer size a couple of pixels
	# larger than the client area, and every passthrough call then makes the viewport flip
	# between the two sizes — the whole scene shifting 2 px on most frames.
	# Only set them here if something has cleared them.
	if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	# Always-on-top is a setting now, not a fact of the build (D49). Still the default —
	# sitting on top of the work is what a desktop buddy is for — but sharing a screen or
	# recording are reasonable things to want, and the alternative was quitting the game.
	# Written only when it differs, for the same reason as borderless above.
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP) \
			!= Settings.always_on_top:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,
			Settings.always_on_top)
	# Deliberately NOT WINDOW_FLAG_NO_FOCUS: the game's own panels need keyboard focus.

	# Restore to a plain windowed state first.
	#
	# A borderless window sized to the whole usable rect is, as far as Windows is concerned,
	# maximised — and a maximised window ignores being resized. So switching Overlay ->
	# Play area changed the setting, redrew the settings page, and left the window covering
	# the screen. There is no way out of that from inside the game, which makes it the worst
	# kind of bug: the one that traps the player in the state they were trying to leave.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	DisplayServer.window_set_position(target.position)
	DisplayServer.window_set_size(target.size)
	_apply_generation += 1
	_reconcile_client_size(_apply_generation)

	# Explicitly off: a stale passthrough flag would make the window ignore every click.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false)

	current_rect = target
	_known_size = target.size
	_applied = true
	apply_performance_settings()
	_force_passthrough_rebuild()
	window_rect_changed.emit(target)

## Sizing a BORDERLESS window leaves its outer size a couple of pixels larger than its
## client area. On its own that is harmless — but every window_set_mouse_passthrough() call
## makes Windows re-report the outer size, so the viewport flips between the two values on
## almost every frame. The whole scene, UI included, then shifts by those pixels each frame,
## which reads as everything vibrating on the spot.
##
## Shrinking the window to its own client size removes the discrepancy the flip needs.
## Must be deferred: the viewport does not report its new size until a frame has passed,
## so reading it immediately after window_set_size() returns the OLD size and corrects
## nothing (which is exactly how the first attempt at this failed).
func _reconcile_client_size(generation: int) -> void:
	for _attempt in 4:
		await get_tree().process_frame
		await get_tree().process_frame
		# A newer apply has started. This one is now describing a window that no longer
		# exists, and writing its answer would undo the new size.
		if generation != _apply_generation:
			return
		if not _applied and _attempt > 0:
			return
		var client := Vector2i(get_viewport().get_visible_rect().size)
		var outer := DisplayServer.window_get_size()
		if client.x <= 0 or client.y <= 0 or client == outer:
			return
		# A large difference means something other than the border is at work; leave it.
		if absi(outer.x - client.x) > 16 or absi(outer.y - client.y) > 16:
			return
		DisplayServer.window_set_size(client)
		_known_size = client
		current_rect.size = client

func set_window_mode(mode: WindowLayout.Mode) -> void:
	Settings.window_mode = mode
	Settings.save_settings()
	apply_window_configuration()

func set_play_area_size(size: Vector2i) -> void:
	Settings.play_area_size = size
	# The saved rect belongs to the old size; drop it so the corner snap recomputes.
	Settings.play_area_rect = Rect2i()
	Settings.save_settings()
	apply_window_configuration()

## One rung up or down the play-area ladder. Switches to play-area mode as it goes, since
## resizing is meaningless while the window is a fullscreen overlay. Shared by the F9/F10
## hotkeys and the settings panel so the two cannot drift.
func step_play_area_size(direction: int) -> void:
	Settings.window_mode = WindowLayout.Mode.PLAY_AREA
	set_play_area_size(WindowLayout.step_size(Settings.play_area_size, direction))

func snap_to_corner(corner: WindowLayout.Corner) -> void:
	Settings.play_area_corner = corner
	Settings.window_mode = WindowLayout.Mode.PLAY_AREA
	Settings.save_settings()
	apply_window_configuration()

## Float above everything, or sit in the stack like any other window (D49).
##
## Applied through the same path as every other window setting rather than by flipping the
## flag here: `apply_window_configuration` is the one place that knows about the borderless
## outer-size quirk, and a second writer of window flags is how the 2px vibration bug got in.
func set_always_on_top(value: bool) -> void:
	if Settings.always_on_top == value:
		return
	Settings.always_on_top = value
	Settings.save_settings()
	apply_window_configuration()

func move_to_monitor(screen: int) -> void:
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		return
	Settings.monitor_id = screen
	# The saved rect belongs to the old monitor; drop it so the new one is recomputed.
	Settings.play_area_rect = Rect2i()
	Settings.save_settings()
	apply_window_configuration()

func cycle_monitor() -> void:
	var count := DisplayServer.get_screen_count()
	if count > 1:
		move_to_monitor((Settings.monitor_id + 1) % count)

## Falls back to the primary screen if the saved monitor has been unplugged.
func _validated_monitor() -> int:
	var count := DisplayServer.get_screen_count()
	if Settings.monitor_id < 0 or Settings.monitor_id >= count:
		push_warning("OverlayManager: monitor %d unavailable; falling back to primary" % Settings.monitor_id)
		Settings.monitor_id = DisplayServer.get_primary_screen()
		Settings.save_settings()
	return Settings.monitor_id

func _on_window_size_changed() -> void:
	if not _applied:
		return
	var size := DisplayServer.window_get_size()
	# Ignore no-op reports. Windows raises a window change every time the passthrough
	# region is set, and treating that as a real resize is what created the feedback loop.
	if size == _known_size:
		return
	_known_size = size
	current_rect.size = size
	window_rect_changed.emit(current_rect)
	_force_passthrough_rebuild()

# --- performance -----------------------------------------------------------

func apply_performance_settings() -> void:
	if Settings.low_power_mode:
		Engine.max_fps = Settings.fps_low_power
	else:
		Engine.max_fps = Settings.fps_active if _interacting or _panel_open else Settings.fps_idle

## Called when the player starts or stops touching things, so the frame rate only climbs
## while it is actually buying something.
func set_interacting(value: bool) -> void:
	if _interacting == value:
		return
	_interacting = value
	apply_performance_settings()

func set_low_power_mode(enabled: bool) -> void:
	Settings.low_power_mode = enabled
	Settings.save_settings()
	apply_performance_settings()

## What is painted behind him (D38). Owned here with the other window settings: the F3
## hotkeys and the settings page both come through this one door.
func set_backdrop(id: StringName) -> void:
	Settings.backdrop = Backdrop.choice(id)["id"]
	Settings.save_settings()
	EventBus.backdrop_changed.emit(Settings.backdrop)

# --- mouse passthrough: REMOVED --------------------------------------------
#
# There is no click-through. The window is transparent, so you see through it, but it
# takes every click inside its rect like any normal window.
#
# Both approaches Godot offers were tried and rejected:
#
#   * A passthrough POLYGON is implemented on Windows as a window REGION, and a window
#     region clips what the window DRAWS. The visible shape of the window followed the
#     buddy's bounding box, cutting pieces off him as he moved, and an empty region blanked
#     the window completely.
#   * The all-or-nothing FLAG toggled by cursor position avoids the clipping, but it is a
#     separate feature that needs designing properly rather than bolting on.
#
# Real click-through is deferred until it can be built and visually verified on its own.
# See docs/overlay-tech.md.

## Kept so callers and signals do not need to know it is gone.
func rebuild_passthrough() -> void:
	pass

func _force_passthrough_rebuild() -> void:
	pass

func _clear_passthrough() -> void:
	pass

func _on_cursor_power_changed(item_id: StringName) -> void:
	_cursor_power_active = item_id != &""
	_force_passthrough_rebuild()

func _on_ui_panel_changed(panel: StringName) -> void:
	_panel_open = panel != &""
	apply_performance_settings()
	_force_passthrough_rebuild()


## Dev-only readout and hotkeys. Created here rather than placed in a scene so it exists
## in every level and survives the M2 scene rebuild.
func _install_debug_overlay() -> void:
	var overlay := preload("res://Scripts/Overlay/debug_overlay.gd").new()
	overlay.name = "DebugOverlay"
	add_child(overlay)
