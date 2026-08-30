class_name ShopPanel
extends PanelPage

## The toy box: categories across the top, a list down the left, and the thing you picked
## filling the right.
##
## Every tile is generated from ItemDB — there is no per-item code here and there must
## never be (docs/decisions.md D8). The prototype's version of this file had seven
## hardcoded handlers and a preload each, which is why it stalled at seven items.
##
## The list is deliberately thin: a picture, a name, a price. It used to carry every item's
## description as two wrapped lines, which is thirteen paragraphs of prose stacked on one
## card — correct, and unreadable. The words now live in the detail pane, one item's worth
## at a time, where there is room to set them large.

## Short enough to sit under a 32px sprite without wrapping. "Cursor Powers" became
## "Cursor" for that reason and nothing was lost — the picture says the rest.
const CATEGORY_NAMES := {
	ItemData.CATEGORY_WEAPON: "Melee",
	ItemData.CATEGORY_THROWABLE: "Boom",
	ItemData.CATEGORY_CURSOR_POWER: "Cursor",
	ItemData.CATEGORY_TURRET: "Turret",
	ItemData.CATEGORY_CRITTER: "Critters",
	# "Kind" was this drawer's name back when it was the only kind drawer. It is now the name
	# of the whole side, and this one holds what you do with your own hands.
	ItemData.CATEGORY_FRIENDLY: "Care",
	ItemData.CATEGORY_TOY: "Play",
	ItemData.CATEGORY_COMFORT: "Comfort",
	ItemData.CATEGORY_FOOD: "Food",
	ItemData.CATEGORY_AMBIENCE: "Mood",
}

## The two front doors.
##
## Ten categories will not fit across a card this narrow, and they should not have to: the
## first decision a player makes is not "melee or turrets", it is what kind of session they
## are having. Splitting that off means each side gets a strip of about five, which is the
## width the tabs were designed for — and the kind half stops being one tab hiding at the
## end of a row of weapons.
const SIDE_NAMES := {
	ItemData.SIDE_HARM: "Harm",
	ItemData.SIDE_KIND: "Kind",
}

const SIDE_GLYPHS := {
	ItemData.SIDE_HARM: &"bone",
	ItemData.SIDE_KIND: &"heart",
}

## Wide enough for the longest item name at the reading size, narrow enough to leave the
## detail pane the larger half.
const LIST_WIDTH := 232

var _side_row: HBoxContainer
var _side_tabs: Dictionary = {}   ## int (side) -> Button
var _side: int = ItemData.SIDE_HARM
var _tab_row: HBoxContainer
var _list: VBoxContainer
var _rows: Dictionary = {}   ## StringName -> Button
var _tabs: Dictionary = {}   ## int (category) -> Dictionary {button, badge, count, shown}
var _by_category: Dictionary = {}
var _category: int = -1
var _selected: StringName = &""

# --- the detail pane ---
var _detail_sprite: TextureRect
var _detail_name: Label
var _detail_kind: Label
var _detail_body: Label
var _detail_action: Button
var _detail_note: Label
var _mastery_box: PanelContainer
var _mastery_label: Label
var _mastery_bar: ProgressBar

func _ready() -> void:
	# `currency_changed` fires on every hit and once a second per currency from automation,
	# forever. PanelPage drops the repaint while the card is shut; without that this page
	# re-themed its whole list in the background for the life of the session.
	EventBus.currency_changed.connect(func(_c: StringName, _b: float) -> void: request_refresh())
	EventBus.item_purchased.connect(_on_item_purchased)
	EventBus.cursor_power_changed.connect(func(_id: StringName) -> void: request_refresh())
	super()

func _build_page() -> void:
	add_theme_constant_override("separation", 8)
	for item in ItemDB.all_items():
		if not _by_category.has(item.category):
			_by_category[item.category] = []
		_by_category[item.category].append(item)

	_side_row = HBoxContainer.new()
	_side_row.add_theme_constant_override("separation", 3)
	add_child(_side_row)
	for side in [ItemData.SIDE_HARM, ItemData.SIDE_KIND]:
		var tile := _make_side_tile(side)
		_side_tabs[side] = tile
		_side_row.add_child(tile)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 3)
	add_child(_tab_row)

	var categories := _by_category.keys()
	categories.sort()
	for category in categories:
		_tab_row.add_child(_make_tab(category, _by_category[category]))

	add_child(_rule())

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var scroll := ScrollContainer.new()
	# SHOW_NEVER, not DISABLED. A ScrollContainer with an axis *disabled* folds its
	# child's minimum size into its own, so one long unwrapped line on one page would
	# push the card wider than every other page's — which is exactly the resizing the
	# fixed card exists to stop.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	split.add_child(_detail_pane())

	if not categories.is_empty():
		show_side(_side)

func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = UIStyle.EDGE
	rule.custom_minimum_size = Vector2(0, UIStyle.BORDER_WIDTH)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

# --- categories ------------------------------------------------------------

func _make_tab(category: int, items: Array) -> Button:
	var tab := UIStyle.button(CATEGORY_NAMES.get(category, "Other"), UIStyle.MICRO)
	tab.theme_type_variation = &"IconTab"
	tab.toggle_mode = true
	tab.custom_minimum_size = Vector2(0, 60)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Icon above caption. The picture is the label; the word is the caption on the picture.
	tab.icon = _category_icon(items)
	tab.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	if _has_art(items):
		UIStyle.art_icons(tab)
	tab.pressed.connect(func() -> void: show_category(category))

	# Anchored *and given an explicit rect*: a Button is not a Container, so nothing lays
	# this out or sizes it — a child of a plain Control keeps whatever size it was created
	# with, which is zero.
	var badge := PanelContainer.new()
	badge.theme_type_variation = &"Badge"
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	badge.offset_left = -24.0
	badge.offset_top = -6.0
	badge.offset_right = 4.0
	badge.offset_bottom = 15.0
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	var count := UIStyle.label("0", UIStyle.MICRO, UIStyle.PANEL)
	count.theme_type_variation = &"Numeral"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(count)
	tab.add_child(badge)

	_tabs[category] = {"button": tab, "badge": badge, "count": count, "shown": 0}
	return tab

## The first item in the category that actually has art. Data-driven so a category's face
## changes on its own when its first item is drawn.
func _category_icon(items: Array) -> Texture2D:
	for item in items:
		if item.icon != null:
			return UIStyle.boxed(item.icon, ROW_ICON)
	return UIStyle.item_face(items[0] if not items.is_empty() else null, ROW_ICON)

func _has_art(items: Array) -> bool:
	for item in items:
		if item.icon != null:
			return true
	return false

## The side tile is a tab, not a picture: same variation as the category tabs, so it picks up
## the theme's `hover_pressed` like everything else. A variation the theme does not define
## falls through to Godot's stock dark theme rather than to anything neutral, which is how
## every toggled-on button in the shell once drew dark ink on a dark box.
func _make_side_tile(side: int) -> Button:
	var tile := UIStyle.button(String(SIDE_NAMES.get(side, "Other")), UIStyle.BODY)
	tile.theme_type_variation = &"IconTab"
	tile.toggle_mode = true
	tile.custom_minimum_size = Vector2(0, 44)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Boxed, like every other picture in the shell: a Button *grows* to fit its icon, so an
	# unboxed one sets the tile's height rather than the other way round (D27).
	tile.icon = UIStyle.boxed(UIStyle.glyph(StringName(SIDE_GLYPHS.get(side, &"crate"))),
		UIStyle.GLYPH)
	tile.pressed.connect(func() -> void: show_side(side))
	return tile

## Switches which half of the shop the tab strip is showing. The tabs are all built once and
## hidden rather than rebuilt, so the unread badges keep counting on the side you are not
## looking at — which is the entire point of a badge.
func show_side(side: int) -> void:
	_side = side
	for key in _side_tabs:
		(_side_tabs[key] as Button).button_pressed = key == side
	var first := -1
	var categories := _by_category.keys()
	categories.sort()
	for category in categories:
		var visible_here: bool = ItemData.CATEGORY_SIDE.get(category, ItemData.SIDE_HARM) == side
		if _tabs.has(category):
			(_tabs[category]["button"] as Button).visible = visible_here
		if visible_here and first < 0:
			first = int(category)
	# Only move off the current category if it belongs to the other side now. Coming back to
	# a side you were already on should land where you left it.
	if _category < 0 or ItemData.CATEGORY_SIDE.get(_category, ItemData.SIDE_HARM) != side:
		if first >= 0:
			show_category(first)
	else:
		show_category(_category)

func show_category(category: int) -> void:
	if not _by_category.has(category):
		return
	_category = category
	for key in _tabs:
		(_tabs[key]["button"] as Button).button_pressed = key == category
	_rebuild_list()
	UIMotion.page_in(_list)

func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()

	var items: Array = _by_category.get(_category, [])
	for item in items:
		_list.add_child(_make_row(item))
	select(items[0].id if not items.is_empty() else &"")

# --- the list --------------------------------------------------------------

## Every row is this tall and its icon is exactly this wide, whatever the item's art is.
## Two constants rather than two accidents: a Button grows to fit its icon, so before these
## a single 64px PNG made its row nearly twice the height of the row under it and pushed
## that row's name 30px further right than its neighbours'.
## Sized so the art fits at its native size. An item icon is a 32px canvas, and asking for
## it in a 24px box does not crop it — `boxed()` steps it down by a whole number, which is
## a *halving* to 16px. Two thirds of every icon in the shop was being thrown away to satisfy
## a box size picked out of the air. The box follows the art, not the other way round.
const ROW_ICON := UIStyle.ICON_CANVAS
## The icon plus the ListRow stylebox's own margins (5 + 5) and its rule (1).
const ROW_HEIGHT := UIStyle.ICON_CANVAS + 12

## How much of a row's right edge belongs to the price. The name is clipped before it, by
## the `ListRow` stylebox's right content margin — `clip_text` alone clips at the row's own
## edge, which let a long name run straight under its own cost.
const PRICE_LANE := 96

func _make_row(item: ItemData) -> Button:
	var row := UIStyle.button(item.display_name, UIStyle.MICRO)
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.icon = UIStyle.item_face(item, ROW_ICON)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.clip_text = true
	# An ellipsis rather than a hard cut. The row has always clipped — `ui_stress` even
	# tests it with the name "Chocolate Fountain" — but until M3.5-A no real item was long
	# enough to hit it, and a name sheared mid-word ("Chocolate Fou") reads as a broken
	# label rather than as a name that did not fit. Three of the twelve new items are over
	# the budget, and the shortest honest name for a massage chair is "Massage Chair".
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.tooltip_text = item.display_name
	if UIStyle.has_art(item):
		UIStyle.art_icons(row)
	row.pressed.connect(func() -> void: select(item.id))
	UIMotion.hook(row)

	# The price rides on the row's right edge. Anchored with explicit offsets for the same
	# reason the category badge is: a Button lays nothing out.
	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 4)
	price.alignment = BoxContainer.ALIGNMENT_END
	price.set_anchors_preset(Control.PRESET_RIGHT_WIDE, true)
	price.offset_left = -float(PRICE_LANE)
	price.offset_right = -10.0
	price.offset_top = 0.0
	price.offset_bottom = 0.0
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(price)

	var mark := UIStyle.icon(&"bone", UIStyle.GLYPH, UIStyle.BONES)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.add_child(mark)
	var value := UIStyle.label("", UIStyle.MICRO, UIStyle.BONES)
	value.theme_type_variation = &"Numeral"
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.add_child(value)

	row.set_meta(&"mark", mark)
	row.set_meta(&"value", value)
	_rows[item.id] = row
	return row

func select(item_id: StringName) -> void:
	_selected = item_id
	for key in _rows:
		(_rows[key] as Button).button_pressed = key == item_id
	_refresh()
	if item_id != &"":
		UIMotion.punch(_detail_sprite, 1.12)

# --- the detail pane -------------------------------------------------------

func _detail_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_theme_constant_override("separation", 8)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	pane.add_child(top)

	var well := PanelContainer.new()
	well.theme_type_variation = &"Sunk"
	well.custom_minimum_size = Vector2(UIStyle.WELL_HERO, UIStyle.WELL_HERO)
	well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(well)
	_detail_sprite = UIStyle.sprite(null, UIStyle.WELL_HERO - 8)
	well.add_child(_detail_sprite)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_theme_constant_override("separation", 2)
	top.add_child(heading)
	_detail_name = UIStyle.label("", UIStyle.NAME)
	_detail_name.theme_type_variation = &"NameLabel"
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_detail_name)
	_detail_kind = UIStyle.eyebrow("")
	heading.add_child(_detail_kind)

	# Set at the reading size, in the reading face, with room to breathe — which is the
	# entire point of moving it off the list.
	_detail_body = UIStyle.body("", UIStyle.NAME)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pane.add_child(_detail_body)

	# What you have done with it, for something you already own. The shop and the tree are
	# the same object seen twice — an item's mastery is the reason to keep using it — and
	# a detail pane that says nothing about a toy you have had for an hour is a hole.
	_mastery_box = PanelContainer.new()
	_mastery_box.theme_type_variation = &"Sunk"
	_mastery_box.visible = false
	pane.add_child(_mastery_box)

	var mastery_column := VBoxContainer.new()
	mastery_column.add_theme_constant_override("separation", 5)
	_mastery_box.add_child(mastery_column)

	var mastery_row := HBoxContainer.new()
	mastery_row.add_theme_constant_override("separation", 6)
	mastery_column.add_child(mastery_row)
	mastery_row.add_child(UIStyle.icon(&"star", UIStyle.GLYPH, UIStyle.BONES))
	_mastery_label = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	_mastery_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mastery_label.clip_text = true
	mastery_row.add_child(_mastery_label)

	_mastery_bar = ProgressBar.new()
	_mastery_bar.max_value = 1.0
	_mastery_bar.step = 0.001
	_mastery_bar.show_percentage = false
	_mastery_bar.custom_minimum_size = Vector2(0, 10)
	_mastery_bar.add_theme_stylebox_override("fill", UIStyle.meter_fill(UIStyle.BONES))
	mastery_column.add_child(_mastery_bar)

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(gap)

	_detail_note = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	_detail_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pane.add_child(_detail_note)

	_detail_action = UIStyle.button("", UIStyle.LABEL)
	_detail_action.theme_type_variation = &"BuyButton"
	_detail_action.custom_minimum_size = Vector2(0, 44)
	_detail_action.pressed.connect(_on_action_pressed)
	pane.add_child(_detail_action)
	UIMotion.hook(_detail_action, null, _detail_sprite)
	return pane

## One handler for every item in the game, because the item id is data rather than a
## method name. This is the whole point of the rewrite.
func _on_action_pressed() -> void:
	var item := ItemDB.get_item(_selected)
	if item == null:
		return

	if Progression.is_unlocked(_selected):
		EventBus.spawn_requested.emit(_selected, Vector2.ZERO)
		UIMotion.punch(_detail_sprite, 1.35)
		return

	# A refusal is a reaction, not a silence. The button stays live even when the price is
	# out of reach precisely so that pressing it can say no — a disabled control swallows
	# the click and teaches the player nothing.
	if not Progression.can_purchase(_selected) or not Progression.purchase_item(_selected):
		UIMotion.buzz(_detail_action)
		return

	UIMotion.confirm(_detail_sprite)
	EventBus.ui_spend.emit(item.currency_id(), float(item.cost),
		UIScale.screen_centre(_detail_action))

func _on_item_purchased(item_id: StringName) -> void:
	request_refresh()
	if item_id == _selected:
		UIMotion.punch(_detail_sprite, 1.4)

# --- state -----------------------------------------------------------------

func _refresh() -> void:
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	var active_power: StringName = spawner.active_power() if spawner else &""
	var affordable := {}

	for category in _by_category:
		for item in _by_category[category]:
			if not Progression.is_unlocked(item.id) and Progression.can_purchase(item.id) \
					and Economy.can_afford(item.currency_id(), float(item.cost)):
				affordable[category] = int(affordable.get(category, 0)) + 1
	_refresh_badges(affordable)

	for key in _rows:
		_refresh_row(_rows[key] as Button, ItemDB.get_item(key))
	_refresh_detail(active_power)

func _refresh_row(row: Button, item: ItemData) -> void:
	if item == null:
		return
	var mark := row.get_meta(&"mark") as TextureRect
	var value := row.get_meta(&"value") as Label
	if Progression.is_unlocked(item.id):
		# Owned: no price, a tick. The list is scanned for what is still to buy.
		UIStyle.set_sprite(mark, UIStyle.glyph(&"check"))
		mark.modulate = UIStyle.AFFORDABLE
		value.text = ""
		row.modulate = Color.WHITE
		return
	if not Progression.can_purchase(item.id):
		UIStyle.set_sprite(mark, UIStyle.glyph(&"lock"))
		mark.modulate = UIStyle.TEXT_DIM
		value.text = ""
		# Not `modulate`: fading a row is the same contrast bug as fading disabled text.
		# The padlock is what says it is locked.
		row.modulate = Color.WHITE
		return
	var currency := item.currency_id()
	var can := Economy.can_afford(currency, float(item.cost))
	UIStyle.set_sprite(mark, UIStyle.currency_glyph(currency))
	mark.modulate = UIStyle.currency_colour(currency) if can else UIStyle.TEXT_DIM
	value.text = UIStyle.format_amount(item.cost)
	value.add_theme_color_override("font_color",
		UIStyle.currency_colour(currency) if can else UIStyle.TEXT_DIM)
	row.modulate = Color.WHITE

func _refresh_detail(active_power: StringName) -> void:
	var item := ItemDB.get_item(_selected)
	if item == null:
		_detail_name.text = ""
		_detail_kind.text = ""
		_detail_body.text = ""
		_detail_note.text = ""
		_detail_sprite.texture = null
		_detail_action.visible = false
		return

	_detail_action.visible = true
	UIStyle.set_sprite(_detail_sprite, _big_art(item))
	_detail_sprite.modulate = Color.WHITE if UIStyle.has_art(item) \
		else Color(UIStyle.TEXT_DIM, 0.8)
	_detail_name.text = item.display_name
	_detail_kind.text = CATEGORY_NAMES.get(item.category, "Other")
	_detail_body.text = item.description
	_detail_note.text = ""
	_refresh_mastery(item)

	if Progression.is_unlocked(item.id):
		if item.is_cursor_power():
			var equipped := active_power == item.id
			_detail_action.text = "Unequip" if equipped else "Equip"
			_detail_action.icon = UIStyle.glyph(&"hand")
		else:
			_detail_action.text = "Spawn"
			_detail_action.icon = UIStyle.glyph(&"spawn")
		_detail_action.disabled = false
		UIStyle.tint_button(_detail_action, UIStyle.TEXT)
		return

	# Requirements unmet. This one really is inert: there is no price to quote and no
	# amount of money that would change the answer today.
	if not Progression.can_purchase(item.id):
		_detail_action.text = "Locked"
		_detail_action.icon = UIStyle.glyph(&"lock")
		_detail_action.disabled = true
		UIStyle.tint_button(_detail_action, UIStyle.TEXT_DIM)
		_detail_note.text = _requirement_text(item)
		return

	var currency := item.currency_id()
	var can := Economy.can_afford(currency, float(item.cost))
	_detail_action.text = UIStyle.format_amount(item.cost)
	_detail_action.icon = UIStyle.currency_glyph(currency)
	_detail_action.disabled = false
	UIStyle.tint_button(_detail_action, UIStyle.currency_colour(currency) if can
		else UIStyle.TEXT_DIM)
	if not can:
		var short := float(item.cost) - Economy.balance_of(currency)
		_detail_note.text = "%s SHORT" % UIStyle.format_amount(short)

## Mastery, upgrades bought, and what the next rank opens — for something already owned.
## A toy you have not bought has no history, so the block is simply absent rather than
## showing three zeroes.
func _refresh_mastery(item: ItemData) -> void:
	var owned := Progression.is_unlocked(item.id)
	var nodes := ItemDB.augments_for(item.id)
	_mastery_box.visible = owned and not nodes.is_empty()
	if not _mastery_box.visible:
		return
	var bought := 0
	var total := 0
	for node in nodes:
		bought += Progression.augment_level(node.id)
		total += node.max_levels
	_mastery_label.text = "MASTERY %d  \u00b7  %d / %d UPGRADES" % [
		Progression.mastery_rank(item.id), bought, total]
	_mastery_bar.value = Progression.mastery_progress(item.id)

## What is standing between the player and this item, named. "Locked" on its own is the
## least useful word a shop can print.
func _requirement_text(item: ItemData) -> String:
	var missing: Array[String] = []
	for requirement in item.requires:
		if not Progression.is_unlocked(requirement):
			var other := ItemDB.get_item(requirement)
			missing.append(other.display_name.to_upper() if other else String(requirement))
	if missing.is_empty():
		return ""
	return "NEEDS %s FIRST" % ", ".join(missing)

## The 64px sprite where there is one — the detail well is 72px and this is the one place
## in the shell that shows the big art.
func _big_art(item: ItemData) -> Texture2D:
	var box := int(_detail_sprite.custom_minimum_size.x)
	var path := "res://Assets/sprites/items/%s.png" % item.id
	if ResourceLoader.exists(path):
		return UIStyle.boxed(ResourceLoader.load(path) as Texture2D, box)
	return UIStyle.item_face(item, box)

## The count of what is affordable inside each category. It pops when it goes up, because
## the moment a new toy comes into reach is the moment the shop is worth opening — and the
## player is usually looking at the buddy, not at the tab row.
func _refresh_badges(counts: Dictionary) -> void:
	for category in _tabs:
		var entry: Dictionary = _tabs[category]
		var count := int(counts.get(category, 0))
		var badge := entry["badge"] as Control
		(entry["count"] as Label).text = str(count)
		var was := int(entry["shown"])
		badge.visible = count > 0
		entry["shown"] = count
		if count > was and badge.visible:
			UIMotion.punch(badge, 1.5)
