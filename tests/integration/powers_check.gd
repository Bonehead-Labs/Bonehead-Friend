extends Node

## Headless check of the supernatural cursor powers (docs/decisions.md D72): telekinesis, time
## stop, the meteor shower and smite on the harm side; the blessing, levitation and the rainbow
## on the kind — each equipped from the shop's own path and worked with synthetic input at real
## positions, down the road real events take: the viewport, `CursorPowerBase._unhandled_input`,
## `SpellPower._input`.
##
##   Godot --headless --path <project> res://tests/integration/powers_check.tscn [-- --only=smite,d47]
##
## For every power: D47's three rules (a toy under the cursor is picked up, Shift gives him back
## to your hands, Esc holsters), what it does on him and on empty space, what it pays and through
## which road — the multipliers read *before* the event that pays (CLAUDE.md) — the row his face
## plays, and that nothing of it runs once it is put away and its effect is over.
##
## Its own save slot and its own settings file, and it puts back what it pins. `_check(what, ok)`
## takes two arguments, like loop_check's — a third is a parse error, and a parse error here looks
## like a hang (CLAUDE.md).

const TEST_SLOT := "powers_check_slot"
const VIEW_SIZE := Vector2i(1100, 700)
const HARM: Array[StringName] = [&"telekinesis", &"time_stop", &"meteor_shower", &"smite"]
const KIND: Array[StringName] = [&"blessing", &"levitation", &"rainbow"]
const HOME := Vector2(550, 600)

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
var _only: PackedStringArray = []

## What the bus carried. Members, not locals: a lambda captures locals by value (CLAUDE.md).
var _hits: Array[HitInfo] = []
var _acts: Array = []
var _trickles: Array = []
var _paid: Array = []
## A payout worked out at the moment something is about to pay, for the next payout to match.
var _expect_next := -1.0
var _expect_got := -1.0

func _want(suite: String) -> bool:
	return _only.is_empty() or _only.has(suite)

func _ready() -> void:
	# Before anything else (D51): equipping a power fires a one-off hint, and a hint saves.
	Settings.config_path = "user://settings_powers_check.cfg"
	_restore = {
		"focus": Settings.focus_intensity,
		"scale": Settings.ui_scale,
		"hud_pinned": Settings.hud_pinned,
		"tabs_pinned": Settings.tabs_pinned,
		"hints": Settings.hints_seen.duplicate(),
	}
	# Normal, not Off: the smite's tell is a Normal-gated row, and the spells' particles are part
	# of what is being checked for staying off at rest. Sound is muted instead — the headless
	# dummy driver reports finished playbacks as leaks at exit.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.ui_scale = 1
	Settings.hints_seen = PackedStringArray()
	AudioManager._set_muted(true)
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()

	print("")
	print("Bonehead Friend — powers check")
	print("==============================")

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
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--only="):
			_only = String(arg).trim_prefix("--only=").split(",", false)

	EventBus.damage_dealt.connect(func(info: HitInfo) -> void: _hits.append(info))
	EventBus.kindness_given.connect(func(id: StringName, value: float, _at: Vector2) -> void:
		_acts.append([id, value]))
	EventBus.kindness_sustained.connect(func(id: StringName, value: float, _at: Vector2) -> void:
		_trickles.append([id, value]))
	EventBus.payout.connect(_on_payout)
	EventBus.contract_event.connect(_on_contract)
	# The smite's strike announces itself (its tell going out) the instant before it hands him
	# the impulse, which is the moment to read what that impulse will pay.
	EventBus.threat_changed.connect(_on_threat)

	if _want("content"):
		_the_powers_are_content()
	if _want("budget"):
		_nothing_exists_until_equipped()
	Economy.grant(Economy.BONES, 5.0e6)
	Economy.grant(Economy.HEARTS, 5.0e6)
	for id in HARM + KIND:
		_buy(id)
	if _want("d47"):
		await _the_d47_rules_hold()
	if _want("telekinesis"):
		await _telekinesis()
	if _want("time_stop"):
		await _time_stop()
	if _want("meteor_shower"):
		await _meteor_shower()
	if _want("smite"):
		await _smite()
	if _want("blessing"):
		await _blessing()
	if _want("levitation"):
		await _levitation()
	if _want("rainbow"):
		await _rainbow()
	if _want("budget"):
		await _nothing_runs_once_put_away()
	_finish()

func _finish() -> void:
	_release_all()
	if _spawner:
		_spawner.holster_power()
		_spawner.clear_desk()
	print("")
	print("==============================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_clear_slot()
	AudioManager._set_muted(false)
	Settings.focus_intensity = _restore["focus"]
	Settings.ui_scale = _restore["scale"]
	Settings.hud_pinned = _restore["hud_pinned"]
	Settings.tabs_pinned = _restore["tabs_pinned"]
	Settings.hints_seen = _restore["hints"]
	Settings.save_settings()
	get_tree().quit(1 if _failed > 0 else 0)

func _on_payout(currency: StringName, amount: float, _at: Vector2, source_id: StringName) -> void:
	_paid.append([currency, amount, source_id])
	if _expect_next >= 0.0 and _expect_got < 0.0:
		_expect_got = amount

func _on_threat(kind: StringName, _at: Vector2, level: float) -> void:
	if kind == &"windup" and level <= 0.0 and _spawner and _spawner.active_power() == &"smite":
		var power := _spawner.get_power(&"smite") as SmitePower
		var amount := EconomyMath.damage_from_impulse(power.smite_impulse,
			ItemDB.balance.min_damage_impulse, ItemDB.balance.damage_per_impulse,
			power.effective_damage_mult())
		_expect_next = _expected_hit(amount, &"smite")
		_expect_got = -1.0

# --- content ------------------------------------------------------------------------

func _the_powers_are_content() -> void:
	_suite("content")
	for id in HARM + KIND:
		var item := ItemDB.get_item(id)
		_check("%s is in the shop" % id, item != null)
		if item == null:
			continue
		var kind := KIND.has(id)
		_check("%s is %s, priced in %s, and equips as a power" % [id,
			"filed with the kind things in Care" if kind else "in the Cursor drawer",
			"Hearts" if kind else "Bones"],
			item.is_kind() == kind and item.is_cursor_power()
			and item.category == (ItemData.CATEGORY_FRIENDLY if kind else ItemData.CATEGORY_CURSOR_POWER)
			and item.currency == (ItemData.CURRENCY_HEARTS if kind else ItemData.CURRENCY_BONES))
		_check("%s says how to work it" % id, not item.controls.is_empty())
		_check("%s is gated behind a power that stays in the game" % id, not item.requires.is_empty()
			and not item.requires.has(&"pistol") and not item.requires.has(&"shotgun")
			and not item.requires.has(&"minigun"))
		var power := item.scene.instantiate() as SpellPower
		_check("%s is a spell with a cursor of its own, hotspot at its middle" % id, power != null
			and power.cursor_texture != null and power.cursor_hotspot == Vector2(32, 32)
			and power.cursor_texture.get_width() == 64)
		if power:
			power.free()
		_check("%s has an icon" % id, item.icon != null)
		var keys := {}
		var capstone: AugmentNode = null
		for node in ItemDB.augments_for(id):
			if node.is_automation:
				capstone = node
				continue
			keys[node.effect_key] = true
			_check("%s's %s is bought with the drawer's currency" % [id, node.id],
				node.currency == (AugmentNode.CURRENCY_HEARTS if kind else AugmentNode.CURRENCY_BONES))
		var want := [&"damage_mult", &"payout_mult"]
		if id != &"levitation":
			want.append(&"cooldown_mult")
		_check("%s has a tree of %s" % [id, ", ".join(want)], keys.size() == want.size()
			and want.all(func(k: StringName) -> bool: return keys.has(k)))
		_check("%s has a capstone on the claw arm, priced in Hearts" % id, capstone != null
			and capstone.device_mount == &"arm" and capstone.currency == AugmentNode.CURRENCY_HEARTS)
	for event in [&"seized", &"time_stopped", &"time_resumed", &"time_thawed", &"blessed",
			&"levitating", &"rainbow_ride", &"rainbow_landed"]:
		var row: StringName = ExpressionBrain.FIDGET_ROWS.get(event, &"")
		_check("'%s' has a row on his face (%s)" % [event, row],
			row != &"" and ExpressionBrain.ROWS.has(row))

## A power that has never been equipped does not exist: the spawner instances one on first use.
func _nothing_exists_until_equipped() -> void:
	_suite("budget: unequipped")
	for id in HARM + KIND:
		_check("%s has no instance until it is first equipped" % id, _spawner.get_power(id) == null)

# --- D47 ----------------------------------------------------------------------------

func _the_d47_rules_hold() -> void:
	_suite("D47: toys still grab, Shift gives him back, Esc holsters")
	await _stand_him_up(HOME)
	var bat := await _fresh(&"baseball_bat", HOME + Vector2(-260.0, 10.0))
	for id in HARM + KIND:
		var power := await _equip(id)
		if power == null:
			_check("%s equips" % id, false)
			continue
		_check("%s equips from the shop's own path and the cursor becomes it" % id,
			power.active and _spawner.active_power() == id)
		# Over a toy: the click is the toy's.
		if is_instance_valid(bat):
			var grip := _grip_of(bat)
			await _hover(grip)
			_press(grip)
			await _frames(2)
			_check("%s: pressed over the bat, the bat is picked up and the power does nothing" % id,
				bat.dragging and not _busy(power))
			_release(_mouse)
			await _frames(20)
		# Shift over him: the click is his to be picked up by.
		await _stand_him_up(HOME)
		await _hover(_centre())
		_press(_centre(), MOUSE_BUTTON_LEFT, true)
		await _frames(2)
		_check("%s: Shift+click on him picks him up, and the power does nothing" % id,
			_buddy.dragging and not _busy(power))
		_release(_mouse)
		await _frames(30)
		# Esc: put away before anything else.
		_view.push_input(_key(KEY_ESCAPE, true), true)
		_view.push_input(_key(KEY_ESCAPE, false), true)
		await _settle()
		_check("%s: Esc holsters it" % id, not power.active and _spawner.active_power() == &"")
		# Second time out, it says how it works (D57's one-off, for a power).
		await _equip(id)
		_check("%s: taken out a second time, it teaches its controls once" % id,
			Settings.hint_seen(StringName("controls:%s" % id)))
		_spawner.holster_power()
		await _settle()
	if is_instance_valid(bat):
		bat.bin_myself()
	await _frames(5)

# --- the harm four ------------------------------------------------------------------

func _telekinesis() -> void:
	_suite("telekinesis")
	await _stand_him_up(HOME)
	var power := await _equip(&"telekinesis") as TelekinesisPower
	var hand := HOME + Vector2(250.0, -300.0)
	_move(hand)
	await _frames(2)
	_press(hand)
	await _frames(2)
	_check("pressed on empty space, the hand takes him from where he is", power.is_gripping())
	_check("and his face is the grip's", _face.beat_id() == &"seized")
	for i in 60:
		_move(hand)
		await _frames(1)
	_check("he is carried up to the hand (%.0f px from it)" % _centre().distance_to(hand),
		_centre().distance_to(hand) < 80.0)
	_check("and the hand claims what he hits (%s)" % _buddy.impacts_claimed_by(),
		_buddy.impacts_claimed_by() == &"telekinesis")
	# The crush, paid through the pipeline at the multipliers of the moment it was asked for.
	var amount := EconomyMath.damage_from_impulse(power.crush_impulse,
		ItemDB.balance.min_damage_impulse, ItemDB.balance.damage_per_impulse, power.effective_damage_mult())
	_arm_expectation(_expected_hit(amount, &"telekinesis"))
	var hits := _hits.size()
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	await _frames(3)
	_check("right-click while holding him crushes: one hit of %.1f" % amount,
		_hits.size() == hits + 1 and is_equal_approx(_hits[-1].amount, amount)
		and _hits[-1].source_id == &"telekinesis")
	_check_near("paid in Bones through the pipeline", _expect_got, _expect_next)
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	await _frames(3)
	_check("a second squeeze inside the gap does nothing", _hits.size() == hits + 1)
	_release(_mouse)
	await _frames(2)
	_check("let go, the hand lets go and stops running", not power.is_gripping()
		and not power.is_physics_processing() and _buddy.modulate == Color.WHITE)
	await _frames(90)
	_spawner.holster_power()
	await _settle()

func _time_stop() -> void:
	_suite("time stop")
	await _stand_him_up(HOME)
	var power := await _equip(&"time_stop") as TimeStopPower
	await _click(HOME + Vector2(300.0, -200.0))
	_check("clicked on empty space, time does not stop", not power.is_stopped())
	_buddy.apply_central_impulse(Vector2(0.0, -800.0) * _buddy.mass)
	await _frames(8)
	await _click(_centre())
	var held := _buddy.global_position
	_check("clicked on him in the air, he stops dead", power.is_stopped() and _buddy.freeze)
	_check("tinted and with the stopped face", _buddy.modulate != Color.WHITE
		and _face.beat_id() == &"time_frozen")
	var blows := 0
	for offset in [Vector2(-30, -20), Vector2(-30, 20), Vector2(-20, 0)]:
		await _frames(int(ceil(power.blow_gap * 60.0)) + 1)
		await _click(_centre() + offset)
		blows += 1
	await _frames(20)
	_check("three clicks on him bank three blows, and none lands", power.banked() == blows
		and _hits.filter(func(h: HitInfo) -> bool: return h.source_id == &"time_stop").is_empty())
	_check("and he has not moved (%.2f px)" % _buddy.global_position.distance_to(held),
		_buddy.global_position.distance_to(held) < 0.5)
	var amount := EconomyMath.damage_from_impulse(power.blow_impulse,
		ItemDB.balance.min_damage_impulse, ItemDB.balance.damage_per_impulse, power.effective_damage_mult())
	var before := _hits.size()
	await _click(_centre() + Vector2(300.0, -100.0))
	await _frames(3)
	var burst := _hits.slice(before).filter(func(h: HitInfo) -> bool: return h.source_id == &"time_stop")
	_check("a click off him lets time go, and all three land at once (%d)" % burst.size(),
		not power.is_stopped() and not _buddy.freeze and burst.size() == blows
		and burst.all(func(h: HitInfo) -> bool: return is_equal_approx(h.amount, amount)))
	await _frames(8)
	_check("and the burst is one heavy blow on his face (%s)" % _face.beat_id(),
		_face.beat_id() == &"hit_heavy")
	_check("he is his own colour again", _buddy.modulate == Color.WHITE)
	# The stop runs out by itself too.
	await get_tree().create_timer(power.recharge_seconds + 0.1).timeout
	await _stand_him_up(HOME)
	await _click(_centre())
	_check("recharged, he can be stopped again", power.is_stopped())
	await get_tree().create_timer(power.stop_seconds + 0.2).timeout
	await _frames(2)
	_check("left alone, time starts again by itself", not power.is_stopped() and not _buddy.freeze
		and not power.is_processing())
	_spawner.holster_power()
	await _settle()

func _meteor_shower() -> void:
	_suite("meteor shower")
	await _stand_him_up(HOME)
	var power := await _equip(&"meteor_shower") as MeteorShowerPower
	# Held on empty space, far from him: it rains there, and he is not touched.
	var away := HOME + Vector2(-420.0, 0.0)
	var hits := _hits.size()
	var uses := _uses(&"meteor_shower")
	_press(away)
	for i in 50:
		_move(away)
		await _frames(1)
	_release(_mouse)
	await _await(func() -> bool: return not power.is_live(), 120)
	_check("held on empty space, meteors land there (%d)" % (_uses(&"meteor_shower") - uses),
		_uses(&"meteor_shower") - uses >= 3)
	_check("and none of them touches him", _hits.size() == hits)
	# Held on him.
	var bones := _paid_by(&"meteor_shower")
	_press(_centre())
	for i in 70:
		_move(_centre())
		await _frames(1)
	_release(_mouse)
	await _await(func() -> bool: return not power.is_live(), 120)
	var mine := _hits.slice(hits).filter(func(h: HitInfo) -> bool: return h.source_id == &"meteor_shower")
	_check("held on him, they hurt him (%d hits)" % mine.size(), mine.size() >= 2)
	_check("paid in Bones under its own name (%.1f)" % (_paid_by(&"meteor_shower") - bones),
		_paid_by(&"meteor_shower") > bones)
	_check("let go, the last one lands and nothing runs", not power.is_live()
		and not power.is_physics_processing())
	_spawner.holster_power()
	await _settle()

func _smite() -> void:
	_suite("smite")
	await _stand_him_up(HOME)
	var power := await _equip(&"smite") as SmitePower
	var hits := _hits.size()
	# Called down on empty space, well clear of him and his quake.
	await _click(HOME + Vector2(480.0, -100.0))
	await _await(func() -> bool: return not power.is_live(), 90)
	_check("called down away from him, it strikes there and does not touch him",
		_hits.size() == hits and _uses(&"smite") >= 1)
	await get_tree().create_timer(power.recharge_seconds + 0.1).timeout
	await _stand_him_up(HOME)
	_expect_next = -1.0
	await _click(_centre() + Vector2(0.0, -150.0))
	await _frames(4)
	_check("called down on his column, the light gathers and he sees it coming (%s)" % _face.beat_id(),
		power.is_live() and _face.beat_id() == &"threatened" and _hits.size() == hits)
	await _await(func() -> bool: return _hits.size() > hits, 90)
	_check("then it strikes him", _hits.size() > hits and _hits[hits].source_id == &"smite")
	_check_near("paid in Bones through the pipeline", _expect_got, _expect_next)
	_check("and drives him into the desk, whose blow is its to claim (%s)" % _buddy.impacts_claimed_by(),
		_buddy.impacts_claimed_by() == &"smite")
	await _await(func() -> bool: return not power.is_live(), 60)
	_check("the pillar goes and nothing runs", not power.is_processing())
	_spawner.holster_power()
	await _settle()

# --- the kind three -----------------------------------------------------------------

func _blessing() -> void:
	_suite("blessing")
	await _stand_him_up(HOME)
	await _clear_combo()
	var power := await _equip(&"blessing") as BlessingPower
	_acts.clear()
	_trickles.clear()
	await _click(HOME + Vector2(300.0, -150.0))
	_check("clicked on empty space, nothing is blessed", _acts.is_empty() and not power.is_live())
	var value := power.bless_value * power.effective_damage_mult()
	_arm_expectation(_expected_act(value, &"blessing"))
	await _click(_centre())
	_check("clicked on him: one blessing worth %.2f" % value,
		_acts.size() == 1 and is_equal_approx(float(_acts[0][1]), value))
	_check_near("paid in Hearts through the pipeline", _expect_got, _expect_next)
	_check("a halo over him, and he wears it (%s)" % _face.beat_id(), power.is_live()
		and _face.beat_id() == &"blessed")
	await get_tree().create_timer(1.1).timeout
	_check("the halo trickles while it lasts (%d flushes)" % _trickles.size(), _trickles.size() >= 2
		and _trickles.all(func(t: Array) -> bool: return t[0] == &"blessing"))
	_check("and no Bones are ever paid for it", _paid.filter(func(p: Array) -> bool:
		return p[2] == &"blessing" and p[0] == Economy.BONES).is_empty())
	_spawner.holster_power()
	await _settle()
	_check("put away, the halo goes and nothing runs", not power.is_live() and not power.is_processing())

func _levitation() -> void:
	_suite("levitation")
	await _stand_him_up(HOME)
	await _clear_combo()
	var power := await _equip(&"levitation") as LevitationPower
	_acts.clear()
	_trickles.clear()
	var hits := _hits.size()
	var floor_y := _centre().y
	var value := power.lift_value * power.effective_damage_mult()
	_arm_expectation(_expected_act(value, &"levitation"))
	_press(_centre())
	await _frames(2)
	_check_near("the lift is one kind act, paid through the pipeline", _expect_got, _expect_next)
	for i in 100:
		await _frames(1)
	_check("held, he floats up (%.0f px)" % (floor_y - _centre().y), floor_y - _centre().y > 90.0)
	_check("asleep up there (%s)" % _face.beat_id(), _face.beat_id() == &"levitating")
	_check("and every half second aloft pays (%d)" % _trickles.size(), _trickles.size() >= 2)
	_release(_mouse)
	var fastest := 0.0
	for i in 240:
		await _frames(1)
		fastest = maxf(fastest, _buddy.linear_velocity.y)
		if not power.is_live():
			break
	_check("let go, he drifts down no faster than %.0f px/s (%.0f)" % [power.sink_speed, fastest],
		fastest <= power.sink_speed + 25.0 and not power.is_live())
	_check("and nothing on the way down is billed", _hits.size() == hits)
	_check("down, nothing of it runs", not power.is_physics_processing())
	_spawner.holster_power()
	await _settle()

func _rainbow() -> void:
	_suite("rainbow")
	await _stand_him_up(HOME + Vector2(-300.0, 0.0))
	await _clear_combo()
	var power := await _equip(&"rainbow") as RainbowPower
	_acts.clear()
	var hits := _hits.size()
	var start := _centre()
	var target := start + Vector2(420.0, -150.0)
	_press(start)
	for i in 20:
		_move(start.lerp(target, float(i + 1) / 20.0))
		await _frames(1)
	var value := power.ride_value * power.effective_damage_mult()
	_arm_expectation(_expected_act(value, &"rainbow"))
	_release(_mouse)
	await _frames(2)
	_check("dragged off him and let go, he is on a rainbow", power.is_riding())
	_check_near("the ride is one kind act, paid through the pipeline", _expect_got, _expect_next)
	_check("and he loves it (%s)" % _face.beat_id(), _face.beat_id() == &"riding")
	_check("riding it, he is out of every layer but the world's", _buddy.collision_layer == 0
		and _buddy.collision_mask == 1)
	await _await(func() -> bool: return not power.is_riding(), 200)
	await _frames(20)
	_check("he steps off on the desk under where it was let go (%.0f px off)" % absf(_centre().x - target.x),
		absf(_centre().x - target.x) < 40.0)
	_check("back on his own layers, and nothing was billed", _buddy.collision_layer != 0
		and _hits.size() == hits)
	await _await(func() -> bool: return not power.is_live(), 60)
	_check("the rainbow fades and nothing runs", not power.is_physics_processing())
	_spawner.holster_power()
	await _settle()

# --- the budget ---------------------------------------------------------------------

func _nothing_runs_once_put_away() -> void:
	_suite("budget: put away")
	await get_tree().create_timer(0.5).timeout
	for id in HARM + KIND:
		var power := _spawner.get_power(id) as SpellPower
		if power == null:
			_check("%s was equipped by this run" % id, false)
			continue
		var emitting := _all_nodes(power).filter(func(n: Node) -> bool:
			return n is GPUParticles2D and (n as GPUParticles2D).emitting)
		_check("%s, put away: no frame, no physics frame, no input, nothing emitting (%d)"
			% [id, emitting.size()], not power.active and not power.is_processing()
			and not power.is_physics_processing() and not power.is_processing_input()
			and emitting.is_empty())

# --- staging -----------------------------------------------------------------------

func _buy(id: StringName) -> void:
	var item := ItemDB.get_item(id)
	if item == null or Progression.is_unlocked(id):
		return
	for req in item.requires:
		_buy(req)
	Progression.purchase_item(id)

## What the shop's Equip does.
func _equip(id: StringName) -> SpellPower:
	if _spawner.active_power() != id:
		EventBus.spawn_requested.emit(id, Vector2.ZERO)
	await _settle()
	return _spawner.get_power(id) as SpellPower

## Whether a power has taken a press or has an effect running.
func _busy(power: SpellPower) -> bool:
	return power.is_live() or power._held

func _fresh(id: StringName, at: Vector2) -> BaseDraggable:
	EventBus.spawn_requested.emit(id, at)
	var found: BaseDraggable = null
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		var body := node as BaseDraggable
		if body and body.item_id == id and not body.is_queued_for_deletion():
			found = body
	_idle.notice_player()
	await _frames(40)
	return found

func _grip_of(body: BaseDraggable) -> Vector2:
	if body.drag_area:
		for child in body.drag_area.get_children():
			if child is CollisionShape2D:
				return (child as CollisionShape2D).global_position
	return body.global_position

func _stand_him_up(at: Vector2) -> void:
	_idle.notice_player()
	_buddy.freeze = false
	_buddy.global_position = at
	_buddy.global_rotation = 0.0
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	await _frames(60)

func _centre() -> Vector2:
	return _buddy.get_interaction_rect().get_center()

func _uses(id: StringName) -> int:
	return int(_use_count.get(String(id), 0))

## `use:<id>` contract events, counted per id: a meteor landing, a strike.
var _use_count := {}

func _on_contract(key: StringName, count: int) -> void:
	var text := String(key)
	if text.begins_with("use:"):
		var id := text.trim_prefix("use:")
		_use_count[id] = int(_use_count.get(id, 0)) + count

func _clear_combo() -> void:
	if Economy.combo_seconds_left() > 0.0:
		await get_tree().create_timer(Economy.combo_seconds_left() + 0.05).timeout

func _paid_by(id: StringName) -> float:
	var total := 0.0
	for entry in _paid:
		if entry[2] == id:
			total += float(entry[1])
	return total

func _arm_expectation(value: float) -> void:
	_expect_next = value
	_expect_got = -1.0

## What one kindness act of `value` pays in Hearts, read BEFORE it is emitted (CLAUDE.md).
func _expected_act(value: float, id: StringName) -> float:
	var b := ItemDB.balance
	var count: int = Economy._combo_count + 1 if Economy.combo_seconds_left() > 0.0 else 0
	var combo := EconomyMath.kindness_combo(count, b.kindness_combo_step, b.kindness_combo_max)
	return Economy.payout_for(value * b.hearts_per_kindness * combo, id)

## What one hit of `amount` pays in Bones, read BEFORE it lands.
func _expected_hit(amount: float, id: StringName) -> float:
	return Economy.payout_for(amount * ItemDB.balance.bones_per_damage * Economy.grime_multiplier(), id)

# --- input ------------------------------------------------------------------------

func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = at - _mouse
	motion.button_mask = _mask
	_mouse = at
	_view.push_input(motion, true)

func _hover(at: Vector2) -> void:
	_view.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
	_move(at)
	await _frames(3)

func _press(at: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	if at != _mouse:
		_move(at)
	_mask |= 1 << (button - 1)
	_view.push_input(_button(at, button, true, shift), true)

func _release(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_mask &= ~(1 << (button - 1))
	_view.push_input(_button(at, button, false, false), true)

func _click(at: Vector2) -> void:
	_move(at)
	await _frames(2)
	_press(at)
	_release(at)
	await _frames(2)

func _release_all() -> void:
	if _mask & 2:
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	if _mask & 1:
		_release(_mouse, MOUSE_BUTTON_LEFT)

func _button(at: Vector2, button: int, pressed: bool, shift: bool) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = pressed
	click.button_mask = _mask
	click.shift_pressed = shift
	click.position = at
	click.global_position = at
	return click

func _key(code: Key, pressed: bool) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = pressed
	return key

# --- plumbing -----------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await get_tree().physics_frame

func _await(condition: Callable, frames: int) -> bool:
	for i in frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()

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
		want > 0.0 and absf(got - want) <= maxf(0.001, absf(want) * 0.01))
