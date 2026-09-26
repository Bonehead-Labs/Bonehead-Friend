class_name ShockwaveAbility
extends WeaponAbility

## Slam it into the desk and the desk throws everything up (D74): the sledgehammer's Ground Pound.
##
## Right while holding it: the hand lifts `raise_px` for `raise_seconds`, then **drives down** —
## the handle plunged toward the desk under the head (`BaseDraggable.hand_offset`, the katana's
## mechanism turned on its end) in `plunge_seconds`, never further than `reach` — with a kick of
## `slam_speed` on the head, and comes back up in `recover_seconds`. The drag joint does the
## carrying, so the hammer lands with its own weight, head first, the way it hangs from the hand.
##
## The first tick the head is on the world — touching it, or within a few pixels of it straight
## down — the desk **jumps**: every free body within `radius` of the impact is thrown up and a
## little outward (`lift_degrees` off vertical) by the same velocity whatever it weighs — a wave
## through the desk lifts a pencil and a skeleton alike — at `pop` px/s at the impact, holding most
## of it near the impact and falling to nothing at the rim (`1 - (d / radius)²`).
##
## Him, it bills: the impulse it hands him (his mass times that velocity) goes through
## `Buddy.take_impulse` at the hammer's multiplier times `wave_mult`, the blast's path (D7), from
## the tick, before `StepStart` (D64); and where he comes down is the hammer's for
## `claim_seconds` (D65). Held items stay in their hands; the hammer is not thrown by its own wave.
## A plunge that meets no desk has slammed the air: a puff, and half a cooldown.
##
## Only the world starts a wave. A head that lands on him on the way down is an ordinary hit,
## billed as one; the wave is what happens when it reaches the desk.
##
## Row: `raise_px`, `raise_seconds`, `plunge_seconds`, `recover_seconds`, `reach`, `slam_speed`,
## `radius`, `pop`, `lift_degrees`, `wave_mult`, `claim_seconds`.

const RAISE := 0
const PLUNGE := 1
const RECOVER := 2
const FLOOR_PROBE := 18.0

var _phase := RAISE
var _t := 0.0
var _depth := 0.0
var _offset := Vector2.ZERO
var _waved := false
var _ring_again := -1.0
var _impact := Vector2.ZERO
var _recover_from := 0.0

## For the suites: where the last wave was, what it handed him and how many bodies it lifted.
var last_impact := Vector2.INF
var last_pop := 0.0
var last_lifted := 0

func _on_press() -> void:
	_phase = RAISE
	_t = 0.0
	_waved = false
	_ring_again = -1.0
	last_impact = Vector2.INF
	last_pop = 0.0
	last_lifted = 0
	# How far the hand has to go for the head to meet the desk: the gap under the head, and a
	# little more so the joint drives it in.
	var head := com_world()
	var below := _probe(head, 480.0)
	var gap := (below.y - head.y) - _head_reach() if below != Vector2.INF else num("reach", 220.0)
	_depth = clampf(gap + 16.0 + num("raise_px", 50.0), 0.0, num("reach", 220.0) + num("raise_px", 50.0))
	run(true)
	threaten(true)
	sound(&"whoosh", -10.0, 0.55)

func _on_tick(delta: float) -> void:
	_t += delta
	if _ring_again >= 0.0:
		_ring_again -= delta
		if _ring_again < 0.0:
			var fx := fx()
			if fx:
				fx.ring(_impact, num("radius", 240.0) * 1.25, WorldFX.DUST, 0.5, 2.0)
	match _phase:
		RAISE:
			var k := clampf(_t / maxf(num("raise_seconds", 0.1), 0.01), 0.0, 1.0)
			_set_offset(Vector2(0.0, -num("raise_px", 50.0) * sin(k * PI * 0.5)))
			if k >= 1.0:
				_phase = PLUNGE
				_t = 0.0
				threaten(false)
				body.apply_central_impulse(Vector2.DOWN * body.mass * num("slam_speed", 500.0))
				sound(&"whoosh", -4.0, 0.7)
		PLUNGE:
			var k := clampf(_t / maxf(num("plunge_seconds", 0.09), 0.01), 0.0, 1.0)
			# Accelerating into the desk.
			_set_offset(Vector2(0.0, -num("raise_px", 50.0) + _depth * k * k))
			if _check_floor():
				return
			if k >= 1.0:
				_phase = RECOVER
				_recover_from = _offset.y
				_t = 0.0
		RECOVER:
			var k := clampf(_t / maxf(num("recover_seconds", 0.25), 0.01), 0.0, 1.0)
			_set_offset(Vector2(0.0, _recover_from * (1.0 - k * k * (3.0 - 2.0 * k))))
			if not _waved and _check_floor():
				return
			if k >= 1.0:
				_set_offset(Vector2.ZERO)
				if _waved:
					finish()
				else:
					var fx := fx()
					if fx:
						fx.puff(com_world(), 5, WorldFX.DUST, 50.0, 0.5)
					finish(num("cooldown", 5.0) * 0.5)

func _check_floor() -> bool:
	if _waved or _t <= 0.0:
		return false
	var hit := _floor_under_head()
	if hit == Vector2.INF:
		return false
	_waved = true
	_wave(hit)
	_phase = RECOVER
	_recover_from = _offset.y
	_t = 0.0
	return true

## The world under the head: a contact with anything that is not a free body, or the desk within a
## few pixels straight down. INF for neither.
func _floor_under_head() -> Vector2:
	var head := com_world()
	for other in body.get_colliding_bodies():
		if not (other is RigidBody2D) and other is PhysicsBody2D:
			var under := _probe(head, 90.0)
			if under != Vector2.INF:
				return under
	return _probe(head, FLOOR_PROBE + _head_reach())

func _probe(from: Vector2, length: float) -> Vector2:
	if not body.is_inside_tree():
		return Vector2.INF
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2.DOWN * length, WORLD_LAYER,
		[body.get_rid()])
	query.hit_from_inside = true
	var hit := body.get_world_2d().direct_space_state.intersect_ray(query)
	return hit.get("position", Vector2.INF)

## How far below its centre of mass the head reaches: the half-diagonal of the shape nearest it.
func _head_reach() -> float:
	var head := com_world()
	var lowest := 0.0
	for child in body.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		var rect := cs.shape.get_rect()
		var centre := cs.global_transform * rect.get_center()
		if centre.distance_to(head) > 40.0:
			continue
		lowest = maxf(lowest, centre.y + (rect.size * cs.global_transform.get_scale().abs()).length() * 0.5 - head.y)
	return clampf(lowest, 0.0, 60.0)

func _set_offset(offset: Vector2) -> void:
	var delta := offset - _offset
	_offset = offset
	body.hand_offset = offset
	if body.dragging and body.handle:
		body.handle.global_position += delta

func _on_dropped() -> void:
	_set_offset(Vector2.ZERO)
	finish(num("cooldown", 5.0) * 0.5)

func _on_stop() -> void:
	_offset = Vector2.ZERO
	if body:
		body.hand_offset = Vector2.ZERO

func _wave(at: Vector2) -> void:
	_impact = at
	last_impact = at
	var radius := num("radius", 240.0)
	var pop := num("pop", 900.0)
	var tilt := deg_to_rad(num("lift_degrees", 25.0))
	var him := buddy()
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	params.shape = circle
	params.transform = Transform2D(0.0, at)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 2 | 4
	var hit_him := false
	for result in body.get_world_2d().direct_space_state.intersect_shape(params, 24):
		var other := result.get("collider") as RigidBody2D
		if other == null or other == body or other.freeze:
			continue
		if other is BaseDraggable and (other as BaseDraggable).dragging:
			continue
		var offset := other.global_position - at
		# A plateau, not a cone: a wave through the desk loses little near the impact and dies at
		# the rim. Linear, it lifted him 45 px from a slam beside him.
		var r := clampf(offset.length() / radius, 0.0, 1.0)
		var k := 1.0 - r * r
		if k <= 0.0:
			continue
		var side := signf(offset.x) if absf(offset.x) > 2.0 else 0.0
		var dir := Vector2(sin(tilt) * side, -cos(tilt)).normalized()
		var impulse := other.mass * pop * k
		if other == him:
			hit_him = true
			last_pop = pop * k
			strike(impulse, dir, him.get_interaction_rect().get_center(), num("wave_mult", 1.0))
			him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 1.5))
		else:
			other.apply_central_impulse(dir * impulse)
		last_lifted += 1
	var shaped := AbilityLooks.pay_spec(look(), &"ground_pound").has("shape")
	var fx := fx()
	if fx:
		# With a look of its own (`Shapes/ground_pound.gd`) the desk cracks and throws up its own
		# chunks and dust; the rings are the generic wave.
		if not shaped:
			fx.ring(at, radius, Color("f2ead8"), 0.4, 5.0)
			fx.chips(at, WorldFX.DUST, 10, 360.0)
		fx.puff(at, 12, WorldFX.DUST, 140.0, 0.8)
		fx.shake(8.0)
	sound(&"quake", 0.0, 1.0, 0.04)
	sound(&"impact_metal", -6.0, 0.55)
	if hit_him:
		tell(&"quaked", at)
	# The payoff is the wave, where the head met the desk (D77), not where it threw him.
	fx_at = at
	paid_off.emit(&"ground_pound")
	# A second, wider ring a moment later: the wave going out through the desk.
	_ring_again = -1.0 if shaped else 0.1
