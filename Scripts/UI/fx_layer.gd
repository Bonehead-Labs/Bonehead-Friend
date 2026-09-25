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

## Below this much headroom under the headline no arc fits, and the cap is not applied.
const ARC_MIN_ROOM := 40.0

## Draw order inside the layer: rising lines over their sparks over the fountain coins.
const Z_LINE := 100
const Z_COIN := 98

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
##
## It is also each rising number's clock: `get_total_elapsed_time()` is exactly how far along
## its path the number is, on the same clock that moves it — which the wall clock is not
## under `--fixed-fps`, where a capture tool's frames take as long as a PNG takes to write.
var _tweens: Array[Tween] = []
var _next := 0

## Where each rising number is for the whole of its life, one entry per pool slot (see "keeping
## the numbers apart" below). Packed, because this is read for every live number every time a
## new one is placed.
var _held_on := PackedByteArray()
var _held_from := PackedVector2Array()
var _held_half := PackedVector2Array()
var _held_pad := PackedVector2Array()
var _held_punch := PackedFloat32Array()
var _held_rise := PackedFloat32Array()
var _held_rank := PackedInt32Array()
var _held_key: Array[StringName] = []
var _hit_stop_until_msec := 0

var _sparks: Array[GPUParticles2D] = []
var _next_spark := 0
## The display face, loaded rather than themed: a `CanvasLayer` does not inherit a Theme
## (that is why every layer in the shell hands one to its own root), so these labels were
## quietly drawing in Godot's default sans while the whole rest of the game was in Jersey.
var _face: Font

func _ready() -> void:
	# Above the HUD (10), below the panels (20). D48 moved the numbers sideways out of the
	# HUD's corner and that was only ever half the problem: at layer 5 the HUD painted over
	# every number wherever it was, so a knockout headline wide enough to reach the corner
	# lost to the status card no matter where it started. Position cannot beat draw order.
	#
	# Below the panels on purpose. An open shop is something the player is reading, and a
	# payout number scrolling across it is worse than a payout number they missed.
	layer = 15
	_face = load(UIStyle.FONT_DISPLAY) as Font
	for i in POOL_SIZE:
		var label := Label.new()
		label.visible = false
		label.z_index = Z_LINE
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
		_held_key.append(&"")
	_held_on.resize(POOL_SIZE)
	_held_on.fill(0)
	_held_from.resize(POOL_SIZE)
	_held_half.resize(POOL_SIZE)
	_held_pad.resize(POOL_SIZE)
	_held_punch.resize(POOL_SIZE)
	_held_rise.resize(POOL_SIZE)
	_held_rank.resize(POOL_SIZE)

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
	EventBus.mastery_rank_up.connect(_on_mastery_rank_up)
	EventBus.prestige_performed.connect(_on_prestige_performed)
	EventBus.grime_changed.connect(_on_grime_changed)

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
	var placed := spawn_number("+%s" % _format(amount), world_pos + offset, ramp[tier], 1.0, tier)
	# The tag rides the number where it was actually put, not where it was aimed: a number
	# stepped aside to make room would otherwise leave its tag hanging over somebody else's.
	if placed.is_finite():
		_tag_streak(currency, source_id, placed, ramp, tier)

## The streak and the combo, drawn. The kindness combo swung the payout up to x3 and the
## damage streak is the genre's whole feeling of momentum, and neither was ever on screen
## (assessment-2026-09 §4). A small hot tag rides above the number, one tier hotter than it,
## from the third hit or the second pet — never for automation, which is not a rhythm.
const STREAK_SHOW_FROM := 3
const COMBO_SHOW_FROM := 1
## Below this a "best" is not worth announcing: the first few hits of any session set one.
const RECORD_SHOW_FROM := 6
## Above and to the right of its number. Where it actually lands is up to `_place`.
const TAG_OFFSET := Vector2(30, -22)

func _tag_streak(currency: StringName, source_id: StringName, at: Vector2, ramp: Array,
		tier: int) -> void:
	if source_id == &"automation" or source_id == &"":
		return
	var hot := mini(tier + 1, TIER_SIZE.size() - 1)
	# **One tag of each kind on screen at a time**, keyed: the newest replaces the last. A
	# streak is one number that is going up, not a tag per hit — twelve hits in a second used
	# to leave "x3" through "x12" stacked over each other in one smear.
	if currency == Economy.BONES:
		var streak := Economy.damage_streak()
		if streak >= STREAK_SHOW_FROM:
			# A record in progress says so: the one time a streak is worth pushing for.
			var record := streak >= RECORD_SHOW_FROM and streak >= int(Economy.stats.get("best_streak", 0))
			spawn_number("x%d best" % streak if record else "x%d" % streak,
				at + TAG_OFFSET, ramp[hot], 0.8, hot, hot, &"streak")
		return
	if currency == Economy.HEARTS:
		# Only on the act's own number, not on a hot tub's trickle arriving mid-streak.
		if not Economy.paying_kind_act:
			return
		var combo := Economy.kindness_combo()
		if combo >= COMBO_SHOW_FROM:
			var b := ItemDB.balance
			var mult := EconomyMath.kindness_combo(combo, b.kindness_combo_step, b.kindness_combo_max)
			spawn_number("x%.1f" % mult, at + TAG_OFFSET, ramp[hot], 0.8, hot, hot, &"combo")

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
		1.6, TIER_SIZE.size() - 1, RANK_HEADLINE, &"knockout")
	# A record round gets a second line, over the headline like a banner. Economy has already
	# closed the round by the time he lands, because it connects to the bus before this layer
	# does. It used to be aimed 56px *under* a headline 77px tall, so the two shared their middle
	# band; placed clear of the headline's punch, under was so far down that the fountain had no
	# room left to rise without flying through it. Over, the space between the headline and him
	# is the fountain's.
	var round := Economy.last_round
	if not round.is_empty() and bool(round.get("record", false)) and int(round.get("number", 0)) > 1:
		spawn_number("NEW BEST ROUND", centre - Vector2(0.0, 56.0), BONES_RAMP[BONES_RAMP.size() - 1],
			1.1, TIER_SIZE.size() - 1, RANK_HEADLINE, &"best_round", LEAN_UP)
	_fountain(_buddy_position(centre), total,
		maxf(_line_bottom(&"knockout"), _line_bottom(&"best_round")) + HUD_MARGIN)

## Coins bursting out of the heap. Each is a share of the bonus rather than a decoration,
## so the fountain adds up to the number the player was just shown.
##
## `ceiling` is the bottom of the headline: no coin is thrown hard enough to reach it. The
## coins are a spray from one point and are not placed like the rising lines, so the one thing
## they must not do is fly through the words that say what they add up to — which they did,
## straight through NEW BEST ROUND. Where he lies too close under the headline for any arc to
## fit, they are thrown as they always were.
func _fountain(origin: Vector2, total: float, ceiling: float = -INF) -> void:
	var coins := maxi(1, int(ItemDB.balance.knockout_fountain_coins * Settings.intensity_scale()))
	var share := total / float(coins)
	var from := origin - Vector2(0, ARC_ORIGIN_LIFT)
	var room := from.y - ceiling
	var climb := sqrt(2.0 * ARC_GRAVITY * room) if room > ARC_MIN_ROOM else INF
	for i in coins:
		var angle := lerpf(-PI * 0.88, -PI * 0.12, float(i) / float(maxi(1, coins - 1)))
		angle += randf_range(-0.1, 0.1)
		var velocity := Vector2.RIGHT.rotated(angle) * randf_range(ARC_SPEED_MIN, ARC_SPEED_MAX)
		velocity.y = maxf(velocity.y, -climb)
		spawn_arc("+%s" % _format(share), from, velocity, BONES_COLOUR, float(i) * ARC_STAGGER)

## The lowest a live line with this key reaches, at the top of its punch, or -INF.
func _line_bottom(key: StringName) -> float:
	for slot in _pool.size():
		if _held_on[slot] == 1 and _held_key[slot] == key and _pool[slot].visible:
			return _held_from[slot].y + _held_half[slot].y * _held_punch[slot] + _held_pad[slot].y
	return -INF

## Found by group, never by path — FXLayer is on a CanvasLayer and he is in the world
## (docs/decisions.md D9). Falls back to the given point if he is somehow not in the tree.
func _buddy_position(fallback: Vector2) -> Vector2:
	var buddy := get_tree().get_first_node_in_group(&"buddy") as Node2D
	return buddy.global_position if buddy else fallback

# --- keeping the numbers off the HUD (D48) ---------------------------------

## Gap left between a number and the HUD when one is moved out of the way.
const HUD_MARGIN := 10.0

## How long a read of the HUD's rect is trusted. The rect only changes when the window
## resizes or the HUD parks itself, and `hover_drawer.gd` records that drawers polling
## `screen_rect()` every frame for eight hours was the largest "runs when nothing is
## happening" cost in the shell. Numbers spawn per hit, which can be many a second, so this
## is capped rather than left to the caller: four reads a second, and auto-hide is tracked
## within a quarter of a second of parking.
const HUD_RECT_TTL_MSEC := 250

var _hud_rect := Rect2()
var _hud_rect_msec := -HUD_RECT_TTL_MSEC

## Move a number out of the HUD's corner rather than under or over it.
##
## The alternatives were to shrink the HUD or to draw the numbers on top of it. Shrinking
## trades a permanent loss of readable state for a transient collision. Drawing on top hides
## the purse and the meter at exactly the moment the player is being paid, which is when
## those two numbers are worth watching. Moving the number keeps both, and it only happens on
## the small fraction of hits that land in one corner.
##
## Sideways first, because these rise as they live: pushing a number down puts it back under
## the HUD a moment later. Down is the fallback for a play area too narrow to step aside in,
## where sideways would push it off the other edge.
##
## Against its settled size, not the peak of its punch. Clearing the punch pushed a centred
## REINCARNATED ninety pixels off centre for the whole of its life, to spare the card a fifth
## of a second of overhang — and the numbers draw above the HUD, so for that moment the number
## is whole and it is the card that is covered.
func _clear_of_hud(centre: Vector2, half: Vector2, rise: float = RISE_PIXELS) -> Vector2:
	var keep := _hud_keep_out()
	if keep.size.x <= 0.0 or keep.size.y <= 0.0:
		return centre
	# The band it will occupy over its whole life, not just where it starts.
	var band := Rect2(centre - half, half * 2.0)
	band.position.y -= rise
	band.size.y += rise
	if not keep.intersects(band):
		return centre
	var view := get_viewport().get_visible_rect().size
	var beside := keep.end.x + HUD_MARGIN + half.x
	if beside + half.x <= view.x:
		return Vector2(beside, centre.y)
	return Vector2(centre.x, keep.end.y + HUD_MARGIN + half.y)

func _hud_keep_out() -> Rect2:
	# Numbers can be asked for during teardown — a kind item banks its sustained kindness in
	# `_exit_tree`, which pays out — and by then this layer may have left the tree, where
	# `get_tree()` is null and the group lookup below is a hard error. Nothing to dodge at
	# that point anyway.
	if not is_inside_tree():
		return Rect2()
	var now := Time.get_ticks_msec()
	if now - _hud_rect_msec < HUD_RECT_TTL_MSEC:
		return _hud_rect
	_hud_rect_msec = now
	_hud_rect = Rect2()
	var hud := get_tree().get_first_node_in_group(HUD.GROUP_HUD)
	if hud and hud.has_method("shell_rect"):
		_hud_rect = hud.call("shell_rect") as Rect2
	return _hud_rect

# --- keeping the numbers apart ---------------------------------------------
#
# **Two numbers are never drawn over each other.** Every rising number holds the space it will
# pass through for the whole of its life, and a new one is put where no live one will be at any
# moment of either's life — not just where none is now. That distinction is the bug this
# replaces: numbers rise on an ease-out, so a young one rises faster than an old one and catches
# it up, and a pair that started a line apart could be a smear half a second later.
#
# It was three separate collisions, all visible in `ui_shots` 16-juice: two rank-ups on the same
# frame printed at one point ("BASEBALE BATNRANK 43" is MACE RANK 4 behind BASEBALL BAT RANK 43),
# a streak tag aimed 22px above a number that is 24px tall, and a burst of hits piling a dozen
# numbers onto one pixel with ±18px of random drift as the only separation.
#
# Placement is solved once, when a number is spawned, and never per frame: numbers arrive
# several times a second for eight hours and the layer has no `_process` to spend. Every
# number moves on the same closed-form path (a quadratic ease-out rise, no sideways drift), so
# where it will be at any time is known the moment it starts — and because two quadratics differ
# by a quadratic, whether two paths ever meet is an endpoint-and-vertex check, not a simulation.
#
# What happens when there is no room within reach of where it happened:
#  - a more important number (a bigger tier, a headline) takes the space, and whatever was in
#    the way is put away early;
#  - an equal or lesser one is **not drawn**. The purse and the rate row have counted it; a
#    number that could only be drawn on top of another was never going to be read.
#
# The knockout fountain's coins are not part of this: they are thrown on arcs from one point by
# design, and a spray that starts at a single pixel cannot also start apart. What they are kept
# from is the words: they draw beneath every rising line, and are thrown no higher than the
# bottom of the headline (`_fountain`).

## Returned by `spawn_number` when a number was not drawn.
const NOWHERE := Vector2(INF, INF)

## Progression lines — a rank, a clean, a knockout, a rebirth. Always drawn: they search the
## whole play area for room, and past that put away anything lesser that is in the way. Payout
## numbers rank by their tier, 0..4, and a streak tag by its own (one hotter than its number).
const RANK_HEADLINE := 10

## How far a payout may be moved from where it happened before it is not drawn instead: this
## many of its own line heights, and never less than `REACH_MIN`. The floor is what lets a small
## number get past a big one — clearing a tier-3 number mid-punch is 55px for a "+8.0", which a
## reach counted in the small number's own 21px lines never covered, so the small one was lost
## beside every big one. Near enough that every number is still visibly about its own hit.
const REACH_LINES := 2.6
const REACH_MIN := 100.0

## Which way a line would rather be moved, when it has to be. A rank or a clean over him leans
## up, because below the first line is his head, and so does the knockout's banner, because
## below the headline is the fountain's; "+2.50 MARROW" leans down, because it belongs under
## REINCARNATED. Moving against the lean costs `LEAN_COST` times as much. Payout numbers take
## whichever is nearer.
const LEAN_UP := -1
const LEAN_DOWN := 1
const LEAN_COST := 2.5

## The punch-in, which is the one moment a number is bigger than its settled size. Reserved in
## full: two numbers from the same frame are both mid-punch at once.
const PUNCH_FROM := 0.55
const PUNCH_IN := 0.09
const PUNCH_OUT := 0.13
const PUNCH_TIME := PUNCH_IN + PUNCH_OUT
## `TRANS_BACK` overshoots its target by a tenth of the distance travelled, so the largest a
## number ever gets is past the scale it is tweened to.
const BACK_OVERSHOOT := 1.1

## Rows of the constraint table, rebuilt for each number placed: one per live number that is in
## the way anywhere. Members rather than locals so a busy desk reuses the same buffers.
var _c_slot := PackedInt32Array()
var _c_x := PackedFloat32Array()
var _c_wide := PackedFloat32Array()      ## horizontal clearance while either is punching
var _c_narrow := PackedFloat32Array()    ## horizontal clearance once both have settled
var _c_punch := PackedVector2Array()     ## forbidden centre-y band if they overlap only then
var _c_whole := PackedVector2Array()     ## and if they overlap for the rest of their lives too

func spawn_number(text: String, world_pos: Vector2, colour: Color, scale: float = 1.0,
		tier: int = 0, rank: int = -1, key: StringName = &"", lean: int = 0) -> Vector2:
	var intensity := Settings.intensity_scale()
	# Out of the tree during teardown — a kind item banks its sustained kindness in its own
	# `_exit_tree`, which pays out — where there is no viewport to place anything in.
	if intensity <= 0.0 or not is_inside_tree():
		return NOWHERE
	tier = clampi(tier, 0, TIER_SIZE.size() - 1)
	if rank < 0:
		rank = tier
	# A keyed line replaces the last one of its kind rather than stacking beside it: one
	# streak tag, one rank line per item.
	if key != &"":
		_retire_key(key)
	var index := _take()
	var label := _pool[index]
	label.text = text
	# The saturated colour is the *outline*, with a pale core inside it. A number drawn in
	# one flat colour disappears into any desktop that happens to be near that colour; a
	# bright core in a hot outline over a dark shadow survives all of them.
	label.add_theme_color_override("font_color", CORE_RAMP[tier])
	label.add_theme_color_override("font_outline_color", colour)
	label.add_theme_font_size_override("font_size", TIER_SIZE[tier])
	label.add_theme_constant_override("outline_size", TIER_OUTLINE[tier])
	label.z_index = Z_LINE
	label.modulate.a = 1.0
	# reset_size() first, or the size is still the previous number's.
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	var half := label.size * 0.5 * scale
	var pad := _pad(tier, scale)
	var target := 1.0 + 0.12 * float(tier + 1)
	var punch := PUNCH_FROM + BACK_OVERSHOOT * (target - PUNCH_FROM)
	var rise := RISE_PIXELS * scale * (1.0 + float(tier) * 0.25)
	var at := _place(world_pos, half, pad, punch, rise, rank, lean)
	if not at.is_finite():
		label.visible = false
		return NOWHERE
	# Centred on `at`. The pivot is the label's own centre, so the drawn centre is
	# `position + size / 2` at every scale — the old `- half * scale` put a 1.6x headline a
	# third of its own width up and to the left of where it was aimed.
	label.position = at - label.size * 0.5
	label.scale = Vector2.ONE * scale * PUNCH_FROM
	label.visible = true

	# Everything starts at once, so every number's path is the same function of its age.
	var tween := create_tween().set_parallel(true)
	# Punch in, then settle. The overshoot is what makes it land rather than appear.
	tween.tween_property(label, "scale", Vector2.ONE * scale * target, PUNCH_IN) \
		.from(Vector2.ONE * scale * PUNCH_FROM).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE * scale, PUNCH_OUT).set_delay(PUNCH_IN) \
		.set_trans(Tween.TRANS_QUAD)
	# Straight up. The random sideways drift that used to separate a burst is gone: `_place`
	# separates them on purpose, and a drift nobody can predict is a collision nobody can rule
	# out.
	tween.tween_property(label, "position:y", label.position.y - rise, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Held at full opacity for the first half, then faded. Fading from the first frame makes
	# the number hardest to read exactly when it is largest.
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME * 0.5) \
		.set_delay(LIFETIME * 0.5).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: label.visible = false)
	_tweens[index] = tween

	_held_on[index] = 1
	_held_from[index] = at
	_held_half[index] = half
	_held_pad[index] = pad
	_held_punch[index] = punch
	_held_rise[index] = rise
	_held_rank[index] = rank
	_held_key[index] = key

	_sparkle(world_pos, colour, tier, intensity)
	return at

## The ink past the label's box. The outline is drawn outside the glyphs and the shadow two
## pixels right of them; vertically the font's own line height already has room for both.
func _pad(tier: int, scale: float) -> Vector2:
	return Vector2(float(TIER_OUTLINE[tier]) * 0.5 + 2.0, 0.0) * scale

## Where a new number goes: where it was aimed if nothing will be there, otherwise the nearest
## place within reach that nothing will be, otherwise over lesser numbers, otherwise nowhere.
##
## A headline only steps around other headlines. Anything lesser where it lands is put away:
## a knockout's second line used to travel two hundred pixels to get round the payout of the
## very hit that knocked him out, which read as two unrelated messages.
func _place(want: Vector2, half: Vector2, pad: Vector2, punch: float, rise: float,
		rank: int, lean: int) -> Vector2:
	var at := _clear_of_hud(want, half, rise)
	var down_cost := LEAN_COST if lean < 0 else (1.0 / LEAN_COST if lean > 0 else 1.0)
	if rank >= RANK_HEADLINE:
		_constrain(at, INF, half, pad, punch, rise, RANK_HEADLINE)
		var line_at := _nearest_free(at, half, pad, rise, INF, down_cost)
		if not line_at.is_finite():
			line_at = at
		_constrain(line_at, 0.0, half, pad, punch, rise, 0)
		_clear_for(line_at, rank)
		return line_at
	var reach := maxf((half.y + pad.y) * 2.0 * REACH_LINES, REACH_MIN)
	_constrain(at, reach, half, pad, punch, rise, 0)
	var spot := _nearest_free(at, half, pad, rise, reach, down_cost)
	if spot.is_finite():
		return spot
	# No room. Whatever is in the way at the aimed spot gives way to a number that outranks all
	# of it; otherwise this one is not drawn.
	for row in _c_slot.size():
		var band := _band(row, at.x)
		if band.x < at.y and at.y < band.y and _held_rank[_c_slot[row]] >= rank:
			return NOWHERE
	_clear_for(at, rank)
	return at

## Put away every number in the table that is in the way at `spot` and ranks below `rank`.
func _clear_for(spot: Vector2, rank: int) -> void:
	for row in _c_slot.size():
		var band := _band(row, spot.x)
		if band.x < spot.y and spot.y < band.y and _held_rank[_c_slot[row]] < rank:
			_retire(_c_slot[row])

## Fills the constraint table: for every live number within reach, the band of centre heights
## the new one may not start in, so that the two never overlap at any moment they are both alive.
##
## Relative motion, written out. Both rise by `R * e(age / LIFETIME)` with `e(x) = 2x - x^2`
## (`TRANS_QUAD` + `EASE_OUT`). With the new one at age `u` and the old one at `u + s`, the
## vertical gap changes by `D(u) = R_old * e((u + s) / L) - R_new * e(u / L)` — a quadratic, so
## its range over any stretch of time is its two ends and its vertex. Staying below the old one
## for the whole stretch needs `y >= y_old + (h_old + h_new) - min D`; staying above needs
## `y <= y_old - (h_old + h_new) - max D`; between the two is the band.
##
## Two stretches, because the punch-in makes both bigger for its first `PUNCH_TIME`: while
## either is punching the halves are the peak ones and the band is wider, and a column far
## enough to the side to miss the settled halves may still catch the punch.
##
## A number that cannot reach the search window, sideways or vertically, is left out of the
## table altogether: on a busy desk most of the pool is somewhere else. So is one ranked below
## `min_rank`, which is how a headline ignores the numbers it will clear out of its way.
func _constrain(at: Vector2, reach: float, half: Vector2, pad: Vector2, punch: float,
		rise: float, min_rank: int) -> void:
	_c_slot.clear()
	_c_x.clear()
	_c_wide.clear()
	_c_narrow.clear()
	_c_punch.clear()
	_c_whole.clear()
	var settled := half + pad
	var peak := half * punch + pad
	for slot in _pool.size():
		if _held_on[slot] == 0 or not _pool[slot].visible or _held_rank[slot] < min_rank:
			continue
		var running := _tweens[slot]
		if running == null or not running.is_valid():
			continue
		var age := running.get_total_elapsed_time()
		var left := LIFETIME - age
		if left <= 0.0:
			continue
		var from := _held_from[slot]
		var other := _held_half[slot] + _held_pad[slot]
		var other_peak := (_held_half[slot] * _held_punch[slot] + _held_pad[slot]) \
			if age < PUNCH_TIME else other
		var wide := other_peak.x + peak.x
		if absf(from.x - at.x) >= wide + reach:
			continue
		var cut := minf(PUNCH_TIME, left)
		var early := _gap_change(_held_rise[slot], age, rise, 0.0, cut)
		var sum_peak := other_peak.y + peak.y
		var punch_band := Vector2(from.y - sum_peak - early.y, from.y + sum_peak - early.x)
		var whole := punch_band
		var narrow := -1.0
		if cut < left:
			var late := _gap_change(_held_rise[slot], age, rise, cut, left)
			var sum := other.y + settled.y
			whole = Vector2(minf(punch_band.x, from.y - sum - late.y),
				maxf(punch_band.y, from.y + sum - late.x))
			narrow = other.x + settled.x
		if whole.y <= at.y - reach or whole.x >= at.y + reach:
			continue
		_c_slot.append(slot)
		_c_x.append(from.x)
		_c_wide.append(wide)
		_c_narrow.append(narrow)
		_c_punch.append(punch_band)
		_c_whole.append(whole)

## The range of `D(u)` over `[u0, u1]`: how much the vertical gap between an older number
## (rise `r_old`, already `s` seconds along) and a new one (rise `r_new`) changes.
func _gap_change(r_old: float, s: float, r_new: float, u0: float, u1: float) -> Vector2:
	var l := LIFETIME
	var qa := (r_new - r_old) / (l * l)
	var qb := 2.0 * r_old / l - 2.0 * r_old * s / (l * l) - 2.0 * r_new / l
	var qc := 2.0 * r_old * s / l - r_old * s * s / (l * l)
	var v0 := qc + u0 * (qb + u0 * qa)
	var v1 := qc + u1 * (qb + u1 * qa)
	var lo := minf(v0, v1)
	var hi := maxf(v0, v1)
	if absf(qa) > 1e-6:
		var vertex := -qb / (2.0 * qa)
		if vertex > u0 and vertex < u1:
			var v := qc + vertex * (qb + vertex * qa)
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return Vector2(lo, hi)

## The forbidden band a table row puts on a column, or an empty one if it cannot reach it.
func _band(row: int, x: float) -> Vector2:
	var dx := absf(x - _c_x[row])
	if dx < _c_narrow[row]:
		return _c_whole[row]
	if dx < _c_wide[row]:
		return _c_punch[row]
	return Vector2(INF, -INF)

## The cheapest free spot within `reach` (sideways plus weighted vertical distance), or NOWHERE.
##
## Columns tried: straight up and down from the aimed spot, and flush beside each number that
## is in the way there — close enough to read as one burst, far enough to miss its punch.
func _nearest_free(at: Vector2, half: Vector2, pad: Vector2, rise: float, reach: float,
		down_cost: float) -> Vector2:
	var view := get_viewport().get_visible_rect().size
	var keep := _hud_keep_out()
	var best_cost := reach + 0.001
	var y := _open_row(at.x, at.y, half, pad, rise, keep, view, best_cost, down_cost)
	var best := NOWHERE
	if is_finite(y):
		best = Vector2(at.x, y)
		if y == at.y:
			# The common case, and the one that has to stay cheap: nothing in the way.
			return best
		best_cost = _lift_cost(y - at.y, down_cost)
	var side := half.x + pad.x
	for row in _c_slot.size():
		var band := _band(row, at.x)
		if band.x >= band.y:
			continue
		for dir in [1.0, -1.0]:
			var x: float = _c_x[row] + float(dir) * _c_wide[row]
			var sideways := absf(x - at.x)
			if sideways >= best_cost:
				continue
			# A column of its own making must be on screen; the aimed one is taken as it comes.
			if x - side < 0.0 or x + side > view.x:
				continue
			y = _open_row(x, at.y, half, pad, rise, keep, view, best_cost - sideways, down_cost)
			if not is_finite(y):
				continue
			var cost := sideways + _lift_cost(y - at.y, down_cost)
			if cost < best_cost:
				best_cost = cost
				best = Vector2(x, y)
	return best

## What moving a number `by` pixels vertically costs: its distance, with a move down weighted.
func _lift_cost(by: float, down_cost: float) -> float:
	return by * down_cost if by > 0.0 else -by

## The free centre height in column `x` cheapest to move to from `y0` and costing less than
## `limit`, or INF. `y0` itself if nothing is in the way. Ties go up: numbers rise anyway.
func _open_row(x: float, y0: float, half: Vector2, pad: Vector2, rise: float, keep: Rect2,
		view: Vector2, limit: float, down_cost: float) -> float:
	var bands := PackedVector2Array()
	var clear := true
	for row in _c_slot.size():
		var dx := absf(x - _c_x[row])
		var band: Vector2
		if dx < _c_narrow[row]:
			band = _c_whole[row]
		elif dx < _c_wide[row]:
			band = _c_punch[row]
		else:
			continue
		bands.append(band)
		if y0 > band.x + 0.01 and y0 < band.y - 0.01:
			clear = false
	# The HUD is in the way of this column for the whole of the band the number would rise
	# through (D48), so it is just one more band here.
	if keep.size.x > 0.0 and absf(x - keep.get_center().x) < keep.size.x * 0.5 + half.x + pad.x:
		var hud := Vector2(keep.position.y - half.y, keep.end.y + half.y + rise)
		bands.append(hud)
		if y0 > hud.x + 0.01 and y0 < hud.y - 0.01:
			clear = false
	if clear:
		return y0
	var best := INF
	var best_d := limit
	for band in bands:
		for edge in [band.x, band.y]:
			var y: float = edge
			var d := _lift_cost(y - y0, down_cost)
			if d > best_d or (d == best_d and y >= best):
				continue
			if y - half.y < 0.0 or y + half.y > view.y:
				continue
			var blocked := false
			for other in bands:
				if y > other.x + 0.01 and y < other.y - 0.01:
					blocked = true
					break
			if not blocked:
				best = y
				best_d = d
	return best

## Put a number away early: it was in the way of something that matters more, or it is being
## replaced by a newer line of its own kind.
func _retire(slot: int) -> void:
	var running := _tweens[slot]
	if running != null and running.is_valid():
		running.kill()
	_tweens[slot] = null
	_pool[slot].visible = false
	_held_on[slot] = 0

func _retire_key(key: StringName) -> void:
	for slot in _pool.size():
		if _held_on[slot] == 1 and _held_key[slot] == key:
			_retire(slot)

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
	var index := _take()
	var label := _pool[index]
	label.text = text
	# Every override set, not just the colour. A coin used to inherit the size and outline of
	# whatever number last had its slot, so one fountain could be half 20px coins in a gold
	# outline and half 48px coins in Ectoplasm green.
	label.add_theme_color_override("font_color", CORE_RAMP[1])
	label.add_theme_color_override("font_outline_color", colour)
	label.add_theme_font_size_override("font_size", TIER_SIZE[1])
	label.add_theme_constant_override("outline_size", TIER_OUTLINE[1])
	label.scale = Vector2.ONE
	# Under the rising lines, so a coin that does cross one passes behind the words.
	label.z_index = Z_COIN
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
	_tweens[index] = tween

## A free slot if there is one, else the next in turn. A free list first, because the pool
## now holds its numbers' places: recycling a live number to make room for one that then
## finds nowhere to go would put a number away for nothing. A coin waiting out its stagger is
## hidden but not free — its tween is still running — so it is never taken from under itself.
func _take() -> int:
	var count := _pool.size()
	var index := _next
	for step in count:
		var slot := (_next + step) % count
		var running := _tweens[slot]
		if not _pool[slot].visible and (running == null or not running.is_valid()):
			index = slot
			break
	_next = (index + 1) % count
	var running := _tweens[index]
	if running != null and running.is_valid():
		running.kill()
	_tweens[index] = null
	_held_on[index] = 0
	return index

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

## The hit-stop **pauses physics**. It used to squeeze `Engine.time_scale`, and that was the
## cause of the rebounding the owner reported (D54).
##
## Godot hands the 2D solver `physics_step * time_scale`, so `0.05` did not slow the world so
## much as shrink the timestep from 1/60 s to 1/1200 s. A `PinJoint2D`'s positional correction
## is `error * bias / step`, so the drag joint's authority went up **twentyfold** for the
## duration — while `BaseDraggable._physics_process` went on chasing the real cursor in real
## time, opening fresh error every one of those frames. The joint turned that error into
## velocity and the body kept it when time returned to 1.0.
##
## It was armed by the very contact it amplified, which made it a positive feedback loop:
## a bigger hit bought a longer stop, and a longer stop bought a bigger launch. Measured on a
## rig with the shipped bat and buddy, an eight-frame stop threw him at **24,729 px/s**;
## freezing instead of squeezing gives **2,056**.
##
## Freezing is also what a hit-stop is supposed to be. Everything that is not the simulation —
## the numbers, the shake, the tweens — keeps running, which is the effect the player came for.
func _hit_stop(seconds: float) -> void:
	var now := Time.get_ticks_msec()
	# Overlapping hits must not stack into a visible freeze.
	if now < _hit_stop_until_msec:
		return
	_hit_stop_until_msec = now + int(seconds * 1000.0)
	BaseDraggable.physics_frozen = true
	PhysicsServer2D.set_active(false)
	# ignore_time_scale is kept even though nothing scales time now: it costs nothing and it
	# is one less thing to remember if a slow-motion effect ever does arrive.
	await get_tree().create_timer(seconds, true, false, true).timeout
	PhysicsServer2D.set_active(true)
	BaseDraggable.physics_frozen = false

## The restore above sits after an `await`. If this layer is freed mid-stop — a scene change,
## a quit, a killed test run — that coroutine is abandoned and physics stays switched off for
## the rest of the process, which looks exactly like the game hanging.
func _exit_tree() -> void:
	PhysicsServer2D.set_active(true)
	BaseDraggable.physics_frozen = false
	# Belt and braces: an older build squeezed time here, and a save left mid-stop by a
	# previous version has no other way back.
	Engine.time_scale = 1.0

# --- the things that happen to him ------------------------------------------
#
# Progression used to be invisible: a rank ticked up inside a panel nobody had open, a
# Reincarnation was a toast in the corner, a full clean was a face. Each of these is now a
# line over his head in the same face as a payout, because they are the same kind of thing —
# a reward — and the player has already learned where to look for one.

const MARROW_COLOUR := Color("46c48f")
const CLEAN_COLOUR := Color("8fd8ff")

func _on_mastery_rank_up(item_id: StringName, rank: int) -> void:
	var item := ItemDB.get_item(item_id)
	var short := item.display_name if item else String(item_id)
	# Keyed per item: a newer rank of the same toy replaces the line rather than stacking on
	# it. Two *different* toys ranking on one frame — a hit that levels the bat while the mace
	# is still catching up — both print, one above the other.
	spawn_number("%s  RANK %d" % [short.to_upper(), rank], _buddy_position(_centre()) + Vector2(0, -78),
		BONES_RAMP[2], 0.9, 2, RANK_HEADLINE, StringName("rank:%s" % item_id), LEAN_UP)

## The headline of the whole game. Centre of the play area like the knockout, top tier,
## in Ectoplasm — and the Marrow it paid on a second line, so the number the player just
## chose to reset everything for is the biggest number they see that session.
func _on_prestige_performed(gained: float) -> void:
	var centre := _centre()
	spawn_number("REINCARNATED", centre, MARROW_COLOUR, 1.6, TIER_SIZE.size() - 1,
		RANK_HEADLINE, &"reincarnated")
	spawn_number("+%.2f MARROW" % gained, centre + Vector2(0, 60), MARROW_COLOUR, 1.1,
		TIER_SIZE.size() - 1, RANK_HEADLINE, &"marrow", LEAN_DOWN)

var _last_grime := 0.0

func _on_grime_changed(value: float) -> void:
	if is_zero_approx(value) and _last_grime > 0.25:
		spawn_number("SQUEAKY CLEAN", _buddy_position(_centre()) + Vector2(0, -78), CLEAN_COLOUR,
			0.9, 2, RANK_HEADLINE, &"clean", LEAN_UP)
	_last_grime = value

## Coming back to the game: what he earned while you were out, thrown off him as coins the
## moment the window is up. The Dream Journal toast says it; this shows it, because the
## reunion is the genre's whole point and it deserves more than a line of text.
func welcome_shower(bones: float, hearts: float) -> void:
	if Settings.intensity_scale() <= 0.0:
		return
	var from := _buddy_position(_centre()) - Vector2(0, ARC_ORIGIN_LIFT)
	var index := 0
	for pair in [[bones, BONES_COLOUR, 6], [hearts, HEARTS_COLOUR, 4]]:
		var total := float(pair[0])
		if total < 0.01:
			continue
		var coins := int(pair[2])
		for i in coins:
			var angle := lerpf(-PI * 0.85, -PI * 0.15, float(i) / float(maxi(1, coins - 1)))
			spawn_arc("+%s" % _format(total / float(coins)), from,
				Vector2.RIGHT.rotated(angle) * randf_range(ARC_SPEED_MIN * 0.8, ARC_SPEED_MAX * 0.8),
				pair[1], float(index) * ARC_STAGGER)
			index += 1

func _centre() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5
