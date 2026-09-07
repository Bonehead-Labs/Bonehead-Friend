class_name GrimeComponent
extends Node

## How filthy Bonehead is, 0..1. Dust and soot accumulate from being beaten and blown up;
## the sponge is the only thing that removes it.
##
## Grime suppresses **Bones** income, so the cheapest Hearts item in the game is also the
## thing that protects the player's damage economy. That is the dual-currency spine in one
## object: you cannot opt out of being nice to him without paying for it.

signal changed(value: float)

## The body sprite, dirtied as grime rises — as a `grime` uniform on the shader
## `EffectsPlayer` installs (`effects_player.gd`), not `modulate`. A `modulate` tint browned
## the teal headphones along with everything else; the shader version is masked to bone-white
## pixels, so the outline and the headphones are exempt. `EffectsPlayer.material_for()` is a
## static helper precisely so this component can share Puppet's material rather than fight
## `EffectsPlayer` for `.material`.
##
## **The face is deliberately not dirtied** (D46). It was, from M3 until now, on the reasoning
## that a spotless face on a filthy skeleton looks wrong. In practice grime over the face
## obscured the one thing the whole expression system exists to show — and the expression is
## how he asks to be cleaned, so hiding it behind the dirt hid the prompt to remove the dirt.
## The three patches are placed clear of the face box for the same reason. `BuddyArt` still
## installs the same material on Face for the wardrobe tints, so its `grime` uniform simply
## stays at zero.
@export var puppet: CanvasItem

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
	if puppet == null:
		return
	var material := EffectsPlayer.material_for(puppet)
	material.set_shader_parameter(&"grime", value)
	material.set_shader_parameter(&"grime_color", GRIME_COLOR)
	material.set_shader_parameter(&"grime_cell", _frame_cell())

## The frame's size in texels, for the shader's frame-local UV. The Aseprite Wizard packs
## every body frame into one atlas, so a patch positioned in raw `UV` would be pinned to the
## atlas and would crawl across him as the frame changed — which is exactly what D44's
## speckle did. Read off the SpriteFrames rather than hard-coded, so the buddy's 96px frame
## and any future sheet agree without a constant to keep in sync.
##
## Returns 0 for a plain texture, which the shader reads as "the texture is the frame".
## **This assumes the atlas is a grid of equal cells**, which is what the importer produces;
## a tightly-packed atlas would need the region origin instead, and there is no way to reach
## it from a shader.
func _frame_cell() -> float:
	var animated := puppet as AnimatedSprite2D
	if animated == null or animated.sprite_frames == null:
		return 0.0
	var names := animated.sprite_frames.get_animation_names()
	if names.is_empty():
		return 0.0
	var texture := animated.sprite_frames.get_frame_texture(names[0], 0)
	if texture is not AtlasTexture:
		return 0.0
	return maxf(texture.get_width(), texture.get_height())
