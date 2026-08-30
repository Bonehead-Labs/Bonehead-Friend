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

## Pellets per shot, scattered inside `spread`. One pellet is a pistol; five is a shotgun.
## Modelled as several small blasts rather than one big one because that is what makes
## range matter — at the muzzle every pellet lands, at distance most of them miss.
@export var pellets: int = 1
@export var spread: float = 0.0

func fire(at: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var mult := effective_damage_mult()
	for i in maxi(1, pellets):
		var point := at
		if pellets > 1 and spread > 0.0:
			point += Vector2.RIGHT.rotated(randf() * TAU) * randf() * spread
		for hit in ExplosionUtil.point_blast(space, point, blast_radius, blast_force):
			var target: Node = hit["body"]
			if target is Buddy:
				(target as Buddy).take_impulse(float(hit["impulse"]), item_id, mult, point)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)
