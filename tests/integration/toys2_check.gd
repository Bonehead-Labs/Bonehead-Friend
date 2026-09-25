extends Node

## Headless check of the second five fidget toys (docs/decisions.md D66): the slinky, the
## Newton's cradle, the pull-back car, the yo-yo and the slingshot — every gesture each one
## takes, what it pays and through which road, what he does with it, and that it costs nothing
## at rest.
##
##   Godot --headless --path <project> res://tests/integration/toys2_check.tscn
##
## Built the way `fidget_check` is: the real game in a SubViewport, and every gesture a
## synthetic event at a real position, down the road real events take — the viewport,
## `BaseDraggable._unhandled_input`, `GestureZones`. Where a line calls a toy directly instead
## (a fast-forwarded swing, a yo-yo put next to him at a known speed), it says why.
##
## Its own save slot and its own settings file, and it puts back what it pins. `_check(what,
## ok)` takes two arguments, like loop_check's — a third is a parse error, and a parse error
## here looks like a hang (CLAUDE.md).

const TEST_SLOT := "toys2_check_slot"
const VIEW_SIZE := Vector2i(1100, 700)
const TOYS: Array[StringName] = [&"slinky", &"newtons_cradle", &"pull_back_car", &"yo_yo",
	&"slingshot"]
const KIND: Array[StringName] = [&"slinky", &"newtons_cradle", &"pull_back_car"]

var _passed := 0
var _failed := 0
var _view: SubViewport
var _main: Node
var _restore := {}
var _buddy: Buddy
var _face: ExpressionBrain
var _idle: IdleBrain
var _spawner: ItemSpawner

var _mask := 0
var _mouse := Vector2.ZERO

## What the bus carried while a toy was being watched. Members, not locals: a lambda captures
## locals by value (CLAUDE.md).
var _hits: Array[HitInfo] = []
var _acts: Array = []
var _trickles: Array = []
var _beats: Array[StringName] = []
var _only: PackedStringArray = []

func _want(suite: String) -> bool:
	return _only.is_empty() or _only.has(suite)

func _ready() -> void:
	# Before anything else (D51): putting a toy down can fire a one-off hint, which saves.
	Settings.config_path = "user://settings_toys2_check.cfg"
	_restore = {
		"focus": Settings.focus_intensity,
		"scale": Settings.ui_scale,
		"hud_pinned": Settings.hud_pinned,
		"tabs_pinned": Settings.tabs_pinned,
		"hints": Settings.hints_seen.duplicate(),
	}
	Settings.focus_intensity = Settings.Intensity.OFF
	Settings.ui_scale = 1
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()

	print("")
	print("Bonehead Friend — toys2 check")
	print("=============================")

	_view = SubViewport.new()
	_view.size = VIEW_SIZE
	_view.handle_input_locally = true
	_view.physics_object_picking = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_view.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
	_main = load("res://main.tscn").instantiate()
	_view.add_child(_main)
	await _settle()

	_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	_idle = get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	_spawner = get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	_face = _buddy.expression if _buddy else null
	if _buddy == null or _idle == null or _spawner == null or _face == null:
		_check("the game booted with a buddy, both brains and a spawner", false)
		_finish()
		return
	Economy.grant(Economy.HEARTS, 2.0e6)
	Economy.grant(Economy.BONES, 2.0e6)
	for id in TOYS:
		var item := ItemDB.get_item(id)
		if item:
			for req in item.requires:
				Progression.purchase_item(req)
		Progression.purchase_item(id)
	EventBus.damage_dealt.connect(func(info: HitInfo) -> void: _hits.append(info))
	EventBus.kindness_given.connect(func(id: StringName, value: float, _at: Vector2) -> void:
		_acts.append([id, value]))
	EventBus.kindness_sustained.connect(func(id: StringName, value: float, _at: Vector2) -> void:
		_trickles.append([id, value]))

	# `-- --only=slinky,car` runs those suites and no others, while working on one toy.
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--only="):
			_only = String(arg).trim_prefix("--only=").split(",", false)
	if _want("content"):
		_the_toys_are_content()
		_his_face_has_rows_for_them()
	if _want("slinky"):
		await _the_slinky_boings()
		await _the_slinky_walks()
	if _want("cradle"):
		await _the_cradle_clacks()
	if _want("car"):
		await _the_car_winds_and_gives_rides()
	if _want("yoyo"):
		await _the_yo_yo_sleeps_and_bonks()
	if _want("slingshot"):
		await _the_slingshot_draws_and_fires()
	if _want("zones"):
		await _zones_follow_a_turned_body()
		await _hover_shows_what_is_a_button()
	if _want("focus"):
		await _a_gesture_outlives_a_panel_but_not_the_focus()
	if _want("bin"):
		await _shift_right_always_bins()
	if _want("rest"):
		await _nothing_runs_at_rest()
	if _want("him"):
		await _he_plays_with_the_kind_ones()
	_finish()

func _finish() -> void:
	_spawner_clear()
	print("")
	print("=============================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_clear_slot()
	Settings.focus_intensity = _restore["focus"]
	Settings.ui_scale = _restore["scale"]
	Settings.hud_pinned = _restore["hud_pinned"]
	Settings.tabs_pinned = _restore["tabs_pinned"]
	Settings.hints_seen = _restore["hints"]
	Settings.save_settings()
	get_tree().quit(1 if _failed > 0 else 0)

# --- content ---------------------------------------------------------------------

func _the_toys_are_content() -> void:
	_suite("content")
	for id in TOYS:
		var item := ItemDB.get_item(id)
		_check("%s is in the shop" % id, item != null)
		if item == null:
			continue
		var kind := KIND.has(id)
		_check("%s is on the %s side, priced in %s" % [id, "kind" if kind else "harm",
			"Hearts" if kind else "Bones"], item.is_kind() == kind
			and item.currency == (ItemData.CURRENCY_HEARTS if kind else ItemData.CURRENCY_BONES))
		_check("%s says how to work it" % id, not item.controls.is_empty())
		_check("%s has a picture and an icon" % id, item.icon != null
			and ResourceLoader.exists("res://Assets/sprites/items/%s.png" % id))
		var keys := {}
		var capstone := false
		for node in ItemDB.augments_for(id):
			if node.is_automation:
				capstone = true
				continue
			keys[node.effect_key] = true
			_check("%s's %s is bought with the drawer's currency" % [id, node.id],
				node.currency == (AugmentNode.CURRENCY_HEARTS if kind else AugmentNode.CURRENCY_BONES))
		_check("%s has a tree of value, payout and pace, and a capstone" % id,
			keys.has(&"damage_mult") and keys.has(&"payout_mult") and keys.has(&"cooldown_mult")
			and keys.size() == 3 and capstone)
	_check("the slinky and the car are in Play, the cradle in Mood",
		ItemDB.get_item(&"slinky").category == ItemData.CATEGORY_TOY
		and ItemDB.get_item(&"pull_back_car").category == ItemData.CATEGORY_TOY
		and ItemDB.get_item(&"newtons_cradle").category == ItemData.CATEGORY_AMBIENCE)
	_check("the yo-yo is Melee and the slingshot a Gun",
		ItemDB.get_item(&"yo_yo").category == ItemData.CATEGORY_WEAPON
		and ItemDB.get_item(&"slingshot").category == ItemData.CATEGORY_GUN)

func _his_face_has_rows_for_them() -> void:
	_suite("his face")
	for event in [&"boing", &"clacking", &"yoyo_trick", &"ride", &"spinning"]:
		var row: StringName = ExpressionBrain.FIDGET_ROWS.get(event, &"")
		_check("'%s' has a row (%s) and the row exists" % [event, row],
			row != &"" and ExpressionBrain.ROWS.has(row))

# --- the slinky ---------------------------------------------------------------------

func _the_slinky_boings() -> void:
	_suite("slinky")
	# On the floor first: at boot he is still dropping in from his authored spawn point, and a
	# toy put "beside him" then is put in mid-air.
	await _stand_him_up(Vector2(640, 560))
	var slinky := await _fresh(&"slinky", _beside_him(-240.0)) as Slinky
	if slinky == null:
		_check("a slinky is on the desk", false)
		return
	await _frames(20)
	_check("at rest it is a stack and runs no frame", slinky.is_compact() and not slinky.is_processing())

	# In the hand: hold right and pull, and the end it is held by stays put.
	var at := slinky.global_position
	await _hover(at)
	_press(at)
	_check("left picks it up by an end", slinky.dragging)
	await _frames(4)
	var grip := slinky.global_position
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_check("right while holding it plants that end", slinky.stretching() and slinky.freeze)
	_move(_mouse + Vector2(40, -150))
	await _frames(3)
	_check("pulling the cursor away stretches the coil (%.0f px)" % slinky.stretch(),
		slinky.stretch() > 120.0)
	_check("and the planted end did not move", slinky.global_position.distance_to(grip) < 2.0)
	var rings := _rings_of(slinky)
	_check("the coil is drawn and the stack is not", slinky.coil.visible and not slinky.sprite.visible)
	_check("from the planted end to the cursor", rings.size() >= 2
		and rings[0].global_position.distance_to(slinky.global_position) < 3.0
		and rings[-1].global_position.distance_to(_mouse) < 3.0)
	await _clear_combo()
	_acts.clear()
	var hearts := Economy.balance_of(Economy.HEARTS)
	var share := clampf(slinky.stretch() / slinky._full_stretch(), 0.0, 1.0)
	var value := slinky.boing_value * (0.25 + 0.75 * share) * slinky.value_multiplier()
	var expected := _expected_act(value, &"slinky")
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("letting go of right boings it", slinky.boings == 1)
	_check("as one kind act worth the stretch (%s)" % str(_acts),
		_acts.size() == 1 and is_equal_approx(float(_acts[0][1]), value))
	_check_near("paid in Hearts through the pipeline", Economy.balance_of(Economy.HEARTS) - hearts, expected)
	_check("and the planted end springs back into the hand", not slinky.freeze
		and not slinky.stretching() and not slinky.is_compact())
	var home := false
	for i in 90:
		await get_tree().physics_frame
		if slinky.is_compact():
			home = true
			break
	_check("where it is a stack again, and stops drawing", home and not slinky.is_processing())
	_release(_mouse)
	await _frames(40)

	# On the desk: right-drag it where it lies, and the far end springs back onto it.
	at = slinky.global_position
	_acts.clear()
	_press(at, MOUSE_BUTTON_RIGHT)
	_check("a right-press on it where it lies plants it", slinky.stretching() and not slinky.dragging)
	_move(at + Vector2(90, -110))
	_check("and a drag stretches it (%.0f px)" % slinky.stretch(), slinky.stretch() > 100.0)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("letting go boings it again, and pays", slinky.boings == 2 and _acts.size() == 1)
	var settled := false
	for i in 150:
		await get_tree().physics_frame
		if slinky.is_compact():
			settled = true
			break
	_check("the far end springs back onto it and it is a stack", settled and not slinky.is_processing())
	_check("and the end it lay on never moved (%.1f px)" % slinky.global_position.distance_to(at),
		slinky.global_position.distance_to(at) < 3.0)
	_check("and it was never binned by the right button", slinky.is_inside_tree())

	# A tug too short to be a stretch neither boings nor pays.
	_acts.clear()
	_press(at, MOUSE_BUTTON_RIGHT)
	_move(at + Vector2(8, -6))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("a tug is not a stretch: no boing, no pay", slinky.boings == 2 and _acts.is_empty()
		and slinky.is_compact())

	# "Looser Coil": the same pull is worth more of a full boing.
	var before := slinky._full_stretch()
	var node := _node_for(&"slinky", &"cooldown_mult")
	if node:
		Progression.purchase_augment(node.id, 3)
	_check("Looser Coil makes a full boing a shorter pull (%.0f -> %.0f)"
		% [before, slinky._full_stretch()], slinky._full_stretch() < before)

	# He plucks it himself: a boing he did, paid as his trickle, not as an act.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	_acts.clear()
	_trickles.clear()
	var his := slinky.boings
	slinky.idle_use(_buddy)
	_check("left alone with it, he plucks it and it boings", slinky.boings == his + 1
		and _acts.is_empty())
	await _frames(40)
	_check("and it pays him a trickle", _trickles.any(func(t: Array) -> bool: return t[0] == &"slinky"))
	await _frames(60)
	Settings.focus_intensity = Settings.Intensity.OFF
	var still := slinky.global_position
	_trickles.clear()
	slinky.idle_use(_buddy)
	await _frames(35)
	_check("at Focus Off his pluck pays and nothing moves", slinky.is_compact()
		and slinky.global_position.distance_to(still) < 1.0
		and _trickles.any(func(t: Array) -> bool: return t[0] == &"slinky"))
	_spawner_clear()

func _the_slinky_walks() -> void:
	_suite("slinky walks")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	var slinky := await _fresh(&"slinky", Vector2(_buddy.global_position.x - 420.0, 600.0)) as Slinky
	if slinky == null:
		_check("a slinky is on the desk", false)
		return
	await _frames(20)
	# Thrown: picked up, carried up and flung sideways, let go.
	var at := slinky.global_position
	await _hover(at)
	_press(at)
	for i in 8:
		_move(_mouse + Vector2(0, -12))
		await get_tree().physics_frame
	for i in 5:
		_move(_mouse + Vector2(26, 0))
		await get_tree().physics_frame
	_release(_mouse)
	var walked := false
	for i in 240:
		await get_tree().physics_frame
		if slinky.steps_walked > 0:
			walked = true
		if walked and not slinky.is_walking():
			break
	_check("thrown, it lands and walks end over end (%d steps)" % slinky.steps_walked, walked)
	_check("and stops, a stack again, running no frame", slinky.is_compact()
		and not slinky.is_processing())
	# Directly, for the count: each step is a span, and a trickle.
	_trickles.clear()
	var from := slinky.global_position
	slinky.walk(2, -1.0)
	for i in 90:
		await get_tree().process_frame
		if not slinky.is_walking():
			break
	await _frames(40)
	_check("two steps left move it two spans (%.0f px)" % (from.x - slinky.global_position.x),
		from.x - slinky.global_position.x >= slinky.walk_span * 1.5)
	_check("and a walk trickles", _trickles.any(func(t: Array) -> bool: return t[0] == &"slinky"))
	Settings.focus_intensity = Settings.Intensity.OFF
	from = slinky.global_position
	slinky.walk(3, 1.0)
	_check("at Focus Off it does not walk", not slinky.is_walking()
		and slinky.global_position.distance_to(from) < 1.0)
	_spawner_clear()

# --- the cradle ---------------------------------------------------------------------

func _the_cradle_clacks() -> void:
	_suite("Newton's cradle")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	var cradle := await _fresh(&"newtons_cradle", _beside_him(-190.0)) as NewtonsCradle
	if cradle == null:
		_check("a cradle is on the desk", false)
		return
	await _frames(30)
	_check("at rest it runs no frame", not cradle.is_processing() and not cradle.is_swinging())
	_face.clear()
	_trickles.clear()
	var uses := [0]
	var probe := func(key: StringName, count: int) -> void:
		if key == &"use:newtons_cradle":
			uses[0] += count
	EventBus.contract_event.connect(probe)
	var ball := cradle.gestures.zone_world(&"ball_l")
	_press(ball, MOUSE_BUTTON_RIGHT)
	_move(ball + Vector2(-26, -10))
	_move(ball + Vector2(-34, -16))
	_check("right-dragging the left ball out swings it out (%.0f deg)"
		% rad_to_deg(cradle.ball_angle(0)), cradle.ball_angle(0) > deg_to_rad(20.0)
		and cradle.ball_angle(0) <= NewtonsCradle.MAX_PULL + 0.001)
	_check("and nothing else moves yet", is_zero_approx(cradle.ball_angle(4)))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	EventBus.contract_event.disconnect(probe)
	_check("letting go sets it swinging, and only now does it run a frame", cradle.is_swinging()
		and cradle.is_processing())
	_check("the pull is the player's use of it", uses[0] == 1)
	var first := cradle.amplitude()
	var answered := false
	var calmed := false
	for i in 150:
		await get_tree().process_frame
		answered = answered or cradle.ball_angle(4) < -deg_to_rad(5.0)
		calmed = calmed or _face.beat_id() == &"calmed"
	_check("the far ball answers (%d clacks)" % cradle.clacks, answered and cradle.clacks >= 2)
	_check("each clack a little softer (%.2f -> %.2f)" % [first, cradle.amplitude()],
		cradle.amplitude() < first)
	_check("and each a Hearts trickle, not an act", _trickles.any(func(t: Array) -> bool:
		return t[0] == &"newtons_cradle"))
	_check("he watches it and is calmed by it", calmed)
	# Runs down over the best part of half a minute. Fast-forwarded.
	var seconds := 0.0
	while cradle.is_swinging() and seconds < 120.0:
		cradle._process(0.05)
		seconds += 0.05
	_check("it runs down in about half a minute (%.0f s)" % seconds, seconds >= 8.0 and seconds <= 45.0)
	_check("comes to rest hanging straight, and stops running frames", not cradle.is_processing()
		and is_zero_approx(cradle.ball_angle(0)) and is_zero_approx(cradle.ball_angle(4)))
	# "Harder Steel" loses less a clack.
	var kept := cradle._kept()
	var node := _node_for(&"newtons_cradle", &"cooldown_mult")
	if node:
		Progression.purchase_augment(node.id, 3)
	_check("Harder Steel keeps more of each clack (%.3f -> %.3f)" % [kept, cradle._kept()],
		cradle._kept() > kept)
	# A nudge is not a pull.
	ball = cradle.gestures.zone_world(&"ball_r")
	_press(ball, MOUSE_BUTTON_RIGHT)
	_move(ball + Vector2(2, 0))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("a nudge sets nothing going", not cradle.is_swinging())
	# He pulls a ball himself when it is still.
	var still_appeal := cradle.idle_appeal()
	cradle.idle_use(_buddy)
	_check("left alone with a still one, he sets it going", cradle.is_swinging())
	# Swinging is not "nothing to do here" (D70): the brain reads a zero as exactly that, and a
	# cradle he set going on his last tick at it was never a destination again.
	_check("and swinging it is still somewhere to go (%.3f, still %.3f)"
		% [cradle.idle_appeal(), still_appeal], cradle.idle_appeal() > 0.0
		and is_equal_approx(cradle.idle_appeal(), still_appeal))
	cradle._stop()
	Settings.focus_intensity = Settings.Intensity.OFF
	_trickles.clear()
	cradle.idle_use(_buddy)
	await _frames(35)
	_check("at Focus Off it pays without a ball moving", not cradle.is_swinging()
		and _trickles.any(func(t: Array) -> bool: return t[0] == &"newtons_cradle"))
	_spawner_clear()

# --- the car -------------------------------------------------------------------------

func _the_car_winds_and_gives_rides() -> void:
	_suite("pull-back car")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	await _stand_him_up(Vector2(700, 560))
	var car := await _fresh(&"pull_back_car", Vector2(_buddy.global_position.x - 230.0, 600.0)) as PullBackCar
	if car == null:
		_check("a car is on the desk", false)
		return
	await _frames(30)
	_check("at rest it runs no frame and is not driving", not car.is_processing() and not car.is_driving())
	var start := car.global_position
	var at := car.global_position
	_press(at, MOUSE_BUTTON_RIGHT)
	_check("a right-press on it starts the wind", car.is_winding())
	for i in 18:
		_move(_mouse + Vector2(-10, 0))
	_check("dragging it away from him turns it to face him", is_equal_approx(car.facing, 1.0))
	_check("and winds it a notch at a time, to full (%d notches)" % car.notches(),
		car.notches() == PullBackCar.NOTCHES and is_equal_approx(car.charge, 1.0))
	_check("rolling it back under the hand (%.0f px)" % (start.x - car.global_position.x),
		start.x - car.global_position.x > 100.0)
	_move(_mouse + Vector2(30, 0))
	_check("and pushing it forward unwinds nothing: it is a ratchet",
		car.notches() == PullBackCar.NOTCHES)
	await _clear_combo()
	_acts.clear()
	var hearts := Economy.balance_of(Economy.HEARTS)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("letting go launches it", car.is_driving() and not car.is_winding() and not car.freeze)
	var hopped := false
	var rode := false
	var fastest := 0.0
	for i in 240:
		await get_tree().physics_frame
		fastest = maxf(fastest, car.linear_velocity.x)
		hopped = hopped or car.is_hopping()
		if car.is_riding():
			rode = true
			break
	_check("it zooms at him (%.0f px/s)" % fastest, fastest > 200.0)
	_check("and he hops on", hopped)
	_check("and lands on the roof for a ride", rode)
	if rode:
		var ride := car.ride_value * 1.0 * car.value_multiplier()
		_check("the ride is one kind act, worth the wind (%s)" % str(_acts),
			_acts.size() == 1 and is_equal_approx(float(_acts[0][1]), ride))
		_check("paid in Hearts", Economy.balance_of(Economy.HEARTS) > hearts)
		var feet := _buddy.get_interaction_rect().end.y
		_check("he is on top of it (feet %.0f, roof %.0f)" % [feet, car._roof_y()],
			absf(feet - car._roof_y()) <= PullBackCar.ROOF_SLACK + 4.0)
		var carried := _buddy.global_position.x
		await _frames(30)
		_check("and it carries him along (%.0f px)" % (_buddy.global_position.x - carried),
			_buddy.global_position.x - carried > 30.0)
		var ended := false
		for i in 180:
			await get_tree().physics_frame
			if not car.is_riding():
				ended = true
				break
		_check("then the ride ends and he hops off", ended and not car.freeze
			and car.get_children().filter(func(n: Node) -> bool: return n is PinJoint2D).is_empty())
	await _frames(60)

	# Twelve turns a second is more than a frame can show (D75): driving, the wheels spin over a
	# blur, and at Low Power's 20 fps are drawn turning under half a turn a frame, where the
	# one bolt would otherwise read as turning backwards. Stopped, they are crisp again.
	var focus := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL
	car._turn_wheels(car.max_speed / 60.0, 1.0 / 60.0)
	var blurred := car._wheel_blurs.filter(func(b: RotorBlur) -> bool: return b.is_blurred()).size()
	_check("flat out, both wheels spin over a blur (%d)" % blurred, blurred == 2)
	var from_angle := car.rear_wheel.rotation
	car._turn_wheels(car.max_speed / 20.0, 1.0 / 20.0)
	var turned := absf(car.rear_wheel.rotation - from_angle)
	_check("and at 20 fps a wheel is drawn turning forward, under half a turn (%.0f deg for %.0f)"
		% [rad_to_deg(turned), rad_to_deg(car.max_speed / 20.0 / PullBackCar.WHEEL_RADIUS)],
		turned > 0.0 and turned < PI)
	car._turn_wheels(0.0)
	_check("stopped, they are crisp", car._wheel_blurs.all(func(b: RotorBlur) -> bool: return not b.is_blurred()))
	Settings.focus_intensity = focus

	# A wind too short to be a wind goes nowhere.
	at = car.global_position
	_press(at, MOUSE_BUTTON_RIGHT)
	_move(at + Vector2(6 * car.facing * -1.0, 0))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("a nudge does not launch it", not car.is_driving())

	# "Tighter Spring": a full wind is a shorter pull.
	var pull := car._full_pull()
	var node := _node_for(&"pull_back_car", &"cooldown_mult")
	if node:
		Progression.purchase_augment(node.id, 3)
	_check("Tighter Spring winds it fully in a shorter pull (%.0f -> %.0f)" % [pull, car._full_pull()],
		car._full_pull() < pull)

	# He winds it himself and lets it go away from him, then chases it.
	await _frames(60)
	_trickles.clear()
	_acts.clear()
	car.idle_use(_buddy)
	var away := signf(car.global_position.x - _buddy.global_position.x)
	_check("left alone with it, he lets it go away from him", car.is_driving()
		and is_equal_approx(car.facing, away))
	# The chase is the game, so a driving car is still his toy (D70).
	_check("and a car on the move is still somewhere to go (%.3f)" % car.idle_appeal(),
		car.idle_appeal() > 0.0)
	await _frames(40)
	_check("and that is his trickle, not an act", _acts.is_empty()
		and _trickles.any(func(t: Array) -> bool: return t[0] == &"pull_back_car"))
	await _frames(150)
	Settings.focus_intensity = Settings.Intensity.OFF
	_spawner_clear()

# --- the yo-yo -----------------------------------------------------------------------

func _the_yo_yo_sleeps_and_bonks() -> void:
	_suite("yo-yo")
	await _stand_him_up(Vector2(640, 560))
	var yoyo := await _fresh(&"yo_yo", _beside_him(-260.0)) as YoYo
	if yoyo == null:
		_check("a yo-yo is on the desk", false)
		return
	await _frames(20)
	_check("at rest it runs no frame and shows its string's loose end", not yoyo.is_processing()
		and yoyo.tail.visible)
	var at := yoyo.global_position
	await _hover(at)
	_press(at)
	_check("left holds it", yoyo.dragging)
	_check("in the hand it is an ordinary weapon to him", yoyo.effective_damage_mult() > 0.0)
	await _mouse_to(Vector2(at.x, 250.0))
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_check("right throws it out on its string", yoyo.is_out() and yoyo.mouse_joint == null
		and not yoyo.tail.visible)
	_check("and on the string his contact path bills nothing — it bills itself",
		is_zero_approx(yoyo.effective_damage_mult()))
	await _frames(40)
	_check("the string pays out to its length (%.0f)" % yoyo.string_out(),
		is_equal_approx(yoyo.string_out(), yoyo.string_length))
	_check("and it hangs at the end of it (%.0f px from the hand)"
		% yoyo.global_position.distance_to(yoyo.handle.global_position),
		yoyo.global_position.distance_to(yoyo.handle.global_position) <= yoyo.string_length + 12.0)
	_check("held there, it sleeps", yoyo.is_asleep())
	var string := yoyo.get_node_or_null("String") as Line2D
	_check("the string is drawn from the hand to it", string != null and string.visible
		and string.get_point_count() == 2)
	await get_tree().create_timer(yoyo._trick_needed() + 0.2).timeout
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("a long sleep brought back is a trick", yoyo.tricks == 1 and yoyo.trick_armed())
	var home := false
	for i in 60:
		await get_tree().physics_frame
		if not yoyo.is_out():
			home = true
			break
	_check("and it climbs back into the hand", home and yoyo.mouse_joint != null and yoyo.tail.visible)
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	await _frames(3)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	for i in 60:
		await get_tree().physics_frame
		if not yoyo.is_out():
			break
	_check("a flick straight back is no trick", yoyo.tricks == 1)
	_release(_mouse)
	await _frames(30)

	# A bonk on the string: out, and sent at him. Put beside him at a known speed rather than
	# swung, so the number it bills can be checked against the collision it was.
	# The trick above is still armed for a moment; this one is the plain bonk.
	yoyo._trick_until_msec = 0
	var bonk := await _bonk(yoyo, 950.0)
	_check("swung into him on its string, it bonks him (%d hits)" % bonk.size(), bonk.size() == 1)
	if bonk.size() == 1:
		var info: HitInfo = bonk[0]
		var want := Progression.damage_mult_for(&"yo_yo", yoyo.damage_mult)
		var got := info.amount / (info.raw_impulse * ItemDB.balance.damage_per_impulse)
		_check("billed at its own multiplier (x%.3f, the data says x%.3f)" % [got, want],
			absf(got - want) < 0.001)
		_check("for the collision it was: (1+e) x reduced mass x speed (%.0f)" % info.raw_impulse,
			info.raw_impulse > ItemDB.balance.min_damage_impulse)
	# The trick shot: slept, brought back, then a bonk inside the window is worth trick_mult.
	yoyo._trick_until_msec = Time.get_ticks_msec() + 2000
	bonk = await _bonk(yoyo, 950.0)
	if bonk.size() == 1:
		var info: HitInfo = bonk[0]
		var want := Progression.damage_mult_for(&"yo_yo", yoyo.damage_mult) * yoyo.trick_mult
		var got := info.amount / (info.raw_impulse * ItemDB.balance.damage_per_impulse)
		_check("a bonk after a trick is a trick shot (x%.3f, x%.3f wanted)" % [got, want],
			absf(got - want) < 0.001 and not yoyo.trick_armed())
	else:
		_check("a bonk after a trick is a trick shot (%d hits)" % bonk.size(), false)
	# Let go of the finger loop with it out: it is loose.
	yoyo = get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED).filter(
		func(n: Node) -> bool: return n is YoYo).front() as YoYo
	if yoyo and yoyo.dragging:
		_release(_mouse)
		await _frames(2)
		_check("let go of with it out, it is loose and the string goes", not yoyo.is_out()
			and not (yoyo.get_node("String") as Line2D).visible)
	_release_all()
	# "Ball Bearing": a shorter sleep is a trick.
	var needed := yoyo._trick_needed() if yoyo else 0.0
	var node := _node_for(&"yo_yo", &"cooldown_mult")
	if node and yoyo:
		Progression.purchase_augment(node.id, 3)
		_check("Ball Bearing makes a shorter sleep a trick (%.2f -> %.2f s)"
			% [needed, yoyo._trick_needed()], yoyo._trick_needed() < needed)
	_spawner_clear()

## Out on its string beside him, moving at him at `speed`, and the hits it billed.
func _bonk(yoyo: YoYo, speed: float) -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	if not is_instance_valid(yoyo):
		return out
	_buddy.health.reset_meter()
	var him := _buddy.get_interaction_rect().get_center()
	if not yoyo.dragging:
		await _hover(yoyo.global_position)
		_press(yoyo.global_position)
		await _frames(2)
	# Hand up and to one side: thrown straight down from here the yo-yo lands beside him, and
	# put next to him it is still inside the string's reach.
	_mouse_move_instant(him + Vector2(-120, -150))
	await _frames(8)
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	await _frames(20)
	yoyo.global_position = him + Vector2(-58, 0)
	yoyo.linear_velocity = Vector2(speed, 0)
	yoyo._history.fill(Vector2(speed, 0))
	_hits.clear()
	for i in 20:
		await get_tree().physics_frame
	for info in _hits:
		if info.source_id == &"yo_yo":
			out.append(info)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	for i in 60:
		await get_tree().physics_frame
		if not yoyo.is_out():
			break
	return out

# --- the slingshot -------------------------------------------------------------------

func _the_slingshot_draws_and_fires() -> void:
	_suite("slingshot")
	await _stand_him_up(Vector2(700, 560))
	var sling := await _fresh(&"slingshot", _beside_him(-240.0)) as Slingshot
	if sling == null:
		_check("a slingshot is on the desk", false)
		return
	await _frames(20)
	var at := sling.global_position
	await _hover(at)
	_press(at)
	_check("left holds it", sling.dragging)
	# Held at his height, so the draw is straight back along the desk and never crosses the HUD:
	# a motion over a panel is the panel's, and the pouch would stop following it.
	await _mouse_to(Vector2(at.x, (_buddy.global_transform * _buddy.center_of_mass).y + 14.0))
	await _frames(30)
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_check("right while holding it plants it, upright", sling.is_drawn() and sling.freeze
		and absf(sling.global_rotation) < 0.01)
	# Drawn straight back from him, all the way.
	var fork := sling.fork_position()
	var him := _buddy.global_transform * _buddy.center_of_mass
	var back := (fork - him).normalized()
	_move(fork + back * 180.0)
	_check("the pouch follows the cursor, as far as the bands go (%.0f px)"
		% sling.pouch_position().distance_to(fork),
		is_equal_approx(sling.pouch_position().distance_to(fork), sling.max_draw))
	_check("the bands are drawn to it", sling.pouch.visible and not sling.rest_bands.visible)
	_check("and a dotted line shows the shot (%d dots)" % sling.preview_points().size(),
		sling.preview_points().size() >= 4)
	_check("drawn at him, he knows it", sling.is_threatening())
	await _frames(4)
	_check("and cowers (beat '%s')" % _face.beat_id(), _face.beat_id() == &"aimed_at")
	_buddy.health.reset_meter()
	_hits.clear()
	var bones := Economy.balance_of(Economy.BONES)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("letting go of right fires a pellet", sling.shots_fired == 1 and not sling.is_drawn()
		and not sling.freeze)
	_check("and he is no longer aimed at", not sling.is_threatening())
	var hit: HitInfo = null
	for i in 60:
		await get_tree().physics_frame
		for info in _hits:
			if info.source_id == &"slingshot":
				hit = info
		if hit:
			break
	_check("the pellet hits him", hit != null)
	if hit:
		var want := sling.shot_force * Progression.damage_mult_for(&"slingshot", sling.damage_mult) \
			* ItemDB.balance.damage_per_impulse
		_check_near("for a full draw's damage", hit.amount, want)
		_check("and pays Bones", Economy.balance_of(Economy.BONES) > bones)
	await _frames(4)
	_check("once: a pellet bills itself one time", _hits.filter(func(i: HitInfo) -> bool:
		return i.source_id == &"slingshot").size() == 1)
	# Straight away again: the pouch is empty until it reloads.
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_move(sling.fork_position() + back * 120.0)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("a second draw before it reloads fires nothing", sling.shots_fired == 1)
	await get_tree().create_timer(sling._reload() + 0.1).timeout
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_move(sling.fork_position() + back * 8.0)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("a twitch of a draw fires nothing either", sling.shots_fired == 1)
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_move(sling.fork_position() + Vector2(60, 60))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("reloaded, it fires again", sling.shots_fired == 2)
	_release(_mouse)
	await _frames(4)
	# "Pellet Pouch": reloads sooner.
	var reload := sling._reload()
	var node := _node_for(&"slingshot", &"cooldown_mult")
	if node:
		Progression.purchase_augment(node.id, 3)
	_check("Pellet Pouch reloads sooner (%.2f -> %.2f s)" % [reload, sling._reload()],
		sling._reload() < reload)
	# Binned mid-flight, it takes its pellets with it.
	await _hover(sling.global_position)
	_press(sling.global_position)
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_move(sling.fork_position() + Vector2(-80, 40))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_release(_mouse)
	var pellets := _all_nodes(_main).filter(func(n: Node) -> bool: return n is Slingshot.Pellet)
	sling.bin_myself()
	await _frames(2)
	_check("binned, its pellets go with it (%d were flying)" % pellets.size(), pellets.all(
		func(p) -> bool: return not is_instance_valid(p) or (p as Node).is_queued_for_deletion()))
	_spawner_clear()

# --- panels and focus (D70) ------------------------------------------------------------

## A live gesture hears the mouse over a panel — the HUD's rows stop the mouse, and the world's
## `_unhandled_input` never sees a motion a control took — and a gesture the game loses focus in
## the middle of is called off, not let go of: alt-tab with a slingshot drawn fired it at him.
func _a_gesture_outlives_a_panel_but_not_the_focus() -> void:
	_suite("panels and focus")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	await _stand_him_up(Vector2(700, 560))
	var sling := await _fresh(&"slingshot", _beside_him(-240.0)) as Slingshot
	if sling == null:
		_check("a slingshot is on the desk", false)
		return
	await _frames(20)
	var at := sling.global_position
	await _hover(at)
	_press(at)
	await _mouse_to(Vector2(at.x, (_buddy.global_transform * _buddy.center_of_mass).y + 14.0))
	await _frames(30)
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	var fork := sling.fork_position()
	_move(fork + Vector2(-10, 0))
	# A panel across the draw, stopping the mouse the way the HUD's rows do.
	var panel := _panel_in_the_way(Rect2(fork + Vector2(-140, -60), Vector2(120, 120)))
	_move(fork + Vector2(-80, 4))
	_check("drawn across a panel, the pouch still follows the cursor (%.0f px off)"
		% sling.pouch_position().distance_to(fork + Vector2(-80, 4)),
		sling.pouch_position().distance_to(fork + Vector2(-80, 4)) < 1.0)
	var shots := sling.shots_fired
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("and letting go over the panel still looses it", sling.shots_fired == shots + 1
		and not sling.is_drawn())
	panel.get_parent().queue_free()
	await get_tree().create_timer(sling._reload() + 0.1).timeout
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	# Straight back from him, from wherever the frame hangs now.
	var again := sling.fork_position()
	var him := _buddy.global_transform * _buddy.center_of_mass
	_move(again + (again - him).normalized() * 90.0)
	_check("drawn again, at him", sling.is_drawn() and sling.is_threatening())
	shots = sling.shots_fired
	_main.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("the game losing focus mid-draw fires nothing (%d shots)" % (sling.shots_fired - shots),
		sling.shots_fired == shots)
	_check("it slackens instead: not drawn, not planted, not aimed at him", not sling.is_drawn()
		and not sling.freeze and not sling.is_threatening() and not sling.pouch.visible)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_release(_mouse)
	await _frames(4)
	_check("and neither the right nor the left coming up later fires it", sling.shots_fired == shots)
	_check("with nothing live, its zones listen to nothing", not sling.gestures.is_processing_input())
	_spawner_clear()

	# The car: wound to full, then the focus goes. It unwinds where it stands.
	var car := await _fresh(&"pull_back_car", Vector2(_buddy.global_position.x - 230.0, 600.0)) as PullBackCar
	if car:
		await _frames(30)
		_press(car.global_position, MOUSE_BUTTON_RIGHT)
		for i in 18:
			_move(_mouse + Vector2(-10, 0))
		var wound := car.notches()
		var launches := car.launches
		_main.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		_check("a car wound to %d notches when the focus goes does not drive off" % wound,
			wound == PullBackCar.NOTCHES and car.launches == launches and not car.is_driving())
		_check("it stops winding and is a car again", not car.is_winding() and not car.freeze)
		_release(_mouse, MOUSE_BUTTON_RIGHT)
		_check("and the right coming up later launches nothing", car.launches == launches)
	_spawner_clear()

	# The cradle: a ball held out when the focus goes goes back into the row.
	var cradle := await _fresh(&"newtons_cradle", _beside_him(-190.0)) as NewtonsCradle
	if cradle:
		await _frames(30)
		var ball := cradle.gestures.zone_world(&"ball_l")
		_press(ball, MOUSE_BUTTON_RIGHT)
		_move(ball + Vector2(-26, -10))
		_move(ball + Vector2(-34, -16))
		var held_out := cradle.ball_angle(0)
		_main.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		_check("a cradle ball held out (%.0f deg) when the focus goes swings nothing"
			% rad_to_deg(held_out), held_out > deg_to_rad(20.0) and not cradle.is_swinging()
			and is_zero_approx(cradle.ball_angle(0)))
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	_spawner_clear()

	# The slinky: stretched in the hand when the focus goes, it goes home without a boing.
	var slinky := await _fresh(&"slinky", _beside_him(-240.0)) as Slinky
	if slinky:
		await _frames(20)
		await _hover(slinky.global_position)
		_press(slinky.global_position)
		await _frames(4)
		_press(_mouse, MOUSE_BUTTON_RIGHT)
		_move(_mouse + Vector2(40, -150))
		await _frames(3)
		var stretched := slinky.stretch()
		await _clear_combo()
		_acts.clear()
		var boings := slinky.boings
		_main.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		_check("a slinky stretched %.0f px when the focus goes pays no boing (%s)" % [stretched, str(_acts)],
			stretched > 120.0 and slinky.boings == boings and _acts.is_empty())
		_check("and is let go of all the same", not slinky.stretching() and not slinky.freeze)
		_release_all()
	Settings.focus_intensity = Settings.Intensity.OFF
	_spawner_clear()

## A control that stops the mouse, over `rect`, on a layer above the HUD. Freed by freeing its
## parent layer.
func _panel_in_the_way(rect: Rect2) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "PanelInTheWay"
	layer.layer = 120
	var panel := Control.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.position = rect.position
	panel.size = rect.size
	layer.add_child(panel)
	_view.add_child(layer)
	return panel

# --- zones in a turned body ------------------------------------------------------------

func _zones_follow_a_turned_body() -> void:
	_suite("zones on a turned, mirrored body")
	var cradle := await _fresh(&"newtons_cradle", _beside_him(-220.0)) as NewtonsCradle
	if cradle:
		cradle.freeze = true
		cradle.global_rotation = PI
		await _frames(2)
		# Upside down, the right-hand ball is on the left.
		var ball := cradle.gestures.zone_world(&"ball_r")
		_check("upside down, the right ball's zone is on the left", ball.x < cradle.global_position.x)
		_press(ball, MOUSE_BUTTON_RIGHT)
		_move(ball + (ball - cradle.global_position).normalized() * 30.0)
		_check("and pulling it there pulls that ball (%.2f)" % cradle.ball_angle(4),
			cradle.ball_angle(4) < -deg_to_rad(10.0) and is_zero_approx(cradle.ball_angle(0)))
		_release(_mouse, MOUSE_BUTTON_RIGHT)
		_check("and it swings", cradle.is_swinging())
	_spawner_clear()
	var car := await _fresh(&"pull_back_car", _beside_him(-260.0)) as PullBackCar
	if car:
		await _frames(20)
		car.set_facing(-1.0)
		_check("a car facing the other way mirrors its zones", car.gestures.mirrored)
		_press(car.global_position, MOUSE_BUTTON_RIGHT)
		for i in 6:
			_move(_mouse + Vector2(12, 0))
		_check("and winds from there, facing away from the pull (%d notches)" % car.notches(),
			car.is_winding() and car.notches() > 0 and is_equal_approx(car.facing, -1.0))
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	_spawner_clear()
	var slinky := await _fresh(&"slinky", _beside_him(-240.0)) as Slinky
	if slinky:
		slinky.freeze = true
		slinky.global_rotation = PI * 0.5
		await _frames(2)
		var zone := slinky.gestures.zone_world(&"coil")
		_press(zone, MOUSE_BUTTON_RIGHT)
		_move(zone + Vector2(-80, -60))
		_check("a slinky on its side is still stretched from where it lies", slinky.stretching()
			and slinky.stretch() > 80.0)
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	_spawner_clear()

# --- hover ------------------------------------------------------------------------------

func _hover_shows_what_is_a_button() -> void:
	_suite("hover")
	var cradle := await _fresh(&"newtons_cradle", _beside_him(-220.0)) as NewtonsCradle
	if cradle:
		await _frames(20)
		_move(cradle.gestures.zone_world(&"ball_l"))
		_check("over an end ball, the pointing hand", cradle.gestures.cursor_shape
			== Input.CURSOR_POINTING_HAND)
		_move(cradle.gestures.art_to_world(Vector2(0.0, -12.0)))
		_check("over the frame, the grab", cradle.gestures.cursor_shape == Input.CURSOR_MOVE)
	_spawner_clear()
	var car := await _fresh(&"pull_back_car", _beside_him(-220.0)) as PullBackCar
	if car:
		await _frames(20)
		_move(car.global_position)
		_check("over the car — which is the toy, not a button on it — the grab",
			car.gestures.cursor_shape == Input.CURSOR_MOVE and car.gestures.hover_zone == &"")
		_move(Vector2(40, 300))
	_spawner_clear()

# --- the bin -----------------------------------------------------------------------------

func _shift_right_always_bins() -> void:
	_suite("Shift+right bins")
	for id in TOYS:
		var body := await _fresh(id, _beside_him(-220.0)) as BaseDraggable
		if body == null:
			_check("%s is on the desk" % id, false)
			continue
		await _frames(20)
		var count := _spawner.item_count()
		var at := body.global_position
		if body.gesture_zones and not body.gesture_zones.zone_ids().is_empty():
			at = body.gesture_zones.zone_world(body.gesture_zones.zone_ids()[0])
		await _hover(at)
		_press(at, MOUSE_BUTTON_RIGHT, true)
		_release(at, MOUSE_BUTTON_RIGHT)
		await _settle()
		_check("Shift+right on the %s bins it" % id, not is_instance_valid(body)
			or not body.is_inside_tree() or _spawner.item_count() < count)
		_spawner_clear()

# --- the budget -------------------------------------------------------------------------

func _nothing_runs_at_rest() -> void:
	_suite("nothing runs at rest")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	var x := -300.0
	var toys: Array[BaseDraggable] = []
	for id in TOYS:
		var toy := await _fresh(id, _beside_him(x)) as BaseDraggable
		x += 150.0
		if toy:
			toys.append(toy)
	await _frames(60)
	for toy in toys:
		var zones := toy.gesture_zones
		_check("%s at rest runs no frame of its own" % toy.item_id, not toy.is_processing())
		_check("and its zones are idle", zones != null and not zones.is_pressed()
			and not zones.action_live() and (zones.get_node("HoldTimer") as Timer).is_stopped())
	Settings.focus_intensity = Settings.Intensity.OFF
	_spawner_clear()

# --- him ---------------------------------------------------------------------------------

## He walks over to each kind one and does his thing with it — the same stepped physics the
## idle brain's own suite uses, on the real floor of the real game.
func _he_plays_with_the_kind_ones() -> void:
	_suite("he plays with them")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	for id in KIND:
		_spawner_clear()
		await _stand_him_up(Vector2(420, 560))
		var toy := await _fresh(id, Vector2(_buddy.global_position.x + 160.0, 560)) as FidgetToy
		if toy == null:
			_check("%s is on the desk" % id, false)
			continue
		await _frames(40)
		_idle.pretend_idle()
		_idle.think_now()
		_check("%s is somewhere he goes (target '%s', routine %d)"
			% [id, _idle.target_id(), _idle.current_routine()],
			_idle.target_id() == id and _idle.current_routine() == IdleBrain.ROUTINE_FIDGET)
		for i in 480:
			await get_tree().physics_frame
			if _idle.phase_name() == IdleBrain.PHASE_PLAYING and i > 30:
				break
		_check("he gets there (phase '%s')" % _idle.phase_name(),
			_idle.phase_name() == IdleBrain.PHASE_PLAYING)
		_trickles.clear()
		var used := false
		for tick in 4:
			_idle.think_now()
			for i in 50:
				await get_tree().physics_frame
				used = used or _state_changed(toy)
		_check("and uses the %s" % id, used or _trickles.any(func(t: Array) -> bool: return t[0] == id))
		_idle._disturb()
	Settings.focus_intensity = Settings.Intensity.OFF
	_spawner_clear()

func _state_changed(toy: FidgetToy) -> bool:
	if toy is Slinky:
		return (toy as Slinky).boings > 0
	if toy is NewtonsCradle:
		return (toy as NewtonsCradle).is_swinging()
	if toy is PullBackCar:
		return (toy as PullBackCar).launches > 0
	return false

# --- staging -----------------------------------------------------------------------

func _fresh(id: StringName, at: Vector2) -> BaseDraggable:
	EventBus.spawn_requested.emit(id, at)
	var found: BaseDraggable = null
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		var body := node as BaseDraggable
		if body and body.item_id == id and not body.is_queued_for_deletion():
			found = body
	_idle._disturb()
	await _frames(30)
	return found

func _spawner_clear() -> void:
	_release_all()
	if _spawner:
		_spawner.clear_desk()

func _beside_him(dx: float) -> Vector2:
	return Vector2(_buddy.global_position.x + dx, _buddy.global_position.y + 20.0)

func _stand_him_up(at: Vector2) -> void:
	_idle._disturb()
	_buddy.global_position = at
	_buddy.global_rotation = 0.0
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	await _frames(60)

func _rings_of(slinky: Slinky) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in slinky.coil.get_children():
		if child is Sprite2D:
			out.append(child)
	return out

func _node_for(id: StringName, key: StringName) -> AugmentNode:
	for node in ItemDB.augments_for(id):
		if node.effect_key == key and not node.is_automation:
			return node
	return null

func _clear_combo() -> void:
	if Economy.combo_seconds_left() > 0.0:
		await get_tree().create_timer(Economy.combo_seconds_left() + 0.05).timeout

## What one kindness act of `value` pays in Hearts, read BEFORE it is emitted (CLAUDE.md).
func _expected_act(value: float, id: StringName) -> float:
	var b := ItemDB.balance
	var count: int = Economy._combo_count + 1 if Economy.combo_seconds_left() > 0.0 else 0
	var combo := EconomyMath.kindness_combo(count, b.kindness_combo_step, b.kindness_combo_max)
	return Economy.payout_for(value * b.hearts_per_kindness * combo, id)

# --- input ------------------------------------------------------------------------

func _move(at: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = at - _mouse
	motion.velocity = velocity
	motion.button_mask = _mask
	_mouse = at
	_view.push_input(motion, true)

func _mouse_move_instant(at: Vector2) -> void:
	_move(at)

## The cursor carried to `target` a few px a frame, so a held body follows rather than snaps.
func _mouse_to(target: Vector2) -> void:
	var guard := 0
	while _mouse.distance_to(target) > 12.0 and guard < 200:
		_move(_mouse.move_toward(target, 12.0))
		await get_tree().physics_frame
		guard += 1
	_move(target)
	await get_tree().physics_frame

func _hover(at: Vector2) -> void:
	# Told again that the mouse is in it: a picking viewport with no container above it forgets.
	_view.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
	_move(at)
	await _frames(3)

func _press(at: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	if at != _mouse:
		_move(at)
	_mask |= 1 << (button - 1)
	_view.push_input(_click(at, button, true, shift), true)

func _release(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_mask &= ~(1 << (button - 1))
	_view.push_input(_click(at, button, false, false), true)

func _release_all() -> void:
	if _mask & 2:
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	if _mask & 1:
		_release(_mouse, MOUSE_BUTTON_LEFT)

func _click(at: Vector2, button: int, pressed: bool, shift: bool) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = pressed
	click.button_mask = _mask
	click.shift_pressed = shift
	click.position = at
	click.global_position = at
	return click

# --- plumbing -----------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await get_tree().physics_frame

func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		out.append_array(_all_nodes(child))
	return out

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _suite(name_: String) -> void:
	print("")
	print("-- %s" % name_)

func _check(what: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("   ok   %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)

func _check_near(what: String, got: float, want: float) -> void:
	_check("%s (%.3f, expected %.3f)" % [what, got, want],
		absf(got - want) <= maxf(0.001, absf(want) * 0.01))
