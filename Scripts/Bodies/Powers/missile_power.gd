class_name MissilePower
extends CursorPowerBase

## Click anywhere and a missile flies in and detonates on that spot.
##
## The prototype's version of this was a third copy-pasted activation implementation with
## its own cooldown flag and its own cursor handling; all of that is CursorPowerBase now,
## which leaves this class as the two things that are actually specific to a missile:
## where it comes in from, and how hard it lands.

@export var missile_scene: PackedScene

## Missiles fly in from off the top of the play area, so the strike reads as arriving
## rather than appearing.
@export var spawn_offset: Vector2 = Vector2(0, -800)

@export var max_force: float = 14000.0

func fire(at: Vector2) -> void:
	if missile_scene == null:
		push_error("MissilePower: no missile_scene assigned")
		return
	var missile := missile_scene.instantiate() as Missile
	if missile == null:
		push_error("MissilePower: missile_scene is not a Missile")
		return
	# Parented to whatever hosts the power (the World node), not to the power itself, so
	# a missile in flight is unaffected by the player unequipping mid-strike.
	_host().add_child(missile)
	missile.global_position = at + spawn_offset
	missile.launch(at, item_id, effective_damage_mult(), max_force)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

func _host() -> Node:
	return get_parent() if get_parent() != null else get_tree().current_scene
