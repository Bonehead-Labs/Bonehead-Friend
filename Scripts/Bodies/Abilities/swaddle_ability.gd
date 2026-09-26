class_name SwaddleAbility
extends ThrowAbility

## The warm towel's Swaddle (docs/decisions.md D78): a tap near him, and it is thrown round his
## shoulders, straight from the dryer, and it stays there and keeps him warm.
##
## The Tomahawk's archetype, landing soft. Within `reach` of him, the towel leaves the hand on the
## low arc at his shoulders; for the flight the two do not collide and it is swept for him (D74).
## Arriving, it **wraps him**: frozen, laid level across his shoulders a little wider than it
## folds, drawn over him — round his middle, under his face (`_drape`) — and riding him
## wherever he goes for `wrap_seconds`, the cleaver's way of staying in him (D74) with nothing sharp
## about it. Its picture rides his breath too (`_breathe`): his figure rises and falls inside its
## frame, and a towel fixed to his collider was left behind at the top of every breath. Its ends hang
## down his sides and steam rises off them (the payoff's shape, `towel_wrap`). The wrap itself is one
## act (`wrap_value`); while it is on him it pays `warm_rate` a second, banked and paid as a rate, the
## towel's own warmth without a hand on it — which is the point: the hand is free to pet him.
## He is `swaddled`: eyes closed, bobbing slowly, for as long as it is round him.
##
## It slides off when the time is up, when he is picked up or knocked down, or when the player takes
## hold of it — the towel is still the grab region it always was.
##
## Row: `reach`, `throw_speed`, `wrap_seconds`, `wrap_value`, `warm_rate`, `drape`, `out_seconds`.

const FLYING := 60
const WRAPPED := 61

var _wrap_local := Transform2D.IDENTITY
var _wrapped: Buddy
var _layer := 0
var _mask := 0
var _freeze_mode := RigidBody2D.FREEZE_MODE_STATIC
var _frozen := false
var _z := 0
var _sprite_scale := Vector2.INF
var _sprite_pos := Vector2.INF
var _next_tell := 0.0
var _banked := 0.0
var _since_flush := 0.0
## His body sprite while it is round him: the towel's picture is re-laid as his frame changes, in
## step with his face (`_breathe`).
var _puppet: AnimatedSprite2D

## For the suites: whether it wrapped him, for how long, and why it came off; and how far its picture
## was last lifted with his breath (`_breathe`), in his frame.
var wrapped := false
var wrap_time := 0.0
var came_off := &""
var ride_lift := 0.0

func is_wrapped() -> bool:
	return _active and _phase == WRAPPED

## 0..1 of the wrap left, for its badge over him (D77).
func wrap_left() -> float:
	if not is_wrapped():
		return 0.0
	return clampf(1.0 - wrap_time / maxf(num("wrap_seconds", 5.0), 0.01), 0.0, 1.0)

func _can_start() -> bool:
	var him := buddy()
	return him != null and com_world().distance_to(_shoulders(him)) <= num("reach", 300.0)

func _shoulders(him: Buddy) -> Vector2:
	var rect := him.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.36)

## Where it lies once it is round him: under his face at the lowest his breathing takes it, in his
## own frame, so it rides there whatever he does. Laid at `_shoulders` it went straight across his
## eyes — the one thing on the top of him that says "head" — and what showed above it was his
## headphones and the notch of his skull, which the first capture pass read as his head gone
## transparent (D77 amended). Only where it is drawn: the throw still aims at, and wraps at, his
## shoulders. `DRAPE_BELOW_FACE` is half the folded band's height and a pixel of air.
const DRAPE_BELOW_FACE := 13.0

func _drape(him: Buddy) -> Vector2:
	if him.art == null or him.art.face == null:
		var rect := him.get_interaction_rect()
		return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.6)
	return him.to_global(Vector2(0.0, him.art.face_floor_local() + DRAPE_BELOW_FACE))

func _on_press() -> void:
	_phase = FLYING
	_t = 0.0
	throw_hits = 0
	caught = false
	wrapped = false
	wrap_time = 0.0
	came_off = &""
	_throwing = true
	_gravity_was = body.gravity_scale
	_cursor = hand_world()
	body._end_drag()
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	var from := com_world()
	_last_com = from
	var target := _shoulders(him) if him else from
	var want := _toss_at(from, target, num("throw_speed", 650.0))
	body.apply_central_impulse((want - body.linear_velocity) * body.mass)
	var inertia := 1.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	# A towel does not tumble: it floats flat-ish on the way.
	body.apply_torque_impulse(-body.angular_velocity * inertia * 0.8)
	last_throw_speed = want.length()
	run(true)
	sound(&"whoosh", -12.0, 0.7)
	AbilityCues.activation(self, from)
	# Something is coming to him to catch, head or wear: whatever routine he was in stands down.
	notice_player()

## The low arc from `from` through `target` at `speed`, or 45 degrees.
func _toss_at(from: Vector2, target: Vector2, speed: float) -> Vector2:
	var dx := target.x - from.x
	var rise := from.y - target.y
	var side := 1.0 if dx >= 0.0 else -1.0
	var x := absf(dx)
	var g := _gravity * body.gravity_scale
	var need := sqrt(maxf(g * (sqrt(x * x + rise * rise) + rise), 1.0)) * 1.1
	var s := maxf(speed, need)
	var v2 := s * s
	var disc := v2 * v2 - g * (g * x * x + 2.0 * rise * v2)
	var angle := PI * 0.25
	if x > 1.0 and disc >= 0.0 and g > 0.0:
		angle = atan((v2 - sqrt(disc)) / (g * x))
	return Vector2(cos(angle) * side, -sin(angle)) * s

func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	if _phase == FLYING or _phase == WRAPPED:
		_t += delta
	match _phase:
		FLYING:
			var him := buddy()
			var com := com_world()
			if him and throw_hits == 0 and (overlaps_him() or _crossed_him(_last_com, com)
					or com.distance_to(_shoulders(him)) <= 30.0):
				_wrap(him)
				return
			_last_com = com
			var hit_world := false
			for other in body.get_colliding_bodies():
				if not (other is RigidBody2D):
					hit_world = true
			if hit_world or _t >= num("out_seconds", 1.2):
				_let_go()
		WRAPPED:
			_ride()
			wrap_time = _t
			var him := _wrapped
			if not is_instance_valid(him) or him.dragging or him.health == null or him.health.down \
					or ExpressionBrain.KNOCKOUT_STATES.has(him.state):
				_slide_off(&"knocked_off")
				return
			_since_flush += delta
			_banked += num("warm_rate", 3.0) * delta
			if _since_flush >= FriendlyBase.FLUSH_SECONDS:
				_flush(him)
			_next_tell -= delta
			if _next_tell <= 0.0:
				_next_tell = 0.8
				tell(&"swaddled", him.get_interaction_rect().get_center())
			if _t >= num("wrap_seconds", 5.0):
				_slide_off(&"time")
		_:
			super._on_tick(delta)

func _flush(him: Buddy) -> void:
	_since_flush = 0.0
	if _banked <= 0.0 or not is_instance_valid(him):
		return
	give_sustained(_banked, him.get_interaction_rect().get_center())
	_banked = 0.0

## Round his shoulders: frozen, level, a little wider than folded, drawn over him, riding him.
func _wrap(him: Buddy) -> void:
	throw_hits += 1
	wrapped = true
	_wrapped = him
	_phase = WRAPPED
	_t = 0.0
	_next_tell = 0.0
	_banked = 0.0
	_since_flush = 0.0
	var at := _drape(him)
	var xf := Transform2D(0.0, at)
	_wrap_local = him.global_transform.affine_inverse() * xf
	_layer = body.collision_layer
	_mask = body.collision_mask
	_freeze_mode = body.freeze_mode
	body.collision_layer = 0
	body.collision_mask = 0
	body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	_frozen = true
	body.global_transform = xf
	_z = body.z_index
	body.z_index = him.z_index + 2
	var s := sprite()
	if s:
		_sprite_scale = s.scale
		_sprite_pos = s.position
		s.scale = _sprite_scale * Vector2(num("drape", 1.25), 0.85)
	give(num("wrap_value", 3.0), at)
	notice_player()
	# The warmth rising off it is steam, which the wrap's shape draws at his sides for as long as it is
	# on him. It used to be a puff of warm chips from under his face as well, which rose straight up
	# over it (D77's captures).
	var fx := fx()
	if fx:
		fx.burst(at, &"heart", WorldFX.kind_colour(body.juice_tier), 3 + body.juice_tier, 100.0, 0.7)
	_puppet = him.art.body if him.art else null
	if _puppet and not _puppet.frame_changed.is_connected(_breathe):
		_puppet.frame_changed.connect(_breathe)
	_breathe()
	sound(&"impact_soft", -6.0, 0.8)
	tell(&"swaddled", him.get_interaction_rect().get_center())
	AbilityCues.payoff(self, &"swaddle", at, "cosy")
	AbilityCues.state(self, true, at)

func _ride() -> void:
	if is_instance_valid(_wrapped):
		body.global_transform = _wrapped.global_transform * _wrap_local
		_breathe()

## Its picture lifted with his figure (`BuddyArt.figure_lift_local`), from the tick and again the
## moment his frame changes — as his face is placed, so the two never part for a frame. The picture
## and not the body: a frozen kinematic body moved between physics steps is put back where the server
## had it at the next one, so the towel lagged his face by a step at every change of frame.
func _breathe() -> void:
	if not is_instance_valid(_wrapped) or not _frozen:
		return
	var s := sprite()
	if s == null or _sprite_pos == Vector2.INF:
		return
	ride_lift = _wrapped.art.figure_lift_local() if _wrapped.art else 0.0
	var up := _wrapped.global_transform.basis_xform(Vector2(0.0, ride_lift))
	s.position = _sprite_pos + body.global_transform.basis_xform_inv(up)

func _unwrap() -> void:
	if not _frozen or body == null:
		return
	_frozen = false
	if is_instance_valid(_puppet) and _puppet.frame_changed.is_connected(_breathe):
		_puppet.frame_changed.disconnect(_breathe)
	_puppet = null
	if is_instance_valid(_wrapped):
		_flush(_wrapped)
	body.freeze = false
	body.freeze_mode = _freeze_mode
	body.collision_layer = _layer
	body.collision_mask = _mask
	body.z_index = _z
	var s := sprite()
	if s and _sprite_scale != Vector2.INF:
		s.scale = _sprite_scale
	if s and _sprite_pos != Vector2.INF:
		s.position = _sprite_pos
	_sprite_scale = Vector2.INF
	_sprite_pos = Vector2.INF
	ride_lift = 0.0
	_wrapped = null
	AbilityCues.state(self, false, com_world())

## Off him and down to the desk beside him, nudged, not thrown.
func _slide_off(why: StringName) -> void:
	came_off = why
	var him := _wrapped
	_unwrap()
	if is_instance_valid(him) and not body.dragging:
		var side := signf(com_world().x - him.global_position.x)
		if side == 0.0:
			side = 1.0
		body.apply_central_impulse(Vector2(side * 90.0, -40.0) * body.mass)
	sound(&"impact_soft", -12.0, 1.2)
	_throwing = false
	_phase = CLEAR
	_clear_t = 0.0

func on_picked_up() -> void:
	if _active and body.dragging:
		if _phase == WRAPPED:
			_slide_off(&"pulled")
		elif _phase == FLYING:
			_throwing = false
			_phase = CLEAR
			_clear_t = 0.0
	super.on_picked_up()

func _on_stop() -> void:
	_unwrap()
	super._on_stop()
