class_name Trampoline
extends BaseDraggable

## Launches whatever lands on it, hardest of all him.
##
## A `PhysicsMaterial` bounce cannot do this: bounce is clamped at 1.0, so the best a
## material can manage is "loses no energy", and a trampoline that returns exactly what it
## was given is a floor. This adds energy on the way up, which is the difference between a
## surface and a toy.
##
## It pays nothing and damages nothing directly. The Bones come from where he lands.

## Upward impulse per unit of downward speed, and the least it will ever give — so a
## skeleton laid gently on it still leaves.
@export var bounce_gain: float = 1.55
@export var minimum_launch: float = 320.0

## Ignores anything drifting rather than falling, so a body resting on it does not jitter.
@export var minimum_impact: float = 90.0

## One launch per body per this long. Without it a body still touching on the next tick is
## launched again from its new speed, which compounds into a body leaving the monitor.
@export var relaunch_cooldown: float = 0.25

var _next_launch: Dictionary = {}
## Above this many remembered bodies, expired entries are swept.
const SWEEP_AT := 32

func _ready() -> void:
	super._ready()
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 6)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var now := Time.get_ticks_msec()
	for body in get_colliding_bodies():
		var rigid := body as RigidBody2D
		if rigid == null or rigid.freeze:
			continue
		# Downward speed only. A body scraping sideways across the mat is not bouncing on
		# it, and launching it would fire props off the desk for touching the edge.
		var falling := rigid.linear_velocity.y
		if falling < minimum_impact:
			continue
		var id := rigid.get_instance_id()
		if now < int(_next_launch.get(id, 0)):
			continue
		# Swept like the buddy's own hit cooldowns: instance ids are never reused, so a mat
		# left out all day otherwise remembers every prop that ever bounced off it.
		if _next_launch.size() >= SWEEP_AT:
			for key in _next_launch.keys():
				if now >= int(_next_launch[key]):
					_next_launch.erase(key)
		_next_launch[id] = now + int(relaunch_cooldown * 1000.0)
		var launch := maxf(falling * bounce_gain, minimum_launch)
		rigid.linear_velocity = Vector2(rigid.linear_velocity.x, -launch)
		# Louder for a harder landing, the same way a hit is.
		AudioManager.play(&"bounce", 0.15, lerpf(-16.0, -4.0, clampf(falling / 900.0, 0.0, 1.0)))
		EventBus.contract_event.emit(&"bounce", 1)
