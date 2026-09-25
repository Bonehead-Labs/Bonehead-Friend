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
	# Him, standing still a little right of centre, on whatever the floor is — once he is back on
	# his feet from anything the last weapon did: a flail flings him to the top of the window, and
	# a stage measured from him in mid-air, or in a knockout, stages the next weapon at nothing.
	for i in 600:
		if not ExpressionBrain.KNOCKOUT_STATES.has(_buddy.state) and not _buddy.health.down:
			break
		await _idle(1)
	_buddy.health.reset_meter()
	_buddy.global_rotation = 0.0
	_buddy.global_position = Vector2(float(SIZE.x) * 0.5 + 160.0, _buddy.global_position.y)
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	await _idle(40)
	for i in 240:
		if _buddy.is_grounded() and _buddy.linear_velocity.length() < 5.0:
			break
		await _idle(1)
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
	# A hooked row that is used differently from its archetype brings a staging of its own: named
	# for the ability (`_stage_<ability id>`, the blades) or for the weapon (`_stage_<item id>`,
	# the blunt and desk nine). Its frames are not its archetype's.
	var staging := "_stage_%s" % ability.ability_id()
	if not has_method(staging) and ability_row.has("script"):
		staging = "_stage_%s" % id
	match &"hooked" if has_method(staging) else ability.archetype():
		&"hooked":
			await call(staging, id, ability, centre, floor_y)
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
		&"tether":
			await _stage_tether(id, ability as TetherAbility, centre)
		&"clamp":
			await _stage_clamp(id, ability as ClampAbility)
		_:
			print("    no staging for the %s archetype yet — add a branch here" % ability.archetype())
	await _idle(30)
	if is_instance_valid(_weapon):
		_weapon.bin_myself()
	await _idle(10)

# --- the blades (D74) -----------------------------------------------------------------------

## Momentum: right held above him and to one side; the heave starts the first arc, the loosened
## grip keeps it going round, and the hand steers the arcs into him while the notches fill.
func _stage_momentum(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-190.0, -200.0), 30)
	var momentum := ability as MomentumAbility
	ability.press()
	await _shot("%s-heave" % id, 10)
	for i in 150:
		await _carry(_hand.move_toward(_buddy.get_interaction_rect().get_center() + Vector2(-120.0, -190.0),
			3.0), 1)
		if momentum.chain() >= 3 or not ability.is_active():
			break
		if i == 40:
			await _shot("%s-arc" % id)
	await _shot("%s-chain" % id, 2)
	ability.release()

## Embed: thrown, lodged in him, a tick of bone dust, and out.
func _stage_embed(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-260.0, -80.0), 40)
	var embed := ability as EmbedAbility
	ability.press()
	await _shot("%s-thrown" % id, 6)
	for i in 40:
		await _idle(1)
		if embed.lodged:
			break
	await _shot("%s-lodged" % id, 2)
	for i in 40:
		await _idle(1)
		if embed.ticks > 0:
			break
	await _shot("%s-tick" % id, 1)
	for i in 200:
		await _idle(1)
		if not embed.is_lodged():
			break
	await _shot("%s-out" % id, 8)

## Brush Clear: three toys on the desk in front of the hand, and one swipe.
func _stage_brush_clear(id: StringName, ability: WeaponAbility, centre: Vector2, floor_y: float) -> void:
	for toy in [&"rubber_duck", &"tennis_ball", &"baseball"]:
		_own(toy)
	EventBus.spawn_requested.emit(&"rubber_duck", Vector2(centre.x - 110.0, floor_y - 30.0))
	EventBus.spawn_requested.emit(&"tennis_ball", Vector2(centre.x - 75.0, floor_y - 30.0))
	EventBus.spawn_requested.emit(&"baseball", Vector2(centre.x + 90.0, floor_y - 30.0))
	await _carry(centre + Vector2(-210.0, -20.0), 50)
	var brush := ability as BrushClearAbility
	ability.press()
	ability.release()
	await _shot("%s-wind" % id, 4)
	for i in 20:
		await _carry(_hand, 1)
		if brush.last_origin != Vector2.INF:
			break
	await _shot("%s-swipe" % id, 1)
	await _shot("%s-cleared" % id, 8)

## Reap: the hand drops and sweeps; his feet go; he goes over.
func _stage_reap(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-170.0, -30.0), 40)
	var reap := ability as ReapAbility
	ability.press()
	ability.release()
	for i in 20:
		await _carry(_hand, 1)
		if reap._phase == ReapAbility.SWEEP:
			break
	await _shot("%s-sweep" % id, 3)
	for i in 30:
		await _carry(_hand, 1)
		if reap.caught_him:
			break
	await _shot("%s-caught" % id, 1)
	await _shot("%s-over" % id, 9)

## Soul Reap: armed, one quick stroke toward him that stops short, the ghost, and his soul.
func _stage_soul_reap(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-430.0, -60.0), 50)
	var soul := ability as SoulReapAbility
	ability.press()
	await _shot("%s-armed" % id, 20)
	for i in 10:
		await _carry(_hand + Vector2(30.0, 0.0), 1)
		if not ability.is_active():
			break
	ability.release()
	await _shot("%s-ghost" % id, 4)
	for i in 40:
		await _carry(_hand, 1)
		if soul.reaps > 0:
			break
	await _shot("%s-reaped" % id, 1)
	await _shot("%s-soul" % id, 8)

## En Garde: on guard at him, and a lunge.
func _stage_en_garde(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-200.0, -40.0), 40)
	var guard := ability as EnGardeAbility
	ability.press()
	await _shot("%s-guard" % id, 40)
	for i in 12:
		await _carry(_hand.move_toward(centre + Vector2(-50.0, -40.0), 20.0), 1)
		if guard.thrusts > 0:
			break
	await _shot("%s-thrust" % id, 1)
	ability.release()

## Flurry: held beside him, jabbing.
func _stage_flurry(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-95.0, -10.0), 40)
	ability.press()
	await _shot("%s-jab" % id, 5)
	await _shot("%s-flurry" % id, 14)
	await _carry(_hand, 60)
	ability.release()

## Snap: three tips, straight.
func _stage_snap(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-300.0, -40.0), 40)
	var snap := ability as SnapAbility
	ability.press()
	ability.release()
	await _shot("%s-first" % id, 3)
	await _shot("%s-three" % id, 12)
	for i in 30:
		await _carry(_hand, 1)
		if snap.tips_hit >= 2:
			break
	await _shot("%s-hit" % id, 1)

## Special Delivery: point first across the desk, the point arriving, and stuck where it landed.
func _stage_special_delivery(id: StringName, ability: WeaponAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-260.0, -60.0), 40)
	var delivery := ability as DeliveryAbility
	ability.press()
	await _shot("%s-flight" % id, 4)
	for i in 40:
		await _idle(1)
		if delivery.point_hits > 0:
			break
	await _shot("%s-point" % id, 1)
	for i in 120:
		await _idle(1)
		if delivery.is_stuck():
			break
	await _shot("%s-stuck" % id, 3)

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

# --- the blunt and desk nine (D74, second pass) --------------------------------------------
#
# Each drives its own hook the way its line says, and asserts the thing that makes it itself.

func _stage_morning_star(id: StringName, ability: BristleAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-180.0, -40.0), 40)
	await _shot("%s-ready" % id, 10)
	ability.press()
	ability.release()
	await _shot("%s-fan" % id, 3)
	for i in 30:
		await _carry(_hand, 1)
		if ability.last_hits > 0:
			break
	await _shot("%s-hit" % id, 2)
	await _shot("%s-bald" % id, 20)
	var gap := ability.cooldown_left()
	for i in int(gap * 60.0):
		await _carry(_hand, 1)
		if ability.cooldown_left() <= gap * 0.45:
			break
	await _shot("%s-regrowing" % id)

func _stage_cricket_bat(id: StringName, ability: MiddleItAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-360.0, -110.0), 40)
	await _carry(_hand, 60)
	ability.press()
	ability.release()
	await _shot("%s-lit" % id, 6)
	# ability_check's sweep: a run-up at an unhurried 450 px/s, then the middle aimed at his middle
	# at the height it rides below the moving hand.
	for attempt in 2:
		if ability.sixes > 0 or not ability.is_active():
			break
		var him := _buddy.get_interaction_rect().get_center()
		await _carry(Vector2(him.x - 360.0, him.y - 110.0), 10)
		while _hand.x < him.x - 230.0:
			await _carry(_hand + Vector2(450.0 / 60.0, 0.0), 1)
		var line := him.y - (ability.middle_world().y - _hand.y)
		while _hand.x < him.x + 200.0 and ability.sixes == 0 and ability.is_active():
			await _carry(Vector2(_hand.x + 450.0 / 60.0, move_toward(_hand.y, line, 4.0)), 1)
		print("    sweep %d: met the blade at %.2f, %d six" % [attempt, ability.last_blade_t, ability.sixes])
	await _shot("%s-six" % id, 1)
	await _shot("%s-up" % id, 14)
	await _shot("%s-top" % id, 30)

func _stage_rolling_pin(id: StringName, ability: FlattenAbility, centre: Vector2, floor_y: float) -> void:
	await _carry(Vector2(centre.x - 190.0, floor_y - 60.0), 40)
	ability.press()
	await _carry(_hand, 24)
	await _shot("%s-down" % id)
	for i in 80:
		await _carry(_hand.move_toward(Vector2(centre.x + 150.0, floor_y - 60.0), 500.0 / 60.0), 1)
		if ability.passes > 0:
			break
	await _shot("%s-flattened" % id, 3)
	await _shot("%s-pancake" % id, 12)
	await _carry(_hand, 20)
	await _shot("%s-springs-back" % id, 20)
	ability.release()

func _stage_stapler(id: StringName, ability: StapleGunAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-260.0, -40.0), 40)
	ability.press()
	await _shot("%s-firing" % id, 14)
	await _carry(_hand, 50)
	await _shot("%s-stapled" % id)
	ability.release()

func _stage_tyre_iron(id: StringName, ability: RicochetAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-250.0, -80.0), 40)
	var hand := _hand
	ability.press()
	ability.release()
	await _shot("%s-thrown" % id, 5)
	for i in 60:
		await _idle(1)
		if ability.banks_done() > 0:
			break
	await _shot("%s-bank" % id, 1)
	for i in 60:
		await _idle(1)
		if ability.throw_hits > 0:
			break
	await _shot("%s-hit" % id, 1)
	await _shot("%s-after" % id, 16)
	_hand = hand

func _stage_war_pick(id: StringName, ability: PinpointAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-130.0, -60.0), 40)
	ability.press()
	await _shot("%s-aiming" % id, 18)
	for i in 60:
		await _carry(_hand, 1)
		if ability.is_locked_on():
			break
	await _shot("%s-locked" % id, 6)
	ability.release()
	for i in 40:
		await _carry(_hand, 1)
		if ability.last_pick > 0.0 or not ability.is_driving():
			break
	print("    the beak came within %.0f px of the spot; the pick %.0f" % [ability.last_miss, ability.last_pick])
	await _shot("%s-struck" % id, 1)
	await _shot("%s-after" % id, 12)

func _stage_mechanical_keyboard(id: StringName, ability: KeycapBarrageAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-260.0, -60.0), 40)
	ability.press()
	ability.release()
	await _shot("%s-fountain" % id, 14)
	for i in 60:
		await _carry(_hand, 1)
		if ability.hits > 0:
			break
	await _shot("%s-rain" % id, 3)
	await _shot("%s-bare" % id, 20)
	await _shot("%s-home" % id, 40)

func _stage_monitor(id: StringName, ability: BlueScreenAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-150.0, -30.0), 40)
	ability.press()
	ability.release()
	await _shot("%s-frozen" % id, 6)
	for i in 30:
		await _carry(_hand.move_toward(centre + Vector2(200.0, -30.0), 26.0), 1)
	await _carry(centre + Vector2(-150.0, -30.0), 20)
	await _shot("%s-stored" % id, 2)
	for i in 90:
		await _carry(_hand, 1)
		if not ability.is_frozen():
			break
	await _shot("%s-dump" % id, 2)
	await _shot("%s-after" % id, 10)

func _stage_office_mug(id: StringName, ability: HotCoffeeAbility, centre: Vector2, _floor_y: float) -> void:
	await _carry(centre + Vector2(-240.0, -60.0), 40)
	ability.press()
	ability.release()
	await _shot("%s-splash" % id, 9)
	for i in 60:
		await _carry(_hand, 1)
		if ability.scalds > 0:
			break
	await _shot("%s-scald" % id, 2)
	await _shot("%s-steam" % id, 24)

# --- transform, tether and clamp (D74, the new archetypes) -----------------------------------

## The three clamps: the jaws brought to him, the bite, and what it leaves — a hole, his headphones
## on the desk and his head bare, or him turned in the jaws as the hand goes round.
func _stage_clamp(id: StringName, clamp: ClampAbility) -> void:
	var head := bool(clamp.row.get("snip_head", false))
	# Lifted clear so it hangs freely, the jaws set level with the point clear of him — his head for
	# the shears — then across to him slowly until he is between them.
	var rect := _buddy.get_interaction_rect()
	var aim := _buddy.to_global(Vector2(0.0, -40.0)) if head else rect.get_center() + Vector2(0.0, 10.0)
	await _carry(Vector2(aim.x - 150.0, rect.position.y - 90.0), 30)
	await _carry(_hand, 60)
	var hang := clamp.jaw_world() - clamp.hand_world()
	await _carry(Vector2(aim.x - 110.0, aim.y) - hang, 30)
	await _carry(_hand, 60)
	for i in 400:
		if clamp.in_jaws():
			break
		await _carry(_hand + Vector2(1.5, 0.0), 1)
	await _shot("%s-jaws" % id, 2)
	clamp.press()
	clamp.release()
	await _shot("%s-bite" % id, 2)
	for i in 30:
		if clamp._phase != ClampAbility.BITING or not clamp.is_active():
			break
		await _carry(_hand, 1)
	if head:
		await _shot("%s-snipped" % id, 16)
		await _shot("%s-bareheaded" % id, 60)
		await _shot("%s-back" % id, int(clamp.num("phones_seconds", 4.0) * 60.0) - 20)
		return
	if clamp.num("hold_seconds", 0.0) > 0.0:
		var centre := _buddy.get_interaction_rect().get_center()
		var radius := maxf(_hand.distance_to(centre), 110.0)
		var a0 := (_hand - centre).angle()
		for i in 110:
			if not clamp.is_clamped():
				break
			var a := a0 + TAU * 1.4 * float(i) / 120.0
			await _carry(_buddy.get_interaction_rect().get_center() + Vector2(cos(a), sin(a)) * radius, 1)
			if i == 40:
				await _shot("%s-cranking" % id)
			if i == 80:
				await _shot("%s-cranked" % id)
		if OS.get_cmdline_user_args().has("--trace"):
			print("      let go: %s after %d cranks, %.2f turns" % [clamp.let_go_reason, clamp.cranks, clamp.turns])
		return
	await _shot("%s-hole" % id, 20)

## The three tethers: the chain round him and swung, the hook out and reeling, the lever.
func _stage_tether(id: StringName, tether: TetherAbility, centre: Vector2) -> void:
	if tether is HookTether:
		var hook := tether as HookTether
		await _carry(centre + Vector2(-230.0, -60.0), 40)
		await _carry(_hand, 20)
		hook.press()
		hook.release()
		await _shot("%s-hook-out" % id, 5)
		for i in 30:
			await _carry(_hand, 1)
			if hook.catches > 0:
				break
		await _shot("%s-hooked" % id, 2)
		for i in 60:
			await _carry(_hand, 1)
			if hook.spiked or not hook.is_active():
				break
		await _shot("%s-spike" % id, 1)
		await _shot("%s-thrown" % id, 10)
		return
	if tether is PryTether:
		var pry := tether as PryTether
		# It hangs claw-down: carried slowly across to him a bar's length above his lower half, until
		# the claw is against his side.
		var bar := pry.grip_world().distance_to(pry.tip_world())
		var level := _buddy.get_interaction_rect().end.y - 40.0 - bar
		await _carry(Vector2(centre.x - 150.0, level), 40)
		await _carry(_hand, 60)
		for i in 300:
			if pry.touches_him(pry.tip_world(), pry.num("reach", 30.0) - 8.0):
				break
			level = _buddy.get_interaction_rect().end.y - 40.0 - bar
			var to := Vector2(_buddy.get_interaction_rect().get_center().x, level)
			await _carry(_hand.move_toward(to, clampf(_hand.distance_to(to) / 30.0, 1.5, 8.0)), 1)
		pry.press()
		await _shot("%s-wedged" % id, 3)
		await _carry(_hand + Vector2(0.0, 28.0), 12)
		await _shot("%s-levering" % id, 4)
		await _carry(_hand + Vector2(0.0, 28.0), 12)
		await _shot("%s-levered" % id, 6)
		pry.release()
		await _shot("%s-pop" % id, 3)
		await _shot("%s-over" % id, 12)
		return
	# The Wrap: right held through a swing; he is caught, swung round, and flung.
	await _carry(centre + Vector2(-190.0, -30.0), 30)
	tether.press()
	for i in 60:
		await _carry(_hand.move_toward(centre + Vector2(190.0, -30.0), 22.0), 1)
		if tether.catches > 0:
			break
	await _shot("%s-wrapped" % id, 2)
	# Up into the open, then round: he whirls on the end of the chain. His meter is kept clear for
	# the picture: a flail's hits knock him out in four, which ends the hold, as it should in play.
	var round := Vector2(float(SIZE.x) * 0.5, float(SIZE.y) * 0.5 - 40.0)
	for i in 24:
		_buddy.health.reset_meter()
		await _carry(_hand.lerp(round + Vector2(110.0, 0.0), float(i + 1) / 24.0), 1)
	for i in 36:
		_buddy.health.reset_meter()
		var a := TAU * float(i) / 36.0
		await _carry(round + Vector2(cos(a) * 110.0, sin(a) * 70.0), 1)
		if i == 24:
			await _shot("%s-swung" % id)
	tether.release()
	await _shot("%s-flung" % id, 3)
	await _shot("%s-landing" % id, 14)
