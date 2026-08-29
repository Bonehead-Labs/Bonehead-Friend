class_name ExplosionUtil
extends RefCounted

## Radial impulse with quadratic falloff, shared by throwables, missiles and cursor powers.
## Every caller used to carry its own byte-identical copy of this loop.

## The blast's real reach, in world units.
##
## **The scale factor is load-bearing.** get_overlapping_bodies() reports whatever the
## SCALED area covers, so computing falloff against the raw shape radius means every body
## past that raw radius is picked up by the blast and then handed an impulse of exactly
## zero — a blast that visibly reaches something and does nothing to it. The prototype's
## missile had a root scale of 3 and a 166 px shape, so two thirds of its visible blast
## was inert.
static func blast_radius(shape_radius: float, scale: float) -> float:
	return maxf(0.0, shape_radius) * maxf(0.001, absf(scale))

## Impulse at `distance` from the centre. Squared falloff: near-misses still hurt, distant
## bodies barely twitch.
static func blast_strength(distance: float, radius: float, max_force: float) -> float:
	if radius <= 0.0:
		return 0.0
	var falloff := 1.0 - clampf(distance / radius, 0.0, 1.0)
	return max_force * falloff * falloff

## Pushes every rigid body inside `area` away from `origin`.
##
## Returns one `{"body": RigidBody2D, "impulse": float}` per affected body. The impulse
## magnitude is returned rather than discarded because damage is measured on the receiver
## (docs/decisions.md D7): the blast hands Bonehead the same kind of number the contact
## solver would, and he decides what it costs him.
static func apply_blast(area: Area2D, origin: Vector2, max_force: float, shape_node: String = "_explosionAreaShape") -> Array[Dictionary]:
	var affected: Array[Dictionary] = []
	var cs := area.get_node_or_null(shape_node) as CollisionShape2D
	if cs == null or not (cs.shape is CircleShape2D):
		push_warning("ExplosionUtil: %s has no circular %s" % [area.name, shape_node])
		return affected

	var radius := blast_radius((cs.shape as CircleShape2D).radius, cs.global_scale.x)
	if radius <= 0.0:
		return affected

	for body in area.get_overlapping_bodies():
		if not (body is RigidBody2D):
			continue
		var to_body: Vector2 = body.global_position - origin
		var strength := blast_strength(to_body.length(), radius, max_force)
		# A body exactly at the origin has no direction to be pushed in; nudge it up.
		var dir := to_body.normalized() if to_body.length() > 0.01 else Vector2.UP
		body.apply_impulse(dir * strength, Vector2.ZERO)
		affected.append({"body": body, "impulse": strength})
	return affected

## The same blast without an authored Area2D: a shape query against the physics space.
##
## Cursor powers fire from wherever the mouse is, and an Area2D that has to be moved to
## the cursor costs a _process every frame whether or not anyone is shooting — a real
## cost in a game budgeted at 3% CPU while idle. The query shape is built per shot rather
## than cached in a `static var`: shots are click-driven, so there is nothing to optimise,
## and a static that holds a Resource keeps this script alive past engine shutdown, which
## shows up as a leak and masks the real ones.
static func point_blast(space: PhysicsDirectSpaceState2D, origin: Vector2, radius: float, max_force: float, max_results: int = 16) -> Array[Dictionary]:
	var affected: Array[Dictionary] = []
	if space == null or radius <= 0.0:
		return affected

	var query_shape := CircleShape2D.new()
	query_shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = query_shape
	params.transform = Transform2D(0.0, origin)
	params.collide_with_bodies = true
	params.collide_with_areas = false

	for result in space.intersect_shape(params, max_results):
		var body = result.get("collider")
		if not (body is RigidBody2D):
			continue
		var to_body: Vector2 = body.global_position - origin
		var strength := blast_strength(to_body.length(), radius, max_force)
		var dir := to_body.normalized() if to_body.length() > 0.01 else Vector2.UP
		body.apply_impulse(dir * strength, Vector2.ZERO)
		affected.append({"body": body, "impulse": strength})
	return affected
