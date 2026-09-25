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
var _had := {}

func _ready() -> void:
	_use_capture_slot()
	# Captured before anything is stomped and written back at the end: the backdrop shots go
	# through `OverlayManager.set_backdrop`, which saves *every* setting — so the pins, the zoom
	# and the Focus Mode this tool forces were landing in the player's own settings.cfg.
	_had = {"hud": Settings.hud_pinned, "tabs": Settings.tabs_pinned, "scale": Settings.ui_scale,
		"focus": Settings.focus_intensity}
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
	# The sixth tab on the harm side (D56): the strip has to hold six at one width.
	shop.call("show_category", ItemData.CATEGORY_GUN)
	shop.call("select", &"revolver")
	await _shot("02b-toys-guns")
	shop.call("show_category", ItemData.CATEGORY_FRIENDLY)
	shop.call("select", &"boombox")
	await _shot("03-toys-kind")

	panels.call("show_panel", &"tree")
	await _shot("04-upgrades")
	tree.call("select", &"mace")
	await _shot("05-upgrades-mace")

	panels.call("show_panel", &"contracts")
	await _shot("06-jobs")
	panels.call("show_panel", &"arcade")
	var arcade := _find(_main, "ArcadePanel")
	await _shot("07-arcade-wheel")
	arcade.call("show_room", &"slot_machine")
	await _shot("07b-arcade-ghosts")
	arcade.call("show_room", &"blackjack")
	arcade.call("_on_play", arcade.get("_machines")[2])
	await _shot("07c-arcade-blackjack")
	arcade.call("show_room", &"wardrobe")
	await _shot("07d-wardrobe")
	arcade.call("show_room", &"rebirth")
	await _shot("07e-rebirth")
	panels.call("show_panel", &"deeds")
	await _shot("06b-deeds")
	panels.call("show_panel", &"settings")
	await _shot("08-settings")
	(panels.get("_host") as ScrollContainer).scroll_vertical = 100000
	await _shot("08b-settings-backdrop")
	# Two backdrops, on the real window: the shots are how anyone reviews a scene, and the
	# setting is restored because ui_shots shares settings.cfg with the player.
	var had_backdrop := Settings.backdrop
	panels.call("close")
	OverlayManager.set_backdrop(&"hills")
	await _shot("13-backdrop-hills")
	OverlayManager.set_backdrop(&"night")
	await _shot("14-backdrop-night")
	OverlayManager.set_backdrop(&"desk")
	await _shot("15-backdrop-desk")
	# The world's effects, caught mid-flight against a flat ground: a boom, a bolt, a landing, a
	# rank line. Six frames in rather than the usual forty-five, because a ring lasts twenty.
	OverlayManager.set_backdrop(&"charcoal")
	await _idle(10)
	var world_fx := _find(_main, "WorldFX")
	var centre := Vector2(SIZE) * 0.5
	world_fx.call("boom", centre + Vector2(-220, 40), 1.0)
	world_fx.call("bolt", PackedVector2Array([centre + Vector2(200, -200), centre + Vector2(200, -40), centre + Vector2(300, 20)]))
	world_fx.call("tracer", centre + Vector2(-380, 120), centre + Vector2(60, 60))
	EventBus.buddy_landed.emit(centre + Vector2(60, 120), 1000.0)
	EventBus.mastery_rank_up.emit(&"mace", 4)
	# A streak on the card and embers on him, and a hot tub steaming beside him.
	Economy._streak_deadline_msec = 0
	for i in 12:
		EventBus.damage_dealt.emit(HitInfo.new(30.0, &"baseball_bat", centre + Vector2(60, 40), 1000.0))
	var tub := (load("res://Scenes/Friendly/hot_tub.tscn") as PackedScene).instantiate() as Node2D
	tub.set("item_id", &"hot_tub")
	(_find(_main, "ItemSpawner").get("world") as Node2D).add_child(tub)
	tub.global_position = centre + Vector2(-140, 220)
	# A rank-40 bat (tier 3, white-hot) beside a rank-8 mace (tier 1): the upgrade, worn.
	EventBus.spawn_requested.emit(&"baseball_bat", centre + Vector2(-330, 60))
	EventBus.spawn_requested.emit(&"mace", centre + Vector2(330, 110))
	# Two turrets, each on the side its art does not face, so both have to turn to look at him;
	# the flamethrower fires ten times a second, so its tracer is in every frame.
	Economy.grant(Economy.BONES, 1.0e6)
	for id in [&"flamethrower", &"pellet_turret"]:
		_unlock_chain(id)
	EventBus.spawn_requested.emit(&"flamethrower", centre + Vector2(-130, 250))
	EventBus.spawn_requested.emit(&"pellet_turret", centre + Vector2(250, 150))
	# Two held guns lying on the desk (D56), for their size beside him and the turrets.
	for id in [&"hunting_rifle", &"water_pistol"]:
		_unlock_chain(id)
	EventBus.spawn_requested.emit(&"hunting_rifle", centre + Vector2(-20, 250))
	EventBus.spawn_requested.emit(&"water_pistol", centre + Vector2(170, 250))
	for step in [["16-juice", 2], ["16b-juice", 6], ["16c-juice", 12]]:
		for i in int(step[1]):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_grab().save_png("%s/%s.png" % [OUT, step[0]])
		print("  %s" % step[0])
	# Binned before the tool moves on: a tub left steaming pays kindness into a HUD that has
	# been torn down by the time the tool quits.
	tub.queue_free()
	await _idle(40)
	OverlayManager.set_backdrop(had_backdrop)

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
	# Six harm tabs at 2x and at the quarter step between (D50, D56): the strip is where a
	# seventh caption would first run out of room.
	shop.call("show_category", ItemData.CATEGORY_GUN)
	await _shot("10b-guns-2x")
	Settings.ui_scale = 1.25
	EventBus.ui_scale_changed.emit(1.25)
	await _shot("10c-guns-1.25x")
	# Restored, and restored to whatever it was rather than to a guess. Leaving this pinned
	# meant every later screenshot was silently taken at 2x — including the ones used to
	# judge whether 1x was readable.
	Settings.ui_scale = pinned
	EventBus.ui_scale_changed.emit(pinned)

	# The automation capstone, owned and running. It is the only card in the shell with
	# four states and it sits below the fold of any item with a full tree, so it went
	# unreviewed for the whole of M3 — and then M3.5-A gave it levels, an output line and a
	# switch of its own. Staged last: buying it needs a purse that would change what every
	# earlier shot says about affordability.
	Economy.grant(Economy.HEARTS, 20000.0)
	Progression.purchase_augment(&"bat_sentry", 4)
	panels.call("show_panel", &"tree")
	tree.call("select", &"baseball_bat")
	await _idle(20)
	tree.call("scroll_to_end")
	await _shot("11-upgrades-automation")

	# And the thing it bought, standing on the desk. The panel says 4.00 Bones/s; this is
	# the only shot that shows what that looks like from across the room, which is where
	# the player is (D6).
	panels.call("close")
	await _shot("12-devices")

	_clear_slot()
	print("ui_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	Settings.hud_pinned = _had["hud"]
	Settings.tabs_pinned = _had["tabs"]
	Settings.ui_scale = _had["scale"]
	Settings.focus_intensity = _had["focus"]
	Settings.save_settings()
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

## Buys an item and everything it requires first, through the shop's own path.
func _unlock_chain(id: StringName) -> void:
	if Progression.is_unlocked(id):
		return
	var item := ItemDB.get_item(id)
	if item == null:
		return
	for req in item.requires:
		_unlock_chain(req)
	Progression.purchase_item(id)
