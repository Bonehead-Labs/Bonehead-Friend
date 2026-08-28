class_name ExplosionUtil
extends RefCounted

## Radial impulse with quadratic falloff, shared by throwables and missiles.
## Both used to carry their own byte-identical copy of this loop.

## Pushes every rigid body inside `area` away from `origin`.
## Returns the bodies actually affected, so callers can attribute damage later.
static func apply_blast(area: Area2D, origin: Vector2, max_force: float, shape_node: String = "_explosionAreaShape") -> Array[RigidBody2D]:
	var affected: Array[RigidBody2D] = []
	var cs := area.get_node_or_null(shape_node) as CollisionShape2D
	if cs == null or not (cs.shape is CircleShape2D):
		push_warning("ExplosionUtil: %s has no circular %s" % [area.name, shape_node])
		return affected

	var radius: float = (cs.shape as CircleShape2D).radius
	if radius <= 0.0:
		return affected

	for body in area.get_overlapping_bodies():
		if not (body is RigidBody2D):
			continue
		var to_body: Vector2 = body.global_position - origin
		var falloff := 1.0 - clampf(to_body.length() / radius, 0.0, 1.0)
		# Squared falloff: near-misses still hurt, distant bodies barely twitch.
		var strength := max_force * falloff * falloff
		# A body exactly at the origin has no direction to be pushed in; nudge it up.
		var dir := to_body.normalized() if to_body.length() > 0.01 else Vector2.UP
		body.apply_impulse(dir * strength, Vector2.ZERO)
		affected.append(body)
	return affected
