class_name ProjectileAbility
extends WeaponAbility

## The weapon launches something at him (D74): the golf club's Drive.
##
## Hold right and a ball is teed up on the club's face; the power fills over `charge_seconds` and
## a dotted arc shows where it will go. The arc is aimed for you — the low arc through his middle
## at the speed the power gives (`min_speed` to `max_speed`) — but not rescued: at a speed too low
## to reach him the solution does not exist, and the ball is lofted at 45 degrees and falls short,
## which the dots show before you let go. Letting go drives it: a crack, a whip of the club through
## the ball, and the ball flies.
##
## **The ball bills itself, once,** the way the slingshot's pellet does (D66): it collides with the
## world and nothing else and sweeps the segment it flew each step for him, so a fast ball cannot
## pass through him unbilled and a ball that bounces off the desk afterwards cannot count twice.
## On him it hands over `ball_force` scaled by the power (0.4 at none, 1.0 at full) through
## `Buddy.take_impulse` at the club's multiplier times `ball_mult`, and shoves him by `shove` of it.
## Then it bounces away and is gone after a few seconds, or when it comes to rest.
##
## Row: `charge_seconds`, `min_speed`, `max_speed`, `ball_force`, `ball_mult`, `shove`, `whip`.

const DOTS := 16
const DOT_SECONDS := 0.05
const BALL_WHITE := Color("f4f1e6")

var _power := 0.0
var _ball_at := Vector2.ZERO
var _tee: Tee
var _dots: Dots
var _balls: Array[WeakRef] = []
var _gravity := 980.0
var _next_click := 0.0

## For the suites: the last drive's speed and power, and the impulse it handed him.
var last_speed := 0.0
var last_power := 0.0
var last_strike := 0.0

func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func _can_start() -> bool:
	return buddy() != null

func power() -> float:
	return _power if _active else 0.0

func pip_fill() -> float:
	return _power if _active else -1.0

func balls_in_flight() -> int:
	var n := 0
	for ref in _balls:
		if ref.get_ref() != null:
			n += 1
	return n

func preview_points() -> PackedVector2Array:
	return _dots.points if _dots else PackedVector2Array()

func _on_press() -> void:
	_power = 0.0
	_next_click = 0.0
	run(true)
	threaten(true)
	if _tee == null:
		_tee = Tee.new()
		_tee.name = "AbilityTee"
		_tee.top_level = true
		_tee.z_index = 31
		add_child(_tee)
		_dots = Dots.new()
		_dots.name = "AbilityArc"
		_dots.top_level = true
		_dots.z_index = 30
		add_child(_dots)
	_tee.visible = true
	_dots.visible = true
	sound(&"tock", -14.0, 1.4)
	_update_ball()
	_update_pip()

func _on_tick(delta: float) -> void:
	_power = minf(1.0, _power + delta / maxf(num("charge_seconds", 0.8), 0.05))
	_next_click -= delta
	if _next_click <= 0.0 and _power < 1.0:
		sound(&"ratchet", -16.0, 0.8 + 0.8 * _power, 0.0)
		_next_click = 0.12
	_update_ball()

func _on_release(_seconds: float) -> void:
	_drive()

func _on_dropped() -> void:
	# No hand, no swing: the ball rolls off the tee.
	finish(num("cooldown", 3.0) * 0.5)

func _on_stop() -> void:
	if _tee:
		_tee.visible = false
	if _dots:
		_dots.visible = false
		_dots.points = PackedVector2Array()
		_dots.queue_redraw()

func _exit_tree() -> void:
	super._exit_tree()
	# The balls are the world's, not the club's — but a binned club takes its balls with it.
	for ref in _balls:
		var ball := ref.get_ref() as Node
		if ball and is_instance_valid(ball):
			ball.queue_free()
	_balls.clear()

## The ball sits on the face of the club: the tip, a little toward the hand.
func _update_ball() -> void:
	var tip := tip_world()
	_ball_at = tip.lerp(grip_world(), 0.06)
	if _tee:
		_tee.global_position = _ball_at.round()
	if _dots:
		var points := PackedVector2Array()
		var v := launch_velocity(_ball_at, _speed())
		for i in range(1, DOTS + 1):
			var t := DOT_SECONDS * float(i)
			points.append(_ball_at + v * t + Vector2(0.0, _gravity) * (0.5 * t * t))
		_dots.points = points
		_dots.queue_redraw()

func _speed() -> float:
	return lerpf(num("min_speed", 520.0), num("max_speed", 1300.0), _power)

## The low arc from `from` through his middle at `speed`, or 45 degrees toward him when that speed
## cannot reach him. Public for the suite, which checks the dots and the ball agree.
func launch_velocity(from: Vector2, speed: float) -> Vector2:
	var target := him_world()
	if target == Vector2.INF:
		return Vector2.RIGHT * speed
	var dx := target.x - from.x
	var rise := from.y - target.y
	var side := 1.0 if dx >= 0.0 else -1.0
	var x := absf(dx)
	var g := _gravity
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * rise * v2)
	var angle := PI * 0.25
	if x > 1.0 and disc >= 0.0:
		# The lower of the two solutions: a drive, not a chip.
		angle = atan((v2 - sqrt(disc)) / (g * x))
	return Vector2(cos(angle) * side, -sin(angle)) * speed

func _drive() -> void:
	var speed := _speed()
	var v := launch_velocity(_ball_at, speed)
	last_speed = speed
	last_power = _power
	var ball := Ball.new()
	ball.name = "GolfBall"
	ball.ability = weakref(self)
	ball.source = body.item_id
	ball.force = num("ball_force", 2200.0) * lerpf(0.4, 1.0, _power)
	ball.mult = base_mult() * num("ball_mult", 1.0)
	ball.shove = num("shove", 0.5)
	var host := body.get_parent() if body.get_parent() else body
	host.add_child(ball)
	ball.global_position = _ball_at
	ball.linear_velocity = v
	_balls.append(weakref(ball))
	# The club goes through the ball.
	whip(signf(v.x) * num("whip", 10.0) * (0.5 + 0.5 * _power))
	var fx := fx()
	if fx:
		fx.chips(_ball_at, Color.WHITE, 4, 200.0)
		fx.ring(_ball_at, 20.0, Color.WHITE, 0.15, 2.0)
	sound(&"tock", -2.0, lerpf(1.1, 0.9, _power))
	sound(&"whoosh", -10.0, 1.4)
	tell(&"fore", him_world())
	finish()

func _ball_struck(impulse: float) -> void:
	last_strike = impulse
	struck.append(impulse)
	billed.append(num("ball_mult", 1.0))
	payoffs += 1
	paid_off.emit(&"drive")

## The ball: ten pixels across — five art pixels, the scale a golf ball is beside him — white with a
## dark rim and one dimple of shade, drawn rather than a sprite. The six-pixel first version was a
## speck nobody could follow across the desk.
class Tee extends Node2D:
	const RIM := Color("26221d")
	const SHADE := Color("c9c4b4")

	func _draw() -> void:
		draw_rect(Rect2(-3, -6, 6, 12), RIM)
		draw_rect(Rect2(-6, -3, 12, 6), RIM)
		draw_rect(Rect2(-5, -5, 10, 10), RIM)
		draw_rect(Rect2(-2, -5, 4, 10), BALL_WHITE)
		draw_rect(Rect2(-5, -2, 10, 4), BALL_WHITE)
		draw_rect(Rect2(-4, -4, 8, 8), BALL_WHITE)
		draw_rect(Rect2(1, 1, 3, 3), SHADE)

## The arc, as two-pixel dots on a black square so it reads at 1x — the slingshot's look.
class Dots extends Node2D:
	var points := PackedVector2Array()

	func _draw() -> void:
		for p in points:
			var at := to_local(p).round()
			draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), Color.BLACK)
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), BALL_WHITE)

## One golf ball. World collision only; it looks for him along the segment it flew each step and
## bills him once (the slingshot pellet's rule, D66).
class Ball extends RigidBody2D:
	const LIFETIME := 3.0
	const REST_SECONDS := 0.5
	const RADIUS := 5.0
	const TRAIL := 6

	var ability: WeakRef
	var source: StringName = &""
	var force := 2000.0
	var mult := 1.0
	var shove := 0.5
	var spent := false
	var _age := 0.0
	var _still := 0.0
	var _last := Vector2.INF
	var _trail: Line2D

	func _ready() -> void:
		collision_layer = 0
		collision_mask = WeaponAbility.WORLD_LAYER
		mass = 0.05
		continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		var material := PhysicsMaterial.new()
		material.bounce = 0.55
		material.friction = 0.6
		physics_material_override = material
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = RADIUS
		shape.shape = circle
		add_child(shape)
		var picture := Tee.new()
		picture.name = "Picture"
		add_child(picture)
		# A short white streak behind it while it is fast, so the flight reads as a drive.
		_trail = Line2D.new()
		_trail.name = "Trail"
		_trail.top_level = true
		_trail.show_behind_parent = true
		_trail.antialiased = false
		_trail.width = 5.0
		_trail.default_color = BALL_WHITE
		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 0.15))
		taper.add_point(Vector2(1.0, 1.0))
		_trail.width_curve = taper
		add_child(_trail)

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		var here := global_position
		if not spent and _last != Vector2.INF:
			_sweep(_last, here)
		_last = here
		if _trail:
			if linear_velocity.length() > 300.0 and Settings.focus_intensity != Settings.Intensity.OFF:
				_trail.add_point(global_position.round())
				while _trail.get_point_count() > TRAIL:
					_trail.remove_point(0)
			elif _trail.get_point_count() > 0:
				_trail.remove_point(0)
		if linear_velocity.length() < 25.0:
			_still += delta
			if _still >= REST_SECONDS:
				queue_free()
		else:
			_still = 0.0

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
			fx.ring(at, 40.0, Color.WHITE, 0.2, 3.0)
			fx.burst(at, &"star", WorldFX.GOLD, 3, 220.0)
		AudioManager.play(&"tock", 0.05, -4.0, 0.8)
		var owner_ability := ability.get_ref() as ProjectileAbility if ability else null
		if owner_ability:
			owner_ability._ball_struck(force)
		# Off him, most of its speed spent.
		global_position = at - heading * RADIUS
		linear_velocity = -heading * linear_velocity.length() * 0.3
