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
## Last polygon actually handed to DisplayServer. Setting a passthrough region makes
## Windows report a window change, which used to force another rebuild on the next frame —
## a self-sustaining loop that called into the compositor every frame and cost ~26 ms.
var _last_polygon := PackedVector2Array()
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
	_passthrough_accumulator += delta
	if _passthrough_accumulator >= 1.0 / PASSTHROUGH_HZ:
		_passthrough_accumulator = 0.0
		rebuild_passthrough()

	# Drop back to the idle frame rate once the player stops touching things.
	if _interacting:
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

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	# Deliberately NOT WINDOW_FLAG_NO_FOCUS: the game's own panels need keyboard focus.

	DisplayServer.window_set_position(target.position)
	DisplayServer.window_set_size(target.size)
	target.size = _reconcile_client_size(target.size)

	current_rect = target
	_known_size = target.size
	_applied = true
	apply_performance_settings()
	_force_passthrough_rebuild()
	window_rect_changed.emit(target)

## Windows can hand back a client area a couple of pixels smaller than the size we asked
## for. Godot then reports a window/viewport mismatch every frame, which produced ~80
## spurious size_changed events per second. Reconciling once stops the storm.
func _reconcile_client_size(requested: Vector2i) -> Vector2i:
	var actual := Vector2i(get_viewport().get_visible_rect().size)
	if actual == requested or actual.x <= 0 or actual.y <= 0:
		return requested
	var delta := (requested - actual).abs()
	# Only correct small discrepancies; a large one means something else resized us.
	if delta.x > 8 or delta.y > 8:
		return requested
	DisplayServer.window_set_size(actual)
	return actual

func set_window_mode(mode: WindowLayout.Mode) -> void:
	Settings.window_mode = mode
	Settings.save_settings()
	apply_window_configuration()

func set_play_area_size(size: Vector2i) -> void:
	Settings.play_area_size = size
	Settings.save_settings()
	apply_window_configuration()

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

# --- mouse passthrough -----------------------------------------------------

func rebuild_passthrough() -> void:
	if not _applied:
		return

	# While a panel is open the whole window must accept clicks, or the player cannot use
	# the thing they just opened. Same when a cursor power is armed: the player is aiming
	# at the desktop, so every pixel has to be a valid target.
	var polygon: PackedVector2Array
	if _panel_open or _cursor_power_active:
		polygon = PassthroughBuilder.whole_window(DisplayServer.window_get_size())
	else:
		var origin := Vector2(DisplayServer.window_get_position())
		polygon = PassthroughBuilder.build(_collect_interaction_rects(), origin)

	_apply_passthrough(polygon)

## Only touches the compositor when the region actually changed. Each call builds a Win32
## region for the whole window, so doing it per frame on a 2560x1380 overlay dominated the
## frame time.
func _apply_passthrough(polygon: PackedVector2Array) -> void:
	if _polygons_equal(polygon, _last_polygon):
		return
	_last_polygon = polygon
	DisplayServer.window_set_mouse_passthrough(polygon)

static func _polygons_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		# Sub-pixel jitter is not worth a compositor round trip.
		if not (a[i].is_equal_approx(b[i]) or a[i].distance_squared_to(b[i]) < 1.0):
			return false
	return true

func _collect_interaction_rects() -> Array:
	var rects: Array = []
	for node in get_tree().get_nodes_in_group(GROUP_INTERACTIVE):
		if not is_instance_valid(node):
			continue
		if node.has_method("get_interaction_rect"):
			rects.append(node.get_interaction_rect())
		elif node is Control:
			# Controls already live in screen space.
			rects.append((node as Control).get_global_rect())
		elif node is Node2D:
			var pos: Vector2 = (node as Node2D).global_position
			rects.append(Rect2(pos - DEFAULT_INTERACTION_EXTENT, DEFAULT_INTERACTION_EXTENT * 2.0))
	return rects

func _force_passthrough_rebuild() -> void:
	_passthrough_accumulator = 1.0

func _clear_passthrough() -> void:
	_last_polygon = PackedVector2Array()
	# Empty array = passthrough disabled = the window intercepts everything, which is the
	# right behaviour when the overlay is turned off.
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())

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
