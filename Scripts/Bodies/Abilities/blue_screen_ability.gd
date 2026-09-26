class_name BlueScreenAbility
extends StunAbility

## The monitor blue-screens and he freezes; what you hit him with meanwhile lands at once when he
## comes back (D74): Blue Screen.
##
## A tap, with him within `reach` of the monitor (further, and the press is refused like a press in
## the cooldown). The screen goes blue — a sad face and three lines of text on the monitor's own
## glass — and **he stops**: for `freeze_seconds` he is a statue, frozen where he stands (the
## knockout's own `freeze`, D4), staring, his animation held (`frozen`, a row at body speed zero),
## scanlines across him. The monitor clangs off him: a frozen body gives nothing.
##
## **The monitor's swings are stored.** A frozen body measures nothing, so the monitor keeps the
## count, the thrown axe's way (D74): each time it meets him moving at least `min_speed`, no more
## often than his own per-source cooldown, it stores one hit of `hit_force` scaled by how fast it
## was going (0.6x to 1.4x of `swing_speed`) — no number, no flinch, only a pip over his head. When
## the freeze ends he comes back all at once: every stored hit goes through `Buddy.take_impulse` on
## the same tick, at the monitor's multiplier times `dump_mult`, so all of them are dealt on one
## frame and each exactly once; he is thrown by `dump_shove` of their impulse, from the tick and
## before `Buddy.StepStart` (D64); and the screen reboots. If what is stored would knock him out,
## the dump comes early — a hit dealt after the knockout would be billed and never paid.
##
## The BONG is the other stun: that one is a daze you keep hitting through. This one is a pause
## and a bill.
##
## Row: `reach`, `freeze_seconds`, `min_speed`, `hit_force`, `swing_speed`, `dump_mult`,
## `dump_shove`, `dump_cap`, `claim_seconds`.

var _frozen: Buddy
var _stored: Array = []
var _last_store_msec := 0
var _last_speed := 0.0
var _touching := false
var _next_frozen_tell := 0.0
var _screen: Screen
var _scan: Scanlines
var _dump_pending := false

## For the suites: hits stored, and dealt in the dump, and how hard it threw him.
var last_stored := 0
var last_dumped := 0
var last_dump_speed := 0.0

func _exit_tree() -> void:
	super._exit_tree()
	if is_instance_valid(_scan):
		_scan.queue_free()
	_scan = null

func _can_start() -> bool:
	var him := buddy()
	if him == null or him.freeze or him.dragging:
		return false
	return com_world().distance_to(him_world()) <= num("reach", 420.0)

func is_armed() -> bool:
	return false

func is_frozen() -> bool:
	return _active and is_instance_valid(_frozen) and not _dump_pending

func is_dazed() -> bool:
	return is_frozen()

func stored() -> int:
	return _stored.size()

func hit_multiplier() -> float:
	return 1.0

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(_left / maxf(num("freeze_seconds", 1.5), 0.01), 0.0, 1.0)

func _on_press() -> void:
	var him := buddy()
	_left = num("freeze_seconds", 1.5)
	_stored.clear()
	_dump_pending = false
	_touching = false
	_last_speed = 0.0
	_next_frozen_tell = 0.0
	last_stored = 0
	last_dumped = 0
	last_dump_speed = 0.0
	_frozen = him
	him.freeze = true
	run(true)
	_show_screen(true)
	if not is_instance_valid(_scan):
		_scan = Scanlines.new()
		_scan.name = "BlueScreenScan"
		_scan.z_index = 3
		him.add_child(_scan)
	_scan.cover(him)
	var fx := fx()
	var at := him.get_interaction_rect().get_center()
	if fx:
		fx.ring(at, 70.0, Screen.BLUE, 0.2, 3.0)
		fx.ring(body.global_position, 60.0, Screen.BLUE, 0.2, 3.0)
	sound(&"bsod", -4.0, 1.0, 0.0)
	payoffs += 1
	tell(&"frozen", at)
	paid_off.emit(&"blue_screen")
	_update_pip()

func _on_tick(delta: float) -> void:
	var him := _frozen
	if not is_instance_valid(him):
		finish()
		return
	if _dump_pending:
		_dump(him)
		return
	# Picked up, or knocked down by something else: the freeze is over now.
	if him.dragging or him.health == null or him.health.down \
			or ExpressionBrain.KNOCKOUT_STATES.has(him.state):
		_left = 0.0
	else:
		_watch_swing(him)
	if _left > 0.0 and _stored_damage() + him.health.damage >= ItemDB.balance.knockout_damage:
		_left = 0.0
	_next_frozen_tell -= delta
	if _next_frozen_tell <= 0.0:
		_next_frozen_tell = 0.4
		tell(&"frozen", him.get_interaction_rect().get_center())
	_left -= delta
	if _left <= 0.0:
		_reboot(him)

## The monitor meeting the statue: a stored hit, sized by how fast it came in.
func _watch_swing(him: Buddy) -> void:
	var speed := body.linear_velocity.length()
	var touching := body.get_colliding_bodies().has(him)
	var came := maxf(speed, _last_speed)
	_last_speed = speed
	var now := Time.get_ticks_msec()
	var gap := int(ItemDB.balance.damage_cooldown * 1000.0)
	if touching and not _touching and came >= num("min_speed", 300.0) and now - _last_store_msec >= gap:
		_last_store_msec = now
		var share := clampf(came / maxf(num("swing_speed", 1100.0), 1.0), 0.6, 1.4)
		var rect := him.get_interaction_rect()
		var com := com_world()
		var at := Vector2(clampf(com.x, rect.position.x, rect.end.x), clampf(com.y, rect.position.y, rect.end.y))
		var dir := (at - com).normalized() if at.distance_squared_to(com) > 1.0 else Vector2.RIGHT
		_stored.append([num("hit_force", 1300.0) * share, dir, at])
		last_stored = _stored.size()
		if _scan:
			_scan.set_pips(_stored.size())
		var fx := fx()
		if fx:
			fx.ring(at, 18.0, Screen.BLUE, 0.12, 2.0)
		sound(&"impact_electric", -12.0, 0.7 + 0.08 * float(mini(_stored.size(), 8)), 0.0)
	_touching = touching

func _stored_damage() -> float:
	var b := ItemDB.balance
	var total := 0.0
	for hit in _stored:
		total += EconomyMath.damage_from_impulse(float(hit[0]), b.min_damage_impulse, b.damage_per_impulse,
			base_mult() * num("dump_mult", 1.3))
	return total

## Time's up: he is himself again, and every stored hit is handed to him on this tick.
func _reboot(him: Buddy) -> void:
	_unfreeze(him)
	var total := 0.0
	var push := Vector2.ZERO
	for hit in _stored:
		# Shoved by nothing here: the throw is the dump's, once, below.
		strike(float(hit[0]), hit[1], hit[2], num("dump_mult", 1.3), 0.0)
		total += float(hit[0])
		push += (hit[1] as Vector2) * float(hit[0])
	last_dumped = _stored.size()
	_stored.clear()
	if is_instance_valid(_scan):
		_scan.queue_free()
	_scan = null
	_show_screen(false)
	sound(&"reboot", -6.0, 1.0, 0.0)
	if last_dumped > 0:
		var side := signf(push.x) if absf(push.x) > 1.0 else signf(him.global_position.x - com_world().x)
		if side == 0.0:
			side = 1.0
		var speed := minf(total * num("dump_shove", 0.5) / maxf(him.mass, 0.01), num("dump_cap", 900.0))
		last_dump_speed = speed
		him.apply_central_impulse(Vector2(side, -0.45).normalized() * speed * him.mass)
		him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 1.5))
	_dump_pending = true

## The tick after: the stored hits are being dealt, all on this frame, and the picture says so.
func _dump(him: Buddy) -> void:
	_dump_pending = false
	var at := him.get_interaction_rect().get_center()
	if last_dumped > 0:
		var fx := fx()
		if fx:
			fx.ring(at, 60.0 + 12.0 * float(last_dumped), Screen.BLUE, 0.35, 4.0)
			fx.ring(at, 40.0, Color.WHITE, 0.2, 3.0)
			fx.chips(at, Color.WHITE, 4 + 2 * last_dumped, 320.0)
			fx.burst(at, &"star", WorldFX.GOLD, mini(3 + last_dumped, 9), 300.0)
			fx.shake(3.0 + 1.0 * float(last_dumped))
		sound(&"crack", -2.0, 0.8)
		# The bill arriving is the payoff (D77): "REBOOT!", and a flash as big as what was stored.
		fx_land(&"reboot", at)
	finish()

## Unfrozen — unless the knockout has him, which owns his freeze until he stands (D4).
func _unfreeze(him: Buddy) -> void:
	if is_instance_valid(him) and him.freeze and not ExpressionBrain.KNOCKOUT_STATES.has(him.state):
		him.freeze = false

func _on_dropped() -> void:
	# The freeze belongs to the screen, which is still blue wherever the monitor is.
	pass

func _on_stop() -> void:
	var him := _frozen
	_frozen = null
	if is_instance_valid(him):
		_unfreeze(him)
		# Anything still stored is dealt, never lost: a monitor binned mid-freeze still pays.
		if not _stored.is_empty() and body and body.is_inside_tree():
			for hit in _stored:
				strike(float(hit[0]), hit[1], hit[2], num("dump_mult", 1.3), 0.0)
	_stored.clear()
	if is_instance_valid(_scan):
		_scan.queue_free()
	_scan = null
	_show_screen(false)
	_dump_pending = false

func _show_screen(on: bool) -> void:
	if on and _screen == null:
		_screen = Screen.new()
		_screen.name = "BlueScreen"
		_screen.z_index = 1
		body.add_child(_screen)
		_screen.fit(_glass())
	if _screen:
		_screen.visible = on

## The glass: the monitor's own collider, less its bezel — the biggest box's top part.
func _glass() -> Rect2:
	if body.collider and body.collider.shape:
		var rect := body.collider.shape.get_rect()
		var xf := body.collider.transform
		var box := Rect2(xf * rect.position, rect.size * xf.get_scale().abs())
		return box.grow_individual(-8.0, -8.0, -8.0, -18.0)
	return Rect2(-44, -44, 88, 46)

## The blue screen on the monitor's glass: blue, a sad face, three lines of "text" and a
## progress bar, in two-pixel blocks so it is drawn at the art's own grain.
class Screen extends Node2D:
	const BLUE := Color("1f56d8")
	const INK := Color("f4f1e6")
	var _glass := Rect2(-44, -44, 88, 46)

	func fit(glass: Rect2) -> void:
		_glass = glass
		queue_redraw()

	func _draw() -> void:
		var g := Rect2(_glass.position.round(), _glass.size.round())
		draw_rect(g, BLUE)
		var o := g.position + Vector2(6, 6)
		# ":("
		draw_rect(Rect2(o + Vector2(0, 2), Vector2(4, 4)), INK)
		draw_rect(Rect2(o + Vector2(0, 10), Vector2(4, 4)), INK)
		draw_rect(Rect2(o + Vector2(10, 0), Vector2(4, 4)), INK)
		draw_rect(Rect2(o + Vector2(8, 4), Vector2(4, 8)), INK)
		draw_rect(Rect2(o + Vector2(10, 12), Vector2(4, 4)), INK)
		var lines := [0.8, 0.55, 0.7]
		for i in lines.size():
			var w: float = maxf(8.0, (g.size.x - 34.0) * float(lines[i]))
			draw_rect(Rect2(o + Vector2(22, 2 + i * 6), Vector2(w, 2)).abs(), INK)
		draw_rect(Rect2(g.position + Vector2(6, g.size.y - 8), Vector2(g.size.x * 0.3, 2)), INK)

## Frozen in the frame: blue scanlines across him, and a pip over his head for every hit stored.
## His child, so it rides with him; freed the moment the freeze ends.
class Scanlines extends Node2D:
	var _rect := Rect2()
	var _pips := 0

	func cover(him: Buddy) -> void:
		var r := him.get_interaction_rect()
		_rect = Rect2(him.to_local(r.position), r.size)
		queue_redraw()

	func set_pips(count: int) -> void:
		_pips = count
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(_rect.position.round(), _rect.size.round())
		var y := r.position.y + 2.0
		while y < r.end.y:
			draw_rect(Rect2(r.position.x, y, r.size.x, 2.0), Color(0.12, 0.34, 0.85, 0.35))
			y += 8.0
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), Screen.BLUE)
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - 2.0), Vector2(r.size.x, 2.0)), Screen.BLUE)
		var shown := mini(_pips, 10)
		var left := r.get_center().x - float(shown) * 5.0
		for i in shown:
			var at := Vector2(left + float(i) * 10.0, r.position.y - 14.0).round()
			draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color.BLACK)
			draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Screen.BLUE)
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), Screen.INK)
