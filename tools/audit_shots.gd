extends Node

## Drives the real game through its states and saves a PNG of each one.
##
##   Godot --path <project> res://tools/audit_shots.tscn [-- --screen N] [--overlay]
##
## Must NOT be headless: headless does not render, and its viewport is 64x64.
##
## `--screen N` runs the audit on a particular monitor and `--overlay` runs it as the real
## fullscreen overlay rather than a fixed play-area window, because "does it look right"
## has a different answer on a 2560x1440 16:9 panel than on a 3440x1440 ultrawide — the
## HUD anchors to window corners that are much further apart on one than the other. Shots
## are suffixed with the screen, so two runs do not overwrite each other.
##
## Flags are command-line args, never environment variables: the game is a Windows process
## and OS.get_environment() cannot see anything exported from WSL (CLAUDE.md).
##
## The window is transparent, so a raw capture is mostly alpha. Each shot is composited
## onto a flat colour first — otherwise the UI is being judged against whatever the
## screenshot viewer happens to paint behind it.

const OUT_DIR := "user://audit"
const BACKDROP := Color(0.17, 0.18, 0.22)
const AUDIT_SLOT := "audit_slot"

var _main: Node
var _panels: PanelLayer
var _esc: EscMenu
var _shot := 0
var _suffix := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var screen := _screen_arg(args)
	var as_overlay := args.has("--overlay")
	_suffix = "_s%d%s" % [screen, "_overlay" if as_overlay else ""]

	# Its own preferences file before any of them are changed (D51): this tool pins Focus
	# Mode, the monitor and the window mode to make a capture reproducible, and a hint firing
	# mid-run would persist all of it into the developer's real settings.
	Settings.config_path = "user://settings_audit.cfg"
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.monitor_id = screen
	SaveManager.slot_name = AUDIT_SLOT

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_place_window(screen, as_overlay)

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_panels = _find(_main, "PanelLayer") as PanelLayer
	_esc = _find(_main, "EscMenu") as EscMenu

	# Money, so the shop shows the affordable and the unaffordable side by side. Hearts too,
	# or the whole friendly half of the catalog photographs as one undifferentiated wall of
	# unaffordable tiles and the audit says nothing about it.
	Economy.grant(Economy.BONES, 1500.0)
	Economy.grant(Economy.HEARTS, 500.0)

	await _settle(70)
	await _shoot("boot")

	if _panels:
		_panels.show_panel(&"shop")
		await _settle(6)
		await _shoot("shop")

		# With mastery earned, so the rank readout and an unlocked branch are in frame.
		Progression.add_mastery_xp(&"baseball_bat",
			EconomyMath.mastery_xp_for_rank(ItemDB.balance.mastery_base, 12))
		_panels.show_panel(&"tree")
		await _settle(6)
		await _shoot("tree")

		# Contracts and Rebirth are shot with something to show: an empty board and a
		# "nothing to gain yet" page tell you nothing about whether either one reads.
		Progression.refresh_contracts(true)
		EventBus.contract_event.emit(&"deal_damage", 2600)
		EventBus.contract_event.emit(&"knockout", 10)
		EventBus.contract_event.emit(&"pet", 200)
		_panels.show_panel(&"contracts")
		await _settle(6)
		await _shoot("contracts")

		Economy.grant(Economy.BONES, ItemDB.balance.marrow_divisor * 30.0)
		_panels.show_panel(&"arcade")
		await _settle(6)
		await _shoot("rebirth")

		_panels.show_panel(&"settings")
		await _settle(6)
		await _shoot("settings")
		_panels.close()

	# Some toys on the desk, and a hit, so the FX layer is in frame.
	# Buy the mace first: spawn_requested is correctly ignored for anything unowned, so an
	# audit that only grants money quietly photographs a world with fewer toys in it.
	Progression.purchase_item(&"mace")
	for id in [&"grenade", &"sponge", &"pizza", &"bowling_ball", &"beach_ball", &"frying_pan"]:
		Progression.purchase_item(id)
	for id in [&"grenade", &"sponge", &"pizza", &"bowling_ball", &"beach_ball", &"frying_pan"]:
		EventBus.spawn_requested.emit(id, Vector2(120 + randi() % 400, 80))
	await _settle(50)
	var centre := Vector2(get_window().size) * 0.5
	EventBus.damage_dealt.emit(HitInfo.new(46.0, &"baseball_bat", centre, 4000.0))
	EventBus.damage_dealt.emit(HitInfo.new(12.0, &"mace", centre + Vector2(90, -40), 1500.0))
	await _settle(4)
	await _shoot("play")

	await _settle(40)
	await _shoot("settled")

	# The two readouts M3 added, at the values that actually need checking: a filthy buddy
	# and a mood at one of the U-curve's paying extremes. Both are invisible at their
	# defaults, which is exactly how the knockout meter went unnoticed for a milestone.
	var buddy := _find_deep(_main, "Buddy") as Buddy

	# The new art, at the two things that matter: does the generated body animation play,
	# and does a hand-drawn expression stay glued to a head that bobs 11 px?
	#
	# Driven through *mood*, not by setting the expression directly. Setting it directly is
	# what the first version of this did, and every shot came back neutral — the mood
	# handler fires during the settle and overrides it, which is correct behaviour and a
	# useless test.
	var art := _find_deep(_main, "BuddyArt")
	if art and buddy:
		for entry in [[-90.0, "despair"], [-40.0, "sad"], [0.0, "neutral"],
				[40.0, "cheerful"], [90.0, "bliss"]]:
			buddy.mood.set_value(float(entry[0]))
			await _settle(9)
			await _shoot("face_%s" % entry[1])
		buddy.mood.set_value(0.0)
	if buddy:
		buddy.grime.set_value(0.8)
		buddy.mood.set_value(-85.0)
		await _settle(6)
		await _shoot("grimy_and_miserable")
		buddy.mood.set_value(90.0)
		buddy.grime.set_value(0.0)
		await _settle(6)
		await _shoot("blissful")

		# The round's climax, mid-collapse and mid-fountain.
		buddy.health.apply_damage(ItemDB.balance.knockout_damage)
		# Late enough for the fountain to have spread. Caught at launch it is a knot of
		# numbers on top of each other and says nothing about whether the beat reads.
		await _settle(58)
		await _shoot("knockout_pile")
		while buddy.health.down:
			await get_tree().process_frame
		await _settle(6)

	if _esc:
		_esc.open()
		await _settle(6)
		await _shoot("esc")

	_cleanup()
	get_tree().quit()

## Which monitor to audit on. Clamped rather than trusted: a screen index from a previous
## session is exactly the sort of thing that survives a monitor being unplugged.
func _screen_arg(args: PackedStringArray) -> int:
	var index := args.find("--screen")
	if index < 0 or index + 1 >= args.size():
		return DisplayServer.get_primary_screen()
	return clampi(args[index + 1].to_int(), 0, DisplayServer.get_screen_count() - 1)

func _place_window(screen: int, as_overlay: bool) -> void:
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if as_overlay:
		# The real thing: OverlayManager owns the window, fills the monitor's usable rect
		# and leaves the taskbar as the floor.
		Settings.overlay_enabled = true
		Settings.window_mode = WindowLayout.Mode.FULLSCREEN_OVERLAY
		OverlayManager.apply_window_configuration()
		return

	# Otherwise keep OverlayManager off the window — its deferred apply would resize and
	# reposition to the player's saved play area, and the audit wants a consistent frame —
	# and place a play-area-sized window on the requested screen by hand.
	Settings.overlay_enabled = false
	# Shoot at the size the player will actually see, not a convenient one: a HUD that only
	# fits in a 1280-wide capture is a HUD that does not fit.
	get_window().size = Settings.play_area_size
	get_window().position = usable.position + (usable.size - Settings.play_area_size) / 2

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _shoot(shot_name: String) -> void:
	# The texture is only valid once the frame has actually been drawn.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var canvas := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	canvas.fill(BACKDROP)
	canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	_shot += 1
	canvas.save_png("%s/%02d_%s%s.png" % [OUT_DIR, _shot, shot_name, _suffix])

## The buddy is nested inside World, so the shallow child scan cannot reach him.
func _find_deep(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name or (root.get_script() != null \
			and root.get_script().get_global_name() == type_name):
		return root
	for child in root.get_children():
		var found := _find_deep(child, type_name)
		if found:
			return found
	return null

func _find(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name or (child.get_script() != null and child.get_script().get_global_name() == type_name):
			return child
	return null

func _cleanup() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
