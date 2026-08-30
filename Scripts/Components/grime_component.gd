class_name GrimeComponent
extends Node

## How filthy Bonehead is, 0..1. Dust and soot accumulate from being beaten and blown up;
## the sponge is the only thing that removes it.
##
## Grime suppresses **Bones** income, so the cheapest Hearts item in the game is also the
## thing that protects the player's damage economy. That is the dual-currency spine in one
## object: you cannot opt out of being nice to him without paying for it.

signal changed(value: float)

## The buddy's body sprite. Tinted toward `GRIME_TINT` as grime rises, using `modulate` —
## EffectsPlayer's hit flash uses `self_modulate`, and the two multiply, so neither stomps
## the other. There is no grime *texture* until the art pass; the tint is the placeholder
## and `art-direction.md` calls for a proper overlay layer.
@export var puppet: CanvasItem

const GRIME_TINT := Color(0.55, 0.50, 0.42)

const EMIT_THRESHOLD := 0.01

var value: float = 0.0

var _last_emitted: float = 0.0

func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	_apply_tint()

func add(amount: float) -> void:
	_apply(MoodMath.clamp_grime(value + maxf(0.0, amount)))

## Removes up to `amount` of grime and returns how much actually came off — the caller
## pays Hearts on that, so scrubbing an already-clean skeleton earns nothing. Without the
## return value a sponge left touching him would farm Hearts forever, which is the
## kindness-side twin of the resting-contact bug the damage cooldown exists for.
func clean(amount: float) -> float:
	var removed := minf(value, maxf(0.0, amount))
	if removed <= 0.0:
		return 0.0
	_apply(value - removed)
	return removed

func set_value(new_value: float) -> void:
	_apply(MoodMath.clamp_grime(new_value))

func _on_damage_dealt(info: HitInfo) -> void:
	add(info.amount * ItemDB.balance.grime_per_damage)

func _apply(new_value: float) -> void:
	if is_equal_approx(new_value, value):
		return
	value = new_value
	_apply_tint()
	if absf(value - _last_emitted) >= EMIT_THRESHOLD or is_zero_approx(value):
		_last_emitted = value
		changed.emit(value)
		EventBus.grime_changed.emit(value)

func _apply_tint() -> void:
	if puppet:
		puppet.modulate = Color.WHITE.lerp(GRIME_TINT, value)
