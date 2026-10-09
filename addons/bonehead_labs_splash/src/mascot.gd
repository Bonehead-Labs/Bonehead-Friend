extends Node2D
## The Bonehead Labs mascot, posed from boneheadlabs.org's CSS animations.
##
## Local units are the master SVG's (viewBox 380 190 1290 1650) with the origin at the feet, so
## the parent places the mascot by its feet and sizes it with [member Node2D.scale]. Each part is
## its own mipmapped SVG texture (art/mascot_<part>.svg), drawn in the site's order: the shadow,
## then the figure (body, cups, ink, mouth, eyes). [method pose] is pure: it sets every transform
## from its arguments, with no state carried between frames.

const Parts := preload("mascot_parts.gd")
const Ease := preload("splash_ease.gd")

const TEXTURES: Dictionary = {
	&"shadow": preload("../art/mascot_shadow.svg"),
	&"body": preload("../art/mascot_body.svg"),
	&"cups": preload("../art/mascot_cups.svg"),
	&"ink": preload("../art/mascot_ink.svg"),
	&"mouth": preload("../art/mascot_mouth.svg"),
	&"mouth_open": preload("../art/mascot_mouth_open.svg"),
	&"eyes": preload("../art/mascot_eyes.svg"),
	&"happy_eyes": preload("../art/mascot_happy_eyes.svg"),
}

## The site's jump (0.75 s, each interval eased by cubic-bezier(.3, .7, .4, 1)):
## [progress, translateY (fraction of the figure's height), scale x, scale y, rotation (deg)].
const JUMP_KEYS: Array = [
	[0.0, 0.0, 1.0, 1.0, 0.0],
	[0.16, 0.0, 1.12, 0.86, 0.0],
	[0.46, -0.2, 0.92, 1.1, -4.0],
	[0.72, 0.0, 1.07, 0.93, 0.0],
	[0.86, 0.0, 0.98, 1.02, 0.0],
	[1.0, 0.0, 1.0, 1.0, 0.0],
]
## The shadow through the jump: [progress, scale, alpha].
const SHADOW_KEYS: Array = [[0.0, 1.0, 1.0], [0.46, 0.55, 0.6], [1.0, 1.0, 1.0]]
## The site's idle "vibe": +-2.2 deg with a 1.2% lift, 1.1 s each way, ease-in-out, alternating.
const VIBE_HALF_PERIOD: float = 1.1
const VIBE_DEG: float = 2.2
const VIBE_LIFT: float = 0.012
const VIBE_SHADOW_X: float = 0.94
## A blink squeezes the eyes to 8% of their height.
const BLINK_SCALE: float = 0.08

var _art: Node2D = null
var _figure: Node2D = null
var _eyes_pivot: Node2D = null
var _sprites: Dictionary = {}
var _happy: bool = false


func _init() -> void:
	name = "Mascot"
	_art = Node2D.new()
	_art.name = "Art"
	_art.position = -Parts.FEET
	add_child(_art)
	_sprites[&"shadow"] = _add_part(_art, &"shadow", Vector2.ZERO)
	_figure = Node2D.new()
	_figure.name = "Figure"
	_art.add_child(_figure)
	for part: StringName in [&"body", &"cups", &"ink", &"mouth", &"mouth_open"]:
		_sprites[part] = _add_part(_figure, part, Vector2.ZERO)
	_eyes_pivot = Node2D.new()
	_eyes_pivot.name = "Eyes"
	_eyes_pivot.position = Vector2(0.0, Parts.EYE_LINE_Y)
	_figure.add_child(_eyes_pivot)
	_sprites[&"eyes"] = _add_part(_eyes_pivot, &"eyes", _eyes_pivot.position)
	_sprites[&"happy_eyes"] = _add_part(_figure, &"happy_eyes", Vector2.ZERO)
	pose(0.0, 0.0, 0.0, 0.0, false)


func _add_part(parent: Node2D, part: StringName, origin: Vector2) -> Sprite2D:
	var rect: Rect2 = Parts.PARTS[part]
	var sprite := Sprite2D.new()
	sprite.name = String(part).to_pascal_case()
	sprite.centered = false
	var tex: Texture2D = TEXTURES[part]
	sprite.texture = tex
	sprite.position = rect.position - origin
	if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
		sprite.scale = rect.size / Vector2(tex.get_size())
	parent.add_child(sprite)
	return sprite


## Poses the mascot. [param jump] is the jump's progress (0 and 1 are the rest pose),
## [param vibe_time] the idle clock in seconds, [param vibe_weight] how much of the idle shows
## (0 = rest), [param blink] 0 open to 1 shut, [param happy] the jump face (open mouth, arcs).
func pose(jump: float, vibe_time: float, vibe_weight: float, blink: float, happy: bool) -> void:
	var fig_h: float = Parts.FIGURE_BOX.size.y
	var j: Array = _sample(JUMP_KEYS, jump)
	var w: float = clampf(vibe_weight, 0.0, 1.0)
	# Start the idle mid-swing (upright), so blending it in never kicks the figure sideways.
	var cycle: float = fposmod(vibe_time / VIBE_HALF_PERIOD + 0.5, 2.0)
	var swing: float = Ease.in_out(cycle if cycle <= 1.0 else 2.0 - cycle)
	var vibe_rot: float = deg_to_rad(lerpf(-VIBE_DEG, VIBE_DEG, swing)) * w
	var vibe_lift: float = -VIBE_LIFT * fig_h * swing * w

	var feet: Vector2 = Parts.FEET
	var m := Transform2D(0.0, feet)
	m = m * Transform2D(vibe_rot, Vector2(0.0, vibe_lift))
	m = m * Transform2D(0.0, Vector2(0.0, float(j[0]) * fig_h))
	m = m * Transform2D(Vector2(float(j[1]), 0.0), Vector2(0.0, float(j[2])), Vector2.ZERO)
	m = m * Transform2D(deg_to_rad(float(j[3])), Vector2.ZERO)
	m = m * Transform2D(0.0, -feet)
	_figure.transform = m

	var s: Array = _sample(SHADOW_KEYS, jump)
	var shadow_x: float = float(s[0]) * lerpf(1.0, VIBE_SHADOW_X, swing * w)
	var shadow: Sprite2D = _sprites[&"shadow"]
	var rect: Rect2 = Parts.PARTS[&"shadow"]
	var centre: Vector2 = Parts.SHADOW_CENTER
	var base_scale: Vector2 = rect.size / Vector2(shadow.texture.get_size()) if shadow.texture != null else Vector2.ONE
	var k := Vector2(shadow_x, float(s[0]))
	shadow.scale = base_scale * k
	shadow.position = centre + (rect.position - centre) * k
	shadow.modulate.a = float(s[1])

	_eyes_pivot.scale = Vector2(1.0, lerpf(1.0, BLINK_SCALE, clampf(blink, 0.0, 1.0)))
	_happy = happy
	(_sprites[&"mouth"] as Sprite2D).visible = not happy
	(_sprites[&"eyes"] as Sprite2D).visible = not happy
	(_sprites[&"mouth_open"] as Sprite2D).visible = happy
	(_sprites[&"happy_eyes"] as Sprite2D).visible = happy


## Keyframe track [progress, values...] at [param x], each interval eased by the jump curve.
func _sample(keys: Array, x: float) -> Array:
	var p: float = clampf(x, 0.0, 1.0)
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if p <= float(b[0]):
			var span: float = maxf(float(b[0]) - float(a[0]), 0.0001)
			var e: float = Ease.jump((p - float(a[0])) / span)
			var out: Array = []
			for v in range(1, a.size()):
				out.append(lerpf(float(a[v]), float(b[v]), e))
			return out
	var last: Array = keys[keys.size() - 1]
	return last.slice(1)


## A cup's centre in this node's local space (the rest pose), for notes leaving the headphones.
func cup_local(side: int) -> Vector2:
	return (Parts.CUP_LEFT if side < 0 else Parts.CUP_RIGHT) - Parts.FEET


## The figure's height in local units (master SVG units).
func figure_height() -> float:
	return Parts.FIGURE_BOX.size.y


## The figure's rest box in this node's local space.
func figure_box_local() -> Rect2:
	return Rect2(Parts.FIGURE_BOX.position - Parts.FEET, Parts.FIGURE_BOX.size)


## Test read.
func get_state() -> Dictionary:
	return {
		"happy": _happy,
		"eye_scale_y": _eyes_pivot.scale.y,
		"figure_transform": _figure.transform,
		"shadow_alpha": (_sprites[&"shadow"] as Sprite2D).modulate.a,
		"textures": _sprites.size(),
	}
