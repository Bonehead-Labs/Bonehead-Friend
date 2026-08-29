class_name EscMenu
extends CanvasLayer

## Escape pauses the sandbox — and only the sandbox.
##
## Never get_tree().paused: that would stop the economy, the autosave timer and the
## offline accrual along with the physics, which in an idle game means Escape costs the
## player money (docs/architecture.md, "Pause semantics matter"). Only the World node's
## process_mode changes.

## The subtree that stops when paused. Set by main.gd.
var world: Node

var _panel: PanelContainer
var _blocker: CenterContainer
var _open := false

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	# This container fills the window, and it sits on the topmost CanvasLayer. On its
	# default mouse filter it is therefore the control under EVERY click in the game —
	# the dock, the panels and the buddy all stopped responding and nothing was drawn to
	# explain why. It only blocks while the menu is actually open, where blocking is the
	# point: a paused game should not take clicks through to the world behind it.
	_blocker = CenterContainer.new()
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blocker)

	_panel = PanelContainer.new()
	UIStyle.apply_panel(_panel)
	_panel.visible = false
	_blocker.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	column.add_child(UIStyle.label("BONEHEAD FRIEND", 18))
	column.add_child(UIStyle.label("Paused — he is having a rest.", 11, UIStyle.TEXT_DIM))

	var resume := UIStyle.button("Resume", 14)
	resume.custom_minimum_size = Vector2(180, 34)
	resume.pressed.connect(close)
	column.add_child(resume)

	var save_button := UIStyle.button("Save now", 14)
	save_button.custom_minimum_size = Vector2(180, 34)
	save_button.pressed.connect(func() -> void: EventBus.save_requested.emit())
	column.add_child(save_button)

	var quit := UIStyle.button("Save and quit", 14)
	quit.custom_minimum_size = Vector2(180, 34)
	quit.pressed.connect(_on_quit)
	column.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	_open = true
	_panel.visible = true
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	if world:
		world.process_mode = Node.PROCESS_MODE_DISABLED
	EventBus.ui_panel_changed.emit(&"esc")

func close() -> void:
	_open = false
	_panel.visible = false
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if world:
		world.process_mode = Node.PROCESS_MODE_INHERIT
	EventBus.ui_panel_changed.emit(&"")

func _on_quit() -> void:
	EventBus.save_requested.emit()
	get_tree().quit()
