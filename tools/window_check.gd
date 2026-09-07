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
	# `_use_capture_slot()` also redirects `Settings.config_path` (D51), before this tool
	# rewrites window mode, play-area size, corner and UI scale. The restore at the end only
	# runs if the run reaches the end; the redirect is what makes a killed run harmless.
	_use_capture_slot()
	_restore = {
		"mode": Settings.window_mode,
		"size": Settings.play_area_size,
		"corner": Settings.play_area_corner,
		"scale": Settings.ui_scale,
		# D52 moves the window for real and D49 added a flag. State left in the singleton
		# mid-run is read by every suite after this one, and by the game on the next launch.
		"rect": Settings.play_area_rect,
		"monitor": Settings.monitor_id,
		"on_top": Settings.always_on_top,
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
	await _the_window_moves()

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
	var hud := _find_node(get_tree().root, "HUD")  # "Hud" never matched: the node is named "HUD" and _find_node is case-sensitive
	if panels == null:
		_check("the panel layer exists", false)
		return

	# Pinned open for the sweep. "Does the shell fit the window" is a question about the shell
	# while it is on screen; auto-hide (D29) parks the HUD column at x=-278 by design, and an
	# unpinned run reports eighteen escapes that are the feature working. This only started
	# mattering when the HUD lookup above was fixed — it had been silently null for the whole
	# life of this suite, so the HUD was never measured at all.
	for drawer_name in ["HudDrawer", "TabsDrawer"]:
		var drawer := _find_node(get_tree().root, drawer_name)
		if drawer:
			drawer.set("pinned", true)
	await _idle(SETTLE)

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
	# Quarter steps (D50). Two things to hold: a fractional pin is honoured on a window big
	# enough for it, and a fractional pin that does *not* fit gives up a quarter at a time
	# rather than falling all the way to the next whole number — which was the old behaviour
	# and would make the finer ladder pointless exactly where it is needed most.
	Settings.ui_scale = 1.75
	var pinned_fine := UIScale.factor_for(Vector2(2560, 1440))
	_check("a fractional pin is honoured when the shell fits (%.2fx)" % pinned_fine,
		is_equal_approx(pinned_fine, 1.75))
	Settings.ui_scale = 3.0
	var stepped := UIScale.factor_for(Vector2(WindowLayout.SIZE_LADDER[0]))
	_check("and one that does not fit gives up quarters, not whole numbers (%.2fx)" % stepped,
		not is_equal_approx(stepped, roundf(stepped)) or stepped <= UIScale.MIN)

	Settings.ui_scale = 0
	_check("and auto still reaches 2x on a 1440p overlay",
		is_equal_approx(UIScale.factor_for(Vector2(2560, 1440)), 2.0))
	_check("auto never picks a fractional factor, so nothing the game chooses is soft",
		is_equal_approx(UIScale.factor_for(Vector2(2560, 1440)),
			roundf(UIScale.factor_for(Vector2(2560, 1440)))))

## Dragging the window by its grip, and staying where it was put (D52).
##
## Drivable at all only because `begin/update/end_window_drag` take the cursor position as an
## argument instead of reading `DisplayServer.mouse_get_position()` themselves — no synthetic
## event can move a real cursor, so a gesture that reads the OS directly is untestable by
## construction. What is NOT covered here is the grip Control receiving the press; that is
## `ui_check`'s job, and crossing a real monitor seam stays in `docs/test-matrix.md`.
##
## Runs last. It deliberately leaves the window somewhere unusual, and every suite above
## reads the window it is given.
func _the_window_moves() -> void:
	_suite("moving the window")
	OverlayManager.set_window_mode(WindowLayout.Mode.PLAY_AREA)
	OverlayManager.snap_to_corner(WindowLayout.Corner.TOP_LEFT)
	await _idle(SETTLE)
	var start := DisplayServer.window_get_position()

	# Under the slop threshold: a click that wobbles is a click, not a drag.
	OverlayManager.begin_window_drag(Vector2i(600, 400))
	OverlayManager.update_window_drag(Vector2i(602, 401))
	await _idle(2)
	_check("a wobble under the slop threshold does not move the window",
		DisplayServer.window_get_position() == start)

	OverlayManager.update_window_drag(Vector2i(800, 500))
	await _idle(SETTLE)
	var moved := DisplayServer.window_get_position()
	_check("a 200x100 drag moves the window by 200x100 (%s -> %s)" % [start, moved],
		moved == start + Vector2i(200, 100))

	OverlayManager.end_window_drag()
	await _idle(SETTLE)
	_check("releasing clears the corner anchor, so nothing snaps it back",
		Settings.play_area_corner == WindowLayout.Corner.FREE)
	_check("and remembers where it was put",
		Settings.play_area_rect.position == DisplayServer.window_get_position())

	# The half that D49 got wrong: the move survived the release and was undone by the next
	# apply, because `target_rect` re-clamped every free position to one monitor.
	var settled := DisplayServer.window_get_position()
	OverlayManager.apply_window_configuration()
	await _idle(SETTLE)
	_check("and an apply leaves it there rather than re-homing it (%s)" % settled,
		DisplayServer.window_get_position() == settled)

	# Resizing used to throw the dragged position away and re-home it to a corner.
	OverlayManager.step_play_area_size(1)
	await _idle(SETTLE)
	_check("stepping the size keeps the position it was dragged to",
		DisplayServer.window_get_position() == settled)
	OverlayManager.step_play_area_size(-1)
	await _idle(SETTLE)

	# One assertion that says something on every machine, single-monitor CI included.
	var screens := DisplayServer.get_screen_count()
	if screens > 1:
		var other := (Settings.monitor_id + 1) % screens
		var target := DisplayServer.screen_get_usable_rect(other)
		var here := DisplayServer.window_get_position()
		OverlayManager.begin_window_drag(Vector2i(0, 0))
		OverlayManager.update_window_drag(target.position + Vector2i(80, 80) - here)
		OverlayManager.end_window_drag()
		await _idle(SETTLE)
		_check("with %d screens, a drag onto another one stays there" % screens,
			WindowLayout.screen_for_rect(Rect2i(DisplayServer.window_get_position(),
				DisplayServer.window_get_size()), _screen_rects()) == other)
	else:
		# The rule that holds either way: dragged past every edge, it is pulled back.
		OverlayManager.begin_window_drag(Vector2i(0, 0))
		OverlayManager.update_window_drag(Vector2i(20000, 20000))
		OverlayManager.end_window_drag()
		await _idle(SETTLE)
		_check("with 1 screen, a drag off the edge is pulled back onto it",
			WindowLayout.screen_for_rect(Rect2i(DisplayServer.window_get_position(),
				DisplayServer.window_get_size()), _screen_rects()) >= 0)

	# The flag D49 made a setting, checked against the real window rather than Settings.
	OverlayManager.set_always_on_top(false)
	await _idle(SETTLE)
	_check("always-on-top can be turned off for real",
		not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP))
	OverlayManager.set_always_on_top(true)
	await _idle(SETTLE)
	_check("and back on",
		DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP))

func _screen_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for i in DisplayServer.get_screen_count():
		out.append(DisplayServer.screen_get_usable_rect(i))
	return out

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
	Settings.play_area_rect = _restore["rect"]
	Settings.monitor_id = _restore["monitor"]
	Settings.always_on_top = _restore["on_top"]
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
