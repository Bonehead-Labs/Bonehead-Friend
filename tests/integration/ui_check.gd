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
	# Before anything else in the suite, including the capture below (D51). Redirecting the
	# file is what actually makes this safe: the restore on the last line only runs if the
	# run reaches its last line, and a timeout, a parse error in an edit or a Ctrl-C all skip
	# it. One killed run left Focus Mode Off in the owner's real settings, and the next launch
	# looked like the payout numbers had stopped working.
	Settings.config_path = "user://settings_ui_check.cfg"
	_restore = {
		"focus": Settings.focus_intensity,
		"scale": Settings.ui_scale,
		"play_area": Settings.play_area_size,
		"hud_pinned": Settings.hud_pinned,
		"tabs_pinned": Settings.tabs_pinned,
		"backdrop": Settings.backdrop,
		# Duplicated, not aliased: the one-off tips are an Array on the singleton, and
		# holding a reference to it would "restore" whatever the run appended. The suite puts
		# an item on the desk and equips a power, and both of those fire a hint that marks
		# itself seen and saves — so without this a developer would silently lose the tips
		# they have not met yet, and only find out by never being taught the controls.
		"hints": Settings.hints_seen.duplicate(),
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

	_the_suite_writes_nowhere_real()
	_the_window_has_one_grab_point()
	_nothing_blocks_the_window()
	await _the_strip_opens_the_panels()
	await _the_card_is_one_size()
	await _shop_tiles_are_clickable()
	await _the_shop_describes_what_is_listed()
	await _every_visible_button_is_reachable()
	await _the_capstone_levels_and_switches()
	await _the_settings_page_works()
	await _feedback_is_two_taps_away()
	await _the_rebirth_page_refuses_an_empty_reset()
	await _the_tabs_are_one_width()
	await _every_page_is_readable()
	await _the_deeds_board_is_on_the_page()
	await _the_hud_calls_for_rebirth()
	await _the_wardrobe_is_on_the_arcade_page()
	await _the_arcade_is_one_room_at_a_time()
	await _the_stake_is_a_stepper()
	await _the_backdrop_is_a_choice()
	await _the_jobs_tab_wears_a_badge()
	await _the_purse_can_count_high()
	await _the_payouts_are_visible()
	await _the_big_numbers_dodge_the_hud()
	await _the_numbers_keep_apart()
	await _abilities_read_clear_of_him()
	await _numbers_leave_without_a_ghost()
	await _the_hud_reads_on_any_desk()
	await _the_power_leaves_your_hands_free()
	await _the_world_has_juice()
	await _the_sounds_are_recorded()
	await _the_hud_points_at_the_next_toy()
	await _the_shell_hides_until_hovered()
	await _nothing_overflows_its_box()
	await _the_shell_at_every_menu_size()
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
	Settings.backdrop = _restore["backdrop"]
	Settings.hints_seen = _restore["hints"]
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

	# A press on the desk rolls the card up, so playing never means a trip back to the tab.
	# The desk is wherever no control takes the mouse; find a patch of it.
	var desk := Vector2(-1, -1)
	for y in range(40, int(VIEW_SIZE.y) - 20, 40):
		for x in range(20, int(VIEW_SIZE.x) - 20, 40):
			if _hovered_at(Vector2(x, y)) == null:
				desk = Vector2(x, y)
				break
		if desk.x >= 0.0:
			break
	_check("there is desk to click with the card open", desk.x >= 0.0)
	if desk.x >= 0.0:
		await _click(_centre_of(_find(panels, "Card") as Control))
		_check("a click on the card leaves it open", panels.call("is_open"))
		await _click(desk)
		_check("a click on the desk rolls the card up", not panels.call("is_open"))
		await _click(_centre_of(toys))
		_check("and the tab opens it again", panels.call("is_open"))

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

## The detail pane describes a row of the list on screen, never an item from another drawer.
##
## `ui_shots` 03-toys-kind came back with the Care tab lit over a pane describing the Boombox:
## the tool asked for Care and then selected an item M3.7-B had moved to Mood. The shop was
## right — the one production caller, `PanelLayer._on_show_item`, opens the item's own drawer
## first — so this pins that path for one item in each kind drawer, and the capture tools'
## own staging, which now reads the drawer off the item's data.
func _the_shop_describes_what_is_listed() -> void:
	_suite("shop drawers")
	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	if panels == null or shop == null:
		_check("the shop is there to ask", false)
		return
	for id in [&"boombox", &"pizza", &"baseball", &"sponge", &"beanbag"]:
		var item := ItemDB.get_item(id)
		if item == null:
			continue
		EventBus.ui_show_item.emit(id)
		await _settle()
		_check("asked for the %s, the shop opens its own drawer and selects it in the list" % id,
			shop.get("_category") == item.category and shop.get("_selected") == id
				and (shop.get("_rows") as Dictionary).has(id),
			"drawer %s, selected %s" % [shop.get("_category"), shop.get("_selected")])
	shop.call("show_category", ItemDB.get_item(&"boombox").category)
	shop.call("select", &"boombox")
	await _settle()
	_check("the capture tools' staging lists what it selects",
		(shop.get("_rows") as Dictionary).has(shop.get("_selected")))
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

	for pair in [["Harm", ["Melee", "Boom", "Cursor", "Turret", "Critters", "Guns"]],
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

const FEEDBACK_ROOT := "user://playtest_ui_check"
const FEEDBACK_SEND := "user://playtest_ui_check_send"

## The playtest kit's card (docs/playtest-plan.md): two taps from anywhere, the keyboard reaches
## it, Esc backs out of it before the Esc menu hears, and what it saves carries what it promises.
##
## The window is transparent and has no click-through, so the one thing that could stop a note
## being typed is focus — which is why this types into it, rather than setting its text.
func _feedback_is_two_taps_away() -> void:
	_suite("feedback")
	var card := _find(_main, "FeedbackCard")
	var panels := _find(_main, "PanelLayer")
	var esc := _find(_main, "EscMenu")
	_check("the feedback card exists", card != null and panels != null and esc != null)
	if card == null or panels == null or esc == null:
		return
	var log_before := Settings.playtest_log
	# Its own folders, before anything is written — the same rule as the settings file (D51).
	for dir in [FEEDBACK_ROOT, FEEDBACK_SEND]:
		_remove_tree(dir)
	Playtest.use_root(FEEDBACK_ROOT)
	Playtest.send_dir = FEEDBACK_SEND
	Playtest.upload_config_path = "user://playtest_ui_check_no_such.cfg"
	var blocker := _find(card, "FeedbackBlocker") as Control
	_check("it is shut on boot, and its full-window blocker lets every click through",
		not bool(card.call("is_open")) and blocker != null
		and blocker.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# Tap one, the Settings tab; tap two, the key.
	panels.call("show_panel", &"settings")
	await _settle()
	var settings_page := _find(_main, "SettingsPanel")
	var key := _button_labelled("Leave a note", settings_page)
	_check("Settings offers 'Leave a note'", key != null)
	if key == null:
		return
	await _scroll_into_view(key)
	_check("and it is the control under the cursor", _hovered_at(_centre_of(key)) == key,
		_describe(_hovered_at(_centre_of(key))))
	await _click(_centre_of(key))
	_check("clicking it opens the card", bool(card.call("is_open")))
	var text := _find(card, "FeedbackText") as TextEdit
	var trying := _find(card, "FeedbackTrying") as LineEdit
	_check("the note box has the keyboard", text != null and text.has_focus(),
		_describe(_view.gui_get_focus_owner()))
	_type("hi")
	await _settle()
	_check("typing reaches it", text != null and text.text == "hi", text.text if text else "")
	for control_name in ["Mood_good", "Mood_meh", "Mood_bad", "FeedbackText", "FeedbackTrying",
			"FeedbackSave", "FeedbackCancel"]:
		var control := _find(card, control_name) as Control
		_check("%s is the control under the cursor" % control_name,
			control != null and _hovered_at(_centre_of(control)) == control,
			_describe(_hovered_at(_centre_of(control))) if control else "missing")
	await _click(_centre_of(_find(card, "Mood_good") as Control))
	_check("one tap picks a mood", String(card.get("_mood")) == "good")
	await _click(_centre_of(trying))
	_type("x")
	await _settle()
	_check("a click moves the keyboard to the second line, and typing follows it",
		trying.has_focus() and trying.text == "x", trying.text)
	await _click(_centre_of(_find(card, "FeedbackSave") as Control))
	_check("saving closes the card and lets go of the keyboard",
		not bool(card.call("is_open")) and _view.gui_get_focus_owner() == null,
		_describe(_view.gui_get_focus_owner()))
	var notes := Array(DirAccess.get_files_at("%s/feedback" % FEEDBACK_ROOT)).filter(
		func(n: String) -> bool: return n.ends_with(".json"))
	var note = JSON.parse_string(FileAccess.get_file_as_string("%s/feedback/%s" % [FEEDBACK_ROOT, notes[0]])) \
		if notes.size() == 1 else null
	_check("one note is written", typeof(note) == TYPE_DICTIONARY, str(notes))
	if typeof(note) == TYPE_DICTIONARY:
		var context: Dictionary = note.get("context", {})
		_check("with what was chosen and typed", note["mood"] == "good" and note["text"] == "hi"
			and note["trying"] == "x", str([note["mood"], note["text"], note["trying"]]))
		_check("and the page it was written on, the purse and the build",
			context.get("page", "") == "settings" and (context.get("currencies", {}) as Dictionary).has("bones")
			and String(note["build"]) == BuildInfo.id(), str(context.get("page", "")))

	# Anywhere: F1 with the card shut, and Esc backs out of the card, not into the pause menu.
	panels.call("close")
	await _settle()
	await _key(KEY_F1)
	_check("F1 opens it from anywhere", bool(card.call("is_open")))
	await _key(KEY_ESCAPE)
	_check("Esc closes the card, and the Esc menu does not also open",
		not bool(card.call("is_open")) and not bool(esc.get("_open")))
	esc.call("open")
	await _settle()
	var from_menu := _button_labelled("Feedback (F1)", esc)
	_check("the Esc menu offers it too, under the cursor",
		from_menu != null and _hovered_at(_centre_of(from_menu)) == from_menu)
	if from_menu:
		await _click(_centre_of(from_menu))
		await get_tree().create_timer(0.35).timeout
		await _settle()
		_check("and it opens the card once the menu has gone",
			bool(card.call("is_open")) and not bool(esc.get("_open")))
		await _click(_centre_of(_find(card, "FeedbackCancel") as Control))
		_check("Cancel closes it without a note", not bool(card.call("is_open"))
			and Array(DirAccess.get_files_at("%s/feedback" % FEEDBACK_ROOT)).filter(
				func(n: String) -> bool: return n.ends_with(".json")).size() == 1)

	# The other keys: Send writes one zip where it was asked to (there is no uploader), and the
	# log's switch is the tester's to flip.
	panels.call("show_panel", &"settings")
	await _settle()
	var send := _button_labelled("Send feedback", settings_page)
	if send:
		await _scroll_into_view(send)
		await _click(_centre_of(send))
	var zips := Array(DirAccess.get_files_at(FEEDBACK_SEND)) if DirAccess.dir_exists_absolute(FEEDBACK_SEND) else []
	_check("Send feedback writes one zip, with no uploader configured", send != null and zips.size() == 1,
		str(zips))
	var toggle := _stepper_beside("Session log", settings_page)
	if toggle:
		await _scroll_into_view(toggle)
		await _click(_centre_of(toggle))
	_check("the session log's switch flips the setting", toggle != null and Settings.playtest_log != log_before)
	panels.call("close")
	await _settle()

	Settings.playtest_log = log_before
	Settings.save_settings()
	Playtest.use_root(Playtest.ROOT_DIR)
	Playtest.send_dir = ""
	Playtest.upload_config_path = ""
	for dir in [FEEDBACK_ROOT, FEEDBACK_SEND]:
		_remove_tree(dir)

## The feedback card at one Menu size: open, measured against the window, shut. "" if it fits.
func _feedback_card_fits() -> String:
	var card := _find(_main, "FeedbackCard")
	if card == null:
		return "no card"
	card.call("open_card")
	await _settle()
	var view := Rect2(Vector2.ZERO, Vector2(_view.size))
	var problems: Array[String] = []
	for control_name in ["FeedbackPanel", "FeedbackText", "FeedbackTrying", "FeedbackSave"]:
		var control := _find(card, control_name) as Control
		if control == null:
			problems.append("%s missing" % control_name)
			continue
		var rect := UIScale.screen_rect(control)
		if not view.grow(0.5).encloses(rect):
			problems.append("%s %s" % [control_name, rect])
	card.call("close_card")
	await _settle()
	return ", ".join(problems)

## The key a row puts after its readout, found by the readout's caption.
func _stepper_beside(caption: String, root: Node) -> Button:
	var label := _label_containing(caption, root)
	if label == null:
		return null
	for sibling in label.get_parent().get_children():
		if sibling is Button:
			return sibling
	return null

## Typing, one character at a time, the way a keyboard does it: a press carrying the character,
## then a release.
func _type(text: String) -> void:
	for character in text:
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.keycode = OS.find_keycode_from_string(character.to_upper())
			event.unicode = character.unicode_at(0)
			event.pressed = pressed
			_view.push_input(event)

func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		_view.push_input(event)
	await _settle()

func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)

## Reincarnation throws away the entire run, so the one thing worth asserting in a click
## test is that it cannot be triggered by accident: disabled with nothing to gain, and two
## presses even when there is.
func _the_rebirth_page_refuses_an_empty_reset() -> void:
	_suite("rebirth")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	panels.call("show_panel", &"arcade")
	_find(_main, "ArcadePanel").call("show_room", &"rebirth")
	await _settle()

	var page := _find(_main, "PrestigePanel")
	_check("the rebirth page exists", page != null)
	if page == null:
		return
	# Between lives: the offline cap is sold here, because it survives the reset like Marrow.
	var sleep_button: Button = null
	for node in _all_nodes(page):
		if node is Button and (node as Button).text.begins_with("Sleep"):
			sleep_button = node
	_check("it sells a longer sleep for Hearts", sleep_button != null)

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
	_find(_main, "ArcadePanel").call("show_room", &"rebirth")
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
	_check("and the best streak", _label_containing("BEST STREAK", page) != null)
	_check("and the best round", _label_containing("BEST ROUND", page) != null)
	_check("and this session's receipt", _label_containing("THIS SESSION", page) != null
		or _label_containing("This session", page) != null)
	panels.call("close")
	await _settle()

## The Jobs tab wears a count when a finished contract is waiting to be claimed — the one page
## that can owe the player money while it is shut.
func _the_jobs_tab_wears_a_badge() -> void:
	_suite("jobs badge")
	var badge := _find(_main, "Badge_contracts") as Control
	_check("the Jobs tab has a badge", badge != null)
	if badge == null:
		return
	Progression.refresh_contracts(true)
	var contract := ItemDB.get_contract(&"daily_damage")
	if contract == null:
		_check("a damage contract exists to finish", false)
		return
	# **The board is the day's draw, so it holds exactly the contract under test.** The draw is
	# seeded by the date (`Progression._roll`) and ten contracts count `deal_damage`. On a day
	# that also drew one with a lower target, the single emit below finished both: the badge
	# read "2", and claiming one left it lit. That is how this passed on 2026-09-07 and failed
	# on 2026-09-25 with no code change. The badge is the subject here, not the draw.
	var drawn := Progression._active_contracts.duplicate()
	var rivals := PackedStringArray()
	for id in drawn:
		var other := ItemDB.get_contract(id)
		if id != contract.id and other != null and other.goal_key == contract.goal_key:
			rivals.append(String(id))
	Progression._active_contracts.clear()
	Progression._active_contracts.append(contract.id)
	EventBus.contract_board_changed.emit()
	await _settle()
	_check("with nothing claimable it is hidden (today's draw also counts damage on: %s)"
		% ("nothing" if rivals.is_empty() else ", ".join(rivals)), not badge.visible)
	EventBus.contract_event.emit(&"deal_damage", contract.target)
	await _settle()
	_check("a finished contract shows a count", badge.visible
		and _label_containing("1", badge) != null)
	_check("claiming it clears the badge", Progression.claim_contract(contract.id))
	await _settle()
	_check("(badge hidden again)", not badge.visible)
	Progression._active_contracts.assign(drawn)
	EventBus.contract_board_changed.emit()
	await _settle()

## The wardrobe is the one thing in the Arcade that is not a gamble, and the Dollars sink the
## design owed the currency: a row per finish, and the button buys, wears or says worn.
func _the_wardrobe_is_on_the_arcade_page() -> void:
	_suite("wardrobe")
	var panels := _find(_main, "PanelLayer")
	if panels == null:
		return
	panels.call("show_panel", &"arcade")
	_find(_main, "ArcadePanel").call("show_room", &"wardrobe")
	await _settle()
	var list := _find(_main, "Wardrobe")
	_check("the arcade has a wardrobe", list != null)
	if list == null:
		return
	# A key per cosmetic on the rails (D58: a stage of swatches and a deck for the one you
	# picked, where it used to be a list of ten tall rows that scrolled off the card).
	var keys: Array[Button] = []
	for node in _all_nodes(list):
		if node is Button and String(node.name).begins_with("Swatch_"):
			keys.append(node)
	_check("with a key per cosmetic (%d of %d)" % [keys.size(), ItemDB.all_cosmetics().size()],
		keys.size() == ItemDB.all_cosmetics().size())
	var worn := 0
	var priced := 0
	for node in _all_nodes(list):
		if node is Label and (node as Label).is_visible_in_tree():
			var text := (node as Label).text
			if text == "Worn":
				worn += 1
			elif text != "Owned" and text.strip_edges() != "" and text[0].is_valid_int():
				priced += 1
	_check("the free finish is worn by default", worn >= 1)
	_check("and the rest are priced", priced >= 5)
	# A paid set of headphones is shown in the colour the shader dyes it (its tint), not in a
	# teal multiplied by it — the swatches once sold Pink Cans as navy and Gold Cans as green.
	var arcade := _find(_main, "ArcadePanel")
	var misshown: Array[String] = []
	for cosmetic in ItemDB.all_cosmetics():
		if cosmetic.slot == CosmeticData.SLOT_PHONES and not cosmetic.is_free():
			var shown: Color = arcade.call("_swatch_colour", cosmetic)
			if not shown.is_equal_approx(cosmetic.tint):
				misshown.append(String(cosmetic.id))
	_check("headphone swatches show the dyed colour", misshown.is_empty(), ", ".join(misshown))
	# Buy the cheapest priced finish with exactly its price and it is worn at once: click its
	# swatch to choose it, then the deck's key.
	var cheapest: CosmeticData = null
	for cosmetic in ItemDB.all_cosmetics():
		if not cosmetic.is_free() and not Economy.owns_cosmetic(cosmetic.id) \
				and (cheapest == null or cosmetic.price_dollars < cheapest.price_dollars):
			cheapest = cosmetic
	if cheapest:
		Economy.grant(Economy.DOLLARS, float(cheapest.price_dollars))
		var page := _find(_main, "ArcadePanel")
		page.call("request_refresh")
		await _settle()
		var swatch: Button = (page.get("_wardrobe_rows") as Dictionary)[cheapest.id]["key"]
		await _scroll_into_view(swatch)
		await _click(_centre_of(swatch))
		await _settle()
		_check("clicking a swatch chooses it", page.get("_wardrobe_selected") == cheapest.id
			and swatch.button_pressed)
		_check("and nothing is bought by choosing", not Economy.owns_cosmetic(cheapest.id))
		var action := _find(page, "WardrobeAction") as Button
		_check("the deck's key carries its price", action != null
			and action.text == UIStyle.format_amount(float(cheapest.price_dollars)))
		if action:
			await _scroll_into_view(action)
			await _click(_centre_of(action))
			await _settle()
		_check("clicking the deck's key buys it and he wears it", Economy.is_wearing(cheapest.id))
		_check("and the key says so", action != null and action.text == "Worn" and action.disabled)
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

## A payout that lands under the HUD steps aside instead of hiding behind it (D48).
##
## The HUD is anchored to a corner someone's buddy is regularly standing in, and the top
## payout tier is 48px of text with an 11px outline — so the biggest, rarest, most
## deliberately-earned number in the game was the one most likely to be unreadable. Asserted
## against the HUD's own `shell_rect()` rather than a constant, because the box's size moves
## with the menu scale and a hard-coded rect would pass at 1x and lie at 3x.
func _the_big_numbers_dodge_the_hud() -> void:
	_suite("hud dodge")
	var fx := _find(_main, "FXLayer")
	var hud := get_tree().get_first_node_in_group(HUD.GROUP_HUD)
	if fx == null or hud == null or not hud.has_method("shell_rect"):
		_check("the FX layer and the HUD are both present to test", false)
		return

	# Draw order first, because position cannot beat it. D48 moved the numbers out of the
	# HUD's corner and the owner still had a knockout headline painted over by the status
	# card: FXLayer was on layer 5 and the HUD on 10, so every number lost wherever it sat.
	# Below the panels on purpose — a payout scrolling across an open shop is worse than one
	# the player missed.
	var panels := _find(_main, "PanelLayer") as CanvasLayer
	_check("payout numbers draw above the HUD, not behind it (%d vs %d)"
		% [(fx as CanvasLayer).layer, (hud as CanvasLayer).layer],
		(fx as CanvasLayer).layer > (hud as CanvasLayer).layer)
	if panels:
		_check("and below the panels, so an open page is never scribbled on",
			(fx as CanvasLayer).layer < panels.layer)

	var keep: Rect2 = hud.call("shell_rect")
	_check("the HUD reports a rect to keep clear of", keep.size.x > 0.0 and keep.size.y > 0.0,
		"rect %s" % keep)
	if keep.size.x <= 0.0:
		return

	var saved := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL
	for label in fx.get_children():
		if label is Label:
			(label as Label).visible = false

	# Straight into the middle of the HUD, at the knockout tier — the worst case.
	fx.call("spawn_number", "KNOCKOUT  +999", keep.get_center(), FXLayer.BONES_RAMP[0], 1.6,
		FXLayer.TIER_SIZE.size() - 1)
	await _settle()
	# Measured once its punch has settled. A 1.6x headline at the top of its punch is 780px
	# wide, which does not fit beside this HUD in a 960px window: the number steps aside for its
	# settled size and the punch overhangs the card for the fifth of a second it lasts.
	await get_tree().create_timer(FXLayer.PUNCH_TIME + 0.05).timeout

	var checked := 0
	var clear := true
	for child in fx.get_children():
		var label := child as Label
		if label == null or not label.visible:
			continue
		checked += 1
		# The rect as drawn. `Rect2(position, size * scale)` is the box a top-left pivot would
		# give; the numbers pivot on their centre, so that rect is off by a fifth of the width.
		if keep.intersects(_drawn_rect(label)):
			clear = false
	_check("a number aimed at the HUD is drawn somewhere else", checked > 0 and clear,
		"%d number(s) placed, keep-out %s" % [checked, keep])

	Settings.focus_intensity = saved

## Two floating texts are never drawn over each other (fx_layer.gd, "keeping the numbers apart").
##
## `ui_shots` 16-juice printed "BASEBALE BATNRANK 43": two rank-ups on one frame at one point,
## one printed behind the other. In the same shot a streak tag sat on its own payout number, and
## twelve hits in a frame piled twelve numbers on one pixel. Asserted the way it failed —
## everything at once, at one point, on one frame — and then again later in their lives,
## because they rise on an ease-out and a young number catches an old one up.
func _the_numbers_keep_apart() -> void:
	_suite("numbers keep apart")
	var fx := _find(_main, "FXLayer")
	if fx == null:
		_check("the FX layer is present to test", false)
		return
	var saved := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL
	await _quiet_numbers(fx)

	var buddy := get_tree().get_first_node_in_group(&"buddy") as Node2D
	var spot := (buddy.global_position if buddy else Vector2(VIEW_SIZE) * 0.5) + Vector2(0, -78)
	# The capture's frame, and then some: two different toys ranking at once, and a big and a
	# small payout aimed at the very spot the rank lines print.
	EventBus.mastery_rank_up.emit(&"mace", 4)
	EventBus.mastery_rank_up.emit(&"baseball_bat", 43)
	EventBus.payout.emit(Economy.BONES, 4800.0, spot, &"baseball_bat")
	EventBus.payout.emit(Economy.BONES, 4.0, spot, &"baseball_bat")
	await get_tree().process_frame
	_check("two rank-ups on one frame both print",
		_visible_tag(fx, "MACE  RANK 4") and _visible_tag(fx, "BASEBALL BAT  RANK 43"))
	_check("and a big and a small payout at the same spot both print",
		_visible_tag(fx, "+%s" % fx.call("_format", 4800.0))
		and _visible_tag(fx, "+%s" % fx.call("_format", 4.0)))
	await _apart_for_life(fx, "rank lines and payouts at one point")

	# The burst: twelve hits in one frame, exactly as `ui_shots` stages it.
	await _quiet_numbers(fx)
	Economy._streak_deadline_msec = 0
	var hit := Vector2(VIEW_SIZE) * 0.5 + Vector2(60, 40)
	for i in 12:
		EventBus.damage_dealt.emit(HitInfo.new(30.0, &"baseball_bat", hit, 1000.0))
	await get_tree().process_frame
	var payouts := 0
	var tags := 0
	for child in fx.get_children():
		var label := child as Label
		if label and label.visible:
			if label.text.begins_with("+"):
				payouts += 1
			elif label.text.begins_with("x"):
				tags += 1
	_check("a burst of twelve still reads as a burst (%d numbers drawn)" % payouts, payouts >= 5)
	_check("with one streak tag, not one per hit (%d)" % tags, tags == 1)
	await _apart_for_life(fx, "a burst of twelve hits")

	# An ability's words (D77): its name, then its landing replacing it (keyed), a big one and the
	# payout of the very hit it names, all at one point. Found by group, as the abilities find it.
	await _quiet_numbers(fx)
	_check("the FX layer is found by group, as an ability finds it", FXLayer.of(self) == fx, "")
	var word_at := spot + Vector2(0, 30)
	fx.call("callout", "IAIDO", word_at, Color("6fa8ff"), 1.0, &"ability:iaido")
	fx.call("callout", "SLASH!", word_at, Color("6fa8ff"), 1.0, &"ability:iaido")
	EventBus.payout.emit(Economy.BONES, 480.0, word_at, &"katana")
	await get_tree().process_frame
	_check("an ability's landing word replaces its name rather than stacking on it",
		_visible_tag(fx, "SLASH!") and not _visible_tag(fx, "IAIDO"), "")
	_check("and the payout it names still prints beside it",
		_visible_tag(fx, "+%s" % fx.call("_format", 480.0)), "")
	var word := _visible_label(fx, "SLASH!")
	_check("in the display face", word != null and word.get_theme_font("font") != null
		and word.get_theme_font("font").resource_path == UIStyle.FONT_DISPLAY, "")
	await _apart_for_life(fx, "an ability's word and its payout")

	# The knockout: a record round's banner over the headline, and a fountain of coins that is a
	# spray by design and so passes *behind* the words rather than through them.
	await _quiet_numbers(fx)
	var had_round := Economy.last_round
	Economy.last_round = {"record": true, "number": 3}
	fx.call("_on_knockout_payout", 12345.0)
	fx.call("_on_buddy_state_changed", &"pile")
	Economy.last_round = had_round
	await get_tree().process_frame
	var headline := _visible_label(fx, "KNOCKOUT")
	var banner := _visible_label(fx, "NEW BEST ROUND")
	_check("a record knockout prints its banner over the headline", headline != null
		and banner != null and _drawn_rect(banner).end.y <= _drawn_rect(headline).position.y + 0.5)
	var coins_behind := true
	for child in fx.get_children():
		var coin := child as Sprite2D
		if coin and coin.visible and headline and coin.z_index >= headline.z_index:
			coins_behind = false
	_check("and the fountain's coins draw behind the lines", coins_behind)
	await _apart_for_life(fx, "the knockout's lines")

	Settings.focus_intensity = saved
	await _quiet_numbers(fx)

## Nothing an ability says is printed over the badge on him or across his face (D77 amended).
##
## The first capture pass of D77, frame by frame: "KATANA RANK 1" straight through the slash badge
## (every first use is also the first rank-up), the towel's trickles risen onto the Swaddle badge
## where D75 sends them, an ability's name across his eyes with the weapon at him, and the rank-up
## putting away the very word it was ranking for. FXLayer placed lines apart from lines and knew
## nothing of the badges; now a badge is something a line steps around, a badge put up under a line
## waits for it, a word steps around his face, and a headline steps around a word.
##
## Asserted as each failed, on the real layer and the real badge, at five points through the rise:
## nothing drawn from a line ever meets anything drawn by a badge or his face. He is held still for
## it, so the checks are about the placement and not about him walking into a word.
func _abilities_read_clear_of_him() -> void:
	_suite("ability words and badges")
	var fx := _find(_main, "FXLayer") as FXLayer
	var buddy := get_tree().get_first_node_in_group(&"buddy") as Buddy
	var afx := AbilityFX.of(buddy) if buddy else null
	if fx == null or buddy == null or afx == null:
		_check("the FX layer, him and the ability effects are present to test", false)
		return
	var saved := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL
	var was_frozen := buddy.freeze
	buddy.freeze = true
	await _quiet_numbers(fx)
	var slash := {"icon": &"slash", "colour": Color("6fa8ff"), "seconds": 3.0}

	# The katana's frame: the badge is up when its first use ranks the katana up.
	var badge := AbilityFX.state(buddy, &"ui_sliced", slash, self, afx)
	await get_tree().process_frame
	EventBus.mastery_rank_up.emit(&"katana", 1)
	await get_tree().process_frame
	_check("with a badge up, the rank-up still prints", _visible_label(fx, "KATANA") != null, "")
	await _clear_of(fx, [badge], false, "a rank-up and the badge up before it")
	AbilityFX.clear_states(buddy, self)
	await _quiet_numbers(fx)

	# The other order, on one frame: the rank-up first, then the state it ranked for.
	EventBus.mastery_rank_up.emit(&"katana", 2)
	badge = AbilityFX.state(buddy, &"ui_sliced", slash, self, afx)
	# Two frames: `process_frame` resumes this before the badge's own `_process` has run.
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a badge put up under a rising line waits for it", badge.waiting,
		"badge %s, line %s" % [badge.drawn_rect(), _drawn_rect(_visible_label(fx, "KATANA"))
			if _visible_label(fx, "KATANA") else Rect2()])
	await _clear_of(fx, [badge], false, "a rank-up and the badge put up after it")
	var shown := false
	for i in 90:
		await get_tree().process_frame
		if not badge.waiting and badge.drawn_rect().has_area():
			shown = true
			break
	_check("and is drawn once the line has passed", shown, "")
	await _quiet_numbers(fx)

	# The towel's frame: a trickle risen over his head, where the badge is (D75).
	Economy.paying_kind_act = false
	var centre := buddy.get_interaction_rect().get_center()
	for i in 3:
		EventBus.payout.emit(Economy.HEARTS, 2.0 + float(i) * 0.1, centre, &"warm_towel")
		await get_tree().process_frame
	var trickles := 0
	for child in fx.get_children():
		if child is Label and (child as Label).visible and (child as Label).text.begins_with("+2"):
			trickles += 1
	_check("trickles over his head still print beside a badge (%d of 3)" % trickles, trickles >= 2, "")
	await _clear_of(fx, [badge], false, "trickles risen over his head and the badge there")
	AbilityFX.clear_states(buddy, self)
	await _quiet_numbers(fx)

	# A word called out with the weapon at him: aimed at his face, drawn clear of it.
	var face := fx.face_rect()
	_check("his face is found to keep words off it", face.has_area(), str(face))
	fx.callout("BRUSH CLEAR", face.get_center(), Color("e0c060"), 1.0, &"ability:ui_brush")
	await get_tree().process_frame
	_check("a word aimed at his face is still drawn", _visible_label(fx, "BRUSH CLEAR") != null, "")
	await _clear_of(fx, [], true, "a word aimed at his face")
	await _quiet_numbers(fx)

	# An act with the hand at his face (D75 amended): the feather duster's "+1.0" and the towel's wrap
	# printed on white bone across his eyes. Beside his face, on the side the hand was, at the hand's
	# height — not over his head, where it would read as a trickle and not as the hand's.
	for side in [1.0, -1.0]:
		face = fx.face_rect()
		var hand := face.get_center() + Vector2(float(side) * face.size.x * 0.2, 0.0)
		Economy.paying_kind_act = true
		EventBus.payout.emit(Economy.HEARTS, 1.0, hand, &"feather_duster")
		Economy.paying_kind_act = false
		await get_tree().process_frame
		var act := _visible_label(fx, "+1.0")
		var ink := _drawn_rect(act) if act else Rect2()
		var beside := ink.position.x >= face.end.x - 0.5 if side > 0.0 else ink.end.x <= face.position.x + 0.5
		_check("an act at his face is drawn beside it, on the hand's side (%s)" % ("right" if side > 0.0
			else "left"), act != null and beside, "number %s, face %s" % [ink, face])
		_check("at the hand's height, not over his head", act != null
			and absf(ink.get_center().y - (hand.y + 14.0)) <= 8.0, "number %s, hand %s" % [ink, hand])
		await _clear_of(fx, [], true, "an act aimed at his face")
		await _quiet_numbers(fx)

	# The chainsaw's frame (D77 amended): its badge went up over its own grind's numbers, already rising
	# where the badge goes, and waited up to a line's life for them. A badge is what is happening to him
	# now; a payout under it gives way.
	var head_rect := buddy.get_interaction_rect()
	var over := Vector2(head_rect.get_center().x, head_rect.position.y)
	for i in 3:
		EventBus.payout.emit(Economy.BONES, 20.0 + float(i), over + Vector2(0.0, 10.0 + 14.0 * float(i)),
			&"chainsaw")
	await get_tree().process_frame
	var saw := AbilityFX.state(buddy, &"ui_revving", slash, self, afx)
	var under := fx.crosses(saw.fx_keep_out())
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a badge put up over rising payouts is drawn at once", under and not saw.waiting
		and saw.drawn_rect().has_area(), "numbers under it %s, waiting %s" % [under, saw.waiting])
	await _clear_of(fx, [saw], false, "payouts and a badge put up over them")
	AbilityFX.clear_states(buddy, self)
	await _quiet_numbers(fx)

	# The word for the moment and the rank-up it earned, on one frame: both print.
	var head := buddy.get_interaction_rect()
	fx.callout("SLASH!", Vector2(head.get_center().x, head.position.y - 58.0), Color("6fa8ff"), 1.0,
		&"ability:ui_iaido")
	EventBus.mastery_rank_up.emit(&"katana", 3)
	await get_tree().process_frame
	_check("a rank-up does not put away the ability's word it lands beside",
		_visible_label(fx, "SLASH!") != null and _visible_label(fx, "KATANA") != null, "")
	await _apart_for_life(fx, "an ability's word and its rank-up")

	buddy.freeze = was_frozen
	Settings.focus_intensity = saved
	await _quiet_numbers(fx)

## Samples five points through the lines' rise: no visible line's ink meets a badge's drawn ink,
## nor, with `face`, his face.
func _clear_of(fx: FXLayer, badges: Array, face: bool, what: String) -> void:
	var clashes: Array[String] = []
	var elapsed := 0.0
	for at in [0.0, 0.12, 0.3, 0.55, 0.8]:
		if at > elapsed:
			await get_tree().create_timer(at - elapsed).timeout
			elapsed = at
		var keep: Array[Rect2] = []
		for badge in badges:
			if is_instance_valid(badge):
				keep.append((badge as AbilityFX.StateMark).drawn_rect())
		if face:
			keep.append(fx.face_rect())
		for child in fx.get_children():
			var label := child as Label
			if label == null or not label.visible or label.z_index == FXLayer.Z_COIN:
				continue
			var ink := _drawn_rect(label)
			for rect in keep:
				if rect.has_area() and ink.intersects(rect):
					clashes.append("t+%.2f: \"%s\" %s over %s" % [at, label.text, ink, rect])
	_check("%s never meet, at any point in the rise" % what, clashes.is_empty(), "; ".join(clashes))

## Nothing on the FX layer is ever drawn part-transparent (D68). A number used to fade out over
## the second half of its life, and over a flat backdrop — the chroma green a streamer keys out —
## a half-transparent number is a grey ghost of itself, on every hit. Numbers now leave by
## drawing in to their centre, and the fountain is coins that do the same. Watched frame by frame
## through a payout's whole life and then a whole fountain.
func _numbers_leave_without_a_ghost() -> void:
	_suite("no ghosts")
	var fx := _find(_main, "FXLayer")
	if fx == null:
		_check("the FX layer is present to test", false)
		return
	var saved := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL
	await _quiet_numbers(fx)
	Economy._streak_deadline_msec = 0

	EventBus.payout.emit(Economy.BONES, 4800.0, Vector2(VIEW_SIZE) * 0.5, &"baseball_bat")
	var payout := await _watch_leaving(fx, FXLayer.LIFETIME + 0.15)
	_check("a payout number is drawn at full strength for its whole life (faintest %.2f)"
		% payout["faintest"], payout["seen"] >= 1 and payout["faintest"] >= 0.999,
		"%d watched" % payout["seen"])
	_check("and leaves by drawing in, not by vanishing", payout["popped"].is_empty(),
		", ".join(payout["popped"]))

	await _quiet_numbers(fx)
	fx.call("_on_knockout_payout", 12345.0)
	fx.call("_on_buddy_state_changed", &"pile")
	var fountain := await _watch_leaving(fx, FXLayer.ARC_LIFETIME + FXLayer.ARC_STAGGER * 16.0 + 0.15)
	_check("the knockout's fountain is coins, not ten copies of one number (%d coins)"
		% fountain["coins"], fountain["coins"] >= 5)
	_check("and the headline and every coin are drawn at full strength (faintest %.2f)"
		% fountain["faintest"], fountain["faintest"] >= 0.999)
	_check("and each of them leaves by drawing in", fountain["popped"].is_empty(),
		", ".join(fountain["popped"]))
	Settings.focus_intensity = saved
	await _quiet_numbers(fx)

## Samples every frame for `seconds`: the faintest alpha any visible number or coin was drawn at,
## and which of them were still more than a third of their size on their last visible frame.
## Watched at quarter speed: a frame is sampled on the wall clock, and on a machine busy with
## other suites one 60 ms stall carried a coin from half size to gone between two samples, which
## reads exactly like a coin that vanished.
func _watch_leaving(fx: Node, seconds: float) -> Dictionary:
	const SLOW := 0.25
	var saved_scale := Engine.time_scale
	Engine.time_scale = SLOW
	var faintest := 1.0
	var last_scale := {}
	var peak_scale := {}
	var coins := {}
	var until := Time.get_ticks_msec() + int(seconds / SLOW * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		for child in fx.get_children():
			if not (child is Label or child is Sprite2D) or not (child as CanvasItem).visible:
				continue
			faintest = minf(faintest, _drawn_alpha(child as CanvasItem))
			var s: float = (child as Control).scale.x if child is Control else (child as Node2D).scale.x
			last_scale[child] = s
			peak_scale[child] = maxf(float(peak_scale.get(child, 0.0)), s)
			if child is Sprite2D:
				coins[child] = true
	Engine.time_scale = saved_scale
	var popped: Array[String] = []
	for item in last_scale:
		if (item as CanvasItem).visible:
			continue
		if float(last_scale[item]) > float(peak_scale[item]) / 3.0:
			popped.append("%s at %.2f of %.2f" % [item.name, last_scale[item], peak_scale[item]])
	return {"faintest": faintest, "seen": last_scale.size(), "coins": coins.size(),
		"popped": popped}

func _visible_label(fx: Node, prefix: String) -> Label:
	for child in fx.get_children():
		var label := child as Label
		if label and label.visible and label.text.begins_with(prefix):
			return label
	return null

## Asserts no two visible floating labels overlap, now and at four points later in their lives.
func _apart_for_life(fx: Node, what: String) -> void:
	var clashes: Array[String] = []
	var elapsed := 0.0
	for at in [0.0, 0.12, 0.3, 0.55, 0.8]:
		if at > elapsed:
			await get_tree().create_timer(at - elapsed).timeout
			elapsed = at
		var clash := _overlapping_labels(fx)
		if clash != "":
			clashes.append("t+%.2f: %s" % [at, clash])
	_check("%s never overlap, at any point in their rise" % what, clashes.is_empty(),
		"; ".join(clashes))

## The first pair of visible rising labels whose drawn ink overlaps, or "". The fountain's
## coins are left out: they are thrown from one point on purpose.
func _overlapping_labels(fx: Node) -> String:
	var labels: Array[Label] = []
	for child in fx.get_children():
		var label := child as Label
		if label and label.visible and label.z_index != FXLayer.Z_COIN:
			labels.append(label)
	for i in labels.size():
		for j in range(i + 1, labels.size()):
			if _drawn_rect(labels[i]).intersects(_drawn_rect(labels[j])):
				return "\"%s\" over \"%s\"" % [labels[i].text, labels[j].text]
	return ""

## Where a floating label's ink actually is: scaled about its pivot, with the outline that is
## drawn outside the glyphs.
func _drawn_rect(label: Label) -> Rect2:
	var top_left := label.position + label.pivot_offset * (Vector2.ONE - label.scale)
	var ink := float(label.get_theme_constant("outline_size")) * 0.5 * label.scale.x
	return Rect2(top_left, label.size * label.scale).grow_individual(ink, 0.0, ink, 0.0)

## Lets every number on screen finish, so a check starts on an empty desk.
func _quiet_numbers(fx: Node) -> void:
	await get_tree().create_timer(FXLayer.LIFETIME + 0.15).timeout
	await _settle()
	for child in fx.get_children():
		if child is Label:
			(child as Label).visible = false

## The status corner has to read over whatever is behind the window: the dark desk the owner
## captured, a chroma key, a photograph. Three failures, one suite.
##
## **The toast faded in.** `show_toast` called `UIMotion.rise`, which is for rows *on* a card and
## takes them from alpha 0 — so the card itself, straight on a transparent window, spent its first
## 0.18 s as smoked glass, and every toast in a burst restarted it. 16-juice caught "Wider Desk ·
## $400" as dark ink on a dark strip. Headless has no motion, which is exactly why no suite saw
## it: this one turns motion on for the length of the entrance and reads every frame.
##
## **The streak figure heated past legibility**, to an orange 2.25:1 on the card.
##
## **The pin stayed where the card's edge used to be.** The HUD card widens when its footer
## appears, nothing woke the drawer, and the pin ended up inside the card beside the Bones figure.
func _the_hud_reads_on_any_desk() -> void:
	_suite("hud over the desk")
	var hud := _find(_main, "HUD")
	var toast := _find(hud, "Toast") as Control if hud else null
	var words := hud.get("_toast_label") as Label if hud else null
	if toast == null or words == null:
		_check("the HUD's toast is present to test", false)
		return
	var saved := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL
	UIMotion.run_in_headless = true
	# The burst the capture caught, through the game's own wiring: a rank-up (a celebrated toast,
	# which throws chips) and then the milestone it tipped over.
	EventBus.mastery_rank_up.emit(&"mace", 5)
	Milestones.milestone_claimed.emit(&"ladder_items", 1, 400)
	var faintest := 1.0
	for i in 24:
		await get_tree().process_frame
		if toast.visible:
			faintest = minf(faintest, minf(_drawn_alpha(toast), _drawn_alpha(words)))
	UIMotion.run_in_headless = false
	_check("the toast is drawn at full strength through its whole entrance",
		faintest >= 0.999, "faintest frame at alpha %.2f" % faintest)
	_check("and it is the milestone that is showing", toast.visible
		and words.text.begins_with("Wider Desk"), words.text)
	var ratio := UIStyle.contrast(words.get_theme_color("font_color"), _surface_behind(words))
	_check("its words are legible on its own card (%.2f:1)" % ratio, ratio >= 4.5)
	var stale := 0
	for child in toast.get_children():
		if child is GPUParticles2D and not child.is_queued_for_deletion():
			stale += 1
	_check("with no chips left raining from the message before it", stale == 0,
		"%d emitter(s)" % stale)

	# The streak figure, at the heat it reaches on a real run.
	var row := _find(hud, "StreakRow")
	Economy._streak_deadline_msec = 0
	for i in int(HUD.STREAK_HOT_AT) + 2:
		EventBus.damage_dealt.emit(HitInfo.new(20.0, &"baseball_bat", Vector2(VIEW_SIZE) * 0.5, 1000.0))
	await _settle()
	var figure := _label_containing("x%d" % (int(HUD.STREAK_HOT_AT) + 2), row) if row else null
	_check("a hot streak is on the card", figure != null)
	if figure:
		var hot := UIStyle.contrast(figure.get_theme_color("font_color"), _surface_behind(figure))
		_check("and its figure is still legible at full heat (%.2f:1)" % hot, hot >= 4.5)
		# The hottest punch (1.4x about its centre) must land in room the row reserved for it:
		# unreserved, "x37" drew over its STREAK label and past the card's edge at 1.25x.
		var slot := figure.get_parent() as MarginContainer
		var needed := figure.size.x * 0.4 * 0.5
		var room := float(slot.get_theme_constant("margin_right")) if slot else 0.0
		_check("and its hottest punch has room beside it (%.1f of %.1f px)" % [room, needed],
			slot != null and room >= needed and float(slot.get_theme_constant("margin_left")) >= needed)
	Economy._streak_deadline_msec = 0

	# The pin follows the card when the card grows on its own.
	var box := hud.get("_box") as Control
	var mark := _find(hud, "DrawerMark") as Control
	if box and mark:
		var was := box.custom_minimum_size
		box.custom_minimum_size = Vector2(was.x + 64.0, was.y)
		await _settle()
		var card := UIScale.screen_rect(box)
		var pin := UIScale.screen_rect(mark)
		_check("the pin stays beside the status card when the card widens",
			not card.intersects(pin) and pin.position.x >= card.end.x,
			"pin %s, card %s" % [pin, card])
		box.custom_minimum_size = was
		await _settle()
		card = UIScale.screen_rect(box)
		pin = UIScale.screen_rect(mark)
		_check("and comes back in with it", pin.position.x - card.end.x < 8.0
			and not card.intersects(pin), "pin %s, card %s" % [pin, card])

	Settings.focus_intensity = saved
	await get_tree().create_timer(FXLayer.LIFETIME).timeout

## The alpha an item is actually drawn at: its own, times everything above it on its layer.
func _drawn_alpha(item: CanvasItem) -> float:
	var alpha := item.self_modulate.a
	var walk: Node = item
	while walk is CanvasItem:
		alpha *= (walk as CanvasItem).modulate.a
		walk = walk.get_parent()
	return alpha

## Being armed no longer takes your hands away, and putting the power down is one click (D47).
##
## Three separate complaints, one suite: nothing on screen said you were holding a power,
## unequipping meant a trip back into the panel, and while armed you could not pick anything
## up — so a pistol and a teddy bear could not be used in the same minute. Taught with the
## missile strike since D71 made the pistol a gun you hold.
func _the_power_leaves_your_hands_free() -> void:
	_suite("cursor powers")
	var spawner := get_tree().get_first_node_in_group(&"item_spawner")
	var hud := get_tree().get_first_node_in_group(HUD.GROUP_HUD)
	if spawner == null or hud == null:
		_check("the spawner and the HUD are present to test", false)
		return

	var chip := _find(hud, "ArmedChip") as Button
	_check("the HUD has a chip for what you are holding", chip != null)
	if chip == null:
		return
	_check("and it is hidden while your hands are empty", not chip.visible)

	# Cleared so the first-equip tip is genuinely first. Safe to stomp: `_restore` holds a
	# duplicate of the whole hint list and puts it back before the suite quits.
	Settings.hints_seen.erase(String(HUD.HINT_CURSOR_POWER))
	var toast := _find(hud, "Toast") as CanvasItem
	_check("the HUD's toast is named, so it can be found", toast != null)

	# Paid for, whatever the suites before this one left in the purse.
	Economy.grant(Economy.BONES, float(ItemDB.get_item(&"missile").cost))
	Progression.purchase_item(&"missile")
	EventBus.spawn_requested.emit(&"missile", Vector2.ZERO)
	await _settle()
	_check("equipping a power arms the spawner",
		StringName(spawner.call("active_power")) == &"missile")
	_check("and the chip says so", chip.visible and chip.text.contains("Missile"))
	# The rules are good and invisible, so the one that cannot be guessed gets taught once.
	_check("and the way out is written on the chip, not hidden in a tooltip",
		chip.text.contains("Esc"))
	_check("the first power equipped teaches the gestures",
		Settings.hint_seen(HUD.HINT_CURSOR_POWER))
	if toast:
		_check("and the tip is on screen", toast.visible)

	# The rule that gives the hands back: a click over something the player put on the desk
	# is a grab, not a shot. Asked of the power itself, because a synthetic click cannot move
	# the OS cursor and the hover flags are what the real gesture reads.
	var power := spawner.call("get_power", &"missile") as CursorPowerBase
	_check("the power instance exists once equipped", power != null)
	if power:
		_check("with nothing under the cursor, the power takes the click",
			not bool(power.call("_pointing_at_a_toy")))
		EventBus.spawn_requested.emit(&"baseball_bat", Vector2(VIEW_SIZE) * 0.5)
		await _settle()
		var toy: Node = null
		for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
			toy = node
			break
		_check("a toy is on the desk to test against", toy != null)
		if toy and toy.get("drag_area"):
			var area = toy.get("drag_area")
			area.is_hovered = true
			_check("but over one of your toys it declines, so you can pick it up",
				bool(power.call("_pointing_at_a_toy")))
			area.is_hovered = false

	# The chip carries an icon, a name and a key in a 268px column. "Magnifying Glass" is a
	# lot longer than "Missile Strike", and a Button grows to fit rather than clipping — so the
	# longest name in the roster would silently widen the whole HUD if this went unchecked.
	var widest := ""
	var widest_px := 0.0
	for candidate in ItemDB.all_items():
		if not candidate.is_cursor_power():
			continue
		EventBus.cursor_power_changed.emit(candidate.id)
		await _settle()
		var need := chip.get_combined_minimum_size().x
		if need > widest_px:
			widest_px = need
			widest = candidate.display_name
	_check("the armed chip fits the HUD column for every power (%s, %.0fpx)"
		% [widest, widest_px], widest_px <= HUD.WIDTH,
		"%.0f > %.0f" % [widest_px, HUD.WIDTH])
	EventBus.cursor_power_changed.emit(&"missile")
	await _settle()

	# One click on the chip puts it away — the whole point of the chip existing.
	chip.pressed.emit()
	await _settle()
	_check("the chip holsters it in one click",
		StringName(spawner.call("active_power")) == &"")
	_check("and takes itself off screen", not chip.visible)
	_check("holstering an empty hand reports nothing to do",
		not bool(spawner.call("holster_power")))

## There is exactly one place the window can be picked up, and it is not the background (D52).
##
## D49 armed the move from `OverlayManager._unhandled_input` — any press nothing else claimed.
## On an overlay that is nearly the whole window, and the owner reported it immediately: they
## went to click something in the play area, missed, and moved the window. This asserts the
## replacement exists, is reachable, and that the old gesture is gone.
func _the_window_has_one_grab_point() -> void:
	_suite("window grip")
	var grip := _find(_main, "WindowGripHandle") as Control
	_check("the window has a grip", grip != null)
	if grip == null:
		return
	_check("it is visible", grip.visible)
	_check("and it takes clicks itself rather than letting them fall through",
		grip.mouse_filter == Control.MOUSE_FILTER_STOP,
		"filter %d" % grip.mouse_filter)

	# Top centre: the one edge of the shell nothing else occupies. The HUD column is
	# top-left and the tab strip top-right, so either corner would have meant reserving a
	# strip in both and re-homing two auto-hide drawers.
	var root := grip.get_parent() as Control
	_check("it sits at the top of the window", grip.position.y < 8.0,
		"y %.0f" % grip.position.y)
	_check("and centred, clear of the HUD and the tabs",
		absf((grip.position.x + grip.size.x * 0.5) - root.size.x * 0.5) <= 1.0,
		"grip centre %.0f of %.0f" % [grip.position.x + grip.size.x * 0.5, root.size.x])

	# The gesture, driven through the grip's own handler — which is where it has to live,
	# because a STOP Control consumes the press at the GUI stage and `_unhandled_input` is
	# guaranteed never to see it.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	grip.gui_input.emit(press)
	_check("pressing it arms a window drag", OverlayManager.window_drag_armed())
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	grip.gui_input.emit(release)
	_check("and releasing disarms it", not OverlayManager.window_drag_armed())

	# The old gesture must be gone, not merely supplemented. A grip that works while the
	# background still drags is the original complaint plus one more mark on the desktop.
	_check("the background no longer moves the window",
		not OverlayManager.has_method("_unhandled_input"))

## The suite must not be able to reconfigure the game it is testing (D51).
##
## This asserts the redirect on the first line of `_ready()` is still there. It looks
## circular and is not: the failure it catches is somebody deleting that line, or moving it
## below the first thing that writes, and the cost of missing it is measured in someone
## relaunching the game to find their Focus Mode off and the payout numbers apparently gone.
## Cheap insurance against a bug that presents as a different bug entirely.
func _the_suite_writes_nowhere_real() -> void:
	_suite("isolation")
	_check("the suite writes preferences to its own file, not the player's",
		Settings.config_path != Settings.CONFIG_PATH, Settings.config_path)
	_check("and its own save slot", SaveManager.slot_name == TEST_SLOT)

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
	await _keys_hold_their_size(panels)

## A key of every variation, pressed, hovered while pressed and disabled on a bench in the real
## shell, and measured each time (D68). A Button sizes itself from the state it is in, so a
## state with more margin than the key at rest grows the key — and its row, and the card under
## it. The arcade's deck grew 2px every time a hand was dealt and its keys went dead.
##
## A toggle does not re-measure the key on its own; the next thing that does (a caption change,
## a theme change) picks up the pressed size. So the bench asks, the way that next thing would.
func _keys_hold_their_size(panels: Node) -> void:
	var root := panels.get("_root") as Control
	var theme := UITheme.get_theme()
	var types: Array[String] = ["Button"]
	types.append_array(theme.get_type_variation_list("Button"))
	var bench := VBoxContainer.new()
	bench.name = "KeyBench"
	bench.position = Vector2(40, 40)
	root.add_child(bench)
	var keys: Array[Button] = []
	for type_name in types:
		var row := HBoxContainer.new()
		bench.add_child(row)
		var key := Button.new()
		key.name = "Bench%s" % type_name
		key.text = "Deal"
		UIStyle.set_icon(key, UIStyle.glyph(&"star"))
		key.toggle_mode = true
		key.focus_mode = Control.FOCUS_NONE
		key.theme_type_variation = type_name
		row.add_child(key)
		keys.append(key)
	await _settle()
	var grew: Array[String] = []
	for key in keys:
		var rest := key.get_rect()
		var states: Array[String] = []
		key.button_pressed = true
		key.update_minimum_size()
		await _settle()
		states.append("pressed %s" % key.size)
		var pressed_ok := key.get_rect().is_equal_approx(rest)
		_hovered_at(_centre_of(key))
		key.update_minimum_size()
		await _settle()
		states.append("hovered %s" % key.size)
		var hovered_ok := key.get_rect().is_equal_approx(rest)
		_hovered_at(Vector2(VIEW_SIZE) * 0.5)
		key.button_pressed = false
		key.disabled = true
		await _settle()
		states.append("disabled %s" % key.size)
		var disabled_ok := key.get_rect().is_equal_approx(rest)
		if not (pressed_ok and hovered_ok and disabled_ok):
			grew.append("%s: at rest %s, %s" % [key.theme_type_variation, rest.size,
				", ".join(states)])
	_check("a key of every variation (%d) keeps its rect pressed, hovered and disabled"
		% keys.size(), grew.is_empty(), "; ".join(grew))
	bench.queue_free()
	await _settle()

## The shell at the sizes it is actually used at (D68). Every other suite runs at 1x in a
## 960x640 window; the owner plays at Menu size 1.25x on a 1440x960 play area, 2x is one step
## away in Settings, 1180x760 is the play area a new player starts in, and 480x360 is the
## smallest the window goes. Four things were wrong at those sizes and right at 1x:
##
## - **rules landed uneven.** A 3px rule at 1.25x is 3.75 screen pixels and draws as 3 or 4 by
##   position, so a box was heavier on top than underneath. Rules are 4 at a fractional factor.
## - **captions were clipped** — "Upgrad", "The Whee" — because a tab's width is the card's
##   shared out and the card is narrower at 2x while the words are not.
## - **pages were wider than the card**: seven backdrop keys in one row put Chroma past the
##   card's right edge at 2x, and every Arcade room was wider than the 480x360 card.
## - **the shop scrolled the whole card** at 2x, and took its buy key below the fold.
const MENU_SIZES := [
	[Vector2i(960, 640), 1.0],
	[Vector2i(1440, 960), 1.25],
	[Vector2i(1440, 960), 2.0],
	[Vector2i(1180, 760), 2.0],
	[Vector2i(960, 640), 1.75],
	[Vector2i(480, 360), 1.0],
]

func _the_shell_at_every_menu_size() -> void:
	_suite("menu sizes")
	var panels := _find(_main, "PanelLayer")
	var arcade := _find(_main, "ArcadePanel")
	if panels == null or arcade == null:
		_check("the panels are present to test", false)
		return
	var host := panels.get("_host") as ScrollContainer
	var rebuilds_before := UITheme.rebuilds
	for entry in MENU_SIZES:
		var view_size: Vector2i = entry[0]
		var asked: float = entry[1]
		_view.size = view_size
		Settings.set_ui_scale(asked)
		await _settle()
		await _settle()
		var factor := UIScale.factor_for(Vector2(view_size))
		var at := "%dx%d at %sx" % [view_size.x, view_size.y, ("%.2f" % factor).rstrip("0").rstrip(".")]
		_check("%s: the shell is drawn at the size asked for" % at,
			is_equal_approx(factor, asked) and is_equal_approx((panels as CanvasLayer).scale.x, asked))
		_rules_land_whole(factor, at)
		var widths: Array[String] = []
		var clipped: Array[String] = []
		var shop_scrolls := ""
		for page_id in [&"shop", &"tree", &"contracts", &"deeds", &"arcade", &"settings"]:
			panels.call("show_panel", page_id)
			await _settle()
			var page := _pages_page(panels, page_id)
			if page == null:
				continue
			var room := host.size.x
			if host.get_v_scroll_bar().visible:
				room -= host.get_v_scroll_bar().size.x
			var wide := page.get_combined_minimum_size().x
			if wide > room + 0.5:
				widths.append("%s %.0f in %.0f" % [page_id, wide, room])
			if page_id == &"shop" and page.get_combined_minimum_size().y > host.size.y + 0.5:
				shop_scrolls = "%.0f of page in %.0f of card" % [page.get_combined_minimum_size().y,
					host.size.y]
			if page_id == &"arcade":
				for id in arcade.call("room_ids"):
					arcade.call("show_room", id)
					await _settle()
					var room_wide: float = (arcade as Control).get_combined_minimum_size().x
					if room_wide > room + 0.5:
						widths.append("arcade/%s %.0f in %.0f" % [id, room_wide, room])
					var key := (arcade.get("_rooms") as Dictionary)[id]["tab"] as Button
					var fits := _caption_fits(key)
					if fits != "":
						clipped.append(fits)
		for tab in (panels.get("_buttons") as Dictionary).values():
			var fits := _caption_fits(tab as Button)
			if fits != "":
				clipped.append(fits)
		_check("%s: no page is wider than the card" % at, widths.is_empty(), ", ".join(widths))
		_check("%s: every tab's caption fits its tab, page and room" % at, clipped.is_empty(),
			", ".join(clipped))
		_check("%s: the shop fits the card rather than scrolling it" % at, shop_scrolls == "",
			shop_scrolls)
		panels.call("close")
		await _settle()
		# The tabs are right-aligned and as wide as the card, so on a narrow window they reached
		# across into the status card's corner and the first tab sat on the purse.
		var hud := get_tree().get_first_node_in_group(HUD.GROUP_HUD)
		var tabs: Rect2 = panels.call("shell_rect")
		var status: Rect2 = hud.call("shell_rect") if hud else Rect2()
		# Only where the card fits under the strip. A tall card at a large Menu size does not —
		# 736px under a 92px strip in 760 at 2x — and stepping it all the way down put its foot
		# off the window, which window_check forbids at every size. There it stays inside the
		# window and overlaps the strip's edge, the lesser of the two faults.
		var slack := 24.0
		var fits_below := status.size.y <= float(_view.size.y) - tabs.end.y - slack
		_check("%s: the page tabs never sit on the status card when it fits below them" % at,
			status.size.x > 0.0 and (not fits_below or not tabs.intersects(status)),
			"tabs %s, status %s, fits below %s" % [tabs, status, fits_below])
		var taller_than_window := status.size.y > float(_view.size.y) - slack
		_check("%s: and it never steps down off the bottom of the window" % at,
			taller_than_window or status.end.y <= float(_view.size.y) + 0.5,
			"status %s in %s" % [status, _view.size])
		# The feedback card (the playtest kit) is a modal of its own, sized to the window it is in.
		var fits: String = await _feedback_card_fits()
		_check("%s: the feedback card fits the window, its boxes and its Save key on it" % at,
			fits == "", fits)

	# Rebuilding the theme is paid when the rule width changes and at no other time: the steps
	# above crossed between whole and fractional factors, and a resize at the same factor
	# changes nothing.
	var crossed := UITheme.rebuilds - rebuilds_before
	_check("the theme was rebuilt once per change of rule width (%d)" % crossed, crossed >= 2)
	_view.size = Vector2i(1440, 960)
	Settings.set_ui_scale(1.25)
	await _settle()
	var settled := UITheme.rebuilds
	_view.size = Vector2i(1400, 940)
	await _settle()
	_view.size = Vector2i(1440, 960)
	await _settle()
	_check("and resizing the window at the same factor rebuilds nothing",
		UITheme.rebuilds == settled, "%d rebuild(s)" % (UITheme.rebuilds - settled))

	_view.size = VIEW_SIZE
	Settings.set_ui_scale(1.0)
	await _settle()
	await _settle()
	_check("and back at 1x the rules are the base width again",
		UIStyle.rule_width() == UIStyle.BORDER_WIDTH)

## Every rule the theme draws is a whole number of screen pixels at `factor`, and the shell is
## actually drawing with that theme: the card's own rule, every `UIStyle.rule()`, every lamp.
func _rules_land_whole(factor: float, at: String) -> void:
	var theme := UITheme.get_theme()
	var uneven: Array[String] = []
	var checked := 0
	for type_name in theme.get_stylebox_type_list():
		# Drawn in the world, which the Menu size never scales.
		if type_name == "Bubble":
			continue
		for box_name in theme.get_stylebox_list(type_name):
			var flat := theme.get_stylebox(box_name, type_name) as StyleBoxFlat
			if flat == null:
				continue
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				var width := flat.get_border_width(side)
				# A hairline is one pixel on purpose and cannot be whole at a quarter step
				# without being four; D68 leaves them.
				if width <= 1:
					continue
				checked += 1
				var screen := float(width) * factor
				if absf(screen - roundf(screen)) > 0.001:
					uneven.append("%s/%s %dpx" % [type_name, box_name, width])
	_check("%s: every rule in the theme is whole screen pixels (%d)" % [at, checked],
		checked > 0 and uneven.is_empty(), ", ".join(uneven))
	var rule := UIStyle.rule_for(factor)
	var card := _find(_main, "Card") as Control
	var drawn := (card.get_theme_stylebox("panel") as StyleBoxFlat).border_width_top if card else -1
	var off: Array[String] = []
	var lines := 0
	for node in _all_nodes(_main):
		var panel := node as Panel
		if panel == null:
			continue
		if panel.theme_type_variation == &"Rule":
			lines += 1
			var thick := maxf(panel.custom_minimum_size.x, panel.custom_minimum_size.y)
			if absf(thick - float(rule)) > 0.01:
				off.append("rule %.0f" % thick)
		elif panel.name == "Lamp" and absf(panel.offset_top - float(rule)) > 0.01:
			off.append("lamp at %.0f" % panel.offset_top)
	_check("%s: the card, %d cell rules and every lamp are drawn at %dpx" % [at, lines, rule],
		drawn == rule and lines > 0 and off.is_empty(), "card %d, %s" % [drawn, ", ".join(off)])

## "" if a button's caption fits the width it was given, else what it needed. Measured on the
## realised button — its own face, its own box, its own icon — not on what `UIStyle` decided.
func _caption_fits(button: Button) -> String:
	if button == null or button.text == "":
		return ""
	var font := button.get_theme_font("font")
	var box := button.get_theme_stylebox("normal")
	var need := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		button.get_theme_font_size("font_size")).x + box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	if button.icon:
		need += float(button.icon.get_width() + button.get_theme_constant("h_separation"))
	if need > button.size.x + 0.5:
		return "\"%s\" needs %.0f of %.0f" % [button.text, need, button.size.x]
	return ""

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
	# The run is long enough by now for the idle brain to set off for a toy, which would take
	# his attention mid-suite. A disturbance stands him down and stamps the clock.
	var idle_brain := get_tree().get_first_node_in_group(&"idle_brain") as IdleBrain
	if idle_brain:
		idle_brain._disturb()
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

## The Arcade shows one room at a time behind its own strip: three machines, the wardrobe
## and the back room. Each tab is a real button at a real rect; every view but the chosen one
## is hidden, so a spin in a room the player left stays built and keeps paying, and nothing
## on the page is ever under a second thing.
func _the_arcade_is_one_room_at_a_time() -> void:
	_suite("rooms")
	var panels := _find(_main, "PanelLayer")
	var arcade := _find(_main, "ArcadePanel")
	if panels == null or arcade == null:
		_check("the arcade page exists", false)
		return
	panels.call("show_panel", &"arcade")
	await _settle()
	var ids: Array = arcade.call("room_ids")
	_check("the arcade has five rooms (%d)" % ids.size(), ids.size() == 5,
		", ".join(ids))
	var strip := _find(arcade, "Rooms")
	_check("with a tab strip", strip != null)
	if strip == null:
		return
	_check("one tab per room", strip.get_child_count() == ids.size())
	# A room stays chosen across visits — the wardrobe suite before this one left it there —
	# so what is asserted is that *some* room is open, never a fresh page with nothing showing.
	var first: StringName = arcade.call("current_room")
	_check("a room is open on arrival", ids.has(first), String(first))
	var rooms: Dictionary = arcade.get("_rooms")
	# Click into every other room through its tab, and prove the views swap.
	for id in ids:
		var tab := rooms[id]["tab"] as Button
		_click(UIScale.screen_centre(tab))
		await _settle()
		_check("clicking %s opens it" % id, arcade.call("current_room") == id)
		var shown := 0
		for other in ids:
			if (rooms[other]["view"] as Control).visible:
				shown += 1
		_check("%s: one view on screen (%d)" % [id, shown], shown == 1)
		_check("%s: its tab reads pressed" % id, tab.button_pressed)
		var view := rooms[id]["view"] as Control
		_check("%s: the view has a size" % id, view.size.x > 100.0 and view.size.y > 60.0,
			str(view.size))
	# Every room is a cabinet (D58): marquee, stage, paytable, deck, in that order, and every
	# room's stage is the same height — so the deck, and the key on it, never moves between
	# rooms. This was "every machine's well"; the wardrobe and the back room are held to it
	# now too.
	var stages: Array[float] = []
	var decks: Array[float] = []
	var host := panels.get("_host") as ScrollContainer
	for id in ids:
		var view := rooms[id]["view"] as Control
		arcade.call("show_room", id)
		# The back room scrolls to reach its second cabinet, and the card keeps whatever a
		# suite above left it scrolled to — so every room is measured from the top.
		if host:
			host.scroll_vertical = 0
		await _settle()
		var cabinet := (view if view is Cabinet else _first_cabinet(view)) as Cabinet
		_check("%s is a cabinet" % id, cabinet != null)
		if cabinet == null:
			continue
		var order: Array[String] = []
		for section in cabinet.sections.get_children():
			order.append(String(section.name))
		_check("%s: marquee, stage, paytable, deck" % id,
			order == ["Marquee", "Stage", "OddsStrip", "Deck"], ", ".join(order))
		_check("%s: the marquee is lit in its own colour" % id,
			cabinet.marquee.theme_type_variation == UIStyle.marquee_variation(cabinet.accent))
		_check("%s: and its key on the strip matches" % id,
			(rooms[id]["tab"] as Button).theme_type_variation
				== UIStyle.room_tab_variation(cabinet.accent))
		stages.append(cabinet.stage.size.y)
		decks.append(UIScale.screen_rect(cabinet.deck).position.y)
		# The page-wide readable sweep only ever sees whichever room is open, so each room is
		# graded here, where it is on screen — the marquees above all, whose ink sits on a
		# colour nothing else in the shell is printed on.
		var unreadable: Array[String] = []
		for node in _all_nodes(view):
			var label := node as Label
			if label == null or not label.is_visible_in_tree() or label.text.strip_edges() == "":
				continue
			var ratio := UIStyle.contrast(label.get_theme_color("font_color"), _surface_behind(label))
			if ratio < 4.5:
				unreadable.append("%s \"%s\" %.2f:1" % [label.name, label.text.substr(0, 18), ratio])
		_check("%s: every word is legible where it sits" % id, unreadable.is_empty(),
			", ".join(unreadable))
	_check("five cabinets (%d)" % stages.size(), stages.size() == 5)
	if stages.size() == 5:
		var level := true
		for i in stages.size():
			level = level and absf(stages[i] - stages[0]) < 1.0 and absf(decks[i] - decks[0]) < 1.0
		_check("every stage is one height and every deck on one line", level,
			"stages %s, decks %s" % [str(stages), str(decks)])
		_check("and tall enough to be a stage (%.0f)" % stages[0], stages[0] >= float(Cabinet.STAGE))
	# The rebirth page's own flag follows the room, not just the card (D28).
	var prestige := _find(_main, "PrestigePanel") as Control
	arcade.call("show_room", &"rebirth")
	await _settle()
	_check("rebirth room: the prestige page is visible", prestige != null and prestige.is_visible_in_tree())
	arcade.call("show_room", ids[0])
	await _settle()
	_check("machine room: the prestige page is not", prestige != null and not prestige.visible)
	panels.call("close")
	await _settle()

func _first_cabinet(root: Node) -> Cabinet:
	for node in _all_nodes(root):
		if node is Cabinet:
			return node
	return null

## The stake is a stepper on the deck (D58). What it may change is decided: every Dollars
## prize scales with it, a garnish and a boost do not (D32 caps both by acts and minutes, not
## by the bet), the page charges exactly the stake, and it cannot move while a play is running
## — the stake a hand was dealt at is the stake it is paid at.
func _the_stake_is_a_stepper() -> void:
	_suite("stake")
	var panels := _find(_main, "PanelLayer")
	var arcade := _find(_main, "ArcadePanel")
	if panels == null or arcade == null:
		_check("the arcade page exists", false)
		return
	panels.call("show_panel", &"arcade")
	arcade.call("show_room", &"spin_wheel")
	await _settle()
	var machines: Array = arcade.get("_machines")
	var wheel_machine: Dictionary = machines[0]
	var wheel := wheel_machine["game"] as ArcadeGame
	var more := wheel_machine["more"] as Button
	var less := wheel_machine["less"] as Button
	var price := wheel_machine["price"] as Label
	_check("the wheel opens at its lowest stake", wheel.stake() == wheel.cost
		and price.text == UIStyle.format_amount(wheel.cost), price.text)
	_check("where only + is live", less.disabled and not more.disabled)
	await _click(_centre_of(more))
	await _settle()
	_check("clicking + doubles it", is_equal_approx(wheel.stake(), wheel.cost * 2.0)
		and price.text == UIStyle.format_amount(wheel.cost * 2.0), price.text)
	var cabinet := wheel_machine["cabinet"] as Cabinet
	_check("and the legend's Dollars follow it",
		_label_containing("%s / %s" % [UIStyle.format_amount(WheelGame.SMALL * 2.0),
			UIStyle.format_amount(WheelGame.BIG * 2.0)], cabinet) != null)
	var ring: Array = wheel.get("_wedges")
	for wedge in ring:
		var prize: ArcadeGame.Prize = wheel.call("_prize_for", wedge)
		match wedge.kind:
			WheelGame.KIND_DOLLARS:
				_check("a %s wedge pays twice its table at x2" % wedge.family,
					is_equal_approx(prize.amount, wedge.dollars * 2.0))
			WheelGame.KIND_BOOST:
				_check("the boost does not scale with the stake",
					is_equal_approx(prize.multiplier, WheelGame.BOOST_MULT)
						and is_equal_approx(prize.seconds, WheelGame.BOOST_SECONDS))
			WheelGame.KIND_GARNISH:
				_check("nor does the Bones garnish", is_equal_approx(prize.amount,
					ArcadeGame.garnish_cap(Economy.BONES) * WheelGame.GARNISH_SHARE))
	await _click(_centre_of(less))
	await _settle()
	_check("clicking - brings it back down", wheel.stake() == wheel.cost)

	# A hand in play freezes the stake, and the deal charges exactly what the deck said.
	arcade.call("show_room", &"blackjack")
	await _settle()
	var table_machine: Dictionary = machines[2]
	var table := table_machine["game"] as ArcadeGame
	await _click(_centre_of(table_machine["more"] as Button))
	await _settle()
	var stake := table.stake()
	Economy.grant(Economy.DOLLARS, stake * 3.0)
	await _settle()
	var before := Economy.balance_of(Economy.DOLLARS)
	await _click(_centre_of(table_machine["play"] as Button))
	await _settle()
	_check("dealing charges the stake (%s)" % UIStyle.format_amount(stake),
		is_equal_approx(before - Economy.balance_of(Economy.DOLLARS), stake))
	_check("and the stepper is dead for the hand", table.is_busy()
		and (table_machine["more"] as Button).disabled
		and (table_machine["less"] as Button).disabled)
	await _click(_centre_of(table_machine["less"] as Button))
	_check("a click on it changes nothing", is_equal_approx(table.stake(), stake))
	# Play the hand out: stand as soon as it is the player's turn, then wait for the money.
	# Waited on the clock, not on frames — the cards are dealt by tweens with real intervals,
	# and a headless frame is far shorter than a sixtieth of a second.
	var stand := _find(table_machine["cabinet"], "Stand") as Button
	for i in 80:
		if not table.is_busy():
			break
		if stand and not stand.disabled:
			await _click(_centre_of(stand))
		await get_tree().create_timer(0.1).timeout
	_check("the hand settles", not table.is_busy())
	await _settle()
	_check("and the stepper comes back", not (table_machine["less"] as Button).disabled)
	await _click(_centre_of(table_machine["less"] as Button))
	await _settle()
	panels.call("close")
	await _settle()

## What is behind him is a choice (D38): every entry in `Backdrop.CHOICES` is a real button on
## the settings page, choosing one paints the whole window with it and hides the layer for the
## desktop, the canvas never takes a click, and the choice survives a save and load.
func _the_backdrop_is_a_choice() -> void:
	_suite("backdrop")
	var panels := _find(_main, "PanelLayer")
	var backdrop := _find(_main, "Backdrop") as CanvasLayer
	_check("the game has a backdrop layer", backdrop != null)
	if panels == null or backdrop == null:
		return
	_check("under the world", backdrop.layer < 0)
	var canvas := _find(backdrop, "Canvas") as Control
	_check("with a canvas that ignores the mouse",
		canvas != null and canvas.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	panels.call("show_panel", &"settings")
	await _settle()
	var page := _find(_main, "SettingsPanel")
	var rows: Dictionary = page.get("_rows")
	var ids: Array = Backdrop.ids()
	_check("twelve choices (%d)" % ids.size(), ids.size() == 12)
	for id in ids:
		var button := rows.get(StringName("backdrop_%s" % id)) as Button
		_check("%s: has a button" % id, button != null)
		if button == null:
			continue
		# The backdrop section is below the fold of the card: scroll it into view the way the
		# card itself does, then click at the rect it lands at.
		(panels.get("_host") as ScrollContainer).ensure_control_visible(button)
		await _settle()
		_click(UIScale.screen_centre(button))
		await _settle()
		_check("%s: chosen" % id, Settings.backdrop == id, String(Settings.backdrop))
		_check("%s: its button reads pressed" % id, button.button_pressed)
		var kind: StringName = Backdrop.choice(id)["kind"]
		_check("%s: the layer is %s" % [id, "hidden" if kind == &"none" else "showing"],
			backdrop.visible == (kind != &"none"))
		if canvas:
			_check("%s: the canvas is the window" % id,
				canvas.size.is_equal_approx(canvas.get_viewport().get_visible_rect().size), str(canvas.size))
	# Round trip: what was saved is what loads.
	OverlayManager.set_backdrop(&"hills")
	var before := Settings.backdrop
	Settings.backdrop = &"transparent"
	Settings.load_settings()
	_check("the choice survives a save and load", Settings.backdrop == before, String(Settings.backdrop))
	_check("an unknown id falls back to the desktop", Backdrop.choice(&"nope")["id"] == &"transparent")
	OverlayManager.set_backdrop(_restore["backdrop"])
	panels.call("close")
	await _settle()

# --- the world's effects ------------------------------------------------------

## The world has physical effects (D39): dust where he lands, a ring where something went
## off, a tracer where a turret fired, a bolt where the lightning went, and the picture
## jolting on a real hit. All pooled and named, all silent at Focus Off, and every one of
## them puts itself away when it is spent — a ring that stayed visible would be a ring drawn
## for eight hours.
func _the_world_has_juice() -> void:
	_suite("juice")
	var fx := _find(_main, "WorldFX") as Node2D
	var numbers := _find(_main, "FXLayer")
	var hud := _find(_main, "HUD")
	_check("the world has an effects node", fx != null)
	if fx == null or numbers == null or hud == null:
		return
	for slot in ["Burst0", "Burst9", "Ring0", "Ring3", "Line0", "Line3"]:
		_check("the %s pool slot is named" % slot, fx.has_node(slot))
	for signal_name in ["buddy_landed", "item_spawned", "item_despawned", "mood_changed",
			"grime_changed", "mastery_rank_up", "prestige_performed", "kindness_sustained"]:
		_check("the world listens to %s" % signal_name, _wired(signal_name, fx))
	for signal_name in ["mastery_rank_up", "prestige_performed", "grime_changed"]:
		_check("the numbers listen to %s" % signal_name, _wired(signal_name, numbers))

	var view := fx.get_viewport()
	var centre := Vector2(VIEW_SIZE) * 0.5
	var across := PackedVector2Array([centre, centre + Vector2(120, 0)])
	# Focus Off is the suite's resting state: nothing may draw.
	Settings.focus_intensity = Settings.Intensity.OFF
	fx.call("ring", centre, 80.0, Color.WHITE)
	fx.call("bolt", across)
	fx.call("shake", 8.0)
	# A point of its own: the payouts suite has just thrown chips at the centre, and a one-shot
	# emitter reads as emitting until its last chip has died.
	var spot := centre + Vector2(33.0, 77.0)
	fx.call("puff", spot, 6, Color.WHITE)
	await _settle()
	_check("at Focus Off a ring draws nothing", not _any_visible(fx, "Ring"))
	_check("a bolt draws nothing", not _any_visible(fx, "Line"))
	_check("a puff throws nothing", _emitter_at(fx, spot) == null)
	_check("and a shake moves nothing",
		not bool(fx.call("is_shaking")) and view.canvas_transform == Transform2D.IDENTITY)

	Settings.focus_intensity = Settings.Intensity.NORMAL
	fx.call("ring", centre, 80.0, Color.WHITE)
	fx.call("bolt", across)
	fx.call("tracer", centre, centre + Vector2(0, 100))
	fx.call("shake", 8.0)
	await get_tree().process_frame
	_check("with it on, a ring is drawn", _any_visible(fx, "Ring"))
	_check("a bolt and a tracer are drawn", _any_visible(fx, "Line"))
	_check("and the picture is jolting", bool(fx.call("is_shaking")))
	await get_tree().create_timer(0.8).timeout
	await _settle()
	_check("the ring is put away when spent", not _any_visible(fx, "Ring"))
	_check("the lines too", not _any_visible(fx, "Line"))
	_check("and the jolt stops with the picture back where it was",
		not bool(fx.call("is_shaking")) and view.canvas_transform == Transform2D.IDENTITY,
		str(view.canvas_transform))

	# Through the bus, the way the game does it.
	EventBus.buddy_landed.emit(centre, 900.0)
	await get_tree().process_frame
	_check("a landing throws dust at his feet", _emitter_at(fx, centre) != null)
	var star := UIStyle.glyph(&"star")
	EventBus.mastery_rank_up.emit(&"baseball_bat", 3)
	await _settle()
	_check("a rank up prints over him", _visible_tag(numbers, "BASEBALL BAT  RANK 3"))
	_check("and throws stars", _emitter_with(fx, star) != null)
	EventBus.grime_changed.emit(0.6)
	EventBus.grime_changed.emit(0.0)
	await _settle()
	_check("a full clean says so", _visible_tag(numbers, "SQUEAKY CLEAN"))
	# Reincarnation rebuilds half the shell, so the two listeners are called rather than the
	# bus being fired.
	numbers.call("_on_prestige_performed", 2.5)
	fx.call("_on_prestige_performed", 2.5)
	await get_tree().process_frame
	_check("a rebirth is the headline", _visible_tag(numbers, "REINCARNATED"))
	_check("and says what it paid", _visible_tag(numbers, "+2.50 MARROW"))
	_check("and jolts the desk", bool(fx.call("is_shaking")))
	await get_tree().create_timer(0.9).timeout

	# The knockout meter glows when it is nearly full, and stops when it is not.
	var meter := hud.get("_meter") as Control
	hud.call("_set_meter_hot", true)
	await get_tree().process_frame
	# Headless has no menu motion (UIMotion is off), so the lit state is the flag and a bar
	# left at plain white rather than a running tween.
	_check("a nearly-full meter is lit", bool(hud.get("_meter_hot")) and meter != null
		and meter.modulate == Color.WHITE)
	hud.call("_set_meter_hot", false)
	await get_tree().process_frame
	_check("and goes out when it is not", not bool(hud.get("_meter_hot"))
		and meter != null and meter.modulate == Color.WHITE)
	await _the_desk_has_a_rhythm(fx, hud)
	Settings.focus_intensity = Settings.Intensity.OFF
	await get_tree().create_timer(0.3).timeout
	await _settle()

func _wired(signal_name: String, target: Object) -> bool:
	for connection in EventBus.get_signal_connection_list(signal_name):
		if connection["callable"].get_object() == target:
			return true
	return false

func _any_visible(root: Node, prefix: String) -> bool:
	for child in root.get_children():
		var item := child as CanvasItem
		if item and String(item.name).begins_with(prefix) and item.visible:
			return true
	return false

func _emitter_at(root: Node, at: Vector2) -> GPUParticles2D:
	for child in root.get_children():
		var emitter := child as GPUParticles2D
		if emitter and emitter.emitting and emitter.global_position.is_equal_approx(at):
			return emitter
	return null

func _emitter_with(root: Node, texture: Texture2D) -> GPUParticles2D:
	for child in root.get_children():
		var emitter := child as GPUParticles2D
		if emitter and emitter.emitting and emitter.texture == texture:
			return emitter
	return null

## The second juice pass: the streak and combo row on the card with its draining bar, embers
## on him at a long streak, a trail behind anything fast, and ambient life on the kind items.
## Runs inside the juice suite with Focus Mode still on.
func _the_desk_has_a_rhythm(fx: Node2D, hud: Node) -> void:
	var row := _find(hud, "StreakRow") as Control
	_check("the HUD has a streak row", row != null)
	if row == null:
		return
	Economy._streak_deadline_msec = 0
	await get_tree().create_timer(0.2).timeout
	await _settle()
	_check("it is hidden with no streak", not row.visible)
	var centre := Vector2(VIEW_SIZE) * 0.5
	for i in 3:
		EventBus.damage_dealt.emit(HitInfo.new(20.0, &"baseball_bat", centre, 1000.0))
	await _settle()
	_check("three hits in a row put it on the card", row.visible)
	var value := _label_containing("x3", row)
	_check("reading x3", value != null)
	var bar := _find(row, "ProgressBar") as ProgressBar
	_check("with a bar draining toward the lapse", bar != null and bar.value > 0.5 and bar.value <= 1.0,
		str(bar.value) if bar else "no bar")
	await get_tree().create_timer(Economy.STREAK_WINDOW + 0.3).timeout
	await _settle()
	_check("and it goes away when the streak lapses", not row.visible)

	# Embers and bliss ride on him; both are children of his body and both obey Focus Mode.
	var buddy := _find(_main, "Buddy") as Node2D
	fx.call("_set_ambient", &"embers", true)
	_check("a long streak sets him on fire", bool(fx.call("is_ambient_on", &"embers"))
		and buddy != null and buddy.has_node("Embers"))
	fx.call("_set_ambient", &"bliss", true)
	_check("bliss puts a sparkle on him", bool(fx.call("is_ambient_on", &"bliss")))
	Settings.focus_intensity = Settings.Intensity.OFF
	fx.call("_gate_ambient")
	_check("Focus Off puts both out", not bool(fx.call("is_ambient_on", &"embers"))
		and not bool(fx.call("is_ambient_on", &"bliss")))
	Settings.focus_intensity = Settings.Intensity.NORMAL
	fx.call("_set_ambient", &"embers", false)
	fx.call("_set_ambient", &"bliss", false)

	# The trail: built on first use, in world space, hidden until he moves fast.
	if buddy:
		buddy.call("_build_trail")
		var trail := buddy.get_node_or_null("Trail") as Line2D
		_check("he can leave a trail", trail != null and trail.top_level and not trail.visible)
		_check("in bone white", trail != null and trail.default_color == Color.WHITE)

	# Ambient life: a hot tub steams, and stops steaming at Focus Off.
	var spawner := _find(_main, "ItemSpawner")
	var world := spawner.get("world") as Node2D if spawner else null
	var scene := load("res://Scenes/Friendly/hot_tub.tscn") as PackedScene
	if world and scene:
		var tub := scene.instantiate() as Node2D
		tub.set("item_id", &"hot_tub")
		world.add_child(tub)
		tub.global_position = centre + Vector2(200, 0)
		await _settle()
		var steam := tub.get_node_or_null("Ambient") as GPUParticles2D
		_check("a hot tub steams", steam != null and steam.emitting)
		Settings.focus_intensity = Settings.Intensity.OFF
		tub.call("_gate_ambient")
		_check("and stops at Focus Off", steam != null and not steam.emitting)
		Settings.focus_intensity = Settings.Intensity.NORMAL
		tub.queue_free()
		await _settle()
	await _the_upgrades_are_worn(centre)

## An upgraded item looks upgraded (D41): the tier is read from rank and augments, and a
## spawned body wears it as a glow, a wider trail and an aura that Focus Off stills.
func _the_upgrades_are_worn(centre: Vector2) -> void:
	# Both ramps are indexed by tier. They are read through a clamp, but they must still be
	# long enough or the top tiers all look the same — and this is the assertion that catches
	# a rung added without scrolling down to the arrays. Here rather than in `run_tests`
	# because `BaseDraggable` references `EventBus`, which does not exist under `-s`.
	_check("the glow ramp covers every juice tier",
		BaseDraggable.GLOW_STRENGTH.size() >= MasteryMath.JUICE_TIERS + 1,
		"%d entries" % BaseDraggable.GLOW_STRENGTH.size())
	_check("and so does the aura ramp",
		BaseDraggable.AURA_AMOUNT.size() >= MasteryMath.JUICE_TIERS + 1,
		"%d entries" % BaseDraggable.AURA_AMOUNT.size())
	_check("an untouched item is tier 0", Progression.juice_tier(&"scythe") == 0)
	Progression.add_mastery_xp(&"baseball_bat", 1.0e9)
	await _settle()
	_check("a rank-capped bat is the top tier",
		Progression.juice_tier(&"baseball_bat") == MasteryMath.JUICE_TIERS,
		str(Progression.juice_tier(&"baseball_bat")))
	var spawner := _find(_main, "ItemSpawner")
	EventBus.spawn_requested.emit(&"baseball_bat", centre + Vector2(-200, -60))
	await _settle()
	var bat: Node2D
	for node in get_tree().get_nodes_in_group(&"spawned_item"):
		if node.get("item_id") == &"baseball_bat":
			bat = node
	_check("the bat spawns", bat != null)
	if bat == null:
		return
	_check("and wears its tier", int(bat.get("juice_tier")) == MasteryMath.JUICE_TIERS,
		str(bat.get("juice_tier")))
	_check("as a glow on its sprite", ItemGlow.strength_of(bat.get("sprite")) > 0.9)
	var aura := bat.get_node_or_null("Aura") as GPUParticles2D
	_check("and an aura of chips", aura != null and aura.emitting)
	Settings.focus_intensity = Settings.Intensity.OFF
	spawner.call("refresh_augments")
	_check("Focus Off stills the aura", aura != null and not aura.emitting)
	Settings.focus_intensity = Settings.Intensity.NORMAL
	spawner.call("refresh_augments")
	_check("and Focus back on wakes it", aura != null and aura.emitting)
	bat.call("bin_myself")
	await _settle()
	await _the_turret_faces_him(centre)

## The recorded voices (D42) resolve through the import remap, and every id that has no
## recording still has its synthesised voice — a missing import must never silence anything.
func _the_sounds_are_recorded() -> void:
	_suite("audio")
	for id in [&"impact", &"impact_metal", &"explode_small", &"purchase", &"ui_click", &"card_deal", &"land"]:
		_check("%s plays a recording" % id, AudioManager.is_recorded(id))
	for id in [&"rank_up", &"prestige", &"oof", &"knockout", &"npc_roar", &"wheel_tick"]:
		_check("%s keeps its synthesised voice" % id,
			not AudioManager.is_recorded(id) and AudioManager.get("_streams").has(id))
	_check("a recorded id still has its synthesised fallback", AudioManager.get("_streams").has(&"impact"))
	var recorded: Dictionary = AudioManager.ASSETS
	for id in recorded:
		_check("%s: every listed file imported (%d)" % [id, int(recorded[id])],
			AudioManager.is_recorded(id) and (AudioManager.get("_variants")[id] as Array).size() == int(recorded[id]))

## A turret looks at him (D43): the sprite mirrors when he is on the side the art does not
## face, the barrel turns toward him within its cap, and the shot leaves from the nozzle.
func _the_turret_faces_him(centre: Vector2) -> void:
	var buddy := _find(_main, "Buddy") as RigidBody2D
	var spawner := _find(_main, "ItemSpawner")
	var world := spawner.get("world") as Node2D if spawner else null
	var scene := load("res://Scenes/Turrets/pellet_turret.tscn") as PackedScene
	if buddy == null or world == null or scene == null:
		_check("a turret can be staged", false)
		return
	buddy.freeze = true
	buddy.global_position = centre
	var turret := scene.instantiate() as Node2D
	turret.set("item_id", &"pellet_turret")
	world.add_child(turret)
	turret.freeze = true
	# On his right, so a right-facing gun has to mirror to look at him.
	turret.global_position = centre + Vector2(220, 0)
	await _settle()
	await _settle()
	# The gun is the Barrel sprite when the art has been split (D44), the whole sprite when not.
	var sprite := (turret.get("barrel") if turret.get("barrel") else turret.get("sprite")) as Sprite2D
	_check("the pellet turret has a muzzle", turret.get("muzzle") != Vector2.ZERO)
	_check("and a barrel of its own that turns on the mount", turret.get("barrel") != null)
	_check("standing on his right, it mirrors to face him", sprite != null and sprite.flip_h)
	var muzzle: Vector2 = turret.call("muzzle_position")
	_check("and its nozzle is on his side of it", muzzle.x < turret.global_position.x - 20.0,
		"muzzle %s body %s" % [muzzle, turret.global_position])
	# Then on his left: back the way the art faces, nozzle to the right.
	turret.global_position = centre + Vector2(-220, 0)
	await _settle()
	await _settle()
	_check("standing on his left, it faces the way it was drawn", sprite != null and not sprite.flip_h)
	muzzle = turret.call("muzzle_position")
	_check("and the nozzle swings to his side", muzzle.x > turret.global_position.x + 20.0)
	# Overhead: the barrel turns up toward him, but no further than its cap.
	turret.global_position = centre + Vector2(-80, 200)
	await _settle()
	await _settle()
	await _settle()
	var cap: float = deg_to_rad(float(turret.get("aim_lean_degrees")))
	_check("with him above, the barrel turns up", sprite != null and sprite.rotation < -0.05, str(sprite.rotation))
	_check("but no further than its cap", sprite != null and absf(sprite.rotation) <= cap + 0.01)
	turret.queue_free()
	buddy.freeze = false
	await _settle()
