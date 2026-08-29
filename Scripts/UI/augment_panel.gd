class_name AugmentPanel
extends VBoxContainer

## The tree. One UI for every item's augments, because every tree has the same shape
## (docs/economy.md) — that identical shape is what makes three flavours per weapon nearly
## free, and it only pays off if there is exactly one panel for all of them.

## Human wording for an effect_key. Adding an effect means adding a line here; adding an
## augment does not.
const EFFECT_WORDS := {
	&"damage_mult": "damage",
	&"payout_mult": "Bones earned",
	&"mass_mult": "weight",
	&"cooldown_mult": "time between uses",
}

var _item_list: VBoxContainer
var _node_list: VBoxContainer
var _selected: StringName = &""
var _bulk: int = 1

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build()
	EventBus.currency_changed.connect(func(_c: StringName, _b: float) -> void: refresh())
	EventBus.augment_purchased.connect(func(_id: StringName, _l: int) -> void: refresh())
	EventBus.item_purchased.connect(func(_id: StringName) -> void: rebuild())

func _build() -> void:
	var bulk_row := HBoxContainer.new()
	bulk_row.add_theme_constant_override("separation", 4)
	add_child(bulk_row)
	bulk_row.add_child(UIStyle.label("BUY", 10, UIStyle.TEXT_DIM))
	# Bulk buying has to exist from day one — retrofitting it is where the "Buy x10 that
	# quietly overcharges" bug comes from. The maths is closed-form and unit-tested.
	for amount in [1, 10, -1]:
		var button := UIStyle.button("Max" if amount < 0 else "x%d" % amount, 11)
		button.toggle_mode = true
		button.button_pressed = amount == _bulk
		button.pressed.connect(func() -> void:
			_bulk = amount
			_sync_bulk_buttons(bulk_row)
			refresh())
		bulk_row.add_child(button)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	_item_list = VBoxContainer.new()
	_item_list.custom_minimum_size = Vector2(130, 0)
	_item_list.add_theme_constant_override("separation", 3)
	split.add_child(_item_list)

	_node_list = VBoxContainer.new()
	_node_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node_list.add_theme_constant_override("separation", 4)
	split.add_child(_node_list)

	rebuild()

func _sync_bulk_buttons(row: HBoxContainer) -> void:
	var amounts := [1, 10, -1]
	var index := 0
	for child in row.get_children():
		if child is Button:
			(child as Button).button_pressed = amounts[index] == _bulk
			index += 1

## Rebuilt rather than refreshed when the roster changes, which is rare — buying an item
## adds a whole tree.
func rebuild() -> void:
	for child in _item_list.get_children():
		child.queue_free()

	var owned := _items_with_trees()
	if owned.is_empty():
		_selected = &""
	elif not owned.any(func(i: ItemData) -> bool: return i.id == _selected):
		_selected = owned[0].id

	for item in owned:
		var button := UIStyle.button(item.display_name, 12)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Which item's tree you are looking at has to be visible: with one owned item the
		# column reads as a stray label rather than a list you can pick from.
		button.add_theme_color_override("font_color",
			UIStyle.BONES if item.id == _selected else UIStyle.TEXT_DIM)
		var id := item.id
		button.pressed.connect(func() -> void:
			_selected = id
			rebuild())
		_item_list.add_child(button)
	_rebuild_nodes()

func _items_with_trees() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in Progression.owned_items():
		if not ItemDB.augments_for(item.id).is_empty():
			out.append(item)
	return out

func _rebuild_nodes() -> void:
	for child in _node_list.get_children():
		child.queue_free()

	if _selected == &"":
		_node_list.add_child(UIStyle.label("Buy a toy to start upgrading it.", 12, UIStyle.TEXT_DIM))
		return

	for node in ItemDB.augments_for(_selected):
		_node_list.add_child(_make_row(node))
	refresh()

func _make_row(node: AugmentNode) -> Control:
	var row_panel := PanelContainer.new()
	UIStyle.apply_panel(row_panel, UIStyle.BG_RAISED)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row_panel.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)

	var title := UIStyle.label(node.display_name, 13)
	text.add_child(title)
	var detail := UIStyle.label(_effect_text(node), 10, UIStyle.TEXT_DIM)
	text.add_child(detail)

	var level := UIStyle.label("0/%d" % node.max_levels, 12, UIStyle.TEXT_DIM)
	level.custom_minimum_size = Vector2(44, 0)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(level)

	var buy := UIStyle.button("", 12)
	buy.custom_minimum_size = Vector2(104, 30)
	buy.pressed.connect(func() -> void:
		var levels := node.max_levels if _bulk < 0 else _bulk
		Progression.purchase_augment(node.id, levels))
	row.add_child(buy)

	row_panel.set_meta(&"node_id", node.id)
	row_panel.set_meta(&"level_label", level)
	row_panel.set_meta(&"buy_button", buy)
	return row_panel

## "+15% damage per level" / "-5% time between uses per level", derived from the data so a
## new augment needs no copy written for it.
func _effect_text(node: AugmentNode) -> String:
	var word: String = EFFECT_WORDS.get(node.effect_key, String(node.effect_key))
	var percent := (node.effect_per_level - 1.0) * 100.0
	var sign_text := "+" if percent >= 0.0 else ""
	return "%s%.0f%% %s per level" % [sign_text, percent, word]

func refresh() -> void:
	for row_panel in _node_list.get_children():
		if not row_panel.has_meta(&"node_id"):
			continue
		var node := ItemDB.get_augment(row_panel.get_meta(&"node_id"))
		if node == null:
			continue
		var level_label := row_panel.get_meta(&"level_label") as Label
		var buy := row_panel.get_meta(&"buy_button") as Button
		var owned := Progression.augment_level(node.id)
		level_label.text = "%d/%d" % [owned, node.max_levels]

		var reason := Progression.augment_lock_reason(node.id)
		if not reason.is_empty():
			buy.text = "MAX" if reason == "maxed" else reason.to_upper()
			buy.disabled = true
			buy.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
			continue

		var want := node.max_levels if _bulk < 0 else _bulk
		var can_buy := AugmentMath.purchasable_levels(
			float(node.cost_base), node.cost_growth, owned, node.max_levels,
			Economy.balance_of(node.currency_id()), want)
		var quoted := maxi(1, mini(want, node.max_levels - owned))
		var cost := EconomyMath.bulk_cost(float(node.cost_base), node.cost_growth, owned, quoted)

		# The button always quotes the price of what it would buy, even when the player
		# cannot afford it — a disabled button with no number tells them nothing.
		buy.text = "x%d  %s" % [quoted, UIStyle.format_amount(cost)]
		buy.disabled = can_buy <= 0
		buy.add_theme_color_override("font_color",
			UIStyle.AFFORDABLE if can_buy > 0 else UIStyle.TEXT_DIM)
