extends CaptureWindow

## The supernatural powers (D72) as the player sees them: the two shop drawers they are sold in,
## then every one of the seven on the desk, caught in the middle of what it does.
##
##   Godot --fixed-fps 60 --path <project> res://tools/power_shots.tscn   (NOT --headless: it draws)
##   ... res://tools/power_shots.tscn -- --only=smite,rainbow
##
## Files land in `user://power_shots/`. Its own save slot and settings file, through
## `CaptureWindow._use_capture_slot()`, like every capture tool.
##
## A VFX is unfinished until a capture shows it (CLAUDE.md), and a spell is mostly VFX. The
## spells are worked by calling the same entry points their input handlers call — `fire`, the
## aim, `_released`, `_right_pressed` — because the OS cursor cannot be moved by a synthetic
## event and `CursorPowerBase` reads the click's position off the viewport. The OS cursor is
## not in a screenshot either, so the power's own cursor is drawn at the aim point, where the
## player would see it.

const SIZE := Vector2i(1180, 760)
const OUT := "user://power_shots"
const POWERS: Array[StringName] = [&"telekinesis", &"time_stop", &"meteor_shower", &"smite",
	&"blessing", &"levitation", &"rainbow"]

var _main: Node
var _had := {}
var _buddy: Buddy
var _spawner: ItemSpawner
var _proxy: Sprite2D
var _only: PackedStringArray = []

func _ready() -> void:
	_use_capture_slot()
	_had = {"hud": Settings.hud_pinned, "tabs": Settings.tabs_pinned, "scale": Settings.ui_scale,
		"focus": Settings.focus_intensity}
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--only="):
			_only = String(arg).trim_prefix("--only=").split(",", false)
	DirAccess.make_dir_recursive_absolute(OUT)
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.ui_scale = 0
	Settings.hud_pinned = true
	Settings.tabs_pinned = true
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "supernatural powers")
	await _idle(30)
	_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	_spawner = get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	Economy.grant(Economy.BONES, 1.0e7)
	Economy.grant(Economy.HEARTS, 1.0e7)
	for id in POWERS:
		_own(id)
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_proxy = Sprite2D.new()
	_proxy.visible = false
	layer.add_child(_proxy)

	if _want(&"shop"):
		await _shop()
	if _want(&"telekinesis"):
		await _telekinesis()
	if _want(&"time_stop"):
		await _time_stop()
	if _want(&"meteor_shower"):
		await _meteors()
	if _want(&"smite"):
		await _smite()
	if _want(&"blessing"):
		await _blessing()
	if _want(&"levitation"):
		await _levitation()
	if _want(&"rainbow"):
		await _rainbow()

	_clear_slot()
	print("power_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	Settings.hud_pinned = _had["hud"]
	Settings.tabs_pinned = _had["tabs"]
	Settings.ui_scale = _had["scale"]
	Settings.focus_intensity = _had["focus"]
	Settings.save_settings()
	get_tree().quit()

func _want(what: StringName) -> bool:
	return _only.is_empty() or _only.has(String(what))

func _own(id: StringName) -> void:
	var item := ItemDB.get_item(id)
	if item == null or Progression.is_unlocked(id):
		return
	for req in item.requires:
		_own(req)
	Progression.purchase_item(id)

# --- staging ---------------------------------------------------------------

## The floor he stands on, which is the bottom of the play area.
func _floor() -> float:
	return get_viewport().get_visible_rect().end.y

## Him, put down at `x` and left to settle.
func _stand(x: float) -> void:
	_buddy.freeze = false
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	_buddy.rotation = 0.0
	_buddy.global_position = Vector2(x, _floor() - 70.0)
	var idle := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	if idle:
		idle.notice_player()
	await _physics(40)

func _equip(id: StringName) -> SpellPower:
	if _spawner.active_power() != id:
		EventBus.spawn_requested.emit(id, Vector2.ZERO)
	await _idle(2)
	var power := _spawner.get_power(id) as SpellPower
	_proxy.texture = power.cursor_texture if power else null
	return power

func _holster() -> void:
	_spawner.holster_power()
	_proxy.visible = false
	await _idle(2)

## Where the player's cursor is: the spell's aim, and the picture of it in the capture.
func _aim(power: SpellPower, at: Vector2) -> void:
	power._aim = at
	power._moved(at)
	_proxy.position = at
	_proxy.visible = true

func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("  %s (staged; headless draws nothing)" % name)
		return
	await RenderingServer.frame_post_draw
	_grab().save_png("%s/%s.png" % [OUT, name])
	print("  %s" % name)

func _him() -> Vector2:
	return _buddy.get_interaction_rect().get_center()

# --- the shop --------------------------------------------------------------

func _shop() -> void:
	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	panels.call("show_panel", &"shop")
	shop.call("show_side", ItemData.SIDE_HARM)
	shop.call("show_category", ItemData.CATEGORY_CURSOR_POWER)
	shop.call("select", &"smite")
	await _idle(40)
	await _snap("01-shop-cursor")
	shop.call("show_side", ItemData.SIDE_KIND)
	shop.call("show_category", ItemData.CATEGORY_FRIENDLY)
	shop.call("select", &"rainbow")
	await _idle(40)
	await _snap("02-shop-care")
	panels.call("close")
	await _idle(20)

# --- the seven -------------------------------------------------------------

func _telekinesis() -> void:
	await _stand(float(SIZE.x) * 0.5 + 200.0)
	var power := await _equip(&"telekinesis") as TelekinesisPower
	var from := _him()
	var hand := Vector2(float(SIZE.x) * 0.5 - 200.0, 260.0)
	_aim(power, hand)
	power.fire(hand)
	await _physics(10)
	await _snap("03-telekinesis-seize")
	for i in 40:
		_aim(power, hand + Vector2(sin(float(i) * 0.12) * 90.0, cos(float(i) * 0.09) * 30.0))
		await get_tree().physics_frame
	await _snap("04-telekinesis-carry")
	power._right_pressed(hand)
	await _physics(3)
	await _snap("05-telekinesis-crush")
	for i in 24:
		_aim(power, power._aim + Vector2(38.0, 0.0))
		await get_tree().physics_frame
	power._held = false
	power._released(power._aim)
	await _physics(6)
	await _snap("06-telekinesis-fling")
	await _physics(60)
	await _holster()
	print("    telekinesis: seized from %s" % from)

func _time_stop() -> void:
	await _stand(float(SIZE.x) * 0.5)
	var power := await _equip(&"time_stop") as TimeStopPower
	_buddy.apply_central_impulse(Vector2(120.0, -1000.0) * _buddy.mass)
	await _physics(12)
	var him := _him()
	_aim(power, him)
	power.fire(him)
	await _physics(4)
	for offset in [Vector2(-28, -34), Vector2(-34, 4), Vector2(24, -20), Vector2(-10, 34),
			Vector2(30, 22)]:
		var at: Vector2 = _him() + offset
		_aim(power, at)
		power._next_blow_msec = 0
		power.fire(at)
		await _physics(8)
	await _physics(20)
	await _snap("07-time-stop")
	var away := _him() + Vector2(260.0, -60.0)
	_aim(power, away)
	power.fire(away)
	await _physics(4)
	await _snap("08-time-resume")
	await _physics(90)
	await _holster()

func _meteors() -> void:
	await _stand(float(SIZE.x) * 0.5)
	var power := await _equip(&"meteor_shower") as MeteorShowerPower
	var at := _him()
	_aim(power, at)
	power.fire(at)
	await _physics(34)
	await _snap("09-meteors")
	await _physics(17)
	await _snap("10-meteors-later")
	power._held = false
	power._released(at)
	await _physics(80)
	await _holster()

func _smite() -> void:
	await _stand(float(SIZE.x) * 0.5)
	var power := await _equip(&"smite") as SmitePower
	var at := _him() + Vector2(0.0, -120.0)
	_aim(power, at)
	power.fire(at)
	await _physics(26)
	await _snap("11-smite-charge")
	while power._state == SmitePower.CHARGING:
		await get_tree().physics_frame
	await _physics(2)
	await _snap("12-smite-strike")
	await _physics(8)
	await _snap("13-smite-after")
	await _physics(60)
	await _holster()

func _blessing() -> void:
	await _stand(float(SIZE.x) * 0.5)
	var power := await _equip(&"blessing") as BlessingPower
	var at := _him()
	_aim(power, at)
	power.fire(at)
	await _physics(70)
	_aim(power, at + Vector2(90.0, -40.0))
	await _snap("14-blessing")
	await _holster()

func _levitation() -> void:
	await _stand(float(SIZE.x) * 0.5)
	var power := await _equip(&"levitation") as LevitationPower
	var at := _him()
	_aim(power, at)
	power.fire(at)
	await _physics(150)
	await _snap("15-levitation")
	power._held = false
	power._released(at)
	await _physics(30)
	await _snap("16-levitation-down")
	await _physics(120)
	await _holster()

func _rainbow() -> void:
	await _stand(float(SIZE.x) * 0.5 - 300.0)
	var power := await _equip(&"rainbow") as RainbowPower
	var at := _him()
	_aim(power, at)
	power.fire(at)
	var target := at + Vector2(520.0, -120.0)
	for i in 20:
		_aim(power, at.lerp(target, float(i + 1) / 20.0))
		await get_tree().physics_frame
	await _snap("17-rainbow-draw")
	power._held = false
	power._released(target)
	await _physics(int(power._ride_seconds * 60.0 * 0.45))
	await _snap("18-rainbow-ride")
	while power.is_riding():
		await get_tree().physics_frame
	await _physics(4)
	await _snap("19-rainbow-landed")
	await _physics(60)
	await _holster()
