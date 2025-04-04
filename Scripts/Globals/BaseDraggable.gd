class_name BaseDraggable extends RigidBody2D


@export var Health: HealthComponent
@export var mouse_collider: Area2D
@export var Effects_Player: EffectsPlayer
@export var SoundPlayer: SoundPlayer
@export var force_multiplier: float = 1000.0
@export var sprite: AnimatedSprite2D
@export var collision_shape: CollisionShape2D
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start dragging if the mouse is hovering over the Area2D.
			if mouse_collider.is_hovered:
				dragging = true
				drag_offset = to_local(get_global_mouse_position())
		else:
			dragging = false

func _physics_process(delta: float) -> void:
	if dragging:
		var target_pos: Vector2 = get_global_mouse_position()
		var displacement: Vector2 = target_pos - global_position
		# Apply a force proportional to the displacement.
		var damping_force: Vector2 = -linear_velocity * 50.0
		apply_force(displacement * force_multiplier + damping_force, drag_offset)



func connect_health_signals():
	if Health:
		Health.EntityKilled.connect(destroy_entity)
		Health.EntityDamaged.connect(entity_damaged)
		Health.EntityHealed.connect(entity_healed)
		print("Signals connected successfully!")

func destroy_entity():
	await get_tree().create_timer(0.5).timeout
	queue_free()
	
func entity_damaged():
	if Effects_Player:
		Effects_Player.hit_effect()
		if SoundPlayer:
			SoundPlayer.hit_effect()
	
func entity_healed():
	pass
