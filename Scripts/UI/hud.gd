class_name HUD
extends CanvasLayer

## Currency chips, the knockout meter and the dock buttons that open the panels.
##
## Built in code rather than authored as a scene: every widget here is driven by data
## (currencies come from Economy's dictionary, not a fixed pair of labels), and the real
## visual pass is an art-and-Theme job that has not happened yet.

signal panel_requested(panel: StringName)

## Inset from the window edge. Small: the overlay sits on someone's desktop and the HUD
## should read as part of the game, not as a border around their screen.
const MARGIN := 12.0

var _chips: Dictionary = {}  ## StringName -> Label
var _meter: ProgressBar
var _item_count: Label
var _health: HealthComponent

func _ready() -> void:
	layer = 10
	_build()
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)
	for currency in [Economy.BONES, Economy.HEARTS]:
		_on_currency_changed(currency, Economy.balance_of(currency))

func _process(_delta: float) -> void:
	if _health and _meter:
		_meter.value = _health.fill_fraction()

## Nothing to poll until the buddy hands his meter over.
func _enter_tree() -> void:
	set_process(false)

## The meter belongs to the buddy, so main.gd hands it over rather than the HUD hunting
## for a node path across scenes (docs/decisions.md D9).
func bind_health(health: HealthComponent) -> void:
	_health = health
	set_process(true)

func bind_spawner(spawner: ItemSpawner) -> void:
	spawner.item_count_changed.connect(_set_item_count)
	# The signal only fires on a change, so the readout would sit at its placeholder until
	# the player spawned something — showing a limit of zero on a fresh boot.
	_set_item_count(spawner.item_count(), spawner.item_limit())

func _set_item_count(count: int, limit: int) -> void:
	_item_count.text = "%d / %d items" % [count, limit]

func _build() -> void:
	# A plain Control, not a MarginContainer: a container lays every child out in the same
	# rect and ignores its anchors, which would stack the dock on top of the currency
	# chips. Anchors only do what they say inside a non-container parent.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	column.position = Vector2(MARGIN, MARGIN)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)

	# --- currency chips ---
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 8)
	column.add_child(chips)
	chips.add_child(_make_chip(Economy.BONES, "BONES", UIStyle.BONES))
	chips.add_child(_make_chip(Economy.HEARTS, "HEARTS", UIStyle.HEARTS))

	# --- knockout meter ---
	var meter_box := PanelContainer.new()
	meter_box.custom_minimum_size = Vector2(210, 0)
	meter_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UIStyle.apply_panel(meter_box, UIStyle.BG)
	column.add_child(meter_box)

	var meter_column := VBoxContainer.new()
	meter_column.add_theme_constant_override("separation", 4)
	meter_box.add_child(meter_column)
	meter_column.add_child(UIStyle.label("KNOCKOUT METER", 10, UIStyle.TEXT_DIM))

	_meter = ProgressBar.new()
	_meter.max_value = 1.0
	_meter.step = 0.001
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(0, 14)
	_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter.add_theme_stylebox_override("background", UIStyle.meter_background())
	_meter.add_theme_stylebox_override("fill", UIStyle.meter_fill())
	meter_column.add_child(_meter)

	_item_count = UIStyle.label("0 / 0 items", 10, UIStyle.TEXT_DIM)
	meter_column.add_child(_item_count)

	# --- dock ---
	var dock := HBoxContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock.offset_left -= MARGIN
	dock.offset_right -= MARGIN
	dock.offset_top += MARGIN
	dock.offset_bottom += MARGIN
	dock.add_theme_constant_override("separation", 6)
	root.add_child(dock)

	for entry in [[&"shop", "Toys"], [&"tree", "Upgrades"]]:
		var button := UIStyle.button(entry[1], 14)
		button.custom_minimum_size = Vector2(96, 34)
		var panel: StringName = entry[0]
		button.pressed.connect(func() -> void: panel_requested.emit(panel))
		dock.add_child(button)

func _make_chip(currency: StringName, caption: String, colour: Color) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UIStyle.chip_box(UIStyle.BG))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	row.add_child(UIStyle.label(caption, 10, UIStyle.TEXT_DIM))
	var value := UIStyle.label("0", 16, colour)
	row.add_child(value)
	_chips[currency] = value
	return chip

func _on_currency_changed(currency: StringName, amount: float) -> void:
	var label := _chips.get(currency) as Label
	if label:
		label.text = UIStyle.format_amount(amount)

func _on_buddy_state_changed(state: StringName) -> void:
	if state == &"knockout" and _meter:
		_meter.value = 1.0
