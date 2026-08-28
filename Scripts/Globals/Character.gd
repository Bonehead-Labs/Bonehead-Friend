class_name Character extends BaseDraggable

## Bonehead. Kept as a single rigid body by design (docs/decisions.md D4) — the uplift
## is animation, not simulated dismemberment.

const GROUP_BUDDY := &"buddy"

## How far outside the visible area he may get before being rescued.
const OUT_OF_BOUNDS_MARGIN := 1200.0

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
	# Failsafe if he escapes the world. Measured against the actual viewport, because the
	# window is resizable — a fixed distance is meaningless when the play area can be
	# anything from 320x240 to an ultrawide. The old check tested y < -2000, which is
	# *upward*: the one direction gravity guarantees he will not go.
	var bounds := get_viewport().get_visible_rect().grow(OUT_OF_BOUNDS_MARGIN)
	if not bounds.has_point(global_position):
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

## Somewhere sensible inside the current window, which is not necessarily where the scene
## authored him — that position assumes a 1280x720 window.
func _home_position() -> Vector2:
	var rect := get_viewport().get_visible_rect()
	var inset := rect.grow(-96.0)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		inset = rect
	return initial_position.clamp(inset.position, inset.end)

func _return_home() -> void:
	global_position = _home_position()
	global_rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

func entity_damaged() -> void:
	if Effects_Player:
		Effects_Player.hit_effect()

func entity_healed() -> void:
	if Effects_Player:
		Effects_Player.heal_effect()
