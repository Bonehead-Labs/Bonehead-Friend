class_name FlareGun
extends HeldGun

## A flare gun (docs/decisions.md D71). Right fires a flare: slow, arcing, burning. If it meets
## him it sticks in him and keeps burning — a small hit every `burn_every` for `burn_time` —
## with sparks coming off him; if it misses it lies on the desk and burns out there.
##
## The one thing in the drawer that keeps hurting him after the shot. Every tick is a real hit
## at the gun's shot multiplier through his own door (`Buddy.take_impulse`, D7), sized over the
## damage floor, so the flare pays by the tick and a second flare stacks on the first.
## One in the chamber: it reloads between shots, which is the fire interval.

@export_group("Flare")
@export var flare_texture: Texture2D
## Seconds a flare burns once it has landed, in him or on the desk.
@export var burn_time: float = 4.0
## Seconds between the ticks of a flare burning in him.
@export var burn_every: float = 0.5
## The impulse each tick hands him. Over the damage floor (350), or it would be decoration.
@export var burn_force: float = 900.0

var _flares: Array[WeakRef] = []

func _shoot(from: Vector2, dir: Vector2) -> void:
	var flare := Flare.new()
	flare.name = "Flare"
	flare.source = item_id
	flare.mult = shot_damage_mult()
	flare.force = shot_force
	flare.shove = shove
	flare.texture = flare_texture
	flare.radius = 3.0
	flare.bounce = 0.25
	flare.friction = 0.8
	flare.lifetime = 3.0
	flare.burn_time = burn_time
	flare.burn_every = burn_every
	flare.burn_force = burn_force
	flare.gravity_scale = projectile_gravity
	flare.z_index = 20
	var host := get_parent() if get_parent() else self
	host.add_child(flare)
	flare.global_position = from
	flare.linear_velocity = dir * projectile_speed
	_flares.append(weakref(flare))
	var fx := WorldFX.of(self)
	if fx:
		fx.shot(from, false, mini(juice_tier, 1))
		fx.puff(from, 4, WorldFX.SOOT, 40.0, 0.7)

## Flares that are still alight, anywhere. For the suite.
func flares_burning() -> int:
	var count := 0
	for ref in _flares:
		var flare := ref.get_ref() as Flare
		if flare and not flare.is_queued_for_deletion():
			count += 1
	return count

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _flares:
		var flare := ref.get_ref() as Node
		if flare and is_instance_valid(flare):
			flare.queue_free()
	_flares.clear()

## One flare. Sticks in him and burns him, or lies on the desk and burns out.
class Flare extends GunProjectile:
	## Two reds, alternated a tick at a time, so a flare flickers without a shader.
	const FLICKER := [Color(1.0, 1.0, 1.0), Color(1.0, 0.72, 0.55)]
	## Sparks off a flare on the desk, this often.
	const SPARK_EVERY := 0.3
	## World px past his outline that a stuck flare's middle sits, so it burns on him, not beside.
	const EMBED := 6.0

	var burn_time := 4.0
	var burn_every := 0.5
	var burn_force := 900.0
	## Ticks it has billed him.
	var ticks := 0
	var _lit := false
	var _next_tick := 0.0
	var _next_spark := 0.0

	func _on_him(him: Buddy, at: Vector2, heading: Vector2) -> void:
		him.apply_central_impulse(heading * force * shove)
		him.take_impulse(force, source, mult, at)
		stick_to(him, at + heading * EMBED)
		_light()
		AudioManager.play(&"impact_soft", 0.05, -6.0, 1.3)

	func _flying(_delta: float, resting: bool) -> void:
		if _lit:
			_spark()
		elif resting:
			_light()

	func _while_stuck(_delta: float) -> void:
		if _age < _next_tick:
			return
		_next_tick += burn_every
		var him := stuck_to() as Buddy
		if him:
			him.take_impulse(burn_force, source, mult, global_position)
			ticks += 1
		var fx := WorldFX.of(self)
		if fx:
			fx.heat(global_position, 0)
		if picture:
			picture.modulate = FLICKER[ticks % 2]

	func _light() -> void:
		if _lit:
			return
		_lit = true
		spent = true
		_next_tick = _age + burn_every
		_next_spark = _age
		# A hair past the last tick, so a flare of four seconds at a tick every half burns eight.
		lifetime = _age + burn_time + 0.05

	func _spark() -> void:
		if _age < _next_spark:
			return
		_next_spark = _age + SPARK_EVERY
		var fx := WorldFX.of(self)
		if fx:
			fx.heat(global_position, 0)
		if picture:
			picture.modulate = FLICKER[int(_age / SPARK_EVERY) % 2]

	func _expire() -> void:
		var fx := WorldFX.of(self)
		if fx and _lit:
			fx.puff(global_position, 3, WorldFX.SOOT, 30.0, 0.6)
		queue_free()
