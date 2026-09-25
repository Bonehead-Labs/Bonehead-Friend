extends CaptureWindow

## Every gun (D56, D71) as the player sees it: the Guns drawer and its how-to strip, the whole
## rack laid on the desk beside him for scale, and each of D71's verbs caught mid-use — the
## minigun's stream, a grenade in the air and going off, the harpoon's line reeling him in, a
## flare burning in him, foam darts stuck to him, the ray gun's beam.
##
##   Godot --path <project> res://tools/gun_shots.tscn        (NOT --headless: it draws)
##
## Files land in `user://gun_shots/`. Its own save slot and settings file, through
## `CaptureWindow._use_capture_slot()`, like every capture tool.
##
## A gun is held the way `gun_check` holds one: the real grab, then its handle pinned where a
## hand would be on every physics frame, because the OS cursor it would otherwise chase cannot
## be moved from here.

const SIZE := Vector2i(1180, 760)
const OUT := "user://gun_shots"
const RACK: Array[StringName] = [&"slingshot", &"pistol", &"revolver", &"shotgun", &"flare_gun",
	&"smg", &"minigun", &"pump_shotgun", &"tommy_gun", &"hunting_rifle", &"grenade_launcher",
	&"harpoon_gun", &"blunderbuss", &"ray_gun", &"water_pistol", &"foam_dart_blaster",
	&"bubble_blaster"]

var _main: Node
var _had := {}
var _floor_y := 0.0
var _buddy: Buddy
## Guns in a hand, and where: re-pinned every physics frame.
var _hands := {}

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
	get_tree().physics_frame.connect(_pin_hands)

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "guns")
	await _idle(20)
	Economy.grant(Economy.BONES, 5.0e6)
	Economy.grant(Economy.HEARTS, 1.0e6)
	for id in RACK:
		_buy(id)
	_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	_floor_y = float(SIZE.y) - 60.0

	# `-- --stages=rack,darts` runs some of them, while one is being worked on.
	var stages := PackedStringArray(["shop", "rack", "minigun", "grenade", "harpoon", "flare",
		"darts", "ray"])
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--stages="):
			stages = String(arg).trim_prefix("--stages=").split(",", false)
	for stage in stages:
		await Callable(self, "_%s" % stage).call()

	get_tree().physics_frame.disconnect(_pin_hands)
	_clear_slot()
	print("gun_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	Settings.hud_pinned = _had["hud"]
	Settings.tabs_pinned = _had["tabs"]
	Settings.ui_scale = _had["scale"]
	Settings.focus_intensity = _had["focus"]
	Settings.save_settings()
	get_tree().quit()

func _buy(id: StringName) -> void:
	var item := ItemDB.get_item(id)
	if item == null:
		return
	for need in item.requires:
		_buy(need)
	Progression.purchase_item(id)

# --- the stages --------------------------------------------------------------------------

func _shop() -> void:
	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	panels.call("show_panel", &"shop")
	shop.call("show_side", ItemData.SIDE_HARM)
	shop.call("show_category", ItemData.CATEGORY_GUN)
	shop.call("select", &"minigun")
	await _shot("01-shop-guns-minigun")
	shop.call("select", &"harpoon_gun")
	await _shot("02-shop-guns-harpoon")
	shop.call("show_side", ItemData.SIDE_KIND)
	shop.call("show_category", ItemData.CATEGORY_FRIENDLY)
	shop.call("select", &"foam_dart_blaster")
	await _shot("03-shop-care-darts")
	panels.call("close")
	await _idle(10)

## Every gun on the desk beside him, in the drawer's order and in two sets — the desk holds ten
## things at once — each laid level on the floor and held still for the picture.
func _rack() -> void:
	var sets := [RACK.slice(0, 9), RACK.slice(9)]
	for i in sets.size():
		var x := 90.0
		for id in sets[i]:
			var body := _spawn(id, Vector2(x, _floor_y - 40.0)) as RigidBody2D
			if body:
				body.global_rotation = 0.0
				body.freeze = true
			x += 110.0
			# The long ones take a little more of the floor.
			if id in [&"minigun", &"blunderbuss", &"hunting_rifle", &"harpoon_gun"]:
				x += 24.0
		_park_buddy(Vector2(float(SIZE.x) - 70.0, _floor_y - 120.0))
		await _physics(30)
		await _shot("04-desk-rack-%d" % (i + 1))
		await _clear_desk()

func _minigun() -> void:
	_park_buddy(Vector2(float(SIZE.x) * 0.5 + 220.0, _floor_y - 120.0))
	var gun := await _hold(&"minigun", Vector2(float(SIZE.x) * 0.5 - 220.0, _floor_y - 150.0))
	gun.pull_trigger()
	await _physics(60)
	await _shot("05-minigun-stream", 8)
	gun.release_trigger()
	await _physics(10)
	await _clear_desk()

func _grenade() -> void:
	_park_buddy(Vector2(float(SIZE.x) * 0.5 + 260.0, _floor_y - 120.0))
	var gun := await _hold(&"grenade_launcher", Vector2(float(SIZE.x) * 0.5 - 260.0, _floor_y - 140.0))
	gun._next_shot_msec = 0
	gun.fire()
	await _physics(16)
	await _shot("06-grenade-in-the-air", 0)
	for i in 60:
		await _physics(1)
		if (gun as GrenadeLauncher).grenades_in_flight() == 0:
			break
	await _shot("07-grenade-goes-off", 2)
	await _clear_desk()

func _harpoon() -> void:
	_park_buddy(Vector2(float(SIZE.x) * 0.5 + 200.0, _floor_y - 120.0))
	var gun := await _hold(&"harpoon_gun", Vector2(float(SIZE.x) * 0.5 - 260.0, _floor_y - 170.0)) as HarpoonGun
	gun.pull_trigger()
	gun.release_trigger()
	for i in 40:
		await _physics(1)
		if gun.harpoon_in_him():
			break
	await _physics(20)
	await _shot("08-harpoon-in-him", 0)
	gun.pull_trigger()
	await _physics(24)
	await _shot("09-harpoon-reeling", 0)
	gun.release_trigger()
	await _clear_desk()

func _flare() -> void:
	_park_buddy(Vector2(float(SIZE.x) * 0.5 + 160.0, _floor_y - 120.0))
	var gun := await _hold(&"flare_gun", Vector2(float(SIZE.x) * 0.5 - 180.0, _floor_y - 150.0))
	gun._next_shot_msec = 0
	gun.fire()
	# Stuck, then a tick and a quarter on, between two flashes, once the strike's number has gone.
	await _physics(130)
	await _shot("10-flare-burning", 0)
	await _clear_desk()

func _darts() -> void:
	_park_buddy(Vector2(float(SIZE.x) * 0.5 + 160.0, _floor_y - 120.0))
	var gun := await _hold(&"foam_dart_blaster", Vector2(float(SIZE.x) * 0.5 - 180.0, _floor_y - 150.0))
	for i in 4:
		gun._next_shot_msec = 0
		gun.fire()
		await _physics(18)
	# Long enough for the payout numbers over them to have floated off.
	await _physics(80)
	await _shot("11-darts-on-him", 2)
	await _clear_desk()

func _ray() -> void:
	_park_buddy(Vector2(float(SIZE.x) * 0.5 + 200.0, _floor_y - 120.0))
	var gun := await _hold(&"ray_gun", Vector2(float(SIZE.x) * 0.5 - 200.0, _floor_y - 150.0))
	gun.pull_trigger()
	await _physics(70)
	await _shot("12-ray-beam-hot", 0)
	gun.release_trigger()
	await _clear_desk()

# --- staging -----------------------------------------------------------------------------

func _spawn(id: StringName, at: Vector2) -> Node:
	EventBus.spawn_requested.emit(id, at)
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		if (node as BaseDraggable).item_id == id and not _hands.has(node):
			return node
	return null

## Picked up at `hand` and held there, laid on him and settled.
func _hold(id: StringName, hand: Vector2) -> HeldGun:
	var gun := _spawn(id, hand) as HeldGun
	await _physics(2)
	gun.global_position = hand
	gun.linear_velocity = Vector2.ZERO
	gun.angular_velocity = 0.0
	gun.follow_lerp = 0.0
	gun._start_drag()
	# The joint `_start_drag` made was anchored where the OS cursor is; made again with the
	# handle already at the hand, as a click on the grip makes it (gun_check's `_grab`).
	if gun.mouse_joint:
		gun.mouse_joint.free()
	gun.handle.global_position = hand
	var joint := PinJoint2D.new()
	joint.position = gun.grip_offset
	joint.softness = gun.joint_softness
	joint.bias = gun.joint_bias
	gun.add_child(joint)
	joint.node_a = gun.handle.get_path()
	joint.node_b = gun.get_path()
	gun.mouse_joint = joint
	_hands[gun] = hand
	await _physics(50)
	return gun

func _pin_hands() -> void:
	for gun in _hands.keys():
		if not is_instance_valid(gun):
			_hands.erase(gun)
			continue
		if (gun as HeldGun).dragging:
			(gun as HeldGun).handle.global_position = _hands[gun]

func _park_buddy(at: Vector2) -> void:
	if _buddy == null:
		return
	var idle := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	if idle:
		idle._disturb()
	_buddy.health.reset_meter()
	_buddy.global_position = at
	_buddy.global_rotation = 0.0
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0

func _clear_desk() -> void:
	for gun in _hands.keys():
		if is_instance_valid(gun) and (gun as HeldGun).dragging:
			(gun as HeldGun)._end_drag()
	_hands.clear()
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if spawner:
		spawner.clear_desk()
	await _physics(30)

func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

## Headless draws nothing, so there a shot is only the staging — which is still worth running,
## because it proves the staging itself works before anyone opens a window for it. `settle` is
## how many drawn frames to wait: a stage that is caught mid-flight wants none.
func _shot(name: String, settle: int = 45) -> void:
	await _idle(settle)
	if DisplayServer.get_name() == "headless":
		print("  %s (staged; headless draws nothing)" % name)
		return
	await RenderingServer.frame_post_draw
	_grab().save_png("%s/%s.png" % [OUT, name])
	print("  %s" % name)
