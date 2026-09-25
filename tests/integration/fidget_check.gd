extends Node

## Headless check of the fidget layer (docs/decisions.md D57): click zones and gestures, the
## first five toys, what he does with each of them, and what the shop says about them.
##
##   Godot --headless --path <project> res://tests/integration/fidget_check.tscn
##
## The real game in a SubViewport, as `ui_check` does it: a headless root viewport is 64x64,
## and a gesture is only worth testing on the road real events take — through the viewport,
## into `BaseDraggable._unhandled_input`, into `GestureZones`. Every gesture here is a
## synthetic event at a real position. Where a test calls a toy directly instead (a forced
## fortune, a fast-forwarded spin), the line says why.
##
## Runs against its own save slot and its own settings file, and puts back what it pins.
## `_check(what, ok)` takes two arguments, like loop_check's — a third is a parse error, and a
## parse error here looks like a hang (CLAUDE.md).

const TEST_SLOT := "fidget_check_slot"
const VIEW_SIZE := Vector2i(1100, 700)
const FIDGETS: Array[StringName] = [&"bubble_wrap", &"stress_ball", &"fidget_spinner",
	&"magic_eight_ball", &"jack_in_the_box"]

var _passed := 0
var _failed := 0
var _view: SubViewport
var _main: Node
var _restore := {}
var _buddy: Buddy
var _face: ExpressionBrain
var _idle: IdleBrain
var _spawner: ItemSpawner

## The buttons held down, for the motion events' mask, and where the cursor last was.
var _mask := 0
var _mouse := Vector2.ZERO

## Gestures seen on whichever toy is being watched. A member, not a local: a lambda captures
## locals by value (CLAUDE.md).
var _seen: Array[StringName] = []

func _ready() -> void:
	# Before anything else (D51): a one-off hint marks itself seen and saves, and this suite
	# puts toys on the desk on purpose.
	Settings.config_path = "user://settings_fidget_check.cfg"
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
	print("Bonehead Friend — fidget check")
	print("==============================")

	_view = SubViewport.new()
	_view.size = VIEW_SIZE
	_view.handle_input_locally = true
	_view.physics_object_picking = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	# No container above it, so it has to be told the mouse is in it, or physics picking —
	# which is what makes a grab a grab — never runs (CLAUDE.md).
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
	for id in FIDGETS:
		Progression.purchase_item(id)

	_the_toys_are_content()
	await _the_grammar_is_wired()
	await _bubble_wrap_pops()
	await _the_spinner_spins()
	await _the_jack_pops_out()
	await _the_ball_tells_fortunes()
	await _the_ball_squeezes_and_is_caught()
	await _zones_follow_a_turned_body()
	await _hover_shows_the_hand()
	await _shift_right_always_bins()
	await _nothing_runs_at_rest()
	await _he_plays_with_every_one()
	await _the_shop_says_how()
	_finish()

func _finish() -> void:
	_spawner_clear()
	print("")
	print("==============================")
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
	for id in FIDGETS:
		var item := ItemDB.get_item(id)
		_check("%s is in the shop" % id, item != null)
		if item == null:
			continue
		_check("%s is filed in Play, priced in Hearts" % id,
			item.category == ItemData.CATEGORY_TOY and item.currency == ItemData.CURRENCY_HEARTS)
		_check("%s says how to work it" % id, not item.controls.is_empty())
		_check("%s has a picture and an icon" % id,
			item.icon != null and ResourceLoader.exists("res://Assets/sprites/items/%s.png" % id))
		var keys := {}
		var capstone := false
		for node in ItemDB.augments_for(id):
			keys[node.effect_key] = true
			capstone = capstone or node.is_automation
		# Every key is one the toy reads: value (pay_act / pay_sustained), Hearts (Economy),
		# and "time between uses" (each toy's own rate). Anything else would be a placebo.
		_check("%s has a tree of value, payout and pace, and a capstone" % id,
			keys.has(&"damage_mult") and keys.has(&"payout_mult") and keys.has(&"cooldown_mult")
			and keys.size() == 3 and capstone)

# --- the grammar -------------------------------------------------------------------

func _the_grammar_is_wired() -> void:
	_suite("the grammar")
	_check("his face listens to the toys",
		EventBus.fidget_event.is_connected(_face._on_fidget_event))
	for row in ExpressionBrain.FIDGET_ROWS.values():
		_check("fidget row %s exists" % row, ExpressionBrain.ROWS.has(row))
	_check("his fidget routine has a hold",
		ExpressionBrain.ROUTINE_HOLDS.get(IdleBrain.ROUTINE_FIDGET, &"") == &"fiddling")
	_check("and the brain pays nothing for it — the toy does",
		not _idle._brain_pays(IdleBrain.ROUTINE_FIDGET))
	var wrap := await _fresh(&"bubble_wrap", Vector2(700, 600))
	if wrap == null:
		_check("a bubble wrap can be put on the desk", false)
		return
	var zones := (wrap as FidgetToy).gestures
	_check("the zones found their body by what it is", zones != null and wrap.gesture_zones == zones)
	_check("the bubble wrap has eight bubbles and its film",
		zones != null and zones.zone_ids().size() == 9)
	# Code lines only: the class comment names the call it must never make.
	var polls := false
	for line in FileAccess.get_file_as_string("res://Scripts/Bodies/gesture_zones.gd").split("\n"):
		if not line.strip_edges().begins_with("#") and line.contains("mouse_position("):
			polls = true
	_check("the zones never read the OS cursor", not polls)
	_spawner_clear()

	# Every kind of gesture a zone can produce, on one real zone: the jack's crank.
	var jack := await _fresh(&"jack_in_the_box", _beside_him(170.0)) as JackInTheBox
	if jack == null:
		_check("a jack-in-the-box is on the desk", false)
		return
	jack.freeze = true
	jack.set_facing(1.0)
	var pivot := jack.gestures.zone_world(&"crank")
	var on := pivot + Vector2(10, 0)
	jack.gestures.gesture.connect(_record)
	_seen.clear()
	_press(on, MOUSE_BUTTON_RIGHT)
	_release(on, MOUSE_BUTTON_RIGHT)
	_check("a quick press is PRESS, TAP, RELEASE (%s)" % ", ".join(_seen),
		_seen == [GestureZones.PRESS, GestureZones.TAP, GestureZones.RELEASE])
	_seen.clear()
	_press(on, MOUSE_BUTTON_RIGHT)
	await get_tree().create_timer(jack.gestures.hold_seconds + 0.2).timeout
	_release(on, MOUSE_BUTTON_RIGHT)
	_check("a still press held is a HOLD, and then not a tap (%s)" % ", ".join(_seen),
		_seen == [GestureZones.PRESS, GestureZones.HOLD, GestureZones.RELEASE])
	_seen.clear()
	_press(on, MOUSE_BUTTON_RIGHT)
	_move(pivot + Vector2(0, 10), Vector2(-600, 600))
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_check("a moving press is DRAG and CRANK, and a fast release a FLICK (%s)" % ", ".join(_seen),
		_seen.has(GestureZones.DRAG) and _seen.has(GestureZones.CRANK)
		and _seen.has(GestureZones.FLICK) and _seen.back() == GestureZones.RELEASE
		and not _seen.has(GestureZones.TAP))
	jack.gestures.gesture.disconnect(_record)
	_spawner_clear()

# --- bubble wrap ---------------------------------------------------------------------

func _bubble_wrap_pops() -> void:
	_suite("bubble wrap")
	var wrap := await _fresh(&"bubble_wrap", Vector2(620, 600)) as BubbleWrap
	if wrap == null:
		_check("a bubble wrap is on the desk", false)
		return
	var zones := wrap.gestures
	wrap.freeze = true
	await _clear_combo()
	_face.clear()

	# Left-tap a bubble: it pops, and pays one kindness act, in Hearts, through the bus.
	var hearts := Economy.balance_of(Economy.HEARTS)
	var bones := Economy.balance_of(Economy.BONES)
	var expected := _expected_act(wrap.pop_value * wrap.value_multiplier(), &"bubble_wrap")
	var at := zones.zone_world(&"b0")
	_press(at)
	_release(at)
	await _settle()
	_check("a left tap pops a bubble", wrap.is_popped(0))
	_check("and does not pick the sheet up", not wrap.dragging)
	_check_near("it pays one pop in Hearts", Economy.balance_of(Economy.HEARTS) - hearts, expected)
	_check("and no Bones", is_equal_approx(Economy.balance_of(Economy.BONES), bones))
	_check("he is amused by it (beat '%s')" % _face.beat_id(), _face.beat_id() == &"amused")
	_check("a popped bubble claims nothing any more", not zones.zone_enabled(&"b0"))

	# A left press on a bubble that turns into a drag is a grab, and the bubble survives it.
	var b1 := zones.zone_world(&"b1")
	await _hover(b1)
	_press(b1)
	_move(b1 + Vector2(24, -4))
	_check("pressing a bubble and dragging lifts the sheet instead", wrap.dragging)
	_check("and the bubble under the press is still there", not wrap.is_popped(1))
	_release(b1 + Vector2(24, -4))
	await _settle()
	_check("letting go puts it down", not wrap.dragging)

	# A popped bubble is sheet: a left press there grabs.
	await _hover(at)
	_press(at)
	_check("a left press on a popped bubble grabs the sheet", wrap.dragging)
	_release(at)
	await _settle()

	# A right-stroke starting on the film pops a run, in one fast motion.
	_seen.clear()
	zones.gesture.connect(_record)
	await _clear_combo()
	var run_hearts := Economy.balance_of(Economy.HEARTS)
	_press(at, MOUSE_BUTTON_RIGHT)
	_move(zones.zone_world(&"b3"), Vector2(1200, 0))
	_release(zones.zone_world(&"b3"), MOUSE_BUTTON_RIGHT)
	await _settle()
	zones.gesture.disconnect(_record)
	_check("a right-stroke pops the whole run it passes over (b1, b2, b3)",
		wrap.is_popped(1) and wrap.is_popped(2) and wrap.is_popped(3))
	_check("and leaves the other row alone", not wrap.is_popped(4) and not wrap.is_popped(7))
	_check("it arrives as crossings (%s)" % ", ".join(_seen),
		_seen.count(GestureZones.CROSS) >= 3)
	_check("the run pays", Economy.balance_of(Economy.HEARTS) > run_hearts)
	_check("and the sheet was never binned by the right button", is_instance_valid(wrap)
		and wrap.is_inside_tree())

	# Bubbles grow back, one at a time, and claim again. Run on a short fuse rather than four
	# real seconds.
	var popped := 8 - wrap.intact_count()
	wrap._regrow.start(0.05)
	await get_tree().create_timer(0.2).timeout
	_check("a bubble grows back (%d flat before, %d now)" % [popped, 8 - wrap.intact_count()],
		8 - wrap.intact_count() == popped - 1)
	_check("and claims its tap again", zones.zone_enabled(&"b0"))

	# He pops them by coming down on it. Dropped from a height that cannot hurt him.
	wrap.freeze = false
	await _frames(20)
	var intact := wrap.intact_count()
	var him_hearts := Economy.balance_of(Economy.HEARTS)
	await _drop_him_on(wrap, 40.0)
	_check("he lands on it and a bubble goes (%d -> %d)" % [intact, wrap.intact_count()],
		wrap.intact_count() < intact)
	_check("and that pays too", Economy.balance_of(Economy.HEARTS) > him_hearts)
	_spawner_clear()

# --- the spinner ------------------------------------------------------------------

func _the_spinner_spins() -> void:
	_suite("fidget spinner")
	var spinner := await _fresh(&"fidget_spinner", _beside_him(150.0)) as FidgetSpinner
	if spinner == null:
		_check("a spinner is on the desk", false)
		return
	spinner.freeze = true
	var hub := spinner.rotor.global_position
	_check("it is at rest and costs nothing", not spinner.is_processing() and not spinner.is_spinning())

	# A right-swipe up across the right-hand arm: counter-clockwise, fast.
	var from := hub + Vector2(18, 10)
	_press(from, MOUSE_BUTTON_RIGHT)
	_move(hub + Vector2(20, -8), Vector2(0, -900))
	_release(hub + Vector2(20, -8), MOUSE_BUTTON_RIGHT)
	_check("a right-swipe across an arm spins it (%.1f rad/s)" % spinner.spin,
		spinner.is_spinning() and spinner.spin < 0.0)
	_check("as fast as the swipe, capped", absf(spinner.spin) <= spinner.max_spin + 0.01
		and absf(spinner.spin) > spinner.max_spin * 0.5)
	_check("and only now does it run a frame", spinner.is_processing())

	# While it spins in front of him, it pays and he stares at it.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	_face.clear()
	var hearts := Economy.balance_of(Economy.HEARTS)
	var watched := false
	for i in 90:
		await get_tree().process_frame
		watched = watched or _face.beat_id() == &"entranced"
	_check("it pays while he watches it spin", Economy.balance_of(Economy.HEARTS) > hearts)
	_check("and he is entranced by it", watched)
	Settings.focus_intensity = Settings.Intensity.OFF

	# Runs down over about half a minute, then settles on a third of a turn. Fast-forwarded:
	# thirty real seconds is not a test.
	var seconds := 0.0
	while spinner.is_spinning() and seconds < 120.0:
		spinner._process(0.05)
		seconds += 0.05
	_check("it runs down in about half a minute (%.1f s from full)" % seconds,
		seconds >= 18.0 and seconds <= 45.0)
	var guard := 0
	while spinner.is_processing() and guard < 400:
		spinner._process(0.05)
		guard += 1
	var third := fposmod(spinner.rotor.rotation, TAU / 3.0)
	_check("and comes to rest on a third of a turn (%.3f off)" % minf(third, TAU / 3.0 - third),
		minf(third, TAU / 3.0 - third) < 0.01)
	_check("and stops running frames", not spinner.is_processing())

	# The hub is not a zone: a left press there is a grab.
	await _hover(hub)
	_press(hub)
	_check("a left press on the hub picks it up", spinner.dragging)
	# In the hand, right on an arm is still the arm's, not the bin: a zone that claims the
	# right button comes before the body's own right-click.
	var arm := hub + Vector2(18, 10)
	_press(arm, MOUSE_BUTTON_RIGHT)
	_check("held, a right press on an arm is the arm's (zone '%s')"
		% spinner.gestures.pressed_zone(), spinner.gestures.pressed_zone() == &"arms")
	_check("and never bins what you are holding", spinner.is_inside_tree()
		and not spinner.is_queued_for_deletion())
	_release(arm, MOUSE_BUTTON_RIGHT)
	_release(arm)
	await _settle()

	# He flicks it himself.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	spinner.idle_use(_buddy)
	_check("left alone with it, he flicks it", spinner.is_spinning())
	spinner.launch(0.0, false)
	# At Off he is simply there: it pays and nothing on the desk moves.
	Settings.focus_intensity = Settings.Intensity.OFF
	var off_rotation := spinner.rotor.rotation
	spinner.idle_use(_buddy)
	_check("at Focus Off his flick moves nothing", not spinner.is_spinning()
		and is_equal_approx(spinner.rotor.rotation, off_rotation))
	_spawner_clear()

# --- the jack --------------------------------------------------------------------

func _the_jack_pops_out() -> void:
	_suite("jack-in-the-box")
	var jack := await _fresh(&"jack_in_the_box", _beside_him(170.0)) as JackInTheBox
	if jack == null:
		_check("a jack-in-the-box is on the desk", false)
		return
	jack.freeze = true
	jack.set_facing(1.0)
	_buddy.mood.set_value(0.0)
	_check("the crank is on the right as drawn", jack.crank.position.x > 0.0)
	_check("and the lid claims nothing while it is shut", not jack.gestures.zone_enabled(&"lid"))
	await _clear_combo()
	_face.clear()

	_seen.clear()
	jack.gestures.gesture.connect(_record)
	var hearts := Economy.balance_of(Economy.HEARTS)
	var turns := await _crank(jack, 12)
	jack.gestures.gesture.disconnect(_record)
	_check("right-dragging circles on the crank winds it (%d crank events)"
		% _seen.count(GestureZones.CRANK), _seen.count(GestureZones.CRANK) > 20)
	_check("a plink per quarter turn (%d quarters)" % jack._quarters, jack._quarters >= 4 * 6)
	_check("it pops after six to ten turns (%.1f)" % turns, jack.is_out()
		and turns >= jack.min_turns - 0.3 and turns <= jack.max_turns + 0.3)
	_check("the lid is thrown open", absf(jack.lid.rotation) > 1.0)
	_check("he startles (beat '%s')" % _face.beat_id(), _face.beat_id() == &"startled")
	_check("the lid is live now it is open", jack.gestures.zone_enabled(&"lid"))
	var expected := _expected_act(jack.laugh_value * jack.value_multiplier(), &"jack_in_the_box")
	await get_tree().create_timer(JackInTheBox.LAUGH_DELAY + 0.15).timeout
	_check("then he laughs (beat '%s')" % _face.beat_id(), _face.beat_id() == &"laugh")
	_check_near("and the laugh is the Hearts", Economy.balance_of(Economy.HEARTS) - hearts, expected)

	# Right-tap the lid: back in, shut, ready again.
	var lid_at := jack.gestures.zone_world(&"lid")
	_press(lid_at, MOUSE_BUTTON_RIGHT)
	_release(lid_at, MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("a right-tap on the lid puts him back", not jack.is_out())
	_check("and the tune starts again from nothing", is_zero_approx(jack.turns_wound()))
	_check("the box is still on the desk", is_instance_valid(jack) and jack.is_inside_tree())

	# Miserable, the pop only frightens him.
	await _clear_combo()
	_buddy.mood.set_value(-90.0)
	var sad_hearts := Economy.balance_of(Economy.HEARTS)
	await _crank(jack, 12)
	await get_tree().create_timer(JackInTheBox.LAUGH_DELAY + 0.15).timeout
	_check("in a black mood he does not laugh (beat '%s')" % _face.beat_id(),
		_face.beat_id() != &"laugh")
	_check("and a laugh he did not have pays nothing",
		is_equal_approx(Economy.balance_of(Economy.HEARTS), sad_hearts))
	_buddy.mood.set_value(0.0)
	jack.close(true)

	# Mirrored, the crank is on the left and its zone went with it.
	jack.set_facing(-1.0)
	_check("mirrored, the crank is on the left", jack.crank.position.x < 0.0
		and jack.gestures.zone_world(&"crank").x < jack.global_position.x)
	var before := jack.turns_wound()
	await _crank(jack, 1)
	_check("and it still winds from there (%.2f turns)" % jack.turns_wound(),
		jack.turns_wound() > before + 0.5)

	# He winds it himself: a turn a tick, animated.
	jack.close(true)
	jack._wound = 0.0
	Settings.focus_intensity = Settings.Intensity.NORMAL
	jack.idle_use(_buddy)
	await get_tree().create_timer(JackInTheBox.HIS_TURN_SECONDS + 0.3).timeout
	_check("left alone, he winds it a turn (%.2f)" % jack.turns_wound(), jack.turns_wound() >= 0.99)
	_check("and the winding stops once the turn is done", not jack.is_processing())
	Settings.focus_intensity = Settings.Intensity.OFF
	_spawner_clear()

## Circles on the crank, a sixteenth of a turn per motion event, until it pops or `turns` run
## out. Returns the turns it took.
func _crank(jack: JackInTheBox, turns: int) -> float:
	var pivot := jack.gestures.zone_world(&"crank")
	var radius := Vector2(10, 0)
	_press(pivot + radius, MOUSE_BUTTON_RIGHT)
	var wound := 0.0
	for step in range(1, turns * 16 + 1):
		_move(pivot + radius.rotated(TAU * float(step) / 16.0))
		wound = jack.turns_wound()
		if jack.is_out():
			break
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	await _settle()
	return wound

# --- the fortune ball ----------------------------------------------------------------

func _the_ball_tells_fortunes() -> void:
	_suite("fortune ball")
	var ball := await _fresh(&"magic_eight_ball", _beside_him(140.0)) as MagicEightBall
	if ball == null:
		_check("a fortune ball is on the desk", false)
		return
	ball.freeze = true
	await _clear_combo()
	var at := ball.global_position

	var hearts := Economy.balance_of(Economy.HEARTS)
	_press(at, MOUSE_BUTTON_RIGHT)
	_release(at, MOUSE_BUTTON_RIGHT)
	_check("read unshaken, it says to shake it first", ball.last_answer == MagicEightBall.UNSHAKEN
		and ball.answer_showing())
	_check("and that pays nothing", is_equal_approx(Economy.balance_of(Economy.HEARTS), hearts))
	_check("and a right-click on it did not bin it", ball.is_inside_tree())

	# Shake it: pick it up and wave it about.
	await _hover(at)
	_press(at)
	_check("left picks it up", ball.dragging)
	for i in 8:
		_move(at + Vector2(30.0 if i % 2 == 0 else -30.0, 0.0))
	_check("direction changes charge it (%.0f)" % ball.energy(), ball.is_ready_to_read())
	_press(_mouse, MOUSE_BUTTON_RIGHT)
	_check("right while holding reads it ('%s')" % ball.last_answer,
		ball.last_answer != MagicEightBall.UNSHAKEN and ball.last_answer != "")
	_check("in a bubble above it", ball.answer_showing() and ball.answer_text() == ball.last_answer)
	var bubble := ball.get_node_or_null("AnswerBubble") as PanelContainer
	_check("drawn by the theme's Bubble style, in the display face",
		bubble != null and bubble.theme_type_variation == &"Bubble" and bubble.theme != null)
	_check("and it never takes a click", bubble != null
		and bubble.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("above the ball, not on it", bubble != null
		and bubble.global_position.y + bubble.size.y <= ball.global_position.y)
	_release(_mouse, MOUSE_BUTTON_RIGHT)
	_release(_mouse)
	await _settle()

	# Each kind of answer, forced — a random pick cannot be waited for — and his face to it.
	for tone in [&"yes", &"no", &"maybe"]:
		var index := -1
		for i in MagicEightBall.ANSWERS.size():
			if MagicEightBall.ANSWERS[i][1] == tone:
				index = i
				break
		await _clear_combo()
		_face.clear()
		ball._energy = ball._needed()
		var before := Economy.balance_of(Economy.HEARTS)
		var expected := _expected_act(ball.answer_value * ball.value_multiplier(), &"magic_eight_ball")
		ball.read(true, index)
		_check("a %s answer and he looks it (beat '%s')" % [tone, _face.beat_id()],
			_face.beat_id() == StringName("answer_%s" % tone))
		if tone == &"yes":
			_check_near("a yes pays", Economy.balance_of(Economy.HEARTS) - before, expected)
		else:
			_check("a %s pays nothing" % tone, is_equal_approx(Economy.balance_of(Economy.HEARTS), before))

	ball.bubble_seconds = 0.1
	ball._energy = ball._needed()
	ball.read(true, 0)
	await get_tree().create_timer(0.3).timeout
	_check("the answer goes away, and so does the frame it cost", not ball.answer_showing()
		and not ball.is_processing())

	Settings.focus_intensity = Settings.Intensity.NORMAL
	ball._energy = 0.0
	ball.idle_use(_buddy)
	_check("left alone, he shakes it", ball.is_ready_to_read())
	ball.idle_use(_buddy)
	_check("and reads it", ball.last_answer != "" and ball.energy() == 0.0)
	Settings.focus_intensity = Settings.Intensity.OFF
	_spawner_clear()

# --- the stress ball ---------------------------------------------------------------

func _the_ball_squeezes_and_is_caught() -> void:
	_suite("stress ball")
	var ball := await _fresh(&"stress_ball", _beside_him(150.0)) as StressBall
	if ball == null:
		_check("a stress ball is on the desk", false)
		return
	ball.freeze = true
	await _clear_combo()
	var at := ball.global_position
	await _hover(at)
	_press(at)
	_check("left picks it up", ball.dragging)
	_press(at, MOUSE_BUTTON_RIGHT)
	_check("hold right while holding it and it squeezes", ball.is_squeezing())
	await get_tree().create_timer(0.8).timeout
	_check("the squeeze builds (%.2f)" % ball.charge, ball.charge >= StressBall.SWAP_AT)
	_check("and swaps to its drawn, squashed face", ball.squeeze_sprite.visible
		and not ball.sprite.visible)
	# Read at the moment of the release, not before the wait: his mood drifts home over the
	# eight tenths of a second, and the payout is at the mood in force when it fires.
	var unit := Economy.payout_for(1.0, &"stress_ball")
	var hearts := Economy.balance_of(Economy.HEARTS)
	var bones := Economy.balance_of(Economy.BONES)
	_release(at, MOUSE_BUTTON_RIGHT)
	var value := ball.squeeze_value * (0.25 + 0.75 * ball.charge) * ball.value_multiplier()
	_check("letting go of right lets go of the squeeze", not ball.is_squeezing())
	_check_near("and pays by how hard it was squeezed (%.2f)" % ball.charge,
		Economy.balance_of(Economy.HEARTS) - hearts, unit * value * ItemDB.balance.hearts_per_kindness)
	_check("in Hearts only", is_equal_approx(Economy.balance_of(Economy.BONES), bones))
	_check("and it springs back round", ball.sprite.visible and not ball.squeeze_sprite.visible)
	_release(at)
	await _settle()

	# Thrown at him, he catches it: it has to have left the player's hand.
	ball.freeze = false
	var catches := Economy.balance_of(Economy.HEARTS)
	_face.clear()
	ball._start_drag()
	ball._end_drag()
	var chest := _buddy.global_position + Vector2(-120, -20)
	ball.global_position = chest
	ball.linear_velocity = Vector2(900, -40)
	var caught := false
	var seen_catch := false
	for i in 60:
		await get_tree().physics_frame
		caught = caught or ball.is_caught()
		seen_catch = seen_catch or _face.beat_id() == &"catch"
	_check("thrown at him, he catches it", caught)
	_check("and looks pleased with himself", seen_catch)
	_check("and the catch pays", Economy.balance_of(Economy.HEARTS) > catches)
	await get_tree().create_timer(ball.catch_seconds + 0.2).timeout
	_check("then he lets it go", not ball.is_caught())

	# Merely put down against him is not a throw.
	await _frames(40)
	var resting := Economy.balance_of(Economy.HEARTS)
	ball.linear_velocity = Vector2.ZERO
	ball.global_position = _buddy.global_position + Vector2(-60, 30)
	await _frames(40)
	_check("a ball that falls on him is not caught", not ball.is_caught()
		and is_equal_approx(Economy.balance_of(Economy.HEARTS), resting))
	_spawner_clear()

# --- zones in a turned body ---------------------------------------------------------

func _zones_follow_a_turned_body() -> void:
	_suite("zones on a turned, mirrored body")
	var jack := await _fresh(&"jack_in_the_box", _beside_him(200.0)) as JackInTheBox
	if jack == null:
		_check("a jack-in-the-box is on the desk", false)
		return
	jack.freeze = true
	jack.set_facing(-1.0)
	jack.global_rotation = PI * 0.5
	await _frames(2)
	var crank := jack.gestures.zone_world(&"crank")
	# Turned a quarter clockwise, mirrored: the crank that was at (+13, 1) art sits at
	# (-13, 1), which a quarter turn carries to (-1, -13) — straight above the box's middle.
	_check("the crank zone turned with the body (%.0f, %.0f from the middle)"
		% [(crank - jack.global_position).x, (crank - jack.global_position).y],
		(crank - jack.global_position).distance_to(Vector2(-2, -26)) < 3.0)
	_check("and maps back to where it was drawn",
		jack.gestures.world_to_art(crank).distance_to(Vector2(13, 1)) < 0.01)
	var before := jack.turns_wound()
	await _crank(jack, 2)
	_check("and cranks there (%.2f turns)" % jack.turns_wound(), jack.turns_wound() > before + 1.0)

	var wrap := await _fresh(&"bubble_wrap", _beside_him(-220.0)) as BubbleWrap
	if wrap:
		wrap.freeze = true
		wrap.global_rotation = PI
		await _frames(2)
		# Upside down, the top-left bubble is at the bottom right.
		var b0 := wrap.gestures.zone_world(&"b0")
		_check("upside down, bubble 0 is bottom-right", b0.x > wrap.global_position.x
			and b0.y > wrap.global_position.y)
		_press(b0)
		_release(b0)
		_check("and tapping it there pops it", wrap.is_popped(0))
	_spawner_clear()

# --- hover -------------------------------------------------------------------------

func _hover_shows_the_hand() -> void:
	_suite("hover")
	var jack := await _fresh(&"jack_in_the_box", _beside_him(180.0)) as JackInTheBox
	if jack == null:
		_check("a jack-in-the-box is on the desk", false)
		return
	jack.freeze = true
	jack.set_facing(1.0)
	var zones := jack.gestures
	_move(zones.zone_world(&"crank"))
	_check("over the crank, the pointing hand", zones.hover_zone == &"crank"
		and zones.cursor_shape == Input.CURSOR_POINTING_HAND)
	_move(jack.global_position + Vector2(-12, 8))
	_check("over the rest of the box, the grab", zones.hover_zone == &""
		and zones.cursor_shape == Input.CURSOR_MOVE)
	_move(jack.global_position + Vector2(-300, -250))
	_check("away from it, the arrow again", zones.cursor_shape == Input.CURSOR_ARROW
		and not zones.hover_body)
	var wrap := await _fresh(&"bubble_wrap", _beside_him(-200.0)) as BubbleWrap
	if wrap:
		wrap.freeze = true
		_move(wrap.gestures.zone_world(&"b2"))
		_check("over a bubble, the hand", wrap.gestures.cursor_shape == Input.CURSOR_POINTING_HAND)
		# The film's left margin: part of the sheet, claimed by the right-stroke, not a button.
		_move(wrap.gestures.art_to_world(Vector2(-19.0, 0.0)))
		_check("over the film around them, the grab — it is the toy, not a button",
			wrap.gestures.cursor_shape == Input.CURSOR_MOVE and wrap.gestures.hover_zone == &"")
		_move(Vector2(40, 400))
	_spawner_clear()

# --- the bin -----------------------------------------------------------------------

func _shift_right_always_bins() -> void:
	_suite("Shift+right bins")
	for entry in [[&"bubble_wrap", &"b1"], [&"jack_in_the_box", &"crank"],
			[&"magic_eight_ball", &"ball"]]:
		var body := await _fresh(entry[0], _beside_him(170.0)) as FidgetToy
		if body == null:
			_check("%s is on the desk" % entry[0], false)
			continue
		body.freeze = true
		await _frames(2)
		var count := _spawner.item_count()
		var at := body.gestures.zone_world(entry[1])
		await _hover(at)
		_press(at, MOUSE_BUTTON_RIGHT, true)
		_release(at, MOUSE_BUTTON_RIGHT)
		await _settle()
		_check("Shift+right on %s's %s bins it, zone or no zone" % [entry[0], entry[1]],
			not is_instance_valid(body) or not body.is_inside_tree()
			or _spawner.item_count() < count)
		_spawner_clear()

# --- the budget --------------------------------------------------------------------

func _nothing_runs_at_rest() -> void:
	_suite("nothing runs at rest")
	var script := load("res://Scripts/Bodies/gesture_zones.gd") as Script
	var methods: Array[String] = []
	for method in script.get_script_method_list():
		methods.append(String(method["name"]))
	_check("GestureZones has no frame callback at all",
		not methods.has("_process") and not methods.has("_physics_process"))
	var x := -260.0
	var toys: Array[FidgetToy] = []
	for id in FIDGETS:
		var toy := await _fresh(id, _beside_him(x)) as FidgetToy
		x += 130.0
		if toy:
			toys.append(toy)
	await _frames(40)
	for toy in toys:
		var zones := toy.gestures
		_check("%s at rest runs no frame of its own" % toy.item_id, not toy.is_processing())
		_check("and its zones are idle", zones != null and not zones.is_processing()
			and not zones.is_physics_processing() and not zones.is_pressed()
			and (zones.get_node("HoldTimer") as Timer).is_stopped())
	var wrap: BubbleWrap = null
	for toy in toys:
		if toy is BubbleWrap:
			wrap = toy
	_check("a full sheet of bubble wrap has no timer running", wrap != null
		and wrap._regrow.is_stopped())
	_spawner_clear()

# --- him ---------------------------------------------------------------------------

## He walks over to each one and does his thing with it. The same stepped physics the idle
## brain's own suite uses, on the real floor of the real game.
func _he_plays_with_every_one() -> void:
	_suite("he plays with them")
	Settings.focus_intensity = Settings.Intensity.NORMAL
	for id in FIDGETS:
		_spawner_clear()
		await _stand_him_up(Vector2(420, 560))
		var toy := await _fresh(id, Vector2(_buddy.global_position.x + 150.0, 560)) as FidgetToy
		if toy == null:
			_check("%s is on the desk" % id, false)
			continue
		await _frames(40)
		_idle.pretend_idle()
		_idle.think_now()
		_check("%s is somewhere he goes (target '%s', routine %d)"
			% [id, _idle.target_id(), _idle.current_routine()],
			_idle.target_id() == id and _idle.current_routine() == IdleBrain.ROUTINE_FIDGET)
		# Busy is his face on the toy: fiddling with it, or — for the spinner — staring at it.
		var fiddled := false
		for i in 480:
			await get_tree().physics_frame
			fiddled = fiddled or _face.beat_id() in [&"fiddling", &"entranced"]
			if _idle.phase_name() == IdleBrain.PHASE_PLAYING and i > 30:
				break
		_check("he gets there (phase '%s')" % _idle.phase_name(),
			_idle.phase_name() == IdleBrain.PHASE_PLAYING)
		var snapshot := _state_of(toy)
		var hearts := Economy.balance_of(Economy.HEARTS)
		for tick in 4:
			_idle.think_now()
			for i in 50:
				await get_tree().physics_frame
				fiddled = fiddled or _face.beat_id() in [&"fiddling", &"entranced"]
		_check("and uses the %s (%s -> %s)" % [id, snapshot, _state_of(toy)],
			_state_of(toy) != snapshot or Economy.balance_of(Economy.HEARTS) > hearts)
		_check("and looks busy with it", fiddled)
		_idle._disturb()
	# At Off he is simply there, and it still pays, and the toy does not move.
	Settings.focus_intensity = Settings.Intensity.OFF
	_spawner_clear()
	await _stand_him_up(Vector2(420, 560))
	var ball := await _fresh(&"stress_ball", Vector2(_buddy.global_position.x + 150.0, 560)) as StressBall
	if ball:
		await _frames(30)
		_idle.pretend_idle()
		_idle.think_now()
		var hearts := Economy.balance_of(Economy.HEARTS)
		_idle.think_now()
		_idle.think_now()
		await _frames(40)
		_check("at Focus Off he is already at it (phase '%s')" % _idle.phase_name(),
			_idle.phase_name() == IdleBrain.PHASE_PLAYING)
		_check("and it pays, quietly", Economy.balance_of(Economy.HEARTS) > hearts)
		_check("without the ball visibly moving", ball.sprite.scale.is_equal_approx(Vector2(2, 2)))
	_idle._disturb()
	_spawner_clear()

## A one-line summary of what a toy has done, so "he used it" is a change in this string.
func _state_of(toy: FidgetToy) -> String:
	if toy is BubbleWrap:
		return "%d intact" % (toy as BubbleWrap).intact_count()
	if toy is FidgetSpinner:
		return "spin %.1f" % absf((toy as FidgetSpinner).spin)
	if toy is JackInTheBox:
		var jack := toy as JackInTheBox
		return "%.2f turns%s" % [jack.turns_wound(), ", out" if jack.is_out() else ""]
	if toy is MagicEightBall:
		var ball := toy as MagicEightBall
		return "energy %.0f, '%s'" % [ball.energy(), ball.last_answer]
	return "?"

# --- the shop and the tip ------------------------------------------------------------

func _the_shop_says_how() -> void:
	_suite("the shop says how")
	var panels := _find(_main, "PanelLayer")
	var shop := _find(_main, "ShopPanel")
	if panels == null or shop == null:
		_check("the shop is present", false)
		return
	panels.call("show_panel", &"shop")
	await _settle()
	shop.call("show_category", ItemData.CATEGORY_TOY)
	shop.call("select", &"jack_in_the_box")
	await _settle()
	var how := _find(shop, "HowTo") as PanelContainer
	var line := _find(shop, "Controls") as Label
	_check("the detail pane has a how-to strip", how != null and line != null)
	if how and line:
		_check("a fidget toy shows how it works", how.is_visible_in_tree()
			and line.text == ItemDB.get_item(&"jack_in_the_box").controls)
		_check("on the theme's own HowTo style", how.theme_type_variation == &"HowTo"
			and UITheme.get_theme().has_stylebox("panel", "HowTo"))
		shop.call("select", &"rubber_duck")
		await _settle()
		_check("an item worked the ordinary way shows nothing", not how.visible)
	panels.call("close")
	await _settle()

	var hud := get_tree().get_first_node_in_group(HUD.GROUP_HUD)
	var toast := _find(hud, "Toast") as PanelContainer if hud else null
	var key := HUD.HINT_CONTROLS_PREFIX + "fidget_spinner"
	Settings.hints_seen.erase(key)
	_spawner_clear()
	await _fresh(&"fidget_spinner", _beside_him(150.0))
	var label: Label = _first_label(toast)
	_check("the first spinner on the desk teaches its controls",
		Settings.hint_seen(StringName(key)) and toast != null and toast.visible and label != null
		and label.text.contains(ItemDB.get_item(&"fidget_spinner").controls))
	if label:
		label.text = ""
	await _fresh(&"fidget_spinner", _beside_him(-150.0))
	_check("and only the first", label != null and label.text == "")
	_spawner_clear()

func _first_label(root: Node) -> Label:
	if root == null:
		return null
	for node in _all_nodes(root):
		if node is Label:
			return node
	return null

# --- staging -----------------------------------------------------------------------

## A toy on the desk through the spawner, settled, and him left alone for it: spawning a toy
## is an offer (IdleBrain.INVITED_SECONDS), and an offer six seconds old sends him over in the
## middle of somebody else's assertion.
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

## A spot on the floor beside him.
func _beside_him(dx: float) -> Vector2:
	return Vector2(_buddy.global_position.x + dx, _buddy.global_position.y + 20.0)

func _stand_him_up(at: Vector2) -> void:
	_idle._disturb()
	_buddy.global_position = at
	_buddy.global_rotation = 0.0
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0
	await _frames(60)

## Drops him onto a toy from `height` px above its top edge — low enough that the landing
## cannot hurt him.
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

## Waits out the kindness combo, so an expected payout can be computed at a count of zero.
func _clear_combo() -> void:
	if Economy.combo_seconds_left() > 0.0:
		await get_tree().create_timer(Economy.combo_seconds_left() + 0.05).timeout

## What one kindness act of `value` pays in Hearts, read BEFORE it is emitted (CLAUDE.md:
## Economy pays at the mood in force when the event fired, and the act then moves it).
func _expected_act(value: float, id: StringName) -> float:
	var b := ItemDB.balance
	var count: int = Economy._combo_count + 1 if Economy.combo_seconds_left() > 0.0 else 0
	var combo := EconomyMath.kindness_combo(count, b.kindness_combo_step, b.kindness_combo_max)
	return Economy.payout_for(value * b.hearts_per_kindness * combo, id)

# --- input -----------------------------------------------------------------------

func _move(at: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = at - _mouse
	motion.velocity = velocity
	motion.button_mask = _mask
	_mouse = at
	_view.push_input(motion, true)

## A motion there, then long enough for physics picking to notice — which is what a grab
## (as opposed to a zone) is gated on.
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

func _record(g: GestureZones.Gesture) -> void:
	_seen.append(g.kind)

# --- plumbing --------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await get_tree().physics_frame

func _find(root: Node, what: String) -> Node:
	for node in _all_nodes(root):
		if node.name == what or (node.get_script()
				and (node.get_script() as Script).get_global_name() == what):
			return node
	return null

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
