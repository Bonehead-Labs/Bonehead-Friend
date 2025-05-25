class_name Throwable
extends BaseDraggable

@export var throwable_delay: float = 4.5


func _input(event: InputEvent) -> void:
    super._input(event)
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        prime_explosion()


func prime_explosion() -> void:
    Effects_Player.explosion_countdown()
    await get_tree().create_timer(throwable_delay).timeout
    explode()


func explode() -> void:
    Effects_Player.explosion_effect()
    # Here you can add logic to deal damage to nearby entities, etc.
    # For example, you might want to check for entities within a certain radius
    # and apply damage to them.
    queue_free()  # Remove the throwable from the scene after explosion