class_name Character extends BaseDraggable

@export var health: HealthComponent
@export var hurtbox: HitBoxComponent
var can_take_damage: bool = true

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
	
func connect_health_signals():
	if health:
		health.EntityKilled.connect(destroy_entity)
		health.EntityDamaged.connect(entity_damaged)
		health.EntityHealed.connect(entity_healed)
		print("Signals connected successfully!")

func destroy_entity():
	# if SoundPlayer:
	#     SoundPlayer.death_effect()
	rotate(240)
	hurtbox.queue_free()
	# if DamageZone:
	#     DamageZone.queue_free()
	set_process(false)
	await get_tree().create_timer(0.5).timeout
	queue_free()
	
func entity_damaged():
	pass
	# if Effects_Player:
	#     Effects_Player.hit_effect()
	#     if SoundPlayer:
	#         SoundPlayer.hit_effect()

func entity_healed():
	pass
