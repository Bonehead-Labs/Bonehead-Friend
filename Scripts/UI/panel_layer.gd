class_name PanelLayer
extends CanvasLayer

## The Shop and the Tree, in one opaque panel over the transparent window.
##
## Opaque and inside the single game window on purpose (docs/decisions.md D6): extra
## native Window nodes each complicate always-on-top ordering for no benefit, and the
## overlay needs to know when a panel is open because a panel open means the whole window
## is taking clicks.

var _panel: PanelContainer
var _tabs: HBoxContainer
var _pages: Dictionary = {}  ## StringName -> Control
var _current: StringName = &""

func _ready() -> void:
	layer = 20
	_build()
	close()

func _build() -> void:
	var anchor := MarginContainer.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.add_theme_constant_override("margin_left", 12)
	anchor.add_theme_constant_override("margin_top", 56)
	anchor.add_theme_constant_override("margin_right", 12)
	anchor.add_theme_constant_override("margin_bottom", 12)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	UIStyle.apply_panel(_panel)
	anchor.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_tabs)

	var close_button := UIStyle.button("✕", 14)
	close_button.custom_minimum_size = Vector2(30, 28)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)

	_add_page(&"shop", "Toys", ShopPanel.new(), pages)
	_add_page(&"tree", "Upgrades", AugmentPanel.new(), pages)

func _add_page(id: StringName, caption: String, page: Control, host: Control) -> void:
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.visible = false
	host.add_child(page)
	_pages[id] = page

	var tab := UIStyle.button(caption, 13)
	tab.custom_minimum_size = Vector2(88, 28)
	tab.pressed.connect(func() -> void: show_panel(id))
	_tabs.add_child(tab)

## Clicking the dock button for the panel that is already open closes it, which is what
## every player expects and what the prototype's toggle did right.
func toggle(panel: StringName) -> void:
	if _current == panel:
		close()
	else:
		show_panel(panel)

func show_panel(panel: StringName) -> void:
	if not _pages.has(panel):
		return
	_current = panel
	_panel.visible = true
	for id in _pages:
		(_pages[id] as Control).visible = id == panel
	EventBus.ui_panel_changed.emit(panel)

func close() -> void:
	_current = &""
	if _panel:
		_panel.visible = false
	EventBus.ui_panel_changed.emit(&"")

func is_open() -> bool:
	return _current != &""
