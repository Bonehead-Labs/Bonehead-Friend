class_name BrushClearAbility
extends ShockwaveAbility

## The machete's Brush Clear (D74, the blades): tap right and the hand makes one wide chest-high
## swipe, and everything in the `cone_degrees` in front of it is thrown away from you — props off
## the desk, and him with them.
##
## The sledgehammer's wave goes down into the desk and comes up under everything around the
## impact. This goes *across*: out of the swipe, level, and only in front — a machete clearing
## the path it is pointed down.
##
## **The swipe is the hand** (`BaseDraggable.hand_offset`): back `wind_px` for `wind_seconds`,
## then across and through toward him in `swipe_seconds`, with a whip of `whip` rad/s on the blade,
## then back in `recover_seconds`. Halfway through the swipe the cone clears: every free body
## within `radius` of where the hand stood when right was pressed — the swipe's own travel would
## carry the apex past him — whose direction from it is inside the cone (flattened to twice its
## height, so the desk in front is in it) is thrown straight away
## from the hand and a little up (`lift_degrees`), by the same velocity whatever it weighs —
## `pop` px/s at the hand, falling to nothing at the rim (`1 - (d / radius)²`, the wave's
## plateau). Held items stay in their hands; the machete is not thrown by its own swipe.
##
## Him, it bills: the impulse it hands him goes through `Buddy.take_impulse` at the machete's
## multiplier times `wave_mult` (D7), from the tick, before `StepStart` (D64); where he lands is the
## machete's for `claim_seconds` (D65). A swipe with nobody in front of it clears whatever is there
## and nothing else.
##
## Row: `wind_px`, `wind_seconds`, `swipe_px`, `swipe_seconds`, `recover_seconds`, `whip`,
## `radius`, `cone_degrees`, `pop`, `lift_degrees`, `wave_mult`, `claim_seconds`.

const WIND := 10
const SWIPE := 11
const BACK := 12

const LEAF := Color("6fae4a")
const LEAF_DARK := Color("3f7a33")

var _facing := Vector2.RIGHT
var _origin := Vector2.ZERO
var _cleared := false
var _back_from := Vector2.ZERO
var _swath: Swath
var _leaves: GPUParticles2D

## For the suites: how many bodies the last swipe threw, and the velocity it gave him.
var last_swept := 0
var last_push := 0.0
var last_origin := Vector2.INF

func _on_press() -> void:
	var him := him_world()
	var hand := hand_world()
	_origin = hand
	_facing = Vector2.RIGHT
	if him != Vector2.INF and absf(him.x - hand.x) > 1.0:
		_facing = Vector2(signf(him.x - hand.x), 0.0)
	_phase = WIND
	_t = 0.0
	_cleared = false
	last_swept = 0
	last_push = 0.0
	last_origin = Vector2.INF
	last_lifted = 0
	last_pop = 0.0
	run(true)
	threaten(true)
	sound(&"whoosh", -12.0, 0.8)

func _on_tick(delta: float) -> void:
	_t += delta
	match _phase:
		WIND:
			var k := clampf(_t / maxf(num("wind_seconds", 0.08), 0.01), 0.0, 1.0)
			_set_offset(Vector2(-_facing.x * num("wind_px", 40.0), -14.0) * sin(k * PI * 0.5))
			if k >= 1.0:
				_phase = SWIPE
				_t = 0.0
				threaten(false)
				whip(swing_sign() * num("whip", 14.0))
				sound(&"swish", -2.0, 1.0, 0.04)
		SWIPE:
			var k := clampf(_t / maxf(num("swipe_seconds", 0.12), 0.01), 0.0, 1.0)
			var from := Vector2(-_facing.x * num("wind_px", 40.0), -14.0)
			var to := Vector2(_facing.x * num("swipe_px", 90.0), 6.0)
			# Out fast and through: the arc of a cut, not a push.
			var e := 1.0 - (1.0 - k) * (1.0 - k)
			_set_offset(from.lerp(to, e) + Vector2(0.0, -18.0 * sin(e * PI)))
			if not _cleared and k >= 0.45:
				_cleared = true
				_clear(_origin)
			if k >= 1.0:
				_phase = BACK
				_t = 0.0
				_back_from = _offset
		BACK:
			var k := clampf(_t / maxf(num("recover_seconds", 0.2), 0.01), 0.0, 1.0)
			_set_offset(_back_from * (1.0 - k * k * (3.0 - 2.0 * k)))
			if k >= 1.0:
				_set_offset(Vector2.ZERO)
				finish()

## The cone, from `origin` along the swipe's facing.
func _clear(origin: Vector2) -> void:
	last_origin = origin
	var radius := num("radius", 230.0)
	var half := deg_to_rad(num("cone_degrees", 120.0)) * 0.5
	var pop := num("pop", 700.0)
	var tilt := deg_to_rad(num("lift_degrees", 20.0))
	var him := buddy()
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	params.shape = circle
	params.transform = Transform2D(0.0, origin)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 2 | 4
	var hit_him := false
	var seen := {}
	for result in body.get_world_2d().direct_space_state.intersect_shape(params, 32):
		var other := result.get("collider") as RigidBody2D
		if other == null or other == body or other.freeze or seen.has(other):
			continue
		seen[other] = true
		if other is BaseDraggable and (other as BaseDraggable).dragging:
			continue
		var centre := other.global_transform * other.center_of_mass
		if other == him:
			centre = him.get_interaction_rect().get_center()
		var offset := centre - origin
		var d := offset.length()
		# In front: inside the cone, or so close to the hand that the blade is already in it. The
		# cone is flattened, twice as tall as its angle says, because a swipe at chest height still
		# clears what is on the desk in front of it — the swathe is wide, not a searchlight.
		var flat := Vector2(offset.x, offset.y * 0.5)
		if d > 24.0 and absf(_facing.angle_to(flat)) > half:
			continue
		var r := clampf(d / radius, 0.0, 1.0)
		var k := 1.0 - r * r
		if k <= 0.0:
			continue
		# Away from the hand, level with the swipe, and a little up so it leaves the desk.
		var away := offset.normalized() if d > 1.0 else _facing
		away = Vector2(away.x, minf(away.y, 0.0) * 0.5)
		if absf(away.x) < 0.2:
			away.x = _facing.x * 0.2
		var dir := away.normalized().rotated(-signf(away.x) * tilt)
		var impulse := other.mass * pop * k
		if other == him:
			hit_him = true
			last_push = pop * k
			strike(impulse, dir, him.get_interaction_rect().get_center(), num("wave_mult", 1.3))
			him.claim_impacts(body.item_id, base_mult(), num("claim_seconds", 1.5))
		else:
			other.apply_central_impulse(dir * impulse)
		last_swept += 1
	last_lifted = last_swept
	last_pop = last_push
	_draw_swath(origin, radius, half)
	var fx := fx()
	if fx:
		fx.puff(origin + _facing * radius * 0.4, 6, WorldFX.DUST, 90.0, 0.5)
		fx.chips(origin + _facing * radius * 0.3, LEAF, 6, 300.0)
		fx.shake(4.0)
	if hit_him:
		tell(&"swept", him.get_interaction_rect().get_center())
		sound(&"impact_metal", -8.0, 1.2)
	else:
		# A swipe with nobody in it pays off in the swathe it cut (D77), not on him.
		fx_at = origin + _facing * radius * 0.45
	paid_off.emit(&"brush_clear")

## The swathe the blade cut: a crescent across the cone, fading, and leaves flying out of it.
func _draw_swath(origin: Vector2, radius: float, half: float) -> void:
	if Settings.focus_intensity == Settings.Intensity.OFF:
		return
	if _swath == null:
		_swath = Swath.new()
		_swath.name = "AbilitySwath"
		_swath.top_level = true
		_swath.z_index = 30
		add_child(_swath)
	_swath.cut(origin, _facing.angle(), half, radius, tier_colour())
	if _leaves == null:
		_leaves = emitter("leaves", &"chip", LEAF, 18, Vector2.ZERO, Vector2(1, 0) * 420.0, 50.0,
			0.7, Vector2(0, 700))
		_leaves.one_shot = true
		_leaves.explosiveness = 0.85
		var mat := _leaves.process_material as ParticleProcessMaterial
		if mat:
			mat.color_ramp = null
			mat.hue_variation_min = -0.05
			mat.hue_variation_max = 0.05
	_leaves.position = body.to_local(origin + _facing * 30.0)
	_leaves.rotation = -body.global_rotation + _facing.angle()
	_leaves.modulate = LEAF if randf() < 0.5 else LEAF_DARK
	_leaves.emitting = true
	_leaves.restart()

func _on_dropped() -> void:
	_set_offset(Vector2.ZERO)
	finish(num("cooldown", 4.0) * 0.5)

## A crescent over the cone, thick at the middle of the cut and gone in a fifth of a second.
class Swath extends Node2D:
	const LIFE := 0.22
	var facing := 0.0
	var half := 1.0
	var radius := 200.0
	var colour := Color.WHITE
	var _age := 0.0

	func cut(at: Vector2, angle: float, half_angle: float, reach: float, tint: Color) -> void:
		global_position = at.round()
		facing = angle
		half = half_angle
		radius = reach
		colour = tint
		_age = 0.0
		visible = true
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			visible = false
			set_process(false)
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / LIFE, 0.0, 1.0)
		var r := radius * lerpf(0.45, 0.8, k)
		var width := lerpf(10.0, 2.0, k)
		var steps := 18
		draw_arc(Vector2.ZERO, r, facing - half, facing + half, steps, colour, width, false)
		draw_arc(Vector2.ZERO, r - width - 3.0, facing - half * 0.7, facing + half * 0.7, steps,
			Color("f2ead8"), maxf(1.0, width * 0.4), false)
