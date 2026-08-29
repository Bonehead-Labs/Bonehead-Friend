class_name GunPower
extends CursorPowerBase

## Click-to-shoot cursor powers: the pistol now, shotgun and minigun later off the same
## class with different radius, force and cooldown in their .tres.
##
## A shot is a tight point blast at the cursor. Modelling it as an impulse rather than a
## bespoke damage call feeds the same receiver-side pipeline a bat swing uses, and it
## also shoves loose props around, which is most of the comedy.

@export var blast_radius: float = 48.0
@export var blast_force: float = 3000.0

func fire(at: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	for hit in ExplosionUtil.point_blast(space, at, blast_radius, blast_force):
		var target: Node = hit["body"]
		if target is Buddy:
			(target as Buddy).take_impulse(float(hit["impulse"]), item_id, effective_damage_mult(), at)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)
