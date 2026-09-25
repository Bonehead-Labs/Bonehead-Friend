class_name MagicEightBall
extends FidgetToy

## A fortune ball (D57).
##
## - **Shake it**: pick it up and wave it about. What counts is the changes of direction, not
##   the distance — a slow drag across the desk is not a shake. When it has had enough it
##   sloshes and wobbles, so the player knows.
## - **Right-tap it** (or press right while holding it) to read it. An answer appears in a small
##   bubble above it — one of twenty, in the game's display face, on the shell's own `Bubble`
##   style rather than anything drawn here.
## - **He believes every word.** A yes cheers him up, a no sinks him, a maybe puzzles him, and a
##   good answer pays Hearts. Read it unshaken and it tells you to shake it first.
## - Left alone with it, he shakes it and reads it himself.
##
## Its own twenty, in its own voice: the classic ten-five-five split of yes, maybe and no, and
## none of the famous toy's actual sentences.

const ANSWERS := [
	["Without a doubt.", &"yes"],
	["Bone-afide yes.", &"yes"],
	["It is certain.", &"yes"],
	["All signs say yes.", &"yes"],
	["You can count on it.", &"yes"],
	["Yes, obviously.", &"yes"],
	["The spirits agree.", &"yes"],
	["Most likely.", &"yes"],
	["I would bet my ribs.", &"yes"],
	["Yes. Now smile.", &"yes"],
	["Ask again later.", &"maybe"],
	["Too foggy to tell.", &"maybe"],
	["Shake harder.", &"maybe"],
	["Can't say. Won't say.", &"maybe"],
	["Maybe after a nap.", &"maybe"],
	["No chance.", &"no"],
	["Deeply unlikely.", &"no"],
	["My sources say no.", &"no"],
	["Not in this life.", &"no"],
	["Outlook: bleak.", &"no"],
]
const UNSHAKEN := "Shake me first."

## Full shakes to be ready, before the "time between uses" node takes some off. A full shake is
## one stroke of at least `STROKE` px between two changes of direction.
@export var shakes_needed: float = 4.0
## Kindness value of a yes, before the item's own value node. A maybe or a no pays nothing.
@export var answer_value: float = 14.0
## How long an answer stays up.
@export var bubble_seconds: float = 3.2

## A carried step shorter than this (world px) is jitter, not a shake.
const SHAKE_STEP := 3.0
## How much of each stroke counts, world px: a stroke this long is one whole shake, a shorter
## one its share of one, and anything past it nothing — carrying the ball across the desk is not
## shaking it, however far it goes. A comfortable flick of the wrist.
const STROKE := 32.0

var last_answer := ""
var last_tone: StringName = &""
var _energy := 0.0
var _last_step := Vector2.ZERO
## How far the current stroke has gone since the last change of direction, world px.
var _stroke := 0.0
## The first stroke is only carrying it until it turns back; what it was worth waits here.
var _first := 0.0
var _turned := false
var _bubble: PanelContainer
var _bubble_label: Label
var _bubble_until := 0
var _wobble: Tween

func _ready() -> void:
	super._ready()
	set_process(false)

func energy() -> float:
	return _energy

func is_ready_to_read() -> bool:
	return _energy >= _needed()

func _needed() -> float:
	return maxf(1.0, shakes_needed * upgrade(&"cooldown_mult"))

func _on_gesture(g: GestureZones.Gesture) -> void:
	match g.kind:
		GestureZones.CARRY:
			_shake_step(g.delta)
		GestureZones.ACTION:
			read(true)
		GestureZones.TAP:
			if g.button == MOUSE_BUTTON_RIGHT and g.zone == &"ball":
				read(true)

## One carried step. A reversal is a step against the one before it, both of them real, and it
## starts a new stroke.
##
## **The shake is counted continuously, by how far each stroke went** (D70, the item audit's
## F10). It used to count one whole reversal at a time against `4 x 0.94^n`, so "Looser Dice"
## rounded back up to four reversals for its first four levels and took off one shake, once,
## across all ten. Now every step of a stroke is worth its share of a shake as it happens, up to
## `STROKE`, so the ball fills as the hand moves and 6% less shaking is 6% less shaking. The
## first stroke is only carrying it until the hand turns back — a straight drag is never a shake
## — and then counts as if it had been one all along.
func _shake_step(step: Vector2) -> void:
	var length := step.length()
	if length < SHAKE_STEP:
		return
	var reversed := _last_step != Vector2.ZERO and step.dot(_last_step) < 0.0
	_last_step = step
	var gained := 0.0
	if reversed:
		_stroke = 0.0
		if not _turned:
			_turned = true
			gained += _first
	var worth := clampf(STROKE - _stroke, 0.0, length) / STROKE
	_stroke += length
	if _turned:
		gained += worth
	else:
		_first += worth
	if gained <= 0.0:
		return
	var was_ready := is_ready_to_read()
	_energy = minf(_energy + gained, _needed() * 2.0)
	if not was_ready and is_ready_to_read():
		_ready_tell()

## The dice inside have settled: a slosh and a wobble.
func _ready_tell() -> void:
	AudioManager.play(&"slosh", 0.1, -12.0, 1.3)
	if not animating() or sprite == null:
		return
	if _wobble and _wobble.is_valid():
		_wobble.kill()
	_wobble = create_tween()
	for angle in [0.18, -0.14, 0.08, 0.0]:
		_wobble.tween_property(sprite, "rotation", angle, 0.06)

## Reads it. `pick` forces an answer by index, for a suite that cannot wait for the one it
## wants to come up.
func read(by_player: bool, pick: int = -1) -> void:
	if not is_ready_to_read():
		_say(UNSHAKEN)
		last_answer = UNSHAKEN
		last_tone = &""
		return
	_energy = 0.0
	_last_step = Vector2.ZERO
	_stroke = 0.0
	_first = 0.0
	_turned = false
	var index := pick if pick >= 0 and pick < ANSWERS.size() else randi() % ANSWERS.size()
	last_answer = ANSWERS[index][0]
	last_tone = ANSWERS[index][1]
	_say(last_answer)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	var reaction := StringName("answer_%s" % last_tone)
	if last_tone == &"yes":
		chips(global_position + Vector2(0, -24), &"heart", 4, 90.0)
		if by_player:
			pay_act(answer_value, global_position, reaction)
			return
		pay_sustained(answer_value, global_position)
	fidget(reaction)

# --- the bubble -----------------------------------------------------------------

## The answer, above the ball. A themed `PanelContainer` in world space — the shell's `Bubble`
## variation and the display face, never a look built here (CLAUDE.md, the UI rules). It
## ignores the mouse: an answer must never be the thing a click lands on.
func _say(text: String) -> void:
	if _bubble == null:
		_build_bubble()
	_bubble_label.text = text
	_bubble.visible = true
	# A child of a plain Node2D is never laid out: own the size, now and again once the font
	# has measured the new text (CLAUDE.md).
	_bubble.reset_size()
	_bubble.call_deferred(&"reset_size")
	_place_bubble()
	_place_bubble.call_deferred()
	_bubble_until = Time.get_ticks_msec() + int(bubble_seconds * 1000.0)
	set_process(true)

func answer_showing() -> bool:
	return _bubble != null and _bubble.visible

func answer_text() -> String:
	return _bubble_label.text if _bubble_label else ""

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "AnswerBubble"
	_bubble.theme = UITheme.get_theme()
	_bubble.theme_type_variation = &"Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# In the world's space, not the ball's: it must not spin with a thrown ball.
	_bubble.top_level = true
	_bubble.z_index = 60
	_bubble_label = Label.new()
	_bubble_label.name = "Answer"
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.add_child(_bubble_label)
	add_child(_bubble)

func _place_bubble() -> void:
	if _bubble == null:
		return
	var lift := 24.0
	if collider and collider.shape:
		lift = collider.shape.get_rect().size.y * 0.5 + 10.0
	var anchor := global_position + Vector2(0, -lift)
	_bubble.global_position = (anchor - Vector2(_bubble.size.x * 0.5, _bubble.size.y)).round()

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= _bubble_until:
		if _bubble:
			_bubble.visible = false
		set_process(false)
		return
	_place_bubble()

# --- him ------------------------------------------------------------------------

func idle_appeal() -> float:
	# A read every other tick, and half of the answers are a yes.
	return answer_value * 0.5 / (IdleBrain.THINK_SECONDS * 2.0)

## He shakes it on one tick and reads it on the next. At Focus Off it is read without the
## shake being seen (D36).
func idle_use(_him: Buddy) -> void:
	if is_ready_to_read():
		read(false)
		return
	_energy = _needed()
	if animating():
		_ready_tell()
