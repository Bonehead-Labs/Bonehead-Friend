class_name ExplosionUtil
extends RefCounted

## Radial impulse with quadratic falloff, shared by throwables, missiles and cursor powers.
## Every caller used to carry its own byte-identical copy of this loop.
##
## **Both blasts push through the centre of mass** (D54). They used to call
## `apply_impulse(dir * strength, Vector2.ZERO)`, and that second argument is an offset from
## the body **origin** — not "no offset". The buddy's centre of mass is authored at (0, 10),
## so every sideways blast in the game was also applying a torque of ten times the impulse.
## Measured on the shipped buddy: a 10,000 sideways impulse spun him at 16 rad/s, two and a
## half turns a second, at exactly the same linear speed `apply_central_impulse` gives with
## 0.00 spin. That was most of the "weird sudden movement" — the same one-word mistake was in
## `npc_base.gd` twice as well, so a goose peck and a gorilla slam did it too.

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
static func apply_blast(area: Area2D, origin: Vector2, max_force: float, shape_node: String = "") -> Array[Dictionary]:
	var affected: Array[Dictionary] = []
	var cs := _circle_in(area, shape_node)
	if cs == null:
		push_error("ExplosionUtil: %s has no circular collision shape, so its blast does "
			% area.name + "nothing at all")
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
		body.apply_central_impulse(dir * strength)
		affected.append({"body": body, "impulse": strength})
	return affected

## The blast's shape, found by *looking for it* rather than by name.
##
## This used to require a child called `_explosionAreaShape` — the name the prototype's
## hand-authored scenes happened to use. When those scenes were rebuilt from script the
## shape came out called `CollisionShape2D`, the lookup returned null, and every explosion
## in the game silently applied no force whatsoever for the price of one `push_warning`
## nobody was reading. A node name is not a contract; a circular shape under the blast area
## is.
static func _circle_in(area: Area2D, preferred: String) -> CollisionShape2D:
	if preferred != "":
		var named := area.get_node_or_null(preferred) as CollisionShape2D
		if named and named.shape is CircleShape2D:
			return named
	for child in area.get_children():
		var cs := child as CollisionShape2D
		if cs and cs.shape is CircleShape2D:
			return cs
	return null

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
		body.apply_central_impulse(dir * strength)
		affected.append({"body": body, "impulse": strength})
	return affected
