class_name Throwable
extends BaseDraggable

## Grenades, dynamite: prime with right-click while dragging, explode after a delay.

@export var throwable_delay: float = 3.0
@export var explosion_area: Area2D
@export var max_force: float = 10000.0

var is_primed: bool = false

func _ready() -> void:
	super._ready()
	if explosion_area:
		explosion_area.monitoring = false

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if is_primed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and dragging:
		prime_explosion()

func prime_explosion() -> void:
	if is_primed:
		return
	is_primed = true
	if explosion_area:
		explosion_area.monitoring = true
	await get_tree().create_timer(throwable_delay).timeout
	# The player can bin a primed grenade before it goes off.
	if is_instance_valid(self):
		explode()

func explode() -> void:
	if explosion_area:
		ExplosionUtil.apply_blast(explosion_area, global_position, max_force)
		explosion_area.monitoring = false
	if Effects_Player:
		Effects_Player.explosion_effect(global_position)
	if sprite:
		sprite.visible = false
	EventBus.item_despawned.emit(self)
	await get_tree().create_timer(0.5).timeout
	queue_free()
