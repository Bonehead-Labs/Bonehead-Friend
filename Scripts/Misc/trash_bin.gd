extends Node2D
@onready var overlapping_bodies = []
@export var delete_timer: Timer
var delete_timer_active: bool = false


func _on_trash_area_body_entered(body:Node2D) -> void:
	if not (body.has_method("Character") or body.has_method("fist")):
		overlapping_bodies.append(body)


func _on_trash_area_body_exited(body:Node2D) -> void:
	overlapping_bodies.erase(body)

func _process(delta: float) -> void:
	if overlapping_bodies.size() > 0:
		start_timer()


func delete_bodies() -> void:
	for body in overlapping_bodies:
		body.queue_free()
		overlapping_bodies.erase(body)

func start_timer() -> void:
	if not delete_timer_active:
		delete_timer_active = true
		delete_timer.start()


func _on_delete_timer_timeout() -> void:
	delete_bodies()
