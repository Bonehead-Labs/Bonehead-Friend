extends CaptureWindow

## Records the shell's motion as frame sequences, so the animation can be reviewed instead
## of described.
##
##   Godot --fixed-fps 60 --path <project> res://tools/ui_motion_shots.tscn
##
## `--fixed-fps` is not optional. Without it every frame's delta is however long the
## previous PNG took to write, the tweens advance in huge irregular steps, and the capture
## is a recording of the disk rather than of the animation.
##
## Frames land in `user://ui_motion/<sequence>/NNN.png` and are assembled outside the
## engine. Nothing in the game depends on this.

const SIZE := Vector2i(1020, 720)
const OUT := "user://ui_motion"

var _main: Node
var _sequence := ""
var _frame := 0

func _ready() -> void:
	_use_capture_slot()
	Settings.focus_intensity = Settings.Intensity.NORMAL
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "motion capture")
	await _idle(20)
	_stage()
	await _idle(30)

	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")

	# --- the card unrolling from the strip ---
	panels.call("close")
	await _idle(20)
	_begin("open")
	await _record(4)
	await _click(_centre(_button("Toys", panels)))
	await _record(34)

	# --- switching page ---
	await _idle(20)
	_begin("tab")
	await _click(_centre(_button("Upgrades", panels)))
	await _record(34)

	# --- a key under the cursor, not pressed ---
	panels.call("show_panel", &"shop")
	# Every item this sequence clicks is opened in its own drawer first, read off its data: they
	# were all in Care when this was written, and M3.7-B spread them over Mood, Food and Play,
	# which left `_button()` finding nothing to click (see ui_shots, 03-toys-kind).
	_open_drawer(shop, &"boombox")
	shop.call("select", &"boombox")
	await _idle(30)
	var action := _find(shop, "_detail_action") as Button
	if action == null:
		action = _action_button(shop)
	_begin("hover")
	await _record(6)
	_move(_centre(action))
	await _record(20)
	_move(Vector2(120, 400))
	await _record(16)

	# --- picking something out of the list ---
	await _idle(20)
	_open_drawer(shop, &"pizza")
	await _idle(10)
	_begin("select")
	await _record(4)
	await _click(_centre(_button("Pizza", shop)))
	await _record(28)

	# --- paying for it ---
	await _idle(20)
	_open_drawer(shop, &"baseball")
	await _idle(10)
	await _click(_centre(_button("Baseball", shop)))
	await _idle(20)
	action = _action_button(shop)
	_move(_centre(action))
	await _idle(6)
	_begin("buy")
	_press(_centre(action), true)
	await _record(4)
	_press(_centre(action), false)
	await _record(52)

	# --- being refused ---
	await _idle(20)
	_open_drawer(shop, &"boombox")
	await _idle(10)
	await _click(_centre(_button("Boombox", shop)))
	await _idle(20)
	action = _action_button(shop)
	_move(_centre(action))
	await _idle(6)
	_begin("deny")
	_press(_centre(action), true)
	await _record(4)
	_press(_centre(action), false)
	await _record(34)

	# --- the auto-hide drawers, revealing and parking again ---
	panels.call("close")
	_move(Vector2(520, 400))
	await _idle(40)

	var hud := _find(_main, "HUD")
	var hud_arrow := _find(hud, "DrawerMark") as Control
	_begin("drawer-hud")
	await _record(6)
	if hud_arrow:
		_move(UIScale.screen_centre(hud_arrow))
	await _record(34)
	_move(Vector2(620, 500))
	await _record(34)

	var tabs_arrow := _find(panels, "DrawerMark") as Control
	_begin("drawer-tabs")
	await _record(6)
	if tabs_arrow:
		_move(UIScale.screen_centre(tabs_arrow))
	await _record(34)
	_move(Vector2(620, 500))
	await _record(34)

	print("ui_motion: wrote %s" % ProjectSettings.globalize_path(OUT))
	get_tree().quit()

## Enough money that some prices are in reach and some are not — a refusal cannot be
## recorded in a run where everything is affordable.
func _stage() -> void:
	Economy.grant(Economy.BONES, 1510.0)
	Economy.grant(Economy.HEARTS, 500.0)
	Progression.purchase_item(&"sponge")

# --- capture ---------------------------------------------------------------

func _begin(sequence: String) -> void:
	_sequence = sequence
	_frame = 0
	DirAccess.make_dir_recursive_absolute("%s/%s" % [OUT, sequence])

func _record(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_grab().save_png("%s/%s/%03d.png" % [OUT, _sequence, _frame])
		_frame += 1

# --- input -----------------------------------------------------------------

func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)

func _press(point: Vector2, down: bool) -> void:
	_move(point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	click.pressed = down
	click.position = point
	click.global_position = point
	get_viewport().push_input(click, true)

func _click(point: Vector2) -> void:
	_press(point, true)
	await _idle(2)
	_press(point, false)

## The drawer an item is filed in, opened the way the HUD's next-up row opens it.
func _open_drawer(shop: Node, item_id: StringName) -> void:
	var item := ItemDB.get_item(item_id)
	if item:
		shop.call("show_category", item.category)

## The shop's one action button — the big key at the bottom of the detail pane. It is
## whichever visible Button carries the item glyph and is not a list row or a tab, which is
## more fragile than naming it and much less fragile than walking the tree by index.
func _action_button(shop: Node) -> Button:
	var best: Button = null
	for node in _all(shop):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		if button.theme_type_variation == &"BuyButton":
			best = button
	if best == null:
		push_error("ui_motion: the shop has no action button")
	return best
