extends CaptureWindow

## Renders the shell against content designed to break it.
##
##   Godot --path <project> res://tools/ui_stress.tscn        (NOT --headless: it draws)
##
## `ui_shots.tscn` photographs the game as it is. This photographs the game as it will be:
## the roster is meant to reach 28 items and the trees to grow tiers, and every layout bug
## the owner has hit so far has been a piece of content that was a different size from the
## content the layout was built against — a 64px crosshair in a 44px well, an effect line
## that wraps to three lines beside two that wrap to two.
##
## So this loads the real UI and feeds it deliberately hostile data **in memory only**:
## names at the length the catalogue actually reaches, an icon at the wrong size, a
## category with more items than any category has today, an augment with more levels than
## the pip row can draw. Nothing is written to disk and no `.tres` is touched.
##
## Read the shots side by side with `user://ui_shots`: anything that moves between the two
## is a layout that depends on its content rather than on its rules.

const SIZE := Vector2i(1180, 760)
const OUT := "user://ui_stress"

## The longest names in `docs/game-design.md`'s catalogue that are not built yet. If the
## shell cannot draw these, it cannot draw the roster it is specified to have.
const LONG_NAMES := {
	&"baseball_bat": "Chocolate Fountain",
	&"mace": "Reinforced Massage Chair",
	&"frying_pan": "Firework Rocket Launcher",
	&"grenade": "Weighted Companion Cube",
	&"sponge": "Extra Absorbent Sponge",
	&"pizza": "Family Size Deep Pan Pizza",
}

var _main: Node

func _ready() -> void:
	_use_capture_slot()
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.ui_scale = 0
	DirAccess.make_dir_recursive_absolute(OUT)
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "stress")
	await _idle(20)

	_stage()
	_make_it_hostile()
	var shop := _find(_main, "ShopPanel")
	var tree := _find(_main, "AugmentPanel")
	var panels := _find(_main, "PanelLayer")
	await _idle(20)

	# Both panels build their rows once and only refresh afterwards, which is correct for
	# the game and means a stress tool has to ask for the rebuild explicitly.
	panels.call("show_panel", &"shop")
	if shop:
		shop.call("show_category", ItemData.CATEGORY_WEAPON)
	await _shot("s1-toys-long-names")
	if shop:
		shop.call("show_category", ItemData.CATEGORY_CURSOR_POWER)
	await _shot("s2-toys-cursor-powers")
	if shop:
		shop.call("show_category", ItemData.CATEGORY_FRIENDLY)
	await _shot("s3-toys-crowded")

	panels.call("show_panel", &"tree")
	await _shot("s4-tree")
	if tree:
		tree.call("select", &"mace")
	await _shot("s5-tree-long-name")

	panels.call("show_panel", &"contracts")
	await _shot("s6-jobs")
	panels.call("show_panel", &"settings")
	await _shot("s7-settings")

	# The same hostile content at 2x, where every box is twice as big and every texture is
	# still whatever size it was authored at.
	Settings.ui_scale = 2
	EventBus.ui_scale_changed.emit(2)
	panels.call("show_panel", &"shop")
	await _shot("s8-toys-2x")
	Settings.ui_scale = 0
	EventBus.ui_scale_changed.emit(0)

	print("ui_stress: wrote %s" % ProjectSettings.globalize_path(OUT))
	_clear_slot()
	get_tree().quit()

## A mid-run save, so shops and trees have something in them.
func _stage() -> void:
	Economy.grant(Economy.BONES, 4000.0)
	Economy.grant(Economy.HEARTS, 2000.0)
	for id in [&"mace", &"sponge", &"pistol", &"frying_pan", &"pizza"]:
		Progression.purchase_item(id)
	Progression.add_mastery_xp(&"baseball_bat", 40000.0)

## In memory only. `ItemDB` hands out the same ItemData objects the panels already hold, so
## renaming one is enough to make every label that draws it re-measure.
func _make_it_hostile() -> void:
	for id in LONG_NAMES:
		var item := ItemDB.get_item(id)
		if item:
			item.display_name = LONG_NAMES[id]
	# The exact bug the owner photographed, made deliberate: an icon at the size a raw
	# prototype asset happens to be rather than at the size the well expects.
	var oversized := ResourceLoader.load("res://Assets/Crosshair Basic.png") as Texture2D
	var bat := ItemDB.get_item(&"baseball_bat")
	if bat and oversized:
		bat.icon = oversized
	# And the opposite: an item with no art at all, which falls back to a 16px glyph.
	var pan := ItemDB.get_item(&"frying_pan")
	if pan:
		pan.icon = null

func _shot(name: String) -> void:
	await _idle(45)
	await RenderingServer.frame_post_draw
	_grab().save_png("%s/%s.png" % [OUT, name])
	print("  %s" % name)
