extends CaptureWindow

## Does the window actually do what the settings page says it did?
##
##   Godot --path <project> res://tools/window_check.tscn      (NOT --headless)
##
## This exists because Overlay -> Play area silently stopped working: the setting changed,
## the page redrew, and the window stayed covering the screen — with no way out from inside
## the game. Nothing in the headless suites could have caught it, because a headless run has
## no window and `apply_window_configuration` returns immediately.
##
## Everything here talks to the real DisplayServer, so it must run with a real window, and
## it restores the machine's own window settings before it exits.

const SETTLE := 12

var _passed := 0
var _failed := 0
var _restore := {}

func _ready() -> void:
	_use_capture_slot()
	_restore = {
		"mode": Settings.window_mode,
		"size": Settings.play_area_size,
		"corner": Settings.play_area_corner,
		"scale": Settings.ui_scale,
	}
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _idle(20)

	print("")
	print("Bonehead Friend — window check")
	print("==============================")

	await _the_two_modes_round_trip()
	await _the_corners_move_the_window()
	await _the_size_steps()
	await _the_shell_fits_the_window()

	print("")
	print("==============================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_restore_settings()
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

## The bug this file was written for. A borderless window sized to the whole usable rect is
## maximised as far as Windows is concerned, and a maximised window ignores being resized —
## so the trip out of overlay mode did nothing at all.
func _the_two_modes_round_trip() -> void:
	_suite("overlay <-> play area")
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())

	OverlayManager.set_window_mode(WindowLayout.Mode.PLAY_AREA)
	await _idle(SETTLE)
	var play := DisplayServer.window_get_size()
	_check("play area is not the whole screen (%s of %s)" % [play, usable.size],
		play.x < usable.size.x - 8 and play.y < usable.size.y - 8)

	OverlayManager.set_window_mode(WindowLayout.Mode.FULLSCREEN_OVERLAY)
	await _idle(SETTLE)
	var overlay := DisplayServer.window_get_size()
	_check("overlay covers the screen (%s of %s)" % [overlay, usable.size],
		overlay.x >= usable.size.x - 8 and overlay.y >= usable.size.y - 8)

	OverlayManager.set_window_mode(WindowLayout.Mode.PLAY_AREA)
	await _idle(SETTLE)
	var back := DisplayServer.window_get_size()
	_check("and it goes back (%s, was %s)" % [back, overlay],
		back.x < usable.size.x - 8 and back.y < usable.size.y - 8)
	_check("back to the size it left at (%s vs %s)" % [back, play],
		absi(back.x - play.x) <= 8 and absi(back.y - play.y) <= 8)

func _the_corners_move_the_window() -> void:
	_suite("corners")
	OverlayManager.set_window_mode(WindowLayout.Mode.PLAY_AREA)
	await _idle(SETTLE)
	var seen: Array[Vector2i] = []
	for corner in [WindowLayout.Corner.TOP_LEFT, WindowLayout.Corner.TOP_RIGHT,
			WindowLayout.Corner.BOTTOM_LEFT, WindowLayout.Corner.BOTTOM_RIGHT]:
		OverlayManager.snap_to_corner(corner)
		await _idle(SETTLE)
		seen.append(DisplayServer.window_get_position())
	var distinct := {}
	for position in seen:
		distinct[position] = true
	_check("all four corners are different places (%d of 4)" % distinct.size(),
		distinct.size() == 4)

func _the_size_steps() -> void:
	_suite("size")
	OverlayManager.snap_to_corner(WindowLayout.Corner.TOP_LEFT)
	# Started from a known rung, not from whatever is in the developer's settings.cfg. On a
	# machine left at the top of the ladder "stepping up resizes the window" is false and
	# the suite reports a bug that is really its own starting condition — the same class as
	# the ui_scale finding, one file over.
	Settings.play_area_size = WindowLayout.SIZE_LADDER[1]
	OverlayManager.apply_window_configuration()
	await _idle(SETTLE)
	var before := DisplayServer.window_get_size()
	OverlayManager.step_play_area_size(1)
	await _idle(SETTLE)
	var bigger := DisplayServer.window_get_size()
	_check("stepping up resizes the window (%s -> %s)" % [before, bigger], bigger != before)
	OverlayManager.step_play_area_size(-1)
	await _idle(SETTLE)
	_check("and stepping back down returns to it",
		DisplayServer.window_get_size() == before)

## Play area size and menu size are two settings the player can reach independently, and
## the small end of one with the large end of the other used to put the card off the screen
## — taking the tab strip that would have let you set it back with it. Nothing asserted the
## shell was inside the window, because nothing in the three suites read Control geometry
## at all. Six rungs times three scales, against a real DisplayServer.
func _the_shell_fits_the_window() -> void:
	_suite("the shell fits the window")
	OverlayManager.set_window_mode(WindowLayout.Mode.PLAY_AREA)
	await _idle(SETTLE)

	var panels := _find_node(get_tree().root, "PanelLayer")
	var hud := _find_node(get_tree().root, "Hud")
	if panels == null:
		_check("the panel layer exists", false)
		return

	var escapes: Array[String] = []
	for rung in WindowLayout.SIZE_LADDER:
		for pinned in [1, 2, 3]:
			Settings.play_area_size = rung
			Settings.ui_scale = pinned
			OverlayManager.apply_window_configuration()
			EventBus.ui_scale_changed.emit(UIScale.factor_for(Vector2(rung)))
			await _idle(SETTLE)
			var window := Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size()))
			# Grown by a pixel: a rect that ends exactly on the window edge is inside it,
			# and float error at 3x should not read as an escape.
			var bounds := window.grow(1.0)
			for part in [panels.call("shell_rect"), hud.call("shell_rect") if hud else Rect2()]:
				var rect := part as Rect2
				if rect.size == Vector2.ZERO:
					continue
				if not bounds.encloses(rect):
					escapes.append("%dx%d @%dx: %s outside %s (viewport %s, factor %d)"
						% [rung.x, rung.y, pinned, str(rect), str(window.size),
						str(get_viewport().get_visible_rect().size),
						UIScale.factor_for(get_viewport().get_visible_rect().size)])
	_check("no part of the shell leaves the window at any size or scale (%d escapes)"
		% escapes.size(), escapes.is_empty())
	for line in escapes.slice(0, 4):
		print("        %s" % line)

	# And the guarantee that makes that possible: a pinned scale the shell cannot fit into
	# is stepped down rather than honoured.
	Settings.ui_scale = 3
	_check("a 3x pin is refused on the smallest play area",
		UIScale.factor_for(Vector2(WindowLayout.SIZE_LADDER[0])) < 3)
	Settings.ui_scale = 0
	_check("and auto still reaches 2x on a 1440p overlay",
		UIScale.factor_for(Vector2(2560, 1440)) == 2)

func _find_node(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name or root.name == type_name \
			or (root.get_script() and root.get_script().get_global_name() == type_name):
		return root
	for child in root.get_children():
		var found := _find_node(child, type_name)
		if found:
			return found
	return null

func _restore_settings() -> void:
	Settings.play_area_size = _restore["size"]
	Settings.play_area_corner = _restore["corner"]
	Settings.ui_scale = _restore["scale"]
	Settings.window_mode = _restore["mode"]
	Settings.save_settings()

func _suite(title: String) -> void:
	print("")
	print("-- %s" % title)

func _check(what: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("   ok   %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)
