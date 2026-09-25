extends CaptureWindow

## The held weapons' abilities (D74) as the player sees them: each one used on him in the real
## game, and caught at the frames that say what it is — the wind-up, the moment it lands, what it
## leaves behind. A VFX is unfinished until a capture shows it (CLAUDE.md).
##
##   Godot --fixed-fps 60 --path <project> res://tools/ability_shots.tscn        (NOT --headless)
##   ... -- --only=baseball_bat,katana
##   ... -- --trace          (where the hand, the handle, the grip and he are at each shot)
##
## `--fixed-fps 60` is mandatory: each shot is a frame count after the press, and without it a
## frame is however long the last PNG took to write. Files land in `user://ability_shots/`. Its own
## save slot and settings file, through `CaptureWindow._use_capture_slot()`.
##
## **The hand is the tool's, not the cursor.** The root viewport's mouse position is the OS
## pointer, which nothing here can move, so each weapon is held the way `tools/swing_rig.gd` holds
## one: its own drag joint at the grip, `follow_lerp` zeroed, and the handle written every frame.
## An ability that moves the hand itself (the katana's lunge, the hammer's plunge) nudges that same
## handle, so it is exactly the game's motion. The thrown axe is let go before it comes home,
## because catching it re-grabs at the OS pointer.

const SIZE := Vector2i(1180, 700)
const OUT := "user://ability_shots"
## The crop each shot is also written as, at 3x, into `zoom/`.
const ZOOM_BOX := Vector2i(360, 240)

var _main: Node
var _had := {}
var _hand := Vector2.ZERO
var _weapon: WeaponBase
var _buddy: Buddy
var _n := 0

func _ready() -> void:
	_use_capture_slot()
	_had = {"hud": Settings.hud_pinned, "tabs": Settings.tabs_pinned, "scale": Settings.ui_scale,
		"focus": Settings.focus_intensity}
	DirAccess.make_dir_recursive_absolute(OUT + "/zoom")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.ui_scale = 0
	Settings.hud_pinned = true
	Settings.tabs_pinned = true
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "abilities")
	await _idle(30)
	Economy.grant(Economy.BONES, 1.0e7)
	for id in AbilityTable.item_ids():
		_own(id)

	# The shop's how-to strip, on the starter weapon.
	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	if panels and shop:
		panels.call("show_panel", &"shop")
		shop.call("show_side", ItemData.SIDE_HARM)
		shop.call("show_category", ItemData.CATEGORY_WEAPON)
		shop.call("select", &"baseball_bat")
		await _shot("shop-howto-bat", 45)
		panels.call("close")
		await _idle(10)

	_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	var only := _only()
	for id in AbilityTable.item_ids():
		if not only.is_empty() and not only.has(String(id)):
			continue
		await _stage(id)

	_clear_slot()
	print("ability_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	Settings.hud_pinned = _had["hud"]
	Settings.tabs_pinned = _had["tabs"]
	Settings.ui_scale = _had["scale"]
	Settings.focus_intensity = _had["focus"]
	Settings.save_settings()
	get_tree().quit()

func _only() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--only="):
			return String(arg).trim_prefix("--only=").split(",", false)
	return PackedStringArray()

func _own(id: StringName) -> void:
	var item := ItemDB.get_item(id)
	if item == null or Progression.is_unlocked(id):
		return
	for req in item.requires:
		_own(req)
	Economy.grant(item.currency_id(), float(item.cost))
	Progression.purchase_item(id)

# --- one weapon --------------------------------------------------------------------------

func _stage(id: StringName) -> void:
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if spawner:
		spawner.clear_desk()
	await _idle(4)
	var idle := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	if idle:
		idle._disturb()
	# Him, standing still a little right of centre, on whatever the floor is.
	_buddy.health.reset_meter()
	_buddy.global_rotation = 0.0
	_buddy.global_position = Vector2(float(SIZE.x) * 0.5 + 160.0, _buddy.global_position.y)
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	await _idle(40)
	_n = 0
	var ability_row := AbilityTable.row_for(id)
	var centre := _buddy.get_interaction_rect().get_center()
	var floor_y := _buddy.get_interaction_rect().end.y
	var start := centre + Vector2(-220.0, -40.0)
	EventBus.spawn_requested.emit(id, start)
	await _idle(2)
	_weapon = null
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		if (node as BaseDraggable).item_id == id:
			_weapon = node as WeaponBase
	if _weapon == null or _weapon.ability == null:
		print("  %s: no weapon with an ability" % id)
		return
	_hold(start)
	await _carry(start, 20)
	var ability := _weapon.ability
	print("  %s — %s" % [id, ability_row.get("name", "")])
	match ability.archetype():
		&"charge":
			await _carry(centre + Vector2(-130.0, -20.0), 30)
			ability.press()
			await _carry(_hand, 38)
			await _shot("%s-winding" % id)
			await _carry(_hand, 20)
			ability.release()
			for i in 30:
				await _carry(_hand.move_toward(centre + Vector2(170.0, -20.0), 22.0), 1)
				if ability.payoffs > 0:
					break
			await _shot("%s-lands" % id, 1)
			await _shot("%s-launched" % id, 12)
		&"dash":
			await _carry(centre + Vector2(-200.0, -10.0), 40)
			var dash := ability as DashAbility
			ability.press()
			ability.release()
			await _shot("%s-draw" % id, 4)
			for i in 20:
				await _carry(_hand, 1)
				if dash._phase == DashAbility.DASH and dash._t >= 0.04:
					break
			await _shot("%s-lunge" % id)
			for i in 20:
				await _carry(_hand, 1)
				if dash._phase == DashAbility.HOLD:
					break
			await _shot("%s-through" % id, 3)
			for i in 40:
				await _carry(_hand, 1)
				if dash.last_cut > 0.0:
					break
			await _shot("%s-cut" % id, 1)
			await _shot("%s-after" % id, 14)
		&"stun":
			await _carry(centre + Vector2(-150.0, -30.0), 30)
			ability.press()
			ability.release()
			await _shot("%s-armed" % id, 4)
			for i in 40:
				await _carry(_hand.move_toward(centre + Vector2(170.0, -30.0), 22.0), 1)
				if ability.payoffs > 0:
					break
			await _shot("%s-bong" % id, 2)
			await _carry(centre + Vector2(-150.0, -30.0), 20)
			await _shot("%s-dazed" % id, 10)
		&"sustain":
			await _carry(centre + Vector2(-70.0, 0.0), 30)
			ability.press()
			await _carry(_hand, 20)
			await _shot("%s-revving" % id)
			await _carry(_hand, 20)
			await _shot("%s-grinding" % id)
			ability.release()
		&"shockwave":
			await _carry(Vector2(centre.x - 100.0, floor_y - 150.0), 60)
			ability.press()
			await _shot("%s-raised" % id, 6)
			for i in 30:
				await _carry(_hand, 1)
				if (ability as ShockwaveAbility).last_impact != Vector2.INF:
					break
			await _shot("%s-impact" % id, 1)
			await _shot("%s-wave" % id, 10)
		&"projectile":
			await _carry(centre + Vector2(-330.0, -40.0), 40)
			ability.press()
			await _carry(_hand, 50)
			await _shot("%s-teed" % id)
			ability.release()
			await _shot("%s-flight" % id, 9)
			for i in 40:
				await _carry(_hand, 1)
				if ability.payoffs > 0:
					break
			await _shot("%s-hit" % id, 1)
		&"spin":
			await _carry(centre + Vector2(-95.0, -40.0), 40)
			ability.press()
			ability.release()
			await _shot("%s-spinning" % id, 14)
			for i in 20:
				await _carry(_hand.move_toward(_buddy.get_interaction_rect().get_center()
					+ Vector2(-95.0, -40.0), 15.0), 1)
			await _shot("%s-whirl" % id, 1)
		&"throw":
			await _carry(centre + Vector2(-260.0, -80.0), 40)
			var hand := _hand
			ability.press()
			await _shot("%s-thrown" % id, 7)
			for i in 40:
				await _idle(1)
				if (ability as ThrowAbility).throw_hits > 0:
					break
			await _shot("%s-chop" % id, 1)
			# Let go before it comes home: the catch re-grabs at the OS pointer.
			(ability as ThrowAbility)._left_down = false
			await _shot("%s-returning" % id, 12)
			_hand = hand
		&"transform":
			var change := ability as TransformAbility
			await _carry(centre + Vector2(-170.0, -30.0), 30)
			ability.press()
			ability.release()
			await _shot("%s-changed" % id, 10)
			if change.is_phased():
				# Drawn slowly through him and held in him, the way a lit blade is used.
				for i in 90:
					await _carry(_hand.move_toward(centre + Vector2(40.0, 0.0), 4.0), 1)
					if change.burns > 0:
						break
				await _shot("%s-inside" % id, 1)
				for i in 30:
					await _carry(_hand.move_toward(centre + Vector2(-60.0, 10.0), 4.0), 1)
				await _shot("%s-burning" % id)
			else:
				for i in 40:
					await _carry(_hand.move_toward(centre + Vector2(170.0, -30.0), 22.0), 1)
					if change.blows > 0:
						break
				await _shot("%s-blow" % id, 1)
				await _shot("%s-quake" % id, 5)
		_:
			print("    no staging for the %s archetype yet — add a branch here" % ability.archetype())
	await _idle(30)
	if is_instance_valid(_weapon):
		_weapon.bin_myself()
	await _idle(10)

## The weapon held at `at` the way swing_rig holds one: its grip on a joint to its own handle.
func _hold(at: Vector2) -> void:
	_hand = at
	_weapon.follow_lerp = 0.0
	_weapon.global_rotation = 0.0
	_weapon.global_position = at - _weapon.grip_offset
	_weapon.linear_velocity = Vector2.ZERO
	_weapon.angular_velocity = 0.0
	_weapon.handle.global_position = at
	var joint := PinJoint2D.new()
	joint.name = "CaptureJoint"
	joint.position = _weapon.grip_offset
	joint.node_a = _weapon.handle.get_path()
	joint.node_b = _weapon.get_path()
	joint.softness = _weapon.joint_softness
	joint.bias = _weapon.joint_bias
	_weapon.add_child(joint)
	_weapon.mouse_joint = joint
	_weapon.dragging = true

## Carries the hand to `to` over `frames` frames, a straight line, writing the handle each frame —
## outright, as swing_rig does: the handle is a child of the weapon, so with the chase zeroed it
## would otherwise ride along with whatever the weapon does. The ability's own hand offset
## (`BaseDraggable.hand_offset`) rides on top of it, exactly as it does on the cursor in the game.
func _carry(to: Vector2, frames: int) -> void:
	var from := _hand
	for i in frames:
		var k := float(i + 1) / float(maxi(frames, 1))
		_hand = from.lerp(to, k)
		# The frame passes whether or not anything is held: a shot of the shop waits too.
		if is_instance_valid(_weapon) and _weapon.dragging and _weapon.handle:
			_weapon.handle.global_position = _hand + _weapon.hand_offset
		await _idle(1)

## A frame of the window, `after` frames from now. Headless draws nothing, so there a shot is
## only the staging — still worth running, because it proves the staging works.
func _shot(name: String, after: int = 0) -> void:
	for i in after:
		await _carry(_hand, 1)
	_n += 1
	if DisplayServer.get_name() == "headless":
		print("    %s (staged; headless draws nothing)" % name)
		return
	await RenderingServer.frame_post_draw
	var frame := _grab()
	frame.save_png("%s/%s.png" % [OUT, name])
	# And the part that matters at 3x, nearest-neighbour: a 1x frame of a whole desk is too small
	# to judge a two-pixel glow or a hole in him by. Centred between the weapon and him.
	if is_instance_valid(_weapon) and is_instance_valid(_buddy):
		var mid := (_weapon.global_position + _buddy.get_interaction_rect().get_center()) * 0.5
		var box := Rect2i(Vector2i(mid - Vector2(ZOOM_BOX) * 0.5), ZOOM_BOX)
		box = box.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
		if box.size.x > 8 and box.size.y > 8:
			var crop := frame.get_region(box)
			crop.resize(box.size.x * 3, box.size.y * 3, Image.INTERPOLATE_NEAREST)
			crop.save_png("%s/zoom/%s.png" % [OUT, name])
	print("    %s" % name)
	if OS.get_cmdline_user_args().has("--trace") and is_instance_valid(_weapon):
		print("      hand %s handle %s grip %s him %s" % [_hand.round(), _weapon.handle.global_position.round(),
			_weapon.to_global(_weapon.grip_offset).round(), _buddy.get_interaction_rect().get_center().round()])
