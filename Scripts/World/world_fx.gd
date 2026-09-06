class_name WorldFX
extends Node2D

## Everything physical that happens in the world and is not a body: bursts at the point of
## contact, dust where something lands, a shockwave where something goes off, a tracer where
## a turret fired, a bolt where the lightning went — and the whole picture jolting when the
## desk takes a real hit (docs/decisions.md D30, D39).
##
## The floating payout numbers (`FXLayer`) already say *how much*. This says *where* and
## *what kind of thing*, and it is the half that was missing: a hit registered as a number
## appearing in the top corner of the buddy and nothing happening at the place the bat
## actually landed; a grenade was a sprite that vanished and a number that appeared.
##
## **Everything here is the UI glyph set at world scale, or a four-pixel chip.** A bone chip
## is `bone.png`, a heart is `heart.png`, a star is `star.png` — the same shapes the purse
## counts in. Dust, soot, sparks and heat are all the same 4px square in a different colour.
## Pixel art must not have the one soft round particle on screen.
##
## Three things this must not do, all of them budget:
##   - it must cost nothing while idle. Every emitter, ring and line is pooled and parked,
##     never spawned per event; a game that allocates on every contact for eight hours is a
##     game that stutters in hour three. The shake is the one `_process` here and it turns
##     itself off the moment it settles.
##   - it must be silent under Focus Mode Off, like every other moving thing (D21), and
##     halved under Subtle.
##   - it must not survive its own burst. One-shot emitters are restarted from the pool, so
##     the node count is constant for the life of the process.

## Emitters in the ring. Ten rather than six since the minigun and the fastest turret each
## ask for a spark burst twenty times a second on top of the hit chips — a burst that
## restarts an emitter still mid-flight simply cuts the older one short, which is correct
## under a stream, but with six the *hit* chips were the ones being cut.
const POOL := 10
const RING_POOL := 4
const LINE_POOL := 4

## Chips per burst at the extremes of the damage range, and the damage that earns the top
## of it. Anchored on `balance.hit_stop_full_damage`, so the biggest shower and the longest
## hit-stop are the same hit — two channels saying one thing rather than two.
const CHIPS_MIN := 3
const CHIPS_MAX := 14

## Kind acts fire several times a second while petting, so their burst is deliberately the
## smallest thing here. The same reasoning that makes the petting *sound* quiet.
const HEART_CHIPS := 3

## Falling faster than this throws dust when he lands; the top of the range is a full shower.
const LAND_SOFT := 250.0
const LAND_HARD := 1100.0

## Mood bands that get a physical tell when he crosses into them: hearts drifting off him
## when he becomes delighted, a dark little cloud when he becomes miserable.
const MOOD_BAND := 60.0
## Grime puffs off him every quarter of the way to filthy; a full clean throws white.
const GRIME_STAGE := 0.25

## How long a jolt lasts and how far the picture moves at full strength. Short and small:
## this is a desk, not an earthquake, and the game is on for eight hours.
const SHAKE_MSEC := 220
const SHAKE_CAP := 9.0

## The chip palette. Cream dust for a landing, dark soot for smoke and misery, pale sparks
## for a shot, orange heat for the sunbeam, sky blue for the bolt, straw for a tracer.
const DUST := Color("cfc9b4")
const SOOT := Color("5c574c")
const SPARK := Color("fff1b8")
const HEAT := Color("ff8c1a")
const BOLT := Color("cfe9ff")
const TRACER := Color("ffe9a8")
## Ectoplasm, saturated: the colour a life leaves in when he is reborn.
const MARROW := Color("46c48f")
## Gold for a star: the payout ramp's bone gold, not the purse's brown, which vanishes on him.
const GOLD := Color("ffc247")

## GPU emitters, like `FXLayer` and `UIMotion`. The first version of this file used
## `CPUParticles2D`, and in this project those emit and never draw a pixel — the pool sat
## "emitting" at the right place with the right texture and the screen stayed empty, which
## the shot tool finally showed. Everything the particle needs to know lives in a
## `ParticleProcessMaterial`, cached per recipe; there are about a dozen recipes in the game.
var _pool: Array[GPUParticles2D] = []
var _next := 0
var _materials: Dictionary = {}
var _rings: Array[Ring] = []
var _next_ring := 0
var _lines: Array[Line2D] = []
var _next_line := 0
var _chip: Texture2D

var _shake_amp := 0.0
var _shake_until_msec := 0

var _mood_band := 0
var _grime_stage := 0

## The world's effects node, found by group from anywhere in the world: an item, a power, a
## component. Never by path (docs/decisions.md D9). Null in a scene that has none, which
## every caller treats as "no effect" rather than as an error.
static func of(node: Node) -> WorldFX:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(&"world_fx") as WorldFX

func _ready() -> void:
	add_to_group(&"world_fx")
	set_process(false)
	_chip = _chip_texture()
	for i in POOL:
		var emitter := GPUParticles2D.new()
		# Named, not left as @GPUParticles2D@31: a node with a generated name cannot be
		# found by a test and cannot be read in the remote scene tree.
		emitter.name = "Burst%d" % i
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.lifetime = 0.7
		# World space: a parked emitter is moved to the next burst, and its chips must not
		# come with it.
		emitter.local_coords = false
		emitter.z_index = 30
		add_child(emitter)
		_pool.append(emitter)
	for i in RING_POOL:
		var ring_node := Ring.new()
		ring_node.name = "Ring%d" % i
		ring_node.visible = false
		ring_node.z_index = 40
		add_child(ring_node)
		_rings.append(ring_node)
	for i in LINE_POOL:
		var line := Line2D.new()
		line.name = "Line%d" % i
		line.visible = false
		line.width = 3.0
		line.z_index = 40
		line.antialiased = false
		line.joint_mode = Line2D.LINE_JOINT_BEVEL
		add_child(line)
		_lines.append(line)

	_mood_band = _band_of(Economy.mood)
	_grime_stage = int(floor(Economy.grime / GRIME_STAGE))

	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kindness_given.connect(_on_kindness_given)
	EventBus.kindness_sustained.connect(_on_kindness_sustained)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)
	EventBus.buddy_landed.connect(_on_buddy_landed)
	EventBus.item_spawned.connect(_on_item_spawned)
	EventBus.item_despawned.connect(_on_item_despawned)
	EventBus.mood_changed.connect(_on_mood_changed)
	EventBus.grime_changed.connect(_on_grime_changed)
	EventBus.mastery_rank_up.connect(_on_mastery_rank_up)
	EventBus.prestige_performed.connect(_on_prestige_performed)

## A 4px square, plotted rather than imported — the same chip `FXLayer` and `UIMotion` throw.
func _chip_texture() -> Texture2D:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

# --- gates -------------------------------------------------------------------

func _on() -> bool:
	return Settings.focus_intensity != Settings.Intensity.OFF

## Subtle halves a shower rather than removing it: the setting is about how loud the game
## is, and a hit that produces nothing at all reads as a hit that missed.
func _count(count: int) -> int:
	if Settings.focus_intensity == Settings.Intensity.SUBTLE:
		return maxi(1, count / 2)
	return maxi(1, count)

# --- reactions ---------------------------------------------------------------

## The chips run hotter as the streak runs longer: bone-brown at a tap, orange by the
## twentieth hit in a row. The streak is the genre's whole feeling of momentum, and a tag on
## the number is the only place it showed; now the desk itself heats up.
const STREAK_HOT_AT := 20.0

func _on_damage_dealt(info: HitInfo) -> void:
	var full := maxf(1.0, ItemDB.balance.hit_stop_full_damage)
	var heat_of_hit := clampf(info.amount / full, 0.0, 1.0)
	var streak := clampf(float(Economy.damage_streak()) / STREAK_HOT_AT, 0.0, 1.0)
	burst(info.position, &"bone", UIStyle.BONES.lerp(HEAT, streak),
		int(lerpf(CHIPS_MIN, CHIPS_MAX, heat_of_hit)), lerpf(110.0, 340.0, heat_of_hit))

func _on_kindness_given(_source_id: StringName, _value: float, world_pos: Vector2) -> void:
	burst(world_pos, &"heart", UIStyle.HEARTS, HEART_CHIPS, 90.0)

## A kind item in use — a hot tub, a boombox — pays several times a second and would bury
## him in hearts. One heart drifts up every so often instead, from wherever the item is.
const SUSTAIN_EVERY_MSEC := 1400
var _next_sustain_msec := 0

func _on_kindness_sustained(_source_id: StringName, _value: float, world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_sustain_msec:
		return
	_next_sustain_msec = now + SUSTAIN_EVERY_MSEC
	_emit(world_pos, UIStyle.glyph(&"heart"), UIStyle.HEARTS, 1, 40.0, 1.2, Vector2(0, -60), 0.8, 1.0)

## He comes apart, so the chips do too — a wide, slow shower rather than a spray, because
## this one is the round's full stop and wants to hang in the air for a moment. The desk
## jolts and a ring goes out from him: the knockout was a fountain of numbers and nothing
## physical, and it is the one moment in the loop that is allowed to shout.
func _on_buddy_state_changed(state: StringName) -> void:
	if state != &"knockout":
		return
	var at := _buddy_position()
	burst(at, &"bone", UIStyle.BONES, 22, 260.0, 1.1)
	ring(at, 130.0, UIStyle.BONES, 0.45, 4.0)
	shake(6.0)

## Dust at his feet, more of it the harder he came down. A landing was a sound and a
## flinch; now it is also something on the floor.
func _on_buddy_landed(at: Vector2, speed: float) -> void:
	var hardness := clampf((speed - LAND_SOFT) / (LAND_HARD - LAND_SOFT), 0.0, 1.0)
	puff(at, int(lerpf(3.0, 10.0, hardness)), DUST, lerpf(45.0, 120.0, hardness), 0.55)

## A toy arriving: it pops rather than appears, and kicks a little dust. Only the sprite is
## scaled — the body is a RigidBody2D and its scale is the physics' — and from the scale the
## art table gave it, not from one, because almost nothing on the desk is drawn at 1:1.
func _on_item_spawned(node: Node2D) -> void:
	if not _on() or not is_instance_valid(node):
		return
	puff(node.global_position, 6, DUST, 70.0, 0.5)
	var sprite := node.get("sprite") as Node2D
	if sprite == null or not is_instance_valid(sprite):
		return
	var base := sprite.scale
	sprite.scale = base * 0.25
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", base, 0.28).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

## A toy leaving: the same dust, unless it left by exploding, which has its own send-off.
## An exploding charge hides its sprite before it announces itself, and that is the tell.
func _on_item_despawned(node: Node2D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var sprite := node.get("sprite") as CanvasItem
	if sprite != null and is_instance_valid(sprite) and not sprite.visible:
		return
	puff(node.global_position, 5, DUST, 55.0, 0.5)

## Hearts drift off him when he crosses into delighted; a dark cloud when he crosses into
## miserable. The bar in the HUD already moves — this is the same fact where he is.
func _on_mood_changed(value: float) -> void:
	var band := _band_of(value)
	if band == _mood_band:
		return
	var rising := band > _mood_band
	_mood_band = band
	var at := _buddy_position() + Vector2(0, -30)
	if band > 0 and rising:
		_emit(at, UIStyle.glyph(&"heart"), UIStyle.HEARTS, 7, 60.0, 1.1, Vector2(0, -70), 0.7, 1.2)
	elif band < 0 and not rising:
		puff(at, 8, SOOT, 40.0, 0.9)

func _band_of(mood: float) -> int:
	if mood >= MOOD_BAND:
		return 1
	if mood <= -MOOD_BAND:
		return -1
	return 0

## Soot puffs off him each quarter of the way to filthy, and a full clean throws white:
## the sponge had a number and a face and nothing coming off him.
func _on_grime_changed(value: float) -> void:
	var stage := int(floor(value / GRIME_STAGE))
	if stage > _grime_stage:
		puff(_buddy_position(), 6, SOOT, 60.0, 0.8)
	elif is_zero_approx(value) and _grime_stage > 0:
		_emit(_buddy_position(), _chip, Color.WHITE, 16, 170.0, 0.6, Vector2(0, 240), 1.0, 2.2)
	_grime_stage = stage

## Stars off him at a rank. The rank was a toast in the corner; now it happens to *him*.
func _on_mastery_rank_up(_item_id: StringName, _rank: int) -> void:
	_emit(_buddy_position() + Vector2(0, -20), UIStyle.glyph(&"star"), GOLD, 10,
		220.0, 0.9, Vector2(0, 500), 0.8, 1.3)

## Reborn. Three rings leave him in Ectoplasm green, a shower of stars, and the desk jolts:
## the biggest decision in the game was a toast and a sound.
func _on_prestige_performed(_marrow: float) -> void:
	if not _on():
		return
	var at := _buddy_position()
	_emit(at, UIStyle.glyph(&"star"), MARROW, 24, 320.0, 1.2, Vector2(0, 380), 0.8, 1.5)
	ring(at, 90.0, MARROW, 0.4, 4.0)
	shake(5.0)
	# Rare enough to afford two timers; the pool has room for all three rings at once.
	get_tree().create_timer(0.12).timeout.connect(func() -> void: ring(at, 160.0, MARROW, 0.5, 3.0))
	get_tree().create_timer(0.24).timeout.connect(func() -> void: ring(at, 240.0, MARROW, 0.6, 2.0))

# --- the vocabulary ------------------------------------------------------------

## Throws `count` chips of one glyph from a point. Public because the arcade, the NPCs and
## anything else that wants a physical reaction should use this pool rather than building a
## second one.
func burst(at: Vector2, glyph: StringName, colour: Color, count: int, speed: float,
		lifetime: float = 0.7) -> void:
	_emit(at, UIStyle.glyph(glyph), colour, count, speed, lifetime, Vector2(0, 900), 0.7, 1.4)

## A puff of chips that drifts up and dies: dust, soot, smoke, heat. Slow, light, no spin.
func puff(at: Vector2, count: int, colour: Color, speed: float = 60.0, lifetime: float = 0.6) -> void:
	_emit(at, _chip, colour, count, speed, lifetime, Vector2(0, -40), 1.2, 2.6)

## A shot landing: a few hot sparks and, for a spread, a small ring. Cheap enough to run
## twenty times a second, which the minigun does.
func shot(at: Vector2, spread: bool = false) -> void:
	_emit(at, _chip, SPARK, 5 if spread else 3, 220.0, 0.3, Vector2(0, 600), 0.8, 1.6)
	if spread:
		ring(at, 40.0, SPARK, 0.18, 2.0)

## A tick of the sunbeam: heat rising off the spot.
func heat(at: Vector2) -> void:
	_emit(at, _chip, HEAT, 3, 70.0, 0.5, Vector2(0, -160), 1.0, 2.0)

## Something went off. A shockwave, a smoke puff, a spray of sparks and a jolt, all scaled
## by `size` (one is a grenade).
func boom(at: Vector2, size: float = 1.0) -> void:
	ring(at, 120.0 * size, SPARK, 0.4, 4.0)
	_emit(at, _chip, SPARK, int(8 * size), 300.0 * size, 0.45, Vector2(0, 500), 0.8, 1.8)
	puff(at, int(10 * size), SOOT, 90.0 * size, 1.0)
	shake(7.0 * size)

## An expanding ring: the shockwave off an explosion, the halo off a knockout, a rebirth.
## Drawn, not a sprite, so it is the right size at any radius and never resampled.
func ring(at: Vector2, radius: float, colour: Color, time: float = 0.35, width: float = 3.0) -> void:
	if not _on() or _rings.is_empty():
		return
	var r := _rings[_next_ring]
	_next_ring = (_next_ring + 1) % _rings.size()
	r.show_ring(at, radius, colour, time, width)

## The line a shot travelled, gone in a tenth of a second. Thin, and thinner as it goes.
func tracer(from: Vector2, to: Vector2, colour: Color = TRACER) -> void:
	_line(PackedVector2Array([from, to]), colour, 0.1, 2.0)

## A bolt through `points` — each leg broken into jagged segments, because a straight line
## is a laser and this is lightning. Sky blue, and gone in a sixth of a second.
func bolt(points: PackedVector2Array, colour: Color = BOLT) -> void:
	if points.size() < 2:
		return
	var jagged := PackedVector2Array()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var legs := maxi(2, int(a.distance_to(b) / 28.0))
		var side := (b - a).normalized().orthogonal()
		jagged.append(a)
		for k in range(1, legs):
			var t := float(k) / float(legs)
			jagged.append(a.lerp(b, t) + side * randf_range(-11.0, 11.0))
	jagged.append(points[points.size() - 1])
	_line(jagged, colour, 0.16, 3.0)
	# The first strike gets a small ring; the chain does not, or three rings arrive at once.
	ring(points[1], 34.0, colour, 0.2, 2.0)

## The whole picture jolts. Through the viewport's canvas transform, which is how a Camera2D
## would do it — rendering only, so nothing in the physics world moves and every mouse
## position still maps through it (`Buddy` reads `get_canvas_transform()`, and the shell is
## on CanvasLayers of its own, which do not follow). Off at Subtle and Off: a shake is the one
## effect a player working beside the window might find rude, so it is Normal-and-up only.
func shake(pixels: float) -> void:
	if Settings.intensity_scale() < 0.9:
		return
	var amp := minf(pixels * Settings.intensity_scale(), SHAKE_CAP)
	_shake_amp = maxf(_shake_amp, amp)
	_shake_until_msec = maxi(_shake_until_msec, Time.get_ticks_msec() + SHAKE_MSEC)
	set_process(true)

func _process(_delta: float) -> void:
	var viewport := get_viewport()
	var now := Time.get_ticks_msec()
	if now >= _shake_until_msec or _shake_amp < 0.5 or viewport == null:
		if viewport:
			viewport.canvas_transform = Transform2D.IDENTITY
		_shake_amp = 0.0
		set_process(false)
		return
	# Decays to nothing over the window, and lands on whole pixels: a half-pixel offset
	# resamples every sprite on the desk for the length of the jolt.
	var t := float(_shake_until_msec - now) / float(SHAKE_MSEC)
	var amp := _shake_amp * t
	viewport.canvas_transform = Transform2D(0.0,
		Vector2(randf_range(-amp, amp), randf_range(-amp, amp)).round())

func is_shaking() -> bool:
	return is_processing()

# --- pools ----------------------------------------------------------------

func _emit(at: Vector2, texture: Texture2D, colour: Color, count: int, speed: float,
		lifetime: float, gravity: Vector2, scale_min: float, scale_max: float) -> void:
	if not _on() or texture == null:
		return
	var emitter := _pool[_next]
	_next = (_next + 1) % _pool.size()
	emitter.emitting = false
	emitter.global_position = at
	emitter.texture = texture
	emitter.modulate = colour
	emitter.amount = _count(count)
	emitter.lifetime = lifetime
	# Glyphs tumble; a chip does not have a face to tumble.
	emitter.process_material = _material(speed, gravity.y, scale_min, scale_max, texture != _chip)
	emitter.restart()

## One recipe, built once. Keyed on everything that goes into it, rounded, so the dozen or
## so distinct bursts in the game share a dozen materials for the life of the process.
func _material(speed: float, gravity_y: float, scale_min: float, scale_max: float,
		spins: bool) -> ParticleProcessMaterial:
	var key := "%d|%d|%d|%d|%s" % [int(round(speed)), int(round(gravity_y)),
		int(round(scale_min * 10.0)), int(round(scale_max * 10.0)), spins]
	if _materials.has(key):
		return _materials[key]
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = speed * 0.45
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, gravity_y, 0)
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	mat.damping_min = 20.0
	mat.damping_max = 60.0
	if spins:
		mat.angular_velocity_min = -720.0
		mat.angular_velocity_max = 720.0
	# Shrinking to nothing rather than fading to nothing: alpha fade on a pixel-art chip
	# reads as a smudge, and a chip that gets smaller reads as distance.
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(0.7, 0.9))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	_materials[key] = mat
	return mat

func _line(points: PackedVector2Array, colour: Color, time: float, width: float) -> void:
	if not _on() or _lines.is_empty():
		return
	var line := _lines[_next_line]
	_next_line = (_next_line + 1) % _lines.size()
	if line.has_meta(&"_tween"):
		var previous := line.get_meta(&"_tween") as Tween
		if previous and previous.is_valid():
			previous.kill()
	line.points = points
	line.default_color = colour
	line.width = width
	line.visible = true
	var tween := line.create_tween()
	line.set_meta(&"_tween", tween)
	# Thins to nothing rather than fading: an alpha fade on a hard line is a smear.
	tween.tween_property(line, "width", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: line.visible = false)

## Found by group, never by path — he is in the world and this is too, but not in his scene
## (docs/decisions.md D9). Falls back to the middle of the view if he is somehow not there.
func _buddy_position() -> Vector2:
	var buddy := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Node2D
	if buddy:
		return buddy.global_position
	return get_viewport().get_visible_rect().size * 0.5

## One expanding ring, drawn as a hard-edged arc. Radius eases out, width eases to one
## pixel, and it hides itself when spent.
class Ring extends Node2D:
	var radius := 0.0
	var width := 3.0
	var colour := Color.WHITE
	var _tween: Tween

	func show_ring(at: Vector2, to_radius: float, ring_colour: Color, time: float, from_width: float) -> void:
		if _tween and _tween.is_valid():
			_tween.kill()
		global_position = at
		colour = ring_colour
		radius = maxf(4.0, to_radius * 0.12)
		width = from_width
		visible = true
		queue_redraw()
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "radius", to_radius, time).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "width", 1.0, time).set_trans(Tween.TRANS_QUAD)
		_tween.tween_method(func(_t: float) -> void: queue_redraw(), 0.0, 1.0, time)
		_tween.chain().tween_callback(func() -> void: visible = false)

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, maxi(16, int(radius / 3.0)), colour, width, false)
