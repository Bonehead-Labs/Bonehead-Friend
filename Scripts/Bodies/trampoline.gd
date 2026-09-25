class_name Trampoline
extends BaseDraggable

## Launches whatever lands on it, hardest of all him.
##
## A `PhysicsMaterial` bounce cannot do this: bounce is clamped at 1.0, so the best a
## material can manage is "loses no energy", and a trampoline that returns exactly what it
## was given is a floor. This adds energy on the way up, which is the difference between a
## surface and a toy.
##
## It pays nothing by itself. His landing on it is a contact like any other, billed to the mat at
## the swing floor (D64), which is where the Bones in bouncing come from.

## Upward impulse per unit of downward speed, and the least it will ever give — so a
## skeleton laid gently on it still leaves.
@export var bounce_gain: float = 1.55
@export var minimum_launch: float = 320.0
## The most the gain will take anything to (D64). x1.55 a bounce is a runaway — four bounces
## from a drop is 4,000 px/s — so above this the mat stops adding and only gives back what it was
## given: nothing ever leaves slower than it arrived. 1,080 is the speed that lifts him 600 px,
## which is the reference 720 px desk from his feet to the top with his head still on it.
@export var max_launch: float = 1080.0

## Ignores anything drifting rather than falling, so a body resting on it does not jitter.
@export var minimum_impact: float = 90.0

## One launch per body per this long. Without it a body still touching on the next tick is
## launched again from its new speed, which compounds into a body leaving the monitor.
@export var relaunch_cooldown: float = 0.25

var _next_launch: Dictionary = {}
## Above this many remembered bodies, expired entries are swept.
const SWEEP_AT := 32

## How fast each body on the mat was coming down when the step that put it there began, by
## instance id — written by `_integrate_forces`, read and emptied by `_physics_process`.
##
## **Not its velocity now** (D64). By the time `_physics_process` sees a body in contact, the
## solver has already stopped it: he landed at 722 px/s, the mat read what the solver had left of
## that, and every launch was the 320 minimum — "leaves faster than it arrived" was never true.
## A contact's collider velocity is the one the solver started from: the speed it arrived with.
var _arrivals: Dictionary = {}

func _ready() -> void:
	super._ready()
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 6)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_arrivals.clear()
	for i in state.get_contact_count():
		# Relative to the mat, so one being carried about does not launch what it is carried into.
		var closing := (state.get_contact_collider_velocity_at_position(i)
			- state.get_contact_local_velocity_at_position(i)).y
		var id := state.get_contact_collider_id(i)
		_arrivals[id] = maxf(closing, float(_arrivals.get(id, closing)))

## What his landing on the mat is billed at. The landing is a contact like any other and pays at
## the swing floor (`Buddy._min_impulse_for`), but until D64 it was never billed at all, so nothing
## noticed that "Tighter Springs" sold a damage node the hit could not see — `Buddy._attribute`
## reads this method off anything that has it, as it does off an animal or a turret.
func effective_damage_mult() -> float:
	return Progression.damage_mult_for(item_id, 1.0)

## The speed it leaves at, from the speed it arrived with: x`bounce_gain`, never under
## `minimum_launch`, never over `max_launch` unless it came in faster than that — in which case
## it leaves exactly as fast.
func launch_speed(arrival: float) -> float:
	return maxf(minf(maxf(arrival * bounce_gain, minimum_launch), max_launch), arrival)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var now := Time.get_ticks_msec()
	for body in get_colliding_bodies():
		var rigid := body as RigidBody2D
		if rigid == null or rigid.freeze:
			continue
		# Downward speed only. A body scraping sideways across the mat is not bouncing on
		# it, and launching it would fire props off the desk for touching the edge.
		var id := rigid.get_instance_id()
		var falling := float(_arrivals.get(id, rigid.linear_velocity.y))
		if falling < minimum_impact:
			continue
		if now < int(_next_launch.get(id, 0)):
			continue
		# Swept like the buddy's own hit cooldowns: instance ids are never reused, so a mat
		# left out all day otherwise remembers every prop that ever bounced off it.
		if _next_launch.size() >= SWEEP_AT:
			for key in _next_launch.keys():
				if now >= int(_next_launch[key]):
					_next_launch.erase(key)
		_next_launch[id] = now + int(relaunch_cooldown * 1000.0)
		var launch := launch_speed(falling)
		rigid.linear_velocity = Vector2(rigid.linear_velocity.x, -launch)
		# Dust off the mat, more for a harder landing.
		var fx := WorldFX.of(self)
		if fx:
			fx.puff(Vector2(rigid.global_position.x, global_position.y), int(lerpf(3.0, 8.0, clampf(falling / 900.0, 0.0, 1.0))), WorldFX.DUST, 80.0, 0.5)
			if juice_tier >= MasteryMath.JUICE_MID:
				fx.ring(Vector2(rigid.global_position.x, global_position.y), 26.0 + 10.0 * juice_tier, trail_colour(), 0.25, 2.0)
		# Louder for a harder landing, the same way a hit is.
		AudioManager.play(&"bounce", 0.15, lerpf(-16.0, -4.0, clampf(falling / 900.0, 0.0, 1.0)))
		EventBus.contract_event.emit(&"bounce", 1)
