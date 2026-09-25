class_name SettingsPanel
extends PanelPage

## The knobs a player needs to make the overlay liveable, pulled forward from M4.
##
## The full settings UI is M4 scope. This is the subset that is *load-bearing for a
## playtest*: until it existed, resizing the window, moving it to another monitor or
## turning the effects down were F3-overlay developer hotkeys, so a playtester who did not
## know F9/F10 could not make the game fit on their desk. A borderless window has no OS
## grab handle either, so there was no discoverable way to resize it at all.
##
## Everything here writes through OverlayManager and Settings, which already persist and
## revalidate; this file is only the widgets. Deliberately buttons rather than sliders and
## OptionButtons: both of those are awkward over a transparent always-on-top window, and
## the ui_check sweep can assert a Button is reachable in a way it cannot for a popup.

const FOCUS_NAMES: Array[String] = ["Off", "Subtle", "Normal", "Chaos"]
const CORNER_NAMES: Array[String] = ["Top left", "Top right", "Bottom left", "Bottom right"]

## Volume steps. Coarse on purpose — this is a desktop toy, not a mixing desk.
const VOLUME_STEP := 0.1

var _rows: Dictionary = {}  ## StringName -> Control whose text is refreshed
var _column: VBoxContainer

func _ready() -> void:
	EventBus.focus_mode_changed.connect(func(_level: int) -> void: request_refresh())
	# The F3 developer hotkeys change window mode, corner and monitor without going through
	# this panel and emit nothing, so this is the one page that cannot be brought up to date
	# by a signal. It re-reads every time it is shown.
	refresh_on_show = true
	super()

func _build_page() -> void:
	add_theme_constant_override("separation", 10)
	# `_section`, `_row` and `_note` all add to `_column`. No scroll of its own — the
	# card's host is already one.
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 9)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_column)

	_section("WINDOW")
	var mode_row := _choices()
	_choice(mode_row, "Overlay", &"mode_overlay", func() -> void:
		OverlayManager.set_window_mode(WindowLayout.Mode.FULLSCREEN_OVERLAY))
	_choice(mode_row, "Play area", &"mode_play", func() -> void:
		OverlayManager.set_window_mode(WindowLayout.Mode.PLAY_AREA))

	var size_row := _row()
	_rows[&"size"] = _stat(size_row, "Play area size", "—")
	_stepper(size_row, "−", func() -> void: OverlayManager.step_play_area_size(-1))
	_stepper(size_row, "+", func() -> void: OverlayManager.step_play_area_size(1))

	# The four corners are a tidy-up, not the only places it can go (D49/D52). Dragging the
	# grip moves the window and clears whichever of these was set, which is why none of them
	# is lit by default any more.
	var corner_row := _choices()
	for i in CORNER_NAMES.size():
		var corner := i + 1  # 0 is FREE; the buttons offer the four snapped corners.
		_choice(corner_row, CORNER_NAMES[i], StringName("corner_%d" % corner), func() -> void:
			OverlayManager.snap_to_corner(corner))
	_column.add_child(_note("Drag the grip at the top of the window to move it — any screen, no snapping. The corners snap it back."))

	var top_row := _row()
	_rows[&"always_on_top"] = _stat(top_row, "Always on top", "—")
	_stepper(top_row, "Toggle", func() -> void: OverlayManager.set_always_on_top(
		not Settings.always_on_top))

	# Only worth the space on a machine that has somewhere to move to.
	if DisplayServer.get_screen_count() > 1:
		_section("DISPLAY")
		var monitor_row := _row()
		_rows[&"monitor"] = _stat(monitor_row, "Monitor", "—")
		_stepper(monitor_row, "Next", func() -> void: OverlayManager.cycle_monitor())

	_section("FOCUS MODE")
	_column.add_child(_note("How loud the game is allowed to be while you work. Off still earns."))
	var focus_row := _choices()
	for level in FOCUS_NAMES.size():
		_choice(focus_row, FOCUS_NAMES[level], StringName("focus_%d" % level), func() -> void:
			Settings.set_focus_intensity(level))

	_section("UI SIZE")
	_column.add_child(_note("How big the menus are drawn, in quarter steps. Whole numbers "
		+ "are the sharp ones: the shell is pixel art, so 1.75x resamples it slightly."))
	var scale_row := _row()
	_rows[&"ui_scale"] = _stat(scale_row, "Menu size", "—")
	_stepper(scale_row, "−", func() -> void: _nudge_ui_scale(-UIScale.STEP))
	_stepper(scale_row, "+", func() -> void: _nudge_ui_scale(UIScale.STEP))
	_stepper(scale_row, "Auto", func() -> void: Settings.set_ui_scale(0.0))

	_section("BACKDROP")
	# Two rows: flat colours, then scenes. Desktop is the transparent default. Every choice
	# is a `Backdrop` entry; the panel adds nothing of its own, so a new backdrop is a row in
	# that table and appears here by itself.
	var backdrop_rows := [_choices(), _choices()]
	for entry in Backdrop.CHOICES:
		var id: StringName = entry["id"]
		_choice(backdrop_rows[int(entry["row"])], entry["name"], StringName("backdrop_%s" % id),
			func() -> void: OverlayManager.set_backdrop(id))
	_column.add_child(_note("Chroma is pure key green, for a stream. Scenes are drawn to the window, so they fit every size and monitor."))

	_section("PERFORMANCE")
	var power_row := _row()
	_rows[&"low_power"] = _stat(power_row, "Low power mode", "—")
	_stepper(power_row, "Toggle", func() -> void:
		OverlayManager.set_low_power_mode(not Settings.low_power_mode))

	_section("AUDIO")
	_volume_row("Master", &"volume_master")
	_volume_row("Effects", &"volume_sfx")

func _volume_row(caption: String, key: StringName) -> void:
	var row := _row()
	_rows[key] = _stat(row, caption, "—")
	_stepper(row, "−", func() -> void: _nudge_volume(key, -VOLUME_STEP))
	_stepper(row, "+", func() -> void: _nudge_volume(key, VOLUME_STEP))

## Step the pinned scale, starting from whatever is actually on screen (D50).
##
## From "Auto" the first press has to land somewhere sensible, and the sensible place is the
## factor the shell is already using — otherwise pressing + on an auto-2x shell drops it to
## 1.25x, which reads as the button working backwards.
func _nudge_ui_scale(delta: float) -> void:
	var current := Settings.ui_scale
	if current <= 0.0:
		current = UIScale.factor_for(get_viewport().get_visible_rect().size)
	Settings.set_ui_scale(current + delta)

func _nudge_volume(key: StringName, delta: float) -> void:
	Settings.set(key, clampf(float(Settings.get(key)) + delta, 0.0, 1.0))
	Settings.save_settings()
	AudioManager.apply_volumes()

# --- state -----------------------------------------------------------------

## Re-reads Settings rather than tracking its own copy. The F3 hotkeys change exactly these
## values behind this panel's back, and two sources of truth for the window mode is how a
## settings screen ends up lying to the player.
func _refresh() -> void:
	_set_choice(&"mode_overlay", Settings.window_mode == WindowLayout.Mode.FULLSCREEN_OVERLAY)
	_set_choice(&"mode_play", Settings.window_mode == WindowLayout.Mode.PLAY_AREA)
	for i in CORNER_NAMES.size():
		_set_choice(StringName("corner_%d" % (i + 1)), Settings.play_area_corner == i + 1)
	for level in FOCUS_NAMES.size():
		_set_choice(StringName("focus_%d" % level), int(Settings.focus_intensity) == level)
	for entry in Backdrop.CHOICES:
		_set_choice(StringName("backdrop_%s" % entry["id"]), Settings.backdrop == entry["id"])

	_set_stat(&"size", "%d x %d" % [Settings.play_area_size.x, Settings.play_area_size.y])
	_set_stat(&"monitor", "%d of %d" % [Settings.monitor_id, DisplayServer.get_screen_count()])
	_set_stat(&"low_power", "on" if Settings.low_power_mode else "off")
	_set_stat(&"always_on_top", "on" if Settings.always_on_top else "off")
	# The factor in force, not the one requested: a pinned 2x on the smallest play area is
	# honoured as 1x because the card would not fit, and the panel has to say so rather than
	# claim a setting the shell is not using.
	# Trailing zeros trimmed, so a whole number reads "2x" rather than "2.00x" — and says
	# whether the shell is following the window or a pin the player set.
	var in_force := UIScale.factor_for(get_viewport().get_visible_rect().size)
	var shown := ("%.2f" % in_force).rstrip("0").rstrip(".")
	_set_stat(&"ui_scale", "%sx%s" % [shown, "" if Settings.ui_scale > 0.0 else "  auto"])
	_set_stat(&"volume_master", "%d%%" % roundi(Settings.volume_master * 100.0))
	_set_stat(&"volume_sfx", "%d%%" % roundi(Settings.volume_sfx * 100.0))

func _set_choice(key: StringName, active: bool) -> void:
	var button := _rows.get(key) as Button
	if button == null:
		return
	button.button_pressed = active
	UIStyle.tint_button(button, UIStyle.TEXT if active else UIStyle.TEXT_DIM)

func _set_stat(key: StringName, text: String) -> void:
	var label := _rows.get(key) as Label
	if label:
		label.text = text

# --- widgets ---------------------------------------------------------------

func _section(title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UIStyle.eyebrow(title))
	var rule := ColorRect.new()
	rule.color = Color(UIStyle.EDGE, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	_column.add_child(row)

func _note(text: String) -> Label:
	var label := UIStyle.body(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	return label

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_column.add_child(row)
	return row

## A row of choices that wraps rather than widens. Seven backdrops at 84px are 624px of keys,
## and at 2x on the default play area the card is 525px inside — so Chroma, the last of them
## and the one a streamer wants, was past the card's right edge with nothing to say it was
## there (D68). A row of choices has no business setting the card's width.
func _choices() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	_column.add_child(row)
	return row

## A caption and its current value, as one expanding cell so the buttons after it line up
## down the column whatever the value's width.
func _stat(row: HBoxContainer, caption: String, value: String) -> Label:
	row.add_child(UIStyle.body(caption, UIStyle.BODY, UIStyle.TEXT))
	var label := UIStyle.label(value, UIStyle.LABEL, UIStyle.TEXT)
	label.theme_type_variation = &"Numeral"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(label)
	return label

## Toggles rather than plain buttons: the theme draws a toggled-on button pushed into the
## card, so which option is selected is a shape and not only a colour. `_refresh()` is
## authoritative — setting `button_pressed` from code emits `toggled`, not `pressed`, so
## there is no loop back into the action.
func _choice(row: Container, caption: String, key: StringName, action: Callable) -> void:
	var button := UIStyle.button(caption, UIStyle.MICRO)
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(84, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		action.call()
		_refresh())
	row.add_child(button)
	_rows[key] = button

## Refreshes after the action, exactly as `_choice` does. Without it the size and monitor
## steppers resize and move the window while their own readout keeps showing the old value —
## and nothing else refreshes the panel, so it stays wrong until some other button is used.
func _stepper(row: HBoxContainer, caption: String, action: Callable) -> void:
	var button := UIStyle.button(caption, UIStyle.MICRO)
	button.theme_type_variation = &"GhostButton"
	button.custom_minimum_size = Vector2(52, 30)
	button.pressed.connect(func() -> void:
		action.call()
		_refresh())
	row.add_child(button)
