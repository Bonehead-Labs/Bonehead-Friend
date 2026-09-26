class_name SnapAbility
extends ProjectileAbility

## The boxcutter's Snap (D74, the blades): tap right and it goes click-click-click — `shots`
## blade tips snapped off and flicked at him `shot_gap` seconds apart, **dead straight**, no arc,
## each one aimed at him afresh as it leaves.
##
## The golf club tees up and lofts one ball on an arc you charge. This is three, at once, flat,
## and the knife stays in your hand: a snap-off blade's whole reason to exist, turned into a burst.
##
## **Each tip bills itself, once** (the golf ball's rule, D66's pellet): it collides with the
## world and nothing else, flies with no gravity at `tip_speed`, and sweeps the segment it flew
## each step for him. On him it hands over `tip_force` through `Buddy.take_impulse` at the
## boxcutter's multiplier times `tip_mult`, shoves him by `shove` of it, and drops — gravity back
## on, a clink on the desk, gone. A tip that meets nothing falls when it has flown `range`.
## The knife kicks back a little with each snap (`recoil`), and the slider clicks before each one.
## For the burst it turns its blade on him (`BladeAim`, D56's aim), after a `first_delay` beat to
## bring it round, so the tips visibly leave the point they were snapped from.
##
## Row: `shots`, `shot_gap`, `first_delay`, `tip_speed`, `tip_force`, `tip_mult`, `shove`, `range`,
## `recoil`, `aim_frequency`, `aim_accel`.

const STEEL := Color("c9d3dc")
const STEEL_DARK := Color("26221d")

var _left := 0
var _next := 0.0
var _gravity_ := 980.0

## For the suites: tips flicked this use, tips that hit him, and the last one's impulse.
var flicked := 0
var tips_hit := 0

func _ready() -> void:
	super._ready()
	_gravity_ = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func pip_fill() -> float:
	return -1.0

func _on_press() -> void:
	_left = int(num("shots", 3.0))
	# A beat to bring the blade round to him, while the slider clicks out.
	_next = num("first_delay", 0.1)
	sound(&"ratchet", -12.0, 1.2, 0.0)
	flicked = 0
	tips_hit = 0
	last_strike = 0.0
	last_speed = num("tip_speed", 1400.0)
	last_power = 1.0
	run(true)

func _on_release(_seconds: float) -> void:
	pass

func _on_tick(delta: float) -> void:
	var him := him_world()
	if him != Vector2.INF:
		BladeAim.hold(self, him - grip_world(), num("aim_frequency", 22.0), 0.8, num("aim_accel", 420.0),
			_gravity_)
	_next -= delta
	if _next <= 0.0 and _left > 0:
		_flick()
		_left -= 1
		_next = num("shot_gap", 0.12)
		if _left == 0:
			finish()

## One tip: the slider clicks, the tip snaps, and it goes straight at him.
func _flick() -> void:
	flicked += 1
	var from := tip_world()
	var target := him_world()
	var dir := (target - from).normalized() if target != Vector2.INF and target.distance_to(from) > 1.0 \
		else (from - grip_world()).normalized()
	if dir.length_squared() < 0.5:
		dir = Vector2.RIGHT
	var shard := Shard.new()
	shard.name = "BladeTip"
	shard.ability = weakref(self)
	shard.source = body.item_id
	shard.force = num("tip_force", 1500.0)
	shard.mult = base_mult() * num("tip_mult", 1.0)
	shard.shove = num("shove", 0.4)
	shard.reach = num("range", 700.0)
	var host := body.get_parent() if body.get_parent() else body
	host.add_child(shard)
	shard.global_position = from + dir * 6.0
	shard.linear_velocity = dir * num("tip_speed", 1400.0)
	shard.rotation = dir.angle()
	_balls.append(weakref(shard))
	# The knife kicks back off the snap.
	body.apply_central_impulse(-dir * body.mass * num("recoil", 60.0))
	var fx := fx()
	if fx:
		fx.chips(from, WorldFX.SPARK, 3, 180.0)
		fx.ring(from, 10.0, Color.WHITE, 0.08, 1.0)
	sound(&"ratchet", -10.0, 1.5, 0.0)
	sound(&"snap", -4.0, 0.95 + 0.07 * float(flicked), 0.03)

func _tip_struck(impulse: float) -> void:
	tips_hit += 1
	last_strike = impulse
	struck.append(impulse)
	if struck.size() > 32:
		struck.pop_front()
	billed.append(num("tip_mult", 1.0))
	if billed.size() > 16:
		billed.pop_front()
	payoffs += 1
	if tips_hit == 1:
		paid_off.emit(&"snap")
	# Each tip in him counted on the badge over him (D77).
	show_state(&"snapped")

func _on_dropped() -> void:
	# Tips already in the air keep flying; the rest are not snapped.
	_left = 0
	finish()

func _on_stop() -> void:
	_left = 0

## One snapped tip: a sliver of steel, point first, straight. World collision only; it looks for
## him along the segment it flew each step and bills him once, then falls.
class Shard extends RigidBody2D:
	const LIFETIME := 2.0

	var ability: WeakRef
	var source: StringName = &""
	var force := 1500.0
	var mult := 1.0
	var shove := 0.4
	var reach := 700.0
	var spent := false
	var _flown := 0.0
	var _age := 0.0
	var _last := Vector2.INF
	var _trail: Line2D

	func _ready() -> void:
		collision_layer = 0
		collision_mask = WeaponAbility.WORLD_LAYER
		mass = 0.02
		gravity_scale = 0.0
		continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		var material := PhysicsMaterial.new()
		material.bounce = 0.3
		material.friction = 0.8
		physics_material_override = material
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var box := RectangleShape2D.new()
		box.size = Vector2(12, 4)
		shape.shape = box
		add_child(shape)
		var picture := Sliver.new()
		picture.name = "Picture"
		add_child(picture)
		_trail = Line2D.new()
		_trail.name = "Trail"
		_trail.top_level = true
		_trail.show_behind_parent = true
		_trail.antialiased = false
		_trail.width = 3.0
		_trail.default_color = Color.WHITE
		add_child(_trail)

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		var here := global_position
		if _last != Vector2.INF:
			_flown += here.distance_to(_last)
			if not spent:
				_sweep(_last, here)
		_last = here
		if not spent and _flown >= reach:
			spent = true
			gravity_scale = 1.0
		if _trail:
			if not spent and Settings.focus_intensity != Settings.Intensity.OFF:
				_trail.add_point(global_position.round())
				while _trail.get_point_count() > 4:
					_trail.remove_point(0)
			elif _trail.get_point_count() > 0:
				_trail.remove_point(0)

	func _sweep(from: Vector2, to: Vector2) -> void:
		if from.is_equal_approx(to):
			return
		var query := PhysicsRayQueryParameters2D.create(from, to, WeaponAbility.BUDDY_LAYER)
		query.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		var him := hit.get("collider") as Buddy
		if him == null:
			return
		spent = true
		var at: Vector2 = hit.get("position", to)
		var heading := linear_velocity.normalized()
		him.apply_central_impulse(heading * force * shove)
		him.take_impulse(force, source, mult, at)
		var fx := WorldFX.of(self)
		if fx:
			fx.chips(at, Color.WHITE, 3, 200.0)
			fx.ring(at, 16.0, Color.WHITE, 0.12, 2.0)
		var owner_ability := ability.get_ref() as SnapAbility if ability else null
		if owner_ability:
			owner_ability._tip_struck(force)
		# Off him, spent: it drops.
		global_position = at - heading * 4.0
		linear_velocity = Vector2(-heading.x * 90.0, -120.0)
		angular_velocity = randf_range(-20.0, 20.0)
		gravity_scale = 1.0

## Twelve pixels of steel with a dark edge and a bright one, pointed at the front: a snapped-off
## segment, at the size a blade tip is beside him (six were a speck).
class Sliver extends Node2D:
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(-7, -3), Vector2(4, -3), Vector2(8, 0),
			Vector2(4, 3), Vector2(-7, 3)]), STEEL_DARK)
		draw_colored_polygon(PackedVector2Array([Vector2(-6, -2), Vector2(4, -2), Vector2(6, 0),
			Vector2(4, 2), Vector2(-6, 2)]), STEEL)
		draw_rect(Rect2(-6, -2, 10, 1), Color.WHITE)
