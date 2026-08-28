class_name Character extends BaseDraggable

## Bonehead. Kept as a single rigid body by design (docs/decisions.md D4) — the uplift
## is animation, not simulated dismemberment.

const GROUP_BUDDY := &"buddy"

## How far outside the world he can get before being rescued.
const OUT_OF_BOUNDS_MARGIN := 3000.0

@export var health: HealthComponent
@export var hurtbox: HitBoxComponent

var can_take_damage: bool = true
var initial_position: Vector2

func _ready() -> void:
	super._ready()
	add_to_group(GROUP_BUDDY)
	initial_position = global_position
	call_deferred("connect_health_signals")

func _process(_delta: float) -> void:
	# Failsafe if he escapes the world. The old check only tested y < -2000, which is
	# *upward* in Godot's 2D space — the one direction gravity guarantees he won't go.
	if global_position.length() > OUT_OF_BOUNDS_MARGIN:
		_return_home()

func connect_health_signals() -> void:
	if health == null:
		push_warning("Character: no HealthComponent assigned")
		return
	health.EntityKilled.connect(destroy_entity)
	health.EntityDamaged.connect(entity_damaged)
	health.EntityHealed.connect(entity_healed)

func destroy_entity() -> void:
	reset_character()

func reset_character() -> void:
	_end_drag()
	health.Health = health.Max_Health
	freeze = true
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(self):
		return
	_return_home()
	freeze = false

func _return_home() -> void:
	global_position = initial_position
	global_rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

func entity_damaged() -> void:
	if Effects_Player:
		Effects_Player.hit_effect()

func entity_healed() -> void:
	if Effects_Player:
		Effects_Player.heal_effect()
