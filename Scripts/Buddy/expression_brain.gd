class_name ExpressionBrain
extends Node

## What he looks like he is feeling. `IdleBrain` is what he *does* when nobody is watching;
## this is the small mind behind his face (docs/plan-expressive-buddy.md).
##
## It owns four things `Buddy` never had: one arbitrated slot for the **beat** he is playing,
## how worked up he is (**arousal**), what he is **attending** to, and how long the player has
## been **away**. Every reaction in the game is a row in `ROWS` — face, body tag, code motion,
## duration, priority, Focus gate — and a caller asks for a row by id. The brain decides
## whether it plays, how loud, and for how long, and hands the presentation to `BuddyArt`.
##
## **Beats are not states** (D36). `Buddy.state` is a public contract — Economy mints the
## knockout bonus off it, WorldFX and the idle brain read it — and nothing here ever calls
## `_set_state`. A beat is a bounded presentation overlay: it changes what he looks like, never
## what he is. The knockout is the one thing in the other direction: while the state machine
## is inside `knockout → pile → reassemble`, the slot is held at `BEAT` priority and nothing
## below it is allowed in. That reproduces the old `_in_knockout` guard without leaking the
## flag into forty call sites.
##
## **At Focus Off he reacts; he does not initiate.** A row gated `R` still plays at Off — the
## player caused it and is looking at it — but as a face and a tag only, with zero procedural
## amplitude, because `_amp()` is `Settings.intensity_scale()` and every motion multiplies by
## it. Rows gated `S`, `N`, `G` and `C` need Subtle, Normal, Normal (gaze) and Chaos.
##
## **No `_process`.** Event-driven plus one re-armed `Timer` that wakes for the next deadline
## and stops when there is none. Every deadline is `Time.get_ticks_msec()`, never a frame
## count — `Engine.max_fps` drops to 20 at idle and in Low Power.

## Priority ladder. Higher preempts. Equal preempts, except under damping.
const AMBIENT := 0
const ATTENTION := 10
const REACTION := 20
## A hit sits between a reaction and a heavy: pain reads over pleasure, so a pet landing in
## the same instant as a swing does not swap `hurt` for `happy` — and a swing landing on a
## pet does. The suite asserts both orders (plan §6.5).
const PAIN := 25
const HEAVY := 30
const BEAT := 40

## Focus gates (plan §2). `R` reactive: plays at Off as face and tag with zero motion.
const GATE_REACTIVE := &"R"
const GATE_SUBTLE := &"S"
const GATE_NORMAL := &"N"
const GATE_GAZE := &"G"
const GATE_CHAOS := &"C"

## An identical beat arriving inside this window extends the deadline and does not restart
## the animation. Without it the player sees frames 1-3 of a six-frame `hurt` forever, which
## is the defect `hurt` already had.
const DAMPING_MSEC := 180

## Arousal halves every this many seconds with nothing happening.
const AROUSAL_HALF_LIFE := 6.0

## Attention kinds.
const ATTEND_NONE := &"none"
const ATTEND_CURSOR := &"cursor"
const ATTEND_TOY := &"toy"
const ATTEND_THREAT := &"threat"

## The reaction table — plan §2, as data. Fields:
##   face      expression to wear; &"" leaves the face alone
##   tag       body animation; &"" leaves the body alone. A tag that is not drawn yet falls
##             through to `fallback` (or to nothing), so a row can be wired before its art.
##   motion    a `BuddyArt` code motion; &"" for none
##   seconds   duration when the tag is missing or &""; otherwise the tag's own length
##   tail      seconds added after the tag ends (the heavy hit's dizzy tail)
##   priority  the ladder above
##   gate      the Focus gate above
##   hold      true for a face-and-tag *hold* refreshed by a repeating signal; `refresh` is
##             how long one refresh keeps it alive (0 = until released)
##   speed     body `speed_scale` for the life of the row (holds only)
##   sound     an `AudioManager` voice, or &""
const ROWS := {
	# --- A: being hit ---
	&"hit_light": {"face": &"shocked", "tag": &"flinch", "fallback": &"hurt",
		"motion": &"impact", "seconds": 0.28, "priority": PAIN, "gate": GATE_REACTIVE},
	&"hit": {"face": &"shocked", "tag": &"hurt",
		"motion": &"impact", "seconds": 0.45, "priority": PAIN, "gate": GATE_REACTIVE},
	&"hit_heavy": {"face": &"shocked", "tag": &"hurt", "tail_face": &"dizzy",
		"motion": &"impact_wobble", "seconds": 0.45, "tail": 0.8, "priority": HEAVY,
		"gate": GATE_REACTIVE, "sound": &"oof"},
	&"hit_annoyed": {"face": &"angry", "tag": &"",
		"motion": &"", "seconds": 1.0, "priority": REACTION, "gate": GATE_REACTIVE},
	&"cooking": {"face": &"crying", "tag": &"hurt",
		"motion": &"shiver", "seconds": 0.4, "priority": PAIN, "gate": GATE_REACTIVE,
		"hold": true, "refresh": 0.4},
	&"meter_reset": {"face": &"neutral", "tag": &"happy",
		"motion": &"shake_off", "seconds": 0.5, "priority": REACTION, "gate": GATE_REACTIVE},
	# --- B: kindness ---
	&"pet": {"face": &"blissful", "tag": &"happy",
		"motion": &"hop", "seconds": 0.45, "priority": REACTION, "gate": GATE_REACTIVE},
	&"pet_combo": {"face": &"blissful", "tag": &"happy",
		"motion": &"hop", "seconds": 0.45, "priority": REACTION, "gate": GATE_REACTIVE},
	&"cared_for": {"face": &"happy", "tag": &"idle_happy",
		"motion": &"wiggle", "seconds": 0.6, "priority": REACTION, "gate": GATE_REACTIVE,
		"hold": true, "refresh": 0.6},
	&"sparkling": {"face": &"blissful", "tag": &"happy",
		"motion": &"shake_off", "seconds": 0.8, "priority": HEAVY, "gate": GATE_REACTIVE},
	&"eat": {"face": &"happy", "tag": &"eat", "fallback": &"happy",
		"motion": &"nod", "seconds": 0.6, "priority": REACTION, "gate": GATE_REACTIVE},
	&"catch": {"face": &"smug", "tag": &"catch", "fallback": &"happy",
		"motion": &"hop", "seconds": 0.7, "priority": REACTION, "gate": GATE_REACTIVE},
	&"soaking": {"face": &"blissful", "tag": &"relax", "fallback": &"idle_happy",
		"motion": &"slow_bob", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_SUBTLE,
		"hold": true, "refresh": 0.0, "speed": 0.6},
	# --- C: the cursor and the player's hands ---
	&"watched": {"face": &"neutral", "tag": &"",
		"motion": &"gaze", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_GAZE,
		"hold": true, "refresh": 0.0},
	&"harm_equipped": {"face": &"shocked", "tag": &"",
		"motion": &"lean_away", "seconds": 0.5, "priority": ATTENTION, "gate": GATE_REACTIVE},
	&"kind_equipped": {"face": &"happy", "tag": &"idle_happy",
		"motion": &"", "seconds": 0.5, "priority": ATTENTION, "gate": GATE_REACTIVE},
	&"picked_up": {"face": &"shocked", "tag": &"", "tail_face": &"neutral",
		"motion": &"", "seconds": 0.3, "tail": 0.01, "priority": REACTION, "gate": GATE_REACTIVE},
	&"held_long": {"face": &"angry", "tag": &"",
		"motion": &"kick", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_NORMAL,
		"hold": true, "refresh": 0.0},
	&"shaken": {"face": &"dizzy", "tag": &"",
		"motion": &"wobble", "seconds": 0.6, "priority": REACTION, "gate": GATE_NORMAL},
	&"landed": {"face": &"", "tag": &"",
		"motion": &"land", "seconds": 0.25, "priority": REACTION, "gate": GATE_SUBTLE,
		"sound": &"impact_soft"},
	# --- D: the world and threats ---
	&"fuse_lit": {"face": &"shocked", "tag": &"flinch", "fallback": &"",
		"motion": &"lean_away", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_REACTIVE,
		"hold": true, "refresh": 0.0, "sound": &"gasp"},
	&"blast": {"face": &"shocked", "tag": &"flinch", "fallback": &"",
		"motion": &"duck", "seconds": 0.5, "priority": ATTENTION, "gate": GATE_REACTIVE},
	&"threatened": {"face": &"shocked", "tag": &"flinch", "fallback": &"",
		"motion": &"face_toward", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_NORMAL,
		"hold": true, "refresh": 0.0},
	&"item_landed": {"face": &"neutral", "tag": &"",
		"motion": &"face_toward", "seconds": 1.2, "priority": ATTENTION, "gate": GATE_NORMAL},
	&"device_appeared": {"face": &"", "tag": &"",
		"motion": &"face_toward", "seconds": 0.4, "priority": AMBIENT, "gate": GATE_NORMAL},
	# --- E: economy and progression ---
	&"purchase": {"face": &"happy", "tag": &"happy",
		"motion": &"hop", "seconds": 0.5, "priority": ATTENTION, "gate": GATE_REACTIVE},
	&"rank_up": {"face": &"smug", "tag": &"idle_happy",
		"motion": &"puff", "seconds": 0.9, "priority": ATTENTION, "gate": GATE_REACTIVE},
	&"claimed": {"face": &"blissful", "tag": &"happy",
		"motion": &"hop2", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_REACTIVE},
	&"reincarnated": {"face": &"neutral", "tag": &"",
		"motion": &"", "seconds": 1.0, "priority": HEAVY, "gate": GATE_REACTIVE},
	&"big_payout": {"face": &"smug", "tag": &"",
		"motion": &"", "seconds": 0.4, "priority": ATTENTION, "gate": GATE_CHAOS},
	# --- F: session and desktop ---
	&"asleep": {"face": &"asleep", "tag": &"sleep", "fallback": &"idle_sad",
		"motion": &"slow_bob", "seconds": 1.0, "priority": AMBIENT, "gate": GATE_SUBTLE,
		"hold": true, "refresh": 0.0, "speed": 0.35, "sound": &"yawn"},
	&"reunion": {"face": &"shocked", "tag": &"happy", "tail_face": &"happy",
		"motion": &"hop2", "seconds": 1.2, "priority": REACTION, "gate": GATE_REACTIVE,
		"sound": &"greet"},
	&"welcome_back": {"face": &"happy", "tag": &"",
		"motion": &"gaze", "seconds": 0.4, "priority": ATTENTION, "gate": GATE_NORMAL},
	&"yawn": {"face": &"asleep", "tag": &"",
		"motion": &"", "seconds": 0.3, "priority": AMBIENT, "gate": GATE_SUBTLE,
		"sound": &"yawn"},
	&"card_opened": {"face": &"", "tag": &"",
		"motion": &"face_toward", "seconds": 0.4, "priority": AMBIENT, "gate": GATE_NORMAL},
	# --- G: the idle brain at work ---
	&"arrived": {"face": &"happy", "tag": &"",
		"motion": &"", "seconds": 0.4, "priority": ATTENTION, "gate": GATE_NORMAL},
	&"bouncing": {"face": &"happy", "tag": &"happy",
		"motion": &"", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_NORMAL,
		"hold": true, "refresh": 0.0},
	&"dancing": {"face": &"happy", "tag": &"dance", "fallback": &"idle_happy",
		"motion": &"wiggle", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_NORMAL,
		"hold": true, "refresh": 0.0},
	&"scrubbing": {"face": &"happy", "tag": &"fiddle", "fallback": &"",
		"motion": &"wiggle", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_NORMAL,
		"hold": true, "refresh": 0.0},
	&"nibbling": {"face": &"happy", "tag": &"eat", "fallback": &"",
		"motion": &"nod", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_NORMAL,
		"hold": true, "refresh": 0.0},
	&"gave_up": {"face": &"angry", "tag": &"fiddle", "fallback": &"",
		"motion": &"shiver", "seconds": 0.8, "priority": ATTENTION, "gate": GATE_NORMAL},
	&"toy_gone": {"face": &"shocked", "tag": &"",
		"motion": &"", "seconds": 0.5, "priority": ATTENTION, "gate": GATE_NORMAL},
	# --- H: ambient ---
	&"blink": {"face": &"asleep", "tag": &"",
		"motion": &"", "seconds": 0.12, "priority": AMBIENT, "gate": GATE_SUBTLE},
	&"fidget": {"face": &"", "tag": &"",
		"motion": &"fidget", "seconds": 0.6, "priority": AMBIENT, "gate": GATE_SUBTLE},
}

## The face he pulls when hit, by what hit him — keyed on category, not id, so ten entries
## cover the roster and everything added after it (D8). Categories not listed use the row's.
const HURT_FACES := {
	ItemData.CATEGORY_WEAPON: &"shocked",
	ItemData.CATEGORY_THROWABLE: &"shocked",
	ItemData.CATEGORY_CURSOR_POWER: &"angry",
	ItemData.CATEGORY_TURRET: &"angry",
	ItemData.CATEGORY_CRITTER: &"angry",
}

## Heat thresholds for the three hit rows (plan §2A).
const HEAT_LIGHT := 0.25
const HEAT_HEAVY := 0.6

const KNOCKOUT_STATES: Array[StringName] = [&"knockout", &"pile", &"reassemble"]

@export var buddy: Buddy
@export var art: BuddyArt

## The one slot. Empty when nothing is playing.
##   id, row, priority, heat, started_msec, until_msec (0 = until released)
var _beat: Dictionary = {}

var _arousal := 0.0
var _arousal_msec := 0

var _attention: StringName = ATTEND_NONE
var _attention_point := Vector2.ZERO

## When the app lost focus, in msec; 0 while it has it. The reunion beat reads it.
var _away_since := 0

## Set while the state machine is inside the knockout beat. Nothing below `BEAT` plays.
var _locked := false

## Counts every ambient beat that actually started. A member, not a local: the Focus Off
## suite asserts it stays at zero, and a GDScript lambda captures locals by value.
var ambient_starts := 0

var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "BeatTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	if art:
		art.beat_animation_finished.connect(_on_beat_animation_finished)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)

# --- asking for a beat -------------------------------------------------------

## Play a row once. `heat` is 0..1 and scales the motion; `at` is where it happened, for
## motions that lean away from or toward a point. Returns whether anything changed.
func react(row_id: StringName, heat: float = 1.0, at: Vector2 = Vector2.INF,
		face_override: StringName = &"") -> bool:
	var row: Dictionary = ROWS.get(row_id, {})
	if row.is_empty():
		push_warning("ExpressionBrain: no row '%s'" % row_id)
		return false
	return _request(row_id, row, clampf(heat, 0.0, 1.0), at, face_override)

## Keep a *hold* row alive. Repeating signals call this on every event; the first call starts
## it and each later one refreshes the deadline without restarting the animation.
func hold(row_id: StringName, at: Vector2 = Vector2.INF) -> bool:
	var row: Dictionary = ROWS.get(row_id, {})
	if row.is_empty():
		push_warning("ExpressionBrain: no row '%s'" % row_id)
		return false
	if _beat.get("id", &"") == row_id and _live():
		_refresh(row)
		return true
	return _request(row_id, row, 1.0, at, &"")

## End a hold early — the cursor left, the fuse went off, he got out of the tub.
func release(row_id: StringName) -> void:
	if _beat.get("id", &"") == row_id:
		_end_beat()

## Drop whatever is playing.
func clear() -> void:
	if not _beat.is_empty():
		_end_beat()

## The hit rows, chosen by heat, with the face by category. One call from `Buddy._deal`.
func react_to_hit(info: HitInfo) -> bool:
	var full := maxf(1.0, ItemDB.balance.hit_stop_full_damage)
	var heat := clampf(info.amount / full, 0.0, 1.0)
	var face: StringName = &""
	var item := ItemDB.get_item(info.source_id)
	if item and HURT_FACES.has(item.category):
		face = HURT_FACES[item.category]
	if heat < HEAT_LIGHT:
		return react(&"hit_light", heat, info.position, face)
	if heat > HEAT_HEAVY:
		return react(&"hit_heavy", heat, info.position)
	return react(&"hit", heat, info.position, face)

# --- reading him -------------------------------------------------------------

func beat_active() -> bool:
	return _live()

func beat_id() -> StringName:
	return _beat.get("id", &"") if _live() else &""

func beat_priority() -> int:
	return int(_beat.get("priority", -1)) if _live() else -1

## 0..1, decaying. Bumped by every beat in proportion to its priority.
func arousal() -> float:
	if _arousal <= 0.0:
		return 0.0
	var elapsed := float(Time.get_ticks_msec() - _arousal_msec) / 1000.0
	return _arousal * pow(0.5, elapsed / AROUSAL_HALF_LIFE)

func attention() -> StringName:
	return _attention

func attention_point() -> Vector2:
	return _attention_point

## What he is looking at. `ATTEND_NONE` clears it.
func attend(kind: StringName, point: Vector2 = Vector2.ZERO) -> void:
	_attention = kind
	_attention_point = point

## Told by `Buddy` when the app gains or loses focus.
func notice_focus(has_focus: bool) -> void:
	if has_focus:
		_away_since = 0
	elif _away_since == 0:
		_away_since = Time.get_ticks_msec()

func away_seconds() -> float:
	if _away_since == 0:
		return 0.0
	return float(Time.get_ticks_msec() - _away_since) / 1000.0

## Inside the knockout beat, nothing below `BEAT` plays. Read off his real state when he is
## there to ask, so a stray `buddy_state_changed` on the bus — a test emits one without ever
## emitting the idle that follows — cannot leave him locked for the rest of the session.
func is_locked() -> bool:
	if buddy:
		return KNOCKOUT_STATES.has(buddy.state)
	return _locked

# --- Focus Mode (D36) --------------------------------------------------------

## Procedural amplitude. 0.0 / 0.4 / 1.0 / 1.6 — reused from `Settings` rather than a third
## ladder. Zero at Off is what makes "he reacts; he does not initiate" arithmetic.
func _amp() -> float:
	return Settings.intensity_scale()

## Whether he may start anything the player did not just cause.
func _initiates() -> bool:
	return Settings.focus_intensity != Settings.Intensity.OFF

## Gaze has its own gate: looking at the cursor is the most attention-grabbing thing a desktop
## character can do, and this game refuses to be Desktop Goose by default.
func _may_gaze() -> bool:
	return Settings.focus_intensity >= Settings.Intensity.NORMAL

func _passes_gate(row: Dictionary) -> bool:
	match row.get("gate", GATE_REACTIVE):
		GATE_REACTIVE: return true
		GATE_SUBTLE: return _initiates()
		GATE_NORMAL: return _may_gaze()
		GATE_GAZE: return _may_gaze()
		GATE_CHAOS: return Settings.focus_intensity == Settings.Intensity.CHAOS
	return true

# --- the slot ----------------------------------------------------------------

func _request(row_id: StringName, row: Dictionary, heat: float, at: Vector2,
		face_override: StringName) -> bool:
	if art == null:
		return false
	if not _passes_gate(row):
		return false
	var priority := int(row.get("priority", REACTION))
	if is_locked() and priority < BEAT:
		return false
	var now := Time.get_ticks_msec()
	if _live():
		var current := int(_beat.get("priority", -1))
		if current > priority:
			return false
		if _beat.get("id", &"") == row_id:
			# Same beat again. Inside the damping window a lighter or equal one only extends
			# the deadline; a heavier one escalates and restarts.
			if now - int(_beat.get("started_msec", 0)) < DAMPING_MSEC \
					and heat <= float(_beat.get("heat", 0.0)):
				_refresh(row)
				return true
		if int(row.get("priority", 0)) == AMBIENT and current == AMBIENT:
			# One fidget does not interrupt another.
			return false
	if priority == AMBIENT and not _initiates():
		return false

	var face: StringName = face_override if face_override != &"" else row.get("face", &"")
	var tag := _resolve_tag(row)
	var seconds := _duration(row, tag)
	var hold := bool(row.get("hold", false))
	var tail := float(row.get("tail", 0.0))
	var until := 0
	if hold:
		var refresh := float(row.get("refresh", 0.0))
		until = now + int(refresh * 1000.0) if refresh > 0.0 else 0
	else:
		until = now + int(seconds * 1000.0)
	_beat = {
		"id": row_id, "row": row, "priority": priority, "heat": heat,
		"started_msec": now, "until_msec": until, "tag": tag,
		# A row with a tail changes face partway: the heavy hit is `shocked` for the tag and
		# `dizzy` for the 0.8 s after it. `tail_at_msec` is when; 0 means no tail or done.
		"tail_at_msec": now + int((seconds - tail) * 1000.0) if tail > 0.0 else 0,
	}
	art.play_beat(tag, face, seconds, _amp(), row.get("motion", &""), heat, at,
		float(row.get("speed", 1.0)))
	var sound: StringName = row.get("sound", &"")
	if sound != &"":
		AudioManager.play(sound, 0.08, -8.0)
	if priority == AMBIENT:
		ambient_starts += 1
	_bump_arousal(priority)
	_arm()
	return true

func _refresh(row: Dictionary) -> void:
	var refresh := float(row.get("refresh", 0.0))
	if bool(row.get("hold", false)):
		if refresh > 0.0:
			_beat["until_msec"] = Time.get_ticks_msec() + int(refresh * 1000.0)
	else:
		# A damped repeat of a one-shot: keep it alive for one more full duration.
		var seconds := _duration(row, _beat.get("tag", &""))
		_beat["until_msec"] = Time.get_ticks_msec() + int(seconds * 1000.0)
	_arm()

func _end_beat() -> void:
	if _beat.is_empty():
		return
	_beat = {}
	if art:
		art.clear_beat()
	_arm()

## The face he settles on partway through a row that has one: the heavy hit's dizzy tail,
## the neutral he adopts once being picked up stops being a surprise.
func _enter_tail() -> void:
	_beat["tail_at_msec"] = 0
	var row: Dictionary = _beat.get("row", {})
	var tail_face: StringName = row.get("tail_face", &"")
	if tail_face != &"" and art:
		art.hold_face(tail_face, int(_beat.get("until_msec", 0)))

func _live() -> bool:
	if _beat.is_empty():
		return false
	var until := int(_beat.get("until_msec", 0))
	return until == 0 or Time.get_ticks_msec() < until

## The tag the row will actually play: its own if drawn, its fallback if not, else nothing.
func _resolve_tag(row: Dictionary) -> StringName:
	var tag: StringName = row.get("tag", &"")
	if tag == &"":
		return &""
	if art and art.has_animation(tag):
		return tag
	var fallback: StringName = row.get("fallback", &"")
	if fallback != &"" and art and art.has_animation(fallback):
		return fallback
	return &""

## The tag's own length when it has one, the row's fallback when it does not — `_beat_time`'s
## pattern from the knockout — plus any tail the row asks for.
func _duration(row: Dictionary, tag: StringName) -> float:
	var seconds := float(row.get("seconds", 0.45))
	if tag != &"" and art:
		var length := art.animation_length(tag)
		# Looping tags (idle_happy, the holds) report their loop length; that is the right
		# refresh unit for a hold and the right minimum for a one-shot row that borrowed one.
		if length > 0.0:
			seconds = length
	return seconds + float(row.get("tail", 0.0))

func _bump_arousal(priority: int) -> void:
	var current := arousal()
	_arousal = clampf(current + float(priority) / float(BEAT) * 0.5, 0.0, 1.0)
	_arousal_msec = Time.get_ticks_msec()

# --- the timer ---------------------------------------------------------------

## One timer, re-armed to the next deadline, stopped when there is none. Strictly cheaper
## than a `_process`: at true idle nothing here runs at all.
func _arm() -> void:
	var next := _next_deadline_msec()
	if next <= 0:
		_timer.stop()
		return
	var wait := float(next - Time.get_ticks_msec()) / 1000.0
	_timer.start(maxf(wait, 0.01))

func _next_deadline_msec() -> int:
	if _beat.is_empty():
		return 0
	var until := int(_beat.get("until_msec", 0))
	var tail_at := int(_beat.get("tail_at_msec", 0))
	if tail_at > 0 and (until == 0 or tail_at < until):
		return tail_at
	return until

func _on_timer() -> void:
	if _beat.is_empty():
		return
	if not _live():
		_end_beat()
		return
	var tail_at := int(_beat.get("tail_at_msec", 0))
	if tail_at > 0 and Time.get_ticks_msec() >= tail_at:
		_enter_tail()
	_arm()

## A one-shot row whose tag has finished is over, whatever `animation_length` estimated —
## unless it is a hold, or it asked for a tail, in which case the tail starts now.
func _on_beat_animation_finished(tag: StringName) -> void:
	if _beat.is_empty() or _beat.get("tag", &"") != tag:
		return
	var row: Dictionary = _beat.get("row", {})
	if bool(row.get("hold", false)):
		return
	if int(_beat.get("tail_at_msec", 0)) > 0:
		_enter_tail()
		_arm()
		return
	if float(row.get("tail", 0.0)) > 0.0:
		return
	_end_beat()

# --- the knockout lock -------------------------------------------------------

func _on_buddy_state_changed(state: StringName) -> void:
	var inside := KNOCKOUT_STATES.has(state)
	_locked = inside
	# The beat owns him completely: whatever was playing stops so the collapse reads.
	if inside and not _beat.is_empty():
		_beat = {}
		if art:
			art.clear_beat()
		_arm()
