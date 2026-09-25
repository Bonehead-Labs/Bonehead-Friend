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
## and stops when there is none. Every deadline is `_now()`, never a frame
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
		"motion": &"wiggle", "seconds": 0.6, "priority": ATTENTION, "gate": GATE_REACTIVE,
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
		"motion": &"", "seconds": 1.0, "priority": ATTENTION, "gate": GATE_GAZE,
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
		"hold": true, "refresh": 1.0},
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

## The brain's clock. Every deadline is milliseconds off this, never a frame count —
## `Engine.max_fps` drops to 20 at idle and in Low Power. `_clock_skew` exists for the suites:
## a test that wants him held for six seconds advances the clock rather than winding a
## timestamp back past zero, which a process a few seconds old cannot survive.
var _clock_skew := 0

func _now() -> int:
	return Time.get_ticks_msec() + _clock_skew

var _timer: Timer

## Hits per source inside `ANNOYED_WINDOW`: source_id -> [count, first_msec, last_msec]. The
## fifth from one source in three seconds earns `angry` on the settle; a cursor power ticking
## faster than `COOKING_GAP` is being cooked rather than hit.
var _hits: Dictionary = {}
var _annoyed_pending := false
const ANNOYED_WINDOW_MSEC := 3000
const ANNOYED_HITS := 5
const COOKING_GAP_MSEC := 400
const HITS_SWEEP_AT := 32

var _last_grime := 0.0

## Drag ladder: when he was picked up (0 = not held), and when being held becomes annoying.
var _drag_since := 0
const HELD_LONG_MSEC := 6000

## Sleep: unfocused this long and he nods off; back after this long and he greets you.
var _sleep_at := 0
const SLEEP_AFTER_MSEC := 90000
const REUNION_AFTER_MSEC := 60000

## Payouts at or above this tier (FXLayer's log10 ladder) get the smug face — at Chaos only.
const BIG_PAYOUT_TIER := 4

func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "BeatTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	if art:
		art.beat_animation_finished.connect(_on_beat_animation_finished)
	if buddy and buddy.drag_area:
		buddy.drag_area.hover_changed.connect(_on_hover_changed)

	# Every connect in one place, and asserted one at a time in loop_check's "expression"
	# suite — CLAUDE.md's own scar is four `connect()` calls stranded after a `return`.
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)
	# A — being hit
	EventBus.damage_dealt.connect(_on_damage_dealt)
	# B — kindness
	EventBus.kindness_given.connect(_on_kindness_given)
	EventBus.kindness_sustained.connect(_on_kindness_sustained)
	EventBus.grime_changed.connect(_on_grime_changed)
	# C — the cursor
	EventBus.cursor_power_changed.connect(_on_cursor_power_changed)
	# E — economy and progression
	EventBus.item_purchased.connect(_on_item_purchased)
	EventBus.mastery_rank_up.connect(_on_mastery_rank_up)
	EventBus.contract_claimed.connect(_on_contract_claimed)
	Milestones.milestone_claimed.connect(_on_milestone_claimed)
	EventBus.prestige_performed.connect(_on_prestige_performed)
	EventBus.payout.connect(_on_payout)
	# F — the desktop
	EventBus.ui_panel_changed.connect(_on_ui_panel_changed)
	# D — the world and threats
	EventBus.threat_changed.connect(_on_threat_changed)
	EventBus.item_spawned.connect(_on_item_spawned)
	EventBus.automation_toggled.connect(_on_automation_toggled)
	# G — the idle brain, installed by main.gd after the buddy, so found a frame later.
	_connect_idle_brain.call_deferred()
	# H — posture
	EventBus.mood_changed.connect(_on_mood_changed)
	EventBus.focus_mode_changed.connect(_on_focus_mode_changed)
	if buddy and buddy.health:
		buddy.health.damaged.connect(_on_health_damaged)
		buddy.health.meter_reset.connect(_on_meter_reset)
	# Who he is this life, and again after every Reincarnation.
	EventBus.prestige_performed.connect(_on_prestige_reroll)
	_load_personality()
	_on_mood_changed(Economy.mood)
	_schedule_blink()
	_schedule_fidget()
	_arm()

# --- D: the world and threats -------------------------------------------------------

## Only threats near him count: a mine armed on the far side of an ultrawide is not his.
const THREAT_RANGE := 420.0

func _on_threat_changed(kind: StringName, world_pos: Vector2, level: float) -> void:
	if buddy == null or buddy.global_position.distance_to(world_pos) > THREAT_RANGE:
		return
	# The Nervous one reacts to the wind-up, not the blow: a real flinch at the tell, where
	# everyone else only watches it.
	if level > 0.0 and flinches_early():
		react(&"hit_light", 0.4, world_pos)
	match kind:
		&"fuse":
			if level > 0.0:
				attend(ATTEND_THREAT, world_pos)
				hold(&"fuse_lit", world_pos)
			else:
				release(&"fuse_lit")
				if _attention == ATTEND_THREAT:
					attend(ATTEND_NONE)
				react(&"blast", 1.0, world_pos)
		&"windup":
			if level > 0.0:
				hold(&"threatened", world_pos)
			else:
				release(&"threatened")
		&"turret":
			# Fires on a schedule; the row's own refresh lets it lapse a second after the last shot.
			hold(&"threatened", world_pos)

func _on_item_spawned(item: Node2D) -> void:
	if item and buddy and item.global_position.distance_to(buddy.global_position) <= THREAT_RANGE:
		react(&"item_landed", 1.0, item.global_position)

func _on_automation_toggled(_node_id: StringName, enabled: bool) -> void:
	if enabled:
		react(&"device_appeared")

# --- G: the idle brain at work -------------------------------------------------------

var _idle_brain: IdleBrain
## The routine hold in force, so a phase change can release exactly it — and so any beat that
## interrupts it hands back to it when it ends (see `_end_beat`).
var _routine_hold: StringName = &""
## The toy that routine is with. Its own payments are the routine, not a separate kindness.
var _routine_toy: StringName = &""
## A hold to start once the current one-shot ends: `arrived` then the routine, `welcome_back`
## then `watched`. Equal priorities would otherwise let the hold cut the greeting short.
var _pending_hold: StringName = &""
## The player has been away from him this long before a return is worth a greeting or he
## is bored enough to yawn.
const QUIET_SECONDS := 25.0
var _yawned := false

const ROUTINE_HOLDS := {
	IdleBrain.ROUTINE_BOUNCE: &"bouncing",
	IdleBrain.ROUTINE_PLAY: &"dancing",
	IdleBrain.ROUTINE_SOAK: &"soaking",
	IdleBrain.ROUTINE_SCRUB: &"scrubbing",
	IdleBrain.ROUTINE_NIBBLE: &"nibbling",
}

func _connect_idle_brain() -> void:
	if is_instance_valid(_idle_brain) or not is_inside_tree():
		return
	_idle_brain = get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	if _idle_brain == null:
		return
	_idle_brain.phase_changed.connect(_on_phase_changed)
	_idle_brain.routine_ended.connect(_on_routine_ended)

func _on_phase_changed(phase: StringName, routine: int, target_id: StringName) -> void:
	if phase == IdleBrain.PHASE_PLAYING:
		var row: StringName = ROUTINE_HOLDS.get(routine, &"")
		if row == &"":
			return
		_routine_toy = target_id
		# The player's cursor over him outranks his toy: he is being looked at.
		if _attention != ATTEND_CURSOR:
			attend(ATTEND_TOY, _attention_point)
		# Pleased to be there first, then settle into it.
		if react(&"arrived"):
			_pending_hold = row
		else:
			hold(row)
		_routine_hold = row
		return
	if _routine_hold != &"":
		# Cleared before the release, so ending it does not hand straight back to it.
		var ending := _routine_hold
		_routine_hold = &""
		_routine_toy = &""
		release(ending)
	_pending_hold = &""
	if _attention == ATTEND_TOY:
		attend(ATTEND_NONE)

func _on_routine_ended(reason: StringName) -> void:
	match reason:
		&"stalled":
			react(&"gave_up")
		&"toy_gone":
			react(&"toy_gone")

func _quiet_seconds() -> float:
	return _idle_brain.seconds_since_disturbance() if is_instance_valid(_idle_brain) else 0.0

# --- H: ambient and posture ----------------------------------------------------------

var _blink_at := 0
var _fidget_at := 0
const BLINK_MIN_MSEC := 4000
const BLINK_MAX_MSEC := 9000
## Default fidget period; personality overrides it in Phase 2. Halved in the mood trough and
## shortened by arousal.
const FIDGET_PERIOD := 12.0
## The mood-trough posture: within this of zero he slows, slouches and fidgets twice as often,
## because at mood 0 he otherwise *looks* fine while earning 0.6x (D15).
const TROUGH_MOOD := 15.0
const TROUGH_SPEED := 0.7
const TROUGH_SLOUCH_DEG := 2.0
var _in_trough := false
## Two things that bias his idle toward `idle_sad` without touching mood: a knockout meter
## past 80% and grime past half.
const METER_SAD_FRACTION := 0.8
const GRIME_SAD_STAGE := 0.5
var _meter_sad := false
var _grime_sad := false
## Airborne stretch, cached so the physics tick writes the art only when it changes.
var _stretch := 0.0

func _schedule_blink() -> void:
	_blink_at = _now() + randi_range(BLINK_MIN_MSEC, BLINK_MAX_MSEC)

func _schedule_fidget() -> void:
	var base := fidget_period()
	if base <= 0.0:
		# A personality that never fidgets. Far enough that the timer never wakes for it.
		_fidget_at = _now() + 3600 * 1000
		return
	var period := base * (0.5 if _in_trough else 1.0) / (1.0 + arousal())
	_fidget_at = _now() + int(period * 1000.0)

## Whether an ambient beat may start at all: he initiates, he is idle, not held, not away,
## and not inside the knockout.
func _ambient_allowed() -> bool:
	if not _initiates() or _drag_since > 0 or _away_since > 0 or is_locked():
		return false
	return buddy == null or buddy.state == &"idle"

func _tick_ambient(now: int) -> void:
	if not _ambient_allowed():
		return
	# Idle long enough to be bored: one yawn per quiet spell.
	var quiet := _quiet_seconds()
	if quiet < QUIET_SECONDS:
		_yawned = false
	elif not _yawned:
		_yawned = true
		if react(&"yawn"):
			return
	if now >= _fidget_at:
		_schedule_fidget()
		react(&"fidget")
	elif now >= _blink_at:
		_schedule_blink()
		react(&"blink")

func _on_mood_changed(value: float) -> void:
	_in_trough = absf(value) < TROUGH_MOOD
	_apply_posture()

func _on_focus_mode_changed(_level: int) -> void:
	_apply_posture()
	_arm()

func _on_health_damaged(_amount: float, _total: float) -> void:
	var sad := buddy != null and buddy.health != null \
		and buddy.health.fill_fraction() > METER_SAD_FRACTION
	if sad != _meter_sad:
		_meter_sad = sad
		_apply_posture()

func _on_meter_reset() -> void:
	if _meter_sad:
		_meter_sad = false
		_apply_posture()

## Posture is continuous and ambient, so it is gated like one: at Off he stands as drawn.
func _apply_posture() -> void:
	if art == null:
		return
	var on := _initiates()
	art.set_posture(TROUGH_SPEED if on and _in_trough else 1.0,
		TROUGH_SLOUCH_DEG if on and _in_trough else 0.0)
	art.posture_bias = &"idle_sad" if on and (_meter_sad or _grime_sad) else &""

## Off the buddy's physics tick: stretched along his fall while airborne, nothing on the
## ground. Written to the art only when the value moves, so a resting body costs nothing.
func notice_airborne(airborne: bool, velocity: Vector2) -> void:
	var k := 0.0
	if airborne:
		k = clampf((velocity.length() - 300.0) / 1200.0, 0.0, 1.0) * 0.12 * _amp()
	if absf(k - _stretch) < 0.005:
		return
	_stretch = k
	if art:
		art.set_stretch(k)

# --- A: being hit --------------------------------------------------------------

func _on_damage_dealt(info: HitInfo) -> void:
	var now := _now()
	var entry: Array = _hits.get(info.source_id, [0, now, 0])
	if now - int(entry[1]) > ANNOYED_WINDOW_MSEC:
		entry = [0, now, 0]
	var gap := now - int(entry[2]) if int(entry[2]) > 0 else ANNOYED_WINDOW_MSEC
	entry[0] = int(entry[0]) + 1
	entry[2] = now
	if _hits.size() >= HITS_SWEEP_AT:
		_sweep_hits(now)
	_hits[info.source_id] = entry
	if int(entry[0]) >= ANNOYED_HITS:
		_annoyed_pending = true
		entry[0] = 0
		entry[1] = now

	# A cursor power ticking at 4 Hz is cooking him, not hitting him: one held face, a shiver,
	# not a hurt restarted four times a second.
	var item := ItemDB.get_item(info.source_id)
	if item and item.category == ItemData.CATEGORY_CURSOR_POWER and gap < COOKING_GAP_MSEC:
		hold(&"cooking", info.position)
		return
	react_to_hit(info)

func _sweep_hits(now: int) -> void:
	for key in _hits.keys():
		if now - int(_hits[key][2]) > ANNOYED_WINDOW_MSEC:
			_hits.erase(key)

# --- B: kindness ----------------------------------------------------------------

func _on_kindness_given(source_id: StringName, _value: float, world_pos: Vector2) -> void:
	var item := ItemDB.get_item(source_id)
	if item and item.category == ItemData.CATEGORY_FOOD:
		react(&"eat", 1.0, world_pos)
		return
	if item and item.category == ItemData.CATEGORY_TOY:
		# Something thrown that he got to: the ball, the popper, the kite string.
		react(&"catch", 1.0, world_pos)
		return
	var combo := Economy.kindness_combo()
	if combo >= 3:
		react(&"pet_combo", clampf(0.5 + float(combo) / 12.0, 0.0, 1.0), world_pos)
	else:
		react(&"pet", 0.5, world_pos)

## How far off his rect a sustained payment may land and still be kindness *to him*.
const CARE_REACH := 24.0

## The sponge, the hot tub, the beanbag he is sat in: kindness that lands on him.
##
## **Only on him** (D60). A generator's placed rate is banked where the generator stands and
## flushed every half second for as long as it is on the desk. That is income, not somebody
## being kind to him — and holding `cared_for` on it meant one boombox anywhere on the desk
## kept him in it for the rest of the session: no mood face, no blink, no fidget, no yawn, and
## no routine of his own, because every one of those sits at or below this row's priority.
func _on_kindness_sustained(source_id: StringName, _value: float, world_pos: Vector2) -> void:
	if buddy and not buddy.get_interaction_rect().grow(CARE_REACH).has_point(world_pos):
		return
	# The toy he is playing with paying him *is* the routine, and the routine has a look of its
	# own: the soak, the dance, the scrub. `cared_for` flushed over it twice a second and he
	# wore the generic face for every routine in the game.
	if _routine_hold != &"" and source_id == _routine_toy:
		return
	# A trickle never cuts a one-shot of its own rank short — the surprise of a toy vanishing
	# under him was replaced by the last flush off that same toy on its way out. The next flush
	# is half a second away and picks it up if the kindness is still coming.
	if _live() and not bool(_beat.get("row", {}).get("hold", false)) \
			and beat_priority() >= int(ROWS[&"cared_for"].get("priority", ATTENTION)):
		return
	hold(&"cared_for", world_pos)

func _on_grime_changed(value: float) -> void:
	if is_zero_approx(value) and _last_grime > 0.0:
		react(&"sparkling")
	_last_grime = value
	var sad := value >= GRIME_SAD_STAGE
	if sad != _grime_sad:
		_grime_sad = sad
		_apply_posture()

# --- C: the cursor and the player's hands -----------------------------------------

## The cursor left the window entirely, which sends no `mouse_exited`. From the buddy's
## `NOTIFICATION_WM_MOUSE_EXIT`, the way the hover drawers already handle it.
func notice_hover(hovered: bool) -> void:
	_on_hover_changed(hovered)

func _on_hover_changed(hovered: bool) -> void:
	if hovered:
		attend(ATTEND_CURSOR, _attention_point)
		# Back after a quiet spell: pleased first, then the watching.
		if _quiet_seconds() >= QUIET_SECONDS and react(&"welcome_back"):
			_pending_hold = &"watched"
		else:
			hold(&"watched")
	else:
		if _pending_hold == &"watched":
			_pending_hold = &""
		if _attention == ATTEND_CURSOR:
			attend(ATTEND_NONE)
		release(&"watched")
		if art:
			art.look(0.0)

## Where the cursor is, from the buddy's own `InputEventMouseMotion` — never polled. The gaze
## is a lean of two pixels toward it, Normal and above, and he never chases (D36).
func notice_cursor(world_pos: Vector2) -> void:
	if _attention != ATTEND_CURSOR:
		return
	_attention_point = world_pos
	if art == null or buddy == null:
		return
	if not _may_gaze():
		art.look(0.0)
		return
	var dx := world_pos.x - buddy.global_position.x
	art.look(signf(dx) * 2.0 * _amp() if absf(dx) > 4.0 else 0.0)

func _on_cursor_power_changed(item_id: StringName) -> void:
	var item := ItemDB.get_item(item_id)
	if item == null:
		return
	react(&"kind_equipped" if item.is_kind() else &"harm_equipped")

## Picked up and put down, from `Buddy._start_drag` / `_end_drag`.
func notice_drag(held: bool) -> void:
	if held:
		_drag_since = _now()
		react(&"picked_up")
	else:
		_drag_since = 0
		release(&"held_long")
	_arm()

## Flung about while held, from the buddy's physics tick. Damping keeps it to one wobble.
func notice_shake() -> void:
	if _drag_since > 0:
		react(&"shaken")

## Came down hard after a drop or a fall, from `_integrate_forces`.
func notice_landing(speed: float) -> void:
	react(&"landed", clampf(speed / 900.0, 0.0, 1.0))

# --- E: economy and progression ------------------------------------------------------

func _on_item_purchased(_item_id: StringName) -> void:
	react(&"purchase")

func _on_mastery_rank_up(_item_id: StringName, _rank: int) -> void:
	react(&"rank_up")

func _on_contract_claimed(_contract_id: StringName, _dollars: int) -> void:
	react(&"claimed")

func _on_milestone_claimed(_id: StringName, _rungs: int, _dollars: int) -> void:
	react(&"claimed")

func _on_prestige_performed(_marrow: float) -> void:
	react(&"reincarnated")

func _on_payout(_currency: StringName, amount: float, _world_pos: Vector2, _source_id: StringName) -> void:
	# The cheap test first: this fires on every hit and every pet.
	if Settings.focus_intensity != Settings.Intensity.CHAOS or amount < 1.0:
		return
	if int(floor(log(amount) / log(10.0))) >= BIG_PAYOUT_TIER:
		react(&"big_payout")

# --- F: session and desktop ------------------------------------------------------------

func _on_ui_panel_changed(panel: StringName) -> void:
	if panel != &"":
		react(&"card_opened")

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
	# A category face that is the generic one says nothing about the source, and passed as an
	# override it locked the personality out: the Masochist's grin, the Diva's glare and the
	# Stone's straight face never once showed for a bat, which is what everybody hits him with
	# (D60). Only a face that is a statement of its own — a power's `angry` — outranks the tell.
	if face == GENERIC_HURT:
		face = &""
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
	var elapsed := float(_now() - _arousal_msec) / 1000.0
	return _arousal * pow(0.5, elapsed / AROUSAL_HALF_LIFE)

func attention() -> StringName:
	return _attention

func attention_point() -> Vector2:
	return _attention_point

## What he is looking at. `ATTEND_NONE` clears it.
func attend(kind: StringName, point: Vector2 = Vector2.ZERO) -> void:
	_attention = kind
	_attention_point = point

## Told by `Buddy` when the app gains or loses focus. Away, arousal drops to nothing, the
## gaze lets go and a sleep deadline is set; back after more than a minute, he greets you.
func notice_focus(has_focus: bool) -> void:
	var now := _now()
	if has_focus:
		var away := now - _away_since if _away_since > 0 else 0
		_away_since = 0
		_sleep_at = 0
		release(&"asleep")
		if away >= REUNION_AFTER_MSEC:
			react(&"reunion")
	elif _away_since == 0:
		_away_since = now
		_arousal = 0.0
		_sleep_at = now + SLEEP_AFTER_MSEC
		if art:
			art.look(0.0)
	_arm()

func away_seconds() -> float:
	if _away_since == 0:
		return 0.0
	return float(_now() - _away_since) / 1000.0

## Inside the knockout beat, nothing below `BEAT` plays. Read off his real state when he is
## there to ask, so a stray `buddy_state_changed` on the bus — a test emits one without ever
## emitting the idle that follows — cannot leave him locked for the rest of the session.
func is_locked() -> bool:
	if buddy:
		return KNOCKOUT_STATES.has(buddy.state)
	return _locked

# --- Focus Mode (D36) --------------------------------------------------------

## Procedural amplitude. 0.0 / 0.4 / 1.0 / 1.6 — reused from `Settings` rather than a third
## ladder — times the personality's own amplitude, which multiplies motion and never a payout
## (D19). Zero at Off is what makes "he reacts; he does not initiate" arithmetic.
func _amp() -> float:
	var own := _personality.reaction_amplitude if _personality else 1.0
	return Settings.intensity_scale() * own

# --- personality on the surface --------------------------------------------------------

## Who he is this life (docs/plan-expressive-buddy.md §5). Read off `Economy.personality`
## here and again on every Reincarnation; the tell is four fields on the resource and touches
## no number.
var _personality: PersonalityData

func _load_personality() -> void:
	_personality = ItemDB.get_personality(StringName(Economy.personality))
	if art:
		art.face_swaps = _personality.face_swaps if _personality else {}
	_schedule_fidget()

func _on_prestige_reroll(_marrow: float) -> void:
	_load_personality()

## The rows that mean "he was hit" and the rows that mean "something good happened", whose
## *generic* face the personality may replace — `shocked` for a hit, `happy` for a celebration.
## A row that already says something specific keeps it: a cursor power's `angry`, the beam's
## `crying`, a rank up's `smug` are more specific statements than the tell.
const HIT_ROWS: Array[StringName] = [&"hit_light", &"hit", &"hit_heavy"]
const CELEBRATION_ROWS: Array[StringName] = [&"purchase", &"rank_up", &"claimed", &"sparkling"]
const GENERIC_HURT := &"shocked"
const GENERIC_JOY := &"happy"

func _personality_face(row_id: StringName, face: StringName, overridden: bool) -> StringName:
	if _personality == null or overridden:
		return face
	if HIT_ROWS.has(row_id) and face == GENERIC_HURT and _personality.hurt_face != &"":
		return _personality.hurt_face
	if CELEBRATION_ROWS.has(row_id) and face == GENERIC_JOY and _personality.celebration_face != &"":
		return _personality.celebration_face
	return face

func fidget_period() -> float:
	return _personality.fidget_period if _personality else FIDGET_PERIOD

func flinches_early() -> bool:
	return _personality != null and _personality.flinches_early

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
	var now := _now()
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
	face = _personality_face(row_id, face, face_override != &"")
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
			_beat["until_msec"] = _now() + int(refresh * 1000.0)
	else:
		# A damped repeat of a one-shot: keep it alive for one more full duration.
		var seconds := _duration(row, _beat.get("tag", &""))
		_beat["until_msec"] = _now() + int(seconds * 1000.0)
	_arm()

func _end_beat() -> void:
	if _beat.is_empty():
		return
	var ended: StringName = _beat.get("id", &"")
	_beat = {}
	if art:
		art.clear_beat()
	# The fifth hit from one source earns `angry` on the settle, not on the hit.
	if _annoyed_pending:
		_annoyed_pending = false
		react(&"hit_annoyed")
		return
	# A hold that was waiting its turn behind a one-shot.
	if _pending_hold != &"":
		var row := _pending_hold
		_pending_hold = &""
		if hold(row):
			return
	# The routine he is in is his background. Whatever interrupted it — a landing on the
	# trampoline, a hit off the mat, a pet — he goes back to it once that is over; before this,
	# the first landing ended the bounce look for the rest of the dwell (D60).
	if _routine_hold != &"" and ended != _routine_hold and hold(_routine_hold):
		return
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
	return until == 0 or _now() < until

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
	_arousal_msec = _now()

# --- the timer ---------------------------------------------------------------

## One timer, re-armed to the next deadline, stopped when there is none. Strictly cheaper
## than a `_process`: at true idle nothing here runs at all.
func _arm() -> void:
	var next := _next_deadline_msec()
	if next <= 0:
		_timer.stop()
		return
	var wait := float(next - _now()) / 1000.0
	_timer.start(maxf(wait, 0.01))

## The soonest of: the beat's end, its face change, being held too long, falling asleep.
func _next_deadline_msec() -> int:
	var next := 0
	if not _beat.is_empty():
		next = _soonest(next, int(_beat.get("until_msec", 0)))
		next = _soonest(next, int(_beat.get("tail_at_msec", 0)))
	if _drag_since > 0 and _beat.get("id", &"") != &"held_long":
		next = _soonest(next, _drag_since + HELD_LONG_MSEC)
	if _away_since > 0 and _sleep_at > 0:
		next = _soonest(next, _sleep_at)
	# Ambient only while he initiates: at Off the timer has nothing to wake for and stops.
	if _ambient_allowed():
		next = _soonest(next, _blink_at)
		next = _soonest(next, _fidget_at)
	return next

static func _soonest(a: int, b: int) -> int:
	if a <= 0:
		return b
	if b <= 0:
		return a
	return mini(a, b)

func _on_timer() -> void:
	var now := _now()
	if not _beat.is_empty():
		if not _live():
			_end_beat()
			return
		var tail_at := int(_beat.get("tail_at_msec", 0))
		if tail_at > 0 and now >= tail_at:
			_enter_tail()
	if _drag_since > 0 and now >= _drag_since + HELD_LONG_MSEC:
		hold(&"held_long")
	if _away_since > 0 and _sleep_at > 0 and now >= _sleep_at:
		_sleep_at = 0
		hold(&"asleep")
	if _idle_brain == null:
		_connect_idle_brain()
	_tick_ambient(now)
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
	var was_locked := _locked
	_locked = inside
	# The beat owns him completely: whatever was playing stops so the collapse reads.
	if inside and not _beat.is_empty():
		_beat = {}
		if art:
			art.clear_beat()
		_arm()
	elif not inside and was_locked and state == &"idle":
		# Back on his feet with the meter reset: two shake-offs and a neutral face.
		react(&"meter_reset")
