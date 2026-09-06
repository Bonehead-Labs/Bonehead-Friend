class_name PanelLayer
extends CanvasLayer

## The tab strip and the card that unrolls from it.
##
## The strip is always on screen and never moves; clicking a tab unrolls the card beneath
## it, clicking the same tab again rolls it back up. That is the whole navigation of the
## game, in one place.
##
## It used to be two: a five-button dock in one corner of the desktop and a second, identical
## row of tabs on the card in the other. Two navigations for five pages, printing the same
## five words twice — and switching page meant a six-hundred-pixel mouse trip from the card
## you were reading back up to the dock. This is one row, and the page you are reading is
## directly under the tab that opened it.
##
## The card is **one fixed size for every page**. It used to measure the page it was about
## to show and resize to fit, which meant the panel changed shape under the cursor every
## time you switched tab. A page that needs more room scrolls.

## Inset from the window edge, in UI pixels (see `UIScale`).
const MARGIN := 12.0
## The card, when there is room for it. Deliberately generous: this is a panel you open on
## purpose, and the previous 460px forced type small enough to be hard to read.
const CARD := Vector2(700, 520)
## Never so small it is useless. Below this the window cannot host the panel at all and the
## card takes what it can get.
const CARD_MIN := Vector2(360, 260)
## The gap between two tabs. Declared here rather than at the `add_theme_constant_override`
## because `_fit()` has to divide the card's width by it.
const TAB_SEPARATION := 3

var _root: Control
var _column: VBoxContainer
var _strip: HBoxContainer
var _card: PanelContainer
var _host: ScrollContainer
## A bare full-rect Control above the card. Coins thrown at the purse live here, because
## it is the one place in the shell where a control can own its own `position`.
var _flight: Control
## Optional auto-hide (Settings > Shell): the strip and its card park above the top edge and
## an arrow pointing down marks the way back.
var _drawer: HoverDrawer
var _pages: Dictionary = {}    ## StringName -> Control
var _buttons: Dictionary = {}  ## StringName -> Button
var _current: StringName = &""

func _ready() -> void:
	layer = 20
	_build()
	EventBus.ui_spend.connect(_on_spend)
	EventBus.ui_show_item.connect(_on_show_item)
	EventBus.ui_show_panel.connect(_on_show_panel)
	EventBus.contract_completed.connect(func(_id: StringName) -> void: _update_badges())
	EventBus.contract_claimed.connect(func(_id: StringName, _d: int) -> void: _update_badges())
	EventBus.contract_board_changed.connect(_update_badges)
	EventBus.prestige_performed.connect(func(_m: float) -> void: _update_badges())
	# Deferred: the board is rolled by Progression on its own schedule, possibly after this.
	_update_badges.call_deferred()
	EventBus.ui_scale_changed.connect(func(_f: int) -> void: _fit())
	get_viewport().size_changed.connect(_fit)
	# `size_changed` is not enough on its own. Changing the play area resizes the OS window,
	# and the viewport has not caught up at the moment the setting is applied — so the shell
	# was laid out against the *previous* window and stayed that way, which put a 697px-wide
	# strip inside a 480px window. `window_rect_changed` fires once the window has actually
	# settled, which is the moment the layout is answerable.
	OverlayManager.window_rect_changed.connect(func(_r: Rect2i) -> void: _fit())
	_fit()

func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Themes propagate down a Control tree but not through a CanvasLayer, so each layer
	# hands it to its own root.
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_column = VBoxContainer.new()
	# Positioned explicitly by `_fit()` rather than anchored to the top right. The column has
	# to be able to own its own `position` — that is what lets `HoverDrawer` slide it off the
	# top — and an anchored control recomputes its position from the anchor on every resize,
	# which would fight the animation.
	_column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_column.position = Vector2(MARGIN, MARGIN)
	# Zero, so the selected tab's cream bottom edge runs straight into the card and the
	# two read as one object rather than as a row of keys above a box.
	_column.add_theme_constant_override("separation", 0)
	_root.add_child(_column)

	# The strip is exactly as wide as the card and its tabs share that width. Right-aligning
	# it instead left the open tab floating over the middle of the card's top edge, and the
	# two read as a row of keys that happened to be near a panel rather than as one object.
	_strip = HBoxContainer.new()
	_strip.name = "TabStrip"
	_strip.add_theme_constant_override("separation", TAB_SEPARATION)
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(_strip)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.theme_type_variation = &"Card"
	# Closed is the initial condition, not something `_ready()` transitions to. Building it
	# open and then calling `close()` played the roll-up and the close sound on every boot,
	# and told every page it had just been hidden before it had ever been shown.
	_card.visible = false
	_column.add_child(_card)

	# A ScrollContainer, not a plain container. Scrolling is enabled on both axes precisely
	# so neither propagates its child's minimum size into the card — which is what makes
	# "one size for every page" absolute rather than true-when-there-happens-to-be-room.
	# The vertical bar appears only if a page really is taller than the card.
	_host = ScrollContainer.new()
	_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_host.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_card.add_child(_host)

	_add_page(&"shop", "Toys", &"crate", ShopPanel.new())
	_add_page(&"tree", "Upgrades", &"star", AugmentPanel.new())
	_add_page(&"contracts", "Jobs", &"scroll", ContractPanel.new())
	# The record: every milestone with its next rung, and the numbers a player quotes. Sixty
	# milestones paid out with a toast and then had nowhere to be seen.
	_add_page(&"deeds", "Deeds", &"check", DeedsPanel.new())
	# The Arcade, where Rebirth was (docs/decisions.md D32). The old tab wore the ghost on the
	# reasoning that a dollar sign would promise the page sells something; this page does not
	# sell, it *takes*, and a room of machines that eat coins is what the mark now means.
	#
	# Reincarnation is not homeless: it is the last and biggest machine on that page. Handing
	# back an entire run for a number that multiplies every life after it is the largest gamble
	# in the game, and the arcade is where the gambles live.
	_add_page(&"arcade", "Arcade", &"dollar", ArcadePanel.new())
	_add_page(&"settings", "Settings", &"sliders", SettingsPanel.new())

	_drawer = HoverDrawer.new()
	_drawer.name = "TabsDrawer"
	add_child(_drawer)
	# The strip leaves upward, so the arrow points down while it is away — and the mark rides
	# the **tab bar**, not the column. Hung off the column it would follow the bottom of the
	# card, which puts a permanent mark in the middle of the screen whenever a page is open.
	_drawer.setup(_column, _root, HoverDrawer.Edge.TOP, _strip)
	_drawer.pinned = Settings.tabs_pinned
	_drawer.pin_toggled.connect(func(value: bool) -> void: Settings.set_tabs_pinned(value))

	_flight = Control.new()
	_flight.name = "Flight"
	_flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flight)

func _add_page(id: StringName, caption: String, mark: StringName, page: Control) -> void:
	page.name = page.get_script().get_global_name()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.visible = false
	_host.add_child(page)
	_pages[id] = page

	# Toggle rather than plain: a toggled-on tab draws the theme's `pressed` box, which is
	# the card's own cream with no bottom rule — so the open tab stops looking like a key
	# and becomes the top edge of the page below it.
	var tab := UIStyle.button(caption, UIStyle.MICRO)
	tab.theme_type_variation = &"TabButton"
	tab.toggle_mode = true
	UIStyle.set_icon(tab, UIStyle.glyph(mark))
	tab.custom_minimum_size = Vector2(0, 32)
	# Width is `_fit()`'s to decide (see there); a caption too long for its share is clipped
	# rather than allowed to widen its own tab.
	tab.clip_text = true
	tab.size_flags_horizontal = Control.SIZE_FILL
	tab.pressed.connect(func() -> void: toggle(id))
	_strip.add_child(tab)
	_buttons[id] = tab

	# A count on the tab's corner, for the one page whose contents can owe the player money
	# while it is shut: a finished contract nobody has claimed. Anchored *and* given an
	# explicit rect — a Button is not a Container, so nothing else would size it (the shop's
	# category badges are built the same way).
	var badge := PanelContainer.new()
	badge.name = "Badge_%s" % id
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
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(count)
	tab.add_child(badge)
	_badges[id] = {"panel": badge, "count": count}

## Tab badges: only Jobs has one today. Refreshed on the contract signals, never per frame.
var _badges: Dictionary = {}

func _update_badges() -> void:
	if not _badges.has(&"contracts"):
		return
	var claimable := 0
	for contract in Progression.active_contracts():
		if Progression.is_contract_complete(contract.id) and not Progression.is_contract_claimed(contract.id):
			claimable += 1
	var badge: Dictionary = _badges[&"contracts"]
	var panel := badge["panel"] as Control
	var was := panel.visible
	panel.visible = claimable > 0
	(badge["count"] as Label).text = str(claimable)
	if panel.visible and not was:
		UIMotion.punch(panel, 1.3)
		# A job came good while the card was shut: a few chips off the tab, so the eye goes there.
		UIMotion.sparkle(panel, UIStyle.DOLLARS, 10, 140.0)

## The card is sized here and nowhere else, and it is the same size whichever page is
## showing. On a window too small to hold it, it shrinks — but it still does not change
## between pages, which is the property that matters.
func _fit() -> void:
	if _root == null:
		return
	UIScale.apply(self, _root)
	if _flight:
		_flight.size = _root.size
	var strip_height := _strip.get_combined_minimum_size().y
	var room := _root.size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + strip_height)
	var wanted := clampf(CARD.x, CARD_MIN.x, maxf(CARD_MIN.x, room.x))

	# The strip is five keys read as one object, so every tab is the same width — and the
	# same width whether or not its page is open. Two things used to break that. Each tab
	# was sized to its own caption ("Toys" 73px, "Upgrades" 102px), and the strip only
	# stretched to the card's width while the card was *visible*, so opening a panel snapped
	# every tab from its caption width to a fifth of 700 underneath the cursor that had just
	# clicked it. Both are gone: the width is derived here, from the card, once.
	#
	# The card's own width is then snapped down to what divides exactly. That costs at most
	# `tabs - 1` pixels and it is what makes the rule hold for a sixth tab as well as these
	# five — the alternative is a leftover of a few pixels handed to whichever tabs happen
	# to sort first, which is where the 137/138/137/138/138 came from.
	var tabs := maxi(1, _buttons.size())
	var gaps := float(TAB_SEPARATION * (tabs - 1))
	var tab_width := maxf(1.0, floorf((wanted - gaps) / float(tabs)))
	var strip_width := tab_width * float(tabs) + gaps
	for id in _buttons:
		var tab := _buttons[id] as Button
		tab.custom_minimum_size.x = tab_width
		# SIZE_FILL, not EXPAND_FILL: expanding is what let the container hand the leftover
		# to some tabs and not others.
		tab.size_flags_horizontal = Control.SIZE_FILL
	# Pinned on the strip too, so the tabs keep their width with the card shut.
	_strip.custom_minimum_size.x = strip_width

	_card.custom_minimum_size = Vector2(strip_width,
		clampf(CARD.y, CARD_MIN.y, maxf(CARD_MIN.y, room.y)))

	_resize_column(strip_width)

	# Right-aligned by arithmetic, now the column is not anchored. The *drawer* owns the
	# position from here — writing it directly as well would snap a parked column back on
	# screen every time the window or the scale changed.
	var home := Vector2(maxf(MARGIN, _root.size.x - strip_width - MARGIN), MARGIN)
	if _drawer:
		_drawer.set_home(home)
	else:
		_column.position = home

## A child of a plain `Control` is never laid out, so the column keeps whatever size it was
## last given. That bites in both axes and both directions:
##
## - its **width** grew to the full card at a big play area and stayed there when the player
##   stepped back down, leaving a 697px strip inside a 480px window;
## - its **height** kept the open card's 554px after the card was hidden, and since the
##   drawer's "is the cursor on the panel" test uses that rect, the menu refused to park
##   itself for as long as the cursor was anywhere in a tall invisible region.
##
## So it is resized whenever anything that decides its size changes — the window, and the
## card being shown or hidden. Deferred as well as immediate, because the minimum size the
## reset clamps to is only recomputed later in the frame.
func _resize_column(width: float = 0.0) -> void:
	if _column == null:
		return
	_column.size = Vector2(width if width > 0.0 else _column.size.x, 0.0)
	_column.reset_size()
	_column.call_deferred("reset_size")

## Clicking the tab for the page that is already open closes it, which is what every
## player expects — and it is why the tabs are toggles rather than a radio group.
func toggle(panel: StringName) -> void:
	if _current == panel:
		close()
	else:
		show_panel(panel)

func show_panel(panel: StringName) -> void:
	if not _pages.has(panel):
		return
	var was_open := _card.visible
	_current = panel
	# Page visibility is settled *before* the card is shown. Showing the card first
	# propagates visible-in-tree to whichever page was last open, so every page that
	# refreshes on becoming visible rebuilt itself once on the way to being hidden.
	for id in _pages:
		(_pages[id] as Control).visible = id == panel
		(_buttons[id] as Button).button_pressed = id == panel
	# A close that was still animating owns the card's scale and alpha; opening cancels
	# that tween but not the state it had already written.
	_card.modulate.a = 1.0
	_card.visible = true
	_host.scroll_vertical = 0
	_resize_column()
	if not was_open:
		UIMotion.unroll(_card)
	UIMotion.page_in(_pages[panel])
	EventBus.ui_panel_changed.emit(panel)

## Onboarding pins the strip open so a first-time player can see the tabs exist.
func pin_drawer(value: bool) -> void:
	if _drawer:
		_drawer.pinned = value

## A page by id, from the HUD. Reincarnation lives at the bottom of the Arcade (D32), so the
## link opens that page and scrolls the card to it once the layout has landed.
func _on_show_panel(panel: StringName) -> void:
	if panel == &"prestige":
		show_panel(&"arcade")
		var arcade := _pages.get(&"arcade") as ArcadePanel
		if arcade:
			arcade.show_room(ArcadePanel.ROOM_REBIRTH)
			if arcade.prestige_panel():
				_host.ensure_control_visible.call_deferred(arcade.prestige_panel())
		return
	if _pages.has(panel):
		show_panel(panel)

## The HUD's "next up" row lands here: open Toys on that item's drawer with it selected.
func _on_show_item(item_id: StringName) -> void:
	var item := ItemDB.get_item(item_id)
	var shop := _pages.get(&"shop") as ShopPanel
	if item == null or shop == null:
		return
	show_panel(&"shop")
	shop.show_category(item.category)
	shop.select(item_id)

func close() -> void:
	if _current == &"" and not (_card and _card.visible):
		return
	_current = &""
	for id in _buttons:
		(_buttons[id] as Button).button_pressed = false
	if _card and _card.visible:
		# The page stays visible for the roll-up — the card animates with its contents —
		# and is hidden with the card, so no page is ever left flagged visible under a
		# shut card. That gap is what made every page's `if visible:` guard a no-op.
		UIMotion.roll_up(_card, func() -> void:
			_card.visible = false
			for id in _pages:
				(_pages[id] as Control).visible = false
			_resize_column())
	EventBus.ui_panel_changed.emit(&"")

## The shell's footprint in **screen** pixels, for the window check. It is not
## `get_global_rect()`: the layer is scaled by a whole number, so a shell Control's global
## rect is in canvas space and wrong by exactly that factor.
func shell_rect() -> Rect2:
	return UIScale.screen_rect(_column) if _column else Rect2()

func is_open() -> bool:
	return _current != &""

## A purchase went through somewhere on the card: throw the coin it cost from the press
## into the purse, and let the purse catch it.
##
## Deliberately driven by a signal rather than called by the shop directly. The shop knows
## what was bought and where the cursor was; it has no business knowing that a purse
## exists, let alone where on screen it is.
func _on_spend(currency: StringName, _amount: float, screen_pos: Vector2) -> void:
	if _flight == null or not _card.visible:
		return
	var purse := get_tree().get_first_node_in_group(&"purse") as PurseStrip
	if purse == null:
		return
	# Screen space on both ends: the purse is on a different CanvasLayer, and once either
	# layer is scaled a plain `get_global_rect()` is in canvas coordinates, not the ones
	# the coin flies through.
	var here := _flight.get_global_transform_with_canvas().affine_inverse()
	UIMotion.fly(_flight, UIStyle.currency_glyph(currency), UIStyle.currency_colour(currency),
		here * screen_pos, here * purse.chip_centre(currency))
	# Landing, not launch: the chip reacts when the coin gets there. Bound, not a lambda —
	# a lambda capturing a Node prints "Lambda capture was freed" if the purse dies first.
	get_tree().create_timer(0.41).timeout.connect(purse.catch.bind(currency))
