extends Node

## Headless click-through of the M2 shell: does the mouse actually reach the UI?
##
##   Godot --headless --path <project> res://tests/integration/ui_check.tscn
##
## The panels and the dock were built and screenshotted but never clicked, and a full-rect
## container sitting on the top CanvasLayer swallowed every click in the window without
## drawing anything. Screenshots cannot catch that; this can.
##
## The real scene runs inside a SubViewport because a headless root viewport is 64x64 —
## every widget would be off-screen and every hit test meaningless. The SubViewport is the
## play-area size, handles its own input, and takes synthetic mouse events.

const TEST_SLOT := "ui_check_slot"
const VIEW_SIZE := Vector2i(960, 640)

var _passed := 0
var _failed := 0
var _view: SubViewport
var _main: Node

## Captured on the very first line, before anything is stomped. This suite clicks real
## settings controls — one of them is a Focus Mode button, whose handler calls
## `Settings.save_settings()` and serialises *every* field — so a run used to leave the
## developer's own Focus Mode and Menu size wherever the test happened to put them. Every
## screenshot taken after one was silently at the wrong scale, which is how a text-size
## complaint got past review.
var _restore := {}

func _ready() -> void:
	_restore = {
		"focus": Settings.focus_intensity,
		"scale": Settings.ui_scale,
		"play_area": Settings.play_area_size,
		"hud_pinned": Settings.hud_pinned,
		"tabs_pinned": Settings.tabs_pinned,
	}
	Settings.focus_intensity = Settings.Intensity.OFF
	# Pinned, so the suite's coverage is a property of the suite and not of whatever the
	# developer last left in settings.cfg.
	Settings.ui_scale = 1
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()

	print("")
	print("Bonehead Friend — UI check")
	print("==========================")

	_view = SubViewport.new()
	_view.size = VIEW_SIZE
	_view.handle_input_locally = true
	_view.physics_object_picking = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	# A SubViewport with no SubViewportContainer above it never gets told the mouse is
	# inside it, and physics picking is gated on exactly that — without this the world
	# silently ignores every synthetic click and the drag checks below always fail.
	_view.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)

	_main = load("res://main.tscn").instantiate()
	_view.add_child(_main)
	await _settle()
	# Hiding until hover is the shell's default (D29), so every suite below that is about
	# what is *on* a page has to hold the page still first. `_the_shell_hides_until_hovered`
	# is the one that unpins, and it pins both halves again when it is done.
	await _pin_shell(true)

	_nothing_blocks_the_window()
	await _the_strip_opens_the_panels()
	await _the_card_is_one_size()
	await _shop_tiles_are_clickable()
	await _every_visible_button_is_reachable()
	await _the_capstone_levels_and_switches()
	await _the_settings_page_works()
	await _the_rebirth_page_refuses_an_empty_reset()
	await _the_tabs_are_one_width()
	await _every_page_is_readable()
	await _the_deeds_board_is_on_the_page()
	await _the_hud_calls_for_rebirth()
	await _the_purse_can_count_high()
	await _the_payouts_are_visible()
	await _the_hud_points_at_the_next_toy()
	await _the_shell_hides_until_hovered()
	await _nothing_overflows_its_box()
	await _closed_pages_do_no_work()
	await _the_buddy_still_takes_clicks()
	await _he_notices_the_player()
	await _escape_menu_opens_and_closes()

	print("")
	print("==========================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_clear_slot()
	_restore_settings()
	get_tree().quit(1 if _failed > 0 else 0)

## Assignment is not enough: a clicked control has already written the file, so the restore
## has to write it back.
func _restore_settings() -> void:
	Settings.focus_intensity = _restore["focus"]
	Settings.ui_scale = _restore["scale"]
	Settings.play_area_size = _restore["play_area"]
	# The pin suite clicks a real pin, whose handler saves. Without this a developer who had
	# pinned their HUD open would find it unpinned after every test run.
	Settings.hud_pinned = _restore["hud_pinned"]
	Settings.tabs_pinned = _restore["tabs_pinned"]
	Settings.save_settings()

# --- checks ----------------------------------------------------------------

## The failure this file exists for: an invisible control on a high CanvasLayer covering
## the window. It eats the dock, the panels and the buddy alike, and looks like nothing.
func _nothing_blocks_the_window() -> void:
	_suite("nothing blocks the window")
	for point in [Vector2(480, 320), Vector2(40, 40), Vector2(900, 600)]:
		var hit := _hovered_at(point)
		var blocker := _covers_everything(hit)
		_check("%s is not swallowed by a full-window control (got %s)"
			% [point, _describe(hit)], blocker == "", blocker)

## The tab strip is now the whole navigation of the game — there is no dock. It is always
## on screen, it never moves, and clicking the tab of the page already showing closes it.
func _the_strip_opens_the_panels() -> void:
	_suite("tab strip")
	var panels := _find(_main, "PanelLayer")
	_check("panel layer exists", panels != null)
	_check("the HUD no longer carries a second copy of the navigation",
		_button_labelled("Toys", _find(_main, "HUD")) == null)
	if panels == null:
		return
	for entry in [["Toys", &"shop"], ["Upgrades", &"tree"], ["Jobs", &"contracts"],
			["Deeds", &"deeds"], ["Arcade", &"arcade"], ["Settings", &"settings"]]:
		var tab := _button_labelled(entry[0], panels)
		_check("the strip has a '%s' tab" % entry[0], tab != null)
		if tab == null:
			continue
		var target := _centre_of(tab)
		_check("'%s' is the top control at %s (got %s)"
			% [entry[0], target, _describe(_hovered_at(target))], _hovered_at(target) == tab)
		await _click(target)
		_check("clicking '%s' opens its page" % entry[0], panels.call("is_open"))
		_check("'%s' shows the right page" % entry[0], panels.get("_current") == entry[1])
		_check("and its tab stays pushed in", tab.button_pressed)

	# The strip survives the card being shut, which is the property that makes it the
	# navigation rather than part of the panel.
	var toys := _button_labelled("Toys", panels)
	await _click(_centre_of(toys))
	_check("a different tab switches page", panels.get("_current") == &"shop")
	await _click(_centre_of(toys))
	_check("clicking the open page's own tab closes it", not panels.call("is_open"))
	_check("the strip is still on screen with the card shut", toys.is_visible_in_tree())
	_check("and no tab is pushed in", not toys.button_pressed)
	await _click(_centre_of(toys))
	_check("clicking it again reopens it", panels.call("is_open"))

## The card is one size whichever page is showing. It used to measure the page it was
## about to show and resize to fit, so the panel changed shape under the cursor on every
## tab click.
func _the_card_is_one_size() -> void:
	_suite("card")
	var panels := _find(_main, "PanelLayer")
	var card := _find(panels, "Card") as Control
	_check("the card exists", card != null)
	if card == null:
		return
	var sizes: Array[Vector2] = []
	for page in [&"shop", &"tree", &"contracts", &"deeds", &"arcade", &"settings"]:
		panels.call("show_panel", page)
		await _settle()
		sizes.append(card.size)
	var first: Vector2 = sizes[0]
	var same := sizes.all(func(s: Vector2) -> bool: return s.is_equal_approx(first))
	_check("every page gets the same card (%s)" % first, same,
		"" if same else str(sizes))
	panels.call("close")
	await _settle()

func _shop_tiles_are_clickable() -> void:
	_suite("shop")
	var panels := _find(_main, "PanelLayer")
	panels.call("show_panel", &"shop")
	await _settle()

	# The shop is a category at a time now, so the tabs are the navigation and a page
	# nobody can reach is a page that does not exist.
	var shop := _find(_main, "ShopPanel")
	_check("the shop page exists", shop != null)
	if shop == null:
		return
	# Two front doors, then a strip of about five tabs behind each. Ten categories will not
	# fit across this card, which is why the sides exist at all — so the assertion that
	# matters is not that every tab is present but that the *other* side's tabs are away.
	for side_caption in ["Harm", "Kind"]:
		_check("shop offers the '%s' side" % side_caption,
			_button_labelled(side_caption, shop) != null)

	for pair in [["Harm", ["Melee", "Boom", "Cursor", "Turret", "Critters"]],
			["Kind", ["Care", "Play", "Comfort", "Food", "Mood"]]]:
		var side_tile := _button_labelled(String(pair[0]), shop)
		if side_tile == null:
			continue
		await _click(_centre_of(side_tile))
		for caption in pair[1]:
			var tab := _button_labelled(String(caption), shop)
			_check("the %s side offers '%s'" % [pair[0], caption], tab != null)
			if tab == null:
				continue
			_check("'%s' is on screen under the %s side" % [caption, pair[0]], tab.visible)
			if _is_on_screen(tab):
				_check("'%s' takes the cursor (got %s)"
					% [caption, _describe(_hovered_at(_centre_of(tab)))],
					_hovered_at(_centre_of(tab)) == tab)
				await _click(_centre_of(tab))
				_check("clicking '%s' shows its page" % caption,
					int(shop.get("_category")) >= 0)

	# The whole point of the split: standing on one side hides the other side's tabs. Without
	# this the two-tile nav could be doing nothing at all and every assertion above would
	# still pass, because a flat strip of ten offers all ten captions too.
	var kind_tile := _button_labelled("Kind", shop)
	if kind_tile:
		await _click(_centre_of(kind_tile))
		# `_button_labelled` only returns what is visible in the tree, so a null here *is*
		# the assertion — the Melee tab is still built and still counting its badge, it is
		# simply not on this side.
		_check("standing on Kind puts the Melee tab away",
			_button_labelled("Melee", shop) == null)
		_check("and brings Comfort out", _button_labelled("Comfort", shop) != null)

	# Asking for a category directly must bring its side's strip with it. The two halves of
	# the header disagreed exactly once and a screenshot caught it: the capture tool calls
	# `show_category` to reach the kind list, and the shot came back showing Care items under
	# a row of tabs reading Melee, Boom, Cursor, Turret, Critters — a strip describing a page
	# nobody was looking at. Nothing above this catches it, because every assertion up there
	# arrives through a side tile.
	shop.call("show_category", ItemData.CATEGORY_WEAPON)
	await _settle()
	_check("reaching Melee directly also shows the Harm strip",
		_button_labelled("Melee", shop) != null and _button_labelled("Comfort", shop) == null)
	shop.call("show_category", ItemData.CATEGORY_FRIENDLY)
	await _settle()
	_check("and reaching Care directly shows the Kind strip",
		_button_labelled("Comfort", shop) != null and _button_labelled("Melee", shop) == null)

	# Back to the starters. The bat is a free starter, so selecting it puts a Spawn button
	# in the detail pane — the shop's one action button, whichever item is selected. Reaching
	# it now takes two clicks: the side, then the category.
	var harm_tile := _button_labelled("Harm", shop)
	if harm_tile:
		await _click(_centre_of(harm_tile))
	var melee := _button_labelled("Melee", shop)
	if melee:
		await _click(_centre_of(melee))
	var bat_row := _button_labelled("Baseball Bat", shop)
	_check("the list offers a row per item", bat_row != null)
	if bat_row:
		await _click(_centre_of(bat_row))
		_check("selecting a row marks it", bat_row.button_pressed)
	var spawn := _button_labelled("Spawn", _find(_main, "PanelLayer"))
	_check("an owned item offers a Spawn button", spawn != null)
	if spawn == null:
		return
	_check("the Spawn button is the top control under the cursor (got %s)"
		% _describe(_hovered_at(_centre_of(spawn))), _hovered_at(_centre_of(spawn)) == spawn)
	var spawner := _find(_main, "ItemSpawner")
	var before: int = spawner.call("item_count")
	await _click(_centre_of(spawn))
	await _settle()
	_check("clicking Spawn puts an item in the world",
		int(spawner.call("item_count")) > before)
	panels.call("close")
	await _settle()

## The capstone card is the one card in the shell that is both a purchase and a switch, and
## until M3.5-A it was the *same button* for both: buying level 1 turned the button into the
## on/off toggle, so a levelled capstone would have sold the player one level and hidden the
## other twenty-nine behind it forever. This clicks both controls on a real card.
func _the_capstone_levels_and_switches() -> void:
	_suite("the capstone")
	var panels := _find(_main, "PanelLayer")
	var tree := _find(_main, "AugmentPanel")
	if tree == null:
		_check("the tree page exists", false)
		return

	# Staged here rather than shared: this is the only suite that needs an unlocked
	# capstone, and mastery XP granted globally would change what every other page shows.
	var node := ItemDB.get_augment(&"bat_sentry")
	Progression.add_mastery_xp(&"baseball_bat",
		EconomyMath.mastery_xp_for_rank(ItemDB.balance.mastery_base, node.requires_mastery))
	Economy.grant(Economy.HEARTS, float(node.cost_base) * 20.0)

	panels.call("show_panel", &"tree")
	tree.call("select", &"baseball_bat")
	await _settle()
	tree.call("scroll_to_end")
	await _settle()

	var card := _card_for(tree, &"bat_sentry")
	_check("the bat's capstone is on the page", card != null)
	if card == null:
		return
	var buy := card.get_meta(&"buy") as Button
	var toggle := card.get_meta(&"toggle") as Button
	_check("its price and its switch are two different buttons", buy != null and toggle != null
		and buy != toggle)
	if buy == null or toggle == null:
		return

	_check("the switch is hidden until something is running", not toggle.visible)
	if _is_on_screen(buy):
		await _click(_centre_of(buy))
		await _settle()
	else:
		Progression.purchase_augment(&"bat_sentry", 1)
		await _settle()
	_check("buying gives it a level", Progression.augment_level(&"bat_sentry") == 1)
	_check("and it is running", Progression.is_automation_enabled(&"bat_sentry"))
	_check("the switch appears once it exists", toggle.visible)

	# The regression, stated directly: pressing the price again must be a second level and
	# not a pause.
	if _is_on_screen(buy):
		await _click(_centre_of(buy))
		await _settle()
		_check("pressing the price again buys another level",
			Progression.augment_level(&"bat_sentry") == 2)
		_check("and does not switch it off", Progression.is_automation_enabled(&"bat_sentry"))

	if _is_on_screen(toggle):
		await _click(_centre_of(toggle))
		await _settle()
		_check("the switch pauses it", not Progression.is_automation_enabled(&"bat_sentry"))
		_check("without refunding a level", Progression.augment_level(&"bat_sentry") == 2)
		await _click(_centre_of(toggle))
		await _settle()
		_check("and starts it again", Progression.is_automation_enabled(&"bat_sentry"))

	panels.call("close")
	await _settle()

## The card for one augment, found by the meta every card carries rather than by its
## position in the tree — the tree's shape is data and changes with the content.
func _card_for(root: Node, node_id: StringName) -> Control:
	var control := root as Control
	if control and control.has_meta(&"node_id") and control.get_meta(&"node_id") == node_id:
		return control
	for child in root.get_children():
		var found := _card_for(child, node_id)
		if found:
			return found
	return null

func _escape_menu_opens_and_closes() -> void:
	_suite("escape menu")
	var esc := _find(_main, "EscMenu")
	_check("escape menu exists", esc != null)
	if esc == null:
		return
	_check("it is closed on boot", not bool(esc.get("_open")))
	esc.call("open")
	await _settle()
	var resume := _button_labelled("Resume", esc)
	_check("the Resume button is reachable while paused",
		resume != null and _hovered_at(_centre_of(resume)) == resume)
	var dock_toys := _button_labelled("Toys", _find(_main, "HUD"))
	_check("a paused game does not pass clicks through to the world",
		dock_toys == null or _hovered_at(_centre_of(dock_toys)) != dock_toys)
	if resume:
		await _click(_centre_of(resume))
		_check("Resume closes the menu", not bool(esc.get("_open")))
	_check("the world runs again after resuming",
		(_find(_main, "World") as Node).process_mode != Node.PROCESS_MODE_DISABLED)

## A sweep rather than a list: every button the player can see should be the thing the
## cursor lands on. Catches the same class of bug anywhere it reappears — an overlapping
## panel, a stray full-rect container, a tile drawn under its own category header.
func _every_visible_button_is_reachable() -> void:
	_suite("every visible button")
	var panels := _find(_main, "PanelLayer")
	for page in [&"shop", &"tree", &"contracts", &"deeds", &"arcade", &"settings"]:
		panels.call("show_panel", page)
		await _settle()
		var blocked := 0
		var tested := 0
		var first := ""
		for node in _all_nodes(_main):
			if not (node is Button) or not (node as Button).is_visible_in_tree():
				continue
			var button := node as Button
			if not _is_on_screen(button):
				continue
			tested += 1
			if _hovered_at(_centre_of(button)) != button:
				blocked += 1
				if first == "":
					first = "%s ('%s') is under %s" % [_main.get_path_to(button),
						button.text, _describe(_hovered_at(_centre_of(button)))]
		_check("%s page: all %d visible buttons take the cursor" % [page, tested],
			blocked == 0 and tested > 0, first)
	panels.call("close")
	await _settle()

## The settings page exists because a playtester cannot resize a borderless window without
## knowing F9/F10 — so the thing worth asserting is that its controls are real and wired,
## not merely that they render.
##
## Only the Focus Mode buttons are actually clicked. The rest call into DisplayServer to
## move and resize the OS window, which in a headless run with a SubViewport-hosted scene
## would be reconfiguring the wrong window; those are hover-tested instead, which is what
## catches the bug this file was written for.
func _the_settings_page_works() -> void:
	_suite("settings")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		_check("panel layer exists", false)
		return
	panels.call("show_panel", &"settings")
	await _settle()

	var settings_page := _find(_main, "SettingsPanel")
	_check("the settings page exists", settings_page != null)
	if settings_page == null:
		return

	for caption in ["Overlay", "Play area", "Top left", "Off", "Normal", "Chaos"]:
		var button := _button_labelled(caption, settings_page)
		_check("settings offers '%s'" % caption, button != null)
		if button and _is_on_screen(button):
			_check("'%s' is the control under the cursor (got %s)"
				% [caption, _describe(_hovered_at(_centre_of(button)))],
				_hovered_at(_centre_of(button)) == button)

	# Focus Mode is pure Settings state, so it is safe to actually press headless.
	var subtle := _button_labelled("Subtle", settings_page)
	_check("a Focus Mode button exists", subtle != null)
	if subtle:
		await _click(_centre_of(subtle))
		_check("clicking it changes Focus Mode",
			Settings.focus_intensity == Settings.Intensity.SUBTLE)
		var off := _button_labelled("Off", settings_page)
		if off:
			await _click(_centre_of(off))
			_check("and back to Off", Settings.focus_intensity == Settings.Intensity.OFF)

	# The panel reads Settings live rather than caching, because the F3 hotkeys change the
	# same values behind its back and two sources of truth is how a settings screen lies.
	Settings.play_area_size = Vector2i(1200, 800)
	settings_page.call("request_refresh")
	await _settle()
	_check("the size readout follows Settings",
		_label_containing("1200 x 800", settings_page) != null)

	panels.call("close")
	await _settle()

## Reincarnation throws away the entire run, so the one thing worth asserting in a click
## test is that it cannot be triggered by accident: disabled with nothing to gain, and two
## presses even when there is.
func _the_rebirth_page_refuses_an_empty_reset() -> void:
	_suite("rebirth")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	panels.call("show_panel", &"arcade")
	await _settle()

	var page := _find(_main, "PrestigePanel")
	_check("the rebirth page exists", page != null)
	if page == null:
		return

	# Marrow is scaled by the *run*, and every suite above this one has been spending money
	# into it, so the empty case has to be made rather than assumed.
	Economy.run_earnings = 0.0
	page.call("request_refresh")
	await _settle()
	var button := _button_labelled("Not yet", page)
	_check("with nothing to gain the button is inert", button != null and button.disabled)

	# Now with something to gain: the first press must arm rather than reset.
	Economy.grant(Economy.BONES, ItemDB.balance.marrow_divisor * 4.0)
	page.call("request_refresh")
	await _settle()
	var reincarnate := _button_labelled("Reincarnate", page)
	_check("it offers a reset once there is Marrow to gain", reincarnate != null)
	if reincarnate == null:
		return
	var count_before: int = Economy.prestige_count
	await _scroll_into_view(reincarnate)
	await _click(_centre_of(reincarnate))
	_check("one press does not reset anything", Economy.prestige_count == count_before)
	_check("it asks for confirmation instead",
		_button_labelled("Press again to reset", page) != null)

	# Closing the card is a decision not to reincarnate. Before this the armed state was
	# only ever cleared by the reset itself, so arming the button and walking away left the
	# game one stray click from deleting the run — hours later, from a different page.
	panels.call("close")
	await _settle()
	panels.call("show_panel", &"arcade")
	await _settle()
	_check("closing the card disarms the reset",
		_button_labelled("Reincarnate", page) != null)
	var armed_button := _button_labelled("Reincarnate", page)
	if armed_button:
		await _scroll_into_view(armed_button)
		await _click(_centre_of(armed_button))
		_check("so the next click asks again rather than resetting",
			Economy.prestige_count == count_before)

	panels.call("close")
	await _settle()

## The tab strip is a row of five keys that are read as one object, so they are one width
## each — and a tab must not change width when it is the open one. A tab that grows on
## being pressed makes the whole strip shuffle sideways under the cursor that pressed it.
func _the_tabs_are_one_width() -> void:
	_suite("tab strip")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	var strip := _find(_main, "TabStrip")
	if strip == null:
		_check("the tab strip exists", false)
		return

	# Closed, then with each page open in turn: the same five widths every time.
	panels.call("close")
	await _settle()
	var shut: Array[float] = []
	for tab in strip.get_children():
		shut.append((tab as Control).size.x)
	var report := "shut %s" % str(shut)

	var drift: Array[String] = []
	for page_id in [&"shop", &"tree", &"contracts", &"deeds", &"arcade", &"settings"]:
		panels.call("show_panel", page_id)
		await _settle()
		var open_widths: Array[float] = []
		for tab in strip.get_children():
			open_widths.append((tab as Control).size.x)
		for i in open_widths.size():
			if absf(open_widths[i] - shut[i]) > 0.5:
				drift.append("%s: tab %d %.0f -> %.0f" % [page_id, i, shut[i], open_widths[i]])
	_check("no tab changes width when it is the open one (%s)" % report, drift.is_empty(),
		", ".join(drift))

	var uneven := false
	for w in shut:
		if absf(w - shut[0]) > 0.5:
			uneven = true
	_check("all five tabs are the same width", not uneven, str(shut))
	panels.call("close")
	await _settle()

## The HUD names the next thing to buy and links to it. The genre's biggest hook was inside
## an open shop page behind a drawer that hides by default (assessment-2026-09); this is the
## row that fixes it, and the three things it has to do: pick something, notice when it
## becomes affordable, and open Toys on it when clicked.
func _the_hud_points_at_the_next_toy() -> void:
	_suite("next up")
	var hud := _find(_main, "HUD")
	var panels := _find(_main, "PanelLayer")
	var row := _find(_main, "NextUp") as Control
	_check("the HUD has a next-up row", hud != null and row != null)
	if hud == null or row == null or panels == null:
		return
	panels.call("close")
	var drawer := _find(_main, "HudDrawer")
	if drawer:
		drawer.set("pinned", true)
	# Coalesced behind a short timer, so a grant is not enough on its own — wait it out.
	Economy.grant(Economy.BONES, 1.0)
	await get_tree().create_timer(0.6).timeout
	await _settle()
	var picked: StringName = hud.get("_next_item")
	_check("it names something to buy", row.visible and picked != &"")
	if picked == &"":
		return
	var item := ItemDB.get_item(picked)
	_check("something the player can actually buy next", Progression.can_purchase(picked))

	# Pay for it and watch the row notice.
	Economy.grant(item.currency_id(), float(item.cost))
	await get_tree().create_timer(0.6).timeout
	await _settle()
	_check("and it notices when that becomes affordable", bool(hud.get("_next_affordable")))

	await _click(_centre_of(row))
	_check("clicking it opens Toys", bool(panels.call("is_open"))
		and panels.get("_current") == &"shop")
	var shop := _find(panels, "ShopPanel")
	_check("on that item", shop != null and shop.get("_selected") == picked)

	# And buying it puts it on the desk (assessment-2026-09 §4): the Aug 31 session showed
	# players buying and then not finding the Spawn button. Cursor powers equip rather than
	# land, so the desk count is asserted only for a thing that lands.
	var spawner := _find(_main, "ItemSpawner")
	var action := shop.get("_detail_action") as Button if shop else null
	_check("the item's action is a live button", action != null and spawner != null)
	if action and spawner:
		var count_before: int = spawner.call("item_count")
		await _click(_centre_of(action))
		await _settle()
		_check("clicking it buys the item", Progression.is_unlocked(picked))
		if item.category != ItemData.CATEGORY_CURSOR_POWER:
			_check("and the purchase lands on the desk (%d -> %d)"
					% [count_before, int(spawner.call("item_count"))],
				int(spawner.call("item_count")) > count_before)
	panels.call("close")
	await _settle()

## Hiding until hover is the shell's default behaviour, not a setting — and hovering the mark
## turns it into a pin the player can click to keep the panel out. Both halves, both ways.
##
## Drivable at all because `HoverDrawer` tracks the cursor from motion events rather than
## polling `get_mouse_position()`: the polled position is the OS cursor, which no synthetic
## event can move.
func _the_shell_hides_until_hovered() -> void:
	_suite("hide and pin")
	var panels := _find(_main, "PanelLayer")
	var hud := _find(_main, "HUD")
	if panels == null or hud == null:
		_check("the shell exists", false)
		return
	panels.call("close")
	Settings.hud_pinned = false
	Settings.tabs_pinned = false
	# By node name: `get_class()` on a script class returns its *engine* base ("Node"), so
	# looking one up by `class_name` finds nothing.
	for drawer_name in ["HudDrawer", "TabsDrawer"]:
		var drawer := _find(_main, drawer_name)
		_check("the %s exists" % drawer_name, drawer != null)
		if drawer:
			drawer.set("pinned", false)
	await _settle()

	var window := Rect2(Vector2.ZERO, Vector2(VIEW_SIZE))
	var away := Vector2(VIEW_SIZE) * 0.5
	for entry in [["status", hud], ["menu", panels]]:
		var who: String = entry[0]
		var shell: Node = entry[1]
		var mark := _find(shell, "DrawerMark") as Control
		_check("the %s leaves a mark behind" % who, mark != null)
		if mark == null:
			continue

		await _park(away)
		_check("the %s hides itself by default" % who,
			not window.intersects(shell.call("shell_rect") as Rect2))
		_check("but its mark stays on screen", window.encloses(UIScale.screen_rect(mark)))

		await _park(UIScale.screen_rect(mark).get_center())
		_check("hovering the mark brings the %s out" % who,
			window.intersects(shell.call("shell_rect") as Rect2))

		await _park(away)
		_check("and taking the cursor away sends it back",
			not window.intersects(shell.call("shell_rect") as Rect2),
			str(shell.call("shell_rect")))

		# Pin it: a click on the mark, then the cursor goes away and it must stay.
		await _park(UIScale.screen_rect(mark).get_center())
		await _click(UIScale.screen_rect(mark).get_center())
		await _park(away)
		_check("clicking the mark pins the %s open" % who,
			window.intersects(shell.call("shell_rect") as Rect2),
			str(shell.call("shell_rect")))

		# And the decision is remembered, not just held.
		_check("which is remembered for next time",
			Settings.hud_pinned if who == "status" else Settings.tabs_pinned)

		await _park(UIScale.screen_rect(mark).get_center())
		await _click(UIScale.screen_rect(mark).get_center())
		await _park(away)
		_check("clicking again unpins it and it hides again",
			not window.intersects(shell.call("shell_rect") as Rect2),
			str(shell.call("shell_rect")))

	# The menu's mark rides the tab bar. Hung off the column it would follow the bottom of
	# the card, putting a permanent mark in the middle of the screen with a page open.
	var tabs_mark := _find(panels, "DrawerMark") as Control
	var strip := _find(panels, "TabStrip") as Control
	if tabs_mark and strip:
		await _park(UIScale.screen_rect(tabs_mark).get_center())
		panels.call("show_panel", &"shop")
		await _park(UIScale.screen_rect(tabs_mark).get_center())
		var mark_rect := UIScale.screen_rect(tabs_mark)
		var strip_rect := UIScale.screen_rect(strip)
		_check("the menu's mark stays level with the tab bar even with a page open",
			mark_rect.get_center().y <= strip_rect.end.y + 4.0,
			"mark %s vs strip %s" % [str(mark_rect), str(strip_rect)])
		panels.call("close")
		await _settle()

	# Back to held-open for everything that follows.
	await _pin_shell(true)

## Move the cursor and let the drawers settle. They ease rather than snap, so a single frame
## proves nothing either way.
func _park(point: Vector2) -> void:
	_move(point)
	for i in 45:
		await get_tree().process_frame

## Big number go up — which only works if a big number actually fits.
##
## The purse is stacked one currency per line so each glyph owns the figure beside it, and
## so the figure has a whole line to grow into. Both halves of that are asserted here: the
## number is printed in full while it fits, it does not clip, and it cannot make the HUD
## card change width no matter how long it gets.
func _the_purse_can_count_high() -> void:
	_suite("purse")
	var hud := _find(_main, "HUD")
	var purse := _find(_main, "PurseStrip")
	if hud == null or purse == null:
		_check("the purse exists", false)
		return
	await _settle()
	var width_before := (hud.call("shell_rect") as Rect2).size.x

	var samples := [
		[999.0, "999"],
		[1000.0, "1,000"],
		[1_204_880.0, "1,204,880"],
		[999_999_999.0, "999,999,999"],
	]
	for sample in samples:
		_check("%d prints as %s" % [int(sample[0]), sample[1]],
			UIStyle.format_purse(sample[0]) == sample[1], UIStyle.format_purse(sample[0]))
	# Past the point where the digits stop fitting, it abbreviates rather than clipping.
	_check("and past a billion it abbreviates", UIStyle.format_purse(2.5e9) == "2.50B",
		UIStyle.format_purse(2.5e9))

	# Now for real, in the live card.
	Economy.grant(Economy.BONES, 987_654_321.0)
	Economy.grant(Economy.HEARTS, 123_456_789.0)
	for i in 90:
		await get_tree().process_frame

	var clipped: Array[String] = []
	var counted := 0
	for node in _all_nodes(purse):
		var label := node as Label
		if label == null or not label.is_visible_in_tree() or label.text.is_empty():
			continue
		counted += 1
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		var needed := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if needed > label.size.x + 0.5:
			clipped.append("%s '%s' needs %.0f in %.0f" % [label.name, label.text, needed,
				label.size.x])
	_check("every figure fits its line at nine digits (%d checked)" % counted,
		clipped.is_empty(), ", ".join(clipped))
	_check("and the card did not change width to fit them",
		is_equal_approx((hud.call("shell_rect") as Rect2).size.x, width_before),
		"%.0f -> %.0f" % [width_before, (hud.call("shell_rect") as Rect2).size.x])

## The payout number is the game's only reward for most of a session, and it is drawn on a
## layer nothing else touches — so when it silently stopped existing, nothing noticed.
##
## It stopped because four `EventBus.connect` calls ended up after a `return` in the middle
## of `_ready()`. No parse error, no warning, no missing node: the pool was built, the layer
## was in the tree, and the game simply never showed a number, took a hit-stop, or played
## its knockout fountain again. A connection that is not made is invisible, so it is asserted.
func _the_payouts_are_visible() -> void:
	_suite("payouts")
	var fx := _find(_main, "FXLayer")
	_check("the FX layer exists and is named", fx != null)
	if fx == null:
		return

	for signal_name in ["payout", "damage_dealt", "knockout_payout", "buddy_state_changed"]:
		var wired := false
		for connection in EventBus.get_signal_connection_list(signal_name):
			if connection["callable"].get_object() == fx:
				wired = true
		_check("the FX layer is listening to %s" % signal_name, wired)

	# Focus Mode Off means the game still earns and stops shouting about it, so the gate is
	# asserted from both sides — the suite runs with it Off, which is why the payout below
	# has to turn it on deliberately.
	var before := _visible_numbers(fx)
	EventBus.payout.emit(Economy.BONES, 480.0, Vector2(VIEW_SIZE) * 0.5, &"baseball_bat")
	await _settle()
	_check("with Focus Mode Off a payout draws nothing", _visible_numbers(fx) == before)

	Settings.focus_intensity = Settings.Intensity.NORMAL
	EventBus.payout.emit(Economy.BONES, 480.0, Vector2(VIEW_SIZE) * 0.5, &"baseball_bat")
	EventBus.payout.emit(Economy.HEARTS, 7300.0, Vector2(VIEW_SIZE) * 0.5, &"open_hand")
	await _settle()
	_check("and with it on, a payout puts a number on screen",
		_visible_numbers(fx) >= before + 2, "%d -> %d" % [before, _visible_numbers(fx)])

	# The streak, drawn: three real hits through the bus put an "x3" tag on the third number.
	# The combo the same way, through the open hand.
	Economy._streak_deadline_msec = 0
	for i in 3:
		EventBus.damage_dealt.emit(HitInfo.new(20.0, &"baseball_bat", Vector2(VIEW_SIZE) * 0.5, 1000.0))
	await _settle()
	_check("a streak of three is tagged on the number", _visible_tag(fx, "x3"))
	Economy._combo_count = 0
	Economy._combo_deadline_msec = 0
	for i in 3:
		EventBus.kindness_given.emit(&"open_hand", 1.0, Vector2(VIEW_SIZE) * 0.5)
	await _settle()
	_check("a petting combo is tagged on the number", _visible_tag(fx, "x1."))
	Settings.focus_intensity = Settings.Intensity.OFF

	# The two economies must stay apart at every magnitude — including the top tier, where
	# running both ramps to white would make them identical exactly where it matters most.
	var same: Array[String] = []
	for tier in FXLayer.BONES_RAMP.size():
		var bones: Color = FXLayer.BONES_RAMP[tier]
		var hearts: Color = FXLayer.HEARTS_RAMP[tier]
		if UIStyle.contrast(bones, hearts) < 1.25 and absf(bones.h - hearts.h) < 0.08:
			same.append("tier %d" % tier)
	_check("Bones and Hearts are distinguishable at every tier%s"
		% ("" if same.is_empty() else ": " + ", ".join(same)), same.is_empty())

## Sixty-two milestones paid out with a toast and were never seen again. The Deeds page is
## where they live: one row per milestone, the secret ones masked until earned, and the
## record the player quotes to a friend.
func _the_deeds_board_is_on_the_page() -> void:
	_suite("deeds")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	panels.call("show_panel", &"deeds")
	await _settle()
	var page := _find(_main, "DeedsPanel")
	_check("the deeds page exists", page != null)
	if page == null:
		return
	var list := _find(page, "DeedsList")
	var board := ItemDB.all_milestones()
	_check("it lists every milestone on the board (%d)" % board.size(),
		list != null and list.get_child_count() == board.size())
	var hidden_unearned := 0
	for milestone in board:
		if milestone.hidden and Milestones.rungs_claimed(milestone.id) == 0:
			hidden_unearned += 1
	var masked := 0
	for label in _all_nodes(page):
		if label is Label and (label as Label).text == "A secret deed":
			masked += 1
	_check("every unearned secret deed is masked (%d of %d)" % [masked, hidden_unearned],
		masked == hidden_unearned)
	_check("the record shows his lifetime Bones",
		_label_containing(UIStyle.format_amount(Economy.lifetime_of(Economy.BONES)), page) != null)
	panels.call("close")
	await _settle()

## Prestige lived at the bottom of the Arcade tab, where a player who never opens the Arcade
## never learns the game has one. Once a run is worth a Marrow the HUD says so, and the row is
## a link to the page that spells out the trade — never a reset in itself.
func _the_hud_calls_for_rebirth() -> void:
	_suite("rebirth call")
	var hud := _find(_main, "HUD")
	var panels := _find(_main, "PanelLayer")
	var row := _find(_main, "RebirthCall") as Control
	_check("the HUD has a rebirth row", hud != null and row != null)
	if hud == null or row == null or panels == null:
		return
	panels.call("close")
	var drawer := _find(_main, "HudDrawer")
	if drawer:
		drawer.set("pinned", true)
	var count_before: int = Economy.prestige_count
	Economy.run_earnings = 0.0
	Economy.grant(Economy.BONES, 1.0)
	await get_tree().create_timer(0.6).timeout
	await _settle()
	_check("with nothing to gain it stays hidden", not row.visible)
	Economy.grant(Economy.BONES, ItemDB.balance.marrow_divisor * 4.0)
	await get_tree().create_timer(0.6).timeout
	await _settle()
	_check("once a run is worth a Marrow, it appears", row.visible)
	_check("and says what the reset would pay",
		_label_containing("Reincarnate for +", row) != null)
	await _click(_centre_of(row))
	await _settle()
	var prestige := _find(_main, "PrestigePanel") as Control
	_check("clicking it opens the Arcade", bool(panels.call("is_open"))
		and panels.get("_current") == &"arcade")
	_check("with Reincarnation on screen", prestige != null and prestige.is_visible_in_tree())
	_check("and resets nothing by itself", Economy.prestige_count == count_before)
	# And the mood row names who he is this life — it used to be a fact only the Reincarnate
	# page knew.
	var who := ItemDB.get_personality(StringName(Economy.personality))
	_check("the mood row names his personality",
		who != null and _label_containing(who.display_name, hud) != null)
	panels.call("close")
	await _settle()

## A visible floating label whose text starts with `prefix` — the streak and combo tags.
func _visible_tag(fx: Node, prefix: String) -> bool:
	for node in _all_nodes(fx):
		var label := node as Label
		if label and label.visible and label.text.begins_with(prefix):
			return true
	return false

func _visible_numbers(fx: Node) -> int:
	var count := 0
	for child in fx.get_children():
		var label := child as Label
		if label and label.visible:
			count += 1
	return count

## The one that keeps coming back, closed at the only level that actually closes it.
##
## Twice now a page has been unreadable and twice the guard in place did not see it, because
## both guards looked at the wrong thing. Grading `UIStyle`'s constants misses a colour
## overridden on one node. Grading the `Theme` misses text that is simply *absent*. Neither
## looks at what is on the screen.
##
## This walks the live tree of every page and asks two questions of every piece of text a
## player can see: is it legible against the surface actually behind it, and is there any of
## it at all. The second half is not pedantry — the Rebirth page failed by rendering two
## empty boxes, which no contrast check in the world would have caught.
func _every_page_is_readable() -> void:
	_suite("readable")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	const FLOOR := 4.5
	for page_id in [&"shop", &"tree", &"contracts", &"deeds", &"arcade", &"settings"]:
		panels.call("show_panel", page_id)
		await _settle()
		var page := _pages_page(panels, page_id)
		if page == null:
			continue
		var unreadable: Array[String] = []
		var with_text := 0
		for node in _all_nodes(page):
			var control := node as Control
			if control == null or not control.is_visible_in_tree():
				continue
			var text := ""
			if control is Label:
				text = (control as Label).text
			elif control is Button:
				text = (control as Button).text
			else:
				continue
			if text.strip_edges().is_empty():
				continue
			with_text += 1
			var ink := control.get_theme_color("font_color")
			var ratio := UIStyle.contrast(ink, _surface_behind(control))
			if ratio < FLOOR:
				unreadable.append("%s \"%s\" %.2f:1" % [control.name, text.substr(0, 18), ratio])
		_check("%s: every visible word is legible where it sits (%d checked)"
			% [page_id, with_text], unreadable.is_empty(), ", ".join(unreadable))
		# A page that came up blank passes every colour test ever written.
		_check("%s: and the page actually rendered its content" % page_id, with_text >= 3,
			"only %d pieces of text" % with_text)
	panels.call("close")
	await _settle()

func _pages_page(panels: Node, page_id: StringName) -> Control:
	var wanted := {
		&"shop": "ShopPanel", &"tree": "AugmentPanel", &"contracts": "ContractPanel",
		&"prestige": "PrestigePanel", &"settings": "SettingsPanel", &"arcade": "ArcadePanel",
		&"deeds": "DeedsPanel",
	}
	# Was a bare `wanted[page_id]`, which threw on the Arcade page — every run since M3.6
	# printed a SCRIPT ERROR here that nobody read because the assertion count stayed green.
	if not wanted.has(page_id):
		push_error("ui_check: no panel class mapped for page '%s'" % page_id)
		return null
	return _find(panels, wanted[page_id]) as Control

## The fill of the nearest styled box at or above this control — which is what its text is
## actually printed on, whatever the palette says it should be.
func _surface_behind(control: Control) -> Color:
	var walk: Node = control
	while walk is Control:
		var here := walk as Control
		var box: StyleBox = null
		if here is Button:
			box = here.get_theme_stylebox("normal")
		elif here is PanelContainer or here is Panel:
			box = here.get_theme_stylebox("panel")
		var flat := box as StyleBoxFlat
		if flat and flat.bg_color.a > 0.5:
			return flat.bg_color
		walk = here.get_parent()
	return UIStyle.PANEL

## The alignment class the owner photographed, as an assertion.
##
## Three separate symptoms — rows of different heights, names starting at different x,
## a picture spilling past the tile that holds it — were one cause: nothing normalised an
## item's art to the box the UI reserved for it, so the layout faithfully rendered whatever
## size the PNG on disk happened to be. Now the box is the contract, and this is what says
## so. It runs over every page, so it also covers pages that do not exist yet.
func _nothing_overflows_its_box() -> void:
	_suite("geometry")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	var offenders: Array[String] = []
	var checked := 0
	for page_id in [&"shop", &"tree", &"contracts", &"deeds", &"arcade", &"settings"]:
		panels.call("show_panel", page_id)
		await _settle()
		for node in _all_nodes(_main):
			var texture: Texture2D = null
			var control: Control = null
			if node is TextureRect and (node as TextureRect).texture:
				control = node as Control
				texture = (node as TextureRect).texture
			elif node is Button and (node as Button).icon:
				control = node as Control
				texture = (node as Button).icon
			if texture == null or not control.is_visible_in_tree():
				continue
			# The **declared** box, not the realised one. A Button and a PanelContainer both
			# grow to fit an oversized icon, so measuring what they ended up as would have
			# passed the exact bug this suite exists to catch: the row was 74px tall
			# *because* the art was 64, and comparing the two would have called that a fit.
			var box := control.custom_minimum_size
			if box == Vector2.ZERO:
				box = control.size
			checked += 1
			var art := texture.get_size()
			if (box.x > 0.0 and art.x > box.x + 0.5) or (box.y > 0.0 and art.y > box.y + 0.5):
				offenders.append("%s: %dx%d art in a %dx%d box"
					% [node.name, int(art.x), int(art.y), int(box.x), int(box.y)])
	_check("every picture fits the box reserved for it (%d checked)" % checked,
		offenders.is_empty(), ", ".join(offenders))
	# Fitting is not enough — it has to fit *at its own size*. A box smaller than the art
	# does not crop it, it halves it: the shop's 32px icons were being asked for in a 24px
	# box and drawn at 16, and the tiny glyph marks at 13 and 14 were drawn at 8.
	_check("and none of it had to be shrunk to get there", UIStyle.shrunk.is_empty(),
		", ".join(UIStyle.shrunk))

	# A list is scanned, so its rows have to be one height and its names one indent. A
	# single oversized icon used to make one row nearly twice the height of the row under it.
	panels.call("show_panel", &"shop")
	await _settle()
	var shop := _find(_main, "ShopPanel")
	if shop:
		for category in [0, 1, 2, 3, 4]:
			if not shop.has_method("show_category"):
				break
			shop.call("show_category", category)
			await _settle()
			var heights: Array[float] = []
			for node in _all_nodes(shop):
				if node is Button and (node as Button).theme_type_variation == &"ListRow" \
						and (node as Button).is_visible_in_tree():
					heights.append((node as Button).size.y)
			if heights.size() < 2:
				continue
			var uniform := true
			for h in heights:
				if absf(h - heights[0]) > 0.5:
					uniform = false
			_check("category %d: all %d rows are one height" % [category, heights.size()],
				uniform, str(heights))

	# A tier is read across, so its cards share a baseline. Whichever node's effect text
	# wraps to two lines must not drop its own pips and price below its neighbours'.
	panels.call("show_panel", &"tree")
	await _settle()
	var tree := _find(_main, "AugmentPanel")
	if tree:
		var rows := {}
		for node in _all_nodes(tree):
			if node is PanelContainer and (node as PanelContainer).has_meta(&"buy"):
				var card := node as PanelContainer
				if not card.is_visible_in_tree():
					continue
				var buy := card.get_meta(&"buy") as Control
				var key := int(card.global_position.y)
				if not rows.has(key):
					rows[key] = []
				(rows[key] as Array).append(buy.global_position.y)
		var ragged: Array[String] = []
		for key in rows:
			var ys := rows[key] as Array
			for y in ys:
				if absf(float(y) - float(ys[0])) > 0.5:
					ragged.append(str(ys))
					break
		_check("every card in a tier puts its buy key on the same line (%d tiers)"
			% rows.size(), ragged.is_empty(), ", ".join(ragged))

	panels.call("close")
	await _settle()

## No page may be left flagged visible under a shut card. That gap is what made every
## page's `if visible:` guard a no-op and left five pages doing full refreshes per hit,
## forever, in a game that is meant to idle under someone's work.
func _closed_pages_do_no_work() -> void:
	_suite("closed pages")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	panels.call("show_panel", &"shop")
	await _settle()
	panels.call("close")
	await _settle()

	var pages: Array[Node] = []
	for node in _all_nodes(_main):
		if node is PanelPage:
			pages.append(node)
	_check("every page of the card is a PanelPage", pages.size() >= 5, str(pages.size()))

	var lying: Array[String] = []
	for page in pages:
		var control := page as Control
		if control.visible != control.is_visible_in_tree():
			lying.append(control.name)
	_check("no page is flagged visible under a shut card", lying.is_empty(), ", ".join(lying))

	var before: Array[int] = []
	for page in pages:
		before.append(int(page.get("refresh_count")) + int(page.get("rebuild_count")))
	for i in 20:
		EventBus.currency_changed.emit(Economy.BONES, Economy.balance_of(Economy.BONES))
	await _settle()
	var moved: Array[String] = []
	for i in pages.size():
		var now := int(pages[i].get("refresh_count")) + int(pages[i].get("rebuild_count"))
		if now != before[i]:
			moved.append("%s +%d" % [pages[i].name, now - before[i]])
	_check("20 currency events with the card shut cost nothing", moved.is_empty(),
		", ".join(moved))

	# And the work is deferred, not dropped: opening the page catches it up.
	panels.call("show_panel", &"shop")
	await _settle()
	var shop_page := _find(_main, "ShopPanel")
	_check("opening the page pays the deferred refresh",
		shop_page != null and not (shop_page as PanelPage).is_dirty())
	panels.call("close")
	await _settle()

func _label_containing(text: String, root: Node) -> Label:
	for node in _all_nodes(root):
		if node is Label and (node as Label).text.contains(text):
			return node
	return null

## Off-screen and scrolled-out-of-view buttons are clipped, so a hit test on them proves
## nothing. Only judge what the player can actually see.
func _is_on_screen(control: Control) -> bool:
	var centre := _centre_of(control)
	if not Rect2(Vector2.ZERO, Vector2(VIEW_SIZE)).has_point(centre):
		return false
	var walk := control.get_parent()
	while walk is Control:
		if walk is ScrollContainer and not UIScale.screen_rect(walk as Control).has_point(centre):
			return false
		walk = walk.get_parent()
	return true

## The blocker above also killed physics picking, so dragging the buddy stopped working
## at the same time and for the same reason: the viewport marks a click handled the moment
## any control claims it, and both the hover test and BaseDraggable run on unhandled input.
func _the_buddy_still_takes_clicks() -> void:
	_suite("the world")
	var panels := _find(_main, "PanelLayer")
	if panels and panels.call("is_open"):
		panels.call("close")
		await _settle()
	var buddy := _find(_main, "Buddy") as RigidBody2D
	_check("buddy exists", buddy != null)
	if buddy == null:
		return
	# Held still so the click lands where the hover test looked.
	buddy.freeze = true
	await _settle()
	var at := buddy.global_position
	_check("no UI control sits over the buddy (got %s)"
		% _describe(_hovered_at(at)), _hovered_at(at) == null)
	await _settle()
	_check("the buddy's drag area sees the cursor", bool(buddy.get("drag_area").is_hovered))
	await _press(at)
	_check("pressing on the buddy starts a drag", bool(buddy.get("dragging")))
	await _release(at)
	_check("releasing lets go of him", not bool(buddy.get("dragging")))
	buddy.freeze = false

# --- input helpers ---------------------------------------------------------

## Screen space, via the canvas transform. `get_global_rect()` stops at the CanvasLayer,
## so the moment a layer is scaled by `UIScale` every rect it returns is wrong by exactly
## that factor — and every hit test in this file silently starts testing the wrong point.
## Brings a control into view inside whichever ScrollContainer holds it, then settles.
##
## The Rebirth page used to be a tab of its own and its button was always on screen. It is
## now the back room of the Arcade, below three machines, so a click at its centre lands on
## whatever the card is actually showing — which is a real click on a real widget and
## therefore fails in a way that looks like the button not working.
## He notices the player (docs/plan-expressive-buddy.md §6.18-21). Headless, so there is no
## DisplayServer focus event to raise: the notifications are sent by hand. The cursor is a
## synthetic motion event through the viewport and the sensor's own `mouse_entered` — the
## one path a test can drive, which is why nothing on the character may poll the OS cursor.
func _he_notices_the_player() -> void:
	_suite("he notices you")
	var panels := _find(_main, "PanelLayer")
	if panels and panels.call("is_open"):
		panels.call("close")
		await _settle()
	var buddy := _find(_main, "Buddy") as Buddy
	_check("buddy exists", buddy != null)
	if buddy == null or buddy.expression == null or buddy.art == null or buddy.drag_area == null:
		_check("with an expression brain, art and a hover sensor", false)
		return
	var brain: ExpressionBrain = buddy.expression
	var art: BuddyArt = buddy.art
	var focus_before := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL
	buddy.freeze = true
	await _settle()

	# Away and back.
	buddy._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("losing focus starts the away clock", brain._away_since > 0)
	brain._clock_skew += brain.REUNION_AFTER_MSEC + 1000
	buddy._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("coming back after a minute is a reunion", brain.beat_id() == &"reunion")
	_check("and it shows on his face", art.face.animation == &"shocked")
	_check("and the clock is cleared", brain.away_seconds() == 0.0)
	brain.clear()
	buddy._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	buddy._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("a moment away earns no greeting", brain.beat_id() != &"reunion")

	# Hover and gaze: over his grab rect, the other side of it, off it, out of the window.
	var centre := buddy.global_position
	var where := buddy.global_position
	await _move(centre + Vector2(30, -10))
	await _settle()
	_check("motion over him sets hover", buddy.drag_area.is_hovered)
	_check("and he attends to the cursor", brain.attention() == ExpressionBrain.ATTEND_CURSOR)
	_check("and at Normal his gaze leans toward it", art.look_x() > 0.0)
	await _move(centre + Vector2(-30, -10))
	await _settle()
	_check("and follows it to the other side", art.look_x() < 0.0)
	_check("he looks; he never chases", buddy.global_position == where)
	await _move(centre + Vector2(400, -300))
	await _settle()
	_check("motion away clears hover", not buddy.drag_area.is_hovered)
	_check("and drops the gaze", is_zero_approx(art.look_x()))
	await _move(centre + Vector2(30, -10))
	await _settle()
	_check("(hovering again)", buddy.drag_area.is_hovered)
	buddy._notification(NOTIFICATION_WM_MOUSE_EXIT)
	_check("leaving the window drops it too", is_zero_approx(art.look_x())
		and brain.attention() != ExpressionBrain.ATTEND_CURSOR)
	await _move(centre + Vector2(400, -300))
	await _settle()

	# At Off he still knows you are there, but he does not look.
	Settings.focus_intensity = Settings.Intensity.OFF
	await _move(centre + Vector2(30, -10))
	await _settle()
	_check("at Off, hover still registers", buddy.drag_area.is_hovered)
	_check("but the gaze stays home", is_zero_approx(art.look_x()))
	await _move(centre + Vector2(400, -300))
	await _settle()

	# Nothing on the character reads the OS cursor: a synthetic event cannot move it.
	for path in ["res://Scripts/Buddy/expression_brain.gd", "res://Scripts/Buddy/buddy_art.gd",
			"res://Scripts/Buddy/buddy.gd"]:
		var source := FileAccess.get_file_as_string(path)
		_check("%s never polls the mouse" % path.get_file(),
			not source.contains("get_mouse_position(") and not source.contains("get_global_mouse_position("))

	buddy.freeze = false
	Settings.focus_intensity = focus_before
	await _settle()

func _scroll_into_view(control: Control) -> void:
	var node: Node = control.get_parent()
	while node != null and not (node is ScrollContainer):
		node = node.get_parent()
	var scroll := node as ScrollContainer
	if scroll == null:
		return
	scroll.scroll_vertical = int(control.global_position.y - scroll.global_position.y
		+ scroll.scroll_vertical - scroll.size.y * 0.5)
	await _settle()

func _centre_of(control: Control) -> Vector2:
	return UIScale.screen_centre(control)

func _hovered_at(point: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_view.push_input(motion, true)
	return _view.gui_get_hovered_control()

func _click(point: Vector2) -> void:
	_hovered_at(point)
	_button_event(point, true)
	_button_event(point, false)
	await _settle()

func _press(point: Vector2) -> void:
	_hovered_at(point)
	_button_event(point, true)
	await _settle()

func _release(point: Vector2) -> void:
	_button_event(point, false)
	await _settle()

## Holds both halves of the shell open, or lets them go back to hiding on hover. Looked up
## by node name: `get_class()` on a script class returns its *engine* base ("Node"), so
## searching for one by its `class_name` finds nothing.
func _pin_shell(value: bool) -> void:
	for drawer_name in ["HudDrawer", "TabsDrawer"]:
		var drawer := _find(_main, drawer_name)
		if drawer:
			drawer.set("pinned", value)
	await _settle()

## A bare motion event. `_hovered_at` sends one too, but this is the whole gesture for
## anything that reads the cursor rather than a click.
func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_view.push_input(motion)

func _button_event(point: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.pressed = pressed
	click.position = point
	click.global_position = point
	_view.push_input(click, true)

## A control is a blocker if it reaches most of the window and draws nothing the player
## can see — the signature of a layout container left on its default mouse filter.
func _covers_everything(control: Control) -> String:
	if control == null:
		return ""
	var area := UIScale.screen_rect(control).size
	if area.x < VIEW_SIZE.x * 0.9 or area.y < VIEW_SIZE.y * 0.9:
		return ""
	if control is Container or control.get_class() == "Control":
		return "%s spans the window on layer %d" % [_describe(control), _layer_of(control)]
	return ""

func _layer_of(node: Node) -> int:
	var walk := node
	while walk:
		if walk is CanvasLayer:
			return (walk as CanvasLayer).layer
		walk = walk.get_parent()
	return 0

func _describe(control: Control) -> String:
	if control == null:
		return "<nothing>"
	return "%s(%s)" % [control.get_class(), control.name]

# --- tree helpers ----------------------------------------------------------

## Some controls are pictures now — the card's page tabs, the close button, the shop's
## category tabs. A test that matches on button text quietly stops testing anything the
## moment a caption becomes a glyph, so those are found by the tooltip that replaced the
## caption, which is also the thing a screen reader and a hovering player get.
func _button_tooltipped(text: String, root: Node) -> Button:
	if root == null:
		return null
	for node in _all_nodes(root):
		if node is Button and (node as Button).tooltip_text == text \
				and (node as Button).is_visible_in_tree():
			return node
	return null

func _button_labelled(text: String, root: Node) -> Button:
	if root == null:
		return null
	for node in _all_nodes(root):
		if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
			return node
	return null

func _find(root: Node, class_or_name: String) -> Node:
	for node in _all_nodes(root):
		if node.get_class() == class_or_name or node.name == class_or_name \
				or (node.get_script() and (node.get_script() as Script).get_global_name() == class_or_name):
			return node
	return null

func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		out.append_array(_all_nodes(child))
	return out

func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await get_tree().physics_frame

# --- reporting -------------------------------------------------------------

func _suite(title: String) -> void:
	print("")
	print("-- %s" % title)

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("   ok   %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s%s" % [what, "" if detail == "" else "  <- " + detail])

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
