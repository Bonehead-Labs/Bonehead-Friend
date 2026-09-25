extends CaptureWindow

## The fidget toys (D57, D66) as the player sees them: the shop's how-to strip, and both sets of
## five on the desk beside him, caught mid-use.
##
##   Godot --path <project> res://tools/fidget_shots.tscn        (NOT --headless: it draws)
##   Godot --fixed-fps 30 --path <project> res://tools/fidget_shots.tscn   (the idle cap)
##
## The `motion-*` sheets are consecutive frames, a row per toy: a spin that strobes shows only
## there, and only at the frame rate it strobes at (D75). Files land in `user://fidget_shots/`. Its own save slot and settings file, through
## `CaptureWindow._use_capture_slot()`, like every capture tool.

const SIZE := Vector2i(1180, 760)
const OUT := "user://fidget_shots"
const FIDGETS: Array[StringName] = [&"bubble_wrap", &"stress_ball", &"fidget_spinner",
	&"magic_eight_ball", &"jack_in_the_box"]
const TOYS2: Array[StringName] = [&"slinky", &"newtons_cradle", &"pull_back_car", &"yo_yo",
	&"slingshot"]

var _main: Node
var _had := {}

func _ready() -> void:
	_use_capture_slot()
	_had = {"hud": Settings.hud_pinned, "tabs": Settings.tabs_pinned, "scale": Settings.ui_scale,
		"focus": Settings.focus_intensity}
	DirAccess.make_dir_recursive_absolute(OUT)
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.ui_scale = 0
	Settings.hud_pinned = true
	Settings.tabs_pinned = true
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "fidget toys")
	await _idle(20)
	Economy.grant(Economy.HEARTS, 50000.0)
	for id in FIDGETS:
		Progression.purchase_item(id)

	# The shop, on the one toy with two gestures to explain.
	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	panels.call("show_panel", &"shop")
	shop.call("show_side", ItemData.SIDE_KIND)
	shop.call("show_category", ItemData.CATEGORY_TOY)
	shop.call("select", &"jack_in_the_box")
	await _shot("01-shop-howto")
	shop.call("select", &"bubble_wrap")
	await _shot("02-shop-howto-bubbles")
	panels.call("close")
	await _idle(10)

	# The desk: all five beside him, each doing its thing.
	var buddy := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	var idle := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	var floor_y := float(SIZE.y) - 60.0
	var x := float(SIZE.x) * 0.5 - 330.0
	var toys := {}
	for id in FIDGETS:
		EventBus.spawn_requested.emit(id, Vector2(x, floor_y - 40.0))
		x += 150.0
		for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
			if (node as BaseDraggable).item_id == id:
				toys[id] = node
	if idle:
		idle._disturb()
	await _idle(90)
	if buddy:
		buddy.global_position = Vector2(float(SIZE.x) * 0.5 - 20.0, floor_y - 120.0)
	var wrap := toys.get(&"bubble_wrap") as BubbleWrap
	if wrap:
		for slot in [1, 2, 6]:
			wrap.pop(slot, true)
	var spinner := toys.get(&"fidget_spinner") as FidgetSpinner
	if spinner:
		spinner.launch(spinner.max_spin, true)
	var jack := toys.get(&"jack_in_the_box") as JackInTheBox
	if jack:
		jack.set_facing(-1.0)
		jack.pop()
	var ball := toys.get(&"magic_eight_ball") as MagicEightBall
	if ball:
		ball.bubble_seconds = 30.0
		ball._energy = ball._needed()
		ball.read(true, 1)
	var squeeze := toys.get(&"stress_ball") as StressBall
	if squeeze:
		squeeze._show_squash(1.0)
	await _shot("03-desk")
	# A moment later: the spinner has moved on, the jack has settled, he has reacted.
	await _shot("04-desk-later")
	# The spinner from a fresh flick, frame by frame, as it runs down (D75).
	if spinner:
		spinner.launch(spinner.max_spin, true)
		await _strip("08-motion-spinner", [spinner], 12)
		await _idle(60)
		await _strip("09-motion-spinner-slower", [spinner], 12)
	await _second_five(buddy, idle, floor_y)

	_clear_slot()
	print("fidget_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	Settings.hud_pinned = _had["hud"]
	Settings.tabs_pinned = _had["tabs"]
	Settings.ui_scale = _had["scale"]
	Settings.focus_intensity = _had["focus"]
	Settings.save_settings()
	get_tree().quit()

## The second five (D66): the Guns drawer's how-to strip on the slingshot, then the five on the
## desk, caught mid-use — a slinky stretched from where it lies, the cradle mid-clack, the car
## half wound with its notches showing. The yo-yo and the slingshot are only ever worked in the
## hand, so they are shown at rest; `toys2_check` is what drives those.
func _second_five(buddy: Buddy, idle: IdleBrain, floor_y: float) -> void:
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if spawner:
		spawner.clear_desk()
	Economy.grant(Economy.BONES, 50000.0)
	for id in TOYS2:
		var item := ItemDB.get_item(id)
		if item:
			for req in item.requires:
				Progression.purchase_item(req)
		Progression.purchase_item(id)
	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	panels.call("show_panel", &"shop")
	shop.call("show_side", ItemData.SIDE_HARM)
	shop.call("show_category", ItemData.CATEGORY_GUN)
	shop.call("select", &"slingshot")
	await _shot("05-shop-howto-slingshot")
	panels.call("close")
	await _idle(10)
	var x := float(SIZE.x) * 0.5 - 380.0
	var toys := {}
	for id in TOYS2:
		EventBus.spawn_requested.emit(id, Vector2(x, floor_y - 40.0))
		x += 170.0
		for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
			if (node as BaseDraggable).item_id == id:
				toys[id] = node
	if idle:
		idle._disturb()
	await _idle(90)
	if buddy:
		buddy.global_position = Vector2(float(SIZE.x) * 0.5 + 60.0, floor_y - 120.0)
	var slinky := toys.get(&"slinky") as Slinky
	if slinky:
		slinky._plant(slinky.global_position)
		slinky._pull_to(slinky.global_position + Vector2(60.0, -130.0))
	var cradle := toys.get(&"newtons_cradle") as NewtonsCradle
	if cradle:
		cradle.release(-1, deg_to_rad(40.0), true)
	var car := toys.get(&"pull_back_car") as PullBackCar
	if car:
		car._start_wind(car.global_position)
		for i in 9:
			car._wind_to(car.global_position + Vector2(-10.0 * float(i + 1), 0.0))
	await _shot("06-desk-toys2")
	if slinky:
		slinky._let_go()
	await _shot("07-desk-toys2-later")
	if car:
		# Let go: it drives, and its wheels are the fastest thing on the desk (D75).
		if cradle:
			cradle.release(-1, deg_to_rad(40.0), true)
		car._end_wind()
		await _strip("10-motion-cradle-car", [cradle, car], 12, Vector2i(112, 96))

## Consecutive frames around a few things, a row per thing and a column per frame, so motion
## can be judged from a still (D75). Something turning past half its own symmetry in one frame
## reads as turning backwards, and only frame to frame. Run the tool at `--fixed-fps 30` to see
## what the idle frame cap shows, or 20 for Low Power.
func _strip(name: String, targets: Array, frames: int, box: Vector2i = Vector2i(96, 96)) -> void:
	if DisplayServer.get_name() == "headless":
		print("  %s (staged; headless draws nothing)" % name)
		return
	var sheet := Image.create_empty(box.x * frames, box.y * targets.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(DESKTOP)
	for f in frames:
		await RenderingServer.frame_post_draw
		var frame := _grab()
		frame.convert(Image.FORMAT_RGBA8)
		for row in targets.size():
			var node := targets[row] as Node2D
			if node == null or not is_instance_valid(node):
				continue
			var at := Vector2i(node.get_global_transform_with_canvas().origin) - box / 2
			sheet.blit_rect(frame, Rect2i(at, box), Vector2i(f * box.x, row * box.y))
	sheet.save_png("%s/%s.png" % [OUT, name])
	print("  %s (%d frames, %.0f fps)" % [name, frames, 1.0 / maxf(get_process_delta_time(), 0.001)])

## Headless draws nothing, so there a shot is only the staging — which is still worth running,
## because it proves the staging itself works before anyone opens a window for it.
func _shot(name: String) -> void:
	await _idle(45)
	if DisplayServer.get_name() == "headless":
		print("  %s (staged; headless draws nothing)" % name)
		return
	await RenderingServer.frame_post_draw
	_grab().save_png("%s/%s.png" % [OUT, name])
	print("  %s" % name)
