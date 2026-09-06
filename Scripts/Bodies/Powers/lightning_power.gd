class_name LightningPower
extends CursorPowerBase

## The top of the Bones ladder: a strike at the cursor that chains to whatever is nearby.
##
## One click, one big point blast, then up to `chains` smaller ones — each jumping from the
## last body struck to the nearest body it has not hit yet. The chain is what makes it the
## reward for owning a full desk: alone it is an expensive pistol, and with eight loose
## props around him it is the whole desk going off at once.
##
## Like every other blast in the game it hands the receiver an impulse and lets him decide
## what it costs (docs/decisions.md D7), so the chain needs no damage model of its own.

@export var blast_radius: float = 72.0
@export var blast_force: float = 9000.0

## How many extra bodies the bolt jumps to.
@export var chains: int = 3

## How far it can jump, and how much of the previous hit's force each jump carries.
@export var chain_range: float = 220.0
@export var chain_falloff: float = 0.65

func fire(at: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	var mult := effective_damage_mult()
	var struck: Array[RID] = []
	var origin := at
	var force := blast_force
	# The bolt comes down from above the first strike and then follows the chain.
	var path := PackedVector2Array([at + Vector2(0, -160), at])

	for jump in maxi(1, chains + 1):
		for hit in ExplosionUtil.point_blast(space, origin, blast_radius, force):
			var target: Node = hit["body"]
			struck.append((target as RigidBody2D).get_rid())
			if target is Buddy:
				(target as Buddy).take_impulse(float(hit["impulse"]), item_id, mult, origin)
		var next := _nearest_unstruck(origin, struck)
		if next == null:
			break
		origin = next.global_position
		force *= chain_falloff
		path.append(origin)

	var fx := WorldFX.of(self)
	if fx:
		fx.bolt(path)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

## The next link: the closest body inside `chain_range` that this bolt has not already
## touched. Walked over the group rather than queried, for the same reason the vortex does
## — the desk holds a couple of dozen bodies at most, and a group walk cannot silently miss
## one whose collision layer someone edited.
func _nearest_unstruck(from: Vector2, struck: Array[RID]) -> RigidBody2D:
	var best: RigidBody2D = null
	var best_distance := chain_range
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		var body := node as RigidBody2D
		if body == null or struck.has(body.get_rid()):
			continue
		var distance := from.distance_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best
