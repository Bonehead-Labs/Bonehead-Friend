extends Control

## The game's `run/main_scene`: the Bonehead Labs studio splash, then `main.tscn`.
##
## The splash is the shared addon `addons/bonehead_labs_splash/`, the same intro every Bonehead
## Labs game plays, used unchanged (its README has the contract). This adapter only configures it
## and fits it to a desktop overlay:
##
## - **A card, not the window.** The window is transparent, borderless and on top of the player's
##   work, and in the default mode OverlayManager stretches it over the whole monitor a frame
##   after boot. Filling that with paper would blank the desktop for four seconds, so the splash
##   plays on an opaque card exactly where the engine drew its boot image (the window's own first
##   rect, 1280x720 centred): the boot frame and the splash meet without a cut, and the rest of
##   the desktop stays visible around it. A card that is no longer inside the window (the overlay
##   went to another monitor) is centred instead, and a window too small for one (the play area)
##   is filled. The card clips, because the splash's glows reach past its own rect.
## - **It closes, it never fades.** The splash ends by closing its paper to ink and is then cut;
##   nothing half-transparent ever sits over the desktop (CLAUDE.md, D63).
## - Its cues play on the SFX bus at the game's volumes, and not at all at Focus Mode Off, which
##   is how AudioManager treats every other sound. Focus Mode Subtle or Off asks for its gentler
##   closing fade (the game has no separate reduce-flashing setting).
## - It plays at the active frame rate (the overlay caps an idle desk at `fps_idle`, 30), and
##   without the project's 2D pixel snapping, which would step its sub-pixel motion. Both are
##   put back when it hands off.
## - A headless run (the boot smoke test, every tool) and a perf-stage measurement go straight to
##   `main.tscn`, as does the addon's own `-- --skip-splash`. Any key or click skips it.

const SPLASH_SCENE: PackedScene = preload("res://addons/bonehead_labs_splash/bonehead_labs_splash.tscn")
const SplashScript := preload("res://addons/bonehead_labs_splash/bonehead_labs_splash.gd")

## Playtest and the suites recognise the splash by this group.
const GROUP := &"boot_splash"

## Where the splash hands off once it has played out.
@export_file("*.tscn") var next_scene: String = "res://main.tscn"

## Where the engine drew its boot image, in screen pixels: the window's rect when this scene
## starts, before OverlayManager's deferred apply moves it. A suite may set it before `_ready`.
var boot_rect := Rect2i()
## Play under `--headless` too. Only splash_check sets it.
var play_in_headless := false

var _splash: SplashScript = null
var _card: Control = null
var _raised_fps := false
var _snap_restore := false


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if (DisplayServer.get_name() == "headless" and not play_in_headless) or _perf_stage():
		get_tree().change_scene_to_file.call_deferred(next_scene)
		return

	if boot_rect.size.x <= 0 or boot_rect.size.y <= 0:
		boot_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())

	_card = Control.new()
	_card.name = "Card"
	_card.clip_contents = true
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	_splash = SPLASH_SCENE.instantiate() as SplashScript
	if _splash == null:
		push_error("BootSplash: the splash addon scene did not load")
		get_tree().change_scene_to_file.call_deferred(next_scene)
		return
	_splash.next_scene = next_scene
	_splash.skippable = true
	_splash.reduce_flashing = Settings.focus_intensity <= Settings.Intensity.SUBTLE
	_splash.audio_bus = StringName(AudioManager.SFX_BUS)
	if Settings.focus_intensity == Settings.Intensity.OFF:
		_splash.volume_db = -80.0
	_card.add_child(_splash)  # configured first: it starts in its own _ready

	# The project snaps every 2D transform to whole pixels for its pixel art; the splash is drawn
	# smooth and moves by fractions of one.
	_snap_restore = get_viewport().snap_2d_transforms_to_pixel
	get_viewport().snap_2d_transforms_to_pixel = false

	_fit_card()
	get_viewport().size_changed.connect(_fit_card)
	OverlayManager.window_rect_changed.connect(func(_rect: Rect2i) -> void: _fit_card())


func _process(_delta: float) -> void:
	# Raised on every frame rather than once, because OverlayManager writes its idle cap when it
	# applies the window, a frame after this scene starts. Only ever raised, never set: a headless
	# run is uncapped (0) and Low Power is the player's choice.
	if _splash == null or Settings.low_power_mode:
		return
	if Engine.max_fps > 0 and Engine.max_fps < Settings.fps_active:
		Engine.max_fps = Settings.fps_active
		_raised_fps = true


func _exit_tree() -> void:
	if _snap_restore:
		get_viewport().snap_2d_transforms_to_pixel = true
	if _raised_fps:
		OverlayManager.apply_performance_settings()


## The addon splash this adapter runs (suites and tools).
func get_splash() -> SplashScript:
	return _splash if is_instance_valid(_splash) else null


## The card, in this control's (the window's) pixels.
func get_card_rect() -> Rect2:
	return Rect2(_card.position, _card.size) if is_instance_valid(_card) else Rect2()


func _fit_card() -> void:
	if not is_instance_valid(_card):
		return
	var rect := card_rect(boot_rect, DisplayServer.window_get_position(), get_viewport_rect().size)
	# A child of a plain Control is never laid out: own both halves of its rect (CLAUDE.md).
	_card.position = rect.position
	_card.size = rect.size


## Where the card goes in a window at `window_position` showing `view` pixels: the boot image's
## own screen rect if it is still inside the window, else that size centred, else the window.
static func card_rect(boot: Rect2i, window_position: Vector2i, view: Vector2) -> Rect2:
	var whole := Rect2(Vector2.ZERO, view)
	if boot.size.x <= 0 or boot.size.y <= 0:
		return whole
	var card := Vector2(boot.size)
	var at_boot := Rect2(Vector2(boot.position - window_position), card)
	if whole.encloses(at_boot):
		return at_boot
	if view.x >= card.x and view.y >= card.y:
		return Rect2(((view - card) * 0.5).floor(), card)
	return whole


static func _perf_stage() -> bool:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--perf-stage="):
			return true
	return false
