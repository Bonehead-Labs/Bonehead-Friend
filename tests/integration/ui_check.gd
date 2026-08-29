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

func _ready() -> void:
	Settings.focus_intensity = Settings.Intensity.OFF
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

	_nothing_blocks_the_window()
	await _dock_opens_the_panels()
	await _shop_tiles_are_clickable()
	await _every_visible_button_is_reachable()
	await _the_buddy_still_takes_clicks()
	await _escape_menu_opens_and_closes()

	print("")
	print("==========================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

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

func _dock_opens_the_panels() -> void:
	_suite("dock")
	var hud := _find(_main, "HUD")
	var panels := _find(_main, "PanelLayer")
	_check("HUD exists", hud != null)
	_check("panel layer exists", panels != null)
	if hud == null or panels == null:
		return
	for entry in [["Toys", &"shop"], ["Upgrades", &"tree"]]:
		var button := _button_labelled(entry[0], hud)
		_check("dock button '%s' exists" % entry[0], button != null)
		if button == null:
			continue
		var target := _centre_of(button)
		_check("'%s' is the top control at %s (got %s)"
			% [entry[0], target, _describe(_hovered_at(target))], _hovered_at(target) == button)
		await _click(target)
		_check("clicking '%s' opens its panel" % entry[0], panels.call("is_open"))
		_check("'%s' shows the right page" % entry[0], panels.get("_current") == entry[1])
	# The panel's own tabs, which live on a different layer to the dock.
	var tab := _button_labelled("Toys", panels)
	_check("the panel has its own tabs", tab != null)
	if tab:
		await _click(_centre_of(tab))
		_check("a tab switches page", panels.get("_current") == &"shop")
	var close_button := _button_labelled("\u2715", panels)
	_check("the panel has a close button", close_button != null)
	if close_button:
		await _click(_centre_of(close_button))
		_check("the close button closes the panel", not panels.call("is_open"))
	# Pressing the dock button for the panel already showing closes it too.
	var dock_toys := _button_labelled("Toys", hud)
	if dock_toys:
		await _click(_centre_of(dock_toys))
		_check("the dock reopens it", panels.call("is_open"))
		await _click(_centre_of(dock_toys))
		_check("the dock button toggles the panel shut", not panels.call("is_open"))

func _shop_tiles_are_clickable() -> void:
	_suite("shop")
	var toys := _button_labelled("Toys", _find(_main, "HUD"))
	if toys == null:
		return
	await _click(_centre_of(toys))
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
	for page in [&"shop", &"tree"]:
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
					first = "'%s' is under %s" % [button.text,
						_describe(_hovered_at(_centre_of(button)))]
		_check("%s page: all %d visible buttons take the cursor" % [page, tested],
			blocked == 0 and tested > 0, first)
	panels.call("close")
	await _settle()

## Off-screen and scrolled-out-of-view buttons are clipped, so a hit test on them proves
## nothing. Only judge what the player can actually see.
func _is_on_screen(control: Control) -> bool:
	var centre := _centre_of(control)
	if not Rect2(Vector2.ZERO, Vector2(VIEW_SIZE)).has_point(centre):
		return false
	var walk := control.get_parent()
	while walk is Control:
		if walk is ScrollContainer and not (walk as Control).get_global_rect().has_point(centre):
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

func _centre_of(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

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
	var area := control.get_global_rect().size
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
