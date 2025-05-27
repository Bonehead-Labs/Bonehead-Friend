class_name Character extends BaseDraggable

@export var health: HealthComponent
@export var hurtbox: HitBoxComponent
var can_take_damage: bool = true
var initial_position: Vector2

func Character() -> void:
	pass

func _process(delta: float) -> void:
	# Failsafe if chaaracter falls off the map
	var current_pos = global_position
	if current_pos.y < -2000:
		global_position = Vector2(500,500)
		linear_velocity = Vector2.ZERO

func _ready() -> void:
	super._ready()
	call_deferred("connect_health_signals")
	initial_position = global_position
	
func connect_health_signals():
	if health:
		health.EntityKilled.connect(destroy_entity)
		health.EntityDamaged.connect(entity_damaged)
		health.EntityHealed.connect(entity_healed)
		print("Signals connected successfully!")

func destroy_entity():
	reset_character()

	
func DELETE():
	rotate(240)
	hurtbox.queue_free()
	set_process(false)
	await get_tree().create_timer(0.5).timeout
	queue_free()
	
func reset_character():
	_end_drag()
	health.Health = health.Max_Health
	linear_velocity = Vector2.ZERO
	set_physics_process(false)
	await get_tree().create_timer(0.5).timeout
	global_position = initial_position
	linear_velocity = Vector2.ZERO
	global_rotation = 0
	await get_tree().create_timer(0.5).timeout
	set_physics_process(true)  # Resume physics
		
	
func entity_damaged():
	pass
	# if Effects_Player:
	#     Effects_Player.hit_effect()
	#     if SoundPlayer:
	#         SoundPlayer.hit_effect()

func entity_healed():
	pass
