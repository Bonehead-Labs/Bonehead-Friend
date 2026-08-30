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
	if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
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
