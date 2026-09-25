class_name DartBlaster
extends HeldGun

## A foam dart blaster (docs/decisions.md D71). The kind side's third gun: right fires a foam
## dart with a suction cup, and a dart that meets him **sticks to him** and stays there, a
## little orange flag, until it drops off on its own. Each one that sticks is a kind act: he is
## being played with, not shot. A dart that misses bounces off the desk and lies there.
##
## Kind in the D56 sense: never a threat, never a hit, no Bones whatever it is thrown at him
## with (`HeldGun.is_kind_gun`). Six in the blaster, then a reload.

@export_group("Dart")
@export var dart_texture: Texture2D
## The kindness one dart sticking to him is worth, before the value node.
@export var dart_value: float = 1.0
## Seconds a dart stays on him before it drops off.
@export var stick_seconds: float = 6.0

var _darts: Array[WeakRef] = []

func _shoot(from: Vector2, dir: Vector2) -> void:
	var dart := Dart.new()
	dart.name = "Dart"
	dart.source = item_id
	dart.value = dart_value * value_multiplier()
	dart.force = shot_force
	dart.shove = shove
	dart.texture = dart_texture
	dart.radius = 2.5
	dart.bounce = 0.45
	dart.friction = 0.9
	dart.lifetime = 3.0
	dart.stick_seconds = stick_seconds
	dart.gravity_scale = projectile_gravity
	dart.z_index = 20
	var host := get_parent() if get_parent() else self
	host.add_child(dart)
	dart.global_position = from
	dart.linear_velocity = dir * projectile_speed
	dart.picture.rotation = dir.angle()
	_darts.append(weakref(dart))

## Darts stuck to him right now. For the suite.
func darts_on_him() -> int:
	var count := 0
	for ref in _darts:
		var dart := ref.get_ref() as Dart
		if dart and not dart.is_queued_for_deletion() and dart.stuck_to() is Buddy:
			count += 1
	return count

func darts_alive() -> int:
	var count := 0
	for ref in _darts:
		var dart := ref.get_ref() as Dart
		if dart and not dart.is_queued_for_deletion():
			count += 1
	return count

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _darts:
		var dart := ref.get_ref() as Node
		if dart and is_instance_valid(dart):
			dart.queue_free()
	_darts.clear()

## One foam dart. Sticks to him and is a kind act, or bounces and lies on the desk.
class Dart extends GunProjectile:
	## World px past his outline that a stuck dart's middle sits.
	const EMBED := 8.0

	var value := 1.0
	var stick_seconds := 6.0
	var _drop_at := 0.0

	func _on_him(him: Buddy, at: Vector2, heading: Vector2) -> void:
		# Foam: a nudge, never a hit. The act is the dart arriving, not the push.
		him.apply_central_impulse(heading * force * shove)
		# Tip in, tail out: stuck across his outline, so the dart shows against his bone.
		stick_to(him, at + heading * EMBED)
		_drop_at = _age + stick_seconds
		lifetime = INF
		EventBus.kindness_given.emit(source, value, at)
		AudioManager.play(&"plink", 0.08, -8.0, 1.2)

	func _while_stuck(_delta: float) -> void:
		if _age < _drop_at:
			return
		# Drops off him, and lies on the desk a moment before it goes.
		unstick(Vector2(randf_range(-40.0, 40.0), -60.0))
		lifetime = _age + 2.0

	func _flying(_delta: float, resting: bool) -> void:
		if resting:
			lifetime = minf(lifetime, _age + 1.0)
