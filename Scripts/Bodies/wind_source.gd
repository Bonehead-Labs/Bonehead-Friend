class_name WindSource
extends BaseDraggable

## The desk fan: a constant push in the direction it faces.
##
## It deals no damage and earns nothing on its own. What it does is change every *other*
## item's arc — a thrown grenade curves, a dropped ball rolls, and a swing that used to land
## now misses. That is the only thing in the roster that modifies the physics sandbox
## rather than adding to it, and it is why the fan is worth owning at all.
##
## The force is applied to bodies overlapping a cone-ish Area2D rather than to everything on
## screen, so turning the fan changes who is in the wind — pointing it is the interaction.

## Push per second on a body in the wind, before falloff.
@export var force: float = 900.0

## Local direction the fan blows in, before its own rotation.
@export var blow_direction: Vector2 = Vector2.RIGHT

## The region the wind fills. Assigned by the scene; without it the fan is a paperweight.
@export var wind_area: Area2D

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if wind_area == null:
		return
	var direction := blow_direction.normalized().rotated(rotation)
	for body in wind_area.get_overlapping_bodies():
		var rigid := body as RigidBody2D
		if rigid == null or rigid == self or rigid.freeze:
			continue
		# Falls off along the throw, so a body at the grille is shoved and one at the far
		# edge is nudged. Measured along the blow direction rather than by straight-line
		# distance: a body beside the fan is not downwind of it.
		var along := (rigid.global_position - global_position).dot(direction)
		if along <= 0.0:
			continue
		var reach := _reach()
		var falloff := clampf(1.0 - along / maxf(reach, 1.0), 0.0, 1.0)
		rigid.apply_central_force(direction * force * falloff * delta * 60.0)

## How far the wind carries, taken from the area's own shape so the number and the picture
## cannot disagree. Looked up by shape rather than by node name — a scene rebuilt from
## script renames its children, and a name is not a contract (see `ExplosionUtil`).
func _reach() -> float:
	for child in wind_area.get_children():
		var cs := child as CollisionShape2D
		if cs == null:
			continue
		if cs.shape is RectangleShape2D:
			return (cs.shape as RectangleShape2D).size.x * absf(cs.global_scale.x)
		if cs.shape is CircleShape2D:
			return (cs.shape as CircleShape2D).radius * 2.0 * absf(cs.global_scale.x)
	return 200.0
