class_name FXLayer
extends CanvasLayer

## Floating payout numbers and hit-stop.
##
## Everything here is Focus-Mode gated: this game runs while the player is working, so the
## feedback has a volume knob and OFF still earns money — it just stops shouting about it
## (docs/game-design.md, Focus Mode).
##
## Labels are pooled. A game left running for eight hours that allocates a Label per hit
## allocates a few hundred thousand of them.

const POOL_SIZE := 24
const RISE_PIXELS := 46.0
const LIFETIME := 0.9

## Fountain coins live a little longer than a hit number, because the whole point of the
## beat is a pause the player watches.
const ARC_LIFETIME := 1.1
const ARC_GRAVITY := 560.0

## Coins are thrown hard enough to separate. At the first tuning they all left at 140-260
## px/s and landed on top of each other in a knot the size of the buddy — ten numbers
## drawn in the same place is one illegible smudge, not a payout.
const ARC_SPEED_MIN := 260.0
const ARC_SPEED_MAX := 460.0

## Each coin leaves fractionally after the last. A fountain that fires as a single frame is
## a burst; staggered, it reads as something pouring out of him.
const ARC_STAGGER := 0.045

## Lifted off him before being thrown. He is usually standing on the taskbar at the bottom
## of a fullscreen overlay, where half a fountain would otherwise arc off-screen.
const ARC_ORIGIN_LIFT := 46.0

# --- how a number looks -----------------------------------------------------
#
# A payout number is the game's only reward for most of a session, so it is treated as the
# reward rather than as a readout. Three things carry that:
#
# **Colour separates the two economies.** Bones and Hearts are earned by opposite actions
# and were both drawn in a pale cream that differed only in tint. They are now a gold and a
# rose, at full saturation, and — as everywhere else in this game — the colour is a
# reinforcement rather than the signal: the two are also different *sizes* and carry
# different particle bursts, because about one player in twelve cannot use the hue
# (docs/art-direction.md).
#
# **The number escalates with its own magnitude.** Tier is `log10` of the amount, so it
# keeps escalating for as long as the player keeps earning — a five-figure payout is
# visibly a bigger event than a two-figure one, forever, with no tuning constant to
# outgrow. This is the whole appeal of the genre made visible.
#
# **It has to survive an unknown desktop.** A bright core inside a saturated outline inside
# a dark shadow reads on white, on black and on a photograph, which is the same reason
# `art-direction.md` requires an outline on every sprite.

## Bones, by tier — warm through hot, and **saturated all the way up**. The first version
## ran the top of both ramps to near-white, which is the obvious way to say "hotter" and
## also the one thing that must not happen here: at the tier the player works hardest to
## reach, the two economies became the same colour. The heat is carried by the core instead
## (`CORE_RAMP`), which goes white while the outline keeps its hue.
const BONES_RAMP: Array[Color] = [
	Color("ffd98a"), Color("ffc247"), Color("ffa521"), Color("ff8c1a"), Color("ff6a00"),
]
const HEARTS_RAMP: Array[Color] = [
	Color("ffb3ce"), Color("ff8fbb"), Color("ff5f9e"), Color("ff3d8a"), Color("ff1f6f"),
]
## The ink inside the outline. Pale at every tier and white-hot at the top.
const CORE_RAMP: Array[Color] = [
	Color("fff8e6"), Color("fffaf0"), Color("fffdf7"), Color("ffffff"), Color("ffffff"),
]
## Display face sizes per tier. The bottom of the ramp is deliberately modest — this fires
## on every hit for eight hours, and a game that shouts at every tap stops being ignorable.
const TIER_SIZE: Array[int] = [20, 24, 30, 38, 48]
const TIER_OUTLINE: Array[int] = [5, 6, 7, 9, 11]
## Sparks thrown per tier, before the Focus Mode scale. Zero at tier 0: the common case is
## the one that has to stay free.
const TIER_SPARKS: Array[int] = [0, 0, 6, 12, 20]

## Pooled emitters, same reasoning as the label pool.
const SPARK_POOL := 8

const BONES_COLOUR := Color("ffc247")
const HEARTS_COLOUR := Color("ff5f9e")

var _pool: Array[Label] = []
## The tween currently animating each pool slot, so recycling one can stop it. Without this
## a reused label has two tweens writing its position, and the fountain makes that reachable
## — it claims most of the pool in a single frame, so the next few payouts wrap onto slots
## whose arc is still running and fly off along the old parabola.
var _tweens: Array[Tween] = []
var _next := 0
var _hit_stop_until_msec := 0

var _sparks: Array[GPUParticles2D] = []
var _next_spark := 0
## The display face, loaded rather than themed: a `CanvasLayer` does not inherit a Theme
## (that is why every layer in the shell hands one to its own root), so these labels were
## quietly drawing in Godot's default sans while the whole rest of the game was in Jersey.
var _face: Font

func _ready() -> void:
	layer = 5
	_face = load(UIStyle.FONT_DISPLAY) as Font
	for i in POOL_SIZE:
		var label := Label.new()
		label.visible = false
		label.z_index = 100
		if _face:
			label.add_theme_font_override("font", _face)
		label.add_theme_font_size_override("font_size", TIER_SIZE[0])
		label.add_theme_constant_override("outline_size", TIER_OUTLINE[0])
		# A drop shadow under the outline. The outline separates the number from the
		# background; the shadow separates it from a *light* background, which an outline in
		# a warm colour cannot do on its own.
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 3)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_pool.append(label)
		_tweens.append(null)

	var dot := _spark_texture()
	for i in SPARK_POOL:
		var sparks := GPUParticles2D.new()
		sparks.texture = dot
		sparks.emitting = false
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.lifetime = 0.75
		sparks.amount = TIER_SPARKS[TIER_SPARKS.size() - 1]
		sparks.local_coords = false
		sparks.z_index = 99
		sparks.process_material = _spark_material()
		add_child(sparks)
		_sparks.append(sparks)

	EventBus.payout.connect(_on_payout)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.knockout_payout.connect(_on_knockout_payout)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)

## A 4px square, plotted rather than imported. The game is pixel art and a soft round
## particle would be the one blurred thing on screen; four hard pixels are a chip of bone.
func _spark_texture() -> Texture2D:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func _spark_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 90.0
	mat.initial_velocity_max = 260.0
	mat.gravity = Vector3(0, 420.0, 0)
	mat.scale_min = 1.0
	mat.scale_max = 2.4
	# Shrinking to nothing rather than fading to nothing: alpha fade on a pixel-art chip
	# reads as a smudge, and a chip that gets smaller reads as distance.
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(0.65, 0.85))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	mat.damping_min = 40.0
	mat.damping_max = 120.0
	return mat

# --- floating numbers ------------------------------------------------------

func _on_payout(currency: StringName, amount: float, world_pos: Vector2, source_id: StringName) -> void:
	if amount < 0.01:
		return
	# **Not everything that is granted is a moment.** Dollars are minted flat on every hit
	# and every kind act (D31), and an arcade win or a contract claim is granted from a
	# panel with no world position at all — so both were drawing a "+1" at world (0,0), in
	# the *Hearts* ramp, in the corner of the play area, on every single swing. Two guards
	# rather than one: the currency has no floating treatment of its own, and a payout that
	# does not know where it happened has nowhere to float from.
	if currency == Economy.DOLLARS or world_pos == Vector2.ZERO:
		return
	var tier := _tier(amount)
	var ramp := BONES_RAMP if currency == &"bones" else HEARTS_RAMP
	# Hearts sit a touch below the hit so the two economies do not stack on the same pixel
	# when a kind item and a weapon are both in play.
	var offset := Vector2(0, 0) if currency == &"bones" else Vector2(0, 14)
	spawn_number("+%s" % _format(amount), world_pos + offset, ramp[tier], 1.0, tier)
	_tag_streak(currency, source_id, world_pos + offset, ramp, tier)

## The streak and the combo, drawn. The kindness combo swung the payout up to x3 and the
## damage streak is the genre's whole feeling of momentum, and neither was ever on screen
## (assessment-2026-09 §4). A small hot tag rides above the number, one tier hotter than it,
## from the third hit or the second pet — never for automation, which is not a rhythm.
const STREAK_SHOW_FROM := 3
const COMBO_SHOW_FROM := 1

func _tag_streak(currency: StringName, source_id: StringName, at: Vector2, ramp: Array,
		tier: int) -> void:
	if source_id == &"automation" or source_id == &"":
		return
	var hot := mini(tier + 1, TIER_SIZE.size() - 1)
	if currency == Economy.BONES:
		var streak := Economy.damage_streak()
		if streak >= STREAK_SHOW_FROM:
			spawn_number("x%d" % streak, at + Vector2(30, -22), ramp[hot], 0.8, hot)
		return
	if currency == Economy.HEARTS:
		# Only on the act's own number, not on a hot tub's trickle arriving mid-streak.
		if not Economy.paying_kind_act:
			return
		var combo := Economy.kindness_combo()
		if combo >= COMBO_SHOW_FROM:
			var b := ItemDB.balance
			var mult := EconomyMath.kindness_combo(combo, b.kindness_combo_step, b.kindness_combo_max)
			spawn_number("x%.1f" % mult, at + Vector2(30, -22), ramp[hot], 0.8, hot)

## How big a number *feels* is how many digits it has, so that is what drives the treatment.
## `log10` rather than a table of thresholds: it keeps escalating for as long as the player
## keeps earning, which is the one property a reward for an idle game has to have.
func _tier(amount: float) -> int:
	if amount < 10.0:
		return 0
	return clampi(int(floor(log(amount) / log(10.0))), 0, TIER_SIZE.size() - 1)

## The payout fountain, and the one moment in the loop the game is allowed to shout.
##
## Economy emits the payout the instant the meter fills, which is while he is still on his
## feet — so the amount is banked here and spent when the buddy actually reaches `pile`.
## The beat only reads if the cause lands before the effect (docs/game-design.md), and
## waiting on his state rather than on a timer keeps the two in step through any retiming
## of the collapse animation.
var _pending_fountain := 0.0

func _on_knockout_payout(total: float) -> void:
	_pending_fountain = total

func _on_buddy_state_changed(state: StringName) -> void:
	if state != &"pile":
		return
	var total := _pending_fountain
	_pending_fountain = 0.0
	if total < 0.01 or Settings.intensity_scale() <= 0.0:
		return

	# The headline number goes in the middle of the play area, so it reads even if the last
	# hit landed at the edge of the screen.
	var centre := get_viewport().get_visible_rect().size * 0.5
	spawn_number("KNOCKOUT  +%s" % _format(total), centre, BONES_RAMP[BONES_RAMP.size() - 2],
		1.6, TIER_SIZE.size() - 1)
	_fountain(_buddy_position(centre), total)

## Coins bursting out of the heap. Each is a share of the bonus rather than a decoration,
## so the fountain adds up to the number the player was just shown.
func _fountain(origin: Vector2, total: float) -> void:
	var coins := maxi(1, int(ItemDB.balance.knockout_fountain_coins * Settings.intensity_scale()))
	var share := total / float(coins)
	var from := origin - Vector2(0, ARC_ORIGIN_LIFT)
	for i in coins:
		var angle := lerpf(-PI * 0.88, -PI * 0.12, float(i) / float(maxi(1, coins - 1)))
		angle += randf_range(-0.1, 0.1)
		spawn_arc("+%s" % _format(share), from,
			Vector2.RIGHT.rotated(angle) * randf_range(ARC_SPEED_MIN, ARC_SPEED_MAX),
			BONES_COLOUR, float(i) * ARC_STAGGER)

## Found by group, never by path — FXLayer is on a CanvasLayer and he is in the world
## (docs/decisions.md D9). Falls back to the given point if he is somehow not in the tree.
func _buddy_position(fallback: Vector2) -> Vector2:
	var buddy := get_tree().get_first_node_in_group(&"buddy") as Node2D
	return buddy.global_position if buddy else fallback

func spawn_number(text: String, world_pos: Vector2, colour: Color, scale: float = 1.0,
		tier: int = 0) -> void:
	var intensity := Settings.intensity_scale()
	if intensity <= 0.0:
		return
	tier = clampi(tier, 0, TIER_SIZE.size() - 1)
	var label := _take()
	label.text = text
	# The saturated colour is the *outline*, with a pale core inside it. A number drawn in
	# one flat colour disappears into any desktop that happens to be near that colour; a
	# bright core in a hot outline over a dark shadow survives all of them.
	label.add_theme_color_override("font_color", CORE_RAMP[tier])
	label.add_theme_color_override("font_outline_color", colour)
	label.add_theme_font_size_override("font_size", TIER_SIZE[tier])
	label.add_theme_constant_override("outline_size", TIER_OUTLINE[tier])
	label.modulate.a = 1.0
	label.visible = true
	# Centre on the hit. reset_size() first, or the size is still the previous number's.
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * scale
	label.position = world_pos - label.size * 0.5 * scale
	# A little sideways scatter, so a burst of hits in one place reads as several numbers
	# rather than one flickering one.
	var drift := randf_range(-18.0, 18.0) * (1.0 + float(tier) * 0.3)

	var tween := create_tween().set_parallel(true)
	# Punch in, then settle. The overshoot is what makes it land rather than appear.
	tween.tween_property(label, "scale", Vector2.ONE * scale * (1.0 + 0.12 * float(tier + 1)),
		0.09).from(Vector2.ONE * scale * 0.55).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(label, "scale", Vector2.ONE * scale, 0.13) \
		.set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - RISE_PIXELS * scale
		* (1.0 + float(tier) * 0.25), LIFETIME).set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:x", label.position.x + drift, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Held at full opacity for the first half, then faded. Fading from the first frame makes
	# the number hardest to read exactly when it is largest.
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME * 0.5) \
		.set_delay(LIFETIME * 0.5).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: label.visible = false)
	_register(label, tween)

	_sparkle(world_pos, colour, tier, intensity)

## A burst of chips in the number's own colour. Tier 0 and 1 throw none — that is the case
## that fires on every hit for eight hours, and it has to stay free.
func _sparkle(at: Vector2, colour: Color, tier: int, intensity: float) -> void:
	var count := int(TIER_SPARKS[tier] * clampf(intensity, 0.0, 1.6))
	if count <= 0 or _sparks.is_empty():
		return
	var sparks := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	sparks.position = at
	sparks.modulate = colour
	sparks.amount = count
	sparks.restart()

## A number thrown on a ballistic arc, for the knockout fountain. Same pool, same Focus
## Mode gate; only the path differs.
func spawn_arc(text: String, world_pos: Vector2, velocity: Vector2, colour: Color,
		delay: float = 0.0) -> void:
	if Settings.intensity_scale() <= 0.0:
		return
	var label := _take()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.scale = Vector2.ONE
	label.modulate.a = 1.0
	label.reset_size()
	label.position = world_pos - label.size * 0.5
	# Hidden until its turn, or a staggered coin sits motionless at the origin waiting to
	# be thrown — which reads as the effect being broken rather than as a stagger.
	label.visible = delay <= 0.0

	# Solved rather than tweened: two tweens on x and y cannot describe a parabola, and a
	# tween on position with a curve preset gets the arc wrong in a way that reads as a
	# glitch rather than as gravity.
	var start := label.position
	var tween := create_tween().set_parallel(true)
	if delay > 0.0:
		tween.tween_callback(func() -> void: label.visible = true).set_delay(delay)
	tween.tween_method(func(t: float) -> void:
			label.position = start + velocity * t + Vector2(0, 0.5 * ARC_GRAVITY * t * t),
		0.0, ARC_LIFETIME, ARC_LIFETIME).set_delay(delay)
	tween.tween_property(label, "modulate:a", 0.0, ARC_LIFETIME) \
		.set_ease(Tween.EASE_IN).set_delay(delay)
	tween.chain().tween_callback(func() -> void: label.visible = false)
	_register(label, tween)

## Round-robin rather than a free list: a number that is still animating when its slot
## comes back around is simply restarted, which is the correct behaviour under a burst.
func _take() -> Label:
	var index := _next
	_next = (_next + 1) % _pool.size()
	var running := _tweens[index]
	if running != null and running.is_valid():
		running.kill()
	_tweens[index] = null
	return _pool[index]

## The slot a label came from, so the caller can register the tween it just started.
func _slot_of(label: Label) -> int:
	return _pool.find(label)

func _register(label: Label, tween: Tween) -> void:
	var index := _slot_of(label)
	if index >= 0:
		_tweens[index] = tween

## The same abbreviation the shop prices use, so a payout and a price are read the same way.
func _format(value: float) -> String:
	if value < 10.0:
		return "%.1f" % value
	return UIStyle.format_amount(value)

# --- hit stop --------------------------------------------------------------

## A few frames of near-frozen time on a big hit. Scaled by magnitude so small taps do not
## make the whole desktop stutter, and gated by Focus Mode along with everything else.
func _on_damage_dealt(info: HitInfo) -> void:
	var intensity := Settings.intensity_scale()
	if intensity < 0.9:
		return
	var b := ItemDB.balance
	var t := clampf(info.amount / maxf(1.0, b.hit_stop_full_damage), 0.0, 1.0)
	var frames := lerpf(b.hit_stop_min_frames, b.hit_stop_max_frames, t)
	_hit_stop(frames / 60.0)

func _hit_stop(seconds: float) -> void:
	var now := Time.get_ticks_msec()
	# Overlapping hits must not stack into a visible freeze.
	if now < _hit_stop_until_msec:
		return
	_hit_stop_until_msec = now + int(seconds * 1000.0)
	Engine.time_scale = 0.05
	# ignore_time_scale, or the timer that ends the hit-stop is itself slowed by it.
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
