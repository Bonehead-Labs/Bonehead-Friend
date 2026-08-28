extends Node2D

## Deletes spawned items dropped into it after a short delay.
##
## Only bodies in the "spawned_item" group are ever deleted — a whitelist, so the buddy
## and cursor powers can never be destroyed by accident. The previous version blacklisted
## by duck-typed marker methods, which silently failed for anything that forgot the marker.

const GROUP_SPAWNED := &"spawned_item"

@export var delete_timer: Timer

var _pending: Array[Node2D] = []

func _ready() -> void:
	if delete_timer:
		delete_timer.one_shot = true

func _on_trash_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group(GROUP_SPAWNED):
		return
	if not _pending.has(body):
		_pending.append(body)
	_start_timer()

func _on_trash_area_body_exited(body: Node2D) -> void:
	_pending.erase(body)
	if _pending.is_empty() and delete_timer:
		delete_timer.stop()

func _on_delete_timer_timeout() -> void:
	# Iterate a copy: queue_free() plus erase() on the live array skipped every other item.
	for body in _pending.duplicate():
		if is_instance_valid(body):
			EventBus.item_despawned.emit(body)
			body.queue_free()
	_pending.clear()

func _start_timer() -> void:
	# is_stopped() is the state itself, so this can't get wedged the way the old
	# never-reset `delete_timer_active` flag did.
	if delete_timer and delete_timer.is_stopped():
		delete_timer.start()
