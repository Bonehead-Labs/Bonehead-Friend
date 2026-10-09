extends Node

## The held guns (docs/decisions.md D56), against real physics and the real payout pipeline.
##
##   Godot --headless --path <project> res://tests/integration/gun_check.tscn
##
## A scene rather than a `-s` script because it needs the autoloads, and it builds its own
## floor: a headless viewport is 64x64, so nothing here may lean on WorldBounds. Runs against
## its own save slot and its own settings file, and clears both.
##
## Since D71 it covers every gun in the game — the cursor's three kept as held guns under their
## own ids (and a save from before, loaded, that owned them), and the six whose verbs are new:
## the double barrel's break, the minigun's spin, the tommy gun's drum, the ray gun's heat, the
## lobbed grenade, the flare that burns, the harpoon that reels and the dart that sticks.
##
## What it is here to prove, because none of it can be seen from source:
##   - the aim settles on him while held, in a time that is stated, and does nothing dropped;
##   - a shot kicks the gun a measurable amount and the aim walks it back;
##   - the trigger is right-click while held and nothing else, and Shift+right still bins;
##   - a hit pays Bones through the real pipeline and a miss — fired along the barrel's actual
##     line, not the ideal one — pays nothing;
##   - a held stream stops on a release the world never saw;
##   - the kind guns clean and pay Hearts, and bouncing one off him pays no Bones;
##   - he cowers while one is pointed at him;
##   - the recoil and fire-rate nodes are read, not placebos.
##
## `_check` takes two arguments, as loop_check's does. A third is a parse error, and a parse
## error in a test scene presents as a hang.

const TEST_SLOT := "gun_check_slot"
const HARM := [&"revolver", &"smg", &"pump_shotgun", &"hunting_rifle", &"blunderbuss",
	# D71: the three the cursor gave up, under their own ids, and the six new ones.
	&"pistol", &"shotgun", &"minigun", &"flare_gun", &"tommy_gun", &"grenade_launcher",
	&"harpoon_gun", &"ray_gun"]
const KIND := [&"water_pistol", &"bubble_blaster", &"foam_dart_blaster"]

## Floor top at y = 600; he stands on it at about x = 900.
const FLOOR_TOP := 600.0
const BUDDY_AT := Vector2(900, 530)
## Where the hand holds a gun: level with his chest, well to his left.
const HAND := Vector2(620, 480)

var _passed := 0
var _failed := 0

var _world: Node2D
var _buddy: Buddy
var _hits: Array[HitInfo] = []
var _payouts: Array[Array] = []
var _given: Array[Array] = []
var _sustained: Array[Array] = []
var _threats: Array[Array] = []
## Where the gun under test is held, and the gun: re-pinned every physics frame by `_step`.
var _hand := HAND
var _held: HeldGun = null

func _ready() -> void:
	# Its own preferences, first (D51): holding a gun can fire a one-off hint that saves.
	Settings.config_path = "user://settings_gun_check.cfg"
	# Silences AudioManager and the FX pools for the run; the brain's reactive rows still play.
	Settings.focus_intensity = Settings.Intensity.OFF
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()

	print("")
	print("Bonehead Friend — gun check")
	print("===========================")

	_build_world()
	EventBus.damage_dealt.connect(func(info: HitInfo) -> void: _hits.append(info))
	EventBus.payout.connect(func(c: StringName, a: float, _p: Vector2, s: StringName) -> void:
		_payouts.append([c, a, s]))
	EventBus.kindness_given.connect(func(s: StringName, v: float, _p: Vector2) -> void:
		_given.append([s, v]))
	EventBus.kindness_sustained.connect(func(s: StringName, v: float, _p: Vector2) -> void:
		_sustained.append([s, v]))
	EventBus.threat_changed.connect(func(k: StringName, _p: Vector2, level: float) -> void:
		_threats.append([k, level]))
	await _steps(60)

	_content()
	_every_gun_is_a_hand_tool()
	await _the_aim_settles_on_him()
	await _a_dropped_gun_does_not_aim()
	await _it_turns_round_rather_than_upside_down()
	await _recoil_kicks_and_the_aim_recovers()
	await _the_trigger_is_right_click_while_held()
	await _a_hit_pays_and_a_miss_does_not()
	await _a_burst_climbs_and_stops_on_any_release()
	await _he_cowers_while_it_is_on_him()
	await _the_water_pistol_cleans_and_pays_hearts()
	await _bubbles_drift_to_him_and_pop_into_hearts()
	await _a_kind_gun_thrown_at_him_pays_no_bones()
	# D71: the cursor guns kept as held guns, and the verbs the new guns brought.
	await _every_trigger_is_right_click_while_held()
	await _the_double_barrel_breaks_open()
	await _the_minigun_spins_up()
	await _the_tommy_gun_runs_dry()
	await _the_ray_gun_overheats()
	await _the_grenade_lobs_and_goes_off()
	await _the_flare_sticks_and_burns()
	await _the_harpoon_reels_him_in()
	await _foam_darts_stick_to_him()
	await _steady_is_read_on_the_new_guns()
	await _the_cursor_guns_are_guns_you_hold()

	print("")
	print("===========================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

# --- the rig -----------------------------------------------------------------

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	var floor_body := StaticBody2D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector2(640, FLOOR_TOP + 100.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(3000, 200)
	shape.shape = rect
	floor_body.add_child(shape)
	_world.add_child(floor_body)
	_buddy = (load("res://Scenes/Buddy/buddy.tscn") as PackedScene).instantiate() as Buddy
	_buddy.position = BUDDY_AT
	_world.add_child(_buddy)

## A gun on the desk, the way ItemSpawner would put it there.
func _spawn(id: StringName, at: Vector2) -> HeldGun:
	var gun := ItemDB.get_item(id).scene.instantiate() as HeldGun
	gun.item_id = id
	gun.add_to_group(BaseDraggable.GROUP_SPAWNED)
	_world.add_child(gun)
	gun.global_position = at
	return gun

## Picked up at `hand`, and held there. `_start_drag` is the real grab; the handle is then
## pinned by `_step` every physics frame, because the OS cursor it would otherwise chase cannot
## be moved from a headless run. The joint is re-made with the handle already at the hand, so
## the two anchors coincide exactly as they do when the player clicks on the grip.
func _grab(gun: HeldGun, hand: Vector2, rotation: float = 0.0) -> void:
	gun.global_position = hand
	gun.global_rotation = rotation
	gun.linear_velocity = Vector2.ZERO
	gun.angular_velocity = 0.0
	gun.follow_lerp = 0.0
	gun._start_drag()
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
	_hand = hand
	_held = gun

func _drop(gun: HeldGun) -> void:
	if is_instance_valid(gun) and gun.dragging:
		gun._end_drag()
	if _held == gun:
		_held = null

func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		if is_instance_valid(_held) and _held.dragging:
			_held.handle.global_position = _hand

func _right(pressed: bool, shift: bool = false, button: MouseButton = MOUSE_BUTTON_RIGHT) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = pressed
	click.shift_pressed = shift
	click.position = Vector2(8, 8)
	click.global_position = Vector2(8, 8)
	get_viewport().push_input(click)

## He stands at `BUDDY_AT`, still, meter empty, clean unless asked otherwise.
func _reset_buddy() -> void:
	while _buddy.health.down:
		await get_tree().physics_frame
	_buddy.global_position = BUDDY_AT
	_buddy.global_rotation = 0.0
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	_buddy.health.reset_meter()
	_buddy.grime.set_value(0.0)
	await _steps(30)

func _own(id: StringName) -> void:
	var item := ItemDB.get_item(id)
	for need in item.requires:
		_own(need)
	if Progression.is_unlocked(id):
		return
	Economy.grant(item.currency_id(), float(item.cost))
	Progression.purchase_item(id)

func _paid(currency: StringName, source: StringName) -> float:
	var total := 0.0
	for p in _payouts:
		if p[0] == currency and p[2] == source:
			total += float(p[1])
	return total

## Frames until the aim error stays under `tolerance` for good, or -1.
func _settle_frames(gun: HeldGun, frames: int, tolerance: float) -> int:
	var settled_at := -1
	for i in frames:
		await _steps(1)
		if absf(gun.aim_error()) < tolerance:
			if settled_at < 0:
				settled_at = i + 1
		else:
			settled_at = -1
	return settled_at

# --- data --------------------------------------------------------------------

func _content() -> void:
	_suite("content")
	_check("Guns is its own drawer on the harm side",
		ItemData.CATEGORY_SIDE.get(ItemData.CATEGORY_GUN, -1) == ItemData.SIDE_HARM)
	_check("and the shop names it", ShopPanel.CATEGORY_NAMES.get(ItemData.CATEGORY_GUN, "") == "Guns")
	for id in HARM + KIND:
		var item := ItemDB.get_item(id)
		if item == null:
			_check("'%s' is in the catalog" % id, false)
			continue
		var kind := KIND.has(id)
		_check("'%s' is filed %s and priced in %s" % [id, "under Care" if kind else "under Guns",
			"Hearts" if kind else "Bones"],
			item.category == (ItemData.CATEGORY_FRIENDLY if kind else ItemData.CATEGORY_GUN)
			and item.currency_id() == (Economy.HEARTS if kind else Economy.BONES))
		_check("'%s' says how to work it (%s)" % [id, item.controls], not item.controls.is_empty())
		var gun := item.scene.instantiate() as HeldGun
		_check("'%s' is a HeldGun with its grip at the origin and a muzzle" % id,
			gun != null and gun.grip_offset == Vector2.ZERO and gun.muzzle != Vector2.ZERO)
		if gun:
			gun.free()
		var keys := ItemDB.augments_for(id).map(func(n: AugmentNode) -> StringName: return n.effect_key)
		var wanted: Array = [&"damage_mult", &"payout_mult", &"cooldown_mult"]
		if not kind:
			wanted += [&"mass_mult", &"recoil_mult"]
		_check("'%s' has its tree (%s)" % [id, ", ".join(wanted)],
			wanted.all(func(k: StringName) -> bool: return keys.has(k)))
		_check("'%s' automates for Hearts" % id, ItemDB.augments_for(id).any(
			func(n: AugmentNode) -> bool: return n.is_automation and n.currency_id() == Economy.HEARTS))

## None of them is a thing he walks over and uses, and none of them may be filed where the
## idle brain would be expected to (the Play tab demands a routine; loop_check asserts it).
func _every_gun_is_a_hand_tool() -> void:
	_suite("routines")
	var brain := IdleBrain.install(self)
	for id in HARM + KIND:
		var item := ItemDB.get_item(id)
		var body := item.scene.instantiate() as BaseDraggable
		body.item_id = id
		_check("'%s' is a hand tool: no routine, and not in the Play tab" % id,
			brain._routine_for(body) == IdleBrain.ROUTINE_NONE and item.category != ItemData.CATEGORY_TOY
			and not item.is_autonomous)
		body.free()
	brain.free()

# --- aim ---------------------------------------------------------------------

func _the_aim_settles_on_him() -> void:
	_suite("aim")
	await _reset_buddy()
	for id in HARM + KIND:
		var gun := _spawn(id, _hand)
		await _steps(2)
		# A quarter turn off, pointing at the ceiling.
		_grab(gun, HAND, -PI * 0.5)
		var frames := await _settle_frames(gun, 90, deg_to_rad(3.0))
		var grip_drift := gun.global_position.distance_to(HAND)
		print("        %-15s settles from 90 deg in %s s (aim %.1f/s, damping %.2f), grip %.1f px off the hand"
			% [id, "never" if frames < 0 else "%.2f" % (frames / 60.0), gun.aim_frequency,
			gun.aim_damping, grip_drift])
		_check("'%s' settles on him within 0.5 s of being picked up pointing the wrong way" % id,
			frames > 0 and frames <= 30)
		_check("'%s' hangs from the hand (grip %.1f px off)" % [id, grip_drift], grip_drift < 8.0)
		_drop(gun)
		gun.free()
		await _steps(2)

func _a_dropped_gun_does_not_aim() -> void:
	_suite("dropped")
	var gun := _spawn(&"revolver", Vector2(400, 100))
	await _steps(2)
	gun.global_rotation = 2.0
	gun.linear_velocity = Vector2.ZERO
	gun.angular_velocity = 0.0
	await _steps(1)
	var before := gun.global_rotation
	await _steps(15)
	_check("in free fall it turns toward nothing (%.3f rad)" % absf(gun.global_rotation - before),
		absf(gun.global_rotation - before) < 0.02)
	_check("and says nothing to him", not gun.is_threatening())
	gun.free()

func _it_turns_round_rather_than_upside_down() -> void:
	_suite("turning round")
	await _reset_buddy()
	# Held to his right, so it has to point left.
	var gun := _spawn(&"revolver", Vector2(1180, 480))
	await _steps(2)
	_grab(gun, Vector2(1180, 480), 0.0)
	await _steps(60)
	var top := -gun.global_transform.y.normalized() * (-1.0 if gun.is_flipped() else 1.0)
	_check("aimed left, it is mirrored", gun.is_flipped())
	_check("so its top is up (top %s)" % top, top.y < -0.5)
	_check("the barrel points at him (error %.1f deg)" % rad_to_deg(gun.aim_error()),
		absf(gun.aim_error()) < deg_to_rad(3.0) and gun.barrel_direction().x < 0.0)
	_check("and the sprite went with it", (gun.sprite as Sprite2D).flip_v)
	_drop(gun)
	gun.free()

# --- recoil ------------------------------------------------------------------

## Peak aim error after one shot, and frames until it is back under two degrees.
func _kick(gun: HeldGun) -> Array:
	await _settle_frames(gun, 60, deg_to_rad(1.0))
	gun._next_shot_msec = 0
	# A rotary gun's first round is the one after it has spun up; one round is what is measured,
	# so its shudder — a random jitter, which is the point in the hand — is noise here.
	if gun.spin_up > 0.0:
		gun._spin = 1.0
		gun._spun = true
		gun.spin_shudder = 0.0
	var fired := gun.fire()
	var peak := 0.0
	var back := -1
	for i in 60:
		await _steps(1)
		peak = maxf(peak, absf(gun.aim_error()))
		if back < 0 and i > 2 and absf(gun.aim_error()) < deg_to_rad(2.0):
			back = i + 1
	return [fired, peak, back]

func _recoil_kicks_and_the_aim_recovers() -> void:
	_suite("recoil")
	await _reset_buddy()
	# Far enough that a shot at him does not knock him about mid-measurement: he is out of
	# range for the pistols, so every one of these shots misses and only the kick is measured.
	var far := BUDDY_AT + Vector2(-1500, -60)
	_buddy.freeze = true
	for id in HARM:
		var gun := _spawn(id, far)
		await _steps(2)
		_grab(gun, far, 0.0)
		var k: Array = await _kick(gun)
		print("        %-15s kicks %.1f deg, back on him in %s s"
			% [id, rad_to_deg(k[1]), "never" if k[2] < 0 else "%.2f" % (k[2] / 60.0)])
		# A stream kicks a little per shot and climbs through the burst (asserted below); a
		# gun fired one shot at a time kicks hard.
		var floor_degrees := 1.5 if gun.auto_fire else 10.0
		_check("'%s' fires and kicks visibly (%.1f deg, at least %.1f)"
			% [id, rad_to_deg(k[1]), floor_degrees], k[0] and k[1] > deg_to_rad(floor_degrees))
		_check("'%s' recovers within a second" % id, k[2] > 0 and k[2] <= 60)
		_drop(gun)
		gun.free()
		await _steps(2)

	# The recoil node is read: ten levels of Steady Hand take the revolver's kick down.
	var gun := _spawn(&"revolver", far)
	await _steps(2)
	_grab(gun, far, 0.0)
	var plain: Array = await _kick(gun)
	_own(&"revolver")
	Economy.grant(Economy.BONES, 1.0e7)
	Progression.purchase_augment(&"revolver_steady", 10)
	var steady: Array = await _kick(gun)
	_check("Steady Hand is read: kick %.1f -> %.1f deg" % [rad_to_deg(plain[1]), rad_to_deg(steady[1])],
		steady[1] < plain[1] * 0.75)
	var slow := gun._interval()
	Progression.purchase_augment(&"revolver_rate", 10)
	_check("and the rate node shortens the gap (%.3f -> %.3f s)" % [slow, gun._interval()],
		gun._interval() < slow * 0.8)
	_drop(gun)
	gun.free()
	_buddy.freeze = false
	await _steps(2)

# --- the trigger ---------------------------------------------------------------

func _the_trigger_is_right_click_while_held() -> void:
	_suite("trigger")
	await _reset_buddy()
	var gun := _spawn(&"revolver", Vector2(400, 560))
	await _steps(20)
	_right(true)
	_right(false)
	await _steps(1)
	_check("a right-click on a gun lying on the desk does nothing", gun.shots_fired == 0
		and not gun.is_queued_for_deletion())
	_grab(gun, HAND, 0.0)
	await _steps(30)
	_right(true)
	_right(false)
	await _steps(1)
	_check("in the hand, right-click fires", gun.shots_fired == 1)
	_check("and the gesture says so", ItemDB.get_item(&"revolver").controls.contains("Right-click"))
	# Middle-click is the bin, and nothing may claim it — hovered, as the hand over its grip is.
	gun.drag_area.is_hovered = true
	gun._next_shot_msec = 0
	_right(true, false, MOUSE_BUTTON_MIDDLE)
	await _steps(1)
	_check("middle-click bins it instead of firing", not is_instance_valid(gun)
		or (gun.is_queued_for_deletion() and gun.shots_fired == 1))
	_held = null
	await _steps(2)

# --- paying ------------------------------------------------------------------

func _a_hit_pays_and_a_miss_does_not() -> void:
	_suite("a hit pays")
	await _reset_buddy()
	_own(&"revolver")
	var gun := _spawn(&"revolver", HAND)
	await _steps(2)
	_grab(gun, HAND, 0.0)
	await _settle_frames(gun, 60, deg_to_rad(1.0))
	# The multipliers now, before the shot: mood and grime move a moment after it (CLAUDE.md).
	var b := ItemDB.balance
	var damage := minf(EconomyMath.damage_from_impulse(gun.shot_force, b.min_damage_impulse,
		b.damage_per_impulse, gun.shot_damage_mult()), b.knockout_damage * b.max_hit_fraction)
	var expected := Economy.payout_for(damage * b.bones_per_damage * Economy.grime_multiplier(),
		&"revolver")
	_hits.clear()
	_payouts.clear()
	gun._next_shot_msec = 0
	_check("it fires", gun.fire())
	await _steps(3)
	var got := _paid(Economy.BONES, &"revolver")
	_check("a shot on him is a hit billed to the revolver", _hits.any(
		func(h: HitInfo) -> bool: return (h.source_id == &"revolver" and is_equal_approx(h.amount, damage))))
	_check("and pays the documented Bones (%.2f, expected %.2f)" % [got, expected],
		expected > 0.0 and absf(got - expected) <= expected * 0.01)

	# Knocked off him and fired before it recovers: the shot goes where the barrel points.
	await _reset_buddy()
	await _settle_frames(gun, 60, deg_to_rad(1.0))
	_hits.clear()
	_payouts.clear()
	gun.global_rotation -= 1.0
	gun._next_shot_msec = 0
	gun.fire()
	await _steps(3)
	_check("fired while knocked a radian off him, it misses (%d hits)" % _hits.size(),
		not _hits.any(func(h: HitInfo) -> bool: return h.source_id == &"revolver"))
	_check("and a miss pays nothing", _paid(Economy.BONES, &"revolver") == 0.0)
	_drop(gun)
	gun.free()
	await _steps(2)

## Consumes a right-button release before the world sees it, the way a panel does.
class ReleaseEater extends Node:
	var eaten := 0
	func _unhandled_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
			eaten += 1
			get_viewport().set_input_as_handled()

func _a_burst_climbs_and_stops_on_any_release() -> void:
	_suite("full auto")
	await _reset_buddy()
	var gun := _spawn(&"smg", HAND)
	await _steps(2)
	_grab(gun, HAND, 0.0)
	await _settle_frames(gun, 60, deg_to_rad(1.0))
	_right(true)
	var peak := 0.0
	for i in 60:
		await _steps(1)
		peak = maxf(peak, gun._climb)
	var shots := gun.shots_fired
	var expected := 1.0 / gun._interval()
	_check("holding right streams (%d shots in a second, about %.0f expected)" % [shots, expected],
		absf(float(shots) - expected) <= 3.0)
	_check("and the burst climbs (%.1f deg)" % rad_to_deg(peak), peak > gun.climb_per_shot * 3.0)
	var eater := ReleaseEater.new()
	eater.name = "ReleaseEater"
	add_child(eater)
	_right(false)
	await _steps(1)
	var at_release := gun.shots_fired
	await _steps(30)
	_check("a release something else consumed still stops it (eaten %d, %d shots after)"
		% [eater.eaten, gun.shots_fired - at_release],
		eater.eaten == 1 and not gun.trigger_held() and gun.shots_fired == at_release)
	await _steps(60)
	_check("and the climb bleeds away (%.1f deg)" % rad_to_deg(gun._climb), gun._climb < 0.01)
	eater.free()
	# Alt-tab with the trigger held and the release goes to the other window (D70). The stream
	# stops when the focus goes, not at the next click after the player comes back.
	_right(true)
	await _steps(10)
	_check("streaming again", gun.trigger_held() and gun.shots_fired > at_release)
	gun.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var at_focus := gun.shots_fired
	await _steps(30)
	_check("losing the focus lets the trigger go (%d shots after)" % (gun.shots_fired - at_focus),
		not gun.trigger_held() and gun.shots_fired == at_focus)
	_right(false)
	_drop(gun)
	gun.free()
	await _steps(2)
	await _a_held_power_lets_go_with_the_focus()

## The held cursor powers of D70: each ends its hold when the game loses focus, because the
## release it waits for goes to whichever window has the focus. Their hold flags, by id. (The
## minigun was one until D71 put it in your hand; its trigger is the check just above. D72's
## held spells are driven with real presses in powers_check.)
func _a_held_power_lets_go_with_the_focus() -> void:
	const HOLDS := {
		&"magnifying_glass": "_burning", &"open_hand": "_stroking", &"gravity_vortex": "_pulling",
	}
	for id in HOLDS:
		var item := ItemDB.get_item(id)
		if item == null or item.scene == null:
			_check("'%s' is a power" % id, false)
			continue
		var node := item.scene.instantiate()
		var power := node as CursorPowerBase
		if power == null:
			_check("'%s' is a cursor power" % id, false)
			node.free()
			continue
		_world.add_child(power)
		power.set(HOLDS[id], true)
		power.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		_check("the %s lets go when the focus goes" % id, power.get(HOLDS[id]) == false)
		power.free()

# --- him ---------------------------------------------------------------------

func _he_cowers_while_it_is_on_him() -> void:
	_suite("he notices")
	await _reset_buddy()
	var brain := _buddy.expression
	brain.clear()
	_threats.clear()
	var gun := _spawn(&"revolver", HAND)
	await _steps(2)
	_grab(gun, HAND, -PI * 0.5)
	await _steps(40)
	_check("pointed at him, it says so", _threats.any(
		func(t: Array) -> bool: return t[0] == &"aim" and float(t[1]) > 0.0))
	_check("and he cowers (beat '%s')" % brain.beat_id(), brain.beat_id() == &"aimed_at")
	_threats.clear()
	_drop(gun)
	await _steps(2)
	_check("put down, it says that too", _threats.any(
		func(t: Array) -> bool: return t[0] == &"aim" and float(t[1]) == 0.0))
	_check("and he stops (beat '%s')" % brain.beat_id(), brain.beat_id() != &"aimed_at")
	gun.free()
	# A kind gun is no threat at all.
	_threats.clear()
	var water := _spawn(&"water_pistol", HAND)
	await _steps(2)
	_grab(water, HAND, 0.0)
	await _steps(40)
	_check("a water pistol pointed at him is not a threat", _threats.is_empty())
	_drop(water)
	water.free()
	await _steps(2)

func _the_water_pistol_cleans_and_pays_hearts() -> void:
	_suite("water pistol")
	await _reset_buddy()
	_own(&"water_pistol")
	_buddy.grime.set_value(1.0)
	var hand := BUDDY_AT + Vector2(-200, -40)
	var gun := _spawn(&"water_pistol", hand)
	await _steps(2)
	_grab(gun, hand, 0.0)
	await _settle_frames(gun, 60, deg_to_rad(1.5))
	_payouts.clear()
	_sustained.clear()
	_hits.clear()
	_right(true)
	await _steps(90)
	_right(false)
	await _steps(2)
	_check("a second and a half of spray scrubs him (grime %.2f)" % _buddy.grime.value,
		_buddy.grime.value < 0.9)
	_check("and pays Hearts as sustained kindness (%.2f Hearts)" % _paid(Economy.HEARTS, &"water_pistol"),
		_sustained.any(func(s: Array) -> bool: return s[0] == &"water_pistol")
		and _paid(Economy.HEARTS, &"water_pistol") > 0.0)
	_check("and never Bones", _paid(Economy.BONES, &"water_pistol") == 0.0
		and not _hits.any(func(h: HitInfo) -> bool: return h.source_id == &"water_pistol"))
	_drop(gun)
	gun.free()
	_buddy.grime.set_value(0.0)
	await _steps(2)

func _bubbles_drift_to_him_and_pop_into_hearts() -> void:
	_suite("bubble blaster")
	await _reset_buddy()
	_own(&"bubble_blaster")
	var hand := BUDDY_AT + Vector2(-220, -40)
	var gun := _spawn(&"bubble_blaster", hand)
	await _steps(2)
	_grab(gun, hand, 0.0)
	await _settle_frames(gun, 60, deg_to_rad(2.0))
	_given.clear()
	_payouts.clear()
	_right(true)
	await _steps(30)
	_right(false)
	var blown := gun.shots_fired
	var popped := 0
	for i in 360:
		await _steps(1)
		popped = _given.filter(func(g: Array) -> bool: return g[0] == &"bubble_blaster").size()
		if popped >= blown:
			break
	_check("half a second of trigger blows bubbles (%d)" % blown, blown >= 2)
	_check("which reach him and pop as kind acts (%d of %d)" % [popped, blown], popped >= 1)
	_check("paying Hearts (%.2f)" % _paid(Economy.HEARTS, &"bubble_blaster"),
		_paid(Economy.HEARTS, &"bubble_blaster") > 0.0)
	_drop(gun)
	gun.free()
	await _steps(2)

## Thrown at him hard. A harm gun is a lump of metal and pays its contact multiplier; a kind
## one pays no Bones whatever it hits him with. The harm throw is the control: without it a
## throw that missed would pass the kind half.
func _a_kind_gun_thrown_at_him_pays_no_bones() -> void:
	_suite("thrown")
	for id in [&"revolver", &"water_pistol"]:
		await _reset_buddy()
		_hits.clear()
		_payouts.clear()
		var gun := _spawn(id, BUDDY_AT + Vector2(-160, -20))
		await _steps(2)
		gun.linear_velocity = Vector2(1800, -60)
		await _steps(40)
		var hit := _hits.any(func(h: HitInfo) -> bool: return h.source_id == id)
		if id == &"revolver":
			_check("a revolver thrown at him is a hit (the control)", hit)
		else:
			_check("a water pistol thrown at him is not", not hit)
			_check("and pays no Bones", _paid(Economy.BONES, id) == 0.0)
		gun.free()
		await _steps(2)

# --- D71: every gun is a gun you hold ---------------------------------------------------

## Shots of `id` billed to him since `_hits` was cleared.
func _hits_by(id: StringName) -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	for h in _hits:
		if h.source_id == id:
			out.append(h)
	return out

## A gun of `id`, bought, spawned at `hand` and picked up there, pointing at him and settled.
func _ready_gun(id: StringName, hand: Vector2) -> HeldGun:
	_own(id)
	var gun := _spawn(id, hand)
	await _steps(2)
	_grab(gun, hand, 0.0)
	await _settle_frames(gun, 60, deg_to_rad(1.5))
	return gun

func _put_away(gun: HeldGun) -> void:
	_right(false)
	await _steps(1)
	_drop(gun)
	if is_instance_valid(gun):
		gun.free()
	await _steps(2)

## Every gun: right on a gun lying on the desk does nothing, and right in the hand is its
## trigger — a shot, or for the minigun the barrels starting to turn.
func _every_trigger_is_right_click_while_held() -> void:
	_suite("every trigger")
	await _reset_buddy()
	for id in HARM + KIND:
		_own(id)
		var gun := _spawn(id, Vector2(420, 560))
		await _steps(20)
		_right(true)
		_right(false)
		await _steps(2)
		var idle := gun.shots_fired == 0 and gun.spin() == 0.0 and not gun.is_queued_for_deletion()
		_grab(gun, HAND, 0.0)
		await _settle_frames(gun, 45, deg_to_rad(2.0))
		_right(true)
		await _steps(3)
		var fired := gun.shots_fired >= 1
		if gun.spin_up > 0.0:
			fired = gun.shots_fired == 0 and gun.spin() > 0.0
		_check("'%s': nothing from right on the desk, and right in the hand %s" % [id,
			"spins it up" if gun.spin_up > 0.0 else "fires"], idle and fired)
		await _put_away(gun)

## The pistol, the shotgun and the minigun were cursor powers until D71. A save from the day
## before, loaded into the real autoloads: all three are guns in the Guns drawer that land on
## the desk rather than equip, the levels bought for them are read by the guns, their devices
## still run, their mastery is where it was, and a held pistol's shot is a Range Day round.
func _the_cursor_guns_are_guns_you_hold() -> void:
	_suite("the cursor guns, kept")
	var fixture = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/save_v4_cursor_guns.json"))
	_check("the pre-D71 fixture is readable", fixture is Dictionary)
	if not (fixture is Dictionary):
		return
	# Written today, so today's board is the one it was saved with and Range Day is on it; a
	# board a day old is re-rolled on load, and whether the pistol's job survives that is the
	# calendar's business, not this suite's.
	(fixture["contracts"] as Dictionary)["refreshed_at"] = int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(SaveManager.save_path().get_base_dir())
	var out := FileAccess.open(SaveManager.save_path(), FileAccess.WRITE)
	out.store_string(JSON.stringify(fixture))
	out.close()
	SaveManager.load_game()
	var spawner := ItemSpawner.new()
	spawner.name = "ItemSpawner"
	spawner.world = _world
	add_child(spawner)
	for id in [&"pistol", &"shotgun", &"minigun"]:
		var item := ItemDB.get_item(id)
		var body := item.scene.instantiate()
		_check("'%s' is still owned, and is a gun in the Guns drawer, not a cursor power" % id,
			Progression.is_unlocked(id) and item.category == ItemData.CATEGORY_GUN
			and not item.is_cursor_power() and body is HeldGun)
		body.free()
		EventBus.spawn_requested.emit(id, HAND)
		await _steps(2)
		var landed: HeldGun = null
		for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
			if node is HeldGun and (node as HeldGun).item_id == id:
				landed = node
		_check("and buying or spawning it puts it on the desk (armed: '%s')" % spawner.active_power(),
			landed != null and spawner.active_power() == &"")
		if landed:
			landed.bin_myself()
		await _steps(2)
	var gun := _spawn(&"pistol", HAND)
	var bought := pow(1.15, 4)
	_check("four levels of Hollow Point are read by the held pistol (x%.3f)" % (gun.shot_damage_mult()
		/ gun.shot_mult), is_equal_approx(gun.shot_damage_mult(), gun.shot_mult * bought))
	_check("and three of Quick Draw shorten its gap (%.3f s)" % gun._interval(),
		is_equal_approx(gun._interval(), gun.fire_interval * pow(0.94, 3)))
	gun.free()
	_check("its mastery is where it was (rank %d)" % Progression.mastery_rank(&"pistol"),
		Progression.mastery_rank(&"pistol") >= ItemDB.balance.mastery_automation_rank)
	var turret := ItemDB.get_augment(&"pistol_turret")
	_check("the Turret Mount still automates, at two levels, on a tripod now",
		turret.is_automation and Progression.augment_level(&"pistol_turret") == 2
		and Progression.is_automation_enabled(&"pistol_turret") and turret.device_mount == &"tripod")
	_check("the Trap Bench a player switched off stays off",
		not Progression.is_automation_enabled(&"shotgun_trap"))
	_check("and the three add their rates to Bones automation (%.1f/s)"
		% Progression.automation_rate_per_second(Economy.BONES),
		Progression.automation_rate_per_second(Economy.BONES) >= 2.0 * turret.automation_rate
		+ ItemDB.get_augment(&"minigun_sentry").automation_rate - 0.001)
	var before := Progression.contract_progress(&"daily_use_pistol")
	_check("Range Day is on the board, half done (%d)" % before, before == 120)
	await _reset_buddy()
	var pistol := await _ready_gun(&"pistol", HAND)
	pistol._next_shot_msec = 0
	pistol.fire()
	await _steps(2)
	_check("a held pistol's shot is a Range Day round (%d -> %d)" % [before,
		Progression.contract_progress(&"daily_use_pistol")],
		Progression.contract_progress(&"daily_use_pistol") == before + 1)
	await _put_away(pistol)
	spawner.free()
	_clear_slot()
	SaveManager.load_game()
	await _steps(2)

## Two barrels, then the break: two shots close together, a third pull that does nothing while
## it is open, and a shot again once it has closed.
func _the_double_barrel_breaks_open() -> void:
	_suite("sawn-off")
	await _reset_buddy()
	var gun := await _ready_gun(&"shotgun", BUDDY_AT + Vector2(-200, -40))
	_check("two in the barrels", gun.rounds_left() == 2)
	_right(true)
	_right(false)
	await _steps(int(ceil(gun._interval() * 60.0)) + 1)
	_right(true)
	_right(false)
	await _steps(2)
	_check("two pulls, two shots", gun.shots_fired == 2)
	_check("and it is open", gun.is_reloading(Time.get_ticks_msec()) and gun.rounds_left() == 0)
	_right(true)
	_right(false)
	await _steps(2)
	_check("a pull while it is open fires nothing", gun.shots_fired == 2)
	await _steps(int(ceil(gun._reload_seconds() * 60.0)) + 2)
	gun._next_shot_msec = 0
	_right(true)
	_right(false)
	await _steps(2)
	_check("closed again after %.1f s, it fires" % gun._reload_seconds(), gun.shots_fired == 3)
	await _put_away(gun)

## Nothing while the barrels wind up, then a stream that climbs; let go and it runs down; press
## again before it stops and it fires at once. The minigun's recoil is fought by feathering.
func _the_minigun_spins_up() -> void:
	_suite("minigun")
	await _reset_buddy()
	var gun := await _ready_gun(&"minigun", BUDDY_AT + Vector2(-320, -40))
	_hits.clear()
	_right(true)
	var first := -1
	for i in 90:
		await _steps(1)
		if first < 0 and gun.shots_fired > 0:
			first = i + 1
	var expected := gun._spin_up_seconds() * 60.0
	_check("nothing until the barrels are up to speed (first round at frame %d, spin-up %.0f)"
		% [first, expected], first >= int(expected) - 2 and first <= int(expected) + 3)
	var climbed := gun._climb
	var due := (90.0 - float(first)) / 60.0 / gun._interval()
	_check("then a stream (%d rounds in %.2f s, %.0f due)" % [gun.shots_fired, (90 - first) / 60.0,
		due], gun.shots_fired >= int(due) - 2)
	_check("that climbs (%.1f deg in under a second)" % rad_to_deg(climbed), climbed > 0.25)
	# Some of it: the climb walks the stream up off him, which is the point of the gun.
	_check("and hurts him (%d hits)" % _hits_by(&"minigun").size(), _hits_by(&"minigun").size() >= 3)
	_right(false)
	await _steps(12)
	_check("let go, it runs down rather than stopping (spin %.2f)" % gun.spin(),
		gun.spin() > 0.3 and gun.spin() < 1.0)
	var at := gun.shots_fired
	_right(true)
	await _steps(3)
	_check("pressed again before it stops, it fires at once (%d)" % (gun.shots_fired - at),
		gun.shots_fired > at)
	_right(false)
	await _steps(90)
	_check("left alone, it stops (spin %.2f)" % gun.spin(), gun.spin() == 0.0)
	await _put_away(gun)

## Fifty in the drum; empty, it pauses for the drum change and carries on.
func _the_tommy_gun_runs_dry() -> void:
	_suite("tommy gun")
	await _reset_buddy()
	var gun := await _ready_gun(&"tommy_gun", BUDDY_AT + Vector2(-260, -40))
	_check("fifty in the drum", gun.rounds_left() == 50)
	# The last few rounds, rather than a whole drum's worth of the suite's time.
	gun._rounds = 4
	_right(true)
	await _steps(30)
	_check("it fires what is left and stops (%d)" % gun.shots_fired, gun.shots_fired == 4)
	_check("to change the drum", gun.is_reloading(Time.get_ticks_msec()))
	await _steps(int(ceil(gun._reload_seconds() * 60.0)) + 6)
	_check("and carries on with a full one (%d)" % gun.shots_fired, gun.shots_fired > 4
		and gun.rounds_left() > 40)
	await _put_away(gun)

## A beam for as long as the gauge allows, then a lock, then the beam again.
func _the_ray_gun_overheats() -> void:
	_suite("ray gun")
	await _reset_buddy()
	var gun := await _ready_gun(&"ray_gun", BUDDY_AT + Vector2(-260, -40))
	_hits.clear()
	_right(true)
	var locked_at := -1
	for i in 240:
		await _steps(1)
		if gun.is_overheated(Time.get_ticks_msec()):
			locked_at = i
			break
	var burst := gun.shots_fired
	_check("held down, it burns until the gauge is full (%d ticks in %.2f s)" % [burst,
		locked_at / 60.0], locked_at > 0 and burst >= int(1.0 / gun.heat_per_shot))
	_check("each tick that touches him is a hit (%d)" % _hits_by(&"ray_gun").size(),
		_hits_by(&"ray_gun").size() >= burst / 2)
	_check("billed at its own impulse", _hits_by(&"ray_gun").all(
		func(h: HitInfo) -> bool: return is_equal_approx(h.raw_impulse, gun.shot_force)))
	await _steps(int(gun.overheat_lock * 60.0) - 6)
	_check("locked, it fires nothing (%d)" % (gun.shots_fired - burst), gun.shots_fired == burst)
	await _steps(12)
	_check("and cooled, it fires again (%d)" % (gun.shots_fired - burst), gun.shots_fired > burst)
	_right(false)
	await _put_away(gun)

## A lobbed grenade: the barrel tips up above the straight line to him, the grenade flies the
## arc, and it goes off on him, billed to the launcher at its shot multiplier.
func _the_grenade_lobs_and_goes_off() -> void:
	_suite("grenade launcher")
	await _reset_buddy()
	var hand := BUDDY_AT + Vector2(-340, -40)
	var gun := await _ready_gun(&"grenade_launcher", hand) as GrenadeLauncher
	var target := _buddy.global_transform * _buddy.center_of_mass
	var straight := (target - gun.muzzle_position()).angle()
	_check("it aims above the straight line, at the arc (%.1f deg above)"
		% rad_to_deg(straight - gun.global_rotation), gun.global_rotation < straight - deg_to_rad(4.0)
		and absf(gun.aim_error()) < deg_to_rad(3.0))
	_hits.clear()
	_payouts.clear()
	var from_x := _buddy.global_position.x
	gun._next_shot_msec = 0
	gun.fire()
	_check("a grenade is in the air", gun.grenades_in_flight() == 1)
	var gone := false
	for i in 150:
		await _steps(1)
		if gun.grenades_in_flight() == 0:
			gone = true
			break
	await _steps(3)
	var hits := _hits_by(&"grenade_launcher")
	_check("it goes off (%s)" % ("gone" if gone else "still flying"), gone)
	_check("on him: a hit billed to the launcher (%d)" % hits.size(), not hits.is_empty())
	if not hits.is_empty():
		var h := hits[0]
		var want := h.raw_impulse * ItemDB.balance.damage_per_impulse * gun.shot_damage_mult()
		_check("at its shot multiplier (%.2f damage from %.0f)" % [h.amount, h.raw_impulse],
			is_equal_approx(h.amount, minf(want, ItemDB.balance.knockout_damage
				* ItemDB.balance.max_hit_fraction)))
	_check("paying Bones (%.2f)" % _paid(Economy.BONES, &"grenade_launcher"),
		_paid(Economy.BONES, &"grenade_launcher") > 0.0)
	_check("and it throws him (%.0f px)" % absf(_buddy.global_position.x - from_x),
		absf(_buddy.global_position.x - from_x) > 20.0 or _buddy.linear_velocity.length() > 100.0)
	await _put_away(gun)

## A flare sticks in him and burns: a tick every `burn_every` for `burn_time`, each a hit at
## the burn's impulse, and then it goes out and is gone.
func _the_flare_sticks_and_burns() -> void:
	_suite("flare gun")
	await _reset_buddy()
	var gun := await _ready_gun(&"flare_gun", BUDDY_AT + Vector2(-240, -40)) as FlareGun
	_hits.clear()
	gun._next_shot_msec = 0
	gun.fire()
	var flare: FlareGun.Flare = null
	for i in 60:
		await _steps(1)
		for node in _world.get_children():
			if node is FlareGun.Flare:
				flare = node
		if flare and flare.stuck_to() == _buddy:
			break
	_check("the flare sticks in him", flare != null and flare.stuck_to() == _buddy)
	# A hit is dealt on his next physics frame, not the one it was billed in.
	await _steps(2)
	var strike := _hits_by(&"flare_gun").size()
	_check("the strike is a hit (%d)" % strike, strike >= 1)
	var frames := int(ceil(gun.burn_time * 60.0)) + 10
	for i in frames:
		await _steps(1)
		if not is_instance_valid(flare):
			break
	var burns := _hits_by(&"flare_gun").filter(
		func(h: HitInfo) -> bool: return is_equal_approx(h.raw_impulse, gun.burn_force))
	var want := int(gun.burn_time / gun.burn_every)
	_check("it burns: %d ticks, %d expected" % [burns.size(), want], absi(burns.size() - want) <= 1)
	_check("each at the burn's own impulse and the shot's multiplier", burns.all(
		func(h: HitInfo) -> bool: return is_equal_approx(h.amount,
			gun.burn_force * ItemDB.balance.damage_per_impulse * gun.shot_damage_mult())))
	_check("and then it has gone out", not is_instance_valid(flare) and gun.flares_burning() == 0)
	await _put_away(gun)

## The harpoon: it sticks, the strike is a hit, holding right reels him in until it tears out
## (the second hit) and winds home; walking away with it pulls him along; dropping the gun lets
## go of the line.
func _the_harpoon_reels_him_in() -> void:
	_suite("harpoon gun")
	await _reset_buddy()
	var hand := BUDDY_AT + Vector2(-330, -30)
	var gun := await _ready_gun(&"harpoon_gun", hand) as HarpoonGun
	_hits.clear()
	_right(true)
	_right(false)
	var stuck := false
	for i in 40:
		await _steps(1)
		if gun.harpoon_in_him():
			stuck = true
			break
	_check("the harpoon sticks in him", stuck)
	await _steps(2)
	_check("the strike is a hit at its impulse", _hits_by(&"harpoon_gun").any(
		func(h: HitInfo) -> bool: return is_equal_approx(h.raw_impulse, gun.shot_force)))
	_check("the harpoon is out of the gun, and the gun shows it", gun.harpoon_out()
		and gun.loaded_sprite != null and not gun.loaded_sprite.visible)
	await _steps(20)
	var start := _buddy.global_position.distance_to(hand)
	_right(true)
	var closest := start
	var tore := false
	for i in 150:
		await _steps(1)
		closest = minf(closest, _buddy.global_position.distance_to(hand))
		if gun.rips > 0:
			tore = true
			break
	_right(false)
	await _steps(2)
	_check("holding right reels him in (%.0f -> %.0f px)" % [start, closest], closest < start - 120.0)
	_check("until it tears out: a second hit", tore and _hits_by(&"harpoon_gun").any(
		func(h: HitInfo) -> bool: return is_equal_approx(h.raw_impulse, gun.shot_force * gun.rip_share)))
	var home := false
	for i in 60:
		await _steps(1)
		if not gun.harpoon_out():
			home = true
			break
	_check("and winds home, loaded again", home and gun.loaded_sprite.visible)

	# On the line, without reeling: the gun walked away, and he comes too.
	await _reset_buddy()
	await _settle_frames(gun, 60, deg_to_rad(1.5))
	gun._next_shot_msec = 0
	_right(true)
	_right(false)
	for i in 40:
		await _steps(1)
		if gun.harpoon_in_him():
			break
	await _steps(30)
	var was := _buddy.global_position.x
	for i in 50:
		_hand.x -= 5.0
		await _steps(1)
	await _steps(10)
	_check("walked 250 px away with it, he is pulled along (%.0f px)" % (was - _buddy.global_position.x),
		gun.harpoon_in_him() and was - _buddy.global_position.x > 60.0)
	_drop(gun)
	await _steps(2)
	_check("dropped, the gun lets go of the line", not gun.harpoon_in_him())
	for i in 60:
		await _steps(1)
		if not gun.harpoon_out():
			break
	_check("and the harpoon winds home", not gun.harpoon_out())
	gun.free()
	await _steps(2)

## Foam darts: each that meets him sticks to him and is one kind act worth the dart's value;
## no Bones, no hits; six to a load; and they drop off him in their own time.
func _foam_darts_stick_to_him() -> void:
	_suite("foam dart blaster")
	await _reset_buddy()
	var gun := await _ready_gun(&"foam_dart_blaster", BUDDY_AT + Vector2(-220, -40)) as DartBlaster
	_given.clear()
	_payouts.clear()
	_hits.clear()
	for i in 3:
		gun._next_shot_msec = 0
		_right(true)
		_right(false)
		await _steps(20)
	await _steps(20)
	var acts := _given.filter(func(g: Array) -> bool: return g[0] == &"foam_dart_blaster")
	_check("darts stick to him (%d of %d)" % [gun.darts_on_him(), gun.shots_fired],
		gun.darts_on_him() >= 2 and gun.shots_fired == 3)
	_check("each one stuck is one kind act (%d)" % acts.size(), acts.size() == gun.darts_on_him())
	_check("worth the dart's value", acts.all(func(g: Array) -> bool:
		return is_equal_approx(float(g[1]), gun.dart_value * gun.value_multiplier())))
	_check("paying Hearts (%.2f) and never Bones" % _paid(Economy.HEARTS, &"foam_dart_blaster"),
		_paid(Economy.HEARTS, &"foam_dart_blaster") > 0.0
		and _paid(Economy.BONES, &"foam_dart_blaster") == 0.0 and _hits_by(&"foam_dart_blaster").is_empty())
	_check("and never a threat", not gun.is_threatening())
	for i in 3:
		gun._next_shot_msec = 0
		_right(true)
		_right(false)
		await _steps(1)
	_check("six to a load, then it reloads", gun.shots_fired == 6 and gun.is_reloading(Time.get_ticks_msec()))
	for node in _world.get_children():
		if node is DartBlaster.Dart and (node as DartBlaster.Dart).stuck_to() == _buddy:
			node.set("_drop_at", 0.0)
	await _steps(3)
	_check("their time up, they drop off him (%d left)" % gun.darts_on_him(), gun.darts_on_him() == 0)
	await _put_away(gun)
	var left := 0
	for node in _world.get_children():
		if node is DartBlaster.Dart and not node.is_queued_for_deletion():
			left += 1
	_check("and a blaster put away takes its darts with it (%d left)" % left, left == 0)

## The Steady node on the minigun, the gun whose recoil is the point: ten levels take its
## kick down, measured the same way as the revolver's.
func _steady_is_read_on_the_new_guns() -> void:
	_suite("steady, on the new guns")
	var far := BUDDY_AT + Vector2(-1500, -60)
	_buddy.freeze = true
	for id in [&"minigun", &"tommy_gun", &"harpoon_gun"]:
		var gun := _spawn(id, far)
		await _steps(2)
		_grab(gun, far, 0.0)
		var plain: Array = await _kick(gun)
		_own(id)
		Economy.grant(Economy.BONES, 1.0e8)
		Progression.purchase_augment(StringName("%s_steady" % id), 10)
		gun._next_shot_msec = 0
		var steady: Array = await _kick(gun)
		_check("'%s': Steady is read (kick %.1f -> %.1f deg)" % [id, rad_to_deg(plain[1]),
			rad_to_deg(steady[1])], steady[1] < plain[1] * 0.8)
		_drop(gun)
		gun.free()
		await _steps(2)
	_buddy.freeze = false
	await _steps(2)

# --- harness -----------------------------------------------------------------

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _suite(name_: String) -> void:
	print("")
	print("  %s" % name_)

func _check(what: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("    ok   %s" % what)
	else:
		_failed += 1
		printerr("    FAIL %s" % what)
