extends CanvasLayer

## F3 debug readout and the developer hotkeys for exercising M1.
##
## The performance numbers here are for spotting regressions while working. They are NOT
## the release gate — that has to be measured on an exported build with Task Manager or
## PresentMon, because editor numbers lie. See docs/overlay-tech.md.

const HOTKEY_HELP := "F3 stats · F4 window mode · F5 corner · F6 monitor · F7 low power · F8 overlay · F9/F10 size"

var _label: Label
var _panel: PanelContainer
var _visible := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.modulate = Color(1, 1, 1, 0.9)
	add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(_label)

	panel.visible = false
	_panel = panel

func _process(_delta: float) -> void:
	if not _visible:
		return
	_label.text = _build_text()

func _build_text() -> String:
	var mode := "fullscreen" if Settings.window_mode == 0 else "play area"
	var corner_names := ["free", "top-left", "top-right", "bottom-left", "bottom-right"]
	var rect := OverlayManager.current_rect
	var interactive := get_tree().get_nodes_in_group(&"interactive").size()

	return "\n".join([
		"BONEHEAD FRIEND — debug",
		"",
		"fps          %d  (cap %d)" % [Engine.get_frames_per_second(), Engine.max_fps],
		"process      %.2f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		"physics      %.2f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"nodes        %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"bodies       %d" % Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"memory       %.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"",
		"window       %s" % mode,
		"rect         %d,%d %dx%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"monitor      %d of %d" % [Settings.monitor_id, DisplayServer.get_screen_count()],
		"corner       %s" % corner_names[clampi(Settings.play_area_corner, 0, 4)],
		"play size    %dx%d" % [Settings.play_area_size.x, Settings.play_area_size.y],
		"low power    %s" % ("ON" if Settings.low_power_mode else "off"),
		"overlay      %s" % ("ON" if Settings.overlay_enabled else "off"),
		"interactive  %d nodes" % interactive,
		"",
		HOTKEY_HELP,
	])

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_F3:
			_visible = not _visible
			_panel.visible = _visible
		KEY_F4:
			OverlayManager.set_window_mode(1 - Settings.window_mode)
		KEY_F5:
			# Cycle through the four corners, skipping "free".
			var next := Settings.play_area_corner + 1
			if next > 4:
				next = 1
			OverlayManager.snap_to_corner(next)
		KEY_F6:
			OverlayManager.cycle_monitor()
		KEY_F7:
			OverlayManager.set_low_power_mode(not Settings.low_power_mode)
		KEY_F9:
			_step_play_size(-1)
		KEY_F10:
			_step_play_size(1)
		KEY_F8:
			Settings.overlay_enabled = not Settings.overlay_enabled
			Settings.save_settings()
			OverlayManager.apply_window_configuration()
		_:
			return
	get_viewport().set_input_as_handled()

## Steps to the next larger or smaller play area. The ladder itself lives in WindowLayout
## now, because the settings panel offers the same steps and the two must not drift apart.
func _step_play_size(direction: int) -> void:
	OverlayManager.step_play_area_size(direction)
