class_name BuddyArt
extends Node

## Drives Bonehead's two sprite layers: the generated body animation, and the hand-drawn
## face that rides on top of it.
##
## **Why the face is a separate node.** Sending it through the animation generator destroys
## it — two-pixel eyes are not enough signal and they dissolve into noise by the fourth
## frame (see `art/prompts/bonehead_idle.md`). Keeping it off the body also gets what
## `docs/architecture.md` actually wants: mood reads independently of body pose, so ten
## expressions across nine body animations is ten sprites and nine animations, not ninety.
##
## **Why it needs offsets.** His head bobs up to 11 px across an idle loop. A face pinned at
## a fixed position detaches immediately. `art/tools/postprocess.py` measures the head on
## every generated frame and writes the offsets to `Data/buddy_face_offsets.json`; this
## reads them back and moves the face to match, per frame.

const BODY_FRAMES := "res://art/src/bonehead.aseprite"
const FACE_FRAMES := "res://art/src/bonehead_face.aseprite"
const OFFSETS_PATH := "res://Data/buddy_face_offsets.json"

## Body animation to play for each buddy state. States without an entry keep whatever is
## already playing, which is what makes a partial art pass survivable: an unbuilt animation
## is a state that does not change pose, not a crash or a blank sprite.
const STATE_ANIMATION := {
	&"idle": &"idle",
	&"dragged": &"dragged",
	&"hurt": &"hurt",
	&"happy": &"happy",
	&"knockout": &"collapse",
	&"pile": &"pile",
	&"reassemble": &"reassemble",
}

## Expression per state, overridden by mood while he is simply idling. The face is the
## cheap half of the character: swapping it is one animation name and costs nothing.
const STATE_FACE := {
	&"hurt": &"shocked",
	&"happy": &"blissful",
	&"knockout": &"dizzy",
	&"pile": &"dizzy",
	&"reassemble": &"shocked",
}

## Animations that play once and stop. Everything else loops. Aseprite Wizard imports every
## tag as looping, which is right for an idle and wrong for a knockout — a collapse that
## loops never lets him get back up.
const ONE_SHOT: Array[StringName] = [&"hurt", &"happy", &"collapse", &"reassemble"]

## The states that always win over a beat. The knockout is choreography the whole game reads
## (Economy pays off it), so a beat never keeps its face or tag through a collapse.
const BEAT_PROOF_STATES: Array[StringName] = [&"knockout", &"pile", &"reassemble"]

## Half his 63 px figure inside the 96 px cell, in art pixels. Squash anchors at his feet:
## `AnimatedSprite2D` is centre-pivoted, so squashing about the origin lifts him off the desk,
## which is the commonest way a squash reads as a glitch.
const FOOT_HALF_HEIGHT := 31.5

## A one-shot beat's body tag ran to its end. `ExpressionBrain` ends the beat on this rather
## than on its own estimate of the length.
signal beat_animation_finished(tag: StringName)

## Which idle he stands in, by mood. Posture is the half of this that reads from across the
## room — the face is four pixels at 2x and the player is working in another window, so a
## slumped body is what actually tells them he is miserable (docs/art-direction.md:
## "silhouette and pose carry the information, never fine detail").
const MOOD_IDLES: Array = [
	[-25.0, &"idle_sad"],
	[25.0, &"idle"],
	[101.0, &"idle_happy"],
]

## Mood thresholds for the idle face, unhappiest first. Mood runs -100..+100.
const MOOD_FACES: Array = [
	[-60.0, &"crying"],
	[-25.0, &"sad"],
	[25.0, &"neutral"],
	[60.0, &"happy"],
	[101.0, &"blissful"],
]

@export var body: AnimatedSprite2D
@export var face: AnimatedSprite2D

## Who this drives. `_state_of_body()` used to find him with `get_parent() as Buddy`, which
## breaks silently the day the art pass wraps the sprites in a `Rig: Node2D` — it would
## return `&"idle"` forever and mood would overwrite every reaction face with nobody
## noticing. Filled by `Buddy._ensure_components()`, exactly like `mood` and `grime` are;
## the group lookup is the fallback for anyone building a `BuddyArt` outside that path.
@export var buddy: Buddy

## Per-animation offset tables, built once at load from the raw JSON — never walked frame by
## frame. `_offset_positions[track][frame]` is the face's [x, y] displacement for that frame,
## authored for facing right; `_offset_visible[track][frame] == 0` means the head is not
## readable on that frame (mid-collapse) and the face should hide rather than pin somewhere
## arbitrary. Both are keyed by StringName to match `AnimatedSprite2D.animation`'s type —
## the JSON's own keys are String, which is why `_load_offsets` converts them once here
## instead of every caller converting on every lookup.
var _offset_positions: Dictionary = {}
var _offset_visible: Dictionary = {}

## The current animation's slice of the tables above, refreshed on `animation_changed` so
## `_place_face` never touches a Dictionary: an array index, once a track change.
var _track_positions: PackedVector2Array = PackedVector2Array()
var _track_visible: PackedByteArray = PackedByteArray()

var _face_home := Vector2.ZERO
var _body_home := Vector2.ZERO

## The scale he was authored at, captured once. Multiplying face offsets by `body.scale`
## instead would be fine until the day something (a hit squash) writes `body.scale` — at
## which point a 0.85 squash drags the face 15% down his skull on every hit.
var _base_scale := Vector2.ONE

## Travel presentation. He has no walk tag — the nine body tags are poses and beats, none of
## them a stride — and the idle brain nevertheless walks him across the desk to his toys.
## Playing `idle` the whole way there reads as a skeleton being dragged by a ghost.
##
## So this is the half that needs no new art: **which way he is facing, and a bob keyed to
## how fast he is going.** A real walk cycle replaces the bob later and nothing that calls
## `travel()` has to change, which is the point of it being here rather than in the brain.
##
## Applied to the body *and* the face together. The face is a sibling sprite re-placed every
## frame from a table of per-frame offsets, so anything that moves one and not the other
## takes his face off — which is why this is a shared offset and a mirrored x rather than a
## rotation on the body sprite.
const BOB_HEIGHT := 1.5
const BOB_RATE := 9.0
## Fast enough that letting go of him stops the bob within a few frames, slow enough that the
## gap between two physics ticks never dips it.
const TRAVEL_DECAY := 6.0

var _facing := 1.0
var _travel := 0.0
var _bob_phase := 0.0
var _bob := 0.0

## The motion accumulator (docs/plan-expressive-buddy.md §3.3). A `Tween` on `body.position`,
## `face.position` or `body.scale` does not work here: travel writes the body every frame and
## the face is re-placed on every frame change, so anything tweened onto either is overwritten
## a frame later. Every code motion is instead a number folded into those same two writes:
##
##   body.position = _body_home + (recoil_x, bob + hop_y + foot_fix)
##   body.scale    = _base_scale * squash
##   face.position = _face_home + offset * _base_scale * squash
##                 + (look_x + beat_look_x + recoil_x, bob + hop_y + nod_y + foot_fix)
##
## All in screen pixels. Every one of them is multiplied by the beat's amplitude when it is
## computed, so at Focus Off they are all exactly zero and his silhouette never moves (D36).
var _recoil_x := 0.0
var _hop_y := 0.0
var _nod_y := 0.0
var _beat_look_x := 0.0
var _look_x := 0.0          ## the gaze, held between `look()` calls
var _squash := Vector2.ONE
var _foot_fix := 0.0
var _face_base_scale := Vector2.ONE

## The live beat, if any. `ExpressionBrain` owns its timing; this owns its look.
var _beat_live := false
var _beat_tag: StringName = &""
var _motion: StringName = &""
var _motion_started_msec := 0
var _motion_seconds := 0.0
var _motion_amp := 0.0
var _motion_heat := 0.0
var _motion_dir := 1.0      ## +1 / -1: which way is *away* from where it happened

func _ready() -> void:
	_load_offsets()
	if body:
		_base_scale = body.scale
		body.animation_finished.connect(_on_body_animation_finished)
		var frames := load(BODY_FRAMES) as SpriteFrames
		if frames:
			body.sprite_frames = frames
			for animation in ONE_SHOT:
				if frames.has_animation(animation):
					frames.set_animation_loop(animation, false)
		# Connected before the first `play()` so the very first track is cached rather than
		# leaving `_track_positions` empty until something later happens to change animation.
		body.frame_changed.connect(_place_face)
		body.animation_changed.connect(_on_body_animation_changed)
		_play_body(&"idle")
		_on_body_animation_changed()
	if face:
		var frames := load(FACE_FRAMES) as SpriteFrames
		if frames:
			face.sprite_frames = frames
		_face_home = face.position
		_face_base_scale = face.scale
		set_expression(&"neutral")
	if body:
		_body_home = body.position

	EventBus.buddy_state_changed.connect(_on_state_changed)
	EventBus.mood_changed.connect(_on_mood_changed)

	# The honest baseline: nothing is moving yet, so there is nothing for `_process` to do.
	# `travel()` is the only thing that turns it back on.
	set_process(false)

## Only runs while something is actually moving — `travel()` re-enables it and it switches
## itself off once travel and the bob it drives have both settled. Placement the rest of the
## time rides `body.frame_changed` / `animation_changed` instead, which fire from the
## sprite's own animation clock whether or not this node is processing.
func _process(delta: float) -> void:
	if body == null or face == null:
		set_process(false)
		return
	_advance_travel(delta)
	if _quiet():
		set_process(false)

## Nothing is moving: no travel, no bob left to ease out, no code motion running.
func _quiet() -> bool:
	return is_zero_approx(_travel) and is_zero_approx(_bob) and _motion == &""

## Re-places the face from the cached per-frame track. Called on `frame_changed` /
## `animation_changed` while he is otherwise still, and from `_advance_travel` while he is
## walking, since the bob it applies changes every frame and the face rides it with the body.
func _place_face() -> void:
	if body == null or face == null:
		return
	var frame := body.frame
	if frame >= _track_visible.size():
		return
	if _track_visible[frame] == 0:
		# No readable head on this frame — he has folded into the pile. Hiding beats pinning
		# the face somewhere arbitrary on a heap of bones.
		face.visible = false
		return
	face.visible = true
	var entry := _track_positions[frame]
	var dx := entry.x * _base_scale.x * _squash.x
	# Mirror only the per-frame offset, not the home position. The old form negated the
	# whole placed.x, which is correct only while `_face_home.x == 0` — true today only
	# because buddy.gd copies `sprite.position` (Puppet sits at the origin). The first
	# non-zero face home the art pass authors would send his face off his head when he
	# faces left.
	if _facing < 0.0:
		dx = -dx
	# The offset rides the squash (a flattened body has a lower head) and the same foot fix
	# the body gets, so the face stays on the skull through a hit rather than hanging where
	# the head used to be.
	var placed := Vector2(
		_face_home.x + dx + _look_x + _beat_look_x + _recoil_x,
		_face_home.y + entry.y * _base_scale.y * _squash.y + _bob + _hop_y + _nod_y + _foot_fix)
	face.position = placed
	face.scale = _face_base_scale * _squash

func _on_body_animation_changed() -> void:
	var track: StringName = body.animation
	_track_positions = _offset_positions.get(track, PackedVector2Array())
	_track_visible = _offset_visible.get(track, PackedByteArray())
	_place_face()

## How he is travelling, from the idle brain. `direction` is -1, 0 or 1; `effort` is how hard
## he is going, 0 to 1, and drives the bob's height so a shuffle and a march differ.
##
## Deliberately a plain setter called every physics frame rather than a state: he is walking
## while a dozen other things are also true of him, and making travel a *state* would mean
## the walk fighting the knockout beat for the same slot.
func travel(direction: float, effort: float) -> void:
	if not is_zero_approx(direction):
		_facing = signf(direction)
	_travel = clampf(effort, 0.0, 1.0)
	set_process(true)

func stop_travelling() -> void:
	_travel = 0.0

func _advance_travel(delta: float) -> void:
	# `travel()` is a heartbeat, not a switch: it is called every physics frame he is walking
	# and this decays it in between. So a caller that simply stops calling — because he
	# arrived, was picked up, was knocked out, or the brain stood down — fades out correctly
	# without anybody remembering to say stop. There is no code path that can leave him
	# bobbing on the spot forever, which is the bug the switch version would have had.
	_travel = maxf(0.0, _travel - delta * TRAVEL_DECAY)
	if _travel > 0.0:
		_bob_phase += delta * BOB_RATE
		_bob = -absf(sin(_bob_phase)) * BOB_HEIGHT * _travel
	else:
		_bob_phase = 0.0
		# Eased rather than snapped: arriving at a hot tub should not drop him a pixel.
		_bob = move_toward(_bob, 0.0, delta * BOB_HEIGHT * 4.0)
	_advance_motion()
	_apply_body()

## The one place the body sprite's transform is written. Everything that moves him — travel,
## the bob, a beat's recoil, hop or squash — is a number folded in here, and the face is
## re-placed in the same breath so it can never be a frame behind the body.
func _apply_body() -> void:
	if body == null or face == null:
		return
	body.flip_h = _facing < 0.0
	face.flip_h = _facing < 0.0
	_foot_fix = (1.0 - _squash.y) * FOOT_HALF_HEIGHT * _base_scale.y
	body.position = _body_home + Vector2(_recoil_x, _bob + _hop_y + _foot_fix)
	body.scale = _base_scale * _squash
	_place_face()

# --- beats ------------------------------------------------------------------
#
# The public surface `ExpressionBrain` drives. All shaped like `set_expression`: guarded, and
# silently a no-op on a name that is not drawn yet, so a reaction can be wired before its art
# and a partial art pass still leaves a playable character.

## Start a beat: a face, a body tag, a code motion, all at once. `amplitude` is the Focus
## amplitude (0 at Off), `heat` is 0..1 and sizes the motion, `at` is where it happened for
## motions that have a direction, `speed` is the body `speed_scale` for the life of the beat.
func play_beat(tag: StringName, face_name: StringName, seconds: float, amplitude: float,
		motion: StringName = &"", heat: float = 1.0, at: Vector2 = Vector2.INF,
		speed: float = 1.0) -> void:
	if body == null:
		return
	_beat_live = true
	_beat_tag = tag
	if face_name != &"":
		set_expression(face_name)
	if tag != &"" and has_animation(tag):
		# `play()` on the animation already playing does not rewind it, and a restart is the
		# point of an escalated hit landing on top of a light one.
		body.play(tag)
		body.frame = 0
		body.frame_progress = 0.0
	body.speed_scale = speed
	_motion = motion if amplitude > 0.0 else &""
	_motion_started_msec = Time.get_ticks_msec()
	_motion_seconds = maxf(seconds, 0.05)
	_motion_amp = amplitude
	_motion_heat = clampf(heat, 0.0, 1.0)
	_motion_dir = _away_from(at)
	if _motion != &"":
		_advance_motion()
		_apply_body()
		set_process(true)

## Change only the face, mid-beat: the heavy hit's dizzy tail. `until_msec` is informational —
## the brain owns the timing; the face stays until the beat clears or something else sets it.
func hold_face(face_name: StringName, _until_msec: int) -> void:
	set_expression(face_name)

## The beat is over. Every accumulator returns to zero, the body to its home and scale, and
## the state machine's own look is re-applied — mood picks the idle if he is idle.
func clear_beat() -> void:
	_beat_live = false
	_beat_tag = &""
	_motion = &""
	_recoil_x = 0.0
	_hop_y = 0.0
	_nod_y = 0.0
	_beat_look_x = 0.0
	_squash = Vector2.ONE
	if body:
		body.speed_scale = 1.0
	_apply_body()
	_reapply_state()
	if _quiet():
		set_process(false)

## A head turn without the bob — `travel()` conflates the two. In screen pixels, already
## scaled by the caller; 0 drops the gaze.
func look(dx_px: float) -> void:
	_look_x = dx_px
	_apply_body()

func set_squash(value: Vector2) -> void:
	_squash = value
	_apply_body()

func beat_active() -> bool:
	return _beat_live

func look_x() -> float:
	return _look_x + _beat_look_x

## Which way is away from `at`, as +1 / -1. No point given: away from where he is facing.
func _away_from(at: Vector2) -> float:
	if at == Vector2.INF or buddy == null:
		return -_facing
	var d := buddy.global_position.x - at.x
	return 1.0 if d >= 0.0 else -1.0

## Puts the state machine's look back after a beat: the idle variant and face by mood when he
## is idle, the state's own tag and face otherwise. A tag already playing is left alone.
func _reapply_state() -> void:
	var state := _state_of_body()
	if state == &"idle":
		_on_mood_changed(Economy.mood)
		return
	var animation: StringName = STATE_ANIMATION.get(state, &"")
	if animation != &"" and body and body.animation != animation:
		_play_body(animation)
	if STATE_FACE.has(state):
		set_expression(STATE_FACE[state])

func _on_body_animation_finished() -> void:
	if _beat_live and body and body.animation == _beat_tag:
		beat_animation_finished.emit(_beat_tag)

## Evaluates the running code motion at the current time into the accumulator. Time-based
## from msec, never frame-counted: `Engine.max_fps` drops to 20 at idle and in Low Power.
## Every number here is multiplied by `_motion_amp`, which is zero at Focus Off.
func _advance_motion() -> void:
	if _motion == &"":
		return
	var e := float(Time.get_ticks_msec() - _motion_started_msec) / 1000.0
	var a := _motion_amp
	var d := _motion_seconds
	_recoil_x = 0.0
	_hop_y = 0.0
	_nod_y = 0.0
	_beat_look_x = 0.0
	_squash = Vector2.ONE
	var finished := false
	match _motion:
		&"impact", &"impact_wobble", &"land":
			# Squash at his feet, overshoot on the way back — a ring-down, not a lerp.
			var depth := 0.2 if _motion == &"land" else 0.10 + 0.18 * _motion_heat
			var ring := exp(-6.0 * e) * cos(TAU * 1.5 * e)
			_squash = Vector2(1.0 + depth * a * ring * 0.6, 1.0 - depth * a * ring)
			if _motion != &"land":
				_recoil_x = _motion_dir * 6.0 * (0.4 + 0.6 * _motion_heat) * a * exp(-5.0 * e)
			if _motion == &"impact_wobble" and e > 0.3:
				# The dizzy tail: the head wobbles ±5 px at 3 Hz and dies away.
				var left := clampf(1.0 - (e - 0.3) / maxf(d - 0.3, 0.1), 0.0, 1.0)
				_beat_look_x = 5.0 * a * sin(TAU * 3.0 * e) * left
			finished = e >= d
		&"hop", &"hop2":
			var count := 2.0 if _motion == &"hop2" else 1.0
			var u := e / 0.32
			if u < count:
				_hop_y = -5.0 * a * absf(sin(PI * u))
			finished = u >= count
		&"nod":
			if e < d:
				_nod_y = 2.0 * a * absf(sin(PI * 3.0 * e / d))
			finished = e >= d
		&"shake_off":
			if e < d:
				_recoil_x = 3.0 * a * sin(TAU * 8.0 * e) * (1.0 - e / d)
			finished = e >= d
		&"wobble":
			if e < d:
				_beat_look_x = 5.0 * a * sin(TAU * 3.0 * e) * (1.0 - e / d)
			finished = e >= d
		&"puff":
			# Chest out: narrower and taller, eased in, held, eased out over the last 0.15 s.
			var k := clampf(e / 0.1, 0.0, 1.0) * clampf((d - e) / 0.15, 0.0, 1.0)
			_squash = Vector2(1.0 - 0.08 * a * k, 1.0 + 0.08 * a * k)
			finished = e >= d
		&"duck":
			if e < 0.15:
				_squash = Vector2(1.0 + 0.05 * a, 1.0 - 0.1 * a)
			else:
				_beat_look_x = -_motion_dir * 2.0 * a
			finished = e >= d
		&"lean_away":
			_beat_look_x = _motion_dir * 2.0 * a
			finished = e >= d
		&"gaze", &"face_toward":
			_beat_look_x = -_motion_dir * 2.0 * a
			finished = e >= d
		&"fidget":
			# A weight shift: over and back once.
			if e < d:
				_recoil_x = 3.0 * a * sin(PI * e / d) * _facing
			finished = e >= d
		# --- continuous: run until the beat clears ---
		&"shiver":
			_recoil_x = 1.5 * a * sin(TAU * 12.0 * e)
		&"wiggle":
			_recoil_x = 2.0 * a * sin(TAU * 1.2 * e)
		&"slow_bob":
			_hop_y = 1.5 * a * sin(TAU * 0.5 * e)
		&"kick":
			var phase := fmod(e, 3.0)
			if phase < 0.3:
				_recoil_x = 4.0 * a * sin(PI * phase / 0.3) * -_facing
		_:
			finished = true
	if finished:
		_motion = &""
		_recoil_x = 0.0
		_hop_y = 0.0
		_nod_y = 0.0
		_beat_look_x = 0.0
		_squash = Vector2.ONE

## How long an animation runs, in seconds. The knockout beat waits on these rather than on
## a hardcoded duration, so retiming a tag in Aseprite retimes the beat with it instead of
## desynchronising the two.
func animation_length(animation: StringName) -> float:
	if body == null or body.sprite_frames == null:
		return 0.0
	if not body.sprite_frames.has_animation(animation):
		return 0.0
	var frames := body.sprite_frames.get_frame_count(animation)
	var speed := body.sprite_frames.get_animation_speed(animation)
	if speed <= 0.0:
		return 0.0
	var total := 0.0
	for i in frames:
		total += body.sprite_frames.get_frame_duration(animation, i) / speed
	return total

func has_animation(animation: StringName) -> bool:
	return body != null and body.sprite_frames != null \
		and body.sprite_frames.has_animation(animation)

func set_expression(expression: StringName) -> void:
	if face == null or face.sprite_frames == null:
		return
	if not face.sprite_frames.has_animation(expression):
		return
	face.animation = expression

func _on_state_changed(state: StringName) -> void:
	# A live beat owns his face and tag; the state machine gets him back when it clears.
	# The knockout is the exception: it always wins, and the brain drops its beat behind it.
	if _beat_live and not BEAT_PROOF_STATES.has(state):
		return
	if state == &"idle":
		# Straight to the mood handler, which picks both the idle variant and the face.
		# Playing plain `idle` first would flash the neutral posture for a frame.
		_on_mood_changed(Economy.mood)
		return
	_play_body(STATE_ANIMATION.get(state, &""))
	if STATE_FACE.has(state):
		set_expression(STATE_FACE[state])

func _on_mood_changed(value: float) -> void:
	if _beat_live:
		return
	# Only while idling: a hurt face should not be overwritten by a cheerful mood the moment
	# after he is hit, and a knockout must not be interrupted by a posture change.
	var state := _state_of_body()
	if STATE_FACE.has(state):
		return
	for threshold in MOOD_FACES:
		if value < float(threshold[0]):
			set_expression(threshold[1])
			break
	if state != &"idle":
		return
	for threshold in MOOD_IDLES:
		if value < float(threshold[0]):
			_play_body(threshold[1])
			return

func _state_of_body() -> StringName:
	var owner_buddy := buddy
	if owner_buddy == null:
		var candidates := get_tree().get_nodes_in_group(Buddy.GROUP_BUDDY)
		if not candidates.is_empty():
			owner_buddy = candidates[0] as Buddy
	return owner_buddy.state if owner_buddy else &"idle"

## Missing animations are skipped rather than played as an error. Most of the inventory in
## `docs/art-direction.md` is unbuilt, and a partial art pass has to leave a playable game.
func _play_body(animation: StringName) -> void:
	if body == null or animation == &"" or body.sprite_frames == null:
		return
	if not body.sprite_frames.has_animation(animation):
		return
	body.play(animation)

func _load_offsets() -> void:
	if not FileAccess.file_exists(OFFSETS_PATH):
		push_warning("BuddyArt: %s missing; the face will not track the head" % OFFSETS_PATH)
		return
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BuddyArt: %s is not valid JSON" % OFFSETS_PATH)
		return
	# Parsed once into packed, per-frame arrays rather than kept as the raw
	# Dictionary-of-Arrays the JSON arrives in. The old `_process` rebuilt a `String` key and
	# walked that shape every rendered frame, forever; this keeps the on-disk shape
	# (`Data/buddy_face_offsets.json` is unchanged) but the in-memory copy is a lookup, not a
	# walk.
	for key in parsed.keys():
		var raw: Array = parsed[key]
		var positions := PackedVector2Array()
		var visible := PackedByteArray()
		positions.resize(raw.size())
		visible.resize(raw.size())
		for i in raw.size():
			var entry = raw[i]
			if entry == null:
				visible[i] = 0
			else:
				positions[i] = Vector2(float(entry[0]), float(entry[1]))
				visible[i] = 1
		var track := StringName(key)
		_offset_positions[track] = positions
		_offset_visible[track] = visible
