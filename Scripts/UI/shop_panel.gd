class_name ShopPanel
extends VBoxContainer

## The toy box. Every tile is generated from ItemDB — there is no per-item code here and
## there must never be (docs/decisions.md D8). The prototype's version of this file had
## seven hardcoded handlers and a preload each, which is why it stalled at seven items.

const CATEGORY_NAMES := {
	ItemData.CATEGORY_WEAPON: "MELEE",
	ItemData.CATEGORY_THROWABLE: "EXPLOSIVES",
	ItemData.CATEGORY_CURSOR_POWER: "CURSOR POWERS",
	ItemData.CATEGORY_FRIENDLY: "FRIENDLY",
	ItemData.CATEGORY_TOY: "TOYS & PROPS",
}

## Tiles are built once and only refreshed, because rebuilding the whole list on every
## currency_changed would rebuild it several times a second during active play.
var _tiles: Dictionary = {}  ## StringName -> Dictionary of the tile's live controls

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build()
	EventBus.currency_changed.connect(func(_c: StringName, _b: float) -> void: refresh())
	EventBus.item_purchased.connect(func(_id: StringName) -> void: refresh())
	EventBus.cursor_power_changed.connect(func(_id: StringName) -> void: refresh())

func _build() -> void:
	var by_category := {}
	for item in ItemDB.all_items():
		if not by_category.has(item.category):
			by_category[item.category] = []
		by_category[item.category].append(item)

	var categories := by_category.keys()
	categories.sort()
	for category in categories:
		add_child(UIStyle.label(CATEGORY_NAMES.get(category, "OTHER"), 11, UIStyle.TEXT_DIM))
		var grid := VBoxContainer.new()
		grid.add_theme_constant_override("separation", 4)
		add_child(grid)
		for item in by_category[category]:
			grid.add_child(_make_tile(item))
	refresh()

func _make_tile(item: ItemData) -> Control:
	var tile := PanelContainer.new()
	UIStyle.apply_panel(tile, UIStyle.BG_RAISED)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	tile.add_child(row)

	if item.icon:
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(UIStyle.label(item.display_name, 14))
	var subtitle := UIStyle.label(item.description, 10, UIStyle.TEXT_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(220, 0)
	text.add_child(subtitle)

	var action := UIStyle.button("", 12)
	action.custom_minimum_size = Vector2(96, 30)
	action.pressed.connect(_on_tile_pressed.bind(item.id))
	row.add_child(action)

	_tiles[item.id] = {"action": action, "subtitle": subtitle}
	return tile

## One handler for every item in the game, because the item id is data rather than a
## method name. This is the whole point of the rewrite.
func _on_tile_pressed(item_id: StringName) -> void:
	if Progression.is_unlocked(item_id):
		EventBus.spawn_requested.emit(item_id, Vector2.ZERO)
	else:
		Progression.purchase_item(item_id)

func refresh() -> void:
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	var active_power: StringName = spawner.active_power() if spawner else &""

	for key in _tiles:
		var item_id := StringName(key)
		var item := ItemDB.get_item(item_id)
		var action := _tiles[key]["action"] as Button
		if item == null:
			continue
		if Progression.is_unlocked(item_id):
			if item.is_cursor_power():
				var equipped := active_power == item_id
				action.text = "Unequip" if equipped else "Equip"
				action.disabled = false
			else:
				action.text = "Spawn"
				action.disabled = false
			action.add_theme_color_override("font_color", UIStyle.TEXT)
		elif not Progression.can_purchase(item_id):
			action.text = "Locked"
			action.disabled = true
			action.add_theme_color_override("font_color", UIStyle.LOCKED)
		else:
			var affordable := Economy.can_afford(item.currency_id(), float(item.cost))
			action.text = "%s %s" % [UIStyle.format_amount(item.cost), _currency_word(item)]
			action.disabled = not affordable
			action.add_theme_color_override("font_color",
				UIStyle.AFFORDABLE if affordable else UIStyle.TEXT_DIM)

func _currency_word(item: ItemData) -> String:
	return "H" if item.currency == ItemData.CURRENCY_HEARTS else "B"
