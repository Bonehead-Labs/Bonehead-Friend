class_name GrimeComponent
extends Node

## How filthy Bonehead is, 0..1. Dust and soot accumulate from being beaten and blown up;
## the sponge is the only thing that removes it.
##
## Grime suppresses **Bones** income, so the cheapest Hearts item in the game is also the
## thing that protects the player's damage economy. That is the dual-currency spine in one
## object: you cannot opt out of being nice to him without paying for it.

signal changed(value: float)

## The body sprite and the face, both tinted toward `GRIME_COLOR` as grime rises — as a
## `grime` uniform on the shader `EffectsPlayer` installs (`effects_player.gd`), not
## `modulate`. A `modulate` tint on the body alone left a spotless white face on a filthy
## skeleton and browned the teal headphones along with everything else; the shader version
## is masked to bone-white pixels, so the outline and the headphones are exempt and Face
## gets the same treatment Puppet does. `EffectsPlayer.material_for()` is a static helper
## precisely so this component can share Puppet's material rather than fight it for
## `.material`, and can put an equivalent one on Face, which has no `EffectsPlayer` of its
## own.
@export var puppet: CanvasItem
@export var face: CanvasItem

const GRIME_COLOR := Color(0.55, 0.50, 0.42)

const EMIT_THRESHOLD := 0.01

var value: float = 0.0

var _last_emitted: float = 0.0

func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	_apply_uniform()

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
	_apply_uniform()
	if absf(value - _last_emitted) >= EMIT_THRESHOLD or is_zero_approx(value):
		_last_emitted = value
		changed.emit(value)
		EventBus.grime_changed.emit(value)

func _apply_uniform() -> void:
	for target in [puppet, face]:
		if target == null:
			continue
		var material := EffectsPlayer.material_for(target)
		material.set_shader_parameter(&"grime", value)
		material.set_shader_parameter(&"grime_color", GRIME_COLOR)
