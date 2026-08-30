class_name CaptureWindow
extends Node

## Shared setup for the two capture tools: a window you can actually watch them work in.
##
## The game's own window is borderless, per-pixel transparent, always-on-top and parked in
## a corner by OverlayManager — which is right for an overlay and useless as a preview. A
## capture run is somebody watching, so it gets a title bar, a normal stacking order and
## the middle of the monitor.
##
## The scene is hosted in the **root** viewport rather than a SubViewport. A SubViewport
## needs a container above it before it will accept a mouse at all, and a
## SubViewportContainer then competes with the synthetic events these tools push; the root
## viewport takes them the same way the game does.

## A flat stand-in for the player's wallpaper. Card stock has to hold up against a real
## desktop, and both a black and a white backdrop flatter it in different, misleading ways.
const DESKTOP := Color("4a4a52")

var _backdrop: CanvasLayer

## Behind everything the game draws, in the same viewport, so a capture composites the way
## the player sees it.
func _install_backdrop() -> void:
	_backdrop = CanvasLayer.new()
	_backdrop.layer = -100
	add_child(_backdrop)
	var fill := ColorRect.new()
	fill.color = DESKTOP
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(fill)

## Called *after* the game has booted, because OverlayManager moves and resizes the window
## on ready and would otherwise undo all of this.
func _show_window(size: Vector2i, title: String) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
	DisplayServer.window_set_title("Bonehead Friend — %s" % title)

## One frame of the window, flattened onto the stand-in desktop so the PNG has no alpha.
func _grab() -> Image:
	var image := get_viewport().get_texture().get_image()
	var flat := Image.create(image.get_width(), image.get_height(), false, image.get_format())
	flat.fill(DESKTOP)
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	return flat

func _idle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

# --- finding things --------------------------------------------------------

func _centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func _find(root: Node, what: String) -> Node:
	for node in _all(root):
		if node.name == what or (node.get_script()
				and (node.get_script() as Script).get_global_name() == what):
			return node
	return null

func _button(text: String, root: Node) -> Button:
	for node in _all(root):
		if node is Button and (node as Button).text == text \
				and (node as Button).is_visible_in_tree():
			return node
	return null

func _tooltipped(text: String, root: Node) -> Button:
	for node in _all(root):
		if node is Button and (node as Button).tooltip_text == text \
				and (node as Button).is_visible_in_tree():
			return node
	return null

func _all(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		out.append_array(_all(child))
	return out

## Its own save slot, cleared before and after.
##
## Not optional and not a nicety: `main.tscn` loads whatever slot SaveManager is pointed at
## and the autosave timer writes back to it, so a capture run left the staged test state —
## a part-levelled tree, a bought mace, several thousand Bones — sitting in the player's
## real save. Both capture tools go through here now, exactly as `ui_check` does.
const CAPTURE_SLOT := "capture_slot"

func _use_capture_slot() -> void:
	SaveManager.slot_name = CAPTURE_SLOT
	_clear_slot()

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
