extends Node

## Every AI mechanic of the character, each on its own stage, asserted by what can be seen
## rather than by the flag that is supposed to cause it (docs/decisions.md D60).
##
##   Godot --headless --path <project> res://tests/integration/brain_check.tscn
##   ... -- --only idle,turrets     run some sections
##   ... -- --quick                 one toy per routine instead of every toy
##   ... -- --only idle.toys --toys hot_tub,beanbag   the every-toy walk for those toys only
##
## `loop_check` proves the wiring: it calls the brain's handlers directly, because emitting
## most of them on the real bus would pay money in the middle of an economy suite. This suite
## is the other half. It builds a desk of its own for each mechanic — a 1280x720 SubViewport,
## because a headless root viewport is 64x64 and every wall, home point and exit derived from
## it is meaningless — puts a real buddy on it, fires each trigger through the signal the game
## really fires it on, steps real physics, and looks at what happened to him.
##
## **Enumerated, never listed.** Every reaction row, every toy with a routine, every
## personality, every critter and every turret is read off `ExpressionBrain.ROWS` and
## `ItemDB`, so content added next month is covered by this file without anybody coming back
## to it. A row or a wire this suite has no real trigger for is reported, not skipped.
##
## Clocks are skewed rather than waited out, the way `loop_check` does it — the expression
## brain has `_clock_skew`, the idle brain's clock is a timestamp that can be backdated — and
## the idle brain's think tick is driven by hand (`think_now()` is the same code the timer
## runs). Physics is real and in real time, because a fixed-fps run would disagree with every
## millisecond deadline in the game.
##
## Writes `user://brain_check_report.md`: a verdict per mechanic and the numbers measured.

const TEST_SLOT := "brain_check_slot"
const CONFIG_PATH := "user://settings_brain_check.cfg"
const REPORT_PATH := "user://brain_check_report.md"
const BUDDY_SCENE := preload("res://Scenes/Buddy/buddy.tscn")

const VIEW_SIZE := Vector2i(1280, 720)
## `WorldBounds` puts the floor's top edge on the bottom of the view.
const FLOOR_Y := 720.0
## His collider spans y -58..+62 about his origin (88x120 at scale 2, offset (0, 2)).
const FEET := 62.0
const HOME := Vector2(760.0, FLOOR_Y - FEET - 1.0)

## Sources used for a blow whose category matters: a weapon (the generic `shocked` face) and a
## second weapon so the annoyance count is not confused with anything the bat did before.
const BAT := &"baseball_bat"
const MACE := &"mace"

var _passed := 0
var _failed := 0
var _t0 := 0
var _only: Array[String] = []
var _quick := false
## `-- --toys id,id`: the every-toy walk for those toys only, for working on one routine.
var _toys: Array[String] = []

## One entry per mechanic: {name, passed, failed, failures, measures}.
var _sections: Array[Dictionary] = []
var _cur: Dictionary = {}
var _notes: Array[String] = []

var _view: SubViewport
var _world: Node2D
var _buddy: Buddy
var _art: BuddyArt
var _brain: ExpressionBrain
var _idle: IdleBrain
var _spawner: ItemSpawner

var _restore := {}

# --- what the bus said, per stage. Members, never locals a lambda captures by value. ------
var _hits: Array[HitInfo] = []
var _given: Array[Array] = []       ## [source_id, value, pos, usec]
var _sustained: Array[Array] = []
var _threats: Array[Array] = []     ## [kind, pos, level, usec, physics frame, engine seconds]
var _landings: Array[Array] = []    ## [pos, speed]
var _states: Array[Array] = []      ## [state, usec]
var _knockouts: Array[float] = []
var _despawns: Array[Node] = []
var _ends: Array[StringName] = []   ## the idle brain's routine_ended reasons
var _hit_usec: Array[int] = []

## Rows seen live while a real trigger was in play, and the wires proven to do something.
var _recording := true
var _seen_real: Dictionary = {}
var _proven: Dictionary = {}

func _ready() -> void:
	# Its own preferences file, on the first line (D51): a run killed half way must not leave
	# Focus Mode wherever a section put it in the developer's real settings.
	Settings.config_path = CONFIG_PATH
	_restore = {
		"focus": Settings.focus_intensity,
		"personality": Economy.personality,
	}
	_t0 = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			for part in args[i + 1].split(","):
				_only.append(part.strip_edges())
		elif args[i] == "--quick":
			_quick = true
		elif args[i] == "--toys" and i + 1 < args.size():
			for part in args[i + 1].split(","):
				_toys.append(part.strip_edges())
	# Silence without Focus Off: the dummy audio driver reports its stream playbacks as leaks
	# at exit, which would bury a real one — and Off is a mode this suite has to test, not a
	# default it can hide behind.
	AudioManager._set_muted(true)
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()
	Economy.personality = "stoic"

	EventBus.damage_dealt.connect(_log_hit)
	EventBus.kindness_given.connect(_log_given)
	EventBus.kindness_sustained.connect(_log_sustained)
	EventBus.threat_changed.connect(_log_threat)
	EventBus.buddy_landed.connect(_log_landing)
	EventBus.buddy_state_changed.connect(_log_state)
	EventBus.knockout_payout.connect(_log_knockout)
	EventBus.item_despawned.connect(_log_despawn)

	print("")
	print("Bonehead Friend — brain check")
	print("=============================")

	if _want("expression", "rows"):
		await _expression_rows()
	if _want("expression", "arbitration"):
		await _expression_arbitration()
	if _want("expression", "triggers"):
		await _expression_triggers()
	if _want("expression", "off"):
		await _expression_focus_off()
	if _want("expression", "attention"):
		await _expression_attention()
	if _want("idle", "start"):
		await _idle_thresholds()
	if _want("idle", "toys"):
		await _idle_every_toy()
	if _want("idle", "interruptions"):
		await _idle_interruptions()
	if _want("idle", "geometry"):
		await _idle_geometry()
	if _want("idle", "off"):
		await _idle_focus_off()
	if _want("movement", "travel"):
		await _movement_travel()
	if _want("movement", "body"):
		await _movement_body()
	if _want("movement", "knockout"):
		await _movement_knockout()
	if _want("mood", "bands"):
		await _mood_bands_and_decay()
	if _want("mood", "payouts"):
		await _mood_payouts()
	if _want("mood", "grime"):
		await _grime()
	if _want("personality"):
		await _personalities()
	if _want("critters"):
		await _critters()
	if _want("turrets"):
		await _turrets()
	# Last, because they read what every section above saw.
	if _only.is_empty():
		_expression_wires()
		_expression_coverage()

	await _teardown()
	EventBus.damage_dealt.disconnect(_log_hit)
	EventBus.kindness_given.disconnect(_log_given)
	EventBus.kindness_sustained.disconnect(_log_sustained)
	EventBus.threat_changed.disconnect(_log_threat)
	EventBus.buddy_landed.disconnect(_log_landing)
	EventBus.buddy_state_changed.disconnect(_log_state)
	EventBus.knockout_payout.disconnect(_log_knockout)
	EventBus.item_despawned.disconnect(_log_despawn)
	Settings.focus_intensity = _restore["focus"]
	Economy.personality = _restore["personality"]
	Settings.save_settings()
	AudioManager._set_muted(false)

	var seconds := float(Time.get_ticks_msec() - _t0) / 1000.0
	_write_report(seconds)
	print("")
	print("=============================")
	print("passed: %d   failed: %d   (%.0f s)" % [_passed, _failed, seconds])
	print("report: %s" % ProjectSettings.globalize_path(REPORT_PATH))
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

## The engine's own process clock, the one a `SceneTreeTimer` counts: an animal's wind-up is
## timed on it, so its tell is measured on it (D70).
var _engine_seconds := 0.0

func _process(delta: float) -> void:
	_engine_seconds += delta

## `--only idle` runs every idle section, `--only idle.geometry` just the one.
func _want(section: String, sub: String = "") -> bool:
	return _only.is_empty() or _only.has(section) or (sub != "" and _only.has("%s.%s" % [section, sub]))

# =====================================================================================
# A — ExpressionBrain
# =====================================================================================

## Every row, driven through the brain's own API, reaches `BuddyArt` as it declares: its face
## (through the personality's swaps), its body tag (or the fallback it names), its speed, its
## motion at the Focus amplitude, for its duration — and then lets go completely.
func _expression_rows() -> void:
	_begin("expression — every row reaches the art")
	await _stage("expression rows", true)
	_focus(Settings.Intensity.NORMAL)
	# Out of the mood trough, so "at rest" is his plain standing posture and not a slouch.
	_buddy.mood.set_value(40.0)
	await _frames(2)
	_recording = false

	var dead := _rows_nobody_asks_for()
	_check("every row is asked for by some code outside the table (dead: %s)"
		% _list(dead), dead.is_empty())
	var tailless: Array[String] = []
	for id in ExpressionBrain.ROWS:
		var row: Dictionary = ExpressionBrain.ROWS[id]
		if row.has("tail_face") and float(row.get("tail", 0.0)) <= 0.0:
			tailless.append(String(id))
	_check("every row with a tail face has a tail to show it in (none: %s)" % _list(tailless),
		tailless.is_empty())

	var moved_by: Array[String] = []
	for id in ExpressionBrain.ROWS:
		var extent: float = await _row_presents(id)
		if extent > 0.0:
			moved_by.append("%s %.1f" % [id, extent])
	_measure("%d rows; peak motion at Normal (px moved + 10 x squash): %s" % [ExpressionBrain.ROWS.size(),
		", ".join(moved_by)])
	_recording = true
	_end()

## One row, end to end. Returns the peak displacement its motion produced, 0 for none.
func _row_presents(id: StringName) -> float:
	var row: Dictionary = ExpressionBrain.ROWS[id]
	var gate: StringName = row.get("gate", ExpressionBrain.GATE_REACTIVE)
	_focus(Settings.Intensity.CHAOS if gate == ExpressionBrain.GATE_CHAOS else Settings.Intensity.NORMAL)
	_brain.clear()
	_art.look(0.0)
	_hush()
	await _frames(1)
	var problems: Array[String] = []
	var at := _buddy.global_position + Vector2(40, 0)
	var hold := bool(row.get("hold", false))
	var ok := _brain.hold(id, at) if hold else _brain.react(id, 1.0, at)
	var extent := 0.0
	if not ok:
		problems.append("refused at %s" % _focus_name())
	else:
		if _brain.beat_id() != id:
			problems.append("beat is '%s'" % _brain.beat_id())
		if _brain.beat_priority() != int(row.get("priority", -1)):
			problems.append("priority %d" % _brain.beat_priority())
		var face: StringName = row.get("face", &"")
		if face != &"":
			var want: StringName = _art.face_swaps.get(face, face)
			if _art.face.animation != want:
				problems.append("face '%s' not '%s'" % [_art.face.animation, want])
		var tag := _brain._resolve_tag(row)
		if tag != &"" and _art.body.animation != tag:
			problems.append("tag '%s' not '%s'" % [_art.body.animation, tag])
		if not is_equal_approx(_art.body.speed_scale, float(row.get("speed", 1.0))):
			problems.append("speed %.2f" % _art.body.speed_scale)
		var motion: StringName = row.get("motion", &"")
		var amp := Settings.intensity_scale() * _brain._personality.reaction_amplitude
		var seconds := _brain._duration(row, tag)
		if motion != &"":
			if _art._motion != motion and _art._motion != &"":
				problems.append("motion '%s' not '%s'" % [_art._motion, motion])
			if not is_equal_approx(_art._motion_amp, amp):
				problems.append("amplitude %.2f not %.2f" % [_art._motion_amp, amp])
			if not is_equal_approx(_art._motion_seconds, maxf(seconds, 0.05)):
				problems.append("motion runs %.2fs, the row %.2fs" % [_art._motion_seconds, seconds])
			extent = await _motion_extent(8)
			if extent < 0.05:
				problems.append("motion '%s' moved nothing" % motion)
		# A tail changes the face partway through: the heavy hit's dizzy, the reunion's happy.
		var tail_at := int(_brain._beat.get("tail_at_msec", 0))
		var tail_face: StringName = row.get("tail_face", &"")
		if tail_at > 0 and tail_face != &"" and _brain.beat_id() == id:
			_brain._clock_skew += maxi(tail_at - _brain._now(), 0) + 5
			_hush()
			_brain._on_timer()
			var want_tail: StringName = _art.face_swaps.get(tail_face, tail_face)
			if _art.face.animation != want_tail:
				problems.append("tail face '%s' not '%s'" % [_art.face.animation, want_tail])
		# The lapse. A hold with no refresh lives until released; everything else ends itself.
		if hold and float(row.get("refresh", 0.0)) <= 0.0:
			_brain._clock_skew += 30000
			_hush()
			_brain._on_timer()
			if _brain.beat_id() != id:
				problems.append("an open hold lapsed on its own")
			_brain.release(id)
		elif _brain.beat_active():
			var until := int(_brain._beat.get("until_msec", 0))
			_brain._clock_skew += maxi(until - _brain._now(), 0) + 20
			_hush()
			_brain._on_timer()
		await _frames(1)
		if _brain.beat_active() and _brain.beat_id() == id:
			problems.append("never lapsed")
		if _art.beat_active():
			problems.append("the art still thinks a beat is live")
		var rest := _at_rest()
		if rest != "":
			problems.append(rest)
	_brain.clear()
	_check("row '%s' [%s, pri %d, gate %s]%s" % [id, "hold" if hold else "one-shot",
		int(row.get("priority", -1)), gate, "" if problems.is_empty() else ": " + "; ".join(problems)],
		problems.is_empty())
	return extent

## Nothing left over: body home and unscaled, no gaze or squash, speed back to his posture,
## the face and the idle his mood asks for.
func _at_rest() -> String:
	var out: Array[String] = []
	if _art.body.position.distance_to(_art._body_home) > 0.01:
		out.append("body off home by %.2f" % _art.body.position.distance_to(_art._body_home))
	if not _art.body.scale.is_equal_approx(_art._base_scale):
		out.append("body scale %s" % _art.body.scale)
	if not is_zero_approx(_art._beat_look_x) or _art._squash != Vector2.ONE:
		out.append("a motion accumulator is non-zero")
	if not is_equal_approx(_art.body.speed_scale, _art._posture_speed):
		out.append("speed %.2f, posture %.2f" % [_art.body.speed_scale, _art._posture_speed])
	if _buddy.state == &"idle":
		var face: StringName = _art.face_swaps.get(_mood_face(Economy.mood), _mood_face(Economy.mood))
		if _art.face.animation != face:
			out.append("face '%s' not the mood's '%s'" % [_art.face.animation, face])
		var idle := _mood_idle(Economy.mood)
		if _art.body.animation != idle:
			out.append("idle '%s' not the mood's '%s'" % [_art.body.animation, idle])
	return "; ".join(out)

## The furthest his drawing moved from where the offsets alone put it, over some frames.
func _motion_extent(frames: int) -> float:
	var peak := 0.0
	for i in frames:
		await get_tree().physics_frame
		var d := _art.body.position.distance_to(_art._body_home) \
			+ (_art.body.scale - _art._base_scale).length() * 10.0 \
			+ _art.face.position.distance_to(_face_spot())
		peak = maxf(peak, d)
	return peak

## Where the face should be from the offsets alone (loop_check's `_face_spot`).
func _face_spot() -> Vector2:
	var frame := _art.body.frame
	if frame >= _art._track_positions.size():
		return _art._face_home
	var entry: Vector2 = _art._track_positions[frame]
	var dx := entry.x * _art._base_scale.x
	if _art._facing < 0.0:
		dx = -dx
	return Vector2(_art._face_home.x + dx + _art._look_x, _art._face_home.y + entry.y * _art._base_scale.y)

## Rows that no code outside the table ever asks for. A row nobody requests is a reaction the
## player can never see, which is the same bug as a `connect()` that never runs.
func _rows_nobody_asks_for() -> Array[String]:
	var text := ""
	for path in _scripts_under("res://Scripts"):
		var source := FileAccess.get_file_as_string(path)
		if path.ends_with("expression_brain.gd"):
			var start := source.find("const ROWS := {")
			var stop := source.find("\n}\n", start)
			if start >= 0 and stop > start:
				source = source.substr(0, start) + source.substr(stop + 3)
		text += source
	var dead: Array[String] = []
	for id in ExpressionBrain.ROWS:
		if text.find("&\"%s\"" % id) < 0:
			dead.append(String(id))
	return dead

func _scripts_under(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for file in d.get_files():
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in d.get_directories():
		out.append_array(_scripts_under(dir.path_join(sub)))
	return out

## Higher preempts lower, lower never preempts higher, equal preempts — except one ambient
## beat never interrupts another. One representative row per priority level, read off the
## table, so a new level is covered the day it is added.
func _expression_arbitration() -> void:
	_begin("expression — arbitration")
	await _stage("arbitration", true)
	_focus(Settings.Intensity.NORMAL)
	_recording = false
	var reps := {}
	for id in ExpressionBrain.ROWS:
		var row: Dictionary = ExpressionBrain.ROWS[id]
		if row.get("gate", &"R") == ExpressionBrain.GATE_CHAOS:
			continue
		var p := int(row.get("priority", 0))
		if not reps.has(p) or (bool(ExpressionBrain.ROWS[reps[p]].get("hold", false))
				and not bool(row.get("hold", false))):
			reps[p] = id
	var levels: Array = reps.keys()
	levels.sort()
	_measure("priority levels in the table: %s" % ", ".join(levels.map(
		func(p: int) -> String: return "%d (%s)" % [p, reps[p]])))
	for i in levels.size():
		for j in range(i + 1, levels.size()):
			var lo: StringName = reps[levels[i]]
			var hi: StringName = reps[levels[j]]
			_brain.clear()
			_ask(hi)
			var refused := not _ask(lo) and _brain.beat_id() == hi
			_brain.clear()
			_ask(lo)
			var taken := _ask(hi) and _brain.beat_id() == hi
			_check("'%s' (%d) cannot interrupt '%s' (%d), and is interrupted by it"
				% [lo, levels[i], hi, levels[j]], refused and taken)
	# Equal priority: the newer one wins, except between two ambient beats.
	var by_level := {}
	for id in ExpressionBrain.ROWS:
		var row: Dictionary = ExpressionBrain.ROWS[id]
		if row.get("gate", &"R") == ExpressionBrain.GATE_CHAOS or bool(row.get("hold", false)):
			continue
		var p := int(row.get("priority", 0))
		if not by_level.has(p):
			by_level[p] = []
		(by_level[p] as Array).append(id)
	for p in by_level:
		var ids: Array = by_level[p]
		if ids.size() < 2:
			continue
		_brain.clear()
		_ask(ids[0])
		var second := _ask(ids[1])
		if p == ExpressionBrain.AMBIENT:
			_check("one ambient beat does not interrupt another ('%s' kept over '%s')" % [ids[0], ids[1]],
				not second and _brain.beat_id() == ids[0])
		else:
			_check("equal priority %d: the newer '%s' replaces '%s'" % [p, ids[1], ids[0]],
				second and _brain.beat_id() == ids[1])
	# Damping: the same beat inside 0.18 s extends and does not rewind; a hotter one restarts.
	_brain.clear()
	_brain.react(&"hit", 0.5)
	var started: int = _brain._beat.get("started_msec", 0)
	_art.body.frame = 2
	var again := _brain.react(&"hit", 0.5)
	_check("an identical hit inside the damping window extends without rewinding",
		again and int(_brain._beat.get("started_msec", -1)) == started and _art.body.frame == 2)
	_check("a hotter one restarts the animation", _brain.react(&"hit", 1.0) and _art.body.frame == 0)
	_brain.clear()
	_recording = true
	_end()

func _ask(id: StringName) -> bool:
	var row: Dictionary = ExpressionBrain.ROWS.get(id, {})
	return _brain.hold(id) if bool(row.get("hold", false)) else _brain.react(id)

## Every row that has a trigger in the game, fired through that trigger — the bus signal, the
## component, the physics — and caught live.
func _expression_triggers() -> void:
	_begin("expression — real triggers")
	await _stage("triggers", true)
	_focus(Settings.Intensity.NORMAL)
	_buddy.mood.set_value(40.0)
	await _frames(2)
	for id in [BAT, MACE, &"pistol", &"open_hand", &"pizza", &"tennis_ball", &"grenade", &"beanbag"]:
		Progression._unlock(id)

	# A — being hit, through his own door and his own physics tick.
	await _settle_hit()
	await _hit(1000.0, BAT)
	_fired(&"hit_light", "a 10-damage bat hit (heat %.2f)" % (10.0 / ItemDB.balance.hit_stop_full_damage))
	_prove(&"damage_dealt")
	await _settle_hit()
	await _hit(6000.0, BAT)
	_fired(&"hit", "a 60-damage bat hit")
	await _settle_hit()
	await _hit(10000.0, BAT)
	_fired(&"hit_heavy", "a 100-damage bat hit")
	await _settle_hit()
	_brain._hits.clear()
	for i in ExpressionBrain.ANNOYED_HITS:
		await _hit(6000.0, MACE)
	# The settle, off the brain's own timer: the hit's deadline passes and the annoyance shows.
	await _advance_brain(int(_brain._beat.get("until_msec", 0)) - _brain._now() + 20)
	_fired(&"hit_annoyed", "five mace hits inside three seconds, on the settle")
	_prove(&"timeout")
	await _settle_hit()
	_brain._hits.clear()
	await _hit(6000.0, &"pistol")
	await _hit(6000.0, &"pistol")
	_fired(&"cooking", "a cursor power ticking twice inside 0.4 s")
	await _settle_hit()
	# A one-shot ends when its tag does, whatever the deadline says: push the deadline a minute
	# out and only the art's `animation_finished` can end it.
	_brain.react(&"hit", 0.5)
	_brain._beat["until_msec"] = _brain._now() + 60000
	var tag_seconds := _art.animation_length(_art.body.animation)
	var tag_ended := await _until(func() -> bool: return not _brain.beat_active(), int(tag_seconds * 60.0) + 20)
	_check("a one-shot ends when its body tag finishes (%.2f s tag)" % tag_seconds, tag_ended)
	if tag_ended:
		_prove(&"beat_animation_finished")
	await _settle_hit()

	# B — kindness, on the bus the items really use.
	Economy._combo_deadline_msec = 0
	EventBus.kindness_given.emit(&"open_hand", 1.0, _buddy.global_position)
	_fired(&"pet", "a pet")
	_prove(&"kindness_given")
	_brain.clear()
	for i in 4:
		EventBus.kindness_given.emit(&"open_hand", 1.0, _buddy.global_position)
	_fired(&"pet_combo", "four pets inside the combo window (combo %d)" % Economy.kindness_combo())
	_brain.clear()
	EventBus.kindness_sustained.emit(&"beanbag", 1.0, _buddy.global_position)
	_fired(&"cared_for", "a sustained trickle from a beanbag")
	_prove(&"kindness_sustained")
	_brain.clear()
	_buddy.grime.set_value(0.4)
	_brain.clear()
	_buddy.grime.clean(1.0)
	_fired(&"sparkling", "the grime component reaching zero")
	_prove(&"grime_changed")
	_brain.clear()
	await _settle_hit()
	# A real pizza, dropped on his head.
	EventBus.spawn_requested.emit(&"pizza", _buddy.global_position + Vector2(0, -150))
	var ate := await _until(func() -> bool: return _seen_now(&"eat"), 90)
	_check("a real pizza dropped on him is eaten (beat 'eat' seen)", ate)
	_mark(&"eat", ate)
	_clear_desk()
	await _frames(2)
	_brain.clear()
	# A real tennis ball, thrown at him.
	EventBus.spawn_requested.emit(&"tennis_ball", _buddy.global_position + Vector2(-160, -20))
	var ball := _last_spawned(&"tennis_ball") as RigidBody2D
	await _frames(2)
	if ball:
		ball.linear_velocity = Vector2(900, -60)
	var caught := await _until(func() -> bool: return _seen_now(&"catch"), 60)
	_check("a real tennis ball thrown at him is a catch (beat 'catch' seen)", caught)
	_mark(&"catch", caught)
	_clear_desk()
	await _frames(2)
	_brain.clear()

	# C — the cursor and the hands, through the SubViewport's own picking and input.
	_idle._disturb()
	var hovered: bool = await _hover(true)
	_check("the cursor over him is picked up by his grab region", hovered)
	_fired(&"watched", "the cursor over him")
	_prove(&"hover_changed")
	_check("and he attends to the cursor", _brain.attention() == ExpressionBrain.ATTEND_CURSOR)
	await _hover(false)
	_check("moving it off lets go of the watch", _brain.beat_id() != &"watched"
		and _brain.attention() == ExpressionBrain.ATTEND_NONE)
	_brain.clear()
	_idle._last_disturbance_msec = Time.get_ticks_msec() - int((ExpressionBrain.QUIET_SECONDS + 1.0) * 1000.0)
	await _hover(true)
	_fired(&"welcome_back", "the cursor back after a quiet spell")
	_brain._clock_skew += int(_brain._beat.get("until_msec", 0)) - _brain._now() + 20
	_brain._on_timer()
	_check("and then he settles into watching", _brain.beat_id() == &"watched")
	await _hover(false)
	_brain.clear()
	EventBus.spawn_requested.emit(&"pistol", Vector2.ZERO)
	_fired(&"harm_equipped", "equipping the pistol")
	_prove(&"cursor_power_changed")
	EventBus.spawn_requested.emit(&"pistol", Vector2.ZERO)
	_brain.clear()
	EventBus.spawn_requested.emit(&"open_hand", Vector2.ZERO)
	_fired(&"kind_equipped", "equipping the open hand")
	EventBus.spawn_requested.emit(&"open_hand", Vector2.ZERO)
	_brain.clear()
	await _frames(2)
	var grabbed: bool = await _grab()
	_check("a click on him picks him up", grabbed and _buddy.dragging)
	_fired(&"picked_up", "being picked up")
	await _advance_brain(ExpressionBrain.HELD_LONG_MSEC + 100)
	_fired(&"held_long", "held for six seconds")
	_buddy.linear_velocity = Vector2(1100, 0)
	await _frames(2)
	_check("flung about while held, he is shaken (beat 'shaken' seen)", _seen_now(&"shaken"))
	_mark(&"shaken", _seen_now(&"shaken"))
	await _release()
	_check("and letting go ends the hold", _brain.beat_id() != &"held_long" and not _buddy.dragging)
	await _frames(40)
	_brain.clear()
	_place(Vector2(HOME.x, FLOOR_Y - FEET - 200.0))
	_landings.clear()
	var landed := await _until(func() -> bool: return not _landings.is_empty(), 90)
	_check("dropped from 200 px he lands (beat 'landed' seen)", landed and _seen_now(&"landed"))
	_mark(&"landed", landed and _seen_now(&"landed"))
	await _frames(20)
	_brain.clear()

	# D — the world. A real grenade, lit beside him and then gone off.
	EventBus.spawn_requested.emit(&"grenade", _buddy.global_position + Vector2(-300, -40))
	var grenade := _last_spawned(&"grenade") as ThrowableBase
	await _frames(30)
	_brain.clear()
	if grenade:
		grenade.prime_explosion()
		_fired(&"fuse_lit", "a grenade primed 300 px away")
		_check("and it holds his attention", _brain.attention() == ExpressionBrain.ATTEND_THREAT)
		_prove(&"threat_changed")
		grenade.explode()
		_fired(&"blast", "the grenade going off")
	else:
		_check("a grenade can be staged", false)
	await _frames(10)
	_clear_desk()
	_brain.clear()
	EventBus.spawn_requested.emit(BAT, _buddy.global_position + Vector2(-150, -60))
	_fired(&"item_landed", "a bat spawned beside him")
	_prove(&"item_spawned")
	_clear_desk()
	_brain.clear()
	var device := _any_automation_node()
	_check("the roster has an automation capstone to switch", device != &"")
	if device != &"":
		_hush()
		Progression.set_automation_enabled(device, true)
		_fired(&"device_appeared", "an automation switched on ('%s')" % device)
		_prove(&"automation_toggled")
	_brain.clear()

	# E — the economy, through Progression and Economy.
	Economy.grant(Economy.BONES, 1.0e9)
	Economy.grant(Economy.HEARTS, 1.0e9)
	_brain.clear()
	var buyable := _something_to_buy()
	if buyable != &"":
		# Sampled from a listener connected after the brain's, so it sees the beat the purchase
		# itself asked for — a milestone the purchase completes is claimed a moment later and
		# its own `claimed` beat, at the same priority, rightly replaces it.
		_sampled.clear()
		EventBus.item_purchased.connect(_sample_beat, CONNECT_ONE_SHOT)
		Progression.purchase_item(buyable)
		var bought := _sampled.has(&"purchase")
		_check("buying '%s' → 'purchase' (beat right after the purchase '%s', now '%s')"
			% [buyable, _list(_sampled), _brain.beat_id()], bought)
		_mark(&"purchase", bought)
		_prove(&"item_purchased")
	_brain.clear()
	Progression.add_mastery_xp(MACE, 50000.0)
	_fired(&"rank_up", "a mastery rank on the mace")
	_prove(&"mastery_rank_up")
	_brain.clear()
	EventBus.contract_claimed.emit(&"brain_check", 0)
	_fired(&"claimed", "a contract claimed")
	_prove(&"contract_claimed")
	_brain.clear()
	Milestones.milestone_claimed.emit(&"brain_check", 1, 0)
	_fired(&"claimed", "a milestone claimed")
	_prove(&"milestone_claimed")
	_brain.clear()
	EventBus.prestige_performed.emit(0.0)
	_fired(&"reincarnated", "a Reincarnation")
	_prove(&"prestige_performed")
	_brain.clear()
	Economy.grant(Economy.BONES, 50000.0, _buddy.global_position, MACE)
	_check("a big payout at Normal is nothing", _brain.beat_id() != &"big_payout")
	_focus(Settings.Intensity.CHAOS)
	Economy.grant(Economy.BONES, 50000.0, _buddy.global_position, MACE)
	_fired(&"big_payout", "a 50,000 payout at Chaos")
	_prove(&"payout")
	_focus(Settings.Intensity.NORMAL)
	_brain.clear()

	# F — the desktop, through the buddy's own notifications.
	EventBus.ui_panel_changed.emit(&"shop")
	_fired(&"card_opened", "the card opening")
	_prove(&"ui_panel_changed")
	EventBus.ui_panel_changed.emit(&"")
	_brain.clear()
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("losing focus starts the away clock", _brain.away_seconds() >= 0.0 and _brain._away_since > 0)
	_hush()
	await _advance_brain(ExpressionBrain.SLEEP_AFTER_MSEC + 50)
	_check("the away clock runs on the brain's clock (%.1f s)" % _brain.away_seconds(),
		_brain.away_seconds() >= ExpressionBrain.SLEEP_AFTER_MSEC / 1000.0)
	_fired(&"asleep", "ninety seconds unfocused")
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_fired(&"reunion", "focus back after more than a minute")
	_brain.clear()
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("back after a moment is no reunion", _brain.beat_id() != &"reunion")
	_brain.clear()

	# H — ambient, off the brain's one timer.
	_idle._disturb()
	_hush()
	_brain._blink_at = _brain._now() + 10
	await _advance_brain(50)
	_fired(&"blink", "the blink deadline passing")
	_brain.clear()
	_hush()
	_brain._fidget_at = _brain._now() + 10
	await _advance_brain(50)
	_fired(&"fidget", "the fidget deadline passing")
	_brain.clear()
	_hush()
	_idle._last_disturbance_msec = Time.get_ticks_msec() - int((ExpressionBrain.QUIET_SECONDS + 1.0) * 1000.0)
	_brain._yawned = false
	# The yawn has no deadline of its own: it is noticed on the next ambient tick.
	_brain._blink_at = _brain._now() + 5
	await _advance_brain(10)
	_fired(&"yawn", "twenty-five quiet seconds, on the next ambient tick")
	_brain.clear()
	await _advance_brain(10)
	_check("one yawn per quiet spell", _brain.beat_id() != &"yawn")
	_idle._disturb()
	_brain.clear()
	_end()

## D36's two rules, for every row: at Off a reactive row still plays — as a face and a tag
## with zero motion — and nothing gated above it starts at all.
func _expression_focus_off() -> void:
	_begin("expression — Focus Off")
	await _stage("focus off", true)
	_buddy.mood.set_value(40.0)
	_focus(Settings.Intensity.OFF)
	await _frames(2)
	_recording = false
	var wrong: Array[String] = []
	for id in ExpressionBrain.ROWS:
		var row: Dictionary = ExpressionBrain.ROWS[id]
		_brain.clear()
		var ok := _ask(id)
		var reactive: bool = row.get("gate", &"R") == ExpressionBrain.GATE_REACTIVE
		if reactive and not ok:
			wrong.append("%s refused" % id)
		elif not reactive and ok:
			wrong.append("%s (gate %s) started" % [id, row.get("gate")])
		elif ok:
			var extent := await _motion_extent(4)
			if extent > 0.001 or _art._motion != &"":
				wrong.append("%s moved %.2f px" % [id, extent])
	_brain.clear()
	_check("at Off, reactive rows play still and every other row stays out (%s)"
		% _list(wrong), wrong.is_empty())
	_recording = true
	# The real triggers too: a hit changes his face and moves nothing.
	var face_before := _art.face.animation
	await _hit(6000.0, BAT)
	_check("a real hit at Off changes his face ('%s' → '%s')" % [face_before, _art.face.animation],
		_art.face.animation != face_before)
	var extent2 := await _motion_extent(6)
	_check("and moves nothing (%.3f px)" % extent2, extent2 < 0.001)
	_brain.clear()
	await _settle_hit()
	var ambient := _brain.ambient_starts
	_brain._clock_skew += 120000
	_brain._on_timer()
	_idle._last_disturbance_msec = Time.get_ticks_msec() - 60000
	_brain._on_timer()
	_check("two idle minutes at Off start no ambient beat, no yawn", _brain.ambient_starts == ambient
		and not _brain.beat_active())
	_brain._arm()
	_check("and the brain's timer has nothing to wake for", _brain._timer.is_stopped())
	_brain._on_mood_changed(0.0)
	_check("the mood-trough posture stays off", is_equal_approx(_art.body.speed_scale, 1.0)
		and is_zero_approx(_art.body.rotation))
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_brain._clock_skew += ExpressionBrain.SLEEP_AFTER_MSEC + 50
	_brain._on_timer()
	_check("unfocused for ninety seconds at Off, he does not fall asleep (Subtle row)",
		_brain.beat_id() != &"asleep")
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("and the reunion still plays: he reacts to you coming back",
		_brain.beat_id() == &"reunion")
	_brain.clear()
	_focus(Settings.Intensity.NORMAL)
	_end()

## What he is looking at, how worked up he is, and how long you have been gone.
func _expression_attention() -> void:
	_begin("expression — attention, arousal, away")
	await _stage("attention", true)
	_focus(Settings.Intensity.NORMAL)
	_buddy.mood.set_value(40.0)
	await _frames(2)
	_brain.clear()
	_brain._arousal = 0.0
	_brain.react(&"hit")
	var bump := _brain.arousal()
	var expected := float(ExpressionBrain.PAIN) / float(ExpressionBrain.BEAT) * 0.5
	_check("a pain beat raises arousal by priority/BEAT x 0.5 (%.3f, want %.3f)" % [bump, expected],
		absf(bump - expected) < 0.01)
	_brain._clock_skew += int(ExpressionBrain.AROUSAL_HALF_LIFE * 1000.0)
	var ratio := _brain.arousal() / bump
	_measure("arousal after one half-life: %.3f of the bump" % ratio)
	_check("and halves every %.0f s (%.3f)" % [ExpressionBrain.AROUSAL_HALF_LIFE, ratio],
		absf(ratio - 0.5) < 0.02)
	_brain.clear()
	# The gaze: two pixels toward the cursor at Normal, nothing at Subtle, never a chase. Only
	# while the cursor is over him — leaving his grab region is leaving him.
	await _hover(true)
	var left := _buddy.global_position + Vector2(-25, -20)
	_push_motion(left)
	await _frames(2)
	var toward := _art._look_x
	_check("at Normal he looks toward the cursor (look %.1f px, cursor on his left side)" % toward,
		toward < -0.5 and absf(toward) <= 2.0 * _brain._amp() + 0.01)
	_push_motion(_buddy.global_position + Vector2(25, -20))
	await _frames(2)
	_check("and follows it across him (look %.1f px)" % _art._look_x, _art._look_x > 0.5)
	_check("but never chases it (he is standing still: %.1f px/s)" % _buddy.linear_velocity.length(),
		_buddy.linear_velocity.length() < 5.0)
	_focus(Settings.Intensity.SUBTLE)
	_push_motion(left)
	await _frames(2)
	_check("at Subtle the gaze is off (look %.1f px)" % _art._look_x, is_zero_approx(_art._look_x))
	_focus(Settings.Intensity.NORMAL)
	await _hover(false)
	_check("leaving drops the gaze and the attention", is_zero_approx(_art._look_x)
		and _brain.attention() == ExpressionBrain.ATTEND_NONE)
	# The cursor leaving the window, which sends no mouse_exited.
	await _hover(true)
	_buddy._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	_check("the cursor leaving the window lets go too", _brain.attention() == ExpressionBrain.ATTEND_NONE
		and _brain.beat_id() != &"watched")
	_brain.clear()
	# Away: arousal drops to nothing and ambient stops while you are gone.
	_brain.react(&"hit")
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("losing focus drops arousal to nothing (%.3f)" % _brain.arousal(), is_zero_approx(_brain.arousal()))
	_check("and no ambient beat may start while away", not _brain._ambient_allowed())
	_brain._clock_skew += 12345
	_check("the away clock reads the skewed time (%.2f s)" % _brain.away_seconds(),
		absf(_brain.away_seconds() - 12.345) < 0.1)
	_buddy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("and stops when you are back", is_zero_approx(_brain.away_seconds()))
	_brain.clear()
	_end()

## Every `connect()` in `ExpressionBrain._ready`, read out of the source, is live — and every
## one this suite knows a trigger for was seen doing something.
func _expression_wires() -> void:
	_begin("expression — every wire")
	var source := FileAccess.get_file_as_string("res://Scripts/Buddy/expression_brain.gd")
	var start := source.find("func _ready() -> void:")
	var stop := source.find("\nfunc ", start + 10)
	var body := source.substr(start, stop - start)
	var re := RegEx.new()
	re.compile("([A-Za-z_][A-Za-z_\\.]*)\\.connect\\(([A-Za-z_]+)\\)")
	var wires := 0
	var unknown: Array[String] = []
	var unproven: Array[String] = []
	for m in re.search_all(body):
		var path := m.get_string(1)
		var sig_name := path.get_slice(".", path.get_slice_count(".") - 1)
		wires += 1
		if not KNOWN_WIRES.has(sig_name):
			unknown.append(path)
			continue
		if not _proven.has(sig_name):
			unproven.append(path)
	_check("the brain's _ready has its wires (%d found)" % wires, wires >= KNOWN_WIRES.size() - 2)
	_check("every known wire was seen doing something in a real trigger (not: %s)"
		% _list(unproven), unproven.is_empty())
	if not unknown.is_empty():
		_note("wires this suite has no trigger for yet — add one: %s" % _list(unknown))
	_end()

## The wires `ExpressionBrain._ready` connects and a section of this suite drives for real.
const KNOWN_WIRES := [
	&"timeout", &"beat_animation_finished", &"hover_changed", &"buddy_state_changed",
	&"damage_dealt", &"kindness_given", &"kindness_sustained", &"grime_changed",
	&"cursor_power_changed", &"item_purchased", &"mastery_rank_up", &"contract_claimed",
	&"milestone_claimed", &"prestige_performed", &"payout", &"ui_panel_changed",
	&"threat_changed", &"item_spawned", &"automation_toggled", &"mood_changed",
	&"focus_mode_changed", &"damaged", &"meter_reset",
]

## Which rows were caught live off a real trigger somewhere in the run. A row nobody caught is
## reported: either the suite needs a trigger for it, or the game never shows it.
func _expression_coverage() -> void:
	_begin("expression — coverage")
	var missed: Array[String] = []
	for id in ExpressionBrain.ROWS:
		if not _seen_real.has(id):
			missed.append(String(id))
	_measure("%d of %d rows caught live off a real trigger" % [ExpressionBrain.ROWS.size() - missed.size(),
		ExpressionBrain.ROWS.size()])
	if not missed.is_empty():
		_note("rows no real trigger produced in this run: %s" % _list(missed))
	# The rows this suite does drive must all have been caught; a new row is a note, not a
	# failure, so the next stream's rows arrive covered by the presentation pass above.
	var expected_missing: Array[String] = []
	for id in missed:
		if TRIGGERED_ROWS.has(StringName(id)):
			expected_missing.append(id)
	_check("every row with a known trigger was caught live (missing: %s)" % _list(expected_missing),
		expected_missing.is_empty())
	_end()

## Rows this suite drives through a real trigger in some section.
const TRIGGERED_ROWS := [
	&"hit_light", &"hit", &"hit_heavy", &"hit_annoyed", &"cooking", &"meter_reset", &"pet",
	&"pet_combo", &"cared_for", &"sparkling", &"eat", &"catch", &"soaking", &"watched",
	&"harm_equipped", &"kind_equipped", &"picked_up", &"held_long", &"shaken", &"landed",
	&"fuse_lit", &"blast", &"threatened", &"item_landed", &"device_appeared", &"purchase",
	&"rank_up", &"claimed", &"reincarnated", &"big_payout", &"asleep", &"reunion",
	&"welcome_back", &"yawn", &"card_opened", &"arrived", &"bouncing", &"dancing",
	&"scrubbing", &"nibbling", &"gave_up", &"toy_gone", &"blink", &"fidget",
]

func _fired(id: StringName, what: String) -> void:
	_see()
	var live := _brain.beat_id() == id
	_check("%s → '%s' (beat '%s', face '%s', tag '%s')" % [what, id, _brain.beat_id(),
		_art.face.animation, _art.body.animation], live)
	_mark(id, live)

func _mark(id: StringName, seen: bool) -> void:
	if seen:
		_seen_real[id] = true

func _prove(wire: StringName) -> void:
	_proven[wire] = true

# =====================================================================================
# stubs filled in below
# =====================================================================================

# =====================================================================================
# B — IdleBrain
# =====================================================================================

## When he sets off: twenty-five seconds left alone, six after being offered something — and
## the sequence the owner actually tried, a ball from the shop dropped where the shop drops it.
func _idle_thresholds() -> void:
	_begin("idle brain — when he starts")
	await _stage("idle thresholds", true)
	_focus(Settings.Intensity.NORMAL)
	var timer := _idle.get_node("ThinkTimer") as Timer
	_check("the brain has its own think timer at %.1f s" % IdleBrain.THINK_SECONDS,
		timer != null and is_equal_approx(timer.wait_time, IdleBrain.THINK_SECONDS))
	await _spawn_toy(&"beanbag", HOME.x - 300.0)
	_idle._disturb()
	_check("being disturbed leaves him the full %.0f s wait" % IdleBrain.IDLE_SECONDS,
		is_equal_approx(_idle._wait_seconds, IdleBrain.IDLE_SECONDS))
	_idle._last_disturbance_msec = Time.get_ticks_msec() - int((IdleBrain.IDLE_SECONDS - 0.5) * 1000.0)
	_idle.think_now()
	_check("at %.1f s alone he is still watching" % (IdleBrain.IDLE_SECONDS - 0.5),
		_idle.phase_name() == IdleBrain.PHASE_WATCHING)
	_idle._last_disturbance_msec = Time.get_ticks_msec() - int((IdleBrain.IDLE_SECONDS + 0.5) * 1000.0)
	_idle.think_now()
	_check("at %.1f s he sets off for the beanbag (phase '%s', target '%s')"
		% [IdleBrain.IDLE_SECONDS + 0.5, _idle.phase_name(), _idle.target_id()],
		_idle.phase_name() == IdleBrain.PHASE_TRAVELLING and _idle.target_id() == &"beanbag")
	_idle._disturb()
	_clear_desk()
	await _frames(3)

	# The offer: putting a toy down shortens the wait and moves the clock, never backdates it.
	var before := Time.get_ticks_msec()
	await _spawn_toy(&"beanbag", HOME.x - 320.0)
	_check("a toy put down is an offer: the wait is %.0f s" % _idle._wait_seconds,
		is_equal_approx(_idle._wait_seconds, IdleBrain.INVITED_SECONDS))
	_check("and the clock moved forward rather than being backdated",
		_idle._last_disturbance_msec >= before)
	_idle._last_disturbance_msec = Time.get_ticks_msec() - int((IdleBrain.INVITED_SECONDS - 0.5) * 1000.0)
	_idle.think_now()
	_check("%.1f s after the offer he is still watching it land" % (IdleBrain.INVITED_SECONDS - 0.5),
		_idle.phase_name() == IdleBrain.PHASE_WATCHING)
	_idle._last_disturbance_msec = Time.get_ticks_msec() - int((IdleBrain.INVITED_SECONDS + 0.5) * 1000.0)
	_idle.think_now()
	_check("%.1f s after it he goes to it (phase '%s')" % [IdleBrain.INVITED_SECONDS + 0.5, _idle.phase_name()],
		_idle.phase_name() == IdleBrain.PHASE_TRAVELLING)
	# Busy: a second toy does not march him across the desk.
	var target := _idle.target_id()
	await _spawn_toy(&"tennis_ball", HOME.x + 300.0)
	_check("a second toy put down while he is on his way does not divert him (target '%s')"
		% _idle.target_id(), _idle.phase_name() == IdleBrain.PHASE_TRAVELLING and _idle.target_id() == target)
	# Mooching is free, though: a toy arriving then is exactly what he is waiting for.
	_idle._finish(true)
	_check("a finished routine leaves him mooching", _idle.phase_name() == IdleBrain.PHASE_WANDERING)
	await _spawn_toy(&"tennis_ball", HOME.x + 250.0)
	_check("and a toy put down while he mooches is considered at once (phase '%s', wait %.0f s)"
		% [_idle.phase_name(), _idle._wait_seconds], _idle.phase_name() == IdleBrain.PHASE_WATCHING
		and is_equal_approx(_idle._wait_seconds, IdleBrain.INVITED_SECONDS))
	_idle._disturb()
	_clear_desk()
	await _frames(3)

	# The owner's sequence. The shop spawns at `_default_position()` — the middle of the window,
	# a fifth of the way down — which is where he stands; the toy falls on his head.
	for id in [&"tennis_ball", &"beach_ball"]:
		_idle._disturb()
		_clear_desk()
		await _frames(2)
		_place(Vector2(_spawner._default_position().x, HOME.y))
		await _frames(20)
		_reset_log()
		Progression._unlock(id)
		EventBus.spawn_requested.emit(id, Vector2.ZERO)
		var offer_at := Time.get_ticks_msec()
		await _frames(90)
		var touched := _value_from(_given, id) > 0.0 or not _hits_from(id).is_empty()
		_measure("'%s' from the shop: landed on him %s; the wait afterwards is %.0f s"
			% [id, "(and paid)" if touched else "(without paying)", _idle._wait_seconds])
		_check("'%s' dropped from the shop onto him is still an offer (wait %.0f s, not %.0f)"
			% [id, _idle._wait_seconds, IdleBrain.IDLE_SECONDS],
			is_equal_approx(_idle._wait_seconds, IdleBrain.INVITED_SECONDS))
		_idle._last_disturbance_msec = offer_at - int((IdleBrain.INVITED_SECONDS + 0.5) * 1000.0)
		_idle.think_now()
		_check("and %.0f s after it was put down he goes to play with it (phase '%s', target '%s')"
			% [IdleBrain.INVITED_SECONDS + 0.5, _idle.phase_name(), _idle.target_id()],
			_idle.target_id() == id and _idle.phase_name() != IdleBrain.PHASE_WATCHING)
	_idle._disturb()
	_end()

## Every toy he has a routine for, read off ItemDB: put down on the floor to his left, he walks
## to it, does the routine, the right party pays, and he leaves and comes back sensibly.
func _idle_every_toy() -> void:
	_begin("idle brain — every toy he has a routine for")
	await _stage("every toy", true)
	_focus(Settings.Intensity.NORMAL)
	var toys := _routine_toys()
	if _quick:
		var seen := {}
		var few: Array[Array] = []
		for entry in toys:
			if not seen.has(entry[1]):
				seen[entry[1]] = true
				few.append(entry)
		toys = few
	if not _toys.is_empty():
		var picked: Array[Array] = []
		for entry in toys:
			if _toys.has(String(entry[0])):
				picked.append(entry)
		toys = picked
	_measure("%d toys with a routine: %s" % [toys.size(), ", ".join(toys.map(
		func(e: Array) -> String: return "%s (%s)" % [e[0], ROUTINE_NAMES.get(e[1], "?")]))])
	var beside: Array[String] = []
	for entry in toys:
		var on_top: bool = await _play_routine(entry[0], entry[1])
		if int(entry[1]) == IdleBrain.ROUTINE_SOAK and not on_top:
			beside.append(String(entry[0]))
	if not beside.is_empty():
		_measure("soak toys he ended up beside rather than on or in: %s" % _list(beside))
	_idle._disturb()
	_clear_desk()
	_end()

const ROUTINE_NAMES := {
	1: "bounce", 2: "play", 3: "soak", 4: "scrub", 5: "nibble", 6: "bop", 7: "fidget",
}

## [item id, routine] for every item whose scene gives him something to do with it.
func _routine_toys() -> Array[Array]:
	var out: Array[Array] = []
	for item in ItemDB.all_items():
		if item.scene == null:
			continue
		var node := item.scene.instantiate()
		var body := node as BaseDraggable
		if body:
			body.item_id = item.id
			var routine := _idle._routine_for(body)
			if routine != IdleBrain.ROUTINE_NONE:
				out.append([item.id, routine])
		node.free()
	return out

## One toy, end to end. Returns whether he finished on it or in it (not merely against it).
func _play_routine(id: StringName, routine: int) -> bool:
	_idle._disturb()
	_clear_desk()
	await _frames(3)
	_buddy.health.reset_meter()
	# The sponge is only worth a trip to a dirty skeleton; everything else wants him clean.
	_buddy.grime.set_value(0.8 if routine == IdleBrain.ROUTINE_SCRUB else 0.0)
	Economy.grime = _buddy.grime.value
	_brain.clear()
	Progression._unlock(id)
	var toy_x := 300.0
	EventBus.spawn_requested.emit(id, Vector2(toy_x, FLOOR_Y - 220.0))
	var toy := _last_spawned(id) as BaseDraggable
	if toy == null:
		_check("'%s' spawns" % id, false)
		return false
	# He stands far enough to its right that reaching it is a walk, not a lean.
	var half := toy.get_interaction_rect().size.x * 0.5
	_place(Vector2(toy_x + half + 44.0 + IdleBrain.ARRIVE_SLACK + 110.0, HOME.y))
	await _frames(45)
	if not is_instance_valid(toy):
		_check("'%s' survives being put down" % id, false)
		return false
	var name_ := "%s (%s)" % [id, ROUTINE_NAMES.get(routine, "?")]
	var start_gap := absf(_buddy.global_position.x - toy.global_position.x)
	_reset_log()
	_idle.pretend_idle()
	_idle.think_now()
	var chose := _idle.target_id() == id
	var problems: Array[String] = []
	if not chose:
		problems.append("did not choose it (target '%s')" % _idle.target_id())

	# The walk.
	var closest := start_gap
	var hops := 0
	var rising := false
	var tilt := 0.0
	var locked := true
	var arrived := _idle.phase_name() == IdleBrain.PHASE_PLAYING
	var walk_frames := 0
	var walk_start := Time.get_ticks_usec()
	for f in 360:
		if arrived:
			break
		await get_tree().physics_frame
		_see()
		walk_frames += 1
		if f % 30 == 29:
			_idle.think_now()
		if not is_instance_valid(toy):
			break
		closest = minf(closest, absf(_buddy.global_position.x - toy.global_position.x))
		tilt = maxf(tilt, absf(wrapf(_buddy.rotation, -PI, PI)))
		var up := _buddy.linear_velocity.y < -150.0
		if up and not rising:
			hops += 1
		rising = up
		if _idle.phase_name() == IdleBrain.PHASE_TRAVELLING:
			locked = locked and _buddy.lock_rotation
		elif _idle.phase_name() == IdleBrain.PHASE_PLAYING:
			arrived = true
		else:
			break
	var walk_seconds := float(Time.get_ticks_usec() - walk_start) / 1.0e6
	var walk_hits := _hits.size()
	var toy_walk_paid := _value_from(_sustained, id)
	if not arrived:
		problems.append("never arrived (phase '%s', closed %.0f of %.0f px)" % [_idle.phase_name(),
			start_gap - closest, start_gap])
	if start_gap - closest < 40.0 and not arrived:
		problems.append("did not travel toward it")
	# Nothing on the way, not even on the way to a trampoline: his own play is not a hit (D70).
	if walk_hits > 0:
		problems.append("the walk cost him %d hits" % walk_hits)
	if hops > IdleBrain.MAX_CLIMBS_PER_TRIP:
		problems.append("%d hops on the way" % hops)
	if tilt > 0.1:
		problems.append("tilted %.1f deg" % rad_to_deg(tilt))
	if not locked:
		problems.append("rotation not locked while travelling")

	# The routine itself, and who pays for it.
	_reset_log()
	var paid_before := _idle.paid_value
	var grime_before := _buddy.grime.value
	var contact := 0
	var on_top := 0
	var play_frames := 0
	var play_start := Time.get_ticks_usec()
	# What he looks like while he does it: the routine's own row (plan §2G) is the whole reason
	# the idle brain is visible at all.
	var look: StringName = ExpressionBrain.ROUTINE_HOLDS.get(routine, &"")
	var seated := 0
	var look_frames := 0
	var lost_frames := 0
	var instead := {}
	if arrived:
		for f in 96:
			await get_tree().physics_frame
			_see()
			play_frames += 1
			if f % 30 == 29:
				_idle.think_now()
			if not is_instance_valid(toy):
				break
			var beat := _brain.beat_id()
			if beat == look:
				look_frames += 1
			else:
				instead[beat] = int(instead.get(beat, 0)) + 1
			# Anything he reacts to on the way — a rank up, a pet off a massage chair, a landing —
			# is fine so long as the routine comes back after it. What is not fine is the slot
			# going empty, or the generic `cared_for` sitting over the routine's own look.
			if f >= 30 and (beat == &"" or beat == &"cared_for"):
				lost_frames += 1
			# Sitting in it is touching it: the two pass through each other while he is in (D70).
			var friendly_toy := toy as FriendlyBase
			if toy in _buddy.get_colliding_bodies() or (friendly_toy and friendly_toy.touches(_buddy)):
				contact += 1
			var mine := _buddy.get_interaction_rect()
			var its := toy.get_interaction_rect()
			var on := mine.end.y <= its.position.y + 16.0 and mine.position.x < its.end.x \
				and mine.end.x > its.position.x
			# In it: his middle over its middle and his feet off the floor it stands on.
			var in_it := mine.get_center().x > its.position.x and mine.get_center().x < its.end.x \
				and mine.end.y <= its.end.y - 12.0
			if on or in_it:
				on_top += 1
			if friendly_toy and friendly_toy.is_seated(_buddy):
				seated += 1
			if _idle.phase_name() != IdleBrain.PHASE_PLAYING:
				break
	var play_seconds := float(Time.get_ticks_usec() - play_start) / 1.0e6
	var brain_paid := _idle.paid_value - paid_before
	var toy_sustained := maxf(_value_from(_sustained, id) - brain_paid, 0.0)
	var toy_given := _value_from(_given, id)
	var toy_hits := _hits_from(id).size()
	var cleaned := grime_before - _buddy.grime.value
	var toy_paid := toy_sustained > 0.0 or toy_given > 0.0 or toy_hits > 0
	if arrived:
		# His own play is never a hit (D70): not the toy, not the floor. Bouncing billed the mat
		# about 17.6 damage a second with nobody at the desk, on top of the brain's Hearts, and a
		# bowling ball bopped onto his own head billed Bones too.
		var own_hits := _hits.filter(func(h: HitInfo) -> bool:
			return h.source_id == id or h.source_id == &"world")
		if not own_hits.is_empty():
			problems.append("his own play billed %d hits (%s)" % [own_hits.size(), _list(own_hits.map(
				func(h: HitInfo) -> String: return "%s %.1f" % [h.source_id, h.amount]))])
		var brain_should := _idle._brain_pays(routine)
		if brain_should and brain_paid <= 0.0:
			problems.append("the brain should pay for this and paid nothing")
		if not brain_should and brain_paid > 0.0:
			problems.append("the brain paid %.2f on top of the toy (double payment)" % brain_paid)
		match routine:
			IdleBrain.ROUTINE_BOUNCE:
				if toy_sustained > 0.0 or toy_given > 0.0:
					problems.append("the trampoline paid kindness itself")
			IdleBrain.ROUTINE_PLAY:
				if toy_sustained <= 0.0:
					problems.append("the generator paid nothing while he danced")
			IdleBrain.ROUTINE_SOAK:
				if toy_sustained <= 0.0:
					problems.append("sitting in it paid nothing (in contact %d of %d frames)" % [contact, play_frames])
				# In it, not against it (D70; AI audit B found 0 of 9 soak toys with him on or in them).
				if seated == 0 or on_top < play_frames / 3:
					problems.append("he never got in it (sat in it %d of %d frames, over or in it %d)"
						% [seated, play_frames, on_top])
			IdleBrain.ROUTINE_SCRUB:
				if cleaned <= 0.0 or toy_sustained <= 0.0:
					problems.append("the scrub cleaned %.3f and paid %.2f" % [cleaned, toy_sustained])
			IdleBrain.ROUTINE_NIBBLE:
				if toy_given <= 0.0 and toy_sustained <= 0.0:
					problems.append("eating it paid nothing")
			IdleBrain.ROUTINE_BOP:
				# A kind ball pays on the bop itself. A weapon-side ball is played with for its own
				# sake: a bop lifts it beside him rather than dropping it on him, and a toy has to
				# land at the fall floor to count — a design question (docs/ai-audit-2026-09.md).
				if not toy_paid and toy is FriendlyBase:
					problems.append("knocking it about paid nothing (%d frames touching)" % contact)
				elif not toy_paid:
					_note("%s is bopped for its own sake: the bop never brings a weapon-side ball down on him" % id)
		# The look: worn, and never lost to an empty slot or the generic trickle face.
		if look != &"" and play_frames >= 60 and (look_frames == 0 or lost_frames > int((play_frames - 30) * 0.2)):
			problems.append("wore '%s' on %d of %d frames, lost it on %d (instead: %s)" % [look, look_frames,
				play_frames, lost_frames, _list(instead.keys().map(func(k: Variant) -> String:
					return "%s x%d" % [k if String(k) != "" else "nothing", instead[k]]))])
	var line := "%s: %.0f px in %.1f s (%d hops, tilt %.1f deg); playing %.1f s, touching %d/%d frames, on or in it %d (sat in it %d); toy paid %.2f sustained + %.2f acts + %d hits, brain %.2f%s" % [
		name_, start_gap - closest, walk_seconds, hops, rad_to_deg(tilt), play_seconds, contact,
		play_frames, on_top, seated, toy_sustained, toy_given, toy_hits, brain_paid,
		(", cleaned %.2f" % cleaned) if routine == IdleBrain.ROUTINE_SCRUB else ""]
	if routine == IdleBrain.ROUTINE_PLAY and walk_seconds > 0.6:
		line += "; its own rate while he walked %.2f/s, while he danced %.2f/s" % [
			toy_walk_paid / walk_seconds, toy_sustained / maxf(play_seconds, 0.01)]
	_measure(line)

	# Leaving, and coming back.
	var guard := 0
	while _idle.phase_name() == IdleBrain.PHASE_PLAYING and guard < 14:
		_idle.think_now()
		guard += 1
	var reason: StringName = _ends.back() if not _ends.is_empty() else &""
	if arrived:
		var consumed := not is_instance_valid(toy)
		if consumed:
			if reason != &"toy_gone" or _idle.phase_name() != IdleBrain.PHASE_WANDERING:
				problems.append("used up, he did not move on (reason '%s', phase '%s')" % [reason, _idle.phase_name()])
		else:
			var cool := int(_idle._cooldowns.get(toy.get_instance_id(), 0)) - Time.get_ticks_msec()
			if reason != &"done" or _idle.phase_name() != IdleBrain.PHASE_WANDERING:
				problems.append("the dwell ran out and he did not leave (reason '%s', phase '%s')"
					% [reason, _idle.phase_name()])
			elif absf(cool / 1000.0 - IdleBrain.TOY_COOLDOWN) > 2.0:
				problems.append("cooldown %.1f s, not %.0f" % [cool / 1000.0, IdleBrain.TOY_COOLDOWN])
			else:
				for i in 3:
					_idle.think_now()
				var mooched := _idle.phase_name() == IdleBrain.PHASE_WATCHING
				# On his feet before he is asked to start again: he never sets off lying down,
				# and a trampoline can still be throwing him about when the dwell ends.
				var before_rest := _hits.size()
				var settled := await _until(_standing_still, 300)
				# Bouncing on after the dwell is still his own play until he stops.
				var after := _hits.slice(before_rest).filter(func(h: HitInfo) -> bool:
					return h.source_id == id or h.source_id == &"world")
				if not after.is_empty():
					problems.append("coming to rest after it billed %d hits" % after.size())
				if not settled:
					problems.append("never came to rest after leaving (v %.0f px/s, tilt %.0f deg)"
						% [_buddy.linear_velocity.length(), rad_to_deg(wrapf(_buddy.rotation, -PI, PI))])
				_idle.pretend_idle()
				_idle.think_now()
				var rested := _idle.phase_name() == IdleBrain.PHASE_WATCHING
				_idle._cooldowns[toy.get_instance_id()] = 0
				_idle.pretend_idle()
				_idle.think_now()
				var back := _idle.target_id() == id and _idle.phase_name() != IdleBrain.PHASE_WATCHING
				if not (mooched and rested and back):
					problems.append("return: mooched %s, left it alone while cooling %s, came back %s"
						% [mooched, rested, back])
	_idle._disturb()
	_check("%s%s" % [name_, "" if problems.is_empty() else ": " + "; ".join(problems)], problems.is_empty())
	return on_top > play_frames / 2

## A toy through the real spawner, on the floor at `x`, settled. Unlocks it first.
func _spawn_toy(id: StringName, x: float) -> BaseDraggable:
	Progression._unlock(id)
	EventBus.spawn_requested.emit(id, Vector2(x, FLOOR_Y - 160.0))
	var toy := _last_spawned(id) as BaseDraggable
	await _frames(40)
	return toy

## Anything the player does stands him down; anything that acts by itself never does.
func _idle_interruptions() -> void:
	_begin("idle brain — interruptions")
	await _stage("interruptions", true)
	_focus(Settings.Intensity.NORMAL)
	var bag := await _spawn_toy(&"beanbag", HOME.x - 320.0)
	_idle.pretend_idle()
	_idle.think_now()
	await _frames(20)
	_check("he is on his way to the beanbag", _idle.phase_name() == IdleBrain.PHASE_TRAVELLING)
	_ends.clear()
	var grabbed: bool = await _grab()
	_check("picking him up mid-walk stands him down (grabbed %s, phase '%s', reason %s)"
		% [grabbed, _idle.phase_name(), _list(_ends)],
		grabbed and _idle.phase_name() == IdleBrain.PHASE_WATCHING and _ends.has(&"disturbed"))
	_check("and gives him his rotation back", not _buddy.lock_rotation)
	_check("and his stride stops the same frame", is_zero_approx(_art._travel))
	await _release()
	await _frames(40)
	_idle.pretend_idle()
	_idle.think_now()
	await _frames(10)
	await _hit(6000.0, BAT)
	_check("the player's bat stands him down", _idle.phase_name() == IdleBrain.PHASE_WATCHING)
	await _settle_hit()

	# Now let him get there and settle, then throw every source in the game at him.
	_place(Vector2(bag.global_position.x + 150.0, HOME.y))
	await _frames(20)
	_idle.pretend_idle()
	_idle.think_now()
	var there := await _until(func() -> bool: return _idle.phase_name() == IdleBrain.PHASE_PLAYING, 240)
	_check("he reaches the beanbag", there)
	var autonomous := 0
	var stood_down: Array[String] = []
	for item in ItemDB.all_items():
		if not item.is_autonomous:
			continue
		autonomous += 1
		EventBus.damage_dealt.emit(HitInfo.new(1.0, item.id, _buddy.global_position, 400.0))
		if _idle.phase_name() != IdleBrain.PHASE_PLAYING:
			stood_down.append(String(item.id))
			_idle.pretend_idle()
			_idle.think_now()
			await _until(func() -> bool: return _idle.phase_name() == IdleBrain.PHASE_PLAYING, 240)
	_check("damage from all %d things that act by themselves never stands him down (did: %s)"
		% [autonomous, _list(stood_down)], stood_down.is_empty() and autonomous > 0)
	EventBus.damage_dealt.emit(HitInfo.new(1.0, &"world", _buddy.global_position, 1600.0))
	EventBus.damage_dealt.emit(HitInfo.new(1.0, &"beanbag", _buddy.global_position, 1600.0))
	EventBus.kindness_sustained.emit(&"beanbag", 1.0, _buddy.global_position)
	_check("nor does the floor, or his own toy hurting or paying him", _idle.phase_name() == IdleBrain.PHASE_PLAYING)
	# The hand-driven half, one of each kind of hand, through the real bus.
	var hand_ids: Array[StringName] = []
	for category in [ItemData.CATEGORY_WEAPON, ItemData.CATEGORY_THROWABLE, ItemData.CATEGORY_CURSOR_POWER]:
		for item in ItemDB.all_items():
			if item.category == category and not item.is_autonomous:
				hand_ids.append(item.id)
				break
	hand_ids.append(&"open_hand")
	var ignored: Array[String] = []
	for source in hand_ids:
		if _idle.phase_name() != IdleBrain.PHASE_PLAYING:
			_idle.pretend_idle()
			_idle.think_now()
			await _until(func() -> bool: return _idle.phase_name() == IdleBrain.PHASE_PLAYING, 240)
		var item := ItemDB.get_item(source)
		if item and item.is_kind():
			EventBus.kindness_given.emit(source, 1.0, _buddy.global_position)
		else:
			EventBus.damage_dealt.emit(HitInfo.new(1.0, source, _buddy.global_position, 400.0))
		if _idle.phase_name() == IdleBrain.PHASE_PLAYING:
			ignored.append(String(source))
	_check("a hand of each kind stands him down: %s (ignored: %s)" % [_list(hand_ids), _list(ignored)],
		ignored.is_empty())
	# A data sweep behind it: every hand-held harm item is not marked autonomous.
	var misfiled: Array[String] = []
	for item in ItemDB.all_items():
		var hand := item.category in [ItemData.CATEGORY_WEAPON, ItemData.CATEGORY_THROWABLE,
			ItemData.CATEGORY_CURSOR_POWER]
		var own := item.category in [ItemData.CATEGORY_TURRET, ItemData.CATEGORY_CRITTER]
		if (hand and item.is_autonomous) or (own and not item.is_autonomous):
			misfiled.append(String(item.id))
	_check("every turret and critter acts on its own and every hand-held harm item does not (misfiled: %s)"
		% _list(misfiled), misfiled.is_empty())
	_idle._disturb()
	await _settle_hit()

	# Real things acting by themselves on the desk while he plays: a turret's shots and a
	# critter's blows. Put down first — putting them down *is* the player arriving.
	for id in [_longest_reach_turret(), &"goose"]:
		if id == &"":
			continue
		_clear_desk()
		await _frames(3)
		Progression._unlock(id)
		# The goose is melee, and a skeleton sitting in a beanbag is out of its 78 px reach (D70:
		# he gets in it now). So it finds him dancing at a boombox, where a peck can land.
		var toy_id := &"boombox" if id == &"goose" else &"beanbag"
		Progression._unlock(toy_id)
		bag = await _spawn_toy(toy_id, 360.0)
		_place(Vector2(520.0, HOME.y))
		# Within the turret's reach of the beanbag he will be sitting in.
		EventBus.spawn_requested.emit(id, Vector2(860.0, FLOOR_Y - 60.0))
		await _frames(10)
		_idle.pretend_idle()
		_idle.think_now()
		await _until(func() -> bool: return _idle.phase_name() == IdleBrain.PHASE_PLAYING, 240)
		_reset_log()
		# A meter deep enough that the goose cannot knock him out inside the window: a knockout
		# stands him down, rightly, and is not what this asks about.
		var meter := _buddy.health.max_damage
		_buddy.health.max_damage = 1.0e9
		var ok := true
		for f in 240:
			await get_tree().physics_frame
			if f % 60 == 59:
				_idle.think_now()
			if _idle.phase_name() == IdleBrain.PHASE_WATCHING:
				ok = false
				break
		_buddy.health.max_damage = meter
		_buddy.health.reset_meter()
		var landed_on_him := _hits_from(id).size()
		_check("with a %s on the desk hitting him (%d hits in 4 s) he carries on playing (phase '%s')"
			% [id, landed_on_him, _idle.phase_name()], ok and landed_on_him > 0)
		_idle._disturb()
	_clear_desk()
	_end()

func _longest_reach_turret() -> StringName:
	var best: StringName = &""
	var best_rate := 0.0
	for item in ItemDB.all_items():
		if item.category != ItemData.CATEGORY_TURRET or item.scene == null:
			continue
		var turret := item.scene.instantiate() as TurretBase
		if turret == null:
			continue
		# Reaches him from the far side of the desk, and fires often enough to be seen doing it.
		var rate := (1.0 / maxf(turret.fire_interval, 0.05)) if turret.max_range >= 600.0 else 0.0
		if rate > best_rate:
			best_rate = rate
			best = item.id
		turret.free()
	return best

## Climbing, walls, shelves, a toy binned under him and a toy off the edge of the window.
func _idle_geometry() -> void:
	_begin("idle brain — geometry")
	await _stage("geometry", true)
	_focus(Settings.Intensity.NORMAL)
	_check("standing on the floor he is grounded", _buddy.is_grounded())
	_buddy.apply_central_impulse(Vector2(0.0, -_buddy.mass * 400.0))
	await _frames(5)
	_check("five frames into a hop he is not", not _buddy.is_grounded())
	await _frames(60)

	# A step: a beanbag on a block 40 px high. Walking has to stop working before he climbs.
	for height in [40.0, 300.0]:
		_clear_desk()
		await _frames(3)
		# The step is a box on the desk; the shelf floats, with nothing under it to stand on.
		var ledge := _block(Vector2(300.0, FLOOR_Y - height * 0.5), Vector2(180.0, height)) \
			if height < 100.0 else _block(Vector2(300.0, FLOOR_Y - height), Vector2(180.0, 24.0))
		var bag := await _spawn_toy(&"beanbag", 300.0)
		if is_instance_valid(bag):
			bag.global_position = Vector2(300.0, FLOOR_Y - height - 12.0 - 40.0)
		_place(Vector2(560.0, HOME.y))
		await _frames(40)
		_reset_log()
		_ends.clear()
		_idle.pretend_idle()
		_idle.think_now()
		var launches := 0
		var rising := false
		var outcome := ""
		# Thought at the brain's own cadence here: the stall is counted in thinks and the climb
		# interval in physics seconds, so thinking faster than the game does would give up on a
		# step before it had been allowed its climbs.
		for f in 900:
			await get_tree().physics_frame
			_see()
			if f % 120 == 119:
				_idle.think_now()
			var up := _buddy.linear_velocity.y < -150.0
			if up and not rising:
				launches += 1
			rising = up
			if _idle.phase_name() == IdleBrain.PHASE_PLAYING and is_instance_valid(bag) \
					and bag in _buddy.get_colliding_bodies():
				outcome = "reached"
				break
			if not _ends.is_empty():
				outcome = String(_ends.back())
				break
		var world_hits := _hits.size()
		_measure("beanbag on a %.0f px ledge: %s after %d launches, %d hits %s" % [height,
			outcome if outcome != "" else "still trying", launches, world_hits,
			_list(_hits.map(func(h: HitInfo) -> String: return "%s@%.0f" % [h.source_id, h.raw_impulse]))])
		if height < 100.0:
			_check("a toy on a %.0f px step is reached (%s, %d launches)" % [height, outcome, launches],
				outcome == "reached" and launches <= IdleBrain.MAX_CLIMBS_PER_TRIP)
		else:
			_check("a toy on a %.0f px shelf is given up on (%s) after at most %d launches (%d)"
				% [height, outcome, IdleBrain.MAX_CLIMBS_PER_TRIP, launches],
				outcome == "stalled" and launches <= IdleBrain.MAX_CLIMBS_PER_TRIP)
			_check("and giving up shows (beat 'gave_up' seen)", _seen_now(&"gave_up"))
			_mark(&"gave_up", _seen_now(&"gave_up"))
			var cool := int(_idle._cooldowns.get(bag.get_instance_id(), 0)) - Time.get_ticks_msec() \
				if is_instance_valid(bag) else 0
			_check("and he leaves it alone for a while (%.0f s)" % (cool / 1000.0), cool > 30000)
		_check("climbing costs him nothing (%d hits)" % world_hits, world_hits == 0)
		_idle._disturb()
		ledge.queue_free()
		await _frames(30)

	# Binned while he walks to it, and binned from under him while he sits in it — the second is
	# the one that matters: the toy flushes what it owes him on its way out.
	for while_playing in [false, true]:
		_clear_desk()
		await _frames(3)
		var gone := await _spawn_toy(&"beanbag", 300.0)
		_place(Vector2(700.0 if not while_playing else 520.0, HOME.y))
		await _frames(20)
		_ends.clear()
		_idle.pretend_idle()
		_idle.think_now()
		if while_playing:
			await _until(func() -> bool: return _idle.phase_name() == IdleBrain.PHASE_PLAYING, 240)
			await _frames(40)
		else:
			await _frames(20)
		_seen_real.erase(&"toy_gone")
		if is_instance_valid(gone):
			gone.bin_myself()
		await _frames(3)
		var what := "sits in" if while_playing else "walks to"
		_check("a toy binned while he %s it ends the routine (phase '%s', reason %s)"
			% [what, _idle.phase_name(), _list(_ends)],
			_idle.phase_name() == IdleBrain.PHASE_WANDERING and _ends.has(&"toy_gone"))
		_check("and he is surprised, whatever it paid him on its way out (beat 'toy_gone' seen)",
			_seen_now(&"toy_gone"))
		_mark(&"toy_gone", _seen_now(&"toy_gone"))
		_check("and his target is cleared", _idle.target_id() == &"")
		_idle._disturb()

	# The window shrinks under a toy: the walls follow and bring it back where he can reach it.
	_clear_desk()
	await _frames(3)
	var far := await _spawn_toy(&"beanbag", 1150.0)
	_place(Vector2(400.0, HOME.y))
	_view.size = Vector2i(900, 720)
	await _frames(40)
	var inside := is_instance_valid(far) and far.global_position.x < 900.0
	_check("shrinking the window brings a toy outside it back in (x %.0f)"
		% (far.global_position.x if is_instance_valid(far) else -1.0), inside)
	_idle.pretend_idle()
	_idle.think_now()
	var reached := await _until(func() -> bool: return _idle.phase_name() == IdleBrain.PHASE_PLAYING, 360)
	_check("and he walks to it where it now is", reached)
	_idle._disturb()
	_view.size = VIEW_SIZE
	await _frames(20)

	# A toy that is off the edge of the window with nothing to bring it back.
	_clear_desk()
	await _frames(3)
	var lost := await _spawn_toy(&"beanbag", 200.0)
	_place(Vector2(700.0, HOME.y))
	await _frames(10)
	if is_instance_valid(lost):
		lost.freeze = true
		lost.global_position = Vector2(-600.0, HOME.y)
	await _frames(2)
	_idle.pretend_idle()
	_idle.think_now()
	# Asserted since D70 (AI audit F): the brain asks its walls where the desk is, not the
	# window, so loop_check's hand-built desk out past a 64x64 root is still a desk.
	var chases := _idle.target_id() == &"beanbag"
	_measure("a toy off the edge of the window: he %s it (phase '%s')" % [
		"sets off for" if chases else "ignores", _idle.phase_name()])
	_check("a toy outside the walls is not somewhere to go (phase '%s')" % _idle.phase_name(),
		not chases)
	# And the same toy back on the desk is: the filter is the walls, not the toy.
	if is_instance_valid(lost):
		lost.global_position = Vector2(420.0, HOME.y)
		lost.freeze = false
	await _frames(20)
	_idle.pretend_idle()
	_idle.think_now()
	_check("and back inside them it is again", _idle.target_id() == &"beanbag")
	_idle._disturb()
	_clear_desk()
	_end()

func _block(centre: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Block"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	body.position = centre
	_world.add_child(body)
	return body

## At Off he skips the walk and is "simply already there" (D21). What that earns, per kind
## of routine, is measured here rather than assumed.
func _idle_focus_off() -> void:
	_begin("idle brain — Focus Off")
	await _stage("idle focus off", true)
	# Every toy he has a routine for, not three (D70): Off is the promise that a player in a
	# meeting can stop the desk moving without giving up the income (D21), and the audit found 26
	# of 33 routine toys earning nothing at Off — every one that pays only for touch.
	var toys := _routine_toys()
	if not _toys.is_empty():
		var picked: Array[Array] = []
		for entry in toys:
			if _toys.has(String(entry[0])):
				picked.append(entry)
		toys = picked
	var earning := 0
	var counted := 0
	var silent: Array[String] = []
	for entry in toys:
		var id: StringName = entry[0]
		_idle._disturb()
		_clear_desk()
		await _frames(3)
		_focus(Settings.Intensity.NORMAL)
		_buddy.grime.set_value(0.8 if int(entry[1]) == IdleBrain.ROUTINE_SCRUB else 0.0)
		Economy.grime = _buddy.grime.value
		var toy := await _spawn_toy(id, 300.0)
		# Six hundred px off: at Off he does not walk, and nothing about "there" may depend on
		# being near it — a jack he wound himself laughed only within earshot.
		_place(Vector2(900.0, HOME.y))
		await _frames(20)
		if not is_instance_valid(toy):
			_check("'%s' survives being put down" % id, false)
			continue
		_focus(Settings.Intensity.OFF)
		# Asked now: food is eaten, and a toy that is gone cannot be asked anything.
		var pays_hearts := toy is FriendlyBase or toy.has_method(&"idle_use") \
			or _idle._brain_pays(int(entry[1]))
		var at := _buddy.global_position
		# A fortune ball's yes is a coin toss: seeded, so the verdict is not one.
		seed(hash(String(id)))
		var paid_before := _idle.paid_value
		_reset_log()
		_idle.pretend_idle()
		_idle.think_now()
		var chose := _idle.target_id() == id
		var skipped := _idle.phase_name() == IdleBrain.PHASE_PLAYING
		for f in 90:
			await get_tree().physics_frame
			if f % 30 == 29:
				_idle.think_now()
		var moved := _buddy.global_position.distance_to(at)
		var brain_paid := _idle.paid_value - paid_before
		var toy_paid := maxf(_value_from(_sustained, id) - brain_paid, 0.0) + _value_from(_given, id)
		# A toy that pays in lumps — a wound jack's laugh, the ball's yes — gets the rest of the dwell.
		var thinks := 3
		while pays_hearts and brain_paid <= 0.0 and toy_paid <= 0.0 and thinks < 12 \
				and _idle.phase_name() == IdleBrain.PHASE_PLAYING:
			# A second between thinks, not half of one: the jack laughs 0.55 s after it pops, and a
			# think sooner than that shuts the lid on the laugh.
			for f in 60:
				await get_tree().physics_frame
			_idle.think_now()
			thinks += 1
			brain_paid = _idle.paid_value - paid_before
			toy_paid = maxf(_value_from(_sustained, id) - brain_paid, 0.0) + _value_from(_given, id)
		# The jack laughs a beat after it pops, and a trickle is flushed half a second after that.
		if pays_hearts and brain_paid <= 0.0 and toy_paid <= 0.0:
			await _frames(75)
			toy_paid = maxf(_value_from(_sustained, id) - brain_paid, 0.0) + _value_from(_given, id)
		moved = maxf(moved, _buddy.global_position.distance_to(at))
		var routine := int(entry[1])
		_measure("%s at Off: skipped the walk %s, moved %.1f px, brain paid %.2f, toy paid %.2f over %d thinks"
			% [id, skipped, moved, brain_paid, toy_paid, thinks])
		_check("at Off he does not walk to the %s (moved %.1f px)" % [id, moved], chose and skipped and moved < 3.0)
		# A weapon-side ball is played with for its own sake at any Focus: his own play mints no
		# Bones (D70) and it has no Hearts to pay.
		if not pays_hearts:
			_note("at Off, as at any Focus, a %s is played with for its own sake" % id)
			continue
		counted += 1
		if brain_paid > 0.0 or toy_paid > 0.0:
			earning += 1
		else:
			silent.append("%s (%s)" % [id, ROUTINE_NAMES.get(routine, "?")])
	_measure("at Off, %d of %d routine toys that pay Hearts earned within a dwell%s" % [earning,
		counted, "" if silent.is_empty() else "; silent: " + _list(silent)])
	_check("at Off every routine toy that pays Hearts still earns (%d of %d%s)" % [earning, counted,
		"" if silent.is_empty() else "; silent: " + _list(silent)], silent.is_empty() and counted > 0)
	_idle._disturb()
	_clear_desk()
	_focus(Settings.Intensity.NORMAL)
	_end()

# =====================================================================================
# C — Movement and body
# =====================================================================================

## Walking pace and facing, measured over a long walk on a flat desk.
func _movement_travel() -> void:
	_begin("movement — walking")
	await _stage("walking", true)
	_focus(Settings.Intensity.NORMAL)
	for side in [-1.0, 1.0]:
		_idle._disturb()
		_clear_desk()
		await _frames(3)
		var start_x := 1180.0 if side < 0.0 else 100.0
		var toy_x := 120.0 if side < 0.0 else 1160.0
		await _spawn_toy(&"beanbag", toy_x)
		_place(Vector2(start_x, HOME.y))
		await _frames(20)
		_idle.pretend_idle()
		_idle.think_now()
		var speeds: Array[float] = []
		var faced := true
		var effort := 0.0
		for f in 240:
			await get_tree().physics_frame
			if f % 120 == 119:
				_idle.think_now()
			if _idle.phase_name() != IdleBrain.PHASE_TRAVELLING:
				break
			if f >= 30:
				speeds.append(_buddy.linear_velocity.x * side)
				faced = faced and signf(_art._facing) == side and _art.body.flip_h == (side < 0.0)
				effort = maxf(effort, _art._travel)
		var mean := 0.0
		for v in speeds:
			mean += v
		mean /= maxf(1.0, float(speeds.size()))
		var want := _idle._walk_speed()
		_measure("walking %s: %.1f px/s over %d frames (derived %.1f px/s), bob effort peaked at %.2f"
			% ["left" if side < 0.0 else "right", mean, speeds.size(), want, effort])
		_check("he cruises at the derived walking speed walking %s (%.1f of %.1f px/s)"
			% ["left" if side < 0.0 else "right", mean, want], absf(mean - want) < want * 0.15)
		_check("and faces the way he walks, the whole way", faced and speeds.size() > 60)
		# Read between physics ticks, after a frame of its own decay: 0.9 is full effort.
		_check("and the bob is driven at full effort once he is up to speed (%.2f)" % effort, effort > 0.8)
		_idle._disturb()
		await _frames(3)
		_check("standing down stops the stride", is_zero_approx(_art._travel))
	_clear_desk()
	_end()

## Landing, being shaken, falling out of the world, and how long a reaction holds him.
func _movement_body() -> void:
	_begin("movement — landing, shaking, rescue, reactions")
	await _stage("body", false)
	_focus(Settings.Intensity.NORMAL)
	for drop in [200.0, 20.0]:
		_place(Vector2(HOME.x, FLOOR_Y - FEET - drop))
		_landings.clear()
		_brain.clear()
		var seen_before := _seen_real.has(&"landed")
		_seen_real.erase(&"landed")
		# Off the floor first: `is_grounded` is last tick's contacts until a tick has run.
		await _frames(4)
		await _until(func() -> bool: return _buddy.is_grounded() and _buddy.linear_velocity.length() < 5.0, 120)
		await _frames(10)
		var want := sqrt(2.0 * 980.0 * drop)
		if drop > 100.0:
			var speed: float = _landings[0][1] if not _landings.is_empty() else 0.0
			_measure("a %.0f px drop lands at %.0f px/s (free fall %.0f)" % [drop, speed, want])
			_check("a %.0f px drop is one landing on the bus (%d)" % [drop, _landings.size()], _landings.size() == 1)
			_check("at the speed he fell (%.0f of %.0f px/s)" % [speed, want], absf(speed - want) < want * 0.15)
			_check("at his feet (y %.0f, floor %.0f)" % [_landings[0][0].y if not _landings.is_empty() else -1.0, FLOOR_Y],
				not _landings.is_empty() and absf(float(_landings[0][0].y) - FLOOR_Y) < 8.0)
			_check("and he squashes (beat 'landed' seen)", _seen_real.has(&"landed"))
		else:
			_check("a %.0f px step down is no landing (%d)" % [drop, _landings.size()], _landings.is_empty())
		if seen_before:
			_seen_real[&"landed"] = true
	_prove(&"buddy_landed")

	# Shaken only while held, and only when it is fast.
	_brain.clear()
	_buddy.linear_velocity = Vector2(1200, 0)
	await _frames(2)
	_check("flung while nobody holds him is not being shaken", _brain.beat_id() != &"shaken")
	await _frames(30)
	_place(HOME)
	await _frames(20)
	await _grab()
	_brain.clear()
	_buddy.linear_velocity = Vector2(400, 0)
	await _frames(2)
	_check("held and moved gently is not being shaken", _brain.beat_id() != &"shaken")
	_buddy.linear_velocity = Vector2(1200, 0)
	await _frames(2)
	_check("held and flung is (beat '%s')" % _brain.beat_id(), _brain.beat_id() == &"shaken")
	await _release()
	await _frames(40)

	# Out of the world: rescued the frame he is further out than the margin, and not before.
	_place(Vector2(-300.0, 300.0))
	await _frames(2)
	_check("300 px past the left wall he is left alone (x %.0f)" % _buddy.global_position.x,
		_buddy.global_position.x < -100.0)
	var fell := Time.get_ticks_msec()
	var rescued := await _until(func() -> bool: return _buddy.global_position.x > 0.0, 240)
	_measure("falling off the desk past the wall, he is rescued after %.2f s"
		% (float(Time.get_ticks_msec() - fell) / 1000.0))
	_check("falling out of the world he is brought home (%s)" % _buddy.global_position, rescued)
	_check("stopped and upright", _buddy.linear_velocity.length() < 1.0 and is_zero_approx(_buddy.rotation))
	_place(Vector2(-1500.0, 300.0))
	await _frames(2)
	_check("teleported far outside, he is home the next frame (%s)" % _buddy.global_position,
		Rect2(Vector2.ZERO, Vector2(VIEW_SIZE)).has_point(_buddy.global_position))
	await _frames(60)

	# How long a reaction holds him: the tag's own length, not a fixed 0.45 s.
	for pair in [[&"hurt", BAT], [&"happy", &"open_hand"]]:
		var state: StringName = pair[0]
		await _until(func() -> bool: return _buddy.state == &"idle", 90)
		_states.clear()
		var t := Time.get_ticks_usec()
		if state == &"hurt":
			_buddy.take_impulse(6000.0, BAT, 1.0, _buddy.global_position)
		else:
			EventBus.kindness_given.emit(&"open_hand", 1.0, _buddy.global_position)
		await _until(func() -> bool: return _buddy.state == state, 6)
		var entered := Time.get_ticks_usec()
		await _until(func() -> bool: return _buddy.state == &"idle", 120)
		var held := float(Time.get_ticks_usec() - entered) / 1.0e6
		var want := _art.animation_length(state)
		_measure("'%s' holds him %.2f s; its tag is %.2f s" % [state, held, want])
		# Read off his state a frame at a time, so a frame or two late under load; the fixed
		# 0.45 s this replaced would be a tenth of a second off the hurt tag either way.
		_check("'%s' holds him for its tag's length (%.2f of %.2f s)" % [state, held, want],
			want > 0.0 and held > want - 0.03 and held < want + 0.09)
	_check("a state with no tag falls back to %.2f s" % Buddy.REACTION_FALLBACK_SECONDS,
		is_equal_approx(_buddy._reaction_seconds(&"no_such_state"), Buddy.REACTION_FALLBACK_SECONDS))
	_buddy.health.reset_meter()
	_end()

## The round's climax: collapse, pile, reassemble, in order, paid once, with his hands off.
func _movement_knockout() -> void:
	_begin("movement — the knockout beat")
	await _stage("knockout", true)
	_focus(Settings.Intensity.NORMAL)
	_buddy.health.reset_meter()
	_reset_log()
	var bones := Economy.balance_of(Economy.BONES)
	# The meter past 80% slumps him before it goes. A hit is capped at half a round.
	await _hit(34000.0, BAT)
	await _hit(13000.0, BAT)
	_check("a meter past 80%% slumps his idle (%.0f%%, bias '%s')" % [_buddy.health.fill_fraction() * 100.0,
		_art.posture_bias], _art.posture_bias == &"idle_sad")
	_prove(&"damaged")
	await _hit(34000.0, BAT)
	var down_at := Time.get_ticks_usec()
	_check("filling the meter knocks him out", _buddy.health.down and _buddy.state == &"knockout")
	# Inside the beat: no drag, no damage, nothing below BEAT.
	await _until(func() -> bool: return _buddy.state == &"pile", 60)
	var grabbed: bool = await _grab()
	_check("he cannot be picked up in the pile", not grabbed and not _buddy.dragging)
	var hits := _hits.size()
	_buddy.take_impulse(20000.0, BAT, 1.0, _buddy.global_position)
	await _frames(2)
	_check("and takes no damage while down", _hits.size() == hits)
	_check("and nothing below the beat plays over it", not _brain.react(&"hit_heavy") and not _brain.react(&"pet"))
	await _hover(false)
	await _until(func() -> bool: return _buddy.state == &"idle", 240)
	var total := float(Time.get_ticks_usec() - down_at) / 1.0e6
	var sequence: Array[StringName] = []
	var stamps: Array[int] = []
	for entry in _states:
		if entry[0] in [&"knockout", &"pile", &"reassemble", &"idle"] and (sequence.is_empty() or sequence.back() != entry[0]):
			sequence.append(entry[0])
			stamps.append(entry[1])
	var tail := sequence.slice(sequence.find(&"knockout"))
	_check("the beat runs knockout, pile, reassemble, idle (%s)" % _list(tail),
		_list(tail) == _list([&"knockout", &"pile", &"reassemble", &"idle"]))
	var i := sequence.find(&"knockout")
	if i >= 0 and i + 3 < stamps.size():
		var b := ItemDB.balance
		var collapse := float(stamps[i + 1] - stamps[i]) / 1.0e6
		var pile := float(stamps[i + 2] - stamps[i + 1]) / 1.0e6
		var rebuild := float(stamps[i + 3] - stamps[i + 2]) / 1.0e6
		_measure("collapse %.2f s (tag %.2f), pile %.2f s (downtime %.2f), reassemble %.2f s (tag %.2f); %.2f s in all"
			% [collapse, _buddy._beat_time(&"collapse", b.knockout_collapse_time), pile, b.knockout_downtime,
			rebuild, _buddy._beat_time(&"reassemble", b.knockout_reassemble_time), total])
		_check("each phase lasts what the art says it lasts",
			absf(collapse - _buddy._beat_time(&"collapse", b.knockout_collapse_time)) < 0.07
			and absf(pile - b.knockout_downtime) < 0.07
			and absf(rebuild - _buddy._beat_time(&"reassemble", b.knockout_reassemble_time)) < 0.07)
	_check("the knockout pays once (%d)" % _knockouts.size(), _knockouts.size() == 1)
	_check("and the Bones arrive (+%.0f)" % (Economy.balance_of(Economy.BONES) - bones),
		Economy.balance_of(Economy.BONES) > bones)
	_check("he gets up with an empty meter, unfrozen and upright", _buddy.health.damage == 0.0
		and not _buddy.health.down and not _buddy.freeze and is_zero_approx(_buddy.global_rotation))
	await _frames(2)
	_check("shakes it off (beat 'meter_reset' seen)", _seen_now(&"meter_reset"))
	_mark(&"meter_reset", _seen_now(&"meter_reset"))
	_prove(&"buddy_state_changed")
	_check("and the reset lifts the slump", _art.posture_bias == &"")
	_prove(&"meter_reset")
	_check("the idle brain stood down for it", _idle.phase_name() == IdleBrain.PHASE_WATCHING)
	_end()

# =====================================================================================
# D — Mood and grime
# =====================================================================================

## Every band edge in `BuddyArt`'s tables, both sides of it; the trough posture; decay.
func _mood_bands_and_decay() -> void:
	_begin("mood — bands, posture, decay")
	await _stage("mood", false)
	_focus(Settings.Intensity.NORMAL)
	var wrong: Array[String] = []
	var edges: Array[float] = []
	for t in BuddyArt.MOOD_FACES:
		edges.append(float(t[0]))
	for t in BuddyArt.MOOD_IDLES:
		edges.append(float(t[0]))
	for edge in edges:
		for m in [edge - 1.0, edge + 1.0]:
			if m < -100.0 or m > 100.0:
				continue
			_buddy.mood.set_value(m)
			_brain.clear()
			await _frames(1)
			var face := _mood_face(m)
			var idle := _mood_idle(m)
			if _art.face.animation != face or _art.body.animation != idle:
				wrong.append("%.0f: '%s'/'%s' not '%s'/'%s'" % [m, _art.face.animation, _art.body.animation, face, idle])
	_check("every mood band edge, both sides, wears its face and idle (%s)" % _list(wrong), wrong.is_empty())
	_buddy.mood.set_value(0.0)
	await _frames(1)
	_check("in the trough he slows and slouches (speed %.2f, lean %.1f deg)" % [_art.body.speed_scale,
		rad_to_deg(_art.body.rotation)], is_equal_approx(_art.body.speed_scale, ExpressionBrain.TROUGH_SPEED)
		and not is_zero_approx(_art.body.rotation))
	_buddy.mood.set_value(50.0)
	await _frames(1)
	_check("out of it he stands up", is_equal_approx(_art.body.speed_scale, 1.0) and is_zero_approx(_art.body.rotation))
	_prove(&"mood_changed")
	_buddy.mood.set_value(0.0)
	_focus(Settings.Intensity.OFF)
	_check("at Off the trough posture is off", is_equal_approx(_art.body.speed_scale, 1.0)
		and is_zero_approx(_art.body.rotation))
	_focus(Settings.Intensity.NORMAL)
	_check("and back at Normal it returns", is_equal_approx(_art.body.speed_scale, ExpressionBrain.TROUGH_SPEED))
	_prove(&"focus_mode_changed")
	# Decay, in real time on his own `_process`.
	for start in [60.0, -60.0]:
		_buddy.mood.set_value(start)
		var t := Time.get_ticks_usec()
		await _frames(120)
		var dt := float(Time.get_ticks_usec() - t) / 1.0e6
		var rate := absf(start - _buddy.mood.value) / dt
		_measure("mood decays from %.0f at %.2f/s (balance %.2f/s)" % [start, rate, ItemDB.balance.mood_decay])
		_check("mood decays toward zero from %.0f at the balance rate (%.2f/s)" % [start, rate],
			absf(rate - ItemDB.balance.mood_decay) < ItemDB.balance.mood_decay * 0.1)
	_buddy.mood.set_value(0.5)
	await _frames(30)
	_check("and stops at zero rather than crossing it (%.3f)" % _buddy.mood.value, _buddy.mood.value == 0.0)
	_check("with Economy told the truth at zero (%.3f)" % Economy.mood, Economy.mood == 0.0)
	_end()

## What a hit and a pet pay at every mood, against the multipliers read before the event.
func _mood_payouts() -> void:
	_begin("mood — the payout it applies")
	await _stage("mood payouts", false)
	_focus(Settings.Intensity.NORMAL)
	var mults: Array[String] = []
	var worst := INF
	var worst_at := 0.0
	var bad: Array[String] = []
	for m in [-100.0, -60.0, -25.0, 0.0, 25.0, 60.0, 100.0]:
		await _settle_hit()
		_buddy.mood.set_value(m)
		_buddy.grime.set_value(0.0)
		Economy.grime = 0.0
		# Read before emitting: Economy pays at the mood in force when the event fired, and the
		# mood component moves it a moment later (CLAUDE.md).
		var mood_mult := Economy.mood_multiplier()
		var grime_mult := Economy.grime_multiplier()
		# 6,000 of impulse through `take_impulse` at a multiplier of 1 is 60 damage.
		var want := Economy.payout_for(60.0 * ItemDB.balance.bones_per_damage * grime_mult, MACE)
		var before := Economy.balance_of(Economy.BONES)
		await _hit(6000.0, MACE)
		var got := Economy.balance_of(Economy.BONES) - before
		if absf(got - want) > maxf(want * 1e-4, 1e-6):
			bad.append("%.0f: got %.3f want %.3f" % [m, got, want])
		mults.append("%.0f → x%.2f" % [m, mood_mult])
		if mood_mult < worst:
			worst = mood_mult
			worst_at = m
		var after := _buddy.mood.value
		if not (after < m or m <= -100.0):
			bad.append("%.0f: a hit did not lower his mood (%.1f)" % [m, after])
	_measure("mood multiplier (%s curve): %s" % [Economy.personality, ", ".join(mults)])
	_check("a hit pays exactly the mood multiplier in force when it landed (%s)" % _list(bad), bad.is_empty())
	_check("neutral is the worst place to be (worst x%.2f at %.0f)" % [worst, worst_at], absf(worst_at) < 30.0)
	# Kindness on the same curve.
	await _settle_hit()
	_buddy.mood.set_value(80.0)
	var mood_mult := Economy.mood_multiplier()
	Economy._combo_deadline_msec = 0
	var hearts := Economy.balance_of(Economy.HEARTS)
	EventBus.kindness_given.emit(&"open_hand", 1.0, _buddy.global_position)
	var got := Economy.balance_of(Economy.HEARTS) - hearts
	var combo := EconomyMath.kindness_combo(0, ItemDB.balance.kindness_combo_step, ItemDB.balance.kindness_combo_max)
	var want := 1.0 * ItemDB.balance.hearts_per_kindness * combo * mood_mult \
		* Progression.get_modifier(&"open_hand", &"payout_mult") * Progression.mastery_multiplier(&"open_hand") \
		* Economy.marrow_multiplier() * Economy.temp_multiplier() * Milestones.income_multiplier()
	_check("a pet at mood 80 pays at x%.2f (%.3f of %.3f Hearts)" % [mood_mult, got, want], absf(got - want) < maxf(want * 1e-3, 1e-6))
	_check("and lifts his mood", _buddy.mood.value > 80.0 - 0.1)
	_end()

## Dirt: gathered by damage, drawn as patches on him and never on his face, charged against
## Bones, and scrubbed off by a real sponge for Hearts.
func _grime() -> void:
	_begin("grime — patches, penalty, cleaning")
	await _stage("grime", false)
	_focus(Settings.Intensity.NORMAL)
	_buddy.grime.set_value(0.0)
	Economy.grime = 0.0
	var n := _hits.size()
	await _hit(6000.0, MACE)
	var amount: float = _hits[n].amount if _hits.size() > n else 0.0
	_check("a hit dirties him by grime_per_damage (%.4f of %.4f)" % [_buddy.grime.value,
		amount * ItemDB.balance.grime_per_damage],
		is_equal_approx(_buddy.grime.value, amount * ItemDB.balance.grime_per_damage))
	_buddy.grime.set_value(0.6)
	var body_mat := EffectsPlayer.material_for(_art.body)
	var face_mat := EffectsPlayer.material_for(_art.face)
	_check("the patches are drawn at the grime level (%.2f)" % float(body_mat.get_shader_parameter(&"grime")),
		is_equal_approx(float(body_mat.get_shader_parameter(&"grime")), 0.6))
	var face_grime: Variant = face_mat.get_shader_parameter(&"grime")
	_check("and never on his face (D46: %s)" % str(face_grime), face_grime == null or is_zero_approx(float(face_grime)))
	_check("in frame-local cells, so they do not crawl (cell %.0f)" % float(body_mat.get_shader_parameter(&"grime_cell")),
		float(body_mat.get_shader_parameter(&"grime_cell")) > 0.0)
	# The Bones penalty, read before each hit.
	var paid := {}
	for g in [0.0, 1.0]:
		await _settle_hit()
		_buddy.mood.set_value(50.0)
		_buddy.grime.set_value(g + 0.01)
		_buddy.grime.set_value(g)
		var before := Economy.balance_of(Economy.BONES)
		var mood_mult := Economy.mood_multiplier()
		await _hit(6000.0, MACE)
		paid[g] = (Economy.balance_of(Economy.BONES) - before) / maxf(mood_mult, 1e-9)
	var ratio: float = float(paid[1.0]) / maxf(float(paid[0.0]), 1e-9)
	_measure("a filthy skeleton earns x%.3f of a clean one's Bones" % ratio)
	_check("filthy, he earns %.2f of a clean hit (penalty %.2f)" % [ratio, ItemDB.balance.grime_max_penalty],
		absf(ratio - (1.0 - ItemDB.balance.grime_max_penalty)) < 0.01)
	# The grime-past-half slump, in the neutral band where posture shows.
	await _settle_hit()
	_buddy.mood.set_value(10.0)
	_buddy.grime.set_value(0.7)
	await _frames(1)
	_check("filthy past half he slumps (bias '%s', idle '%s')" % [_art.posture_bias, _art.body.animation],
		_art.posture_bias == &"idle_sad" and _art.body.animation == &"idle_sad")
	# A real sponge, laid against him.
	Progression._unlock(&"sponge")
	_buddy.grime.set_value(0.6)
	var hearts := Economy.balance_of(Economy.HEARTS)
	_reset_log()
	# On the desk against his side, the way a player leaves one: it rests on him and stays.
	EventBus.spawn_requested.emit(&"sponge", Vector2(_buddy.global_position.x - 60.0, FLOOR_Y - 30.0))
	var sponge := _last_spawned(&"sponge") as BaseDraggable
	if sponge:
		var half := sponge.get_interaction_rect().size * 0.5
		sponge.global_position = Vector2(_buddy.get_interaction_rect().position.x - half.x + 1.0,
			FLOOR_Y - half.y - 1.0)
	var t := Time.get_ticks_usec()
	var clean := await _until(func() -> bool: return _buddy.grime.value <= 0.0, 180)
	var secs := float(Time.get_ticks_usec() - t) / 1.0e6
	var cleaned_value := _value_from(_sustained, &"sponge")
	_measure("a sponge laid on him took 0.60 grime off in %.2f s (rate %.2f/s) and paid %.2f kindness"
		% [secs, ItemDB.balance.sponge_clean_rate, cleaned_value])
	_check("a sponge touching him cleans him (%.2f left)" % _buddy.grime.value, clean)
	_check("and pays Hearts for what came off (+%.1f)" % (Economy.balance_of(Economy.HEARTS) - hearts),
		Economy.balance_of(Economy.HEARTS) > hearts)
	_check("at hearts_per_grime_cleaned per unit (%.2f of %.2f)" % [cleaned_value,
		0.6 * ItemDB.balance.hearts_per_grime_cleaned], absf(cleaned_value
		- 0.6 * ItemDB.balance.hearts_per_grime_cleaned) < 0.6 * ItemDB.balance.hearts_per_grime_cleaned * 0.25)
	await _frames(2)
	_check("coming clean sparkles (beat 'sparkling' seen)", _seen_now(&"sparkling"))
	_check("and lifts the slump", _art.posture_bias == &"")
	_clear_desk()
	_end()

# =====================================================================================
# E — Personalities
# =====================================================================================

## Every personality, read off ItemDB: each tell shows, and none of them touches a number.
func _personalities() -> void:
	_begin("personalities — tells on the surface, numbers untouched")
	await _stage("personalities", false)
	_focus(Settings.Intensity.NORMAL)
	Progression._unlock(MACE)
	var amounts := {}
	var bone_rates := {}
	var mood_deltas := {}
	var grime_deltas := {}
	var heart_rates := {}
	for p in ItemDB.all_personalities():
		Economy.personality = String(p.id)
		# The real reroll path: a Reincarnation re-reads who he is.
		EventBus.prestige_performed.emit(0.0)
		var took := _brain._personality == p
		await _settle_hit()
		var problems: Array[String] = []
		if not took:
			problems.append("the reroll did not load it")
		# The hurt face, from a real bat — the generic shocked face is exactly what the tell replaces.
		_buddy.mood.set_value(40.0)
		await _hit(6000.0, BAT)
		var hurt: StringName = p.face_swaps.get(p.hurt_face, p.hurt_face) if p.hurt_face != &"" else &"shocked"
		if _art.face.animation != hurt:
			problems.append("a bat hit shows '%s', not his '%s'" % [_art.face.animation, hurt])
		await _settle_hit()
		await _hit(10000.0, BAT)
		if _art.face.animation != hurt:
			problems.append("a heavy hit shows '%s', not '%s'" % [_art.face.animation, hurt])
		await _settle_hit()
		# The celebration face.
		_brain.react(&"purchase")
		var joy: StringName = p.face_swaps.get(p.celebration_face, p.celebration_face)
		if _art.face.animation != joy:
			problems.append("a purchase shows '%s', not '%s'" % [_art.face.animation, joy])
		_brain.clear()
		# Swaps apply to every face he pulls.
		for key in p.face_swaps:
			_art.set_expression(key)
			if _art.face.animation != p.face_swaps[key]:
				problems.append("'%s' is not swapped to '%s'" % [key, p.face_swaps[key]])
		# Amplitude, measured: the peak of a pet's hop.
		_brain.react(&"pet", 0.5)
		var peak := 0.0
		for i in 20:
			await get_tree().physics_frame
			peak = maxf(peak, -_art._hop_y)
		_brain.clear()
		var hop_per_amp := peak / maxf(p.reaction_amplitude, 0.01)
		# Fidget period.
		_brain._arousal = 0.0
		_brain._schedule_fidget()
		var period := float(_brain._fidget_at - _brain._now()) / 1000.0
		var want_period := p.fidget_period * (0.5 if _brain._in_trough else 1.0)
		if p.fidget_period > 0.0 and absf(period - want_period) > 0.05:
			problems.append("fidgets every %.1f s, not %.1f" % [period, want_period])
		# The early flinch.
		_brain.clear()
		EventBus.threat_changed.emit(&"windup", _buddy.global_position + Vector2(120, 0), 1.0)
		var flinched := _brain.beat_id() == &"hit_light"
		if flinched != p.flinches_early:
			problems.append("a wind-up %s" % ("made him flinch" if flinched else "did not make him flinch"))
		EventBus.threat_changed.emit(&"windup", _buddy.global_position + Vector2(120, 0), 0.0)
		await _settle_hit()
		# A fuse lit beside him is watched to the end, flinch or no flinch (D70). The Nervous
		# one's early flinch took the slot and the fuse's lean, asked for under it, was never worn.
		EventBus.threat_changed.emit(&"fuse", _buddy.global_position + Vector2(120, 0), 1.0)
		await _advance_brain(1000)
		if _brain.beat_id() != &"fuse_lit":
			problems.append("a fuse lit beside him, a second on, he wore '%s' and not its lean"
				% _brain.beat_id())
		EventBus.threat_changed.emit(&"fuse", _buddy.global_position + Vector2(120, 0), 0.0)
		await _advance_brain(1000)
		if _brain.beat_id() == &"fuse_lit":
			problems.append("and the lean outlived the fuse")
		_brain.clear()
		# The numbers: the same hit, the same mood, and nothing but the curve may differ.
		_buddy.mood.set_value(40.0)
		_buddy.grime.set_value(0.0)
		Economy.grime = 0.0
		# Everything the pipeline multiplies by — the personality's curve included, and the
		# mace's mastery, which climbs as this loop hits him — read before, and divided out.
		var pipeline := Economy.payout_for(1.0, MACE)
		var bones := Economy.balance_of(Economy.BONES)
		# His mood decays in real time, and the hit takes a frame or four to land: a long frame
		# on a busy machine was a 0.23 spread against a 0.1 tolerance. Held still for the reading,
		# so the delta is the hit's alone (D70).
		_buddy.mood.set_process(false)
		var mood_before := _buddy.mood.value
		var n := _hits.size()
		await _hit(6000.0, MACE)
		amounts[p.id] = _hits[n].amount if _hits.size() > n else -1.0
		bone_rates[p.id] = (Economy.balance_of(Economy.BONES) - bones) / maxf(pipeline, 1e-9)
		mood_deltas[p.id] = _buddy.mood.value - mood_before
		_buddy.mood.set_process(true)
		grime_deltas[p.id] = _buddy.grime.value
		await _settle_hit()
		_buddy.mood.set_value(40.0)
		Economy._combo_deadline_msec = 0
		var hearts := Economy.balance_of(Economy.HEARTS)
		var kind_pipeline := Economy.payout_for(1.0, &"open_hand")
		EventBus.kindness_given.emit(&"open_hand", 1.0, _buddy.global_position)
		heart_rates[p.id] = (Economy.balance_of(Economy.HEARTS) - hearts) / maxf(kind_pipeline, 1e-9)
		_brain.clear()
		_measure("%s: hurt '%s', joy '%s', swaps %d, amplitude %.1f (hop %.2f px, %.2f per unit), fidget %.0f s, early flinch %s"
			% [p.id, hurt, joy, p.face_swaps.size(), p.reaction_amplitude, peak, hop_per_amp, p.fidget_period, p.flinches_early])
		_check("%s%s" % [p.id, "" if problems.is_empty() else ": " + "; ".join(problems)], problems.is_empty())
	# Every tell multiplies motion only; the number columns must be identical across all of them.
	_check("the same hit deals the same damage under every personality (%s)" % _spread(amounts), _flat(amounts))
	_check("and pays the same Bones once the curve is divided out (%s)" % _spread(bone_rates), _flat(bone_rates))
	# His decay is held still across the hit, so this is the hit's own effect on him.
	_check("and moves his mood by the same amount (%s)" % _spread(mood_deltas), _flat(mood_deltas, 0.01))
	_check("and dirties him by the same amount (%s)" % _spread(grime_deltas), _flat(grime_deltas))
	_check("and a pet pays the same Hearts once the curve is divided out (%s)" % _spread(heart_rates), _flat(heart_rates))
	Economy.personality = "stoic"
	EventBus.prestige_performed.emit(0.0)
	_prove(&"prestige_performed")
	_end()

func _flat(values: Dictionary, tolerance: float = 0.0) -> bool:
	if values.is_empty():
		return false
	var first: float = values.values()[0]
	for v in values.values():
		if absf(float(v) - first) > maxf(maxf(absf(first) * 1e-4, 1e-6), tolerance):
			return false
	return true

func _spread(values: Dictionary) -> String:
	if values.is_empty():
		return "none"
	var lo := INF
	var hi := -INF
	for v in values.values():
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	return "%.4f..%.4f over %d" % [lo, hi, values.size()]

# =====================================================================================
# F — Critters
# =====================================================================================

## Every critter, read off ItemDB, on a desk of its own: it finds him, tells him it is coming,
## lands a blow that pays through him without throwing him across the room, lets go when it is
## grabbed, and leaves when its time is up.
func _critters() -> void:
	_begin("critters — acquire, tell, strike, leave")
	for item in ItemDB.all_items():
		if item.category != ItemData.CATEGORY_CRITTER:
			continue
		await _critter(item.id)
	_end()

func _critter(id: StringName) -> void:
	await _stage("critter %s" % id, false)
	_focus(Settings.Intensity.NORMAL)
	Progression._unlock(id)
	_place(Vector2(900.0, HOME.y))
	await _frames(10)
	_reset_log()
	EventBus.spawn_requested.emit(id, Vector2(420.0, FLOOR_Y - 90.0))
	var npc := _last_spawned(id) as NpcBase
	if npc == null:
		_check("'%s' spawns as an NPC" % id, false)
		return
	# Something loose on the desk for an animal that throws things.
	if npc.throws_loose_items:
		Progression._unlock(&"bowling_ball")
		EventBus.spawn_requested.emit(&"bowling_ball", Vector2(480.0, FLOOR_Y - 60.0))
	var ref: WeakRef = weakref(npc)
	var problems: Array[String] = []
	var x0 := npc.global_position.x
	var t0 := Time.get_ticks_usec()
	await _frames(20)
	var bodies := 0
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		if node is NpcBase and (node as NpcBase).item_id == id:
			bodies += 1
	if bodies != mini(npc.swarm_count, NpcBase.MAX_SWARM):
		problems.append("%d bodies for a swarm of %d" % [bodies, npc.swarm_count])
	if npc.state != NpcBase.STATE_APPROACH and npc.state != NpcBase.STATE_ATTACK:
		problems.append("not approaching after a third of a second (state '%s')" % npc.state)
	# Until its first swing: the wind-up on the bus, then the blow a tell later.
	var windup: Array = []
	var swing: Array = []
	for f in 600:
		await get_tree().physics_frame
		_see()
		for t in _threats:
			if t[0] != &"windup":
				continue
			if float(t[2]) > 0.0 and windup.is_empty():
				windup = t
			elif float(t[2]) <= 0.0 and swing.is_empty() and not windup.is_empty():
				swing = t
		if not swing.is_empty():
			break
	if windup.is_empty():
		problems.append("no wind-up in 10 s (it closed %.0f px)" % absf(npc.global_position.x - x0))
	var approach := 0.0
	if not windup.is_empty():
		approach = absf((windup[1] as Vector2).x - x0) / maxf(float(int(windup[3]) - t0) / 1.0e6, 0.01)
	var bumps := 0
	for i in _hits.size():
		if _hits[i].source_id == id and (windup.is_empty() or _hit_usec[i] < int(windup[3])):
			bumps += 1
	var blow: HitInfo = null
	var spin_after := 0.0
	var peak_speed := 0.0
	var thrown := false
	if not swing.is_empty():
		# The tell is the wind-up and the swing of the same animal: the latest wind-up before it
		# where it swung from, and the nearest one only for a swarm whose bodies all moved. The
		# nearest alone paired a swing with an earlier wind-up the animal had abandoned, a few
		# pixels closer, and read 0.50 s (D70).
		var tell_from: Array = windup
		var best := INF
		var latest_here: Array = []
		for t in _threats:
			if t[0] == &"windup" and float(t[2]) > 0.0 and int(t[3]) <= int(swing[3]):
				var d := (t[1] as Vector2).distance_to(swing[1])
				if d <= 24.0:
					latest_here = t
				if d < best:
					best = d
					tell_from = t
		if not latest_here.is_empty():
			tell_from = latest_here
		# On the engine's clock, which is what the animal's wind-up timer runs on: the wall clock
		# and the smoothed frame delta part company by a few frames after a long one, and a
		# 0.35 s tell read 0.30 on it once (D70).
		var tell := float(swing[5]) - float(tell_from[5])
		if tell < npc.windup_seconds - 0.03 or tell > npc.windup_seconds + 0.08:
			problems.append("the tell was %.2f s, not %.2f" % [tell, npc.windup_seconds])
		await _frames(3)
		var loose_now := _last_spawned(&"bowling_ball") as RigidBody2D
		var ball_after := loose_now.linear_velocity if loose_now else Vector2.ZERO
		for i in _hits.size():
			if _hit_usec[i] >= int(swing[3]) - 20000:
				if _hits[i].source_id == id and blow == null:
					blow = _hits[i]
				if _hits[i].source_id == &"bowling_ball":
					thrown = true
		spin_after = absf(_buddy.angular_velocity)
		for i in 20:
			peak_speed = maxf(peak_speed, _buddy.linear_velocity.length())
			await get_tree().physics_frame
		if npc.throws_loose_items:
			# Thrown is the ball leaving toward him at throwing speed; landing is ballistics.
			var toward := signf(ball_after.x) == signf(_buddy.global_position.x - (swing[1] as Vector2).x)
			var launched := toward and ball_after.length() >= npc.throw_speed * 0.5
			await _frames(20)
			var landed_ball := not _hits_from(&"bowling_ball").is_empty()
			thrown = launched or landed_ball
			if not thrown:
				problems.append("had a bowling ball to hand and did not throw it (it left at %s px/s)" % ball_after.round())
			_measure("%s: threw the bowling ball at %.0f px/s; it %s" % [id, ball_after.length(),
				"landed on him for %.1f damage" % _hits_from(&"bowling_ball")[0].amount if landed_ball else "missed him"])
		elif blow == null:
			problems.append("the first swing did not land")
		# Central, as D54 made it: an off-centre push the size of this one would spin him at
		# about `10 px x impulse / I` (I = 5,536 for his box). A swarm is also flying into him,
		# which spins him honestly, so the test is on the walkers.
		var torque_bug := 10.0 * (blow.raw_impulse if blow else 0.0) / 5536.0
		if blow != null and not npc.flying and spin_after > maxf(0.5, torque_bug * 0.25):
			problems.append("the blow spun him at %.1f rad/s (off-centre would be %.1f)" % [spin_after, torque_bug])
		_measure("%s: crossed the desk at %.0f px/s (authored %.0f), tell %.2f s (authored %.2f), first swing %s, then peak %.0f px/s, spin %.2f rad/s; %d contact hits before any tell"
			% [id, approach, npc.move_speed, tell, npc.windup_seconds,
			("threw the bowling ball" if thrown else ("%.1f damage from %.0f impulse" % [blow.amount, blow.raw_impulse] if blow else "missed")),
			peak_speed, spin_after, bumps])
	# Every blow is telegraphed (D70, AI audit E): its body brushing him on the way in is a bump,
	# not a hit. The goose's arrival was billed with no tell at all.
	if bumps > 0:
		problems.append("its body hurt him %d times before any tell" % bumps)
	if not npc.flying and approach < npc.move_speed * 0.5:
		problems.append("walked at %.0f px/s, under half its %.0f" % [approach, npc.move_speed])
	if not _seen_now(&"threatened") and not _seen_now(&"hit_light"):
		problems.append("he never looked threatened")
	_mark(&"threatened", _seen_real.has(&"threatened"))
	# Four more seconds of it: grapples, repeats, what it costs.
	var bones := Economy.balance_of(Economy.BONES)
	var n0 := _hits_from(id).size()
	var t_window := _threats.size()
	var fastest := 0.0
	for f in 240:
		await get_tree().physics_frame
		fastest = maxf(fastest, _buddy.linear_velocity.length())
		if _buddy.health.down:
			await _until(func() -> bool: return not _buddy.health.down, 240)
	var more := _hits_from(id).size() - n0
	var swings := _threats.slice(t_window).filter(func(t: Array) -> bool:
		return t[0] == &"windup" and float(t[2]) > 0.0).size()
	_measure("%s: %d more hits in 4 s from %d wind-ups, +%.0f Bones, fastest he was thrown %.0f px/s"
		% [id, more, swings, Economy.balance_of(Economy.BONES) - bones, fastest])
	# No animal throws him harder than the drag joint itself may (D54's 4,500 px/s backstop). It
	# was a note here until D70: the gorilla's slam threw him at 4,640, and its push is capped now.
	if maxf(fastest, peak_speed) > npc.max_drag_speed:
		problems.append("threw him at %.0f px/s, past the %.0f px/s the drag joint is allowed (D54)"
			% [maxf(fastest, peak_speed), npc.max_drag_speed])
	# Grabbed mid-swing, the swing is abandoned.
	if not npc.flying and is_instance_valid(npc):
		var winding := await _until(func() -> bool: return ref.get_ref() != null and (ref.get_ref() as NpcBase).state == NpcBase.STATE_ATTACK, 300)
		if winding:
			_threats.clear()
			var before := _hits_from(id).size()
			# The cursor where the animal is, so the drag joint pins it in place rather than
			# yanking it across the desk to wherever the last event left the mouse.
			_push_motion(npc.global_position)
			await get_tree().physics_frame
			npc._start_drag()
			await _frames(int((npc.windup_seconds + 0.2) * 60.0))
			var swung := false
			for t in _threats:
				if t[0] == &"windup" and float(t[2]) <= 0.0:
					swung = true
			# Its swing, not its body: a held animal still collides with what it is swung into.
			if swung:
				problems.append("the swing it was grabbed in still landed (held %s, swung %s, hits %s)"
					% [npc.dragging, swung, _list(_hits_from(id).slice(before).map(
						func(h: HitInfo) -> String: return "%.0f" % h.raw_impulse))])
			npc._end_drag()
	# Its time is up: it walks to the nearest edge and is gone, swinging at nothing on the way.
	# Every body of the summon, as time would have it: a swarm hatches together.
	_reset_log()
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		if node is NpcBase and (node as NpcBase).item_id == id:
			(node as NpcBase)._age = (node as NpcBase).lifetime_seconds + 1.0
	var gone_in := Time.get_ticks_msec()
	var left := false
	for f in 900:
		await get_tree().physics_frame
		if ref.get_ref() == null:
			left = true
			break
	var remaining := 0
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		if node is NpcBase and (node as NpcBase).item_id == id and not node.is_queued_for_deletion():
			remaining += 1
	if not left:
		problems.append("never left")
	if remaining > 0:
		problems.append("%d bodies stayed behind" % remaining)
	var swings_leaving := 0
	for t in _threats:
		if t[0] == &"windup" and float(t[2]) > 0.0:
			swings_leaving += 1
	if swings_leaving > 0:
		problems.append("wound up %d times on its way out" % swings_leaving)
	# Walked off, not timed out: the timeout despawns it wherever it stands, which is the middle
	# of the desk in front of him.
	var took := float(Time.get_ticks_msec() - gone_in) / 1000.0
	if left and took >= NpcBase.LEAVE_TIMEOUT - 0.5:
		problems.append("never reached an edge; the %.0f s timeout removed it" % NpcBase.LEAVE_TIMEOUT)
	_measure("%s: left in %.1f s; %d contact hits on the way out" % [id, took, _hits_from(id).size()])
	if not _hits_from(id).is_empty():
		problems.append("its body hurt him %d times on its way out, where it swings at nothing" % _hits_from(id).size())
	_check("%s%s" % [id, "" if problems.is_empty() else ": " + "; ".join(problems)], problems.is_empty())

# =====================================================================================
# G — Turrets
# =====================================================================================

## Every turret, read off ItemDB, on a desk of its own: it acquires him inside its reach and
## not outside it, aims within its cap and mirrors to his side, fires on its interval from the
## muzzle, and the shot lands on him and pays.
func _turrets() -> void:
	_begin("turrets — acquire, aim, fire, land")
	for item in ItemDB.all_items():
		if item.category != ItemData.CATEGORY_TURRET:
			continue
		await _turret(item.id)
	_end()

func _turret(id: StringName) -> void:
	await _stage("turret %s" % id, false)
	_focus(Settings.Intensity.NORMAL)
	Progression._unlock(id)
	var probe := ItemDB.get_item(id).scene.instantiate() as TurretBase
	var reach := probe.max_range
	var turret_half := _half_width(probe)
	probe.free()
	_place(Vector2(HOME.x, HOME.y))
	await _frames(10)
	# Never inside him. The sides below are set by teleport, and a teleport into an overlap is
	# resolved by a shove at whatever part overlaps — at the end of a flamethrower's 108 px tank
	# (D61: the collider is the whole picture) that shove tipped it onto its side and put its
	# muzzle straight up. So the gap clears both bodies' own colliders as well as sitting in reach.
	var gap := maxf(minf(reach * 0.6, 260.0), turret_half + _half_width(_buddy) + 8.0)
	EventBus.spawn_requested.emit(id, Vector2(HOME.x - gap, FLOOR_Y - 60.0))
	var turret := _last_spawned(id) as TurretBase
	if turret == null:
		_check("'%s' spawns as a turret" % id, false)
		return
	var problems: Array[String] = []
	# Held off its trigger while it is set up and looked at: a mortar round in the first second
	# puts him across the desk and every aim check after it is about an empty spot.
	turret._since_shot = -1000.0
	await _frames(45)
	if turret._target() != _buddy:
		problems.append("did not acquire him %.0f px away (reach %.0f)" % [gap, reach])
	var cap := deg_to_rad(turret.aim_lean_degrees)
	var sides: Array[String] = []
	for side in [-1.0, 1.0]:
		# -1: the turret on his left, facing right toward him.
		turret.global_position = Vector2(_buddy.global_position.x + side * gap, turret.global_position.y)
		turret.linear_velocity = Vector2.ZERO
		turret.angular_velocity = 0.0
		await _frames(50)
		var facing: float = -side
		var host: Sprite2D = turret.barrel if turret.barrel else turret.sprite as Sprite2D
		if signf(turret._facing) != facing:
			problems.append("facing %+.0f with him on its %s" % [turret._facing, "right" if facing > 0.0 else "left"])
		if turret.flips and host and host.flip_h != (facing != turret.faces):
			problems.append("not mirrored to face him")
		if absf(turret._lean) > cap + 0.001:
			problems.append("leans %.1f deg past its %.0f deg cap" % [rad_to_deg(absf(turret._lean)), turret.aim_lean_degrees])
		var muzzle := turret.muzzle_position()
		if turret.muzzle != Vector2.ZERO and signf(muzzle.x - turret.global_position.x) != facing \
				and absf(turret.muzzle.x) > 2.0:
			problems.append("the muzzle is on the far side (%.0f)" % (muzzle.x - turret.global_position.x))
		sides.append("%s: lean %.1f deg, muzzle %s" % ["left" if side < 0.0 else "right",
			rad_to_deg(turret._lean), (muzzle - turret.global_position).round()])
	# One shot at him standing free: it lands, it pays, and it pushes him away from the gun.
	_reset_log()
	var interval := turret._interval()
	turret._since_shot = interval - 0.02
	var vel_after := Vector2.ZERO
	var first_shot := await _until(func() -> bool: return _shots_from(turret).size() > 0, 30)
	# One step on from the shot: the pellet's push has been integrated.
	await get_tree().physics_frame
	vel_after = _buddy.linear_velocity
	await _frames(3)
	var first_hits := _hits_from(id)
	var pushed := signf(vel_after.x) == signf(_buddy.global_position.x - turret.global_position.x) \
		and absf(vel_after.x) > 1.0
	# The rhythm, with him held still so the first shot cannot carry him out of its reach, and a
	# meter deep enough that three rail-gun rounds do not knock him out between two of them.
	turret._since_shot = -1000.0
	await _until(func() -> bool: return not _buddy.health.down, 300)
	_buddy.health.reset_meter()
	var meter := _buddy.health.max_damage
	_buddy.health.max_damage = 1.0e9
	_place(HOME)
	_buddy.freeze = true
	turret.global_position = Vector2(HOME.x - gap, turret.global_position.y)
	turret.linear_velocity = Vector2.ZERO
	await _frames(10)
	_reset_log()
	turret._since_shot = interval - 0.02
	var shots: Array[int] = []
	await _until(func() -> bool: return _shots_from(turret).size() >= 3, int((interval * 2.0 + 0.6) * 60.0))
	shots = _shots_from(turret)
	await _frames(3)
	_buddy.freeze = false
	_buddy.health.max_damage = meter
	_buddy.health.reset_meter()
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var measured := float(shots[1] - shots[0]) * tick if shots.size() >= 2 else -1.0
	var measured2 := float(shots[2] - shots[1]) * tick if shots.size() >= 3 else measured
	# Within a tick of the interval: it fires on the first tick its timer has passed.
	if shots.size() < 3 or absf(measured - interval) > tick * 1.01 or absf(measured2 - interval) > tick * 1.01:
		problems.append("fired %d shots, %.3f then %.3f s apart (interval %.3f)" % [shots.size(), measured, measured2, interval])
	# Every shot lands on him and pays. The design's number is blast_force: it is the damage.
	var landed := _hits_from(id)
	var design := turret.blast_force * 0.01 * turret.effective_damage_mult()
	var mean := 0.0
	for h in landed + first_hits:
		mean += h.amount
	mean /= maxf(1.0, float(landed.size() + first_hits.size()))
	_measure("%s: every %.2f s (measured %.3f, %.3f), %d shots → %d hits of %.1f damage (design %.1f per pellet, x%d pellets, capped at %.0f); the first pushed him %s at %.0f px/s; %s"
		% [id, interval, measured, measured2, shots.size(), landed.size(), mean, design, turret.pellets,
		ItemDB.balance.knockout_damage * ItemDB.balance.max_hit_fraction,
		"away" if pushed else "NOT away", vel_after.length(), "; ".join(sides)])
	if not first_shot or first_hits.is_empty():
		problems.append("the first shot did not land on him")
	if landed.size() < shots.size():
		problems.append("%d of %d shots landed on him" % [landed.size(), shots.size()])
	var cap_damage := ItemDB.balance.knockout_damage * ItemDB.balance.max_hit_fraction
	if not landed.is_empty() and turret.spread <= 0.0 and mean < minf(design, cap_damage) * 0.9:
		problems.append("a hit is %.1f damage, short of the %.1f its blast is worth" % [mean, minf(design, cap_damage)])
	# D54: a shot is never a launch straight up. How hard it pushes is the splash falloff, which
	# for the smallest blasts is nothing at all — reported above, not failed on.
	if vel_after.y < -100.0 and absf(vel_after.x) < absf(vel_after.y) * 0.25:
		problems.append("the shot launched him straight up (%s px/s)" % vel_after.round())
	if not _seen_now(&"threatened"):
		problems.append("he never looked threatened")
	_mark(&"threatened", _seen_real.has(&"threatened"))
	# Out of reach: it finds nothing, fires nothing, and does not bank an hour of shots.
	_place(Vector2(1200.0, HOME.y))
	await _frames(20)
	var far_x := _buddy.global_position.x - (reach + 60.0)
	if far_x >= 40.0:
		turret.global_position = Vector2(far_x, turret.global_position.y)
		turret.linear_velocity = Vector2.ZERO
		await _frames(int(minf(interval, 1.5) * 60.0) + 10)
		if turret._target() != null:
			problems.append("acquired him out of reach (%.0f px)" % turret.global_position.distance_to(_buddy.global_position))
		if turret._since_shot > interval + 0.001:
			problems.append("banked %.2f s of shots out of reach" % turret._since_shot)
	# Focus Off: it stops moving and keeps firing.
	turret._since_shot = -1000.0
	_place(HOME)
	turret.global_position = Vector2(HOME.x - gap, turret.global_position.y)
	turret.linear_velocity = Vector2.ZERO
	await _frames(20)
	_focus(Settings.Intensity.OFF)
	_reset_log()
	turret._since_shot = interval - 0.02
	await _frames(6)
	var host2: Node2D = turret.barrel if turret.barrel else turret.sprite
	if _threats.is_empty():
		problems.append("stopped firing at Off")
	if host2 and not is_zero_approx(host2.rotation):
		problems.append("still leaning at Off")
	_focus(Settings.Intensity.NORMAL)
	_check("%s%s" % [id, "" if problems.is_empty() else ": " + "; ".join(problems)], problems.is_empty())

# =====================================================================================
# the stage
# =====================================================================================

## A desk of its own: a 1280x720 SubViewport with the game's real walls, a spawner, a buddy
## on the floor at `HOME` and, when asked, an idle brain whose think tick the suite drives.
func _stage(title: String, with_idle_brain: bool = false) -> void:
	await _teardown()
	_view = SubViewport.new()
	_view.name = "Stage"
	_view.size = VIEW_SIZE
	_view.disable_3d = true
	_view.handle_input_locally = true
	_view.physics_object_picking = true
	add_child(_view)
	# A bare SubViewport never learns the mouse is inside it, and picking is gated on that.
	_view.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
	_world = Node2D.new()
	_world.name = "World"
	_view.add_child(_world)
	var bounds := WorldBounds.new()
	bounds.name = "WorldBounds"
	_world.add_child(bounds)
	_spawner = ItemSpawner.new()
	_spawner.name = "ItemSpawner"
	_spawner.world = _world
	_spawner.add_to_group(&"item_spawner")
	_world.add_child(_spawner)
	if with_idle_brain:
		# Before the buddy, so his expression brain finds it on its deferred connect.
		_idle = IdleBrain.install(_world)
		# The suite thinks when it chooses. `think_now()` is the same code the timer runs.
		(_idle.get_node("ThinkTimer") as Timer).stop()
		_idle.routine_ended.connect(_log_end)
	_buddy = BUDDY_SCENE.instantiate() as Buddy
	_buddy.name = "Buddy"
	_buddy.position = HOME
	_world.add_child(_buddy)
	_art = _buddy.art
	_brain = _buddy.expression
	# Economy mirrors mood and grime off the bus; a fresh buddy starts at zero and says nothing.
	Economy.mood = _buddy.mood.value
	Economy.grime = _buddy.grime.value
	_brain._load_personality()
	await _frames(20)
	_brain.clear()
	_reset_log()
	print("      [stage: %s]" % title)

func _teardown() -> void:
	if is_instance_valid(_view):
		_view.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame
	_view = null
	_world = null
	_buddy = null
	_art = null
	_brain = null
	_idle = null
	_spawner = null

func _reset_log() -> void:
	_hits.clear()
	_given.clear()
	_sustained.clear()
	_threats.clear()
	_landings.clear()
	_states.clear()
	_knockouts.clear()
	_despawns.clear()
	_ends.clear()
	_hit_usec.clear()

func _place(at: Vector2) -> void:
	_buddy.global_position = at
	_buddy.global_rotation = 0.0
	_buddy.linear_velocity = Vector2.ZERO
	_buddy.angular_velocity = 0.0

func _focus(level: Settings.Intensity) -> void:
	Settings.set_focus_intensity(level)

func _focus_name() -> String:
	return ["Off", "Subtle", "Normal", "Chaos"][int(Settings.focus_intensity)]

func _clear_desk() -> void:
	if is_instance_valid(_spawner):
		_spawner.clear_desk()

## How far a body's solid shapes reach either side of its origin, in its own pixels — read off
## the shapes, so a collider re-authored to its picture moves the answer with it.
func _half_width(body: Node) -> float:
	var reach := 0.0
	for child in body.get_children():
		var piece := child as CollisionShape2D
		if piece == null or piece.shape == null:
			continue
		var box := piece.transform * piece.shape.get_rect()
		reach = maxf(reach, maxf(absf(box.position.x), absf(box.end.x)))
	return reach

func _last_spawned(id: StringName) -> Node:
	if not is_instance_valid(_spawner):
		return null
	for i in range(_spawner._active.size() - 1, -1, -1):
		var node := _spawner._active[i]
		if is_instance_valid(node) and node is BaseDraggable and (node as BaseDraggable).item_id == id:
			return node
	return null

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		_see()

func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
		_see()
	return cond.call()

func _see() -> void:
	if _recording and is_instance_valid(_brain) and _brain.beat_active():
		_seen_real[_brain.beat_id()] = true

func _seen_now(id: StringName) -> bool:
	_see()
	return _seen_real.has(id)

## A blow through his own door — the one every gunshot, blast and animal uses — and the
## physics ticks that dispatch it onto the bus.
func _hit(impulse: float, source: StringName) -> void:
	var before := _hits.size()
	_buddy.take_impulse(impulse, source, 1.0, _buddy.global_position + Vector2(30, 0))
	await _until(func() -> bool: return _hits.size() > before, 4)

## Back to standing still, idle and unhurt, with no beat in the slot.
func _settle_hit() -> void:
	await _until(func() -> bool: return _buddy.state == &"idle", 90)
	_buddy.health.reset_meter()
	_brain.clear()

## The cursor onto him (or well away), as a motion event pushed through the SubViewport so the
## grab region's own physics picking decides. Returns whether he ended up hovered as asked.
func _hover(on: bool) -> bool:
	var at := _buddy.global_position if on else Vector2(20, 20)
	_push_motion(at)
	await _until(func() -> bool: return _buddy.drag_area.is_hovered == on, 6)
	return _buddy.drag_area.is_hovered == on

func _push_motion(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_view.push_input(motion)

func _grab() -> bool:
	if not await _hover(true):
		return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _buddy.global_position
	click.global_position = click.position
	_view.push_input(click)
	await _frames(1)
	return _buddy.dragging

func _release() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	click.position = _buddy.global_position
	click.global_position = click.position
	_view.push_input(click)
	await _frames(1)
	await _hover(false)

## Pushes the ambient deadlines out of the way, so a skewed clock asks about the beat under
## test and not about a blink that fell due while the clock was being wound on.
func _hush() -> void:
	_brain._blink_at = _brain._now() + 3600 * 1000
	_brain._fidget_at = _brain._now() + 3600 * 1000
	if is_instance_valid(_idle):
		_idle._last_disturbance_msec = Time.get_ticks_msec()

## Winds the brain's clock on and lets its own timer fire, rather than calling the handler:
## the timer is part of what is under test.
func _advance_brain(ms: int) -> void:
	_brain._clock_skew += maxi(ms, 0)
	_brain._arm()
	# `_arm` never starts its timer for less than 10 ms of real time, and three headless frames
	# can pass in less than that — then nothing that was due has fired, which read as "ninety
	# seconds unfocused and he never falls asleep" on a tree that simply ran its frames faster.
	# Wait out the floor on the engine's clock, then the frames.
	await get_tree().create_timer(0.03, true, false, true).timeout
	await _frames(3)

var _sampled: Array[StringName] = []

func _sample_beat(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_sampled.append(_brain.beat_id())

func _any_automation_node() -> StringName:
	for item in ItemDB.all_items():
		for node in ItemDB.augments_for(item.id):
			if node.is_automation:
				return node.id
	return &""

func _something_to_buy() -> StringName:
	for item in ItemDB.all_items():
		if not Progression.is_unlocked(item.id) and Progression.can_purchase(item.id):
			return item.id
	return &""

func _mood_face(mood: float) -> StringName:
	for threshold in BuddyArt.MOOD_FACES:
		if mood < float(threshold[0]):
			return threshold[1]
	return &""

func _mood_idle(mood: float) -> StringName:
	for threshold in BuddyArt.MOOD_IDLES:
		if mood < float(threshold[0]):
			var idle: StringName = threshold[1]
			if idle == &"idle" and _art.posture_bias != &"" and _art.has_animation(_art.posture_bias):
				idle = _art.posture_bias
			return idle
	return &""

# --- the bus log -----------------------------------------------------------------

func _log_hit(info: HitInfo) -> void:
	_hits.append(info)
	_hit_usec.append(Time.get_ticks_usec())

func _log_given(source_id: StringName, value: float, at: Vector2) -> void:
	_given.append([source_id, value, at, Time.get_ticks_usec()])

func _log_sustained(source_id: StringName, value: float, at: Vector2) -> void:
	_sustained.append([source_id, value, at, Time.get_ticks_usec()])

func _log_threat(kind: StringName, at: Vector2, level: float) -> void:
	_threats.append([kind, at, level, Time.get_ticks_usec(), Engine.get_physics_frames(), _engine_seconds])

func _log_landing(at: Vector2, speed: float) -> void:
	_landings.append([at, speed])

func _log_state(state: StringName) -> void:
	_states.append([state, Time.get_ticks_usec()])

func _log_knockout(total: float) -> void:
	_knockouts.append(total)

func _log_despawn(item: Node2D) -> void:
	_despawns.append(item)

func _log_end(reason: StringName) -> void:
	_ends.append(reason)

func _value_from(log: Array[Array], source: StringName) -> float:
	var total := 0.0
	for entry in log:
		if entry[0] == source:
			total += float(entry[1])
	return total

## When a turret fired, off its own `threat_changed` on the bus, in physics ticks — the clock
## the turret itself counts on, where the wall clock jitters by a frame under load.
func _shots_from(turret: Node2D) -> Array[int]:
	var out: Array[int] = []
	for t in _threats:
		if t[0] == &"turret" and (t[1] as Vector2).distance_to(turret.global_position) < 40.0:
			out.append(int(t[4]))
	return out

func _hits_from(source: StringName) -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	for info in _hits:
		if info.source_id == source:
			out.append(info)
	return out

# --- harness ---------------------------------------------------------------------

func _begin(name_: String) -> void:
	_cur = {"name": name_, "passed": 0, "failed": 0, "failures": [], "measures": []}
	_sections.append(_cur)
	print("")
	print("  %s" % name_)

func _end() -> void:
	print("    -- %d ok, %d failed" % [int(_cur.get("passed", 0)), int(_cur.get("failed", 0))])

func _check(what: String, condition: bool) -> void:
	if condition:
		_passed += 1
		_cur["passed"] = int(_cur.get("passed", 0)) + 1
		print("    ok   %s" % what)
	else:
		_failed += 1
		_cur["failed"] = int(_cur.get("failed", 0)) + 1
		(_cur["failures"] as Array).append(what)
		printerr("    FAIL %s" % what)

func _measure(line: String) -> void:
	(_cur["measures"] as Array).append(line)
	print("         = %s" % line)

func _note(line: String) -> void:
	_notes.append("%s: %s" % [_cur.get("name", "?"), line])
	print("    note %s" % line)

func _list(items: Array) -> String:
	return "none" if items.is_empty() else ", ".join(items.map(func(x: Variant) -> String: return str(x)))

func _write_report(seconds: float) -> void:
	var lines: Array[String] = []
	lines.append("# brain_check — %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("")
	lines.append("%d passed, %d failed, %.0f s. Generated by `tests/integration/brain_check.tscn` (D60)."
		% [_passed, _failed, seconds])
	lines.append("")
	lines.append("| Mechanic | Verdict | Passed | Failed |")
	lines.append("|---|---|---|---|")
	for s in _sections:
		lines.append("| %s | %s | %d | %d |" % [s["name"], "PASS" if int(s["failed"]) == 0 else "FAIL",
			int(s["passed"]), int(s["failed"])])
	for s in _sections:
		if (s["failures"] as Array).is_empty() and (s["measures"] as Array).is_empty():
			continue
		lines.append("")
		lines.append("## %s" % s["name"])
		for f in s["failures"]:
			lines.append("- **FAIL** %s" % f)
		for m in s["measures"]:
			lines.append("- %s" % m)
	if not _notes.is_empty():
		lines.append("")
		lines.append("## Notes")
		for n in _notes:
			lines.append("- %s" % n)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines) + "\n")
		file.close()

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## Upright enough to set off, and not moving. Not `is_grounded()`: a body at rest sleeps, and
## that flag is last awake tick's contacts.
func _standing_still() -> bool:
	return _buddy.linear_velocity.length() < 60.0 \
		and absf(wrapf(_buddy.rotation, -PI, PI)) < deg_to_rad(IdleBrain.START_UPRIGHT_DEG)
