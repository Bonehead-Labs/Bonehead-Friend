class_name ItemGlow
extends RefCounted

## The outline an upgraded item wears (docs/decisions.md D41).
##
## A level-three bat has to *look* like a level-three bat, and the art is one sprite per
## item. So the upgrade is worn as light: a one-texel outline in the tier's colour around
## every opaque pixel, breathing slowly. It is drawn by a shader from the sprite's own
## alpha, which means it fits every item in the roster without a second sprite for any of
## them, and it is exactly one texel wide in *art* pixels — the sprite's scale scales the
## outline with it, so the glow stays pixel art at every item size.
##
## The breathing is `TIME` inside the shader, which costs the CPU nothing. Focus Mode Off
## stills it (`pulse` 0) rather than removing it: the glow is information — what tier this
## is — and information stays; only motion goes.

const SHADER_CODE := """
shader_type canvas_item;
uniform vec4 glow_color : source_color = vec4(1.0, 0.76, 0.28, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	// Any opaque neighbour one texel away, in the four cardinal directions: the classic
	// hard pixel outline. Diagonals would round the corners, which is not this game's art.
	float near = texture(TEXTURE, UV + vec2(px.x, 0.0)).a
		+ texture(TEXTURE, UV - vec2(px.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).a
		+ texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float edge = step(0.5, near) * (1.0 - step(0.5, tex.a));
	float breath = mix(1.0, 0.72 + 0.28 * sin(TIME * 2.6), pulse);
	// `COLOR` already is the texture times the modulate: multiplying by `tex` again squared
	// every colour, so an upgraded bat's wood drew at (112, 50, 16) instead of (169, 113, 63)
	// and an item looked darker the more it had earned (D75).
	vec4 body = COLOR;
	vec4 halo = vec4(glow_color.rgb, glow * breath * edge);
	COLOR = mix(body, halo, edge * step(0.01, glow));
}
"""

static var _shader: Shader

## Puts the tier's glow on a sprite, or takes it off. Idempotent: the material is made once
## per sprite and its uniforms rewritten after that.
static func apply(sprite: CanvasItem, colour: Color, strength: float, breathing: bool) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var material := sprite.material as ShaderMaterial
	if material == null or material.shader != _shared():
		if strength <= 0.0:
			return
		material = ShaderMaterial.new()
		material.shader = _shared()
		sprite.material = material
	material.set_shader_parameter(&"glow_color", colour)
	material.set_shader_parameter(&"glow", clampf(strength, 0.0, 1.0))
	material.set_shader_parameter(&"pulse", 1.0 if breathing else 0.0)

static func strength_of(sprite: CanvasItem) -> float:
	var material := sprite.material as ShaderMaterial if sprite else null
	if material == null or material.shader != _shared():
		return 0.0
	return float(material.get_shader_parameter(&"glow"))

static func _shared() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader
