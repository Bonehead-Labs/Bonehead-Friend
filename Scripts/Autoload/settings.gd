extends Node

## Machine-local preferences at user://settings.cfg.
##
## Deliberately separate from the save file and NOT synced to Steam Cloud — it holds
## monitor ids and window rects, which are meaningless (or actively harmful) on another
## machine. See docs/architecture.md.
##
## Window/corner values are stored as plain ints rather than WindowLayout enums: this is
## an autoload, and an autoload that fails to parse because a global class name has not
## been cached yet takes the whole game down with it.

const CONFIG_PATH := "user://settings.cfg"

## Focus Mode: how loud the game is allowed to be while you work.
enum Intensity { OFF, SUBTLE, NORMAL, CHAOS }

# --- overlay window ---
var overlay_enabled: bool = true
## 0 = fullscreen overlay (taskbar is the floor), 1 = small tucked-away play area.
## See WindowLayout.Mode.
var window_mode: int = 0
## 0 = free, 1..4 = top-left, top-right, bottom-left, bottom-right. See WindowLayout.Corner.
var play_area_corner: int = 4
## 480x360 was the M1 spike's placeholder and is too small to play in: a 4x-scaled item
## sprite is two thirds of its height. Sized so the buddy and a couple of toys have room
## without the window dominating the desktop; F9/F10 cycle it at runtime until the
## settings UI exists (M4).
var play_area_size: Vector2i = Vector2i(960, 640)
## Last known good rect, revalidated on boot in case the monitor changed while closed.
var play_area_rect: Rect2i = Rect2i()

# --- display ---
var monitor_id: int = 0
var cover_taskbar: bool = false

# --- performance ---
var low_power_mode: bool = false
var fps_idle: int = 30
var fps_active: int = 60
var fps_low_power: int = 20
var hibernate_when_occluded: bool = true

# --- presentation ---
var focus_intensity: Intensity = Intensity.NORMAL
var streamer_mode: bool = false
var streamer_bg_color: Color = Color(0, 1, 0)  ## Chroma key green

# --- audio ---
var volume_master: float = 0.6
var volume_sfx: float = 1.0
var volume_music: float = 0.8
var mute_when_unfocused: bool = true

# --- meta ---
var first_run: bool = true

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		# No file yet (or unreadable): keep defaults and write them on the first save.
		return

	overlay_enabled = cfg.get_value("overlay", "overlay_enabled", overlay_enabled)
	window_mode = cfg.get_value("overlay", "window_mode", window_mode)
	play_area_corner = cfg.get_value("overlay", "play_area_corner", play_area_corner)
	play_area_size = cfg.get_value("overlay", "play_area_size", play_area_size)
	play_area_rect = cfg.get_value("overlay", "play_area_rect", play_area_rect)

	monitor_id = cfg.get_value("display", "monitor_id", monitor_id)
	cover_taskbar = cfg.get_value("display", "cover_taskbar", cover_taskbar)

	low_power_mode = cfg.get_value("performance", "low_power_mode", low_power_mode)
	fps_idle = cfg.get_value("performance", "fps_idle", fps_idle)
	fps_active = cfg.get_value("performance", "fps_active", fps_active)
	fps_low_power = cfg.get_value("performance", "fps_low_power", fps_low_power)
	hibernate_when_occluded = cfg.get_value("performance", "hibernate_when_occluded", hibernate_when_occluded)

	focus_intensity = cfg.get_value("presentation", "focus_intensity", focus_intensity)
	streamer_mode = cfg.get_value("presentation", "streamer_mode", streamer_mode)
	streamer_bg_color = cfg.get_value("presentation", "streamer_bg_color", streamer_bg_color)

	volume_master = cfg.get_value("audio", "volume_master", volume_master)
	volume_sfx = cfg.get_value("audio", "volume_sfx", volume_sfx)
	volume_music = cfg.get_value("audio", "volume_music", volume_music)
	mute_when_unfocused = cfg.get_value("audio", "mute_when_unfocused", mute_when_unfocused)

	first_run = cfg.get_value("meta", "first_run", first_run)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("overlay", "overlay_enabled", overlay_enabled)
	cfg.set_value("overlay", "window_mode", window_mode)
	cfg.set_value("overlay", "play_area_corner", play_area_corner)
	cfg.set_value("overlay", "play_area_size", play_area_size)
	cfg.set_value("overlay", "play_area_rect", play_area_rect)

	cfg.set_value("display", "monitor_id", monitor_id)
	cfg.set_value("display", "cover_taskbar", cover_taskbar)

	cfg.set_value("performance", "low_power_mode", low_power_mode)
	cfg.set_value("performance", "fps_idle", fps_idle)
	cfg.set_value("performance", "fps_active", fps_active)
	cfg.set_value("performance", "fps_low_power", fps_low_power)
	cfg.set_value("performance", "hibernate_when_occluded", hibernate_when_occluded)

	cfg.set_value("presentation", "focus_intensity", focus_intensity)
	cfg.set_value("presentation", "streamer_mode", streamer_mode)
	cfg.set_value("presentation", "streamer_bg_color", streamer_bg_color)

	cfg.set_value("audio", "volume_master", volume_master)
	cfg.set_value("audio", "volume_sfx", volume_sfx)
	cfg.set_value("audio", "volume_music", volume_music)
	cfg.set_value("audio", "mute_when_unfocused", mute_when_unfocused)

	cfg.set_value("meta", "first_run", first_run)

	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_error("Settings: failed to write %s (error %d)" % [CONFIG_PATH, err])

func set_focus_intensity(level: Intensity) -> void:
	if focus_intensity == level:
		return
	focus_intensity = level
	save_settings()
	EventBus.focus_mode_changed.emit(int(level))

## Scales particle counts, flash strength and damage-number frequency.
## Off still earns money — it just stops shouting about it.
func intensity_scale() -> float:
	match focus_intensity:
		Intensity.OFF: return 0.0
		Intensity.SUBTLE: return 0.4
		Intensity.NORMAL: return 1.0
		Intensity.CHAOS: return 1.6
	return 1.0
