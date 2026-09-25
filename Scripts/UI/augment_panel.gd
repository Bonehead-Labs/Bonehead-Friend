class_name AugmentPanel
extends PanelPage

## The tree. One UI for every item's augments, because every tree has the same shape
## (docs/economy.md) — that identical shape is what makes three flavours per weapon nearly
## free, and it only pays off if there is exactly one panel for all of them.
##
## Drawn as a tree rather than as a list ("Upgrades B", picked at the end of M3). The list
## was correct and unreadable: three ordinary buy buttons in a row is how a player finds
## out that tier 2 is a permanent choice by making it. Here the wires fan into a single
## trunk, the trunk runs through a black gate strip, and once the choice is made the two
## branches not taken are struck through and stay on screen. The shape is the warning.

## Human wording for an effect_key. Adding an effect means adding a line here; adding an
## augment does not.
const EFFECT_WORDS := {
	&"damage_mult": "damage",
	&"payout_mult": "Bones earned",
	&"mass_mult": "weight",
	&"cooldown_mult": "time between uses",
}

## The same keys, worded for the kindness half of the roster. A Hearts item's `damage_mult`
## is the size of its kindness and its `payout_mult` pays Hearts — printing "+15% damage" on
## the open hand names a currency it never earns and a verb it never does.
const HEARTS_EFFECT_WORDS := {
	&"damage_mult": "kindness",
	&"payout_mult": "Hearts earned",
}

## And for a node attached to no item at all: it multiplies every payout in the game, so
## naming either currency is wrong in one direction.
const GLOBAL_EFFECT_WORDS := {
	&"payout_mult": "everything earned",
}

## What the global tree is called on screen. It is not an item, so it has no display_name
## to borrow.
const GLOBAL_NAME := "Everything"

## Past this many levels the pips stop being countable at a glance and the figure is
## clearer. Ten-level nodes — which is every tier-1 node in the game — stay pips.
const PIP_LIMIT := 12

signal content_changed

var _weapons: VBoxContainer
var _tree: VBoxContainer
## Held for `scroll_to_end()`: an item's capstone is the last thing on a tall page, and the
## capture tools cannot review what they cannot scroll to.
var _scroll: ScrollContainer
var _selected: StringName = &""
var _bulk: int = 1
var _bulk_row: HBoxContainer

## The hero: which toy's tree this is, how mastered it is, and what mastery is about to
## unlock. Ranks are what stop a new tier obsoleting an old toy and the shared pool is what
## makes using a *variety* of them worth more than grinding one — neither is visible in the
## augment rows, so a player would experience both as numbers quietly drifting.
var _hero_sprite: TextureRect
var _hero_name: Label
var _hero_rank: Label
## Held so it can be hidden: a mastery star over a tree with no mastery is a promise the
## page cannot keep.
var _rank_star: TextureRect
var _mastery_bar: ProgressBar
var _unlocks: HBoxContainer
var _pool_label: Label
## The picture inside a toy chip. WELL_TILE is the chip; this is what sits in it.
const CHIP_ICON := 32

## The rank the star is currently showing, and **which toy it belongs to**. Keyed to the
## panel alone it fired a rank-up celebration for simply selecting a higher-mastery toy —
## the memory has to travel with the selection, not with the page.
var _shown_rank: int = -1
var _shown_rank_for: StringName = &""

func _ready() -> void:
	EventBus.currency_changed.connect(func(_c: StringName, _b: float) -> void: request_refresh())
	# Rebuilt rather than refreshed: taking an exclusive branch restyles the whole tier,
	# strikes out two cards and redraws the gate, none of which _refresh() tracks.
	EventBus.augment_purchased.connect(_on_augment_purchased)
	EventBus.item_purchased.connect(func(_id: StringName) -> void: request_rebuild())
	EventBus.mastery_rank_up.connect(func(_id: StringName, _r: int) -> void: request_refresh())
	EventBus.prestige_performed.connect(func(_gained: int) -> void: request_rebuild())
	super()

func _build_page() -> void:
	add_theme_constant_override("separation", 8)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	# --- which toy ---
	#
	# A column of pictures, not a column of names. The player picked these things up and
	# hit somebody with them; they know the mace by its shape long before they know it is
	# called a mace. Narrow, so the tree gets the rest of the card.
	var picker := ScrollContainer.new()
	picker.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	picker.custom_minimum_size = Vector2(UIStyle.WELL_TILE + 8, 0)
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(picker)
	_weapons = VBoxContainer.new()
	_weapons.add_theme_constant_override("separation", 3)
	picker.add_child(_weapons)

	var rule := ColorRect.new()
	rule.color = Color(UIStyle.EDGE, 0.25)
	rule.custom_minimum_size = Vector2(1, 0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.add_child(rule)

	var scroll := ScrollContainer.new()
	# SHOW_NEVER, not DISABLED. A ScrollContainer with an axis *disabled* folds its
	# child's minimum size into its own, so one long unwrapped line on one page would
	# push the card wider than every other page's — which is exactly the resizing the
	# fixed card exists to stop.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_scroll = scroll

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	# --- mastery ---
	var hero := PanelContainer.new()
	hero.theme_type_variation = &"Tile"
	column.add_child(hero)

	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 10)
	hero.add_child(hero_row)

	var well := PanelContainer.new()
	well.theme_type_variation = &"Sunk"
	well.custom_minimum_size = Vector2(UIStyle.WELL_HERO, UIStyle.WELL_HERO)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_row.add_child(well)
	_hero_sprite = UIStyle.sprite(null, UIStyle.WELL_HERO - 8)
	well.add_child(_hero_sprite)

	var hero_text := VBoxContainer.new()
	hero_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_text.add_theme_constant_override("separation", 5)
	hero_row.add_child(hero_text)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	hero_text.add_child(name_row)
	_hero_name = UIStyle.label("", UIStyle.NAME)
	_hero_name.theme_type_variation = &"NameLabel"
	_hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_hero_name)
	_rank_star = UIStyle.icon(&"star", 16, UIStyle.BONES)
	name_row.add_child(_rank_star)
	_hero_rank = UIStyle.label("0", UIStyle.LABEL, UIStyle.BONES)
	_hero_rank.theme_type_variation = &"Numeral"
	name_row.add_child(_hero_rank)

	_mastery_bar = ProgressBar.new()
	_mastery_bar.max_value = 1.0
	_mastery_bar.step = 0.001
	_mastery_bar.show_percentage = false
	_mastery_bar.custom_minimum_size = Vector2(0, 14)
	_mastery_bar.add_theme_stylebox_override("fill", UIStyle.meter_fill(UIStyle.BONES))
	hero_text.add_child(_mastery_bar)

	# What mastery is *for*, as three marks rather than a sentence. A tick is a door you
	# have already opened; a padlock is one you have not.
	_unlocks = HBoxContainer.new()
	_unlocks.add_theme_constant_override("separation", 12)
	hero_text.add_child(_unlocks)

	# --- bulk, and what the shared pool is worth ---
	#
	# Bulk buying has to exist from day one — retrofitting it is where the "Buy x10 that
	# quietly overcharges" bug comes from. The maths is closed-form and unit-tested.
	_bulk_row = HBoxContainer.new()
	_bulk_row.add_theme_constant_override("separation", 4)
	column.add_child(_bulk_row)
	_bulk_row.add_child(UIStyle.eyebrow("Buy"))
	for amount in [1, 10, -1]:
		var button := UIStyle.button("Max" if amount < 0 else "x%d" % amount, UIStyle.MICRO)
		button.theme_type_variation = &"GhostButton"
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(44, 24)
		button.button_pressed = amount == _bulk
		button.pressed.connect(func() -> void:
			_bulk = amount
			_sync_bulk_buttons()
			_refresh())
		_bulk_row.add_child(button)

	# Its own line, left-aligned. Sharing the bulk row meant it was right-aligned into
	# whatever width was left over, and `clip_text` then ate the front of it — a figure
	# line reading "OME X1.06" is worse than no figure line.
	#
	# Also Silkscreen, because it is figures.
	_pool_label = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	_pool_label.clip_text = true
	column.add_child(_pool_label)

	_tree = VBoxContainer.new()
	_tree.add_theme_constant_override("separation", 0)
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_tree)

	_rebuild()

func _sync_bulk_buttons() -> void:
	var amounts := [1, 10, -1]
	var index := 0
	for child in _bulk_row.get_children():
		if child is Button:
			(child as Button).button_pressed = amounts[index] == _bulk
			index += 1

# --- the toy picker --------------------------------------------------------

## Rebuilt rather than refreshed when the roster changes, which is rare — buying an item
## adds a whole tree.
func _rebuild() -> void:
	for child in _weapons.get_children():
		child.queue_free()

	var owned := _items_with_trees()
	var ids: Array[StringName] = []
	for item in owned:
		ids.append(item.id)
	# Last, not first. The picker is ordered by what the player owns, and the global tree is
	# the one entry that is not a toy — putting it at the top made it the default selection,
	# so opening Upgrades showed a stranger two unaffordable nodes instead of showing them
	# their bat.
	if not ItemDB.augments_for(AugmentNode.GLOBAL).is_empty():
		ids.append(AugmentNode.GLOBAL)

	if ids.is_empty():
		_selected = &""
	elif not ids.has(_selected):
		_selected = ids[0]

	for id in ids:
		var item := ItemDB.get_item(id)
		var chip := UIStyle.button("", UIStyle.MICRO)
		chip.theme_type_variation = &"IconTab"
		chip.toggle_mode = true
		chip.button_pressed = id == _selected
		chip.custom_minimum_size = Vector2(UIStyle.WELL_TILE, UIStyle.WELL_TILE)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The chip is WELL_TILE square and its picture is CHIP_ICON square, always. A chip
		# whose icon set its own size made the toy column a different width per category.
		if item == null:
			# The global tree has no ItemData and never will: it is not a thing you own, it
			# is what you have learned. It rides the same picker because it is the same
			# question — what do I upgrade next — and inventing a second tree UI for four
			# nodes would be four nodes' worth of content and a page's worth of code.
			# Boxed to the chip's own icon size like every other picture in the shell (D27):
			# a bare 16px glyph handed to a Button draws at 16px inside a 32px box, which
			# here read as an empty chip. And *not* `art_icons` — this is a glyph, so it
			# takes the theme's ink rather than the full white item art needs.
			UIStyle.set_icon(chip, UIStyle.glyph(&"bolt"), CHIP_ICON)
			chip.tooltip_text = GLOBAL_NAME
		else:
			UIStyle.set_icon(chip, UIStyle.item_face(item, CHIP_ICON), CHIP_ICON)
			if UIStyle.has_art(item):
				UIStyle.art_icons(chip)
			chip.tooltip_text = item.display_name
		chip.set_meta(&"item_id", id)
		chip.pressed.connect(func() -> void: select(id))
		_weapons.add_child(chip)
	_rebuild_tree()

func select(item_id: StringName) -> void:
	if _selected == item_id:
		return
	_selected = item_id
	for chip in _weapons.get_children():
		var button := chip as Button
		if button:
			button.button_pressed = button.has_meta(&"item_id") \
				and button.get_meta(&"item_id") == item_id
	_rebuild_tree()
	UIMotion.page_in(_tree)
	content_changed.emit()

## Scrolls the tree to its bottom, where the automation capstone lives. Exists for the
## capture tools: the capstone is the one card in the shell with four states (locked,
## affordable, running, paused) and it is always below the fold on an item with a full tree.
func scroll_to_end() -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _items_with_trees() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in Progression.owned_items():
		if not ItemDB.augments_for(item.id).is_empty():
			out.append(item)
	return out

# --- the tree ---------------------------------------------------------------

func _rebuild_tree() -> void:
	for child in _tree.get_children():
		child.queue_free()

	if _selected == &"":
		_tree.add_child(UIStyle.body("Buy a toy to start upgrading it."))
		_refresh()
		return

	# Grouped by tier, in the order the data declares them, so a new tier needs no code.
	var tiers: Array[Array] = []
	var seen := {}
	for node in ItemDB.augments_for(_selected):
		if not seen.has(node.tier):
			seen[node.tier] = tiers.size()
			tiers.append([])
		tiers[int(seen[node.tier])].append(node)

	var previous := 0
	for tier in tiers:
		var exclusive: bool = tier[0].exclusive_group != &""
		var automation: bool = tier[0].is_automation
		if previous > 0:
			_tree.add_child(_wires(previous, 1 if exclusive or automation else tier.size()))
		if exclusive:
			_tree.add_child(_gate(tier))
			_tree.add_child(_wires(1, tier.size()))
		_tree.add_child(_row(tier, automation))
		previous = tier.size()
	_refresh()

## The wires between two tiers: stubs down from `above` columns, a bar joining them, then
## stubs down to `below`. Drawn rather than assembled out of ColorRects because the column
## positions are fractions of a width the layout has not decided yet.
func _wires(above: int, below: int) -> Control:
	var wires := Control.new()
	wires.custom_minimum_size = Vector2(0, 22)
	wires.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wires.draw.connect(func() -> void:
		var width := wires.size.x
		var height := wires.size.y
		var middle := floorf(height * 0.5)
		var thickness := float(UIStyle.rule_width())
		var half := thickness * 0.5
		for i in above:
			var x := width * (float(i) + 0.5) / float(above)
			wires.draw_rect(Rect2(x - half, 0.0, thickness, middle), UIStyle.EDGE)
		for i in below:
			var x := width * (float(i) + 0.5) / float(below)
			wires.draw_rect(Rect2(x - half, middle, thickness, height - middle), UIStyle.EDGE)
		var spread := maxi(above, below)
		if spread > 1:
			var left := width * 0.5 / float(spread)
			var right := width * (float(spread) - 0.5) / float(spread)
			wires.draw_rect(Rect2(left, middle - half, right - left, thickness), UIStyle.EDGE))
	wires.resized.connect(wires.queue_redraw)
	return wires

## The warning that a tier is a one-way door. Inverted — the only black-on-black strip in
## the game — and it changes to name the branch once one has been taken, because after the
## fact the useful information is which door closed.
func _gate(tier: Array) -> Control:
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"Gate"

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	strip.add_child(row)

	var chosen := Progression.exclusive_choice(_selected, tier[0].exclusive_group)
	if chosen == &"":
		row.add_child(UIStyle.icon(&"lock", 16, UIStyle.PANEL))
		row.add_child(UIStyle.label("PICK ONE — PERMANENT", UIStyle.MICRO, UIStyle.PANEL))
	else:
		var picked := ItemDB.get_augment(chosen)
		row.add_child(UIStyle.icon(&"check", 16, UIStyle.PANEL))
		row.add_child(UIStyle.label("YOU CHOSE %s"
			% (picked.display_name.to_upper() if picked else String(chosen)),
			UIStyle.MICRO, UIStyle.PANEL))
	return strip

func _row(tier: Array, automation: bool) -> Control:
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for node in tier:
		grid.add_child(_capstone(node) if automation else _card(node))
	return grid

# --- one node --------------------------------------------------------------

func _card(node: AugmentNode) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Tile"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)

	var title := UIStyle.label(node.display_name.to_upper(), UIStyle.MICRO)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	# The display face, not the reading face, because this line is a figure. "+15% damage"
	# is exactly the kind of number a player has to be able to trust at a glance, and every
	# figure in the game is set in the same face for that reason.
	var effect := UIStyle.label(_effect_text(node).to_upper(), UIStyle.MICRO, UIStyle.TEXT_DIM)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# This label absorbs the slack, so everything under it — the pips and the buy key —
	# sits on the card's floor rather than immediately under however many lines this node's
	# effect happened to wrap to. A tier is read across, and "Bone Collector" wrapping to
	# two lines used to drop its pips and its price 24px below its neighbours'.
	effect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	effect.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	column.add_child(effect)

	# Levels as pips, not "3 / 10". A fraction has to be read and divided; ten little bars
	# with three filled is the same fact in no time at all.
	var pips: HBoxContainer = null
	var level_text: Label = null
	if node.max_levels > 1 and node.max_levels <= PIP_LIMIT:
		pips = HBoxContainer.new()
		pips.alignment = BoxContainer.ALIGNMENT_CENTER
		pips.add_theme_constant_override("separation", 2)
		for i in node.max_levels:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(7, 9)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pip.add_theme_stylebox_override("panel", UIStyle.pip_box(false))
			pips.add_child(pip)
		column.add_child(pips)
	elif node.max_levels > PIP_LIMIT:
		level_text = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
		level_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(level_text)

	var buy := UIStyle.button("", UIStyle.MICRO)
	buy.theme_type_variation = &"BuyButton"
	buy.custom_minimum_size = Vector2(0, 30)
	buy.pressed.connect(func() -> void: _buy(node, card))
	column.add_child(buy)
	UIMotion.hook(buy, card)

	# A struck-out branch keeps its card and gets a cross laid over it. Removing it would
	# hide the cost of the decision, which is the one thing worth showing.
	#
	# Drawn rather than a glyph: a PanelContainer lays every child into its full rect, so
	# this ends up exactly card-sized whatever the card turns out to be, and two lines
	# scale cleanly where a 16px pixel cross blown up to 60px would not.
	var strike := Control.new()
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike.visible = false
	strike.draw.connect(func() -> void:
		var box := strike.size
		var ink := Color(UIStyle.LOCKED, 0.8)
		strike.draw_line(Vector2(5, 5), box - Vector2(5, 5), ink, 4.0)
		strike.draw_line(Vector2(box.x - 5, 5), Vector2(5, box.y - 5), ink, 4.0))
	strike.resized.connect(strike.queue_redraw)
	card.add_child(strike)

	card.set_meta(&"node_id", node.id)
	card.set_meta(&"buy", buy)
	if pips:
		card.set_meta(&"pips", pips)
	if level_text:
		card.set_meta(&"level_text", level_text)
	card.set_meta(&"strike", strike)
	return card

## The automation capstone gets its own shape: full width, teal-edged, and once bought its
## button stops being a price and becomes an on/off switch. Every automation needs one — a
## player in a meeting has to be able to stop the desktop moving without giving up the
## income (docs/game-design.md).
func _capstone(node: AugmentNode) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Capstone"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	card.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(header)
	header.add_child(UIStyle.icon(&"bolt", 16, UIStyle.TEAL))
	header.add_child(UIStyle.label("AUTOMATION", UIStyle.MICRO, UIStyle.TEAL))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(name_row)
	var item := ItemDB.get_item(node.item_id)
	if item and item.icon:
		name_row.add_child(UIStyle.sprite(item.icon, 32))
	var title := UIStyle.label(node.display_name.to_upper(), UIStyle.LABEL)
	name_row.add_child(title)

	var effect := UIStyle.label(_effect_text(node).to_upper(), UIStyle.MICRO, UIStyle.TEXT_DIM)
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(effect)

	# What it is producing right now, at the level owned. A capstone with thirty levels is
	# the one node in the game whose *current* output is the number the player is buying
	# against, and "1.00 Bones per second, on its own" above it describes a single level.
	var output := UIStyle.label("", UIStyle.MICRO, UIStyle.TEAL)
	output.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(output)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	column.add_child(row)

	# The switch is its own control, and this is the whole reason the card was rebuilt.
	# While capstones were single-level the buy button could *become* the switch once
	# owned — with thirty levels that would sell the player level 1 and then hide levels
	# 2-30 behind the off switch forever.
	var toggle := UIStyle.button("", UIStyle.MICRO)
	toggle.theme_type_variation = &"GhostButton"
	toggle.custom_minimum_size = Vector2(64, 34)
	toggle.pressed.connect(func() -> void: _toggle_automation(node, card))
	row.add_child(toggle)

	var buy := UIStyle.button("", UIStyle.LABEL)
	buy.theme_type_variation = &"BuyButton"
	buy.custom_minimum_size = Vector2(0, 34)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.pressed.connect(func() -> void: _buy(node, card))
	row.add_child(buy)
	UIMotion.hook(buy, card)

	card.set_meta(&"node_id", node.id)
	card.set_meta(&"buy", buy)
	card.set_meta(&"toggle", toggle)
	card.set_meta(&"output", output)
	return card

## Running / paused. Never a purchase — the two were the same button until M3.5-A.
func _toggle_automation(node: AugmentNode, card: Control) -> void:
	if Progression.augment_level(node.id) <= 0:
		return
	var running := not Progression.is_automation_enabled(node.id)
	Progression.set_automation_enabled(node.id, running)
	UIMotion.flash(card, Color(1.3, 1.45, 1.4) if running else Color(1.1, 1.1, 1.1), 0.3)
	_refresh()

func _buy(node: AugmentNode, card: Control) -> void:
	var wanted := node.max_levels if _bulk < 0 else _bulk
	var buy_button := card.get_meta(&"buy") as Control if card.has_meta(&"buy") else null
	# Measured rather than re-derived: the bulk price depends on the level the purchase
	# starts from, and computing it twice is how the two numbers drift apart.
	var currency := node.currency_id()
	var before := Economy.balance_of(currency)
	if Progression.purchase_augment(node.id, wanted) <= 0:
		UIMotion.buzz(card)
		return
	UIMotion.confirm(card)
	if buy_button:
		# Screen space, not canvas space. The shell is scaled by a whole number per
		# CanvasLayer, so `get_global_rect()` on a shell Control is out by that factor and
		# the coin launched from a point that drifts further off the harder the player zooms.
		EventBus.ui_spend.emit(currency, before - Economy.balance_of(currency),
			UIScale.screen_centre(buy_button))

func _on_augment_purchased(node_id: StringName, _level: int) -> void:
	var node := ItemDB.get_augment(node_id)
	if node and node.exclusive_group != &"":
		if not is_visible_in_tree():
			request_rebuild()
			return
		_rebuild_tree()
		content_changed.emit()
	else:
		request_refresh()

# --- state ------------------------------------------------------------------

func _refresh() -> void:
	_refresh_hero()
	for child in _tree.get_children():
		_refresh_row(child)

func _refresh_row(row: Node) -> void:
	for card in row.get_children():
		if card is Control and (card as Control).has_meta(&"node_id"):
			_refresh_card(card as Control)

func _refresh_card(card: Control) -> void:
	var node := ItemDB.get_augment(card.get_meta(&"node_id"))
	if node == null:
		return
	# `has_meta` first, every time. Two traps here, both already paid for: `set_meta(k,
	# null)` *removes* the key rather than storing a null, and `get_meta(k, null)` does
	# not suppress the error either — a null default is indistinguishable from no default
	# given. A capstone has no pips and no strike, so both apply to it.
	var buy := card.get_meta(&"buy") as Button if card.has_meta(&"buy") else null
	if buy == null:
		return
	var owned := Progression.augment_level(node.id)
	var pips := card.get_meta(&"pips") as HBoxContainer if card.has_meta(&"pips") else null
	var level_text := card.get_meta(&"level_text") as Label if card.has_meta(&"level_text") else null
	var strike := card.get_meta(&"strike") as Control if card.has_meta(&"strike") else null

	if pips:
		for i in pips.get_child_count():
			var pip := pips.get_child(i) as Panel
			pip.add_theme_stylebox_override("panel", UIStyle.pip_box(i < owned))
	if level_text:
		level_text.text = "%d / %d" % [owned, node.max_levels]

	var reason := Progression.augment_lock_reason(node.id)
	var struck := reason == EXCLUDED
	if strike:
		strike.visible = struck
	if not node.is_automation:
		card.theme_type_variation = &"TileDead" if struck \
			else (&"TileHot" if owned > 0 else &"Tile")

	var toggle := card.get_meta(&"toggle") as Button if card.has_meta(&"toggle") else null
	var output := card.get_meta(&"output") as Label if card.has_meta(&"output") else null
	if node.is_automation:
		var running := owned > 0 and Progression.is_automation_enabled(node.id)
		if toggle:
			# Nothing to switch until something is running, and a live switch over a device
			# that does not exist yet is a button that does nothing when pressed.
			toggle.visible = owned > 0
			toggle.text = "ON" if running else "OFF"
			UIStyle.set_icon(toggle, UIStyle.glyph(&"bolt" if running else &"lock"))
			UIStyle.tint_button(toggle, UIStyle.TEAL if running else UIStyle.TEXT_DIM)
		if output:
			var item := ItemDB.get_item(node.item_id)
			var unit := "HEARTS" if item and item.currency == ItemData.CURRENCY_HEARTS else "BONES"
			output.visible = owned > 0
			output.text = "LEVEL %d  ·  %.2f %s/S" % [
				owned, node.automation_rate * float(owned), unit]
			output.add_theme_color_override("font_color",
				UIStyle.TEAL if running else UIStyle.TEXT_DIM)

	if not reason.is_empty():
		_wear_lock(buy, reason)
		return

	var want := node.max_levels if _bulk < 0 else _bulk
	# Progression answers with the discount applied, which is the number the purchase will
	# actually honour; `want` is only ever 1, 10 or the whole node, never negative.
	var can_buy := mini(Progression.affordable_augment_levels(node.id), want)
	var quoted := maxi(1, mini(want, node.max_levels - owned))
	# Through Progression, so the quote carries the Mastery Pool discount the charge does.
	var cost := Progression.augment_bulk_cost(node.id, quoted)

	# The button always quotes the price of what it would buy, even when the player cannot
	# afford it — a disabled button with no number tells them nothing. It also stays live,
	# so pressing it can refuse out loud instead of swallowing the click.
	buy.text = UIStyle.format_amount(cost) if quoted == 1 else "x%d  %s" % [quoted,
		UIStyle.format_amount(cost)]
	UIStyle.set_icon(buy, UIStyle.currency_glyph(node.currency_id()))
	buy.disabled = false
	UIStyle.tint_button(buy, UIStyle.currency_colour(node.currency_id()) if can_buy > 0
		else UIStyle.TEXT_DIM)

func _refresh_hero() -> void:
	if _hero_name == null:
		return
	var balance := ItemDB.balance
	if _selected == &"":
		_hero_name.text = "No toys yet"
		_hero_rank.text = "0"
		_hero_sprite.texture = null
		_rank_star.visible = true
		_mastery_bar.visible = true
		_unlocks.visible = true
		_mastery_bar.value = 0.0
	elif _selected == AugmentNode.GLOBAL:
		# No mastery, because there is no item to master. The bar and the three unlock marks
		# would each be answering a question nobody asked of this tree, so they go away
		# rather than showing zeroes.
		_hero_name.text = GLOBAL_NAME
		_hero_rank.text = ""
		_rank_star.visible = false
		UIStyle.set_sprite(_hero_sprite, UIStyle.glyph(&"bolt"))
		_mastery_bar.visible = false
		_unlocks.visible = false
	else:
		var item := ItemDB.get_item(_selected)
		var rank := Progression.mastery_rank(_selected)
		_hero_name.text = item.display_name if item else String(_selected)
		UIStyle.set_sprite(_hero_sprite, _hero_texture(item))
		_rank_star.visible = true
		_mastery_bar.visible = true
		_unlocks.visible = true
		_mastery_bar.value = Progression.mastery_progress(_selected)
		if rank != _shown_rank or _shown_rank_for != _selected:
			# Only when it actually moves, and only for the toy it moved on. _refresh() runs
			# on every currency change, and a star that punches several times a second is a
			# tic, not a reward.
			if _shown_rank_for == _selected and _shown_rank >= 0 and rank > _shown_rank:
				UIMotion.punch(_hero_rank, 1.5)
				UIMotion.flash(_hero_rank, Color(1.7, 1.4, 0.9), 0.5)
			_shown_rank = rank
			_shown_rank_for = _selected
			_hero_rank.text = str(rank)
		_refresh_unlocks(rank, balance)

	# The pool is stated as what it is worth right now, not as a point count: "17 points"
	# means nothing without the checkpoint table in front of you.
	var slots := Progression.item_limit_bonus()
	_pool_label.text = "POOL %d  \u00b7  INCOME x%.2f  \u00b7  COST x%.2f  \u00b7  +%d %s" % [
		Progression.mastery_pool(), Progression.mastery_pool_bonus(),
		Progression.augment_cost_multiplier(), slots, "SLOT" if slots == 1 else "SLOTS"]

## The full-size sprite if there is one, the shop icon otherwise. The hero well is 72px
## and the sprites are 64px canvases, so this is the one place the big art is shown.
func _hero_texture(item: ItemData) -> Texture2D:
	if item == null:
		return null
	var box := int(_hero_sprite.custom_minimum_size.x) if _hero_sprite else UIStyle.WELL_HERO - 8
	var path := "res://Assets/sprites/items/%s.png" % item.id
	if ResourceLoader.exists(path):
		return UIStyle.boxed(ResourceLoader.load(path) as Texture2D, box)
	# `item.icon` and not `item_face()` left the well completely empty for an item with no
	# art yet — the one place in the panel that says which toy you are looking at.
	return UIStyle.item_face(item, box)

## Three marks for the three things mastery unlocks. A tick for the ones already passed,
## a padlock for the ones ahead — so the bar underneath is a promise rather than a number
## going up.
func _refresh_unlocks(rank: int, balance: BalanceData) -> void:
	var wanted := [
		[balance.mastery_branch_rank, "BRANCH"],
		[balance.mastery_automation_rank, "AUTO"],
		[balance.mastery_bonus_rank, "PAYOUT"],
	]
	if _unlocks.get_child_count() != wanted.size():
		for child in _unlocks.get_children():
			child.queue_free()
		for entry in wanted:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row.add_child(UIStyle.icon(&"lock", UIStyle.GLYPH, UIStyle.TEXT_DIM))
			row.add_child(UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM))
			_unlocks.add_child(row)

	for i in wanted.size():
		var row := _unlocks.get_child(i)
		var passed: bool = rank >= int(wanted[i][0])
		var mark := row.get_child(0) as TextureRect
		var text := row.get_child(1) as Label
		UIStyle.set_sprite(mark, UIStyle.glyph(&"check" if passed else &"lock"))
		mark.modulate = UIStyle.AFFORDABLE if passed else UIStyle.TEXT_DIM
		text.text = "%d %s" % [int(wanted[i][0]), wanted[i][1]]
		text.add_theme_color_override("font_color",
			UIStyle.AFFORDABLE if passed else UIStyle.TEXT_DIM)

## Progression states a lock as a sentence, which is right for a log line and far too long
## for a 130px card. These turn it into a mark and at most a number: the card is already
## struck out or greyed, so the button only has to say *what kind* of shut it is.
const EXCLUDED := "another branch is chosen"

func _wear_lock(buy: Button, reason: String) -> void:
	buy.disabled = true
	if reason == "maxed":
		buy.text = "MAX"
		UIStyle.set_icon(buy, UIStyle.glyph(&"check"))
		UIStyle.tint_button(buy, UIStyle.AFFORDABLE)
		return
	if reason == EXCLUDED:
		buy.text = ""
		UIStyle.set_icon(buy, UIStyle.glyph(&"cross"))
		UIStyle.tint_button(buy, UIStyle.LOCKED)
		return
	# "requires mastery 25" and "requires reincarnation 2" both carry the one number the
	# player needs; everything else is a plain padlock.
	var digits := ""
	for chunk in reason.split(" "):
		if chunk.is_valid_int():
			digits = chunk
	if reason.begins_with("requires mastery") and digits != "":
		buy.text = digits
		UIStyle.set_icon(buy, UIStyle.glyph(&"star"))
	elif reason.begins_with("requires reincarnation") and digits != "":
		buy.text = digits
		UIStyle.set_icon(buy, UIStyle.glyph(&"dollar"))
	else:
		buy.text = ""
		UIStyle.set_icon(buy, UIStyle.glyph(&"lock"))
	UIStyle.tint_button(buy, UIStyle.TEXT_DIM)

## "+15% damage per level" / "-5% time between uses per level", derived from the data so a
## new augment needs no copy written for it.
func _effect_text(node: AugmentNode) -> String:
	var item := ItemDB.get_item(node.item_id)
	var hearts := item != null and item.currency == ItemData.CURRENCY_HEARTS
	if node.is_automation:
		# A capstone's effect is a rate, not a multiplier (AugmentNode.automation_rate), so
		# the multiplier wording would read "+0% Bones earned per level" — technically true
		# of a field it does not use, and meaningless.
		return "%.2f %s per second, on its own" % [
			node.automation_rate, "Hearts" if hearts else "Bones"]
	var fallback: String = EFFECT_WORDS.get(node.effect_key, String(node.effect_key))
	var word: String = HEARTS_EFFECT_WORDS.get(node.effect_key, fallback) if hearts else fallback
	if node.item_id == AugmentNode.GLOBAL:
		word = GLOBAL_EFFECT_WORDS.get(node.effect_key, fallback)
	var percent := (node.effect_per_level - 1.0) * 100.0
	var sign_text := "+" if percent >= 0.0 else ""
	# "per level" on a one-level node promises levels that do not exist — every exclusive
	# branch is max_levels 1, so this is most of the tree's tier 2.
	var suffix := " per level" if node.max_levels > 1 else ""
	return "%s%.0f%% %s%s" % [sign_text, percent, word, suffix]
