class_name EffectsPlayer extends Node

## Per-entity VFX: the hit flash and the explosion burst. Screen-wide effects (floating
## numbers, hit-stop) belong to FXLayer, which is pooled and Focus-Mode gated; this stays
## for effects that are attached to one node.

## How long an explosion node lives before freeing itself. Must outlast the
## particle lifetime in Explosion.tscn.
const EXPLOSION_LIFETIME := 2.0

@export var sprite: AnimatedSprite2D
@export var ExplosionScene: PackedScene = preload("res://Scenes/Effects/Explosion.tscn")

const FLASH_SECONDS := 0.1

## The hit flash is a shader that pushes every opaque pixel toward white, not a tint.
## `self_modulate = RED` multiplied a mostly-white skeleton into a flat red silhouette with
## the face swallowed, which reads as an error state rather than an impact; a solid white
## pop is the genre's one-frame "you hit it". The outline stays black-ish because the mix
## is on colour, not alpha.
##
## `grime` shares this material rather than getting one of its own: it is a slow bone-to-
## dust lerp, masked to bright, low-saturation pixels so the near-black outline and the
## teal headphones — the one prop `docs/art-direction.md` says never to compromise — are
## never touched. `flash` is applied on top of the grimed colour, so a filthy buddy still
## flashes and returns to *grimy* rather than to clean.
const FLASH_SHADER := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.0;
uniform vec4 grime_color : source_color = vec4(0.55, 0.50, 0.42, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 lit = tex.rgb * COLOR.rgb;
	float luma = dot(lit, vec3(0.299, 0.587, 0.114));
	float sat = max(lit.r, max(lit.g, lit.b)) - min(lit.r, min(lit.g, lit.b));
	// Bright and low-saturation only: the teal headphones and the black outline are both
	// excluded by this, one on saturation and the other on brightness, with no per-tag
	// exception list to keep in sync as the roster grows.
	float bone_mask = step(0.5, luma) * step(sat, 0.15);
	vec3 grimed = mix(lit, grime_color.rgb, grime * bone_mask);
	COLOR = vec4(mix(grimed, vec3(1.0), flash * step(0.02, tex.a)), tex.a * COLOR.a);
}
"""
static var _flash_shader: Shader

var _flash_token := 0
var _flash_material: ShaderMaterial

func hit_effect() -> void:
	await _flash(1.0)

## Builds (or reuses) the shared flash/grime material on any sprite. Static and public so
## `GrimeComponent` can put the same shader on Puppet *and* Face without EffectsPlayer
## exposing an instance reference to either — Puppet already owns one through `_flash()`
## below, and this is what stops the two from taking turns overwriting `.material`.
static func material_for(target: CanvasItem) -> ShaderMaterial:
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER
	var existing := target.material as ShaderMaterial
	if existing and existing.shader == _flash_shader:
		return existing
	var material := ShaderMaterial.new()
	material.shader = _flash_shader
	target.material = material
	return material

## Overlapping hits are common in a pile-up. Each flash takes a token and only the newest
## one is allowed to clear the flash, so an early timer cannot end a later flash and leave
## him stuck white.
func _flash(strength: float) -> void:
	if sprite == null:
		return
	if _flash_material == null:
		_flash_material = material_for(sprite)
	_flash_token += 1
	var token := _flash_token
	_flash_material.set_shader_parameter(&"flash", strength)
	await get_tree().create_timer(FLASH_SECONDS).timeout
	if is_instance_valid(sprite) and token == _flash_token:
		_flash_material.set_shader_parameter(&"flash", 0.0)

func explosion_effect(at: Vector2) -> void:
	if ExplosionScene == null:
		return
	var explosion := ExplosionScene.instantiate()
	# Parent to the current scene so the explosion outlives the exploding item.
	var host := get_tree().current_scene
	if host == null:
		return
	host.add_child(explosion)
	explosion.global_position = at
	# The effect is a generated animation, found by what it is rather than by name: the
	# scene was rebuilt once and a name lookup across its boundary is the same bug as an
	# absolute node path (CLAUDE.md).
	var animation := _find_animation(explosion)
	if animation and animation.sprite_frames:
		# An explosion must never loop. The Aseprite importer marks every animation as
		# looping, so the effect replayed for the whole life of the node — a 0.5s animation
		# inside a 1.5s node is three explosions for one grenade. Set on the shared
		# SpriteFrames deliberately: there is no case where a looping explosion is right.
		animation.sprite_frames.set_animation_loop(&"explosion", false)
		animation.animation_finished.connect(explosion.queue_free)
		animation.play(&"explosion")
	# Every explosion used to leak its node permanently. In a game left running all day
	# that is an unbounded node count — so a timer frees it whether or not the animation
	# ever finishes. A *bound method*, not a lambda: a lambda capturing `explosion` holds a
	# bare object id, and when the animation has already freed the node the callable
	# validates its captures before running, prints "Lambda capture at index 0 was freed"
	# and hands the body a null — once per explosion, fifteen per cluster throw, and no
	# `is_instance_valid` inside the body can ever see it. A Callable bound to the node is
	# disconnected for free when the node dies.
	explosion.get_tree().create_timer(EXPLOSION_LIFETIME).timeout.connect(explosion.queue_free)

static func _find_animation(root: Node) -> AnimatedSprite2D:
	if root is AnimatedSprite2D:
		return root
	for child in root.get_children():
		var found := _find_animation(child)
		if found:
			return found
	return null
