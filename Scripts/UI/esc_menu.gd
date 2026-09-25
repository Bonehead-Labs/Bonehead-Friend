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
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.theme = UITheme.get_theme()
	add_child(_blocker)
	# The blocker is a CenterContainer sized to the viewport, so it is the one Control in
	# the shell that must NOT be divided by the UI scale — it centres against the real
	# window. The card inside it is scaled by the layer like everything else.
	EventBus.ui_scale_changed.connect(func(_f: float) -> void: _fit())
	get_viewport().size_changed.connect(_fit)
	_fit()

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"Card"
	_panel.visible = false
	_blocker.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(title)
	title.add_child(UIStyle.icon(&"bone", 16, UIStyle.BONES))
	title.add_child(UIStyle.label("BONEHEAD FRIEND", UIStyle.TITLE))

	var subtitle := UIStyle.body("Paused — he is having a rest.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	for entry in [["Resume", &"spawn", close], ["Save now", &"check",
			func() -> void: EventBus.save_requested.emit()],
			["Save and quit", &"close", _on_quit]]:
		var button := UIStyle.button(entry[0], UIStyle.LABEL)
		UIStyle.set_icon(button, UIStyle.glyph(entry[1]))
		button.custom_minimum_size = Vector2(200, 38)
		button.pressed.connect(entry[2])
		column.add_child(button)

func _fit() -> void:
	if _blocker:
		UIScale.apply(self, _blocker)

## Escape backs out of the innermost thing first (D47). With a cursor power equipped that is
## the power, not the game: the player armed the missile, and the gesture for "never mind" is
## the one they already know. A second press opens the menu as it always did.
##
## The precedence lives here rather than in a second `_unhandled_input` on the spawner
## because two nodes racing for the same key across a CanvasLayer and the world is decided by
## tree order, which is not a thing to hang a control scheme on.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if not _open and _holster_power():
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()

func _holster_power() -> bool:
	var spawner := get_tree().get_first_node_in_group(&"item_spawner")
	return spawner != null and spawner.has_method("holster_power") \
		and bool(spawner.call("holster_power"))

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	_open = true
	_panel.visible = true
	UIMotion.unroll(_panel, UIMotion.Pivot.CENTRE)
	UIMotion.stagger(_panel.get_child(0), 0.035)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	if world:
		world.process_mode = Node.PROCESS_MODE_DISABLED
	EventBus.ui_panel_changed.emit(&"esc")

func close() -> void:
	_open = false
	UIMotion.roll_up(_panel, func() -> void: _panel.visible = false, UIMotion.Pivot.CENTRE)
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if world:
		world.process_mode = Node.PROCESS_MODE_INHERIT
	EventBus.ui_panel_changed.emit(&"")

func _on_quit() -> void:
	EventBus.save_requested.emit()
	get_tree().quit()
