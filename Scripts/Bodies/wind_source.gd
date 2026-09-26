class_name WindSource
extends BaseDraggable

## The desk fan: a constant push in the direction it faces.
##
## It deals no damage of its own. What it does is change every *other* item's arc — a thrown
## grenade curves, a dropped ball rolls, and a swing that used to land now misses. That is the
## only thing in the roster that modifies the physics sandbox rather than adding to it, and it
## is why the fan is worth owning at all.
##
## **What it earns is the world** (D65): while its wind is on him, and for a moment after, an
## impact with the floor or a wall is billed to the fan rather than to `world` — the landing it
## bent is its landing. A prop it blows into him is still the prop's. Before this the fan
## earned nothing under its own name, so its payout node and its capstone were unreachable.
##
## The force is applied to bodies overlapping a cone-ish Area2D rather than to everything on
## screen, so turning the fan changes who is in the wind — pointing it is the interaction.

## Push per second on a body in the wind, before falloff. "Higher Setting" (`wind_mult`)
## multiplies it.
@export var force: float = 900.0

## How long after he leaves the wind an impact with the world is still the fan's.
const CLAIM_SECONDS := 0.5

## Local direction the fan blows in, before its own rotation.
@export var blow_direction: Vector2 = Vector2.RIGHT

## The region the wind fills. Assigned by the scene; without it the fan is a paperweight.
@export var wind_area: Area2D

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if wind_area == null:
		return
	var direction := blow_direction.normalized().rotated(rotation)
	var push := force * Progression.get_modifier(item_id, &"wind_mult")
	var by_itself := blowing_by_itself()
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
		rigid.apply_central_force(direction * push * falloff * delta * 60.0)
		if rigid is Buddy:
			(rigid as Buddy).claim_impacts(item_id, Progression.damage_mult_for(item_id, 1.0),
				CLAIM_SECONDS, by_itself)

## **A fan nobody is holding is nobody's hand** (D76 amended). It blows whether or not anyone is
## at the desk, so the wall it blows him into is the world he was blown into: it is billed to the
## fan, and it is an act only when the world's would be — he was held, or a hand moved him in the
## last three seconds. In the hand, or just put down, or just aimed, it is the player's. Measured
## at an empty desk, a fan beside a gorilla turned the landings D76 had made nobody's back into
## acts: 2,325 Dollars an hour, and two knockouts and 370 damage a minute on the board.
func blowing_by_itself() -> bool:
	return not dragging and Time.get_ticks_msec() - _handled_msec > Economy.WORLD_FOLLOWS_MSEC

## When the player last had it: let go of, or aimed.
var _handled_msec := -100000

func _end_drag() -> void:
	super._end_drag()
	_handled_msec = Time.get_ticks_msec()

## How far off level the fan can be aimed, up or down, on either side (D67). Past this it is a
## fan blowing at the ceiling or into the desk, and neither moves anything worth moving.
const MAX_TILT := deg_to_rad(50.0)

## Points the wind at `world` — the fan's verb (D67), a right-drag from its head. The wind area
## turns with the blow direction, so the push and the region it fills cannot disagree, and
## the stand does not move: the body's own rotation still adds to the aim, as it always did.
## A faint line shows where it points for as long as the drag lasts, because the wind itself
## is not drawn.
func aim_at(world: Vector2) -> void:
	var local := to_local(world)
	if local.length_squared() < 64.0:
		return
	_handled_msec = Time.get_ticks_msec()
	var tilt := clampf(atan2(local.y, absf(local.x)), -MAX_TILT, MAX_TILT)
	var angle := tilt if local.x >= 0.0 else PI - tilt
	blow_direction = Vector2.from_angle(angle)
	if wind_area:
		wind_area.rotation = angle
	var fx := WorldFX.of(self)
	if fx:
		var direction := blow_direction.rotated(global_rotation)
		fx.tracer(global_position + direction * 30.0, global_position + direction * 150.0,
			WorldFX.DUST, 0.25, 2.0)

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
