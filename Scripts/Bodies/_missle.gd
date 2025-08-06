#TODO Add missle target pointer object to set target and instantiate missle
#TODO Update missle logic to use target pointer target

class_name Missle
extends Node2D

var target: Vector2
@export var speed: float = 900.0
@export var damage: float = 10.0
@export var explosion_area: Area2D
@export var max_force: float = 10000.0
@export var Effects_Player: EffectsPlayer
@export var flame_effect: CPUParticles2D
var is_primed: bool = false
@export var sprite: AnimatedSprite2D
var has_exploded: bool = false

func _ready():
	if explosion_area:
		explosion_area.monitoring = true

func set_target():
	target = get_global_mouse_position()
	var direction = (target - global_position).normalized()
	rotation = direction.angle() + deg_to_rad(90)
	print("Missle Target Set")

func _process(delta):
	if target and !has_exploded:
		var direction = (target - global_position).normalized()
		global_position += direction * speed * delta
		if global_position.distance_to(target) < 5.0:  # Small threshold for reaching target
			explode()
			
		

func explode() -> void:
	if has_exploded:
		return

	has_exploded = true

	var cs = explosion_area.get_node("_explosionAreaShape") as CollisionShape2D
	var radius = (cs.shape as CircleShape2D).radius

	for body in explosion_area.get_overlapping_bodies():
		print("Body found", body)
		if body is RigidBody2D:
			var dir = body.global_position - global_position
			var dist = dir.length()
			var falloff = 1.0 - clamp(dist / radius, 0.0, 1.0)
			var strength = max_force * falloff * falloff
			body.apply_impulse(dir.normalized() * strength, Vector2.ZERO)
			print("dist:", dist, " radius:", radius, " strength:", strength)

	explosion_area.monitoring = false
	Effects_Player.explosion_effect(global_position)
	sprite.visible = false
	flame_effect.emitting = false
	await get_tree().create_timer(0.5).timeout # test timer
	queue_free()
