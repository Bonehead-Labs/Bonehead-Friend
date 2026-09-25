class_name TimeStopPower
extends SpellPower

## Time stop (D72): click him and time stops around him — he hangs where he was, mid-air if he
## was in the air, tinted and still inside a clock-faced bubble. Every click on him while it
## lasts is a blow that does not land. When it runs out, or you click anywhere off him, time
## catches up: every banked blow lands in the same instant, each one its own hit, and he is
## thrown away from where you struck him.
##
## The blows are real hits the moment they land and not before: each is one `take_impulse` at
## the point you clicked (D7), so a burst of ten is ten numbers, ten chips and ten entries on
## the streak. The throw that follows is his own momentum, and its landing is billed to the
## spell (`Buddy.claim_impacts`, D65).
##
## Stopping him is `freeze`, which the knockout uses too, so the two are kept apart: a knockout
## that starts while he is stopped owns him from then on and the bubble simply goes, and a spell
## never unfreezes a body the knockout froze. Picking him up (Shift) ends the stop, as does
## holstering, and his velocity from before the stop is handed back to him either way.

## How long a stop lasts.
@export var stop_seconds: float = 4.0
## One banked blow, as the impulse he is handed when it lands.
@export var blow_impulse: float = 2600.0
@export var max_blows: int = 10
## The quickest two blows can be banked. A click faster than this is refused, not queued.
@export var blow_gap: float = 0.12
## The throw per blow, as an impulse, and the most it may add up to.
@export var shove_per_blow: float = 380.0
@export var max_shove: float = 3000.0
## Seconds before time can be stopped again, before "Faster Rewind".
@export var recharge_seconds: float = 3.0
@export var bubble_radius: float = 78.0
@export var claim_seconds: float = 2.0
@export var reach_padding: float = 12.0

var _stopped := false
var _started_msec := 0
var _next_blow_msec := 0
var _recharge_until_msec := 0
var _refresh_msec := 0
var _saved_velocity := Vector2.ZERO
var _saved_spin := 0.0
## Blows banked, as offsets from his centre, so they stay on him if the bubble is moved.
var _blows := PackedVector2Array()
var _bubble: Bubble
var _frozen: Buddy

func is_live() -> bool:
	return _stopped

func is_stopped() -> bool:
	return _stopped

func banked() -> int:
	return _blows.size()

## On him to start one; anywhere once one is running, because a click off him is how you let
## time go.
func can_fire_at(at: Vector2) -> bool:
	if _stopped:
		return true
	return _reachable(_buddy()) and _on_him(at, reach_padding)

func fire(at: Vector2) -> void:
	if _stopped:
		if _on_him(at, reach_padding):
			_bank(at)
		else:
			_resume()
		return
	if Time.get_ticks_msec() < _recharge_until_msec:
		_fizzle(at, ICE)
		return
	_stop()

func _spell_deactivated(_was_held: bool) -> void:
	if _stopped:
		_resume()

func _exit_tree() -> void:
	# A scene change mid-stop must not leave him frozen and blue in the next one.
	if _stopped and is_instance_valid(_frozen) and not ExpressionBrain.KNOCKOUT_STATES.has(_frozen.state):
		_frozen.freeze = false
		_frozen.modulate = Color.WHITE
	_stopped = false

func _stop() -> void:
	var buddy := _buddy()
	if not _reachable(buddy):
		return
	_stopped = true
	_frozen = buddy
	_started_msec = Time.get_ticks_msec()
	_next_blow_msec = 0
	_blows.clear()
	_saved_velocity = buddy.linear_velocity
	_saved_spin = buddy.angular_velocity
	buddy.freeze = true
	buddy.modulate = ICE_TINT
	_notice_player()
	_build()
	_bubble.show_at(buddy.global_position, bubble_radius, _tier())
	var fx := _fx()
	if fx:
		fx.ring(buddy.global_position, bubble_radius * 1.6, ICE, 0.3, 3.0)
		fx.puff(buddy.global_position, 10, ICE, 90.0, 0.6)
	AudioManager.play(&"time_stop", 0.0, -4.0)
	_face(&"time_stopped")
	_refresh_msec = Time.get_ticks_msec() + 400
	_use()
	set_process(true)
	_update_input()

func _bank(at: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if _blows.size() >= max_blows or now < _next_blow_msec or _frozen == null:
		_fizzle(at, ICE)
		return
	_next_blow_msec = now + int(blow_gap * 1000.0)
	var offset := (at - _frozen.global_position).limit_length(bubble_radius * 0.9)
	_blows.append(offset)
	_bubble.add_blow(offset)
	var fx := _fx()
	if fx:
		fx.ring(at, 22.0, Color.WHITE, 0.15, 2.0)
		fx.chips(at, ICE, 3, 120.0)
	# A tick that climbs with each blow banked, so a run of them is a count you can hear.
	AudioManager.play(&"wheel_tick", 0.02, -6.0, 1.0 + 0.08 * float(_blows.size()))

func _process(_delta: float) -> void:
	if not _stopped:
		set_process(false)
		return
	var buddy := _frozen
	if buddy == null or not is_instance_valid(buddy):
		_stopped = false
		_bubble.hide()
		set_process(false)
		_update_input()
		return
	# The knockout owns him now: it froze him itself and will unfreeze him when it is done.
	if ExpressionBrain.KNOCKOUT_STATES.has(buddy.state) or (buddy.health and buddy.health.down):
		_abandon()
		return
	if buddy.dragging:
		_resume()
		return
	var now := Time.get_ticks_msec()
	var left := 1.0 - float(now - _started_msec) / (stop_seconds * 1000.0)
	if left <= 0.0:
		_resume()
		return
	_bubble.position = buddy.global_position
	_bubble.left = left
	_bubble.queue_redraw()
	if now >= _refresh_msec:
		_refresh_msec = now + 400
		_face(&"time_stopped")

## Time catches up: he moves again, and every blow lands at once.
func _resume() -> void:
	if not _stopped:
		return
	_stopped = false
	var buddy := _frozen
	_frozen = null
	_bubble.hide()
	set_process(false)
	_recharge_until_msec = Time.get_ticks_msec() + int(recharge_seconds
		* Progression.get_modifier(item_id, &"cooldown_mult") * 1000.0)
	_update_input()
	if buddy == null or not is_instance_valid(buddy):
		return
	buddy.modulate = Color.WHITE
	if ExpressionBrain.KNOCKOUT_STATES.has(buddy.state):
		return
	buddy.freeze = false
	buddy.linear_velocity = _saved_velocity
	buddy.angular_velocity = _saved_spin
	var fx := _fx()
	AudioManager.play(&"time_resume", 0.0, -4.0)
	if fx:
		fx.ring(buddy.global_position, bubble_radius * 1.8, ICE, 0.35, 4.0)
		fx.chips(buddy.global_position, ICE, 14, 320.0)
	if _blows.is_empty():
		# Nothing banked: he shakes the stillness off, and that is all.
		_face(&"time_thawed")
		return
	var mult := effective_damage_mult()
	var push := Vector2.ZERO
	for offset in _blows:
		# Away from where each blow struck; a blow dead centre knocks him up.
		push += -offset.normalized() if offset.length() > 4.0 else Vector2.UP
		buddy.take_impulse(blow_impulse, item_id, mult, buddy.global_position + offset)
	if push.length() < 0.3 * float(_blows.size()):
		push += Vector2.UP * float(_blows.size())
	buddy.apply_central_impulse(push.normalized()
		* minf(shove_per_blow * float(_blows.size()), max_shove))
	buddy.claim_impacts(item_id, mult, claim_seconds)
	if fx:
		fx.shake(3.0 + 0.5 * float(_blows.size()))
		for offset in _blows:
			fx.ring(buddy.global_position + offset, 30.0, Color.WHITE, 0.2, 2.0)
	_blows.clear()
	# After his hits are dealt (a physics frame from now): the burst is one heavy blow on his
	# face, not ten flinches.
	get_tree().create_timer(0.08, true, true).timeout.connect(_after_burst)

func _after_burst() -> void:
	_face(&"time_resumed")

## The knockout took him mid-stop. Nothing is thrown and nothing is unfrozen — the banked blows
## are lost with the round they were going to finish.
func _abandon() -> void:
	_stopped = false
	if is_instance_valid(_frozen):
		_frozen.modulate = Color.WHITE
	_frozen = null
	_blows.clear()
	_bubble.hide()
	set_process(false)
	_update_input()

func recharge_until_msec() -> int:
	return _recharge_until_msec

func _build() -> void:
	if _bubble != null:
		return
	_bubble = Bubble.new()
	_bubble.name = "Bubble"
	_bubble.z_index = 36
	_bubble.visible = false
	add_child(_bubble)

## The stopped moment, drawn: a pale ring with the twelve marks of a clock face, one hand that
## sweeps back to twelve as the time runs out, and a white star frozen on every blow banked.
## Hard pixels throughout — no alpha, nothing resampled.
class Bubble extends Node2D:
	var radius := 78.0
	var left := 1.0
	var tier := 0
	var blows := PackedVector2Array()

	func show_at(at: Vector2, r: float, juice: int) -> void:
		position = at
		radius = r
		left = 1.0
		tier = juice
		blows.clear()
		visible = true
		queue_redraw()

	func add_blow(offset: Vector2) -> void:
		blows.append(offset)
		queue_redraw()

	func _draw() -> void:
		var ice := SpellPower.ICE
		var width := 2.0 + float(tier) * 0.5
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ice, width, false)
		draw_arc(Vector2.ZERO, radius - 5.0, 0.0, TAU, 44, Color.WHITE, 1.0, false)
		for i in 12:
			var a := TAU * float(i) / 12.0
			var dir := Vector2(sin(a), -cos(a))
			var inner := radius - (10.0 if i % 3 == 0 else 6.0)
			draw_line(dir * inner, dir * (radius - 2.0), Color.WHITE, 2.0 if i % 3 == 0 else 1.0)
		# The time left, as a hand from the centre and an arc that shortens around the rim.
		var hand := -PI * 0.5 + TAU * left
		draw_line(Vector2.ZERO, Vector2(cos(hand), sin(hand)) * (radius - 14.0), ice, 3.0)
		draw_arc(Vector2.ZERO, radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * left, 40, ice, 2.0, false)
		draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
		for offset in blows:
			_star(offset)

	## A blow that has not landed yet: a white star in a dark outline, so it reads on his white
	## bones as well as on the desk.
	func _star(at: Vector2) -> void:
		var r := 10.0
		var ink := Color("1a1d24")
		draw_line(at + Vector2(-r - 1, 0), at + Vector2(r + 1, 0), ink, 5.0)
		draw_line(at + Vector2(0, -r - 1), at + Vector2(0, r + 1), ink, 5.0)
		draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), ink)
		draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), Color.WHITE, 3.0)
		draw_line(at + Vector2(0, -r), at + Vector2(0, r), Color.WHITE, 3.0)
		draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), SpellPower.ICE)
		draw_line(at + Vector2(-r, -r) * 0.55, at + Vector2(r, r) * 0.55, SpellPower.ICE, 1.0)
		draw_line(at + Vector2(-r, r) * 0.55, at + Vector2(r, -r) * 0.55, SpellPower.ICE, 1.0)
