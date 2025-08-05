#TODO Add missle target pointer object to set target and instantiate missle
#TODO Update missle logic to use target pointer target

class_name Missle
extends Node2D

var target: Vector2
@export var speed: float = 100.0
@export var damage: float = 10.0
@export var explosion_area: Area2D
@export var max_force: float = 10000.0
@export var Effects_Player: EffectsPlayer
var is_primed: bool = false
var sprite: Node2D

func _ready():
	if explosion_area:
		explosion_area.monitoring = false

func set_target():
	if Input.is_action_just_pressed("mouse_left"):
		target = get_global_mouse_position()
		look_at(target)

func _process(delta):
	if target != Vector2.ZERO and !is_primed:
		# Move toward target
		var direction = (target - global_position).normalized()
		global_position += direction * speed * delta
		
		# Check if we've reached the target
		if global_position.distance_to(target) < 10.0:  # Small threshold for reaching target
			explode()

func _physics_process(delta):
	pass

func explode() -> void:
	if !explosion_area:
		return
		
	explosion_area.monitoring = true
	
	var cs = explosion_area.get_node_or_null("_explosionAreaShape") as CollisionShape2D
	if cs and cs.shape is CircleShape2D:
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
	
	# Remove sprite and then the missile
	if sprite:
		sprite.queue_free()
	
	await get_tree().create_timer(0.5).timeout
	queue_free()
