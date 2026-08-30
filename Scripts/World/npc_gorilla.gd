class_name NpcGorilla
extends NpcBase

## The one NPC whose attack is a different *verb* rather than a different number.
##
## Everything else in the roster hits him. The gorilla hits the **desk**: the haymaker lands
## as a shockwave through everything within `slam_radius` of the impact, so a swing that
## misses still throws the props about and a swing that connects sends him and the props
## together. That is what makes it worth watching from across the room, and it is the whole
## reason this is a subclass rather than four larger numbers in the seed table — a roster
## that varies only `attack_impulse` is one animal printed four times (`NpcBase`, D8).
##
## The shock is the shared blast (`ExplosionUtil`), so the impulse he is handed is the same
## number a grenade at that distance would have handed him, measured on the receiver like
## everything else (docs/decisions.md D7). It is emphatically not a second damage model.

## Bodies the query may report. Sixteen is `ExplosionUtil`'s own default and is well past a
## full desk; it is named here because a slam that silently stopped at eight would read as a
## bug in the physics rather than as a limit.
const MAX_CAUGHT := 16

## Where the fists land, relative to the gorilla: out in front and down at the desk. Anchored
## on the 76 px body in `docs/art-direction.md`'s scale table rather than picked by eye, so
## the shock comes out from under its own arms.
@export var slam_offset := Vector2(44.0, 22.0)

## How far the shock carries. Much wider than `attack_range` on purpose, and the two are tuned
## together: the blast falls off with the *square* of the distance, so a radius set to the
## gorilla's reach would land a headline punch as a tap. At a radius of 200 he takes roughly
## two thirds of the full impulse from where the gorilla stops to swing, and the props on the
## far side of the desk take a shove rather than a launch.
@export var slam_radius: float = 200.0

func _land_blow(buddy: Buddy) -> bool:
	if not _can_target(buddy):
		return false
	var space := get_world_2d().direct_space_state
	if space == null:
		# Nothing to query against. An ordinary punch is a worse gorilla and a better outcome
		# than a wind-up that resolves to nothing at all.
		return super._land_blow(buddy)

	var at := global_position + Vector2(slam_offset.x * _facing, slam_offset.y)
	# **The gorilla is inside its own blast.** `point_blast` has no exclusion list and
	# `ExplosionUtil` is not this file's to change; at an arm's length the falloff is near its
	# maximum, so the first slam would launch the gorilla off the desk. Its velocity is taken
	# before the shock and put back after it, which is cheaper than a shockwave that has to
	# know who set it off.
	var mine := linear_velocity
	var landed := false
	for hit in ExplosionUtil.point_blast(space, at, slam_radius, attack_impulse, MAX_CAUGHT):
		var body: Node = hit["body"]
		if body is Buddy:
			(body as Buddy).take_impulse(float(hit["impulse"]), item_id,
				effective_damage_mult(), at)
			landed = true
	linear_velocity = mine
	return landed
