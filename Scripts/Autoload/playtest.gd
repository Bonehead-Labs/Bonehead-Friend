extends Node

## The playtest kit's quiet half: a session log, the errors the engine raised, the notes a
## tester leaves, and the one zip that carries them back (docs/playtest-plan.md).
##
## **Last in the boot order**, after `AudioManager`. Every signal it listens to is presentation
## for its purposes — it records what happened and changes nothing — so it connects after every
## system that acts on the same signals, and reads state they have already settled. The engine
## logger is the one thing that must be early, and it is: `_init` runs when the autoloads are
## instantiated, which is before any of them is added to the tree, so an error in any autoload's
## `_ready` is caught.
##
## **It costs nothing measurable.** No `_process`. Rows are buffered and appended every thirty
## seconds and on the way out; one row a minute samples the purse; every per-hit handler is one
## dictionary lookup. The files are capped on disk. It writes nothing at all unless this is a
## playtest build (`BuildInfo`) and the tester has left the log switched on in Settings.
##
## **No personal data.** No names, no paths, no clipboard, no other windows. Engine messages are
## scrubbed of the user folder and anything that looks like a home folder before they are kept.
## The only text a person wrote is what they typed into a feedback note.

const Build := preload("res://Scripts/Playtest/build_info.gd")
const Fmt := preload("res://Scripts/Playtest/playtest_format.gd")

## The feedback card listens: F1, the Settings key and the Esc menu all say this.
signal feedback_requested()
## A note was saved, a bundle made or the log switched: Settings re-reads its counts.
signal notes_changed()
## An upload finished, well or badly.
signal upload_finished(ok: bool)

const ROOT_DIR := "user://playtest"

## Where everything is written. A variable so a suite can point it somewhere disposable before
## it writes anything (the same rule as `Settings.config_path`, D51).
var root_dir := ROOT_DIR
## Where "Send feedback" puts the zip when there is no uploader. "" is the Desktop.
var send_dir := ""
## The uploader's config. "" searches beside the exe, then `user://playtest.cfg`.
var upload_config_path := ""
## Seconds before an upload gives up. A closed port on Windows is not refused, it is silent, so
## this is also how long a failed attempt takes.
var upload_timeout := 60.0

const FLUSH_SECONDS := 30.0
const TICK_SECONDS := 60.0
## A pause shorter than this is thinking, not a pause worth a row.
const GAP_SECONDS := 60.0
## What a feedback note carries of the session so far.
const RECENT_ROWS := 40
const RECENT_ERRORS := 10

## Rolling caps. Sessions are the bulk; a tester who leaves it running all week keeps the most
## recent sixty sessions or eight megabytes, whichever is smaller.
const MAX_SESSION_FILES := 60
const MAX_SESSION_BYTES := 8 * 1024 * 1024
## One session past this stops logging everything but its errors and its end.
const MAX_FILE_BYTES := 1024 * 1024
const MAX_NOTES := 200
const MAX_OUTBOX := 5
const MAX_UNIQUE_ERRORS := 100
## The engine's own logs that ride along in a bundle, newest first, each cut to its tail.
const ENGINE_LOGS := 3
const ENGINE_LOG_TAIL := 256 * 1024
## A 4K overlay's screenshot is halved, by whole pixels.
const SHOT_MAX_WIDTH := 1920

const MOODS := ["good", "meh", "bad"]

## Everything pushed to the error log, from any thread. Held under a mutex and drained by the
## main thread on the flush timer; never logs anything itself, or it would log forever.
class Catch extends Logger:
	const CAP := 512
	var _mutex := Mutex.new()
	var _lines: Array = []
	var _dropped := 0

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var kind: String = ["error", "warning", "script", "shader"][clampi(error_type, 0, 3)]
		var message := rationale if rationale != "" else code
		_mutex.lock()
		if _lines.size() < CAP:
			_lines.append([kind, message, "%s:%d" % [file.get_file(), line], function])
		else:
			_dropped += 1
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		_mutex.lock()
		var out := _lines
		_lines = []
		out.append(_dropped)
		_dropped = 0
		_mutex.unlock()
		return out

var _catch: Catch

var _started_msec := 0
var _active := false
var _ended := false
var _session_name := ""
var _session_path := ""
var _buffer := PackedStringArray()
var _bytes := 0
var _file_full := false
var _recent := PackedStringArray()
var _flush_timer: Timer
var _tick_timer: Timer

## What the player is doing, for the gaps and the minute rows.
var _last_act_msec := 0
var _acts_total := 0
var _acts_minute := 0
var _away_since := -1
var _away_in_gap := false
var _page: StringName = &""
var _power: StringName = &""
var _buddy_state: StringName = &""

var _first_session := {}
var _bal_prev := {}
var _bal_now := {}
var _last_window := ""

var _error_counts := {}
var _error_total := 0
var _recent_errors := PackedStringArray()

var _state := ConfigFile.new()
var _state_loaded := false
var _state_dirty := false
var _seen_ever := {}

var _http: HTTPRequest
var _uploading := ""

func _init() -> void:
	_catch = Catch.new()
	OS.add_logger(_catch)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_msec = Time.get_ticks_msec()
	_last_act_msec = _started_msec

	_flush_timer = Timer.new()
	_flush_timer.name = "PlaytestFlush"
	_flush_timer.wait_time = FLUSH_SECONDS
	_flush_timer.timeout.connect(_on_flush_timer)
	add_child(_flush_timer)
	_flush_timer.start()

	_tick_timer = Timer.new()
	_tick_timer.name = "PlaytestTick"
	_tick_timer.wait_time = TICK_SECONDS
	_tick_timer.timeout.connect(_tick)
	add_child(_tick_timer)

	EventBus.item_purchased.connect(_on_item_purchased)
	EventBus.augment_purchased.connect(_on_augment_purchased)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.mastery_rank_up.connect(func(id: StringName, rank: int) -> void:
		record("rank", {"id": String(id), "r": rank}))
	EventBus.contract_claimed.connect(func(id: StringName, dollars: int) -> void:
		record("job", {"id": String(id), "d": dollars}))
	EventBus.knockout_payout.connect(_on_knockout)
	EventBus.prestige_performed.connect(_on_prestige)
	EventBus.ui_panel_changed.connect(_on_page)
	EventBus.item_spawned.connect(_on_item_spawned)
	EventBus.cursor_power_changed.connect(_on_power)
	EventBus.damage_dealt.connect(func(info: HitInfo) -> void:
		if info.source_id != &"":
			_first("hit", info.source_id))
	EventBus.kindness_given.connect(func(source_id: StringName, _v: float, _p: Vector2) -> void:
		if source_id != &"":
			_first("kind", source_id))
	EventBus.ability_event.connect(func(item_id: StringName, event: StringName, _p: Vector2) -> void:
		_first("ability", item_id, event))
	EventBus.fidget_event.connect(func(item_id: StringName, event: StringName, _p: Vector2) -> void:
		_first("fidget", item_id, event))
	EventBus.buddy_state_changed.connect(func(state: StringName) -> void: _buddy_state = state)
	EventBus.ui_scale_changed.connect(func(factor: float) -> void: record("scale", {"f": factor}))
	EventBus.focus_mode_changed.connect(func(level: int) -> void: record("focus_mode", {"l": level}))
	Milestones.milestone_claimed.connect(func(id: StringName, rungs: int, _d: int) -> void:
		record("deed", {"id": String(id), "r": rungs}))
	OverlayManager.window_rect_changed.connect(func(_rect: Rect2i) -> void: _on_window())

	_begin_when_ready()

## After the main scene has loaded the save, so the first row can say who is playing.
func _begin_when_ready() -> void:
	await get_tree().process_frame
	# The studio splash (Scripts/boot_splash.gd) plays before main.tscn, and the save loads with
	# main: wait for the hand-off, or the first row describes an unloaded game.
	var scene := get_tree().current_scene
	if scene != null and scene.is_in_group(&"boot_splash"):
		await get_tree().scene_changed
	if logging_enabled():
		begin_session()
	# Whatever a previous launch could not send goes first, once the desk has settled.
	if uploads_enabled() and not _outbox_files().is_empty():
		get_tree().create_timer(10.0).timeout.connect(_upload_next)

func _exit_tree() -> void:
	_leave("exit")
	if _catch:
		OS.remove_logger(_catch)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_leave("quit")
		NOTIFICATION_CRASH:
			end_session("crash")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _away_since < 0:
				_away_since = Time.get_ticks_msec()
			_away_in_gap = true
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if _away_since >= 0:
				var seconds := (Time.get_ticks_msec() - _away_since) / 1000.0
				_away_since = -1
				if seconds >= GAP_SECONDS:
					record("away", {"s": roundi(seconds)})

var _left := false

## The way out, by the window's close box or by Esc > Save and quit (which never raises a close
## request). With `auto_on_quit` in the uploader's config, what was logged is bundled into the
## queue on the way, and the next launch sends it — nobody has to remember a button. Only while
## the tester has the log switched on: switching it off is how they say "stop sending".
func _leave(why: String) -> void:
	if _left:
		return
	_left = true
	end_session(why)
	if _auto_bundle_on_quit() and logging_enabled():
		make_bundle(_outbox_dir())
		_prune_folder("outbox", ".zip", MAX_OUTBOX, 1 << 30, "")

## Any press is the player doing something. Motion is not: a cursor crossing the window on its
## way to somewhere else is not play.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var key := event as InputEventKey
	if (button and button.pressed) or (key and key.pressed and not key.is_echo()):
		note_act()

# --- the switch --------------------------------------------------------------

## A playtest build with the tester's consent, which is on until they say otherwise.
func logging_enabled() -> bool:
	return Build.is_playtest() and Settings.playtest_log

func is_logging() -> bool:
	return _active

func set_session_log(on: bool) -> void:
	Settings.playtest_log = on
	Settings.save_settings()
	if logging_enabled():
		begin_session()
	else:
		end_session("switched_off")
	notes_changed.emit()

## Everything under a new folder, forgetting what the old one held. Suites call this first.
func use_root(dir: String) -> void:
	end_session("moved")
	root_dir = dir
	_state = ConfigFile.new()
	_state_loaded = false
	_state_dirty = false
	_seen_ever = {}
	_first_session = {}

# --- the session -------------------------------------------------------------

func begin_session() -> void:
	if _active:
		return
	_ensure_dirs()
	_session_name = "%s_%s_%04x" % [Fmt.file_stamp(Time.get_datetime_dict_from_system()),
		_file_safe(Build.id()), randi() & 0xffff]
	_session_path = "%s/sessions/%s.jsonl" % [root_dir, _session_name]
	var file := FileAccess.open(_session_path, FileAccess.WRITE)
	if file == null:
		push_warning("Playtest: cannot create a session log (error %d)" % FileAccess.get_open_error())
		_session_path = ""
		return
	file.close()
	_prune_folder("sessions", ".jsonl", MAX_SESSION_FILES, MAX_SESSION_BYTES, _session_name + ".jsonl")
	_active = true
	_ended = false
	_bytes = 0
	_file_full = false
	_first_session = {}
	# Counted per session. What the logger caught before this line and nobody has drained yet —
	# everything raised during boot, since no flush has run — is drained just below, into this
	# session, which is where it belongs.
	_error_counts = {}
	_error_total = 0
	_load_state()
	_state.set_value("stats", "sessions", int(_state.get_value("stats", "sessions", 0)) + 1)
	_state_dirty = true
	record("start", _start_fields())
	_drain_errors()
	_tick_timer.start()
	# Written now rather than in thirty seconds: a crash in the first half-minute still leaves a
	# file that says a session began, on which build, on what screen.
	flush()

func end_session(why: String) -> void:
	if not _active or _ended:
		return
	_ended = true
	_drain_errors()
	var session: Dictionary = Economy.session
	record("end", {
		"why": why,
		"min": snappedf(uptime_seconds() / 60.0, 0.1),
		"acts": _acts_total,
		"hits": int(session.get("hits", 0)),
		"pets": int(session.get("pets", 0)),
		"b": roundi(float(session.get("bones", 0.0))),
		"h": roundi(float(session.get("hearts", 0.0))),
		"errs": _error_total,
		"err_unique": _error_counts.size(),
	})
	flush()
	_save_state()
	_active = false
	if _tick_timer:
		_tick_timer.stop()

func session_name() -> String:
	return _session_name

func session_path() -> String:
	return _session_path

func uptime_seconds() -> float:
	return (Time.get_ticks_msec() - _started_msec) / 1000.0

## One row. Kept in memory for the next feedback note whether or not the log is on — a note says
## what it carries on its own card — and written to disk only while it is.
func record(event: String, fields: Dictionary = {}) -> void:
	var line := Fmt.row(uptime_seconds(), event, fields)
	_recent.append(line)
	if _recent.size() > RECENT_ROWS:
		_recent.remove_at(0)
	if not _active:
		return
	if _file_full and event != "end" and event != "err":
		return
	_buffer.append(line)
	_bytes += line.length() + 1
	if _bytes > MAX_FILE_BYTES and not _file_full:
		_file_full = true
		_buffer.append(Fmt.row(uptime_seconds(), "full"))
	if _buffer.size() >= 512:
		flush()

## Appends what is buffered. Reopened per flush rather than held open, so a crash leaves every
## flushed row on disk (the same reasoning as `TuningLog`).
func flush() -> void:
	if _buffer.is_empty() or _session_path == "":
		_buffer.clear()
		return
	var file := FileAccess.open(_session_path, FileAccess.READ_WRITE)
	if file == null:
		_buffer.clear()
		return
	file.seek_end()
	for line in _buffer:
		file.store_line(line)
	file.close()
	_buffer.clear()

func _on_flush_timer() -> void:
	_drain_errors()
	flush()
	if _state_dirty:
		_save_state()

func note_act() -> void:
	var now := Time.get_ticks_msec()
	var gap := (now - _last_act_msec) / 1000.0
	if gap >= GAP_SECONDS:
		# `away`: the window lost focus at some point in the gap, so the player was somewhere
		# else. A gap that stayed focused is somebody looking at the game and doing nothing,
		# which is the dead stretch the M3 gate is about.
		record("gap", {"s": roundi(gap), "away": _away_in_gap or _away_since >= 0})
	_last_act_msec = now
	_away_in_gap = _away_since >= 0
	_acts_total += 1
	_acts_minute += 1

func seconds_since_act() -> float:
	return (Time.get_ticks_msec() - _last_act_msec) / 1000.0

## Once a minute while logging: the purse, what is owned, and whether anything is affordable —
## which is the M3 gate's "never more than five minutes from the next affordable thing", read
## straight off the rows.
func _tick() -> void:
	if not _active:
		return
	var next := _next_item()
	record("tick", {
		"b": roundi(Economy.balance_of(Economy.BONES)),
		"h": roundi(Economy.balance_of(Economy.HEARTS)),
		"d": roundi(Economy.balance_of(Economy.DOLLARS)),
		"lb": roundi(Economy.lifetime_of(Economy.BONES)),
		"lh": roundi(Economy.lifetime_of(Economy.HEARTS)),
		"m": snappedf(Economy.marrow, 0.01),
		"pc": Economy.prestige_count,
		"own": Progression.owned_items().size(),
		"desk": get_tree().get_nodes_in_group(&"spawned_item").size(),
		"aff": next["affordable"],
		"next": next["id"],
		"nr": next["ratio"],
		"acts": _acts_minute,
		"idle": roundi(seconds_since_act()),
		"mood": roundi(Economy.mood),
	})
	_acts_minute = 0

## How many items are affordable right now, and the one the HUD would point at next (the same
## rule as `HUD._pick_next`: affordable and cheapest, else whatever the purse is closest to).
func _next_item() -> Dictionary:
	var affordable := 0
	var best_id := ""
	var best_score := -1.0
	var best_ratio := 0.0
	for item in ItemDB.all_items():
		if item.cost <= 0 or not Progression.can_purchase(item.id):
			continue
		var cost := float(item.cost)
		var ratio := Economy.balance_of(item.currency_id()) / cost
		if ratio >= 1.0:
			affordable += 1
		var score := (2.0 + 1.0 / cost) if ratio >= 1.0 else minf(ratio, 0.999)
		if score > best_score:
			best_score = score
			best_id = String(item.id)
			best_ratio = ratio
	return {"affordable": affordable, "id": best_id, "ratio": snappedf(minf(best_ratio, 9.99), 0.01)}

func _start_fields() -> Dictionary:
	var screens: Array = []
	for i in DisplayServer.get_screen_count():
		var size := DisplayServer.screen_get_size(i)
		screens.append([size.x, size.y])
	var view := get_viewport().get_visible_rect().size
	return {
		"fmt": Fmt.FORMAT,
		"build": Build.id(),
		"channel": Build.channel(),
		"tester": tester_id(),
		"n": int(_state.get_value("stats", "sessions", 1)),
		"at": Time.get_datetime_string_from_system(false, false),
		"os": OS.get_name(),
		"os_ver": OS.get_version(),
		"locale": OS.get_locale(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"screens": screens,
		"monitor": Settings.monitor_id,
		"mode": _mode_name(),
		"window": [roundi(view.x), roundi(view.y)],
		"scale": Settings.ui_scale,
		"focus": int(Settings.focus_intensity),
		"backdrop": String(Settings.backdrop),
		"returning": SaveManager.has_save(),
		"own": Progression.owned_items().size(),
		"pc": Economy.prestige_count,
		"lb": roundi(Economy.lifetime_of(Economy.BONES)),
	}

func _mode_name() -> String:
	if not Settings.overlay_enabled:
		return "window"
	return "overlay" if Settings.window_mode == 0 else "play"

# --- what happened -------------------------------------------------------------

func _on_item_purchased(item_id: StringName) -> void:
	var item := ItemDB.get_item(item_id)
	record("buy", {"id": String(item_id), "cur": String(item.currency_id()) if item else "",
		"p": item.cost if item else 0})

## The price is what left the purse: the spend emitted its new balance a moment ago, so the
## difference between the last two is exactly what the levels cost, bulk discount and all.
func _on_augment_purchased(node_id: StringName, level: int) -> void:
	var node := ItemDB.get_augment(node_id)
	var currency: StringName = node.currency_id() if node else &""
	var price := float(_bal_prev.get(currency, 0.0)) - float(_bal_now.get(currency, 0.0))
	record("aug", {"id": String(node_id), "lvl": level, "cur": String(currency),
		"p": roundi(maxf(price, 0.0))})

func _on_currency_changed(currency: StringName, balance: float) -> void:
	_bal_prev[currency] = _bal_now.get(currency, balance)
	_bal_now[currency] = balance

func _on_knockout(bonus: float) -> void:
	var round_info: Dictionary = Economy.last_round
	record("ko", {"bonus": roundi(bonus), "n": int(round_info.get("number", 0)),
		"s": roundi(float(round_info.get("seconds", 0.0)))})

func _on_prestige(marrow_gained: float) -> void:
	record("rebirth", {"m": snappedf(marrow_gained, 0.01), "pc": Economy.prestige_count,
		"pers": Economy.personality})

func _on_page(panel: StringName) -> void:
	if panel == _page:
		return
	_page = panel
	record("page", {"id": String(panel)})

func current_page() -> StringName:
	return _page

func _on_item_spawned(node: Node2D) -> void:
	if node == null:
		return
	var id = node.get("item_id")
	if id != null and StringName(id) != &"":
		_first("item", StringName(id))

func _on_power(item_id: StringName) -> void:
	_power = item_id
	if item_id != &"":
		_first("power", item_id)

func _on_window() -> void:
	var view := get_viewport().get_visible_rect().size
	var key := "%s %dx%d" % [_mode_name(), roundi(view.x), roundi(view.y)]
	if key == _last_window:
		return
	_last_window = key
	record("window", {"mode": _mode_name(), "w": roundi(view.x), "h": roundi(view.y),
		"monitor": Settings.monitor_id})

## The first time this session a thing was used, and whether it was the first time ever — which
## is what "abilities discovered" means in a report. One dictionary lookup on every later call.
func _first(what: String, id: StringName, event: StringName = &"") -> void:
	var key := "%s:%s" % [what, id]
	if _first_session.has(key):
		return
	_first_session[key] = true
	_load_state()
	var ever := not _seen_ever.has(key)
	if ever:
		_seen_ever[key] = true
		_state_dirty = true
	var fields := {"what": what, "id": String(id), "ever": ever}
	if event != &"":
		fields["ev"] = String(event)
	record("first", fields)

# --- errors --------------------------------------------------------------------

func _drain_errors() -> void:
	if _catch == null:
		return
	var taken := _catch.take()
	var dropped := int(taken.pop_back())
	_error_total += dropped
	for entry in taken:
		var message := Fmt.scrub(String(entry[1]), _scrub_map()).strip_edges()
		var where := Fmt.scrub(String(entry[2]), _scrub_map())
		_error_total += 1
		var seen := int(_error_counts.get(message, 0))
		_error_counts[message] = seen + 1
		if seen > 0:
			continue
		_recent_errors.append("%s: %s (%s)" % [entry[0], message.left(200), where])
		if _recent_errors.size() > RECENT_ERRORS:
			_recent_errors.remove_at(0)
		if _error_counts.size() <= MAX_UNIQUE_ERRORS:
			record("err", {"k": String(entry[0]), "m": message.left(300), "at": where})

func error_total() -> int:
	_drain_errors()
	return _error_total

func error_counts() -> Dictionary:
	_drain_errors()
	return _error_counts

func _scrub_map() -> Dictionary:
	return {
		OS.get_user_data_dir(): "user:/",
		OS.get_executable_path().get_base_dir(): "<game>",
	}

# --- notes -------------------------------------------------------------------------

func request_feedback() -> void:
	feedback_requested.emit()

## What a note carries besides the words: taken when the card is asked for, so it describes the
## moment the player decided to say something rather than the moment they finished typing.
func snapshot_context() -> Dictionary:
	_drain_errors()
	var owned: Array = []
	for item in Progression.owned_items():
		owned.append(String(item.id))
	var desk: Array = []
	for node in get_tree().get_nodes_in_group(&"spawned_item"):
		var id = node.get("item_id")
		if id != null:
			desk.append(String(id))
	var recent: Array = []
	for line in _recent:
		recent.append(Fmt.parse_row(line))
	var view := get_viewport().get_visible_rect().size
	return {
		"page": String(_page),
		"power": String(_power),
		"idle_s": roundi(seconds_since_act()),
		"currencies": {
			"bones": roundi(Economy.balance_of(Economy.BONES)),
			"hearts": roundi(Economy.balance_of(Economy.HEARTS)),
			"dollars": roundi(Economy.balance_of(Economy.DOLLARS)),
			"marrow": snappedf(Economy.marrow, 0.01),
		},
		"owned": owned,
		"desk": desk,
		"him": {
			"mood": roundi(Economy.mood),
			"grime": snappedf(Economy.grime, 0.01),
			"state": String(_buddy_state),
			"personality": Economy.personality,
		},
		"progress": {
			"prestiges": Economy.prestige_count,
			"lifetime_bones": roundi(Economy.lifetime_of(Economy.BONES)),
			"lifetime_hearts": roundi(Economy.lifetime_of(Economy.HEARTS)),
		},
		"window": {"mode": _mode_name(), "size": [roundi(view.x), roundi(view.y)],
			"scale": Settings.ui_scale, "focus_mode": int(Settings.focus_intensity)},
		"recent": recent,
		"errors": {"total": _error_total, "recent": Array(_recent_errors)},
	}

## The window as drawn, or null where there is nothing drawn (headless). Only this game's own
## pixels: the desktop behind a transparent window is the compositor's, never in this image.
func capture_window() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var texture := get_viewport().get_texture()
	if texture == null:
		return null
	return texture.get_image()

## Writes one note as `feedback/<id>.json`, and its picture beside it. Returns the JSON's path,
## or "" if it could not be written.
func save_note(note: Dictionary, shot: Image = null) -> String:
	_ensure_dirs()
	var id := "note_%s_%04x" % [Fmt.file_stamp(Time.get_datetime_dict_from_system()), randi() & 0xffff]
	var dir := "%s/feedback" % root_dir
	var out := note.duplicate(true)
	out["format"] = Fmt.FORMAT
	out["id"] = id
	out["build"] = Build.id()
	out["tester"] = tester_id()
	out["session"] = _session_name
	out["saved_at"] = Time.get_datetime_string_from_system(false, false)
	out["session_minutes"] = snappedf(uptime_seconds() / 60.0, 0.1)
	if not out.has("context"):
		out["context"] = snapshot_context()
	out["screenshot"] = ""
	if shot != null and not shot.is_empty():
		var image := shot
		if image.get_width() > SHOT_MAX_WIDTH:
			image = shot.duplicate() as Image
			image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_NEAREST)
		if image.save_png("%s/%s.png" % [dir, id]) == OK:
			out["screenshot"] = "%s.png" % id
	var path := "%s/%s.json" % [dir, id]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Playtest: cannot write a feedback note (error %d)" % FileAccess.get_open_error())
		return ""
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	record("note", {"id": id, "mood": String(out.get("mood", ""))})
	flush()
	_prune_notes()
	notes_changed.emit()
	return path

func notes_count() -> int:
	return _files_in("%s/feedback" % root_dir, ".json").size()

# --- getting it back ---------------------------------------------------------

## Everything under the playtest folder in one zip, plus the tails of the engine's own logs —
## what a crash leaves behind is in those, not in anything this game wrote.
##
## A bundle carries everything still on disk rather than what is new since the last one. The
## report tool de-duplicates by file name, so sending twice costs nothing, and a tester who sends
## once at the end of the week and once again after has sent a superset, not a fragment.
func make_bundle(dest_dir: String) -> String:
	_drain_errors()
	flush()
	_save_state()
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var path := dest_dir.path_join("BoneheadFriend-feedback-%s-%s-%04x.zip" % [tester_id(),
		Fmt.file_stamp(Time.get_datetime_dict_from_system()), randi() & 0xffff])
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		push_warning("Playtest: cannot write a bundle")
		return ""
	var sessions := _files_in("%s/sessions" % root_dir, ".jsonl")
	var notes := _files_in("%s/feedback" % root_dir, ".json")
	for name in sessions:
		_zip_file(zip, "sessions/" + name, FileAccess.get_file_as_bytes("%s/sessions/%s" % [root_dir, name]))
	for name in _files_in("%s/feedback" % root_dir, ""):
		_zip_file(zip, "feedback/" + name, FileAccess.get_file_as_bytes("%s/feedback/%s" % [root_dir, name]))
	var logs := _engine_logs()
	for name in logs:
		_zip_file(zip, "logs/" + String(name), (logs[name] as String).to_utf8_buffer())
	var manifest := {
		"format": Fmt.FORMAT,
		"tester": tester_id(),
		"build": Build.id(),
		"made_at": Time.get_datetime_string_from_system(false, false),
		"sessions": Array(sessions),
		"notes": Array(notes),
		"logs": logs.keys(),
	}
	_zip_file(zip, "manifest.json", JSON.stringify(manifest, "\t").to_utf8_buffer())
	zip.close()
	record("bundle", {"sessions": sessions.size(), "notes": notes.size()})
	return path

func _zip_file(zip: ZIPPacker, name: String, bytes: PackedByteArray) -> void:
	zip.start_file(name)
	zip.write_file(bytes)
	zip.close_file()

## The newest few `godot*.log` files, scrubbed, each cut to its tail.
func _engine_logs() -> Dictionary:
	var out := {}
	var log_path := String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	var dir := log_path.get_base_dir()
	var names := Array(_files_in(dir, ".log")).filter(func(n: String) -> bool:
		return n.begins_with("godot"))
	# The live one has no date in its name and is the newest; the rotated ones sort by date.
	names.sort()
	names.reverse()
	if names.has("godot.log"):
		names.erase("godot.log")
		names.push_front("godot.log")
	for name in names.slice(0, ENGINE_LOGS):
		var file := FileAccess.open(dir.path_join(name), FileAccess.READ)
		if file == null:
			continue
		var length := file.get_length()
		if length > ENGINE_LOG_TAIL:
			file.seek(length - ENGINE_LOG_TAIL)
		var text := file.get_buffer(mini(length, ENGINE_LOG_TAIL)).get_string_from_utf8()
		file.close()
		out[name] = Fmt.scrub(text, _scrub_map())
	return out

## The "Send feedback" key. With no uploader it puts one zip on the Desktop and shows it; with
## one it queues the zip and sends it, and a failure stays queued for the next launch.
func send_feedback() -> Dictionary:
	if not uploads_enabled():
		var dir := send_dir
		if dir == "":
			# A Desktop that does not exist (redirected, or a locked-down account) is not a
			# reason to fail: the playtest folder is always there, and "Open folder" finds it.
			dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
			if dir == "" or not DirAccess.dir_exists_absolute(dir):
				dir = "%s/sent" % root_dir
		var path := make_bundle(dir)
		if path != "":
			_show_file(path)
			toast("Feedback saved as one zip on your Desktop. Send it however you like — thank you.")
		else:
			toast("Could not write the feedback zip.")
		notes_changed.emit()
		return {"ok": path != "", "path": path, "uploading": false}
	var queued := make_bundle(_outbox_dir())
	_prune_folder("outbox", ".zip", MAX_OUTBOX, 1 << 30, queued.get_file())
	if queued != "":
		toast("Sending feedback…")
		_upload_next()
	notes_changed.emit()
	return {"ok": queued != "", "path": queued, "uploading": queued != ""}

func open_folder() -> void:
	_ensure_dirs()
	_show_file(root_dir)

func _show_file(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))

func toast(text: String) -> void:
	if is_inside_tree():
		get_tree().call_group(&"hud", "show_toast", text, 8.0)

# --- the optional uploader ------------------------------------------------------

## `[upload] url=...` in a `playtest.cfg` beside the exe (the build script can write one), or in
## `user://playtest.cfg`. Nothing is sent anywhere without one, and the repository never holds one.
func upload_config() -> Dictionary:
	var paths: Array[String] = []
	if upload_config_path != "":
		paths.append(upload_config_path)
	else:
		paths.append(OS.get_executable_path().get_base_dir().path_join("playtest.cfg"))
		paths.append("user://playtest.cfg")
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		var url := String(cfg.get_value("upload", "url", "")).strip_edges()
		if not (url.begins_with("https://") or url.begins_with("http://")):
			continue
		return {
			"url": url,
			"format": String(cfg.get_value("upload", "format", "multipart")),
			"file_field": String(cfg.get_value("upload", "file_field", "file")),
			"header": String(cfg.get_value("upload", "header", "")),
			"auto_on_quit": bool(cfg.get_value("upload", "auto_on_quit", false)),
		}
	return {}

func uploads_enabled() -> bool:
	return not upload_config().is_empty()

func pending_uploads() -> int:
	return _outbox_files().size()

func _auto_bundle_on_quit() -> bool:
	var cfg := upload_config()
	return not cfg.is_empty() and bool(cfg["auto_on_quit"])

func _outbox_dir() -> String:
	return "%s/outbox" % root_dir

func _outbox_files() -> PackedStringArray:
	return _files_in(_outbox_dir(), ".zip")

## What the next launch does for whatever is queued, on demand.
func retry_uploads() -> void:
	_upload_next()

## One at a time, oldest first. A failure is not retried this session: the next launch tries
## again, which is gentler on a webhook than a loop.
func _upload_next() -> void:
	if _uploading != "":
		return
	var cfg := upload_config()
	var queued := _outbox_files()
	if cfg.is_empty() or queued.is_empty():
		return
	_uploading = "%s/%s" % [_outbox_dir(), queued[0]]
	var bytes := FileAccess.get_file_as_bytes(_uploading)
	var summary := "Bonehead Friend feedback — build %s, tester %s, %s" % [Build.id(), tester_id(),
		queued[0]]
	var headers := PackedStringArray()
	var body: PackedByteArray
	if String(cfg["format"]) == "json":
		headers.append("Content-Type: application/json")
		body = JSON.stringify({
			"build": Build.id(), "tester": tester_id(), "name": queued[0], "summary": summary,
			"zip_base64": Marshalls.raw_to_base64(bytes),
		}).to_utf8_buffer()
	else:
		var boundary := "BoneheadFriend%08x%08x" % [randi(), randi()]
		headers.append("Content-Type: multipart/form-data; boundary=%s" % boundary)
		body = Fmt.multipart(boundary, {"content": summary}, String(cfg["file_field"]),
			queued[0], "application/zip", bytes)
	if String(cfg["header"]) != "":
		headers.append(String(cfg["header"]))
	if _http == null:
		_http = HTTPRequest.new()
		_http.name = "PlaytestUpload"
		_http.use_threads = true
		# A web app (Apps Script) answers a POST with a redirect to its result. The POST has
		# landed by then, and following it would re-send the whole body.
		_http.max_redirects = 0
		_http.request_completed.connect(_on_upload_completed)
		add_child(_http)
	_http.timeout = upload_timeout
	var err := _http.request_raw(String(cfg["url"]), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_finish_upload(false, -err)

func _on_upload_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var answered := result == HTTPRequest.RESULT_SUCCESS or result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED
	_finish_upload(answered and ((code >= 200 and code < 300) or code == 302 or code == 303), code)

func _finish_upload(ok: bool, code: int) -> void:
	record("upload", {"ok": ok, "code": code})
	if ok:
		DirAccess.remove_absolute(_uploading)
		toast("Feedback sent — thank you.")
	else:
		toast("Could not send feedback just now. It will try again next time you start the game.")
	_uploading = ""
	notes_changed.emit()
	upload_finished.emit(ok)
	if ok:
		_upload_next()

# --- files -------------------------------------------------------------------------

func tester_id() -> String:
	_load_state()
	var id := String(_state.get_value("tester", "id", ""))
	if id == "":
		# Random, and nothing else: it groups one person's bundles in a report and cannot be
		# traced back to them. The owner knows who is who because he knows who he sent it to.
		id = "%08x" % randi()
		_state.set_value("tester", "id", id)
		_state.set_value("tester", "since", Time.get_date_string_from_system())
		_state_dirty = true
		_save_state()
	return id

func _load_state() -> void:
	if _state_loaded:
		return
	_state_loaded = true
	_state.load("%s/state.cfg" % root_dir)
	for key in _state.get_value("seen", "firsts", PackedStringArray()):
		_seen_ever[String(key)] = true

func _save_state() -> void:
	if not _state_loaded:
		return
	_state.set_value("seen", "firsts", PackedStringArray(_seen_ever.keys()))
	_ensure_dirs()
	_state.save("%s/state.cfg" % root_dir)
	_state_dirty = false

func _ensure_dirs() -> void:
	for sub in ["sessions", "feedback"]:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [root_dir, sub])

func _files_in(dir: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for name in DirAccess.get_files_at(dir):
		if suffix == "" or name.ends_with(suffix):
			out.append(name)
	out.sort()
	return out

func _prune_folder(sub: String, suffix: String, max_files: int, max_bytes: int, keep: String) -> PackedStringArray:
	var dir := "%s/%s" % [root_dir, sub]
	var entries: Array = []
	for name in _files_in(dir, suffix):
		var file := FileAccess.open("%s/%s" % [dir, name], FileAccess.READ)
		entries.append({"name": name, "size": file.get_length() if file else 0})
		if file:
			file.close()
	var plan := Fmt.prune_plan(entries, max_files, max_bytes, keep)
	for name in plan:
		DirAccess.remove_absolute("%s/%s" % [dir, name])
	return plan

## Notes are a pair: the words and the picture. The oldest pairs go together.
func _prune_notes() -> void:
	var removed := _prune_folder("feedback", ".json", MAX_NOTES, 1 << 30, "")
	for name in removed:
		var picture := "%s/feedback/%s.png" % [root_dir, name.get_basename()]
		if FileAccess.file_exists(picture):
			DirAccess.remove_absolute(picture)

## Test seam for the cap: prune the sessions folder to `max_files` and `max_bytes` now.
func prune_sessions(max_files: int, max_bytes: int) -> PackedStringArray:
	return _prune_folder("sessions", ".jsonl", max_files, max_bytes,
		_session_name + ".jsonl" if _active else "")

func _file_safe(text: String) -> String:
	var out := ""
	for c in text:
		out += c if (c.is_valid_identifier() or c.is_valid_int() or c == "-") else "-"
	return out
