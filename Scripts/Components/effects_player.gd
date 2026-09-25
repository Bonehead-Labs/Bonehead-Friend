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
## `grime` shares this material rather than getting one of its own: it is **three fixed
## patches of dirt** on his bones that gain opacity as he gets filthier (D46), masked to
## bright, low-saturation pixels so the near-black outline and the teal headphones — the one
## prop `docs/art-direction.md` says never to compromise — are never touched. `flash` is
## applied on top of the grimed colour, so a filthy buddy still flashes and returns to
## *grimy* rather than to clean.
##
## **Why the patches need `grime_cell`.** D44's grime was a hash over
## `floor(UV / TEXTURE_PIXEL_SIZE)`, which is the *atlas* texel — and the Aseprite Wizard
## packs all 74 body frames into one 768x768 atlas. So the speckle pattern was pinned to the
## atlas while the body walked across it, and the dirt crawled over him every time the frame
## changed. Anything positional in this shader has to be in **frame-local** coordinates, and
## `grime_cell` is the frame's size in texels: the atlas is a grid of `grime_cell`-sized
## cells, so `mod(texel, grime_cell)` is the position within the frame regardless of which
## cell the frame occupies. `GrimeComponent` reads it off the SpriteFrames. Left at 0 — every
## item in the game, which owns a plain texture — the whole texture is the frame and `UV` is
## already frame-local.
const FLASH_SHADER := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.0;
uniform vec4 grime_color : source_color = vec4(0.55, 0.50, 0.42, 1.0);
// The wardrobe (CosmeticData): a finish is a tint on the bone pixels, a set of headphones a
// dye on the teal. White is "as drawn". Same masks as grime, so a hat pass later can add a
// layer without touching this.
//
// Bone is multiplied, because it is near-white and white times a colour is that colour.
// Headphones are *dyed*: `phone_tint` is the colour they become, each pixel carrying its own
// brightness relative to the base teal so the shading survives. They used to be multiplied
// too, and teal has almost no red in it — so Pink Cans came out blue, Gold Cans green and
// Studio Whites a brighter teal, for Dollars. `phone_dye` is 0 when nothing is worn.
uniform vec4 bone_tint : source_color = vec4(1.0);
uniform vec4 phone_tint : source_color = vec4(1.0);
uniform float phone_dye = 0.0;
// Luma of the palette's base teal (46, 184, 179): the brightness a dyed pixel is measured from.
const float TEAL_LUMA = 0.5575;
// The frame's size in texels when the texture is an atlas of frames; 0 means the texture is
// the frame. See the note above `FLASH_SHADER` — without this the dirt crawls.
uniform float grime_cell = 0.0;
// Where this frame's drawing sits inside its cell, in texels. The body is *redrawn* higher
// or lower within a fixed 96px frame as he breathes, so a patch pinned to the cell slides
// off his bones even though it no longer crawls between frames. `BuddyArt` pushes the same
// per-frame offset it already uses to keep his face on his skull.
uniform vec2 grime_offset = vec2(0.0);

// One dirt patch: an ellipse in frame-local UV, falling off linearly to its rim.
float grime_patch(vec2 uv, vec2 centre, vec2 radius, float weight) {
	vec2 d = (uv - centre) / radius;
	float dist = length(d);
	return dist < 1.0 ? weight * (1.0 - dist) : 0.0;
}

// Three patches, placed clear of the face box (x 0.40..0.60, y 0.30..0.62 once his head
// bob is allowed for) so his expression is never sat on. Taken as a max rather than a sum:
// two overlapping ellipses adding up produce a bright seam where they cross, which reads as
// a third shape rather than as two patches of dirt. Quantised into flat steps because this
// is pixel art — a continuous falloff is an airbrush, and an airbrushed smudge on a
// hand-outlined skeleton reads as a rendering fault rather than as dirt.
float grime_shape(vec2 uv) {
	float best = grime_patch(uv, vec2(0.345, 0.470), vec2(0.070, 0.058), 1.00);
	best = max(best, grime_patch(uv, vec2(0.655, 0.625), vec2(0.062, 0.055), 0.90));
	best = max(best, grime_patch(uv, vec2(0.430, 0.735), vec2(0.082, 0.048), 0.80));
	if (best <= 0.0) {
		return 0.0;
	}
	return min(1.0, (floor(best * 3.0) + 1.0) / 3.0);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 lit = tex.rgb * COLOR.rgb;
	float luma = dot(lit, vec3(0.299, 0.587, 0.114));
	float sat = max(lit.r, max(lit.g, lit.b)) - min(lit.r, min(lit.g, lit.b));
	// Bright and low-saturation only: the teal headphones and the black outline are both
	// excluded by this, one on saturation and the other on brightness, with no per-tag
	// exception list to keep in sync as the roster grows.
	float bone_mask = step(0.5, luma) * step(sat, 0.15);
	// The headphones: saturated, and red well under both green and blue — the teal family.
	float phone_mask = step(0.25, sat) * step(lit.r, min(lit.g, lit.b) * 0.8);
	vec3 dressed = mix(lit, clamp(lit * bone_tint.rgb, 0.0, 1.0), bone_mask);
	vec3 dyed = clamp(phone_tint.rgb * (luma / TEAL_LUMA), 0.0, 1.0);
	dressed = mix(dressed, dyed, phone_mask * phone_dye);
	// Grime is three patches of dirt that darken as he gets filthier (D46), in frame-local
	// UV so they stay on the same bones from frame to frame.
	vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 cell_uv = grime_cell > 0.5
		? (mod(texel, grime_cell) + 0.5 - grime_offset) / grime_cell
		: UV;
	float dirt = grime_shape(cell_uv) * grime * bone_mask;
	vec3 grimed = mix(dressed, grime_color.rgb, dirt);
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

## `size` is the item's juice tier as a scale (D41): one for a fresh grenade, up to 1.75 for a
## finished one. The art grows with it, capped so a big charge still fits on a small desk.
func explosion_effect(at: Vector2, size: float = 1.0) -> void:
	if ExplosionScene == null:
		return
	var explosion := ExplosionScene.instantiate()
	# Parent to the current scene so the explosion outlives the exploding item.
	var host := get_tree().current_scene
	if host == null:
		return
	host.add_child(explosion)
	explosion.global_position = at
	explosion.scale = Vector2.ONE * clampf(size, 1.0, 1.6)
	# The physical half: a shockwave, smoke, sparks and a jolt from the world's pool. The
	# animation alone was a picture of an explosion; this is one happening on the desk.
	var fx := WorldFX.of(host)
	if fx:
		fx.boom(at, size)
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
