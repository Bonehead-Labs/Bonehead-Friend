class_name Missile
extends Node2D

## The projectile MissilePower calls in: flies to a fixed point and detonates there.
##
## Kinematic rather than a rigid body on purpose — the fantasy is a guided strike landing
## exactly where you clicked, and a physics projectile would arrive somewhere near it.
## The detonation still goes through the receiver-side path (docs/decisions.md D7): it
## applies a real blast impulse and hands Bonehead that impulse, so a missile hit is
## measured by the same code as a bat swing.
##
## Spelled "Missile". The prototype spelled it "Missle" in the filename, the class name
## and a user-facing label.

## How long the spent missile lingers before freeing itself, so the explosion particles
## it spawned are not cut off mid-burst.
const CLEANUP_DELAY := 0.5

@export var speed: float = 900.0
@export var explosion_area: Area2D
@export var Effects_Player: EffectsPlayer
@export var flame_effect: CPUParticles2D
@export var sprite: AnimatedSprite2D

var target: Vector2
var max_force: float = 14000.0

var _source_id: StringName = &"missile"
var _damage_mult: float = 1.0
var _flying: bool = false
var _spent: bool = false

func _ready() -> void:
	if explosion_area:
		# Live for the whole (very short) flight rather than switched on at impact. An
		# Area2D only knows its overlaps after it has been through a physics step, so
		# enabling it at detonation means waiting a frame before the blast can see
		# anything — and a frame is long enough for the target to have moved.
		explosion_area.monitoring = true

## Called by the power immediately after spawning. Everything the missile needs to
## attribute its damage is passed in, so the projectile never reaches for the cursor,
## the player's augments or any autoload state of its own.
## Milliseconds between puffs of the trail.
const TRAIL_EVERY_MSEC := 45
var _trail_msec := 0

func launch(at: Vector2, source_id: StringName, damage_mult: float, force: float) -> void:
	target = at
	_source_id = source_id
	_damage_mult = damage_mult
	max_force = force
	_flying = true
	rotation = (target - global_position).angle() + PI / 2.0

func _process(delta: float) -> void:
	if not _flying or _spent:
		return
	var to_target := target - global_position
	# Don't overshoot between frames: at 900 px/s a frame is 15 px, which is enough to
	# sail past the target and orbit it.
	var step := speed * delta
	if to_target.length() <= maxf(step, 5.0):
		global_position = target
		explode()
		return
	global_position += to_target.normalized() * step
	# A smoke trail, one puff every few frames: a missile with no trail is a sprite sliding.
	_trail_msec += int(delta * 1000.0)
	if _trail_msec >= TRAIL_EVERY_MSEC:
		_trail_msec = 0
		var fx := WorldFX.of(self)
		if fx:
			fx.puff(global_position, 2, WorldFX.SOOT, 30.0, 0.45)

func explode() -> void:
	if _spent:
		return
	_spent = true
	_flying = false

	if explosion_area:
		for hit in ExplosionUtil.apply_blast(explosion_area, global_position, max_force):
			var body: Node = hit["body"]
			if body is Buddy:
				(body as Buddy).take_impulse(float(hit["impulse"]), _source_id, _damage_mult, global_position)
		explosion_area.monitoring = false

	if Effects_Player:
		Effects_Player.explosion_effect(global_position, 1.0 + 0.25 * Progression.juice_tier(_source_id))
	if sprite:
		sprite.visible = false
	if flame_effect:
		flame_effect.emitting = false

	# Bound, not awaited: a Callable bound to the node is dropped when the node dies, where a
	# coroutine resumed on a freed instance errors before its guard runs.
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)
