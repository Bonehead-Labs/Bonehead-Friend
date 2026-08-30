class_name MoodComponent
extends Node

## Bonehead's mood: -100 despair to +100 bliss, decaying toward 0.
##
## The seesaw is the game's rhythm mechanic (docs/game-design.md). Mood feeds a U-curve in
## balance.tres whose multiplier is *highest at both extremes and worst in the middle*, so
## the optimal way to play is to swing him between misery and bliss rather than park him
## anywhere. This component owns the value; Economy only mirrors it off the bus, because
## Economy is the only thing allowed to mint currency and the buddy is the only thing that
## knows how he feels.

signal changed(value: float)

var value: float = 0.0

## Emitting on every frame of decay would put a signal on the bus sixty times a second for
## the whole of an eight-hour session, so the bus only hears about a move this large.
const EMIT_THRESHOLD := 0.5

var _last_emitted: float = 0.0

func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kindness_given.connect(_on_kindness_given)
	EventBus.kindness_sustained.connect(_on_kindness_given)

func _process(delta: float) -> void:
	var decayed := MoodMath.decay(value, ItemDB.balance.mood_decay, delta)
	if decayed == value:
		return
	value = decayed
	# Zero is announced unconditionally: it is the bottom of the U-curve and the moment the
	# player's multiplier is worst, which is exactly when the HUD must be honest about it.
	if absf(value - _last_emitted) >= EMIT_THRESHOLD or is_zero_approx(value):
		_emit()

## Moves mood by `amount`, with MoodMath's soft rail applied. Positive is happier.
func nudge(amount: float) -> void:
	var next := MoodMath.nudge(value, amount)
	if next == value:
		return
	value = next
	_emit()

## Used by the save load path, which restores a value rather than nudging toward one.
func set_value(new_value: float) -> void:
	value = MoodMath.clamp_mood(new_value)
	_emit()

func _on_damage_dealt(info: HitInfo) -> void:
	nudge(-info.amount * ItemDB.balance.mood_per_damage)

## Both kindness signals land here: a rate-paid sponge should lift his mood exactly as
## much per Heart as a pet does, or the sustained items would be economically pointless on
## the multiplier that matters most.
func _on_kindness_given(_source_id: StringName, kindness: float, _world_pos: Vector2) -> void:
	nudge(MoodMath.kindness_mood(kindness, ItemDB.balance.mood_per_kindness))

func _emit() -> void:
	_last_emitted = value
	changed.emit(value)
	EventBus.mood_changed.emit(value)
