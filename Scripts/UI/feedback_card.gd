class_name FeedbackCard
extends CanvasLayer

## A note from the person playing, in two taps from anywhere: F1, the Playtest keys on the
## Settings page, or Feedback on the Esc menu (docs/playtest-plan.md).
##
## One tap for how it is going, a box for what happened, and a line for what they were trying
## to do — the question a playtest note most often forgets to answer, and the one that turns
## "the shop is confusing" into something fixable. Everything else is attached by the game:
## the build, the purse, what is owned and on the desk, the page, his mood, the last few minutes
## of play and a picture of the window taken *before* this card was drawn (`Playtest`).
##
## **Keyboard focus.** The window is transparent and borderless but it is an ordinary focusable
## window: there is no click-through (`OverlayManager`, "mouse passthrough: REMOVED"), and it is
## deliberately not created with `WINDOW_FLAG_NO_FOCUS`. So a click on the card gives the window
## the OS focus, and F1 arrived through it already. Opening grabs the window's focus as well as
## the text box's — the Settings key may be the first thing clicked after working elsewhere — and
## closing hands the focus back to nothing, so no box keeps eating keys under a shut card.
##
## Built like `EscMenu`: a centring blocker that takes clicks only while the card is up, one
## `Card`, the layer scaled by `UIScale`. Layer 35, above the Esc menu (30), since the menu is one
## of the ways here.

const WIDTH := 420.0
const MARGIN := 12.0
## The note box's height when the window has the room, and when it does not: at the smallest
## play area (480x360 at 1x) the card has 336px, and everything but the box takes most of it.
const TEXT_ROOMY := 76.0
const TEXT_TIGHT := 44.0
const ROOMY_FROM := 400.0

const MOODS := [["good", "Good"], ["meh", "Meh"], ["bad", "Bad"]]

var _blocker: CenterContainer
var _card: PanelContainer
var _moods: Dictionary = {}   ## mood id -> Button
var _text: TextEdit
var _trying: LineEdit
var _save: Button
var _cancel: Button
var _mood := ""
var _open := false
var _busy := false
var _context: Dictionary = {}
var _shot: Image = null
var _page_before: StringName = &""

func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Playtest.feedback_requested.connect(open_card)
	EventBus.ui_scale_changed.connect(func(_f: float) -> void: _fit())
	get_viewport().size_changed.connect(_fit)
	OverlayManager.window_rect_changed.connect(func(_r: Rect2i) -> void: _fit())
	_fit()

func _build() -> void:
	# Full-window and on a high layer, so it takes clicks only while the card is up — the
	# failure CLAUDE.md warns about, and the one `EscMenu` already solved the same way.
	_blocker = CenterContainer.new()
	_blocker.name = "FeedbackBlocker"
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.theme = UITheme.get_theme()
	add_child(_blocker)

	_card = PanelContainer.new()
	_card.name = "FeedbackPanel"
	_card.theme_type_variation = &"Card"
	_card.visible = false
	_blocker.add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	_card.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var eyebrow := UIStyle.eyebrow("Feedback")
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(eyebrow)
	var build := UIStyle.label("build %s" % BuildInfo.id(), UIStyle.MICRO, UIStyle.TEXT_DIM)
	build.name = "FeedbackBuild"
	head.add_child(build)
	column.add_child(head)

	column.add_child(UIStyle.label("How is it going?", UIStyle.LABEL, UIStyle.TEXT))

	var moods := HBoxContainer.new()
	moods.add_theme_constant_override("separation", 6)
	for entry in MOODS:
		var key := UIStyle.button(entry[1], UIStyle.LABEL)
		key.name = "Mood_%s" % entry[0]
		key.toggle_mode = true
		key.custom_minimum_size = Vector2(0, 36)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.pressed.connect(_pick_mood.bind(String(entry[0])))
		moods.add_child(key)
		_moods[String(entry[0])] = key
	column.add_child(moods)

	_text = TextEdit.new()
	_text.name = "FeedbackText"
	_text.placeholder_text = "What happened? What did you expect?"
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.scroll_fit_content_height = false
	_text.custom_minimum_size = Vector2(0, TEXT_ROOMY)
	_text.text_changed.connect(_refresh_save)
	column.add_child(_text)

	_trying = LineEdit.new()
	_trying.name = "FeedbackTrying"
	_trying.placeholder_text = "What were you trying to do? (optional)"
	_trying.max_length = 240
	_trying.text_submitted.connect(func(_t: String) -> void: _on_save())
	column.add_child(_trying)

	var note := UIStyle.body("Saved with it: a picture of this window, what you own and what "
		+ "is on the desk. Nothing leaves this computer until you send it.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)

	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	_save = UIStyle.button("Save note", UIStyle.LABEL)
	_save.name = "FeedbackSave"
	_save.theme_type_variation = &"BuyButton"
	_save.tooltip_text = "Ctrl+Enter"
	_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save.pressed.connect(_on_save)
	keys.add_child(_save)
	_cancel = UIStyle.button("Cancel", UIStyle.MICRO)
	_cancel.name = "FeedbackCancel"
	_cancel.theme_type_variation = &"GhostButton"
	_cancel.tooltip_text = "Esc"
	_cancel.pressed.connect(close_card)
	keys.add_child(_cancel)
	column.add_child(keys)

## The blocker centres against the real window, the card inside it is scaled with the layer —
## and is never wider or taller than the window leaves room for.
func _fit() -> void:
	if _blocker == null:
		return
	UIScale.apply(self, _blocker)
	var room := _blocker.size - Vector2(MARGIN * 2.0, MARGIN * 2.0)
	_card.custom_minimum_size = Vector2(minf(WIDTH, maxf(240.0, room.x)), 0.0)
	_text.custom_minimum_size.y = TEXT_ROOMY if room.y >= ROOMY_FROM else TEXT_TIGHT

func is_open() -> bool:
	return _open

## Asked for. The context and the picture are taken first: the context before this card changes
## the page, and the picture one drawn frame after the request — so a menu the request closed
## has gone — and before the card exists to be in it.
func open_card() -> void:
	if _open or _busy:
		return
	_busy = true
	_page_before = Playtest.current_page()
	_context = Playtest.snapshot_context()
	_shot = null
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_shot = Playtest.capture_window()
	_busy = false
	_show()

func _show() -> void:
	_open = true
	_mood = ""
	for id in _moods:
		_set_mood_key(id, false)
	_text.text = ""
	_trying.text = ""
	_refresh_save()
	_card.visible = true
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	UIMotion.unroll(_card, UIMotion.Pivot.CENTRE)
	EventBus.ui_panel_changed.emit(&"feedback")
	if DisplayServer.get_name() != "headless" and not get_window().has_focus():
		get_window().grab_focus()
	_text.grab_focus()
	_text.call_deferred(&"grab_focus")

func close_card() -> void:
	if not _open:
		return
	_open = false
	if _text.has_focus() or _trying.has_focus():
		get_viewport().gui_release_focus()
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIMotion.roll_up(_card, func() -> void: _card.visible = false, UIMotion.Pivot.CENTRE)
	EventBus.ui_panel_changed.emit(_page_before)
	_shot = null
	_context = {}

func _pick_mood(id: String) -> void:
	_mood = "" if _mood == id else id
	for key in _moods:
		_set_mood_key(key, key == _mood)
	_refresh_save()

## A toggled key draws pressed into the card; the ink says which one as well, the way the
## Settings page's choices do.
func _set_mood_key(id: String, on: bool) -> void:
	var key := _moods[id] as Button
	key.set_pressed_no_signal(on)
	UIStyle.tint_button(key, UIStyle.TEXT if on else UIStyle.TEXT_DIM)

func _can_save() -> bool:
	return _mood != "" or _text.text.strip_edges() != ""

func _refresh_save() -> void:
	if _save:
		_save.disabled = not _can_save()

func _on_save() -> void:
	if not _open:
		return
	if not _can_save():
		UIMotion.buzz(_save)
		return
	var note := {
		"mood": _mood,
		"text": _text.text.strip_edges(),
		"trying": _trying.text.strip_edges(),
		"context": _context,
	}
	var path := Playtest.save_note(note, _shot)
	close_card()
	if path == "":
		Playtest.toast("That note could not be saved.")
	else:
		Playtest.toast("Thanks — note saved. Settings › Send feedback sends them all.")

## Esc backs out of the card before the Esc menu hears it, and Ctrl+Enter saves from inside
## the note box, where Enter is a new line. `_input`, so both win over the focused box.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close_card()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.is_echo() and key.ctrl_pressed \
			and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		_on_save()
		get_viewport().set_input_as_handled()

## F1 from anywhere. Not F8: that is the developer's escape hatch out of the overlay
## (docs/test-matrix.md), and a tester may need it.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.is_echo() and key.keycode == KEY_F1:
		if not _open:
			open_card()
		get_viewport().set_input_as_handled()
