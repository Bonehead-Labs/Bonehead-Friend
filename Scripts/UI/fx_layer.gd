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

var _pool: Array[Label] = []
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

	EventBus.payout.connect(_on_payout)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.knockout_payout.connect(_on_knockout_payout)

# --- floating numbers ------------------------------------------------------

func _on_payout(currency: StringName, amount: float, world_pos: Vector2) -> void:
	if amount < 0.01:
		return
	var colour := Color(1.0, 0.95, 0.8) if currency == &"bones" else Color(1.0, 0.6, 0.75)
	var prefix := "+" if currency == &"bones" else "+"
	spawn_number("%s%s" % [prefix, _format(amount)], world_pos, colour)

func _on_knockout_payout(total: float) -> void:
	if total < 0.01:
		return
	# The round's climax gets a bigger number in the middle of the play area, so it reads
	# even if the last hit landed at the edge of the screen.
	var centre := get_viewport().get_visible_rect().size * 0.5
	spawn_number("KNOCKOUT  +%s" % _format(total), centre, Color(1.0, 0.85, 0.35), 1.6)

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

## Round-robin rather than a free list: a number that is still animating when its slot
## comes back around is simply restarted, which is the correct behaviour under a burst.
func _take() -> Label:
	var label := _pool[_next]
	_next = (_next + 1) % _pool.size()
	return label

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
