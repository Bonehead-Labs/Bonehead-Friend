extends Node

## Drives the real game through its states and saves a PNG of each one.
##
##   Godot --path <project> res://tools/audit_shots.tscn
##
## Must NOT be headless: headless does not render, and its viewport is 64x64.
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

func _ready() -> void:
	# Keep OverlayManager off the window: its deferred apply would resize and reposition
	# to the player's saved play area, and the audit wants a consistent frame.
	Settings.overlay_enabled = false
	Settings.focus_intensity = Settings.Intensity.NORMAL
	SaveManager.slot_name = AUDIT_SLOT

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Shoot at the size the player will actually see, not a convenient one — a HUD that
	# only fits in a 1280-wide capture is a HUD that does not fit.
	get_window().size = Settings.play_area_size

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_panels = _find(_main, "PanelLayer") as PanelLayer
	_esc = _find(_main, "EscMenu") as EscMenu

	# Money, so the shop shows the affordable and the unaffordable side by side.
	Economy.grant(Economy.BONES, 1500.0)

	await _settle(70)
	await _shoot("boot")

	if _panels:
		_panels.show_panel(&"shop")
		await _settle(6)
		await _shoot("shop")

		_panels.show_panel(&"tree")
		await _settle(6)
		await _shoot("tree")
		_panels.close()

	# Some toys on the desk, and a hit, so the FX layer is in frame.
	# Buy the mace first: spawn_requested is correctly ignored for anything unowned, so an
	# audit that only grants money quietly photographs a world with fewer toys in it.
	Progression.purchase_item(&"mace")
	for id in [&"baseball_bat", &"mace", &"grenade"]:
		EventBus.spawn_requested.emit(id, Vector2(120 + randi() % 400, 80))
	await _settle(50)
	var centre := Vector2(get_window().size) * 0.5
	EventBus.damage_dealt.emit(HitInfo.new(46.0, &"baseball_bat", centre, 4000.0))
	EventBus.damage_dealt.emit(HitInfo.new(12.0, &"mace", centre + Vector2(90, -40), 1500.0))
	await _settle(4)
	await _shoot("play")

	await _settle(40)
	await _shoot("settled")

	if _esc:
		_esc.open()
		await _settle(6)
		await _shoot("esc")

	_cleanup()
	get_tree().quit()

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
	canvas.save_png("%s/%02d_%s.png" % [OUT_DIR, _shot, shot_name])

func _find(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name or (child.get_script() != null and child.get_script().get_global_name() == type_name):
			return child
	return null

func _cleanup() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
