class_name ThrowableBase
extends BaseDraggable

## Grenades and dynamite: prime with right-click while dragging, explode after a delay.
##
## The blast applies a real impulse to everything in range and reports that impulse to
## Bonehead through the same receiver-side path a bat swing uses, so explosives need no
## damage model of their own.

@export var damage_mult: float = 1.0
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
	if sprite:
		# Simple readable tell that it is live; the fuse animation lands with the art pass.
		var tween := create_tween().set_loops()
		tween.tween_property(sprite, "modulate", Color(1.6, 0.6, 0.6), throwable_delay * 0.25)
		tween.tween_property(sprite, "modulate", Color.WHITE, throwable_delay * 0.25)
	await get_tree().create_timer(throwable_delay).timeout
	# The player can bin a primed grenade before it goes off.
	if is_instance_valid(self):
		explode()

func explode() -> void:
	if explosion_area:
		for hit in ExplosionUtil.apply_blast(explosion_area, global_position, max_force):
			var body: Node = hit["body"]
			if body is Buddy:
				(body as Buddy).take_impulse(float(hit["impulse"]), item_id,
					effective_damage_mult(), global_position)
		explosion_area.monitoring = false
	if Effects_Player:
		Effects_Player.explosion_effect(global_position)
	if sprite:
		sprite.visible = false
	EventBus.item_despawned.emit(self)
	await get_tree().create_timer(0.5).timeout
	queue_free()

func effective_damage_mult() -> float:
	if item_id == &"":
		return damage_mult
	return damage_mult * Progression.get_modifier(item_id, &"damage_mult")
