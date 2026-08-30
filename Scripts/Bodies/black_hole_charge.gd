class_name BlackHoleCharge
extends ThrowableBase

## The charge that runs backwards first. When the fuse ends it does not go off — it spends
## `pull_seconds` dragging everything inside its own blast radius into a heap on top of
## itself, and then goes off into the crowd it gathered.
##
## It is the only explosive whose value is not in the throw. A grenade rewards putting the
## blast where he is; this brings him to the blast, and the rest of the desk with him. That
## is also how it earns the top of a ladder that cannot escalate by damage alone — one hit is
## capped at `knockout_damage x max_hit_fraction` however big the charge is, so what a
## late-tier explosive has to buy is reach and company.
##
## Both charges built on it are this class with a longer, stronger pull (D8).

## Inward force at the centre, falling off with distance exactly the way the blast does — so
## what the well gathers is precisely what the blast then reaches.
@export var pull_force: float = 3200.0
@export var pull_seconds: float = 1.3

var _pull_left := 0.0
var _reach := 0.0
var _gathered := false

func explode() -> void:
	if _gathered or pull_seconds <= 0.0 or explosion_area == null:
		super.explode()
		return
	_reach = _blast_reach()
	if _reach <= 0.0:
		super.explode()
		return
	_pull_left = pull_seconds
	explosion_area.monitoring = true
	# Anchored while it pulls. Every body it grabs pushes back on it, and a well that slides
	# off the desk under its own catch detonates somewhere nobody aimed at.
	freeze = true

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _pull_left <= 0.0:
		return
	_pull()
	_pull_left -= delta
	if _pull_left > 0.0:
		return
	_pull_left = 0.0
	freeze = false
	_gathered = true
	explode()

func _pull() -> void:
	for body in explosion_area.get_overlapping_bodies():
		# The blast area's mask covers the item layer, which this body is on, so it reports
		# itself as readily as anything else it caught.
		if body == self or not (body is RigidBody2D):
			continue
		var inward: Vector2 = global_position - body.global_position
		var distance := inward.length()
		if distance < 1.0:
			continue
		# A force, not an impulse: this runs every physics frame for a second or two, and an
		# impulse per frame is a strength that depends on the frame rate.
		(body as RigidBody2D).apply_central_force(inward / distance
			* ExplosionUtil.blast_strength(distance, _reach, pull_force))

## The blast area's real radius, found by *what it is* rather than by name — the same rule
## ExplosionUtil documents and for the same reason: the item scenes renamed that shape once
## already, and every explosion in the game silently stopped applying any force at all.
func _blast_reach() -> float:
	for child in explosion_area.get_children():
		var cs := child as CollisionShape2D
		if cs and cs.shape is CircleShape2D:
			return ExplosionUtil.blast_radius((cs.shape as CircleShape2D).radius,
				cs.global_scale.x)
	return 0.0
