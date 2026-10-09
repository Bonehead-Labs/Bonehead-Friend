extends Node

## Check of the boot: the Bonehead Labs studio splash (`Scripts/boot_splash.gd`, a thin adapter
## over the shared addon `addons/bonehead_labs_splash/`) and its hand-off to `main.tscn`.
##
##   Godot --headless --path <project> res://tests/integration/splash_check.tscn
##   Godot --path <project> res://tests/integration/splash_check.tscn -- --shots    (NOT headless)
##
## The boot settings, where the card goes in each window mode, a quit during the splash, a skip,
## the headless pass-through, and the real flow: the adapter as the current scene, the splash
## played out on its own clock, `main.tscn` opened by `change_scene_to_file`.
##
## `--shots` runs windowed and writes PNGs of the card on the real overlay window to
## `user://splash_shots/`, flattened onto CaptureWindow's stand-in desktop. Headless draws
## nothing, so that is the only way to see the GL Compatibility render. It opens the overlay
## with this machine's own window settings (read, never written) and steals the focus for about
## six seconds.
##
## Runs against its own save slot and its own settings file. `_check(what, ok)` takes two
## arguments, like loop_check's.

const BootSplash := preload("res://Scripts/boot_splash.gd")
const SplashScript := preload("res://addons/bonehead_labs_splash/bonehead_labs_splash.gd")
const ADAPTER := "res://boot_splash.tscn"
const MAIN := "res://main.tscn"
const SPLASH := "res://addons/bonehead_labs_splash/bonehead_labs_splash.tscn"
const BOOT_IMAGE := "res://addons/bonehead_labs_splash/boot/bonehead_boot.png"
const PAPER := Color(0.956863, 0.929412, 0.878431, 1)
const TEST_SLOT := "splash_check_slot"
const TEST_SETTINGS := "user://settings_splash_check.cfg"
const SHOTS_DIR := "user://splash_shots"
const SHOT_TIMES: Array[float] = [0.05, 0.85, 1.3, 1.75, 2.5, 3.62, 3.9]
const DESKTOP := Color("4a4a52")
## Wall-clock ceiling on any one wait, so a broken hand-off fails instead of hanging.
const TIMEOUT_MSEC := 15000

var _passed := 0
var _failed := 0
var _shots := false
var _focus_before := Settings.Intensity.NORMAL
## Members, not locals: a lambda captures locals by value (CLAUDE.md).
var _finished_count := 0
var _finished_state: Dictionary = {}


func _ready() -> void:
	# Before anything else (D51): main.tscn marks hints seen and saves settings.
	Settings.config_path = TEST_SETTINGS
	_focus_before = Settings.focus_intensity
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	_shots = OS.get_cmdline_user_args().has("--shots") and DisplayServer.get_name() != "headless"

	print("")
	print("Bonehead Friend — splash check")
	print("==============================")
	_check_boot_settings()
	_check_card_rect()
	_check_quit_before_load()
	_run.call_deferred()


func _run() -> void:
	# The flow changes scene, which frees the current scene: hand that role to a placeholder so
	# this node survives as a plain child of the root.
	var holder := Node.new()
	holder.name = "SplashCheckHolder"
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder

	if DisplayServer.get_name() == "headless":
		await _check_headless_pass_through()
	await _check_skip()
	await _check_boot_flow()

	print("")
	print("==============================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	Settings.focus_intensity = _focus_before
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)


# --- suites ---------------------------------------------------------------------------

func _check_boot_settings() -> void:
	_suite("boot settings")
	_check("run/main_scene is the splash adapter",
		ProjectSettings.get_setting("application/run/main_scene") == ADAPTER)
	_check("boot image is the splash's first frame",
		ProjectSettings.get_setting("application/boot_splash/image") == BOOT_IMAGE)
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	_check("boot background is the paper", bg.is_equal_approx(PAPER))
	_check("boot image is filtered", ProjectSettings.get_setting("application/boot_splash/use_filter") == true)
	_check("boot image keeps its aspect", int(ProjectSettings.get_setting("application/boot_splash/stretch_mode")) == 1)
	var boot := load(BOOT_IMAGE) as Texture2D
	_check("boot image is imported at 1920x1080", boot != null and boot.get_size() == Vector2(1920, 1080))
	var dir := "res://addons/bonehead_labs_splash/art/"
	var missing: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".svg") and not (load(dir + file) is Texture2D):
			missing.append(file)
	_check("every mascot and note SVG is imported %s" % [missing], missing.is_empty())
	for font in ["fraunces_wordmark", "fraunces_display", "spline_sans_mono"]:
		_check("font %s loads" % font,
			load("res://addons/bonehead_labs_splash/fonts/%s.tres" % font) is Font)


## The pure placement rule, in the cases a desktop actually produces.
func _check_card_rect() -> void:
	_suite("where the card goes")
	var boot := Rect2i(640, 336, 1280, 720)
	_check("the first frame, before the overlay applies: the whole window",
		BootSplash.card_rect(boot, boot.position, Vector2(1280, 720)) == Rect2(0, 0, 1280, 720))
	_check("overlay on the same monitor: exactly where the boot image was",
		BootSplash.card_rect(boot, Vector2i(0, 0), Vector2(2560, 1392)) == Rect2(640, 336, 1280, 720))
	_check("overlay on the other monitor: centred",
		BootSplash.card_rect(boot, Vector2i(2560, 0), Vector2(1920, 1040)) == Rect2(320, 160, 1280, 720))
	_check("play area smaller than the card: filled",
		BootSplash.card_rect(boot, Vector2i(1360, 600), Vector2(1180, 760)) == Rect2(0, 0, 1180, 760))
	_check("no boot rect (headless): the whole view",
		BootSplash.card_rect(Rect2i(), Vector2i.ZERO, Vector2(64, 64)) == Rect2(0, 0, 64, 64))


## A quit while the splash plays, before main.tscn has loaded the save, must not write one.
func _check_quit_before_load() -> void:
	_suite("a quit during the splash")
	if not SaveManager._loaded_data.is_empty():
		_check("precondition: nothing has loaded the save yet", false)
		return
	SaveManager.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check("no save is written before the game has read one",
		not FileAccess.file_exists(SaveManager.save_path()))


func _check_headless_pass_through() -> void:
	_suite("headless")
	var adapter := _adapter(SPLASH, false)
	get_tree().change_scene_to_node(adapter)
	var frames := 0
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != SPLASH:
		await get_tree().process_frame
		frames += 1
		if Time.get_ticks_msec() > deadline:
			break
	_check("a headless run goes straight through (%d frames)" % frames, frames <= 4)


func _check_skip() -> void:
	_suite("skip")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	var adapter := _adapter("", true)
	get_tree().change_scene_to_node(adapter)
	await _until(func() -> bool: return get_tree().current_scene == adapter)
	var splash: SplashScript = adapter.get_splash()
	_check("the splash is running", splash != null)
	if splash == null:
		return
	_finished_count = 0
	splash.finished.connect(func() -> void:
		_finished_count += 1
		_finished_state = splash.get_state())
	await _until(func() -> bool: return float(splash.get_state()["time"]) > 0.6)
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	get_viewport().push_input(press)
	_check("a key skips it", bool(splash.get_state()["skipped"]))
	await _until(func() -> bool: return _finished_count > 0)
	var at := float(_finished_state.get("time", 99.0))
	_check("and it closes within a second of the key (finished at %.2f s)" % at, at < 1.7)
	_check("finished is emitted once", _finished_count == 1)


func _check_boot_flow() -> void:
	_suite("the boot, into main.tscn")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	var adapter := _adapter(MAIN, true)
	if _shots:
		adapter.boot_rect = _engine_boot_rect()
	get_tree().change_scene_to_node(adapter)
	await _until(func() -> bool: return get_tree().current_scene == adapter)
	_check("the adapter is the current scene, in its group",
		get_tree().current_scene == adapter and adapter.is_in_group(BootSplash.GROUP))
	var splash: SplashScript = adapter.get_splash()
	_check("it runs the addon splash", splash != null)
	if splash == null:
		return
	var state: Dictionary = splash.get_state()
	_check("next scene is main.tscn", splash.next_scene == MAIN)
	_check("cues on the SFX bus, which exists",
		state["audio_bus"] == &"SFX" and AudioServer.get_bus_index(&"SFX") >= 0)
	_check("full flashing budget at Focus Normal", not splash.reduce_flashing)
	_check("no shaders and no viewports (GL Compatibility)",
		int(state["materials"]) == 0 and int(state["viewports"]) == 0)
	var card: Control = adapter.get_node("Card")
	_check("the card clips the glows", card.clip_contents)
	_check("the splash fills the card",
		splash.get_global_rect().is_equal_approx(card.get_global_rect()))
	_check("the card is inside the window",
		Rect2(Vector2.ZERO, adapter.get_viewport_rect().size).encloses(adapter.get_card_rect()))
	_check("no pixel snapping while it plays", not adapter.get_viewport().snap_2d_transforms_to_pixel)
	_check("nothing in the adapter takes the mouse",
		adapter.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	_finished_count = 0
	splash.finished.connect(func() -> void:
		_finished_count += 1
		_finished_state = splash.get_state())
	var next_shot := 0
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while is_instance_valid(adapter) and get_tree().current_scene == adapter \
			and Time.get_ticks_msec() < deadline:
		if _shots and is_instance_valid(splash) and next_shot < SHOT_TIMES.size() \
				and float(splash.get_state()["time"]) >= SHOT_TIMES[next_shot]:
			_shoot(adapter, next_shot)
			next_shot += 1
		await get_tree().process_frame
	await _until(func() -> bool:
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == MAIN)

	var scene := get_tree().current_scene
	_check("it hands off to main.tscn", scene != null and scene.scene_file_path == MAIN)
	_check("finished is emitted once, after the whole splash (%.2f s of %.2f)" % [
		float(_finished_state.get("time", 0.0)), float(_finished_state.get("duration", 0.0))],
		_finished_count == 1 and not bool(_finished_state.get("skipped", true))
		and float(_finished_state.get("time", 0.0)) >= float(_finished_state.get("duration", 99.0)) - 0.001)
	await _idle(10)
	_check("the game booted: he is on the desk",
		get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) != null)
	_check("the adapter is gone", not is_instance_valid(adapter))
	_check("the game gets its pixel snapping back",
		get_viewport().snap_2d_transforms_to_pixel
		== bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")))
	SaveManager.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check("once main has loaded it, a quit saves as before",
		FileAccess.file_exists(SaveManager.save_path()))
	if _shots:
		print("  shots: %s" % ProjectSettings.globalize_path(SHOTS_DIR))


# --- helpers --------------------------------------------------------------------------

func _adapter(next: String, play: bool) -> BootSplash:
	var adapter: BootSplash = load(ADAPTER).instantiate()
	adapter.next_scene = next
	adapter.play_in_headless = play
	return adapter


## Where the engine puts a 1280x720 window centred on this screen, as it does at boot.
func _engine_boot_rect() -> Rect2i:
	var size := Vector2i(1280, 720)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Rect2i(usable.position + (usable.size - size) / 2, size)


func _shoot(adapter: BootSplash, index: int) -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var image := get_viewport().get_texture().get_image()
	var flat := Image.create_empty(image.get_width(), image.get_height(), false, image.get_format())
	flat.fill(DESKTOP)
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	var card: Rect2 = adapter.get_card_rect()
	var around := Rect2i(card.grow(64.0)).intersection(Rect2i(Vector2i.ZERO, flat.get_size()))
	var crop := flat.get_region(around)
	crop.save_png("%s/splash_%d_%04dms.png" % [SHOTS_DIR, index, roundi(SHOT_TIMES[index] * 1000.0)])
	if index == 0:
		# The whole window once, scaled down: what the transparent overlay looks like around it.
		var small := flat.duplicate() as Image
		small.resize(maxi(flat.get_width() / 3, 1), maxi(flat.get_height() / 3, 1), Image.INTERPOLATE_BILINEAR)
		small.save_png("%s/window_third.png" % SHOTS_DIR)


func _until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _idle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _suite(title: String) -> void:
	print("")
	print("-- %s" % title)


func _check(what: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)
