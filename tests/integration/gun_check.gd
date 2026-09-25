extends Node

## The held guns (docs/decisions.md D56), against real physics and the real payout pipeline.
##
##   Godot --headless --path <project> res://tests/integration/gun_check.tscn
##
## A scene rather than a `-s` script because it needs the autoloads, and it builds its own
## floor: a headless viewport is 64x64, so nothing here may lean on WorldBounds. Runs against
## its own save slot and its own settings file, and clears both.
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
const HARM := [&"revolver", &"smg", &"pump_shotgun", &"hunting_rifle", &"blunderbuss"]
const KIND := [&"water_pistol", &"bubble_blaster"]

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

func _right(pressed: bool, shift: bool = false) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
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
	# Shift+right is the bin, and nothing may claim it — hovered, as the hand over its grip is.
	gun.drag_area.is_hovered = true
	gun._next_shot_msec = 0
	_right(true, true)
	await _steps(1)
	_check("Shift+right bins it instead of firing", not is_instance_valid(gun)
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
	_drop(gun)
	gun.free()
	await _steps(2)

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
