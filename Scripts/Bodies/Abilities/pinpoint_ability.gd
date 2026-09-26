class_name PinpointAbility
extends ChargeAbility

## Hold right and a crosshair walks onto him; let go and the beak goes into that one spot (D74):
## the war pick's Pinpoint.
##
## **Holding** raises the pick over the shoulder (the bat's cock, `cock_degrees`) and puts a
## crosshair on the beak's point, which walks across to his skull over `charge_seconds`, wobbling
## less as it comes, and closes on it. When it arrives it locks — a click, a red ring — and rides
## on him wherever he goes. He knows: the crosshair on him is the held gun's aim (`aimed_at`).
##
## **Letting go** drives the beak at the crosshair: the hand lifts `raise_px` and then goes, the
## katana's mechanism (`BaseDraggable.hand_offset`) aimed at a point instead of through him, in
## `drive_seconds`, never further than `reach`. For the drive he and the pick do not collide, and
## the beak's point is swept for the spot: if it comes within `pin_radius` of it, the pick goes in
## — `pick_force` scaled by how fast the point was going (0.6x to 1.4x of `pick_speed`), through
## `Buddy.take_impulse` at the pick's multiplier times `pick_mult` — with almost no shove
## (`shove`): everything it has, on one small spot. It holds there `hold_seconds`, then comes out.
## Let go before the lock and the spot is wherever the crosshair had got to: off him, the beak
## finds nothing, and that is the whole cost of rushing it. "And nowhere else": for the drive it
## touches nothing but the spot.
##
## The Home Run is the other charge: that one winds a swing and throws him. This one aims.
##
## Row: `charge_seconds`, `cock_degrees`, `cock_frequency`, `cock_accel`, `raise_px`,
## `drive_seconds`, `hold_seconds`, `return_seconds`, `reach`, `pin_radius`, `pick_force`,
## `pick_speed`, `pick_mult`, `shove`, `settle_seconds`, `turn_frequency`, `turn_accel`,
## `guide_frequency`, `guide_accel`.

const AIM := 0
const RAISE := 1
const DRIVE := 2
const HOLD := 3
const BACK := 4
const SETTLE := 5

var _step := AIM
var _t := 0.0
var _spot := Vector2.INF
var _locked := false
var _cross: Crosshair
var _offset := Vector2.ZERO
var _path := Vector2.ZERO
var _raise := Vector2.ZERO
var _last_point := Vector2.INF
var _next_tell := 0.0
var _excepted: Buddy
var _struck := false
var _beak_local := Vector2.ZERO
## Which way the beak points, body-local: from the head's weight to its point.
var _beak_dir := Vector2.RIGHT
var _drive_dir := Vector2.RIGHT
var _angle_from := 0.0
var _strike_angle := 0.0

## For the suites: where the spot was, whether it locked, how close the beak came, and the hit.
var last_spot := Vector2.INF
var last_locked := false
var last_miss := INF
var last_pick := 0.0
var last_point_speed := 0.0

func _ready() -> void:
	super._ready()
	_beak_local = _find_beak()
	var from_head := _beak_local - body.center_of_mass
	_beak_dir = from_head.normalized() if from_head.length_squared() > 1.0 else Vector2.RIGHT

func is_armed() -> bool:
	return false

func is_aiming() -> bool:
	return _active and _step == AIM

func is_locked_on() -> bool:
	return _active and _locked

func is_driving() -> bool:
	return _active and _step >= RAISE and _step <= HOLD

func hit_multiplier() -> float:
	return 1.0

func pip_fill() -> float:
	return _charge if _active and _step == AIM else -1.0

func spot() -> Vector2:
	return _spot

## The beak's point: of the weapon's shapes, the extreme point furthest from the grip on the side
## the head points — the beak, not the flat of the hammer.
func _find_beak() -> Vector2:
	var best := body._find_tip() if body else Vector2.ZERO
	var far := -1.0
	for child in body.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		var candidates: Array[Vector2] = []
		var capsule := cs.shape as CapsuleShape2D
		if capsule:
			# A capsule's point is the end of its axis, not a corner of its box.
			candidates = [Vector2(0.0, capsule.height * 0.5), Vector2(0.0, -capsule.height * 0.5)]
		else:
			var rect := cs.shape.get_rect()
			candidates = [rect.position, rect.end, Vector2(rect.position.x, rect.end.y),
				Vector2(rect.end.x, rect.position.y)]
		for corner in candidates:
			var local: Vector2 = cs.transform * corner
			# Only the head: above the grip by at least half the haft.
			if local.y > body.grip_offset.y - 40.0:
				continue
			var d := local.distance_to(body.grip_offset) + absf(local.x - body.grip_offset.x) * 2.0
			if d > far and local.x > body.grip_offset.x:
				far = d
				best = local
	return best

func beak_world() -> Vector2:
	return body.to_global(_beak_local)

## His skull: where a crosshair walks to.
func _skull() -> Vector2:
	var him := buddy()
	if him == null:
		return Vector2.INF
	var rect := him.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y + 22.0)

func _on_press() -> void:
	_phase = WINDING
	_step = AIM
	_t = 0.0
	_charge = 0.0
	_locked = false
	_struck = false
	_full = false
	_next_click = 0.0
	_next_tell = 0.0
	last_locked = false
	last_miss = INF
	last_pick = 0.0
	last_point_speed = 0.0
	_spot = beak_world()
	run(true)
	threaten(true)
	if _cross == null:
		_cross = Crosshair.new()
		_cross.name = "PinpointCrosshair"
		_cross.top_level = true
		_cross.z_index = 40
		add_child(_cross)
	_cross.visible = true
	_cross.show_at(_spot, 1.0, false)
	sound(&"tock", -14.0, 1.6)
	_update_pip()

func _on_tick(delta: float) -> void:
	_t += delta
	match _step:
		AIM:
			_aim(delta)
		RAISE, DRIVE, HOLD, BACK:
			_drive(delta)
		SETTLE:
			if not overlaps_him() or _t >= num("settle_seconds", 0.8):
				finish(-1.0 if _struck else num("cooldown", 5.0) * 0.5)

## The crosshair walks from the beak to his skull and closes on it; the pick is raised meanwhile.
func _aim(delta: float) -> void:
	_charge = minf(1.0, _charge + delta / maxf(num("charge_seconds", 0.8), 0.05))
	_cock()
	_tremble()
	# The beak reddens as the crosshair walks on (D77), full once it has locked.
	AbilityFX.shine(sprite(), accent(), 0.1 + 0.4 * _charge)
	var skull := _skull()
	if skull == Vector2.INF:
		return
	var from := beak_world()
	var k := _charge * _charge * (3.0 - 2.0 * _charge)
	var wobble := (1.0 - _charge) * 12.0
	var jitter := Vector2(sin(_t * 23.0), cos(_t * 19.0)) * wobble
	_spot = from.lerp(skull, k) + jitter
	if _charge >= 1.0:
		_spot = skull
		if not _locked:
			_locked = true
			last_locked = true
			sound(&"plink", -6.0, 1.7)
			sound(&"tock", -8.0, 2.0)
			var fx := fx()
			if fx:
				fx.ring(skull, 24.0, Color("ff4d2e"), 0.18, 2.0)
		_next_tell -= delta
		if _next_tell <= 0.0:
			_next_tell = 0.5
			tell(&"targeted", skull)
	else:
		_next_click -= delta
		if _next_click <= 0.0:
			sound(&"ratchet", -16.0, 1.0 + 0.8 * _charge, 0.0)
			_next_click = 0.1
	_cross.show_at(_spot, 1.0 - 0.6 * k, _locked)

func _on_release(_seconds: float) -> void:
	if _step != AIM:
		return
	_rest_sprite()
	threaten(false)
	last_spot = _spot
	_step = RAISE
	_t = 0.0
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	_raise = Vector2(0.0, -num("raise_px", 36.0))
	_angle_from = body.global_rotation
	_last_point = beak_world()
	sound(&"whoosh", -10.0, 0.7)

func _drive(delta: float) -> void:
	var point := beak_world()
	var moved := point.distance_to(_last_point) / maxf(delta, 0.001) if _last_point != Vector2.INF else 0.0
	match _step:
		RAISE:
			var k := clampf(_t / 0.06, 0.0, 1.0)
			_set_offset(_raise * k)
			_turn_to(_angle_from)
			if k >= 1.0:
				_step = DRIVE
				_t = 0.0
				_aim_strike()
				body.apply_central_impulse(_drive_dir * body.mass * 500.0)
				sound(&"whoosh", -4.0, 1.2)
		DRIVE:
			var k := clampf(_t / maxf(num("drive_seconds", 0.09), 0.01), 0.0, 1.0)
			_set_offset(_raise.lerp(_path, k * k))
			# The head comes over: from the raised angle to the one that puts the beak first.
			_turn_to(lerp_angle(_angle_from, _strike_angle, minf(1.0, k * 1.6)))
			if k >= 0.4:
				_guide_beak()
			last_point_speed = maxf(last_point_speed, moved)
			if _check_spot(_last_point, point, moved):
				return
			if k >= 1.0:
				_step = HOLD
				_t = 0.0
		HOLD:
			# Held there while the head, a body on a soft joint, catches the hand up — and, once it
			# is in, held in.
			_turn_to(_strike_angle)
			if not _struck:
				_guide_beak()
			last_point_speed = maxf(last_point_speed, moved)
			if not _struck and _check_spot(_last_point, point, moved):
				return
			if _t >= num("hold_seconds", 0.16):
				if not _struck:
					_whiff()
				_step = BACK
				_t = 0.0
		BACK:
			var k := clampf(_t / maxf(num("return_seconds", 0.2), 0.01), 0.0, 1.0)
			_set_offset(_path * (1.0 - k * k * (3.0 - 2.0 * k)))
			if k >= 1.0:
				_set_offset(Vector2.ZERO)
				_step = SETTLE
				_t = 0.0
	_last_point = point

## Where the strike goes: the beak leading along the line to the spot, and the hand wherever the
## grip has to be for the beak to arrive on it at that angle, a little past so it arrives moving.
func _aim_strike() -> void:
	var beak := beak_world()
	var to := _spot - beak
	_drive_dir = to.normalized() if to.length_squared() > 1.0 else Vector2.RIGHT
	_strike_angle = _drive_dir.angle() - _beak_dir.angle()
	var grip_to_beak := (_beak_local - body.grip_offset).rotated(_strike_angle)
	var grip_at := _spot + _drive_dir * 10.0 - grip_to_beak
	var cursor := hand_world() - _offset
	_path = (grip_at - cursor).limit_length(num("reach", 260.0))

## The wrist putting the point where the eye is: a spring on the beak's point toward the spot,
## damped on the point's own velocity, applied at the point — so the last of the way is aimed and
## not left to a 12 kg head on a soft joint, which arrived 36 px wide of it in a real window.
## Capped at `guide_accel`; a force, never a write to a velocity (D54).
func _guide_beak() -> void:
	var beak := beak_world()
	var r := beak - com_world()
	var v := body.linear_velocity + Vector2(-body.angular_velocity * r.y, body.angular_velocity * r.x)
	var w := num("guide_frequency", 30.0)
	var want := (_spot - beak) * w * w - v * (2.0 * 0.7 * w)
	var force := (want * body.mass).limit_length(body.mass * num("guide_accel", 30000.0))
	body.apply_force(force, beak - body.global_position)

## A torque about the grip toward `angle`: the held gun's PD, stiff, with gravity held (D56).
func _turn_to(angle: float) -> void:
	var err := wrapf(angle - body.global_rotation, -PI, PI)
	var inertia := pivot_inertia()
	var w := num("turn_frequency", 22.0)
	var pd := inertia * (w * w * err - 2.0 * 0.85 * w * body.angular_velocity)
	var cap := inertia * num("turn_accel", 900.0)
	var arm := com_world() - grip_world()
	var hold := -arm.x * body.mass * _gravity * body.gravity_scale
	body.apply_torque(hold + clampf(pd, -cap, cap))

## Did the beak's point come within `pin_radius` of the spot this tick? The segment it flew, so a
## fast point cannot skip over it.
func _check_spot(from: Vector2, to: Vector2, speed: float) -> bool:
	if _struck or _spot == Vector2.INF:
		return false
	var closest := Geometry2D.get_closest_point_to_segment(_spot, from, to)
	var miss := closest.distance_to(_spot)
	last_miss = minf(last_miss, miss)
	if miss > num("pin_radius", 26.0):
		return false
	# The spot is on him only if it was locked on him, or happens to be inside him anyway.
	var him := buddy()
	if him == null or not (_locked or touches_him(_spot, 4.0)):
		return false
	_struck = true
	var share := clampf(speed / maxf(num("pick_speed", 1100.0), 1.0), 0.6, 1.4)
	last_pick = num("pick_force", 1100.0) * share
	var dir := (to - from).normalized() if to.distance_squared_to(from) > 1.0 else Vector2.DOWN
	strike(last_pick, dir, _spot, num("pick_mult", 2.5), num("shove", 0.15))
	paid_off.emit(&"pinpoint")
	_step = HOLD
	_t = 0.0
	var fx := fx()
	if fx:
		fx.ring(_spot, 16.0, Color.WHITE, 0.1, 2.0)
		fx.ring(_spot, 44.0, Color("ff4d2e"), 0.2, 3.0)
		fx.chips(_spot, Color("f2ead8"), 8, 240.0)
		fx.burst(_spot, &"bone", Color("f2ead8"), 2, 200.0)
		fx.shake(5.0)
	sound(&"crack", -2.0, 1.45)
	sound(&"impact_metal", -6.0, 1.7)
	_cross.collapse()
	return true

func _whiff() -> void:
	var fx := fx()
	if fx:
		fx.puff(beak_world(), 4, WorldFX.DUST, 40.0, 0.4)
	sound(&"whoosh", -12.0, 1.6)
	_cross.visible = false

func _set_offset(offset: Vector2) -> void:
	var delta := offset - _offset
	_offset = offset
	body.hand_offset = offset
	if body.dragging and body.handle:
		body.handle.global_position += delta

func _on_hit() -> void:
	pass

func _on_dropped() -> void:
	_set_offset(Vector2.ZERO)
	if _step == AIM:
		finish(num("cooldown", 5.0) * 0.5)
	else:
		_step = SETTLE
		_t = 0.0

func _on_stop() -> void:
	super._on_stop()
	_offset = Vector2.ZERO
	if body:
		body.hand_offset = Vector2.ZERO
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null
	if _cross:
		_cross.visible = false
	_locked = false

## The crosshair: four ticks about a gap, drawn, closing as it homes and red once it has locked.
## Redrawn only while it moves, and gone with the effect.
class Crosshair extends Node2D:
	var _size := 1.0
	var _locked := false
	var _collapse := -1.0

	func show_at(at: Vector2, size: float, locked: bool) -> void:
		global_position = at.round()
		_size = size
		_locked = locked
		_collapse = -1.0
		visible = true
		queue_redraw()

	func collapse() -> void:
		_collapse = 0.0
		set_process(true)

	func _process(delta: float) -> void:
		if _collapse < 0.0:
			set_process(false)
			return
		_collapse += delta
		_size = maxf(0.0, 0.4 - _collapse * 3.0)
		if _size <= 0.0:
			visible = false
			_collapse = -1.0
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		var r := 6.0 + 22.0 * _size
		var ink := Color("ff4d2e") if _locked else Color.WHITE
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var a: Vector2 = d * r
			var b: Vector2 = d * (r + 8.0)
			var side := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([a - side * 2.0 + d * -1.0, b - side * 2.0,
				b + side * 2.0, a + side * 2.0 + d * -1.0]), Color.BLACK)
			draw_line(a, b, ink, 2.0)
		draw_rect(Rect2(-1, -1, 2, 2), ink)
