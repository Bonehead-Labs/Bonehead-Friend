extends Node

## A scripted swing into him, for feel that can be compared before and after a physics change
## (docs/decisions.md D61).
##
##   Godot --headless --path <project> res://tools/swing_rig.tscn [-- --only id,id] [--speed 1200]
##
## For each weapon: he stands on a floor; the weapon is held by its grip, trailing level behind
## the hand with its centre of mass straight back from the grip — the pose any weapon takes
## once the hand is moving — and the hand sweeps straight across him at a fixed speed, through
## his chest, the way a player's cursor goes. Not hung first: hanging from a hand at chest
## height puts a greatsword's tip through the floor. What it reports is what "a plank or a
## rocket" would show up as:
##
##   lever    grip to centre of mass, world px — how far out the weight is
##   inertia  the body's moment of inertia, from its shapes and mass
##   hits / max / sum   contact impulses he received from it, as HitInfo.raw_impulse
##   launch   his peak speed afterwards, px/s
##   impulse  his mass times that — the momentum the swing actually handed him. Deterministic,
##            where the billed HitInfo numbers are not quite: the same contacts are grouped
##            into hits a little differently run to run.
##   spin     the weapon's peak angular speed, rad/s
##   speed    the weapon's peak linear speed, px/s
##
## The drag is the game's own: a PinJoint2D at `grip_offset` with the body's softness and bias,
## pinned to its `Handle`. Only the handle is moved by the rig rather than by the cursor —
## `get_global_mouse_position()` reads the OS pointer, which no headless run can move — so
## `follow_lerp` is zeroed and the rig writes the handle each physics frame instead, exactly as
## `_physics_process` would with the cursor there. No FXLayer is present, so there is no hit-stop.
##
## Its own save slot and settings file, cleared before and after (D51): hits pay, and paying
## is a write.

const TEST_SLOT := "swing_rig_slot"
const FLOOR_TOP := 500.0
const BUDDY_X := 640.0
const START_X := 260.0
const END_X := 1020.0
const FOLLOW_FRAMES := 45
## His chest, above his centre of mass: the height the hand crosses him at.
const CHEST_ABOVE_COM := 20.0

## The references first (they must not move), then the weapons D61 changed the most.
const DEFAULT_SAMPLE := [
	&"baseball_bat", &"mace", &"katana",
	&"greatsword", &"sickle", &"katar", &"scythe", &"halberd", &"machete", &"chainsaw",
	&"nunchaku", &"tyre_iron", &"crowbar", &"flail", &"mechanical_keyboard", &"monitor",
]

var _hits: Array[HitInfo] = []
var _world: Node2D

func _ready() -> void:
	Settings.config_path = "user://settings_swing_rig.cfg"
	Settings.focus_intensity = Settings.Intensity.OFF
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()

	var args := OS.get_cmdline_user_args()
	var sample: Array = DEFAULT_SAMPLE
	var at := args.find("--only")
	if at >= 0 and at + 1 < args.size():
		sample = Array(args[at + 1].split(",", false)).map(func(s: String) -> StringName: return StringName(s))
	var speed := 1200.0
	at = args.find("--speed")
	if at >= 0 and at + 1 < args.size():
		speed = float(args[at + 1])

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	var ground := StaticBody2D.new()
	ground.name = "Floor"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 200)
	shape.shape = rect
	ground.add_child(shape)
	ground.position = Vector2(640, FLOOR_TOP + 100.0)
	_world.add_child(ground)
	EventBus.damage_dealt.connect(func(info: HitInfo) -> void: _hits.append(info))

	print("")
	print("swing rig — hand at %.0f px/s across him, through his chest" % speed)
	print("%-20s %6s %8s %4s %7s %8s %7s %8s %6s %7s" % [
		"id", "lever", "inertia", "hits", "max", "sum", "launch", "impulse", "spin", "speed"])
	for id in sample:
		var row := await _swing(id, speed)
		if row.is_empty():
			print("%-20s (no such body)" % id)
			continue
		print("%-20s %6.1f %8.0f %4d %7.0f %8.0f %7.0f %8.0f %6.1f %7.0f" % [
			id, row["lever"], row["inertia"], row["hits"], row["max"], row["sum"],
			row["launch"], row["impulse"], row["spin"], row["speed"]])

	_clear_slot()
	get_tree().quit()

func _swing(id: StringName, speed: float) -> Dictionary:
	var item := ItemDB.get_item(id)
	if item == null or item.scene == null:
		return {}
	var buddy := (load("res://Scenes/Buddy/buddy.tscn") as PackedScene).instantiate() as Buddy
	buddy.position = Vector2(BUDDY_X, FLOOR_TOP - 64.0)
	_world.add_child(buddy)
	for i in 60:
		await get_tree().physics_frame
	buddy.health.reset_meter()

	var weapon := item.scene.instantiate() as BaseDraggable
	if weapon == null:
		buddy.queue_free()
		return {}
	weapon.item_id = id
	var lever := (weapon.center_of_mass - weapon.grip_offset).length()
	var chest := buddy.to_global(buddy.center_of_mass).y - CHEST_ABOVE_COM
	var hand := Vector2(START_X, chest)
	# Trailing level behind the hand: centre of mass straight back (-x) from the grip.
	var back := (weapon.center_of_mass - weapon.grip_offset).angle()
	weapon.rotation = PI - back
	weapon.position = hand - weapon.grip_offset.rotated(weapon.rotation)
	_world.add_child(weapon)
	weapon.follow_lerp = 0.0
	weapon.handle.global_position = hand
	var joint := PinJoint2D.new()
	joint.position = weapon.grip_offset
	joint.node_a = weapon.handle.get_path()
	joint.node_b = weapon.get_path()
	joint.softness = weapon.joint_softness
	joint.bias = weapon.joint_bias
	weapon.add_child(joint)
	weapon.mouse_joint = joint
	weapon.dragging = true

	# One tick for the joint and the body to exist in the server, then from rest.
	await get_tree().physics_frame
	weapon.handle.global_position = hand
	weapon.linear_velocity = Vector2.ZERO
	weapon.angular_velocity = 0.0
	var inertia := 0.0
	var state := PhysicsServer2D.body_get_direct_state(weapon.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia

	_hits.clear()
	var peak_spin := 0.0
	var peak_speed := 0.0
	var launch := 0.0
	var step := speed / float(Engine.physics_ticks_per_second)
	while hand.x < END_X:
		hand.x = minf(hand.x + step, END_X)
		weapon.handle.global_position = hand
		await get_tree().physics_frame
		peak_spin = maxf(peak_spin, absf(weapon.angular_velocity))
		peak_speed = maxf(peak_speed, weapon.linear_velocity.length())
		launch = maxf(launch, buddy.linear_velocity.length())
	for i in FOLLOW_FRAMES:
		weapon.handle.global_position = hand
		await get_tree().physics_frame
		peak_spin = maxf(peak_spin, absf(weapon.angular_velocity))
		launch = maxf(launch, buddy.linear_velocity.length())

	var mine := _hits.filter(func(h: HitInfo) -> bool: return h.source_id == id)
	var biggest := 0.0
	var total := 0.0
	for h in mine:
		biggest = maxf(biggest, h.raw_impulse)
		total += h.raw_impulse
	var buddy_mass := buddy.mass
	weapon.queue_free()
	buddy.queue_free()
	await get_tree().physics_frame
	return {
		"lever": lever, "inertia": inertia, "hits": mine.size(), "max": biggest, "sum": total,
		"launch": launch, "impulse": launch * buddy_mass, "spin": peak_spin, "speed": peak_speed,
	}

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
