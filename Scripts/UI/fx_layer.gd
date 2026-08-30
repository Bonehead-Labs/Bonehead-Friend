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

const BONES_COLOUR := Color(1.0, 0.95, 0.8)
const HEARTS_COLOUR := Color(1.0, 0.6, 0.75)

var _pool: Array[Label] = []
## The tween currently animating each pool slot, so recycling one can stop it. Without this
## a reused label has two tweens writing its position, and the fountain makes that reachable
## — it claims most of the pool in a single frame, so the next few payouts wrap onto slots
## whose arc is still running and fly off along the old parabola.
var _tweens: Array[Tween] = []
var _next := 0
var _hit_stop_until_msec := 0

func _ready() -> void:
	layer = 5
	for i in POOL_SIZE:
		var label := Label.new()
		label.visible = false
		label.z_index = 100
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 5)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_pool.append(label)
		_tweens.append(null)

	EventBus.payout.connect(_on_payout)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.knockout_payout.connect(_on_knockout_payout)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)

# --- floating numbers ------------------------------------------------------

func _on_payout(currency: StringName, amount: float, world_pos: Vector2) -> void:
	if amount < 0.01:
		return
	var colour := BONES_COLOUR if currency == &"bones" else HEARTS_COLOUR
	spawn_number("+%s" % _format(amount), world_pos, colour)

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
	spawn_number("KNOCKOUT  +%s" % _format(total), centre, Color(1.0, 0.85, 0.35), 1.6)
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

func spawn_number(text: String, world_pos: Vector2, colour: Color, scale: float = 1.0) -> void:
	var intensity := Settings.intensity_scale()
	if intensity <= 0.0:
		return
	var label := _take()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.scale = Vector2.ONE * scale
	label.modulate.a = 1.0
	label.visible = true
	# Centre on the hit. reset_size() first, or the size is still the previous number's.
	label.reset_size()
	label.position = world_pos - label.size * 0.5 * scale

	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - RISE_PIXELS * scale, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: label.visible = false)
	_register(label, tween)

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

func _format(value: float) -> String:
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	if value >= 10.0:
		return "%d" % roundi(value)
	return "%.1f" % value

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
