class_name RotorBlur
extends Node2D

## A rotor too fast to watch, drawn the way film and games draw one (docs/decisions.md D75).
##
## Anything that turns past half its own symmetry in one drawn frame reads as turning
## *backwards*: the eye joins each arm to the nearest arm in the next frame, and past half the
## gap that is the one behind. A three-arm fidget spinner at full speed turns 73 degrees a
## frame at the 30 fps idle cap, against a limit of 60 — the wagon wheel in every western.
## Two things fix it, and neither touches the spin the toy pays by:
##
## - **The picture turns at most `VISUAL_LIMIT` of the symmetry in a frame**, so whatever the
##   eye joins up is always forward. At 60 fps the spinner never reaches the limit; at 30 it
##   is drawn turning more slowly than it spins, which nobody can count at four turns a second.
## - **Past `blur_from` rad/s it spins over a disc**: the rotor's own picture swept round its
##   hub, ring by ring — what a real one looks like spinning, orange where the arms pass and grey
##   where the weights do, as solid as the share of each ring the picture covers. The disc
##   dissolves in by `blur_full` and the crisp rotor keeps turning, forward, on top of it.
##
## **Every pixel of it is ink or nothing.** A ring's share of cover is an ordered dither, not an
## alpha, and the disc fades in by the same dither: a half-transparent smear over the chroma
## green a streamer keys out is a green ghost (D68's rule for the numbers, kept here). Each
## ring is the colour it is most of, leaving the outline out, so the disc is the sprite's own
## palette: an average of orange, red and steel is a brown the toy never was.
##
## Made once per texture, from the texture, by the same rule for a spinner and a wheel. A child
## of the rotor drawn behind it (`show_behind_parent`), held upright against the rotor's turn so
## its rings stay on the pixel grid. Built by `attach` the first time the rotor turns; hidden at
## rest, so a still toy pays nothing.

## The most of its symmetry angle the picture may turn in one drawn frame. Below a half, with
## margin: at exactly a half a turn is as far forward as it is back.
const VISUAL_LIMIT := 0.375
## A ring's cover is lifted by this power (under 1) so the tips of three thin arms still make a
## rim you can see.
const COVER_POWER := 0.7
## Outline and deep shadow: counted in a ring's cover, left out of its colour.
const OUTLINE_LUMA := 0.12

## The disc's dither: a 4x4 ordered (Bayer) threshold per texel against cover x strength.
const SHADER_CODE := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
void fragment() {
	// `COLOR` is already the texture times the modulate; the texture's alpha is the ring's
	// cover, so the modulate's own alpha is what is left of `COLOR.a` without it.
	vec4 tex = texture(TEXTURE, UV);
	ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE)) % 4;
	float threshold = (BAYER[p.y * 4 + p.x] + 0.5) / 16.0;
	float faded = tex.a > 0.0 ? COLOR.a / tex.a : 0.0;
	COLOR = vec4(COLOR.rgb, step(threshold, tex.a * strength) * faded);
}
"""

## The angle after which the rotor looks the same: a third of a turn for three arms, a whole
## turn for a wheel with one bolt.
var symmetry := TAU
## Angular speed where the disc starts, and where it is at full strength, rad/s.
var blur_from := 10.0
var blur_full := 24.0

var _rotor: Sprite2D
var _disc: Sprite2D
var _material: ShaderMaterial

static var _discs := {}
static var _shader: Shader

## A blur for `rotor`, made once and kept. Returns the one already there if there is one.
static func attach(rotor: Sprite2D, symmetry_angle: float, from: float, full: float) -> RotorBlur:
	if rotor == null:
		return null
	for child in rotor.get_children():
		if child is RotorBlur:
			return child
	var blur := RotorBlur.new()
	blur.name = "RotorBlur"
	blur.symmetry = symmetry_angle
	blur.blur_from = from
	blur.blur_full = maxf(full, from + 0.01)
	blur.show_behind_parent = true
	blur.visible = false
	blur._rotor = rotor
	rotor.add_child(blur)
	return blur

## The largest turn the picture may make in one call of length `delta`. Per *drawn frame*,
## not per call: a rotor turned from the physics tick is drawn once every two ticks at the
## 30 fps cap, so a call gets its share of the frame's limit.
func step_limit(delta: float) -> float:
	return symmetry * VISUAL_LIMIT * delta / _frame(delta)

## Turns the rotor for a true spin of `omega` rad/s over `delta` seconds, capped, and dresses it
## for that speed. Returns the angle the picture actually turned.
func turn(omega: float, delta: float) -> float:
	if _rotor == null or delta <= 0.0:
		return 0.0
	var limit := step_limit(delta)
	var step := clampf(omega * delta, -limit, limit)
	_rotor.rotation += step
	_dress(strength(absf(omega)))
	return step

## Still: the crisp rotor alone.
func rest() -> void:
	_dress(0.0)

## The share of full blur at this speed, 0..1.
func strength(speed: float) -> float:
	return smoothstep(blur_from, blur_full, speed)

func is_blurred() -> bool:
	return visible

func _frame(delta: float) -> float:
	return maxf(get_process_delta_time(), delta) if is_inside_tree() else delta

func _dress(b: float) -> void:
	if b <= 0.0:
		visible = false
		return
	if _disc == null:
		_build()
	visible = true
	_disc.rotation = -_rotor.rotation
	_material.set_shader_parameter(&"strength", b)

func _build() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_disc = Sprite2D.new()
	_disc.name = "Disc"
	_disc.centered = _rotor.centered
	_disc.offset = _rotor.offset
	_disc.texture = RotorBlur.disc_for(_rotor)
	_disc.material = _material
	add_child(_disc)

## The rotor's picture swept round the point it turns about, ring by ring, on the same canvas
## and grid as the texture so it lines up with no offsets of its own. Alpha is each ring's
## cover, for the dither; colour is the commonest colour in it that is not outline. Cached per
## texture and pivot.
static func disc_for(rotor: Sprite2D) -> Texture2D:
	var texture := rotor.texture
	if texture == null:
		return null
	var size := texture.get_size()
	var pivot := (size * 0.5 if rotor.centered else Vector2.ZERO) - rotor.offset
	var key := "%s@%s" % [texture.resource_path if texture.resource_path != "" 		else str(texture.get_instance_id()), pivot]
	if _discs.has(key):
		return _discs[key]
	var src := texture.get_image()
	if src == null:
		return null
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	# Per ring of whole-pixel radius: how many pixels it has, how many the picture covers, and
	# how often each colour that is not outline turns up in it.
	var cells := {}
	var covered := {}
	var counts := {}
	for y in h:
		for x in w:
			var r := int(round(Vector2(x + 0.5, y + 0.5).distance_to(pivot)))
			cells[r] = int(cells.get(r, 0)) + 1
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			covered[r] = int(covered.get(r, 0)) + 1
			if c.get_luminance() <= OUTLINE_LUMA:
				continue
			var tally: Dictionary = counts.get(r, {})
			var ink := Color(c, 1.0)
			tally[ink] = int(tally.get(ink, 0)) + 1
			counts[r] = tally
	var inks := {}
	for r in covered:
		var best := Color(0, 0, 0)
		var most := 0
		var tally: Dictionary = counts.get(r, {})
		for ink in tally:
			if int(tally[ink]) > most:
				most = tally[ink]
				best = ink
		best.a = pow(float(covered[r]) / float(cells[r]), COVER_POWER)
		inks[r] = best
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var r := int(round(Vector2(x + 0.5, y + 0.5).distance_to(pivot)))
			if inks.has(r):
				out.set_pixel(x, y, inks[r])
	var disc := ImageTexture.create_from_image(out)
	_discs[key] = disc
	return disc
