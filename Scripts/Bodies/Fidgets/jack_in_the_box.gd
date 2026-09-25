class_name JackInTheBox
extends FidgetToy

## A jack-in-the-box (D57).
##
## - **Right-drag in circles on the crank** to wind it. Every quarter turn plinks the next note
##   of the tune, a little higher each time round, so the player can hear it getting closer.
## - After **six to ten turns** — decided when it closes, never shown — the lid flies open and
##   the jack springs out. He startles; then, if his mood allows it, he laughs, and that laugh
##   is the Hearts: a burst for the player who wound it, a trickle if he wound it himself.
## - **Right-tap the lid** to push the jack back in, and it is ready again.
## - Left grabs the box as usual. Left alone with it, he winds it himself.
##
## The box faces either way. Mirrored, the crank is on the left, and the zones follow.

@export var lid: Node2D
@export var crank: Node2D
@export var jack: Node2D
## Turns to the pop, drawn fresh each time it is closed.
@export var min_turns: float = 6.0
@export var max_turns: float = 10.0
## Kindness value of his laugh, before the item's own value node.
@export var laugh_value: float = 30.0
## He laughs at mood above this. Below it the pop only frightens him.
@export var laugh_mood: float = -40.0

## How far the jack rises out of the box, in world px, and how far the lid swings open.
const JACK_RISE := 34.0
const LID_OPEN := deg_to_rad(-115.0)
## The startle, then the laugh: long enough to read as two things.
const LAUGH_DELAY := 0.55
## The tune, as semitones above the plink's own note, one per quarter turn. "Pop! Goes the
## Weasel" as far as a music box ever gets before the weasel goes.
const TUNE := [0, 0, 2, 2, 4, 7, 4, 0, -5, 0, 0, 2, 2, 4, 0, -5,
	0, 0, 2, 2, 4, 7, 4, 0, 9, 2, 5, 4, 0, 0, 2, 4]
## His winding, per think tick: one full turn, animated over this long.
const HIS_TURN_SECONDS := 0.9

var facing := 1.0
var _wound := 0.0
var _target := 0.0
var _out := false
var _quarters := 0
var _by_player := true
## Radians of his own winding still to animate.
var _auto_wind := 0.0
var _tween: Tween

func _ready() -> void:
	super._ready()
	set_process(false)
	_new_target()
	# The lid only means something while he is out. Shut, a right-click on it is a right-click
	# on the box, and bins it like anything else.
	if gestures:
		gestures.set_zone_enabled(&"lid", false)
	# Either way round: the crank is always on the side away from the hinge, and a box that
	# always faced one way would put it against the wall half the time.
	set_facing(-1.0 if randf() < 0.5 else 1.0)

## Faces the art one way or the other. Every moving part mirrors about the body's origin,
## which is the middle of the box, and so do the zones.
func set_facing(direction: float) -> void:
	direction = -1.0 if direction < 0.0 else 1.0
	if is_equal_approx(direction, facing):
		return
	facing = direction
	for part in [sprite, lid, crank, jack]:
		var s := part as Sprite2D
		if s == null:
			continue
		s.flip_h = facing < 0.0
		s.position.x = -s.position.x
		s.offset.x = -s.offset.x
	if lid and _out:
		lid.rotation = LID_OPEN * facing
	if gestures:
		gestures.mirrored = facing < 0.0

func is_out() -> bool:
	return _out

func turns_wound() -> float:
	return _wound / TAU

func turns_needed() -> float:
	return _target / TAU

func _new_target() -> void:
	# "Shorter Tune": the time-between-uses node takes turns off it.
	var turns := randf_range(min_turns, max_turns) * upgrade(&"cooldown_mult")
	_target = maxf(1.0, turns) * TAU

func _on_gesture(g: GestureZones.Gesture) -> void:
	if g.button != MOUSE_BUTTON_RIGHT:
		return
	match g.kind:
		GestureZones.CRANK:
			if g.zone == &"crank":
				wind(absf(g.angle), true)
		GestureZones.TAP:
			if g.zone == &"lid" and _out:
				close(true)

## Winds it by `radians`, in either direction — a real crank has a ratchet, and a player
## circling the wrong way should not be told they are doing it wrong.
func wind(radians: float, by_player: bool) -> void:
	if _out or radians <= 0.0:
		return
	_by_player = by_player
	_wound += radians
	if crank:
		crank.rotation += radians * facing
	var quarters := int(floor(_wound / (PI * 0.5)))
	while _quarters < quarters:
		_quarters += 1
		_plink(_quarters)
	if _wound >= _target:
		pop()

## The next note, and the whole tune climbing a little with every turn.
func _plink(quarter: int) -> void:
	var note: int = TUNE[(quarter - 1) % TUNE.size()]
	var climb := float(quarter) / 4.0 * 0.5
	AudioManager.play(&"plink", 0.0, -8.0, pow(2.0, (float(note) + climb) / 12.0))

## The lid flies, the jack springs, he jumps. Then, a beat later, he laughs or he does not.
func pop() -> void:
	if _out:
		return
	_out = true
	_auto_wind = 0.0
	if gestures:
		gestures.set_zone_enabled(&"lid", true)
	_kill_tween()
	if animating():
		_tween = create_tween().set_parallel(true)
		if lid:
			_tween.tween_property(lid, "rotation", LID_OPEN * facing, 0.09) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if jack:
			_tween.tween_property(jack, "position:y", _jack_home_y() - JACK_RISE, 0.45) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	else:
		if lid:
			lid.rotation = LID_OPEN * facing
		if jack:
			jack.position.y = _jack_home_y() - JACK_RISE
	AudioManager.play(&"bounce", 0.05, -4.0, 1.25)
	var top := global_position + Vector2(0, -JACK_RISE).rotated(global_rotation)
	chips(top, &"star", 6, 150.0)
	fidget(&"jack_popped", top)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	get_tree().create_timer(LAUGH_DELAY).timeout.connect(_laugh_or_not.bind(_by_player))

## His turn: a laugh if he is in the mood, and the laugh is what pays. Out of earshot, or
## miserable, the pop only frightens him.
##
## A tune he wound himself he is always in earshot of (D70): at Focus Off the brain has him
## "simply there" without the walk, often further off than the ear reaches, and the jack was the
## one routine toy that still earned nothing at Off — every pop out of range, every laugh lost.
func _laugh_or_not(by_player: bool) -> void:
	var him := buddy()
	if him == null or not _out:
		return
	if by_player and him.global_position.distance_to(global_position) > ExpressionBrain.THREAT_RANGE:
		return
	if Economy.mood < laugh_mood:
		return
	chips(him.global_position + Vector2(0, -40), &"heart", 6, 120.0)
	if by_player:
		pay_act(laugh_value, him.global_position, &"jack_laugh")
	else:
		pay_sustained(laugh_value, him.global_position)
		fidget(&"jack_laugh", him.global_position)

## Pushes the jack back in, shuts the lid, and draws the next tune's length.
func close(by_player: bool) -> void:
	if not _out:
		return
	_out = false
	_by_player = by_player
	_wound = 0.0
	_quarters = 0
	_new_target()
	if gestures:
		gestures.set_zone_enabled(&"lid", false)
	_kill_tween()
	if animating():
		_tween = create_tween().set_parallel(true)
		if jack:
			_tween.tween_property(jack, "position:y", _jack_home_y(), 0.16) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if lid:
			_tween.tween_property(lid, "rotation", 0.0, 0.16).set_delay(0.1) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		if jack:
			jack.position.y = _jack_home_y()
		if lid:
			lid.rotation = 0.0
	AudioManager.play(&"impact_soft", 0.1, -12.0)

## Where the jack sits when he is in: the seed tool puts him there, at zero.
func _jack_home_y() -> float:
	return 0.0

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null

func idle_appeal() -> float:
	# One turn a tick against an eight-turn tune, and the laugh at the end of it.
	return laugh_value / ((min_turns + max_turns) * 0.5 * IdleBrain.THINK_SECONDS)

## He winds it a turn at a time, and when it has gone off he pushes it back in. At Focus Off
## the turn happens without the crank visibly going round (D36).
func idle_use(_him: Buddy) -> void:
	if _out:
		close(false)
		return
	if not animating():
		wind(TAU, false)
		return
	_auto_wind += TAU
	set_process(true)

func _process(delta: float) -> void:
	if _auto_wind <= 0.0 or _out:
		_auto_wind = 0.0
		set_process(false)
		return
	var step := minf(_auto_wind, TAU / HIS_TURN_SECONDS * delta)
	_auto_wind -= step
	wind(step, false)
