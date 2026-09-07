class_name WindowGrip
extends CanvasLayer

## The one place you can pick the window up (D52).
##
## The window is borderless, so it has no title bar and no OS grab handle. D49 let the player
## drag the *background* instead, which was too large a target to be deliberate: the owner
## went to click something in the play area, missed it, and moved the window. An overlay is
## mostly empty space, so "anywhere nothing else claimed" is very nearly everywhere.
##
## **Top centre**, which is where a title bar lives on every other window on the desktop, and
## which is the one edge of the shell nothing else occupies — the HUD column is top-left
## (`hud.gd`) and the tab strip is top-right (`panel_layer.gd`). Putting it in either corner
## would have meant reserving a strip in both of them and re-homing two auto-hide drawers.
##
## **Layer 25**: above `PanelLayer` (20) so an open card can never bury it, below `EscMenu`
## (30) so a modal correctly covers it. You can always move the window, even mid-shop.
##
## The gesture is handled here in `gui_input` and not in `OverlayManager._unhandled_input`,
## because a `MOUSE_FILTER_STOP` Control consumes the press at the GUI stage — unhandled
## input is guaranteed never to fire for it. `OverlayManager` owns the maths; this owns the
## target.

## The grab target, in UI pixels. Wide enough to hit without aiming, shallow enough to read
## as trim rather than a toolbar.
const BOX := Vector2(52.0, 14.0)
const INSET := 2.0

## Ink, taken from the shell rather than invented here. Three bars on a sunk plate is the
## universal "drag me" and needs no label or tip to teach.
const BARS := 3
const BAR_INSET := Vector2(10.0, 4.0)

var _root: Control
var _grip: Control
var _hovered := false

func _ready() -> void:
	layer = 25
	_build()
	EventBus.ui_scale_changed.connect(func(_f: float) -> void: _fit())
	get_viewport().size_changed.connect(_fit)
	# `size_changed` alone is not enough after a window-mode change: the resize has not landed
	# when the setting is applied, so a layout done then is against the previous window.
	OverlayManager.window_rect_changed.connect(func(_r: Rect2i) -> void: _fit())
	_fit()

func _build() -> void:
	_root = Control.new()
	_root.name = "GripRoot"
	# IGNORE, or this covers the whole window and eats every click in the game — the failure
	# CLAUDE.md records as having killed the dock, both panels and dragging the buddy at once.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_grip = Control.new()
	_grip.name = "WindowGripHandle"
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.custom_minimum_size = BOX
	_grip.size = BOX
	_grip.tooltip_text = "Drag to move the window — anywhere, including your other screen"
	_grip.gui_input.connect(_on_grip_input)
	_grip.mouse_entered.connect(func() -> void: _hovered = true; _grip.queue_redraw())
	_grip.mouse_exited.connect(func() -> void: _hovered = false; _grip.queue_redraw())
	_grip.draw.connect(_draw_grip)
	_root.add_child(_grip)

## Drawn rather than themed: it is three bars on a plate, it has to land exactly on the pixel
## grid at every whole-number layer scale, and a StyleBox would bring padding and a minimum
## size it does not want.
func _draw_grip() -> void:
	var plate := Color(UIStyle.SUNK)
	plate.a = 0.9 if _hovered else 0.55
	_grip.draw_rect(Rect2(Vector2.ZERO, BOX), plate)
	var ink := UIStyle.TEXT if _hovered else UIStyle.TEXT_DIM
	var span := BOX.x - BAR_INSET.x * 2.0
	var gap := (BOX.y - BAR_INSET.y * 2.0) / float(maxi(BARS - 1, 1))
	for i in BARS:
		var y := BAR_INSET.y + gap * float(i)
		_grip.draw_rect(Rect2(Vector2(BAR_INSET.x, y), Vector2(span, 1.0)), ink)

## A child of a plain Control is never laid out, so both halves of its rect are written here.
func _fit() -> void:
	if _root == null:
		return
	UIScale.apply(self, _root)
	_grip.visible = OverlayManager.window_is_movable()
	_grip.size = BOX
	_grip.position = Vector2(round((_root.size.x - BOX.x) * 0.5), INSET)

func _on_grip_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			OverlayManager.begin_window_drag(DisplayServer.mouse_get_position())
		else:
			OverlayManager.end_window_drag()
		_grip.accept_event()
		return
	# Motion only matters once armed, and it has to keep arriving after the cursor has left
	# the grip — which it does, because a Control that took the press keeps mouse focus for
	# the drag. The position is read from the OS rather than from the event: the window is
	# moving out from under the cursor, so the event's own position is measured against a
	# frame that is itself sliding.
	if event is InputEventMouseMotion and OverlayManager.window_drag_armed():
		OverlayManager.update_window_drag(DisplayServer.mouse_get_position())
		_grip.accept_event()

## A release delivered somewhere else — over another monitor, or outside the window entirely
## — never reaches `gui_input`, and the drag would stay armed until the next click. Watched
## from `_input`, which sees events before GUI picking and therefore sees all of them.
func _input(event: InputEvent) -> void:
	if not OverlayManager.window_drag_armed():
		return
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		OverlayManager.end_window_drag()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			OverlayManager.end_window_drag()
		else:
			OverlayManager.update_window_drag(DisplayServer.mouse_get_position())
