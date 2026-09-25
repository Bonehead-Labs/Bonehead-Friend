class_name GunProjectile
extends RigidBody2D

## Something a held gun fires that flies (docs/decisions.md D71): a grenade, a harpoon, a flare,
## a foam dart. Each is an inner class of the gun that fires it, built on this.
##
## The slingshot's pellet rule (D66), made the rule for every one of them: **it collides with the
## world and nothing else, and looks for him along the segment it flew each step**. A fast body
## bouncing off him is exactly the contact the engine can fail to report (D59's F1), and one
## that also hit the desk after him must not count twice — so meeting him is a ray, it happens
## once, and what it does is the subclass's `_on_him`.
##
## It can **stick**: frozen, colliding with nothing, and carried on the body it hit by that
## body's own transform each physics frame. Nothing is reparented, so the node stays where it
## was spawned and goes with the desk, and a gun that is binned frees what it fired (the
## slingshot's rule again, and `item_check`'s teardown asserts nothing is left behind).
##
## Its picture turns to face its flight; the body itself never turns, so a bounce cannot spin
## the collider and the arc the gun solved for (`HeldGun._lob_angle`) is the arc it flies: no
## damping of its own, gravity at the gun's `projectile_gravity`.

const WORLD_LAYER := 1
const BUDDY_LAYER := 2
## Below this speed for `REST_SECONDS`, it has come to rest on the desk.
const REST_SPEED := 30.0
const REST_SECONDS := 0.4

var source: StringName = &""
## The gun's shot multiplier at the moment it fired, augment included, and the impulse it hands
## him — so a hit carries the numbers the gun had, whatever happens to the gun after.
var mult := 1.0
var force := 0.0
var shove := 1.0
var texture: Texture2D
var radius := 3.0
var bounce := 0.3
var friction := 0.6
## Seconds it may live before `_expire`. A subclass lengthens it once it has something to do.
var lifetime := 4.0
## Whether its picture turns to face its flight.
var turns := true
## Whether it has met him. It meets him once.
var spent := false

var picture: Sprite2D

var _age := 0.0
var _last := Vector2.INF
var _still := 0.0
var _stuck_to: Node2D = null
var _stuck_local := Transform2D.IDENTITY

func _ready() -> void:
	collision_layer = 0
	collision_mask = WORLD_LAYER
	lock_rotation = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	var material := PhysicsMaterial.new()
	material.bounce = bounce
	material.friction = friction
	physics_material_override = material
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	picture = Sprite2D.new()
	picture.name = "Sprite"
	picture.texture = texture
	picture.scale = Vector2(2, 2)
	add_child(picture)

func _physics_process(delta: float) -> void:
	_age += delta
	if _stuck_to != null:
		if not is_instance_valid(_stuck_to):
			queue_free()
			return
		global_transform = _stuck_to.global_transform * _stuck_local
		if _age >= lifetime:
			_expire()
			return
		_while_stuck(delta)
		return
	if _age >= lifetime:
		_expire()
		return
	var here := global_position
	if not spent and _last != Vector2.INF:
		_sweep(_last, here)
		if _stuck_to != null or is_queued_for_deletion():
			return
	_last = here
	var speed := linear_velocity.length()
	if turns and picture and speed > REST_SPEED:
		picture.rotation = linear_velocity.angle()
	if speed < REST_SPEED and not freeze:
		_still += delta
	else:
		_still = 0.0
	_flying(delta, _still >= REST_SECONDS)

func _sweep(from: Vector2, to: Vector2) -> void:
	if from.is_equal_approx(to):
		return
	var query := PhysicsRayQueryParameters2D.create(from, to, BUDDY_LAYER)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	var him := hit.get("collider") as Buddy
	if him == null:
		return
	spent = true
	var heading := linear_velocity.normalized() if linear_velocity.length_squared() > 1.0 \
		else (to - from).normalized()
	_on_him(him, hit.get("position", to), heading)

## Stuck to `body` at `at`, facing the way it was flying, until `unstick`.
func stick_to(body: Node2D, at: Vector2) -> void:
	global_position = at
	linear_velocity = Vector2.ZERO
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_mask = 0
	_stuck_to = body
	_stuck_local = body.global_transform.affine_inverse() * global_transform

## Off whatever it was stuck in, falling, with `velocity`.
func unstick(velocity: Vector2 = Vector2.ZERO) -> void:
	_stuck_to = null
	collision_mask = WORLD_LAYER
	freeze = false
	linear_velocity = velocity
	_last = Vector2.INF
	_still = 0.0

func stuck_to() -> Node2D:
	return _stuck_to if is_instance_valid(_stuck_to) else null

# --- the subclass hooks ------------------------------------------------------------------

## It reached him: `at` on his outline, travelling along `heading`.
func _on_him(_him: Buddy, _at: Vector2, _heading: Vector2) -> void:
	pass

## Every physics frame it is free: `resting` once it has lain still on the desk a moment.
func _flying(_delta: float, _resting: bool) -> void:
	pass

## Every physics frame it is stuck.
func _while_stuck(_delta: float) -> void:
	pass

## Its time is up.
func _expire() -> void:
	queue_free()
