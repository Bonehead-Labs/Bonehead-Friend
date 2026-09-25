class_name AbilityShot
extends RigidBody2D

## One small thing an ability throws at him (D74): a morning star's spike, a staple, a keycap, a
## splash of coffee. The golf ball's rules (D66's pellet), shared so four abilities do not each
## grow a copy of them.
##
## **It bills itself, once.** It collides with the world and nothing else, and sweeps the segment
## it flew each step for him on his layer, so a fast shot cannot pass through him unbilled and one
## that bounces off the desk afterwards cannot count twice. On him it tells the ability that fired
## it (`shot_hit`), which hands him `force` through `Buddy.take_impulse` at the
## weapon's multiplier times `mult` — from this `_physics_process`, before `Buddy.StepStart` (D64).
##
## What it does after is `after_hit` and `after_world`: `drop` (it falls away), `stick` (it stays
## where it hit, then fades), `splat` (it is gone, with a mark), or `home` (it flies back to
## `home_node` at `home_local` and tells the ability it is back — a keycap clacking back on).
## Drawn, not a sprite, per `look`; a six-pixel speck nobody can follow is not a shot (D74's ball).

const DROP := &"drop"
const STICK := &"stick"
const SPLAT := &"splat"
const HOME := &"home"

const SPIKE := &"spike"
const STAPLE := &"staple"
const KEYCAP := &"keycap"
const COFFEE := &"coffee"

const STEEL := Color("c9ced8")
const IRON := Color("2a2e38")
const IRON_EDGE := Color("6b7280")
const KEY_TOP := Color("f2d06b")
const KEY_BODY := Color("a9713f")
const COFFEE_DARK := Color("4a2a14")
const COFFEE_LIGHT := Color("8a5a2b")
const OUTLINE := Color("141210")

var ability: WeakRef
var look: StringName = SPIKE
var force := 600.0
var mult := 1.0
var shove := 0.4
var lifetime := 2.5
var after_hit: StringName = DROP
var after_world: StringName = DROP
## For `home`: where it goes back to, in `home_node`'s own frame.
var home_node: Node2D
var home_local := Vector2.ZERO
var home_speed := 1100.0
var home_after := 0.6
## Which slot this is, for whoever fired it: a keycap's key, a spike's spike.
var slot := 0

var spent := false
var landed := false
var homing := false
var _age := 0.0
var _since_land := 0.0
var _last := Vector2.INF
var _heading := Vector2.RIGHT
var _stuck_at := -1.0
var _trail: Line2D

func _ready() -> void:
	collision_layer = 0
	collision_mask = WeaponAbility.WORLD_LAYER
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	contact_monitor = true
	max_contacts_reported = 2
	lock_rotation = look != KEYCAP
	var material := PhysicsMaterial.new()
	material.bounce = 0.35 if look == KEYCAP else 0.1
	material.friction = 0.8
	physics_material_override = material
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = 5.0 if look == KEYCAP or look == COFFEE else 3.0
	shape.shape = circle
	add_child(shape)
	z_index = 31
	if look != KEYCAP:
		_trail = Line2D.new()
		_trail.name = "Trail"
		_trail.top_level = true
		_trail.show_behind_parent = true
		_trail.antialiased = false
		_trail.width = 4.0 if look == COFFEE else 3.0
		_trail.default_color = COFFEE_LIGHT if look == COFFEE else STEEL
		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 0.1))
		taper.add_point(Vector2(1.0, 1.0))
		_trail.width_curve = taper
		add_child(_trail)

func _owner() -> WeaponAbility:
	return ability.get_ref() as WeaponAbility if ability else null

## Tells the ability that fired it, if it listens: `shot_hit(shot, him, at, heading)`,
## `shot_landed(shot, at)`, `shot_home(shot)`. Asked by name, so `WeaponAbility` needs no stub.
func _tell(method: StringName, args: Array) -> void:
	var fired := _owner()
	if fired and fired.has_method(method):
		fired.callv(method, [self] + args)

func _physics_process(delta: float) -> void:
	if BaseDraggable.physics_frozen:
		return
	_age += delta
	if homing:
		_home(delta)
		return
	if _stuck_at >= 0.0:
		_stuck_at += delta
		modulate.a = clampf(1.0 - (_stuck_at - 0.6) / 0.4, 0.0, 1.0)
		if _stuck_at >= 1.0:
			queue_free()
		return
	if _age >= lifetime:
		if after_hit == HOME or after_world == HOME:
			_start_home()
		else:
			queue_free()
		return
	var here := global_position
	if linear_velocity.length_squared() > 4.0:
		_heading = linear_velocity.normalized()
	if not spent and _last != Vector2.INF:
		_sweep(_last, here)
	_last = here
	_trail_step()
	if landed:
		_since_land += delta
		if after_world == HOME and _since_land >= home_after:
			_start_home()
		return
	if not get_colliding_bodies().is_empty():
		_hit_world()
	queue_redraw()

func _trail_step() -> void:
	if _trail == null:
		return
	if not landed and linear_velocity.length() > 250.0 and Settings.focus_intensity != Settings.Intensity.OFF:
		_trail.add_point(global_position.round())
		while _trail.get_point_count() > 5:
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
	_tell(&"shot_hit", [him, at, _heading])
	match after_hit:
		STICK:
			_stick(at)
		SPLAT:
			queue_free()
		HOME:
			global_position = at - _heading * 6.0
			linear_velocity = Vector2(-_heading.x * 180.0, -260.0)
			landed = true
			_since_land = 0.0
		_:
			# Off him, most of its speed spent.
			global_position = at - _heading * 6.0
			linear_velocity = -_heading * linear_velocity.length() * 0.2 + Vector2(0, -60)

func _hit_world() -> void:
	_tell(&"shot_landed", [global_position])
	match after_world:
		STICK:
			_stick(global_position)
		SPLAT:
			queue_free()
		HOME:
			landed = true
			_since_land = 0.0
		_:
			landed = true

## Stays where it hit — in the desk, or in him, riding along with him — and fades.
func _stick(at: Vector2) -> void:
	_stuck_at = 0.0
	global_position = at
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	set_deferred(&"freeze", true)
	set_deferred(&"collision_mask", 0)
	if _trail:
		_trail.clear_points()
	queue_redraw()

func _start_home() -> void:
	if not is_instance_valid(home_node):
		queue_free()
		return
	homing = true
	set_deferred(&"collision_mask", 0)
	gravity_scale = 0.0
	if _trail:
		_trail.clear_points()

## Home to its slot: a steering impulse toward the velocity that would take it there, never a
## write to its velocity (D54), fast enough that eight of them are back inside half a second. The
## steering is stiff on purpose: a soft one put the last three caps in orbit round their keys.
func _home(delta: float) -> void:
	if not is_instance_valid(home_node):
		queue_free()
		return
	var target := home_node.to_global(home_local)
	var to := target - global_position
	var distance := to.length()
	if distance <= 12.0 or _age >= lifetime + 1.5:
		_tell(&"shot_home", [])
		queue_free()
		return
	var speed := home_speed * clampf(distance / 80.0, 0.4, 1.0)
	var want := to / maxf(distance, 0.001) * speed
	apply_central_impulse((want - linear_velocity).limit_length(24000.0 * delta) * mass)
	angular_velocity = lerpf(angular_velocity, 0.0, 0.2) if absf(angular_velocity) > 30.0 else angular_velocity
	queue_redraw()

func _draw() -> void:
	match look:
		SPIKE:
			# A cone of iron, point first: seven by five art pixels at 2x, dark with a steel edge.
			draw_set_transform(Vector2.ZERO, _heading.angle())
			draw_colored_polygon(PackedVector2Array([Vector2(8, 0), Vector2(-6, -5), Vector2(-6, 5)]), OUTLINE)
			draw_colored_polygon(PackedVector2Array([Vector2(6, 0), Vector2(-4, -3), Vector2(-4, 3)]), IRON)
			draw_rect(Rect2(-4, -3, 6, 2), IRON_EDGE)
		STAPLE:
			# A staple, legs back: a bright bracket eight pixels across, on a dark rim so it reads
			# against the desk and against him.
			draw_set_transform(Vector2.ZERO, _heading.angle())
			draw_rect(Rect2(-5, -5, 8, 10), OUTLINE)
			draw_rect(Rect2(0, -4, 2, 8), STEEL)
			draw_rect(Rect2(-4, -4, 4, 2), STEEL)
			draw_rect(Rect2(-4, 2, 4, 2), STEEL)
		KEYCAP:
			# A cap: five art pixels square, the lit top row and the brown skirt under it.
			draw_rect(Rect2(-5, -5, 10, 10), OUTLINE)
			draw_rect(Rect2(-4, -4, 8, 8), KEY_BODY)
			draw_rect(Rect2(-4, -4, 8, 3), KEY_TOP)
		COFFEE:
			draw_circle(Vector2.ZERO, 6.0, COFFEE_DARK)
			draw_circle(Vector2(-1, -1), 4.0, COFFEE_LIGHT)
			draw_rect(Rect2(-7, -2, 3, 3), COFFEE_DARK)
			draw_rect(Rect2(4, 1, 3, 3), COFFEE_DARK)
