class_name Missle
extends Node2D

## Kinematic missile that flies to a point and detonates.
## Renamed to Missile and given real damage attribution in M2.

var target: Vector2
var has_target: bool = false
var has_exploded: bool = false

@export var speed: float = 900.0
@export var explosion_area: Area2D
@export var max_force: float = 10000.0
@export var Effects_Player: EffectsPlayer
@export var flame_effect: CPUParticles2D
@export var sprite: AnimatedSprite2D

func _ready() -> void:
	if explosion_area:
		explosion_area.monitoring = true

func set_target() -> void:
	target = get_global_mouse_position()
	has_target = true
	rotation = (target - global_position).normalized().angle() + deg_to_rad(90)

func _process(delta: float) -> void:
	if not has_target or has_exploded:
		return
	var to_target := target - global_position
	# Don't overshoot past the target between frames at high speed.
	var step := speed * delta
	if to_target.length() <= maxf(step, 5.0):
		global_position = target
		explode()
		return
	global_position += to_target.normalized() * step

func explode() -> void:
	if has_exploded:
		return
	has_exploded = true

	if explosion_area:
		ExplosionUtil.apply_blast(explosion_area, global_position, max_force)
		explosion_area.monitoring = false
	if Effects_Player:
		Effects_Player.explosion_effect(global_position)
	if sprite:
		sprite.visible = false
	if flame_effect:
		flame_effect.emitting = false

	await get_tree().create_timer(0.5).timeout
	queue_free()
