class_name Throwable
extends BaseDraggable

@export var throwable_delay: float = 3
@export var explosion_area: Area2D
@export var max_force: float = 10000.0
var is_primed: bool = false

func _ready() -> void:
	super._ready()
	explosion_area.monitoring = false

func _input(event: InputEvent) -> void:
	super._input(event)
	if !is_primed:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and dragging:
			prime_explosion()


func prime_explosion() -> void:
	explosion_area.monitoring = true
	is_primed = true
	#Effects_Player.explosion_countdown()
	await get_tree().create_timer(throwable_delay).timeout
	explode()


func explode() -> void:
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
	# 4) Turn off detection and remove self
			print("dist:", dist, " radius:", radius, " strength:", strength)
	explosion_area.monitoring = false
	Effects_Player.explosion_effect()
	sprite.queue_free()
	await get_tree().create_timer(0.5).timeout # test timer
	queue_free()  # Remove the throwable from the scene after explosion
