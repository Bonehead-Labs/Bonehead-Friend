class_name WorldBounds
extends Node

## Generates the four walls that keep Bonehead and his toys inside the window.
##
## Replaces the prototype's hand-placed colliders, which were positioned for a fixed
## 1280x720 window and are meaningless once the player resizes the play area or moves to
## a monitor of a different size.

## Wall thickness. Thick on purpose: a thin wall is a tunnelling bug waiting for the first
## time someone swings a mace at full speed.
const WALL_THICKNESS := 256.0

## How far above the window the ceiling sits, so things can be flung up and come back.
const HEADROOM := 400.0

## Keep-inside margin used when the play area shrinks under something.
const CONTAIN_MARGIN := 64.0

var _walls: Array[StaticBody2D] = []
var _last_size := Vector2.ZERO

func _ready() -> void:
	# Drop the hand-placed prototype borders; this node owns the walls now.
	for child in get_children():
		child.queue_free()
	_build_walls()
	rebuild()
	get_viewport().size_changed.connect(rebuild)

func _build_walls() -> void:
	for i in 4:
		var body := StaticBody2D.new()
		# Layer 1 = "world" (named in Project Settings). Collides with buddy and items.
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		body.add_child(shape)
		add_child(body)
		_walls.append(body)

func rebuild() -> void:
	if _walls.size() < 4:
		return
	var size := get_viewport().get_visible_rect().size
	# size_changed can fire without the size actually changing; rebuilding the walls and
	# re-containing every body on each of those is pure waste.
	if size.is_equal_approx(_last_size):
		return
	_last_size = size
	var half := size * 0.5
	var t := WALL_THICKNESS * 0.5

	# floor, ceiling, left, right
	_place(_walls[0], Vector2(half.x, size.y + t), Vector2(size.x + WALL_THICKNESS, WALL_THICKNESS))
	_place(_walls[1], Vector2(half.x, -HEADROOM - t), Vector2(size.x + WALL_THICKNESS, WALL_THICKNESS))
	_place(_walls[2], Vector2(-t, half.y), Vector2(WALL_THICKNESS, size.y + HEADROOM * 2.0))
	_place(_walls[3], Vector2(size.x + t, half.y), Vector2(WALL_THICKNESS, size.y + HEADROOM * 2.0))

	# Anything already outside the new walls would otherwise be stranded — including the
	# buddy, whose authored spawn point sits outside a small play area entirely.
	_contain_escapees(size)

## Pulls interactive bodies back into view after the window changes size or monitor.
## Without this, shrinking the play area silently loses the buddy off-screen and the
## player sees an empty transparent window.
func _contain_escapees(size: Vector2) -> void:
	var inner := Rect2(Vector2.ZERO, size).grow(-CONTAIN_MARGIN)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		inner = Rect2(Vector2.ZERO, size)
	for node in get_tree().get_nodes_in_group(&"interactive"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var body := node as Node2D
		if inner.has_point(body.global_position):
			continue
		body.global_position = body.global_position.clamp(inner.position, inner.end)
		if body is RigidBody2D:
			var rb := body as RigidBody2D
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0

func _place(body: StaticBody2D, at: Vector2, size: Vector2) -> void:
	body.position = at
	var shape := body.get_child(0) as CollisionShape2D
	(shape.shape as RectangleShape2D).size = size
