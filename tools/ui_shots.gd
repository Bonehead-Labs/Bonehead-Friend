extends CaptureWindow

## Renders the shell to PNGs so the look can be judged instead of imagined.
##
##   Godot --path <project> res://tools/ui_shots.tscn        (NOT --headless: it draws)
##
## Files land in `user://ui_shots/`. Nothing in the game depends on this; it exists because
## a menu cannot be reviewed from source, and because every earlier attempt to eyeball the
## theme by reasoning about stylebox margins was wrong.

const SIZE := Vector2i(1180, 760)
const OUT := "user://ui_shots"

var _main: Node

func _ready() -> void:
	_use_capture_slot()
	DirAccess.make_dir_recursive_absolute(OUT)
	Settings.focus_intensity = Settings.Intensity.NORMAL
	# Never inherit a pinned zoom from the machine: a capture is of the default the player
	# gets, not of whatever the last run left behind.
	Settings.ui_scale = 0
	# Same reason, and the same trap one setting over: the shell hides itself until hovered
	# (D29), and a capture has no cursor. Pinned deliberately so every shot shows the shell,
	# rather than showing whatever the last session left pinned.
	Settings.hud_pinned = true
	Settings.tabs_pinned = true
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "screenshots")
	await _idle(20)

	_stage()
	await _idle(30)

	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	var tree := _find(_main, "AugmentPanel")

	await _shot("01-hud")

	panels.call("show_panel", &"shop")
	await _shot("02-toys-melee")
	shop.call("show_category", ItemData.CATEGORY_FRIENDLY)
	shop.call("select", &"boombox")
	await _shot("03-toys-kind")

	panels.call("show_panel", &"tree")
	await _shot("04-upgrades")
	tree.call("select", &"mace")
	await _shot("05-upgrades-mace")

	panels.call("show_panel", &"contracts")
	await _shot("06-jobs")
	panels.call("show_panel", &"prestige")
	await _shot("07-rebirth")
	panels.call("show_panel", &"settings")
	await _shot("08-settings")

	panels.call("close")
	var esc := _find(_main, "EscMenu")
	esc.call("open")
	await _shot("09-paused")
	esc.call("close")

	# The same window at 2x, which is what a 1440p overlay gets automatically. Shot by
	# pinning the setting rather than by resizing the window, because the point is the
	# ratio of UI to play area and not the number of pixels.
	var pinned := Settings.ui_scale
	Settings.ui_scale = 2
	EventBus.ui_scale_changed.emit(2)
	panels.call("show_panel", &"shop")
	await _shot("10-toys-2x")
	# Restored, and restored to whatever it was rather than to a guess. Leaving this pinned
	# meant every later screenshot was silently taken at 2x — including the ones used to
	# judge whether 1x was readable.
	Settings.ui_scale = pinned
	EventBus.ui_scale_changed.emit(pinned)

	_clear_slot()
	print("ui_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	get_tree().quit()

## A mid-run save, because an empty one shows an empty shop. Enough money to make some
## prices affordable and some not, one weapon bought, a tier-1 node part-levelled and a
## branch taken — which is the only state in which the gate strip and a struck-out card
## can be seen at all.
func _stage() -> void:
	Economy.grant(Economy.BONES, 1510.0)
	Economy.grant(Economy.HEARTS, 500.0)
	Progression.purchase_item(&"mace")
	Progression.purchase_item(&"sponge")
	Progression.add_mastery_xp(&"baseball_bat", 40000.0)
	Progression.add_mastery_xp(&"mace", 3000.0)
	for node in ItemDB.augments_for(&"baseball_bat"):
		if node.tier == 1 and node.exclusive_group == &"":
			Progression.purchase_augment(node.id, 3)
		elif node.exclusive_group != &"" and node.effect_key == &"payout_mult":
			Progression.purchase_augment(node.id, 1)

func _shot(name: String) -> void:
	# Long enough for every entrance tween to have settled: a screenshot of a card mid-open
	# is a picture of a bug that is not there.
	await _idle(45)
	await RenderingServer.frame_post_draw
	_grab().save_png("%s/%s.png" % [OUT, name])
	print("  %s" % name)
