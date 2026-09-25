extends Node

## Headless check of the verbs on everyday things (docs/decisions.md D67): the right button on a
## boombox, a lava lamp, a fish tank and the rest — every verb worked with synthetic events at
## its zone's real position, paid through the real pipeline, answered by his face, and silent
## once it is over.
##
##   Godot --headless --path <project> res://tests/integration/verbs_check.tscn
##
## The real game in a SubViewport, as `fidget_check` does it, and for the same reason: a verb is
## only worth testing on the road a real click takes — the viewport, the body's
## `_unhandled_input`, its `GestureZones`, then `ItemVerbs`.
##
## **Acts are measured on the payout probe, never on the balance.** Every one of these items
## trickles while it sits there (a boombox's placed rate, a hot tub's soak), and a flush landing
## in the middle of an act would be counted as the act. `Economy.paying_kind_act` is true only
## while an act's own payout is on the bus, which is what `item_check` reads for the same reason.
##
## Runs against its own save slot and settings file, and puts back what it pins. `_check(what,
## ok)` takes two arguments — a third is a parse error, and a parse error looks like a hang.

const TEST_SLOT := "verbs_check_slot"
const VIEW_SIZE := Vector2i(1100, 700)
const VerbTable := preload("res://tools/verb_table.gd")

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

## What the watched component fired, as [verb, paid]; the Hearts paid by acts; the kindness
## values put on the bus, and whether each was marked as the hand's. Members, not locals: a
## lambda captures locals by value (CLAUDE.md).
var _fired: Array = []
var _act_hearts := 0.0
var _acts: Array = []
## The value of the act the next `_work` should pay, and what that act is worth in Hearts,
## priced by `_work` itself at the moment it fires.
var _expect_for := 0.0
var _expected := 0.0

func _ready() -> void:
	# Before anything else (D51): the first landing of each of these teaches its controls, and
	# a hint marks itself seen and saves.
	Settings.config_path = "user://settings_verbs_check.cfg"
	_restore = {
		"focus": Settings.focus_intensity,
		"scale": Settings.ui_scale,
		"hud_pinned": Settings.hud_pinned,
		"tabs_pinned": Settings.tabs_pinned,
		"hints": Settings.hints_seen.duplicate(),
	}
	# Normal, not Off: most of what is checked here is the motion a verb makes.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.ui_scale = 1
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()

	print("")
	print("Bonehead Friend — verbs check")
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
	Economy.grant(Economy.HEARTS, 1.0e8)
	# The fan is filed with the toys and priced in Bones.
	Economy.grant(Economy.BONES, 1.0e8)
	# Several passes, because the kind ladder is chained by `requires`.
	for pass_ in 4:
		for item in ItemDB.all_items():
			if item.is_kind() and not Progression.is_unlocked(item.id):
				Progression.purchase_item(item.id)
	Economy.clear_temp_multipliers()
	EventBus.payout.connect(_on_payout)
	EventBus.kindness_given.connect(_on_kindness)

	_the_verbs_are_content()
	_his_face_knows_them()
	await _the_duck_squeaks()
	await _the_boombox_changes_track()
	await _the_chimes_ring()
	await _the_lights_change()
	await _the_lamp_churns()
	await _the_record_scratches()
	await _the_fish_are_fed()
	await _the_plant_is_watered()
	await _the_machine_blows_a_flurry()
	await _the_tea_is_stirred()
	await _the_jets_are_for_him()
	await _the_popper_is_pulled()
	await _the_fan_is_aimed()
	await _he_dances_on()
	await _the_grammar_holds()
	await _focus_off_still_pays()
	await _nothing_runs_at_rest()
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

func _on_payout(currency: StringName, amount: float, _at: Vector2, _source: StringName) -> void:
	if currency == Economy.HEARTS and Economy.paying_kind_act:
		_act_hearts += amount

func _on_kindness(source: StringName, value: float, _at: Vector2) -> void:
	_acts.append([source, value, ItemVerbs.paying])

func _on_fired(verb: StringName, paid: bool) -> void:
	_fired.append([verb, paid])

# --- content ---------------------------------------------------------------------------

func _the_verbs_are_content() -> void:
	_suite("content")
	var carried: Array[StringName] = []
	for item in ItemDB.all_items():
		if ItemVerbs.carried_by(item.id):
			carried.append(item.id)
	_check("the scenes carry exactly the table's verbs (%d scenes, %d rows)"
		% [carried.size(), VerbTable.VERBS.size()],
		carried.size() == VerbTable.VERBS.size()
		and carried.all(func(id: StringName) -> bool: return VerbTable.VERBS.has(id)))
	_check("at least eight everyday things have a verb", carried.size() >= 8)
	for id in VerbTable.VERBS:
		var item := ItemDB.get_item(id)
		if item == null:
			_check("%s is in the shop" % id, false)
			continue
		_check("%s says how to work it, in its own words" % id,
			item.controls == VerbTable.controls(id) and not item.controls.is_empty())
		var body := item.scene.instantiate() as BaseDraggable
		var zones: GestureZones = null
		var verbs: ItemVerbs = null
		for child in body.get_children():
			if child is GestureZones:
				zones = child
			elif child is ItemVerbs:
				verbs = child
		_check("%s carries its zones and its verbs" % id, zones != null and verbs != null)
		# Row for row: a table edited without its scene rebuilt through the seeder fails here,
		# rather than shipping the old verb under the new line.
		var entry: Dictionary = VerbTable.VERBS[id]
		_check("%s's scene is its table row, rebuilt" % id, zones != null and verbs != null
			and var_to_str(zones.zones) == var_to_str(entry.get("zones", []))
			and var_to_str(verbs.verbs) == var_to_str(entry.get("verbs", []))
			and zones.action_enabled == bool(entry.get("action", false)))
		# The item keeps what it was: a verb is a component, never a new class, so everything
		# that drives it by class — item_check above all — drives it as before.
		var cls := (body.get_script() as Script).get_global_name()
		_check("%s is still a %s" % [id, cls], cls == &"FriendlyBase" or cls == &"WindSource")
		if zones and verbs:
			var ids: Array[StringName] = []
			for row in zones.zones:
				ids.append(StringName((row as Dictionary)["id"]))
			for row in verbs.verbs:
				var r := row as Dictionary
				var wanted: Array = r.get("zones", [r.get("zone", &"")])
				var known := wanted.all(func(z) -> bool: return z == &"" or ids.has(z))
				_check("%s: %s fires on zones it has" % [id, r["id"]], known)
				if wanted.has(&""):
					_check("%s: %s is right-in-the-hand, and the hand is on" % [id, r["id"]],
						zones.action_enabled)
				var react := StringName(r.get("react", &""))
				if react != &"":
					_check("%s: %s is something his face answers ('%s')" % [id, r["id"], react],
						ExpressionBrain.FIDGET_ROWS.has(react))
				var sound := StringName(r.get("sound", &""))
				if sound != &"":
					_check("%s: %s makes a sound that exists ('%s')" % [id, r["id"], sound],
						AudioManager._pick(sound) != null)
				# The ceiling the table promises: no verb pays faster than petting does.
				var value := float(r.get("value", 0.0))
				if value > 0.0 and not bool(r.get("once", false)) and not bool(r.get("consume", false)):
					var rate := value / maxf(0.01, float(r.get("cooldown", 0.0)))
					_check("%s: %s pays at most 1.5 value a second however fast it is worked (%.2f)"
						% [id, r["id"], rate], rate <= 1.5)
		body.free()

func _his_face_knows_them() -> void:
	_suite("his face")
	for row in ExpressionBrain.FIDGET_ROWS.values():
		_check("fidget row %s exists" % row, ExpressionBrain.ROWS.has(row))
	for row in [&"grooving", &"marvel", &"pampered"]:
		_check("row %s exists" % row, ExpressionBrain.ROWS.has(row))
	_check("his face listens to the toys", EventBus.fidget_event.is_connected(_face._on_fidget_event))
	# A verb on an everyday thing is the hand's only while the verb pays: the tea is still
	# drunk, the duck still caught, the boombox still smiled at.
	_check("the boombox's trickle is not a hand at work", not _face._worked_by_hand(&"boombox"))
	_check("but a fidget toy's still is", _face._worked_by_hand(&"bubble_wrap"))
	var here := _buddy.global_position
	_face.clear()
	_face._on_kindness_given(&"cup_of_tea", 1.0, here)
	_check("tea with a verb on it is still drunk (beat '%s')" % _face.beat_id(), _face.beat_id() == &"eat")
	_face.clear()
	_face._on_kindness_given(&"rubber_duck", 1.0, here)
	_check("and the duck still caught (beat '%s')" % _face.beat_id(), _face.beat_id() == &"catch")
	_face.clear()
	ItemVerbs.paying = true
	_face._on_kindness_given(&"rubber_duck", 1.0, here)
	ItemVerbs.paying = false
	_check("but the verb's own act leaves him to the verb's row", not _face.beat_active())
	_face.clear()

# --- the verbs, one by one -------------------------------------------------------------------

func _the_duck_squeaks() -> void:
	_suite("rubber duck")
	var duck := await _fresh(&"rubber_duck", _beside_him(150.0))
	var verbs := _verbs_of(duck)
	if verbs == null:
		return
	await _act_once(duck, verbs, &"squeak", &"amused")
	_check("it squashes about its belly", verbs.is_busy() and not duck.sprite.scale.is_equal_approx(
		Vector2(2, 2)))
	await _pays_once_per_cooldown(duck, verbs, &"squeak")
	await get_tree().create_timer(0.4).timeout
	_check("and springs back exactly", duck.sprite.scale.is_equal_approx(Vector2(2, 2))
		and duck.sprite.position.is_zero_approx() and not verbs.is_busy())
	_check("a right-click on it squeaks rather than bins it", is_instance_valid(duck)
		and duck.is_inside_tree())
	_spawner_clear()

func _the_boombox_changes_track() -> void:
	_suite("boombox")
	var box := await _fresh(&"boombox", _beside_him(170.0))
	var verbs := _verbs_of(box)
	if verbs == null:
		return
	var row := verbs.row(&"next_track")
	var ambient := (box as FriendlyBase).ambient_emitter()
	_check("it starts on the first track, in its own teal", verbs.state_of(&"next_track") == 0
		and ambient != null and ambient.modulate == FriendlyBase.NOTE)
	await _act_once(box, verbs, &"next_track", &"grooving")
	var colours: Array = row["colours"]
	var speeds: Array = (row["effects"] as Array)[1]["speeds"]
	_check("the next track is next (%d)" % verbs.state_of(&"next_track"), verbs.state_of(&"next_track") == 1)
	_check("its notes are its own colour", ambient != null and ambient.modulate == colours[1])
	_check("and its own tempo (%.1f)" % ambient.speed_scale, is_equal_approx(ambient.speed_scale, speeds[1]))
	await _pays_once_per_cooldown(box, verbs, &"next_track")
	for i in 3:
		await _work(box, verbs.row(&"next_track"))
	_check("four tracks and round again (%d)" % verbs.state_of(&"next_track"),
		verbs.state_of(&"next_track") == (1 + 1 + 3) % 4)
	# Off the buttons it is a boombox: a right-click on a speaker still bins it (D57's grammar).
	var speaker := box.gesture_zones.art_to_world(Vector2(-12, 8))
	await _hover(speaker)
	_press(speaker, MOUSE_BUTTON_RIGHT)
	_release(speaker, MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("a right-click off the buttons still bins it", not is_instance_valid(box)
		or not box.is_inside_tree() or box.is_queued_for_deletion())
	_spawner_clear()

func _the_chimes_ring() -> void:
	_suite("wind chimes")
	var chimes := await _fresh(&"wind_chimes", _beside_him(150.0))
	var verbs := _verbs_of(chimes)
	if verbs == null:
		return
	await _clear_combo()
	_face.clear()
	_watch(verbs)
	_expect_for = 3.0 * _value_of(&"wind_chimes")
	await _work(chimes, verbs.row(&"ring"))
	_unwatch(verbs)
	var rings := _fired.filter(func(f: Array) -> bool: return f[0] == &"ring")
	_check("a stroke across the chimes rings every tube it crosses (%d)" % rings.size(), rings.size() == 3)
	_check("and pays once for the stroke", rings.filter(func(f: Array) -> bool: return f[1]).size() == 1)
	_check_near("one act's Hearts", _act_hearts, _expected)
	_check("he grooves to it (beat '%s')" % _face.beat_id(), _face.beat_id() == &"grooving")
	_check("and the chime rocks on its hook", verbs.is_busy() and not is_zero_approx(chimes.sprite.rotation))
	# The hook stays put while it rocks: the pivot's drawn position does not move.
	var hook := chimes.sprite.position + Vector2(0, -36).rotated(chimes.sprite.rotation)
	_check("about its hook (%.2f px off)" % hook.distance_to(Vector2(0, -36)),
		hook.distance_to(Vector2(0, -36)) < 0.01)
	_spawner_clear()

func _the_lights_change() -> void:
	_suite("fairy lights")
	var lights := await _fresh(&"fairy_lights", _beside_him(-190.0))
	var verbs := _verbs_of(lights)
	if verbs == null:
		return
	var ambient := (lights as FriendlyBase).ambient_emitter()
	var colours: Array = verbs.row(&"pattern")["colours"]
	await _act_once(lights, verbs, &"pattern", &"marvel")
	_check("the bulbs change colour", lights.sprite.modulate == colours[1])
	_check("and so does their twinkle", ambient != null
		and ambient.modulate.is_equal_approx(FriendlyBase.TWINKLE * colours[1]))
	for i in 3:
		await _work(lights, verbs.row(&"pattern"))
	_check("four patterns and back to warm", lights.sprite.modulate == Color.WHITE
		and ambient.modulate.is_equal_approx(FriendlyBase.TWINKLE))
	_spawner_clear()

func _the_lamp_churns() -> void:
	_suite("lava lamp")
	var lamp := await _fresh(&"lava_lamp", _beside_him(160.0))
	var verbs := _verbs_of(lamp)
	if verbs == null:
		return
	await _act_once(lamp, verbs, &"churn", &"marvel")
	var wax := verbs.emitter("churn0")
	_check("wax rises in the glass", wax != null and wax.emitting and wax.local_coords)
	_check("inside the glass, in the lamp's own frame", wax != null
		and absf(wax.position.x - (-2.0)) < 0.01 and wax.get_parent() == lamp)
	_check("and the lamp rocks on its foot", verbs.is_busy())
	await _pays_once_per_cooldown(lamp, verbs, &"churn")
	_spawner_clear()

func _the_record_scratches() -> void:
	_suite("record player")
	var deck := await _fresh(&"record_player", _beside_him(180.0))
	var verbs := _verbs_of(deck)
	if verbs == null:
		return
	await _clear_combo()
	_face.clear()
	_watch(verbs)
	_expect_for = 5.0 * _value_of(&"record_player")
	await _work(deck, verbs.row(&"scratch"))
	_unwatch(verbs)
	var scratches := _fired.filter(func(f: Array) -> bool: return f[0] == &"scratch")
	_check("a stroke back and forth is several scratches (%d)" % scratches.size(), scratches.size() >= 3)
	_check("and one act", scratches.filter(func(f: Array) -> bool: return f[1]).size() == 1)
	_check_near("one act's Hearts", _act_hearts, _expected)
	_check("he grooves to it (beat '%s')" % _face.beat_id(), _face.beat_id() == &"grooving")
	# A left press on the record is still a grab: the zone claims only the right button.
	var disc := deck.gesture_zones.zone_world(&"disc")
	await _hover(disc)
	_press(disc)
	_check("left on the record picks the player up", deck.dragging)
	_release(disc)
	await _settle()
	_spawner_clear()

func _the_fish_are_fed() -> void:
	_suite("fish tank")
	var tank := await _fresh(&"fish_tank", _beside_him(-220.0))
	var verbs := _verbs_of(tank)
	if verbs == null:
		return
	await _act_once(tank, verbs, &"feed", &"marvel")
	var flakes := verbs.emitter("feed0")
	var bubbles := verbs.emitter("feed2")
	_check("flakes fall from the lid", flakes != null and flakes.emitting)
	_check("and the water bubbles", bubbles != null and bubbles.emitting)
	await get_tree().create_timer(0.45).timeout
	var fish := verbs.emitter("feed1")
	_check("and a moment later the fish come up for it", fish != null and fish.emitting)
	await _pays_once_per_cooldown(tank, verbs, &"feed")
	_spawner_clear()

func _the_plant_is_watered() -> void:
	_suite("houseplant")
	var plant := await _fresh(&"houseplant", _beside_him(150.0))
	var verbs := _verbs_of(plant)
	if verbs == null:
		return
	await _act_once(plant, verbs, &"water", &"amused")
	_check("water falls on the leaves", verbs.emitter("water0") != null
		and verbs.emitter("water0").emitting)
	await get_tree().create_timer(0.55).timeout
	var s := plant.sprite
	_check("then it stands up taller (%.2f)" % (s.scale.y / 2.0), s.scale.y > 2.02)
	# About its pot's base: the bottom of the drawing has not moved.
	var base := s.position.y + 21.0 * s.scale.y
	_check("from its pot, which stays on the desk (%.2f px)" % absf(base - 42.0), absf(base - 42.0) < 0.01)
	await _pays_once_per_cooldown(plant, verbs, &"water")
	_spawner_clear()

func _the_machine_blows_a_flurry() -> void:
	_suite("bubble machine")
	var machine := await _fresh(&"bubble_machine", _beside_him(-170.0))
	var verbs := _verbs_of(machine)
	if verbs == null:
		return
	await _clear_combo()
	_face.clear()
	_watch(verbs)
	_expect_for = 5.0 * _value_of(&"bubble_machine")
	await _work(machine, verbs.row(&"flurry"))
	_unwatch(verbs)
	var winds := _fired.filter(func(f: Array) -> bool: return f[0] == &"wind")
	var flurries := _fired.filter(func(f: Array) -> bool: return f[0] == &"flurry")
	_check("a crank ticks every quarter turn (%d)" % winds.size(), winds.size() >= 4)
	_check("and a full turn blows a flurry (%d)" % flurries.size(), flurries.size() == 1 and flurries[0][1])
	_check_near("one act's Hearts", _act_hearts, _expected)
	_check("out of the chimney", verbs.emitter("flurry0") != null and verbs.emitter("flurry0").emitting)
	_check("he watches it (beat '%s')" % _face.beat_id(), _face.beat_id() == &"marvel")
	_spawner_clear()

func _the_tea_is_stirred() -> void:
	_suite("cup of tea")
	var tea := await _fresh(&"cup_of_tea", _beside_him(-200.0))
	var verbs := _verbs_of(tea)
	if verbs == null:
		return
	await _clear_combo()
	_face.clear()
	_watch(verbs)
	_expect_for = 5.0 * _value_of(&"cup_of_tea")
	await _work(tea, verbs.row(&"stirred"))
	var clinks := _fired.filter(func(f: Array) -> bool: return f[0] == &"clink")
	var stirs := _fired.filter(func(f: Array) -> bool: return f[0] == &"stirred")
	_check("a clink every half turn (%d)" % clinks.size(), clinks.size() >= 4)
	_check("and two turns make it a proper cup", stirs.size() == 1 and stirs[0][1])
	_check_near("which is one act", _act_hearts, _expected)
	_check("he is pleased (beat '%s')" % _face.beat_id(), _face.beat_id() == &"amused")
	_fired.clear()
	var again := _act_hearts
	await _work(tea, verbs.row(&"stirred"))
	_unwatch(verbs)
	stirs = _fired.filter(func(f: Array) -> bool: return f[0] == &"stirred")
	_check("stirred again it is the same cup: it pays once in its life", stirs.size() == 1
		and not stirs[0][1] and is_equal_approx(_act_hearts, again))
	_check("and it is still there to be drunk", is_instance_valid(tea) and tea.is_inside_tree())
	_spawner_clear()

func _the_jets_are_for_him() -> void:
	_suite("hot tub")
	var tub := await _fresh(&"hot_tub", _beside_him(260.0))
	var verbs := _verbs_of(tub)
	if verbs == null:
		return
	await _clear_combo()
	_face.clear()
	_watch(verbs)
	await _work(tub, verbs.row(&"jets"))
	_check("the jets run with nobody in it", verbs.emitter("jets0") != null
		and verbs.emitter("jets0").emitting)
	_check("and pay nothing", is_zero_approx(_act_hearts) and _fired.size() == 1 and not _fired[0][1])
	_check("and he has nothing to feel (beat '%s')" % _face.beat_id(), _face.beat_id() != &"pampered")
	# Put him in.
	tub.freeze = false
	await _drop_him_on(tub, 30.0)
	var touching := tub.get_colliding_bodies().has(_buddy)
	_check("he is in the tub", touching)
	await _clear_combo()
	_face.clear()
	_fired.clear()
	_expect_for = 10.0 * _value_of(&"hot_tub")
	await _work(tub, verbs.row(&"jets"))
	_unwatch(verbs)
	_check("with him in it the jets pay", _fired.size() == 1 and _fired[0][1])
	_check_near("one act's Hearts, apart from the soak it is already paying", _act_hearts, _expected)
	_check("and he loves it (beat '%s')" % _face.beat_id(), _face.beat_id() == &"pampered")
	_spawner_clear()
	await _stand_him_up(Vector2(420, 560))

func _the_popper_is_pulled() -> void:
	_suite("party popper")
	var popper := await _fresh(&"party_popper", _beside_him(150.0))
	var verbs := _verbs_of(popper)
	if verbs == null:
		return
	await _clear_combo()
	_face.clear()
	_watch(verbs)
	_acts.clear()
	var count := _spawner.item_count()
	_expect_for = 45.0 * _value_of(&"party_popper")
	await _work(popper, verbs.row(&"pull"))
	_unwatch(verbs)
	_check("right while holding it pulls the string", _fired.size() == 1 and _fired[0][1])
	_check_near("near him it pays what a throw pays", _act_hearts, _expected)
	_check("marked as the hand's while it paid", _acts.size() == 1 and _acts[0][2])
	_check("and he laughs (beat '%s')" % _face.beat_id(), _face.beat_id() == &"laugh")
	await _settle()
	_check("and it is used up, so it can never pay twice", not is_instance_valid(popper)
		or popper.is_queued_for_deletion() or _spawner.item_count() < count)

	# Out of earshot: confetti for nobody.
	var far := await _fresh(&"party_popper", _beside_him(460.0))
	verbs = _verbs_of(far)
	if verbs == null:
		return
	_watch(verbs)
	await _work(far, verbs.row(&"pull"))
	_unwatch(verbs)
	_check("pulled far from him it pays nothing", _fired.size() == 1 and not _fired[0][1]
		and is_zero_approx(_act_hearts))
	await _settle()
	_check("and is still used up", not is_instance_valid(far) or far.is_queued_for_deletion())
	_spawner_clear()

## The fan: a right-drag from its face points the wind, and the wind goes where it points.
func _the_fan_is_aimed() -> void:
	_suite("desk fan")
	var fan := await _fresh(&"desk_fan", _beside_him(-180.0)) as WindSource
	var verbs := _verbs_of(fan)
	if verbs == null or fan == null:
		return
	_check("it blows right as it always did", fan.blow_direction.is_equal_approx(Vector2.RIGHT)
		and is_zero_approx(fan.wind_area.rotation))
	var face := fan.gesture_zones.zone_world(&"face")
	_press(face, MOUSE_BUTTON_RIGHT)
	_move(face + Vector2(-40, -10))
	_move(fan.global_position + Vector2(-160, -80), Vector2(-300, -150))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	await _settle()
	var want := Vector2(-160, -80).normalized()
	_check("a right-drag from its face aims it at the cursor (%s)" % fan.blow_direction,
		fan.blow_direction.is_equal_approx(want))
	_check("and the wind turns with it", is_equal_approx(wrapf(fan.wind_area.rotation, -PI, PI),
		want.angle()))
	_check("without the stand moving", is_zero_approx(fan.rotation) and fan.is_inside_tree())
	# Up and a little right: steeper than the stop. Not higher than this, or the drag passes
	# under the controls toast the fan's first landing put up, and the GUI takes its motion.
	_press(face, MOUSE_BUTTON_RIGHT)
	_move(fan.global_position + Vector2(40, -120))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("never straight at the ceiling: 50 degrees at most (%.1f)"
		% rad_to_deg(-fan.blow_direction.angle()),
		absf(fan.blow_direction.angle() + WindSource.MAX_TILT) < 0.001)
	# And it blows what is now in front of it: aim it left, level, and a duck there moves left.
	_press(face, MOUSE_BUTTON_RIGHT)
	_move(fan.global_position + Vector2(-200, 0))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("aimed left and level", fan.blow_direction.is_equal_approx(Vector2.LEFT))
	# Away from him, so nothing but the wall stops it. Measured from the moment it lands on the
	# desk, not after `_fresh`'s settling frames: it is being blown the whole time.
	var at := fan.global_position + Vector2(-110, 0)
	EventBus.spawn_requested.emit(&"rubber_duck", at)
	await _frames(20)
	var duck: BaseDraggable = null
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		if (node as BaseDraggable).item_id == &"rubber_duck":
			duck = node
	_check("what is in front of it now is blown away from it (%.0f px)"
		% ((duck.global_position.x - at.x) if duck else 0.0),
		duck != null and duck.global_position.x < at.x - 10.0)
	_spawner_clear()

# --- him, dancing ------------------------------------------------------------------------

## The whole loop: he wanders over to the boombox and dances, the player changes the track, he
## does a new move — and dances on, because the verb on the toy he is at is not somebody
## arriving and a beat over a routine goes back to it.
func _he_dances_on() -> void:
	_suite("he dances on")
	_spawner_clear()
	await _stand_him_up(Vector2(420, 560))
	var box := await _fresh(&"boombox", Vector2(_buddy.global_position.x + 170.0, 560))
	var verbs := _verbs_of(box)
	if verbs == null:
		return
	await _frames(40)
	_idle.pretend_idle()
	_idle.think_now()
	for i in 480:
		await get_tree().physics_frame
		if _idle.phase_name() == IdleBrain.PHASE_PLAYING and i > 30:
			break
	_check("he goes to the boombox to dance (phase '%s', target '%s')"
		% [_idle.phase_name(), _idle.target_id()],
		_idle.phase_name() == IdleBrain.PHASE_PLAYING and _idle.target_id() == &"boombox")
	if _face.beat_id() == &"arrived":
		_face.clear()
	_check("and dances (beat '%s')" % _face.beat_id(), _face.beat_id() == &"dancing")
	box.freeze = true
	await _work(box, verbs.row(&"next_track"))
	_check("a new track is a new move (beat '%s')" % _face.beat_id(), _face.beat_id() == &"grooving")
	_check("and does not send him away from it (phase '%s')" % _idle.phase_name(),
		_idle.phase_name() == IdleBrain.PHASE_PLAYING)
	_face.clear()
	_check("then he dances on (beat '%s')" % _face.beat_id(), _face.beat_id() == &"dancing")
	_idle._disturb()
	_spawner_clear()

# --- the grammar --------------------------------------------------------------------------

func _the_grammar_holds() -> void:
	_suite("the grammar")
	var tank := await _fresh(&"fish_tank", _beside_him(-220.0))
	if tank == null:
		_check("a fish tank is on the desk", false)
		return
	var lid := tank.gesture_zones.zone_world(&"lid")
	_move(lid)
	_check("over the lid, the pointing hand", tank.gesture_zones.hover_zone == &"lid"
		and tank.gesture_zones.cursor_shape == Input.CURSOR_POINTING_HAND)
	var count := _spawner.item_count()
	await _hover(lid)
	_press(lid, MOUSE_BUTTON_RIGHT, true)
	_release(lid, MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("Shift+right on a verb's zone bins the item, zone or no zone",
		not is_instance_valid(tank) or not tank.is_inside_tree() or _spawner.item_count() < count)
	_move(Vector2(40, 400))
	_spawner_clear()

func _focus_off_still_pays() -> void:
	_suite("focus off")
	Settings.focus_intensity = Settings.Intensity.OFF
	var lamp := await _fresh(&"lava_lamp", _beside_him(160.0))
	var verbs := _verbs_of(lamp)
	if verbs != null:
		await _clear_combo()
		_watch(verbs)
		await _work(lamp, verbs.row(&"churn"))
		_unwatch(verbs)
		_check("at Focus Off a verb still pays", _fired.size() == 1 and _fired[0][1]
			and _act_hearts > 0.0)
		_check("and nothing on the desk moves", not verbs.is_busy()
			and lamp.sprite.rotation == 0.0)
	var lights := await _fresh(&"fairy_lights", _beside_him(-190.0))
	verbs = _verbs_of(lights)
	if verbs != null:
		await _work(lights, verbs.row(&"pattern"))
		_check("but a pattern is a state, not a motion: it changes", lights.sprite.modulate
			== (verbs.row(&"pattern")["colours"] as Array)[1])
	Settings.focus_intensity = Settings.Intensity.NORMAL
	_spawner_clear()

func _nothing_runs_at_rest() -> void:
	_suite("nothing runs at rest")
	var script := load("res://Scripts/Bodies/item_verbs.gd") as Script
	var methods: Array[String] = []
	for method in script.get_script_method_list():
		methods.append(String(method["name"]))
	_check("ItemVerbs has no frame callback and no input of its own",
		not methods.has("_process") and not methods.has("_physics_process")
		and not methods.has("_input") and not methods.has("_unhandled_input"))
	# Every verb item on the desk, each worked once, then left alone for longer than the
	# longest effect lasts.
	var bodies: Array[BaseDraggable] = []
	var x := -380.0
	for id in [&"boombox", &"lava_lamp", &"fish_tank", &"houseplant", &"fairy_lights",
			&"wind_chimes", &"rubber_duck", &"record_player"]:
		var body := await _fresh(id, _beside_him(x))
		x += 100.0
		if body:
			bodies.append(body)
			var verbs := _verbs_of(body)
			if verbs:
				await _work(body, verbs.verbs[0])
	await get_tree().create_timer(5.6).timeout
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var verbs := _verbs_of(body)
		_check("%s at rest: its verbs run nothing" % body.item_id, verbs != null
			and not verbs.is_processing() and not verbs.is_physics_processing()
			and not verbs.is_busy())
		_check("%s: and its zones are idle" % body.item_id, body.gesture_zones != null
			and not body.gesture_zones.is_pressed()
			and (body.gesture_zones.get_node("HoldTimer") as Timer).is_stopped())
		_check("%s: and the sprite is back where it was drawn" % body.item_id,
			body.sprite.position.is_zero_approx() and body.sprite.rotation == 0.0
			and body.sprite.scale.is_equal_approx(Vector2(2, 2)))
	_spawner_clear()

# --- driving a verb -------------------------------------------------------------------------

## One act of `verb`: it fires and pays one act's Hearts through the real pipeline, at the
## multipliers in force when it fired, and his face answers with `row`.
func _act_once(body: BaseDraggable, verbs: ItemVerbs, verb: StringName, row: StringName) -> void:
	await _clear_combo()
	_face.clear()
	_watch(verbs)
	var r := verbs.row(verb)
	_expect_for = float(r["value"]) * _value_of(body.item_id)
	_acts.clear()
	await _work(body, r)
	_unwatch(verbs)
	var mine := _fired.filter(func(f: Array) -> bool: return f[0] == verb)
	_check("%s: a right-click %s it" % [body.item_id, verb], mine.size() == 1 and mine[0][1])
	_check_near("%s: one act's Hearts" % body.item_id, _act_hearts, _expected)
	_check("%s: as the hand's act, on the bus as a kindness value" % body.item_id,
		_acts.size() == 1 and _acts[0][0] == body.item_id and _acts[0][2])
	_check("%s: he answers with '%s' (beat '%s')" % [body.item_id, row, _face.beat_id()],
		_face.beat_id() == row)

## Worked again at once it still plays and pays nothing: one act per cooldown.
func _pays_once_per_cooldown(body: BaseDraggable, verbs: ItemVerbs, verb: StringName) -> void:
	_watch(verbs)
	await _work(body, verbs.row(verb))
	_unwatch(verbs)
	var mine := _fired.filter(func(f: Array) -> bool: return f[0] == verb)
	_check("%s: worked again at once it still %s" % [body.item_id, verb], mine.size() == 1)
	_check("%s: and pays nothing until its cooldown is up" % body.item_id,
		not mine.is_empty() and not mine[0][1] and is_zero_approx(_act_hearts))

## Works a verb the way a player would: synthetic events at the zone's real position. If
## `_expect_for` is set, one act of that value is priced into `_expected` at the last moment
## before the events that fire it — after any frames the approach took, because his mood
## drifts home frame by frame and Economy pays at the mood in force when the act lands.
func _work(body: BaseDraggable, r: Dictionary) -> void:
	var zones := body.gesture_zones
	var on = r.get("on", "tap")
	var words: Array = on if on is Array else [on]
	if words.has("action"):
		var grip := body.global_position
		await _hover(grip)
		_press(grip)
		_price(body)
		_press(grip, MOUSE_BUTTON_RIGHT)
		_release(grip, MOUSE_BUTTON_RIGHT)
		_release(grip)
		await _settle()
		return
	var zone_ids: Array = r.get("zones", [r.get("zone", &"")])
	var at := zones.zone_world(zone_ids[0])
	_price(body)
	if words.has("tap"):
		_press(at, MOUSE_BUTTON_RIGHT)
		_release(at, MOUSE_BUTTON_RIGHT)
	elif words.has("cross") or words.has("press"):
		# One stroke, start to end, across every zone it names.
		_press(at, MOUSE_BUTTON_RIGHT)
		for z in zone_ids.slice(1):
			_move(zones.zone_world(z), Vector2(600, 0))
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	elif words.has("crank"):
		# Just past one firing of the verb asked for: a sixteenth of a turn a step, and two more.
		var radius := Vector2(8, 0)
		_press(at + radius, MOUSE_BUTTON_RIGHT)
		var steps := int(ceil(float(r.get("every", TAU)) / TAU * 16.0)) + 2
		for step in range(1, steps + 1):
			_move(at + radius.rotated(TAU * float(step) / 16.0))
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	elif words.has("drag"):
		_press(at, MOUSE_BUTTON_RIGHT)
		for i in 4:
			_move(at + Vector2(12.0 if i % 2 == 0 else -12.0, 0.0), Vector2(400, 0))
		_release(_mouse, MOUSE_BUTTON_RIGHT)
	await _settle()

func _price(body: BaseDraggable) -> void:
	if _expect_for > 0.0:
		_expected = _expected_act(_expect_for, body.item_id)
		_expect_for = 0.0

func _watch(verbs: ItemVerbs) -> void:
	_fired.clear()
	_act_hearts = 0.0
	if not verbs.fired.is_connected(_on_fired):
		verbs.fired.connect(_on_fired)

## Untyped on purpose: a popper that has popped is freed by the time this runs, and a freed
## object handed to a typed parameter is a script error rather than an invalid instance.
func _unwatch(verbs) -> void:
	if is_instance_valid(verbs) and (verbs as ItemVerbs).fired.is_connected(_on_fired):
		(verbs as ItemVerbs).fired.disconnect(_on_fired)

func _verbs_of(body: BaseDraggable) -> ItemVerbs:
	if body == null or not is_instance_valid(body):
		_check("the item is on the desk", false)
		return null
	body.freeze = true
	for child in body.get_children():
		if child is ItemVerbs:
			return child
	_check("%s carries verbs" % body.item_id, false)
	return null

func _value_of(id: StringName) -> float:
	return Progression.get_modifier(id, &"damage_mult")

# --- staging ---------------------------------------------------------------------------------

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

func _drop_him_on(toy: BaseDraggable, height: float) -> void:
	_idle._disturb()
	var top := toy.get_interaction_rect().position.y
	var feet := _buddy.get_interaction_rect().end.y
	_buddy.global_rotation = 0.0
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	_buddy.global_position += Vector2(toy.global_position.x - _buddy.global_position.x,
		top - height - feet)
	await _frames(50)

func _clear_combo() -> void:
	if Economy.combo_seconds_left() > 0.0:
		await get_tree().create_timer(Economy.combo_seconds_left() + 0.05).timeout

## What one kindness act of `value` pays in Hearts, read BEFORE it is emitted (CLAUDE.md).
func _expected_act(value: float, id: StringName) -> float:
	var b := ItemDB.balance
	var count: int = Economy._combo_count + 1 if Economy.combo_seconds_left() > 0.0 else 0
	var combo := EconomyMath.kindness_combo(count, b.kindness_combo_step, b.kindness_combo_max)
	return Economy.payout_for(value * b.hearts_per_kindness * combo, id)

# --- input --------------------------------------------------------------------------------------

func _move(at: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = at - _mouse
	motion.velocity = velocity
	motion.button_mask = _mask
	_mouse = at
	_view.push_input(motion, true)

func _hover(at: Vector2) -> void:
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

func _click(at: Vector2, button: int, pressed: bool, shift: bool) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = pressed
	click.button_mask = _mask
	click.shift_pressed = shift
	click.position = at
	click.global_position = at
	return click

# --- plumbing --------------------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await get_tree().physics_frame

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
