class_name AbilityFX
extends Node2D

## How an ability reads (docs/decisions.md D77): one vocabulary of four stages, so thirty-four verbs
## read as one family, and the next one gets the family look the day it lands.
##
## The owner, of the abilities: "amazing", and then "I also want nice visual effects for each one,
## for instance the frying pan one was not obvious to me." The mechanics were right and the pan's
## ring was a four-star burst on a white skull. So every ability now says the same four things, in
## the same places, each in its own colour:
##
##   READY       a glint on the held weapon in its tier colour, twinkling: there while the ability
##               can be used, gone while it runs or cools, and back with a pop when it is ready.
##   ACTIVATION  the glint flares off the weapon with a ring and the ability's own burst, and a
##               callout — its name — rises in the display face through FXLayer's placement: big the
##               first few times this session, smaller once it has been learned.
##   STATE       a badge over his head for as long as the state lasts: the state's icon on a dark
##               disc, inside a ring in the ability's colour that drains as it counts down, with pips
##               for anything it is counting (hits stored, staples in him).
##   PAYOFF      where it lands: a flash, impact lines, two rings and a burst in the ability's
##               colour, and a jolt, all scaled by `size` 0..1 — and its word ("BONG!", "SIX!").
##
## ## Using it from anything held
##
##   var afx := AbilityFX.of(node)                        # the world's; null with no WorldFX
##   AbilityFX.glint(sprite, point, colour, afx)          # READY: a ReadyGlint; .show_ready(on, pop)
##   afx.activate(at, colour, glyph)                      # ACTIVATION: flare, ring, burst
##   AbilityFX.callout(node, text, at, colour, key, weight) # the words, through FXLayer
##   AbilityFX.state(him, kind, spec, owner, afx)         # STATE: a StateMark on him
##   afx.payoff(at, size, colour)                         # PAYOFF
##
## A held weapon calls none of these itself: `WeaponAbility` does, from its press, its `tell`s and
## its `paid_off`s, with the ability's look from `AbilityLooks` — so a new ability is a row there,
## or nothing at all and the defaults. `afx.waves` (a gong's rings) and `afx.spray` (a burst of any
## texture, the icons included) are there for a hook with a moment of its own.
##
## ## The rules it keeps
##
## - **Nothing runs at rest.** The glint is a sprite drawn once, its twinkle a shader on `TIME` (no
##   CPU, like `ItemGlow`); a badge runs `_process` only while it is on him; a burst only while it
##   is in flight; the pools are built once and parked.
## - **Nothing fades** (D68): everything leaves by drawing in — a ring thins, a flash shrinks, a
##   badge folds to nothing. Every pixel is ink or nothing, for the chroma key.
## - **Everything has a dark rim**, because it is drawn over a white skeleton (white on him is
##   invisible, CLAUDE.md), a dark desk and the chroma green alike.
## - **Focus Mode.** Off: the glint and the badge stay (they are information) but hold still; the
##   flare, the burst, the payoff and the words are motion, and stop. Subtle halves the chips.

const NAME := "AbilityFX"

const OUTLINE := Color("141210")
const DISC := Color("1a1714")
const TRACK := Color("4a433a")
const GOLD := Color("ffc247")

## An ability's first few uses this session call out at headline size (D77); after that it has been
## learned, and a word the size of a headline on every use would shout for eight hours.
const BIG_USES := 3

## One art pixel is two world pixels, the scale every sprite is drawn at.
const ART_SCALE := 2.0

const BURST_POOL := 8
const SPRAY_POOL := 8

## A burst's parts, in seconds: the flash, the impact lines, one ring's expansion, the flare.
const FLASH_T := 0.12
const LINES_T := 0.2
const RING_T := 0.38
const FLARE_T := 0.24

## Uses of each ability this session, by ability id: plain data, so a static is safe (a static
## holding a texture reads as a leak at exit — ExplosionUtil's note — so those live on the node).
static var _uses := {}

var _bursts: Array[Burst] = []
var _next_burst := 0
var _sprays: Array[GPUParticles2D] = []
var _next_spray := 0
var _icons := {}
var _materials := {}
var _glint_material: ShaderMaterial
var _glint_still: ShaderMaterial
var _rng := RandomNumberGenerator.new()

## The world's ability effects: a child of `WorldFX`, built the first time anything asks, found by
## group through it (D9) and never by path. Null in a scene with no WorldFX, which every caller treats
## as "draw nothing", never as an error.
static func of(node: Node) -> AbilityFX:
	var world := WorldFX.of(node)
	if world == null:
		return null
	var known := world.get_node_or_null(NAME) as AbilityFX
	if known:
		return known
	var made := AbilityFX.new()
	made.name = NAME
	world.add_child(made)
	return made

static func moving() -> bool:
	return Settings.focus_intensity != Settings.Intensity.OFF

## One more use of `id`, for how big its words are.
static func note_use(id: StringName) -> void:
	_uses[id] = int(_uses.get(id, 0)) + 1

static func uses_of(id: StringName) -> int:
	return int(_uses.get(id, 0))

## How big an ability's words are now: headline size while it is new, then small. A landing's word
## stays a little bigger than a name, because it is the payoff.
static func weight_for(id: StringName, landing: bool) -> float:
	if uses_of(id) <= BIG_USES:
		return 1.0
	return 0.45 if landing else 0.15

func _ready() -> void:
	z_index = 40
	for i in BURST_POOL:
		var burst := Burst.new()
		burst.name = "Burst%d" % i
		burst.visible = false
		add_child(burst)
		_bursts.append(burst)
	for i in SPRAY_POOL:
		var spray_node := GPUParticles2D.new()
		spray_node.name = "Spray%d" % i
		spray_node.emitting = false
		spray_node.one_shot = true
		spray_node.explosiveness = 1.0
		spray_node.local_coords = false
		spray_node.z_index = -1
		add_child(spray_node)
		_sprays.append(spray_node)

# --- ACTIVATION and PAYOFF ----------------------------------------------------------------

## The ability starting, at the weapon: its glint flares off it, a ring in its colour, and a burst of
## `glyph` (a UI glyph or one of `ICONS`).
func activate(at: Vector2, colour: Color, glyph: StringName = &"star", count: int = 6) -> void:
	if not moving():
		return
	_take().fire(at, colour, {"flare": 30.0, "rings": [[0.0, 46.0, 4.0, colour]]})
	spray(at, texture_for(glyph, colour), tint_for(glyph, colour), count, 230.0, 0.55, 500.0)

## The moment it lands, scaled by `size` 0..1: a flash, impact lines, two rings, stars and a jolt.
func payoff(at: Vector2, size: float, colour: Color) -> void:
	if not moving():
		return
	var s := clampf(size, 0.0, 1.0)
	_take().fire(at, colour, {
		"flash": 12.0 + 22.0 * s,
		"lines": 6 + int(round(6.0 * s)), "line_from": 16.0 + 16.0 * s, "line_to": 42.0 + 96.0 * s,
		"rings": [[0.0, 56.0 + 160.0 * s, 3.0 + 3.0 * s, colour],
			[0.08, 36.0 + 110.0 * s, 2.0 + 2.0 * s, colour.lightened(0.45)]],
	})
	spray(at, texture_for(&"star", GOLD), Color.WHITE, 3 + int(round(9.0 * s)), 180.0 + 220.0 * s, 0.7, 800.0)
	# A jolt for a big one, unless the ability has already jolted the desk for this moment: the shake
	# moves where the cursor maps to (D39), so a second, bigger one on top would move the hand too.
	var world := WorldFX.of(self)
	if world and s >= 0.5 and not world.is_shaking():
		world.shake(2.0 + 6.0 * s)

## Concentric waves out of a point, `gap` seconds apart: a gong struck, a bell, a pulse.
func waves(at: Vector2, colour: Color, count: int, radius: float, gap: float = 0.07,
		width: float = 5.0) -> void:
	if not moving():
		return
	var rings: Array = []
	for i in count:
		var k := float(i) / float(maxi(count - 1, 1))
		rings.append([gap * float(i), radius * lerpf(1.0, 0.6, k), lerpf(width, 2.0, k), colour])
	_take().fire(at, colour, {"rings": rings})

## A one-shot burst of `texture` thrown from a point and falling: stars, flames, envelopes, keys.
func spray(at: Vector2, texture: Texture2D, colour: Color, count: int, speed: float,
		lifetime: float = 0.6, gravity: float = 700.0) -> void:
	if not moving() or texture == null or _sprays.is_empty():
		return
	if Settings.focus_intensity == Settings.Intensity.SUBTLE:
		count = maxi(1, count / 2)
	var em := _sprays[_next_spray]
	_next_spray = (_next_spray + 1) % _sprays.size()
	em.emitting = false
	em.global_position = at
	em.texture = texture
	em.modulate = colour
	em.amount = maxi(1, count)
	em.lifetime = lifetime
	em.process_material = _material(speed, gravity)
	em.restart()

func _material(speed: float, gravity: float) -> ParticleProcessMaterial:
	var key := "%d|%d" % [int(speed), int(gravity)]
	if _materials.has(key):
		return _materials[key]
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = speed * 0.45
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, gravity, 0)
	mat.damping_min = 20.0
	mat.damping_max = 60.0
	mat.angular_velocity_min = -360.0
	mat.angular_velocity_max = 360.0
	# Leaves by shrinking, never by fading (D68).
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(0.7, 0.9))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	_materials[key] = mat
	return mat

func _take() -> Burst:
	var burst := _bursts[_next_burst]
	burst.turn_from = _rng.randf() * TAU
	_next_burst = (_next_burst + 1) % _bursts.size()
	return burst

## A glyph for a spray: one of `ICONS` plotted in `colour`, a four-pixel chip, or a UI glyph (the
## last two white, tinted by the emitter: `tint_for`).
func texture_for(glyph: StringName, colour: Color) -> Texture2D:
	if ICONS.has(glyph):
		return icon(glyph, colour)
	if glyph == &"chip":
		if not _icons.has("chip"):
			var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			_icons["chip"] = ImageTexture.create_from_image(image)
		return _icons["chip"]
	return UIStyle.glyph(glyph)

## What to tint a `texture_for` glyph by: nothing for an icon, which is plotted in its colour.
static func tint_for(glyph: StringName, colour: Color) -> Color:
	return Color.WHITE if ICONS.has(glyph) else colour

# --- the words -------------------------------------------------------------------------------

## An ability's word, through FXLayer's placement (D63): it never lands on another line, and it
## leaves by drawing in (D68). Keyed per ability, so its landing replaces its name rather than
## stacking under it. `weight` 1 is a headline-sized first use, 0 the small everyday one. False when
## nothing was drawn — no FX layer in this scene (the suites' desks), Focus Off, or no room.
static func callout(node: Node, text: String, at: Vector2, colour: Color, key: StringName,
		weight: float) -> bool:
	if text.is_empty() or node == null or not node.is_inside_tree():
		return false
	var layer := FXLayer.of(node)
	if layer == null:
		return false
	return layer.callout(text, at, colour, weight, key).is_finite()

# --- READY -----------------------------------------------------------------------------------

## The ready glint on `sprite`, at `point` in its parent body's frame, built once and kept: a child of
## the sprite, so it turns and swings with the weapon at no cost. Null with no sprite.
static func glint(sprite: Sprite2D, point: Vector2, colour: Color, afx: AbilityFX) -> ReadyGlint:
	if sprite == null or not is_instance_valid(sprite):
		return null
	var known := sprite.get_node_or_null("ReadyGlint") as ReadyGlint
	if known:
		known.tint(colour, afx)
		return known
	var made := ReadyGlint.new()
	made.name = "ReadyGlint"
	made.visible = false
	made.z_index = 2
	sprite.add_child(made)
	# Where the point is on the picture, and at a fixed screen size whatever the sprite's scale.
	var parent_scale := sprite.scale.x if absf(sprite.scale.x) > 0.01 else 1.0
	made.position = (sprite.transform.affine_inverse() * point).round()
	made.base = Vector2.ONE * (ART_SCALE / absf(parent_scale))
	made.scale = made.base
	made.tint(colour, afx)
	return made

## A light over `sprite`: an additive copy of its own picture in `colour`, `strength` 0..1 of it, so
## the weapon glows rather than being painted over (the transform's light, D74). Zero puts it out. A
## child of the sprite, built on first use and kept; it draws once and costs nothing unlit.
static func shine(sprite: Sprite2D, colour: Color, strength: float) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var light := sprite.get_node_or_null("AbilityShine") as Sprite2D
	if strength <= 0.0:
		if light:
			light.visible = false
		return
	if light == null:
		light = Sprite2D.new()
		light.name = "AbilityShine"
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		light.material = add
		light.z_index = 1
		sprite.add_child(light)
	light.texture = sprite.texture
	light.centered = sprite.centered
	light.offset = sprite.offset
	light.flip_h = sprite.flip_h
	light.flip_v = sprite.flip_v
	light.region_enabled = sprite.region_enabled
	light.region_rect = sprite.region_rect
	light.hframes = sprite.hframes
	light.vframes = sprite.vframes
	light.frame = sprite.frame
	var k := clampf(strength, 0.0, 1.0)
	light.modulate = Color(colour.r * k, colour.g * k, colour.b * k, 1.0)
	light.visible = true

func glint_material(still: bool) -> ShaderMaterial:
	if _glint_material == null:
		var shader := Shader.new()
		shader.code = GLINT_SHADER
		_glint_material = ShaderMaterial.new()
		_glint_material.shader = shader
		_glint_material.set_shader_parameter(&"pulse", 1.0)
		_glint_still = ShaderMaterial.new()
		_glint_still.shader = shader
		_glint_still.set_shader_parameter(&"pulse", 0.0)
	return _glint_still if still else _glint_material

## The twinkle: every so often the whole star goes white for a tenth of a second. On `TIME`, so it
## costs the CPU nothing; `pulse` 0 at Focus Off holds it still. Colour only — a vertex scale would
## resample the pixels.
const GLINT_SHADER := """
shader_type canvas_item;
uniform float pulse = 1.0;
void fragment() {
	float t = fract(TIME * 0.55);
	float flash = pulse * step(t, 0.07);
	float ink = step(0.3, dot(COLOR.rgb, vec3(0.333)));
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash * ink);
}
"""

## A four-point sparkle on the held weapon while its ability is ready (D77). Drawn once: no
## `_process`, and a tween only for the pop when it comes back.
class ReadyGlint extends Sprite2D:
	var base := Vector2.ONE
	var colour := Color.WHITE
	var _pop: Tween

	func tint(value: Color, afx: AbilityFX) -> void:
		if value == colour and texture != null:
			return
		colour = value
		texture = afx.icon(&"glint", value) if afx else AbilityFX.plot(&"glint", value)
		if afx:
			material = afx.glint_material(not AbilityFX.moving())

	## On while it can be used; `pop` when it has just become ready, so the eye goes to it.
	func show_ready(on: bool, pop: bool) -> void:
		if not on:
			if _pop and _pop.is_valid():
				_pop.kill()
			scale = base
			visible = false
			return
		visible = true
		if not pop or not AbilityFX.moving():
			scale = base
			return
		if _pop and _pop.is_valid():
			_pop.kill()
		scale = base * 2.5
		_pop = create_tween()
		_pop.tween_property(self, "scale", base, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func is_popping() -> bool:
		return _pop != null and _pop.is_valid() and _pop.is_running()

# --- STATE -----------------------------------------------------------------------------------

## Puts the badge of `kind` on him, or bumps it if it is already there. `spec` (from `AbilityLooks`):
##   icon     one of `ICONS`
##   colour   its ring's colour
##   seconds  how long it lasts, or 0 to last while `while` is true of `owner`
##   while    a method of `owner`: true while the state lasts
##   left     a method of `owner`: 0..1 of it left, for the ring (default: `seconds`, or full)
##   count    a method or property of `owner`: pips under the badge, for what it is counting
##   refresh  a timed state told again starts its clock again
##   aura     {glyph, colour, amount}: chips coming off him for as long as it lasts
##   static   drawn once and never ticked, for a badge over something that does not move and may
##            wait for hours (a letter opener stuck in the desk); the owner takes it off
## `him` is whatever it goes over: him, or the weapon itself.
## His child, `top_level` so it stays upright over his skull whatever he is doing; freed when the
## state ends, or at once when `owner` leaves the tree (`clear_states`).
static func state(him: Node2D, kind: StringName, spec: Dictionary, owner: Object,
		afx: AbilityFX) -> StateMark:
	if him == null or not is_instance_valid(him) or not him.is_inside_tree():
		return null
	var node_name := "AbilityState%s" % String(kind).to_pascal_case()
	var known := him.get_node_or_null(node_name) as StateMark
	if known and not known.is_leaving():
		known.bump(bool(spec.get("refresh", false)))
		return known
	var mark := StateMark.new()
	mark.name = node_name
	mark.kind = kind
	mark.top_level = true
	mark.z_index = 45
	mark.target = him
	mark.owner_ref = weakref(owner) if owner else null
	var colour: Color = spec.get("colour", Color.WHITE)
	mark.colour = colour
	mark.icon = afx.icon(StringName(spec.get("icon", &"pow")), colour) if afx \
		else AbilityFX.plot(StringName(spec.get("icon", &"pow")), colour)
	mark.seconds = float(spec.get("seconds", 1.0))
	mark.while_method = StringName(spec.get("while", &""))
	mark.left_method = StringName(spec.get("left", &""))
	mark.count_key = StringName(spec.get("count", &""))
	mark.refresh = bool(spec.get("refresh", false))
	mark.still = bool(spec.get("static", false))
	var aura: Dictionary = spec.get("aura", {})
	him.add_child(mark)
	if mark.still:
		mark.set_process(false)
		mark.place()
		mark.queue_redraw()
		return mark
	if not aura.is_empty() and afx and AbilityFX.moving():
		var glyph := StringName(aura.get("glyph", &"chip"))
		var tint: Color = aura.get("colour", colour)
		mark.add_aura(afx.texture_for(glyph, tint), AbilityFX.tint_for(glyph, tint),
			int(aura.get("amount", 8)), float(aura.get("rise", 60.0)))
	mark.place()
	return mark

## Takes every badge `owner` put on him off at once: a weapon binned mid-state leaves nothing on him.
static func clear_states(him: Node2D, owner: Object) -> void:
	if him == null or not is_instance_valid(him):
		return
	for child in him.get_children():
		var mark := child as StateMark
		if mark and mark.owner_ref and mark.owner_ref.get_ref() == owner:
			mark.queue_free()

## The badges on him now, for the suites.
static func states_on(him: Node2D) -> Array[StringName]:
	var out: Array[StringName] = []
	if him == null or not is_instance_valid(him):
		return out
	for child in him.get_children():
		var mark := child as StateMark
		if mark and not mark.is_queued_for_deletion():
			out.append(mark.kind)
	return out

## One state on him: its icon on a dark disc, a ring in its colour that drains as it counts down, and
## pips under it for what it counts. Pops in, bumps when it is told again, folds to nothing when it
## ends. Beside any other badge on him, never on top of it.
class StateMark extends Node2D:
	const RADIUS := 15.0
	const WIDTH := 4.0
	const GAP := 38.0
	const ABOVE := 26.0
	const POP_T := 0.16
	const LEAVE_T := 0.14
	const MOST_PIPS := 10

	var target: Node2D
	var kind: StringName = &""
	var icon: Texture2D
	var colour := Color.WHITE
	var owner_ref: WeakRef
	var seconds := 1.0
	var while_method: StringName = &""
	var left_method: StringName = &""
	var count_key: StringName = &""
	var refresh := false
	## Drawn once, never ticked: it waits over something still for as long as it has to.
	var still := false
	var aura: GPUParticles2D
	var fraction := 1.0
	var pips := 0
	var _age := 0.0
	var _clock := 0.0
	var _leaving := -1.0
	var _bump := 0.0

	func is_leaving() -> bool:
		return _leaving >= 0.0 or is_queued_for_deletion()

	## Told again: a pulse, and a timed state that refreshes starts its clock over.
	func bump(restart: bool) -> void:
		_bump = 1.0
		if restart:
			_clock = 0.0

	func add_aura(texture: Texture2D, tint: Color, amount: int, rise: float) -> void:
		if texture == null:
			return
		aura = GPUParticles2D.new()
		aura.name = "Aura"
		aura.top_level = true
		aura.local_coords = false
		# It rides on him, so it updates every frame rather than at 30 fps and leaving clumps.
		aura.fixed_fps = 0
		aura.z_index = 44
		aura.amount = maxi(1, amount)
		aura.lifetime = 0.7
		aura.texture = texture
		aura.modulate = tint
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(18.0, 26.0, 1.0)
		mat.direction = Vector3(0, -1, 0)
		mat.spread = 25.0
		mat.initial_velocity_min = rise * 0.5
		mat.initial_velocity_max = rise
		mat.gravity = Vector3(0, -rise * 0.5, 0)
		mat.scale_min = 0.7
		mat.scale_max = 1.1
		var curve := CurveTexture.new()
		var shape := Curve.new()
		shape.add_point(Vector2(0.0, 0.6))
		shape.add_point(Vector2(0.25, 1.0))
		shape.add_point(Vector2(1.0, 0.0))
		curve.curve = shape
		mat.scale_curve = curve
		aura.process_material = mat
		add_child(aura)
		aura.emitting = true

	func _owner() -> Object:
		return owner_ref.get_ref() if owner_ref else null

	func _process(delta: float) -> void:
		if not is_instance_valid(target) or not target.is_inside_tree():
			queue_free()
			return
		_age += delta
		_clock += delta
		_bump = maxf(0.0, _bump - delta * 5.0)
		var owner := _owner()
		var alive := true
		if while_method != &"":
			alive = owner != null and owner.has_method(while_method) and bool(owner.call(while_method))
			fraction = 1.0
			if owner != null and left_method != &"" and owner.has_method(left_method):
				var left := float(owner.call(left_method))
				fraction = clampf(left, 0.0, 1.0) if left >= 0.0 else 1.0
		else:
			fraction = clampf(1.0 - _clock / maxf(seconds, 0.01), 0.0, 1.0)
			alive = _clock < seconds
			if owner == null and owner_ref != null:
				alive = false
		if owner != null and count_key != &"":
			var n = owner.call(count_key) if owner.has_method(count_key) else owner.get(count_key)
			pips = int(n) if n != null else 0
		if not alive and _leaving < 0.0:
			_leaving = 0.0
			if aura:
				aura.emitting = false
		if _leaving >= 0.0:
			_leaving += delta
			if _leaving >= LEAVE_T:
				queue_free()
				return
		place()
		queue_redraw()

	## Over his skull, beside any other badge on him.
	func place() -> void:
		if not is_instance_valid(target):
			return
		var rect := Rect2(target.global_position - Vector2(24, 48), Vector2(48, 96))
		if target.has_method("get_interaction_rect"):
			rect = target.call("get_interaction_rect")
		var marks: Array[Node] = []
		for child in target.get_children():
			if child is StateMark and not (child as StateMark).is_queued_for_deletion():
				marks.append(child)
		var index := marks.find(self)
		var offset := (float(index) - float(marks.size() - 1) * 0.5) * GAP if index >= 0 else 0.0
		global_position = Vector2(rect.get_center().x + offset, rect.position.y - ABOVE).round()
		if aura:
			aura.global_position = rect.get_center().round()

	func _size() -> float:
		if still:
			return 1.0
		if not AbilityFX.moving():
			return 0.0 if _leaving >= 0.0 else 1.0
		if _leaving >= 0.0:
			return clampf(1.0 - _leaving / LEAVE_T, 0.0, 1.0)
		if _age < POP_T:
			var k := _age / POP_T
			# Out past its size and back: it lands rather than appears.
			return k * 1.25 if k < 0.7 else lerpf(0.875, 1.0, (k - 0.7) / 0.3)
		return 1.0 + 0.22 * _bump

	func _draw() -> void:
		var s := _size()
		if s <= 0.01:
			return
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
		draw_circle(Vector2.ZERO, RADIUS + WIDTH * 0.5 + 2.0, AbilityFX.OUTLINE)
		draw_circle(Vector2.ZERO, RADIUS - WIDTH * 0.5, AbilityFX.DISC)
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, AbilityFX.TRACK, WIDTH, false)
		if fraction > 0.0:
			var steps := maxi(3, int(40.0 * fraction))
			draw_arc(Vector2.ZERO, RADIUS, -PI * 0.5, -PI * 0.5 + TAU * fraction, steps, colour, WIDTH, false)
		if icon:
			var size := icon.get_size() * AbilityFX.ART_SCALE
			draw_texture_rect(icon, Rect2((-size * 0.5).round(), size), false)
		var shown := mini(pips, MOST_PIPS)
		if shown > 0:
			var left := -float(shown) * 4.0 + 1.0
			for i in shown:
				var at := Vector2(left + float(i) * 8.0, RADIUS + 9.0)
				draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), AbilityFX.OUTLINE)
				draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), colour)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- the bursts --------------------------------------------------------------------------------

## One burst, pooled: any of a flare (a four-point star that spins and shrinks), a flash (an
## eight-point star that shrinks), impact lines that run outward, and rings that expand and thin —
## each with a dark rim under it. `_process` only while one is in flight.
class Burst extends Node2D:
	## Where its lines and stars point, set by the pool from its own generator: the global one is the
	## suites' (they seed it per weapon), and a flourish must not move what they measure.
	var turn_from := 0.0
	var colour := Color.WHITE
	var flare := 0.0
	var flash := 0.0
	var lines := 0
	var line_from := 0.0
	var line_to := 0.0
	var rings: Array = []
	var _t := 0.0
	var _life := 0.0
	var _turn := 0.0

	func fire(at: Vector2, tint: Color, spec: Dictionary) -> void:
		global_position = at.round()
		colour = tint
		flare = float(spec.get("flare", 0.0))
		flash = float(spec.get("flash", 0.0))
		lines = int(spec.get("lines", 0))
		line_from = float(spec.get("line_from", 0.0))
		line_to = float(spec.get("line_to", 0.0))
		rings = spec.get("rings", [])
		_turn = turn_from
		_t = 0.0
		_life = 0.0
		if flare > 0.0:
			_life = maxf(_life, AbilityFX.FLARE_T)
		if flash > 0.0:
			_life = maxf(_life, AbilityFX.FLASH_T)
		if lines > 0:
			_life = maxf(_life, AbilityFX.LINES_T)
		for ring in rings:
			_life = maxf(_life, float(ring[0]) + AbilityFX.RING_T)
		visible = true
		set_process(true)
		queue_redraw()

	func is_busy() -> bool:
		return is_processing()

	func _process(delta: float) -> void:
		_t += delta
		if _t >= _life:
			visible = false
			set_process(false)
			return
		queue_redraw()

	func _draw() -> void:
		for ring in rings:
			var k := (_t - float(ring[0])) / AbilityFX.RING_T
			if k < 0.0 or k > 1.0:
				continue
			var e := 1.0 - (1.0 - k) * (1.0 - k)
			var r := lerpf(float(ring[1]) * 0.12, float(ring[1]), e)
			var w := lerpf(float(ring[2]), 1.0, k)
			var steps := maxi(18, int(r / 3.0))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, steps, AbilityFX.OUTLINE, w + 2.0, false)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, steps, ring[3], w, false)
		if lines > 0 and _t < AbilityFX.LINES_T:
			var k := _t / AbilityFX.LINES_T
			var from := lerpf(line_from, line_to, k * 0.7)
			var to := lerpf(line_from * 1.6, line_to, 0.55 + 0.45 * k)
			var w := lerpf(5.0, 1.0, k)
			for i in lines:
				var d := Vector2.RIGHT.rotated(_turn + TAU * float(i) / float(lines))
				draw_line((d * from).round(), (d * to).round(), AbilityFX.OUTLINE, w + 2.0)
				draw_line((d * from).round(), (d * to).round(), colour, w)
		if flash > 0.0 and _t < AbilityFX.FLASH_T:
			var r := flash * (1.0 - _t / AbilityFX.FLASH_T * 0.8)
			_star(8, r + 3.0, r * 0.45 + 3.0, AbilityFX.OUTLINE, _turn)
			_star(8, r, r * 0.45, colour, _turn)
			_star(8, r * 0.45, r * 0.2, colour.lightened(0.6), _turn)
		if flare > 0.0 and _t < AbilityFX.FLARE_T:
			var k := _t / AbilityFX.FLARE_T
			var r := flare * (1.0 - k)
			var turn := k * PI * 0.5
			_star(4, r + 3.0, r * 0.22 + 3.0, AbilityFX.OUTLINE, turn)
			_star(4, r, r * 0.22, colour, turn)
			_star(4, r * 0.5, r * 0.12, colour.lightened(0.7), turn)

	## Not rounded to whole pixels: a small star rounded collapses its inner points onto each other,
	## and a degenerate polygon fails to triangulate and pushes an error.
	func _star(points: int, outer: float, inner: float, tint: Color, turn: float) -> void:
		if outer < 4.0:
			return
		var core := maxf(inner, 1.5)
		var polygon := PackedVector2Array()
		for i in points * 2:
			var r := outer if i % 2 == 0 else core
			polygon.append(Vector2.UP.rotated(turn + PI * float(i) / float(points)) * r)
		draw_colored_polygon(polygon, tint)

# --- icons -------------------------------------------------------------------------------------
#
# Nine by nine art pixels, drawn at the 2x every sprite is: `x` the colour, `w` it lightened, `d` it
# darkened, `k` the dark ink, `.` nothing. A one-pixel dark rim is added round every icon when it
# is plotted, so none of them has to draw its own. Plotted in code once per colour, as the golf
# ball and the punched hole are, rather than imported: an icon is a few pixels and a state, not art.

const ICONS := {
	&"glint": [
		"...x...",
		"...x...",
		"..xwx..",
		"xxwwwxx",
		"..xwx..",
		"...x...",
		"...x...",
	],
	&"star": [
		"....x....",
		"...xwx...",
		"...xwx...",
		"xxxxwxxxx",
		".xxwwwxx.",
		"..xxwxx..",
		"..xx.xx..",
		".xx...xx.",
		".x.....x.",
	],
	&"arrow": [
		"....x....",
		"...xwx...",
		"..xxwxx..",
		".xxxwxxx.",
		"xxxxwxxxx",
		"...xwx...",
		"...xwx...",
		"...xdx...",
		"...xxx...",
	],
	&"slash": [
		".......ww",
		"......wxw",
		".....wxw.",
		"....wxw..",
		"...wxw...",
		"..wxw....",
		".wxw.....",
		"wxw......",
		"ww.......",
	],
	&"saw": [
		".........",
		"x.x.x.x.x",
		"xxxxxxxxx",
		"xwwwwwwwx",
		"xwwwwwwwx",
		"xdddddddx",
		"xxxxxxxxx",
		".........",
		".........",
	],
	&"quake": [
		".........",
		"x...x...x",
		"xx.xxx.xx",
		".xxx.xxx.",
		"..x...x..",
		"x...x...x",
		"xx.xxx.xx",
		".xxx.xxx.",
		"..x...x..",
	],
	&"target": [
		"....x....",
		"..xxxxx..",
		".xx.x.xx.",
		".x..x..x.",
		"xxxxwxxxx",
		".x..x..x.",
		".xx.x.xx.",
		"..xxxxx..",
		"....x....",
	],
	&"bang": [
		"...xxx...",
		"...xwx...",
		"...xwx...",
		"...xwx...",
		"...xwx...",
		"...xxx...",
		".........",
		"...xwx...",
		"...xxx...",
	],
	&"heart": [
		".........",
		".xx...xx.",
		"xwwx.xwxx",
		"xwxxxxxxx",
		"xxxxxxxxx",
		".xxxxxxd.",
		"..xxxxd..",
		"...xxd...",
		"....x....",
	],
	&"flame": [
		"....x....",
		"...xx....",
		"...xxx...",
		"..xxwxx.x",
		".xxwwxxxx",
		".xwwwwxx.",
		"xxwwwwwxx",
		"xxwwwwwxx",
		".xxxxxxx.",
	],
	&"chain": [
		".xxxx....",
		"xx..xx...",
		"x....x...",
		"x..xxxxx.",
		"xx.x.xx.x",
		".xxxx...x",
		"...x....x",
		"...xx..xx",
		"....xxxx.",
	],
	&"hook": [
		"....xxx..",
		"....xwx..",
		"....xwx..",
		"....xwx..",
		"x...xwx..",
		"xx..xwx..",
		"xwx.xwx..",
		".xwwwwx..",
		"..xxxx...",
	],
	&"lever": [
		"......xxx",
		"......xwx",
		".....xwx.",
		"....xwx..",
		"...xwx...",
		"..xwx....",
		".xwx.....",
		"xxxx.....",
		"x..x.....",
	],
	&"hole": [
		"..xxxxx..",
		".xxdddxx.",
		"xxd...dxx",
		"xd.....dx",
		"xd.....dx",
		"xd.....dx",
		"xxd...dxx",
		".xxdddxx.",
		"..xxxxx..",
	],
	&"phones": [
		"..xxxxx..",
		".xx...xx.",
		"xx.....xx",
		"x.......x",
		"xx.....xx",
		"xwx...xwx",
		"xwx...xwx",
		"xwx...xwx",
		"xxx...xxx",
	],
	&"crank": [
		"..xxxxx..",
		".xx...xx.",
		"xx.....x.",
		"x.....xxx",
		"x......x.",
		"x........",
		"xx.....xx",
		".xx...xx.",
		"..xxxxx..",
	],
	&"blade": [
		"xxxxxxx..",
		"xwwwwwwx.",
		"xwwwwwwx.",
		"xwwwwwwx.",
		"xdddddxxx",
		"xxxxxxxdx",
		"......xdx",
		"......xxx",
		".........",
	],
	&"leaf": [
		"......xxx",
		"....xxwwx",
		"...xwwwwx",
		"..xwwwwx.",
		".xwwwwx..",
		".xwwwx...",
		".xxxx....",
		"xx.......",
		"x........",
	],
	&"flip": [
		".xxxxxx..",
		"xx....xx.",
		"x.....xxx",
		"x......x.",
		".........",
		".x......x",
		"xxx.....x",
		".xx....xx",
		"..xxxxxx.",
	],
	&"ghost": [
		"..xxxxx..",
		".xwwwwwx.",
		"xwwwwwwwx",
		"xwkwwwkwx",
		"xwkwwwkwx",
		"xwwwwwwwx",
		"xwwwwwwwx",
		"xwxwxwxwx",
		"x.x.x.x.x",
	],
	&"sword": [
		".......xx",
		"......xwx",
		".....xwx.",
		"....xwx..",
		".x.xwx...",
		".xxwx....",
		"..xx.....",
		".xxxx....",
		"xx..x....",
	],
	&"envelope": [
		".........",
		"xxxxxxxxx",
		"xxwwwwwxx",
		"xwxwwwxwx",
		"xwwxwxwwx",
		"xwwwxwwwx",
		"xwwwwwwwx",
		"xxxxxxxxx",
		".........",
	],
	&"spike": [
		".........",
		"xx.......",
		"xwxx.....",
		"xwwwxx...",
		"xwwwwwxxx",
		"xwwwxx...",
		"xwxx.....",
		"xx.......",
		".........",
	],
	&"six": [
		"..xxxxx..",
		".xx...xx.",
		"xx.......",
		"xx.xxxx..",
		"xxxx..xx.",
		"xx.....xx",
		"xx.....xx",
		".xx...xx.",
		"..xxxxx..",
	],
	&"pancake": [
		".........",
		".........",
		".........",
		"..xxxxx..",
		"xxwwwwwxx",
		"xwwwwwwwx",
		"xdddddddx",
		"xxxxxxxxx",
		".........",
	],
	&"staple": [
		".........",
		"xxxxxxxxx",
		"xwwwwwwwx",
		"xxxxxxxxx",
		"xx.....xx",
		"xx.....xx",
		"xx.....xx",
		"x.......x",
		".........",
	],
	&"bank": [
		"x.......x",
		"xx.....xx",
		".xx...xx.",
		"..xx.xx..",
		"...xxx...",
		"....x....",
		".........",
		"xxxxxxxxx",
		"xdddddddx",
	],
	&"key": [
		".........",
		".xxxxxxx.",
		"xwwwwwwwx",
		"xwwwwwwwx",
		"xwwwwwwwx",
		"xdddddddx",
		"xdddddddx",
		".xxxxxxx.",
		".........",
	],
	&"pause": [
		".........",
		".xxx.xxx.",
		".xwx.xwx.",
		".xwx.xwx.",
		".xwx.xwx.",
		".xwx.xwx.",
		".xwx.xwx.",
		".xxx.xxx.",
		".........",
	],
	&"drop": [
		"....x....",
		"...xx....",
		"...xwx...",
		"..xwwx...",
		"..xwwxx..",
		".xwwwwx..",
		".xwwwwxx.",
		".xxwwwxx.",
		"..xxxxx..",
	],
	&"fetch": [
		"...xxx...",
		"...xwx...",
		"...xwx...",
		"...xwx...",
		"xxxxwxxxx",
		".xxwwwxx.",
		"..xxwxx..",
		"...xxx...",
		"....x....",
	],
	&"feather": [
		".......xx",
		"......xwx",
		".....xwx.",
		"....xwwx.",
		"...xwwx..",
		"..xwwx...",
		".xwxx....",
		".xx......",
		"x........",
	],
	&"ball": [
		"..xxxxx..",
		".xwwwwwx.",
		"xwwwwwwwx",
		"xwwwwwwwx",
		"xdddddddx",
		"xwwwwwwwx",
		"xwwwwwwwx",
		".xwwwwwx.",
		"..xxxxx..",
	],
	&"towel": [
		".........",
		"xxxxxxxxx",
		"xwwwwwwwx",
		"xdddddddx",
		"xwwwwwwwx",
		"xwwwwwwwx",
		"xdddddddx",
		"xwwwwwwwx",
		"xxxxxxxxx",
	],
	&"donut": [
		"..xxxxx..",
		".xwwwwwx.",
		"xwwxxxwwx",
		"xwx...xwx",
		"xwx...xwx",
		"xdx...xdx",
		"xddxxxddx",
		".xdddddx.",
		"..xxxxx..",
	],
	&"cake": [
		"....x....",
		"...xwx...",
		"....x....",
		"....x....",
		".xxxxxxx.",
		"xwwwwwwwx",
		"xdddddddx",
		"xwwwwwwwx",
		"xxxxxxxxx",
	],
	&"bomb": [
		"......x.x",
		".....x.x.",
		"....xx...",
		"..xxxxx..",
		".xwxxxxx.",
		"xwxxxxxxx",
		"xxxxxxxxx",
		".xxxxxxx.",
		"..xxxxx..",
	],
	&"remote": [
		"......x..",
		"......x..",
		"......x..",
		".xxxxxxx.",
		".xwwwwwx.",
		".xwkkkwx.",
		".xwkwkwx.",
		".xwwwwwx.",
		".xxxxxxx.",
	],
	&"pin": [
		"...xxx...",
		"..xwwwx..",
		"..xwwwx..",
		"...xdx...",
		"..xwwwx..",
		".xwwwwwx.",
		".xwwwwwx.",
		".xwwwwwx.",
		"..xxxxx..",
	],
	&"pow": [
		"x...x...x",
		".x.xwx.x.",
		"..xwwwx..",
		".xwwwwwx.",
		"xwwwwwwwx",
		".xwwwwwx.",
		"..xwwwx..",
		".x.xwx.x.",
		"x...x...x",
	],
	&"lock": [
		"..xxxxx..",
		".xx...xx.",
		".x.....x.",
		"xxxxxxxxx",
		"xwwwwwwwx",
		"xwwwkwwwx",
		"xwwwkwwwx",
		"xwwwwwwwx",
		"xxxxxxxxx",
	],
}

## `kind` plotted in `colour`, cached per colour on this node.
func icon(kind: StringName, colour: Color) -> Texture2D:
	var key := "%s|%s" % [kind, colour.to_html()]
	if _icons.has(key):
		return _icons[key]
	var texture := AbilityFX.plot(kind, colour)
	_icons[key] = texture
	return texture

## Plots an icon: its grid in `colour`, with a one-pixel dark rim grown round all of its ink.
static func plot(kind: StringName, colour: Color) -> Texture2D:
	var grid: Array = ICONS.get(kind, ICONS[&"pow"])
	var h := grid.size()
	var w := String(grid[0]).length()
	var image := Image.create_empty(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var light := colour.lightened(0.55)
	var dark := colour.darkened(0.35)
	for y in h:
		var row := String(grid[y])
		for x in w:
			var c := row[x] if x < row.length() else "."
			if c == ".":
				continue
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var px := x + 1 + int(dx)
					var py := y + 1 + int(dy)
					if image.get_pixel(px, py).a < 0.5:
						image.set_pixel(px, py, OUTLINE)
	for y in h:
		var row := String(grid[y])
		for x in w:
			var c := row[x] if x < row.length() else "."
			var ink := Color(0, 0, 0, 0)
			match c:
				"x": ink = colour
				"w": ink = light
				"d": ink = dark
				"k": ink = OUTLINE
				_: continue
			image.set_pixel(x + 1, y + 1, ink)
	return ImageTexture.create_from_image(image)
