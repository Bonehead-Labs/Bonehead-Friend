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

var _offsets: Dictionary = {}
var _face_home := Vector2.ZERO

func _ready() -> void:
	_load_offsets()
	if body:
		var frames := load(BODY_FRAMES) as SpriteFrames
		if frames:
			body.sprite_frames = frames
			for animation in ONE_SHOT:
				if frames.has_animation(animation):
					frames.set_animation_loop(animation, false)
			_play_body(&"idle")
	if face:
		var frames := load(FACE_FRAMES) as SpriteFrames
		if frames:
			face.sprite_frames = frames
		_face_home = face.position
		set_expression(&"neutral")

	EventBus.buddy_state_changed.connect(_on_state_changed)
	EventBus.mood_changed.connect(_on_mood_changed)

## The face follows the body frame by frame, so it has to be re-placed every frame rather
## than only when the animation changes.
func _process(_delta: float) -> void:
	if body == null or face == null:
		return
	var track: Array = _offsets.get(String(body.animation), [])
	if body.frame >= track.size():
		return
	var entry = track[body.frame]
	if entry == null:
		# No readable head on this frame — he has folded into the pile. Hiding beats pinning
		# the face somewhere arbitrary on a heap of bones.
		face.visible = false
		return
	face.visible = true
	face.position = _face_home + Vector2(float(entry[0]), float(entry[1])) * body.scale

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
	if state == &"idle":
		# Straight to the mood handler, which picks both the idle variant and the face.
		# Playing plain `idle` first would flash the neutral posture for a frame.
		_on_mood_changed(Economy.mood)
		return
	_play_body(STATE_ANIMATION.get(state, &""))
	if STATE_FACE.has(state):
		set_expression(STATE_FACE[state])

func _on_mood_changed(value: float) -> void:
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
	var buddy := get_parent() as Buddy
	return buddy.state if buddy else &"idle"

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
	if typeof(parsed) == TYPE_DICTIONARY:
		_offsets = parsed
	else:
		push_error("BuddyArt: %s is not valid JSON" % OFFSETS_PATH)
