class_name ProximityMine
extends ThrowableBase

## The mine: no fuse, no timer, no click. Drop it, walk away, and it waits.
##
## Everything else in the explosives category is thrown *at* him. This one is placed and
## then set off by him — which is what makes it the only explosive that combos with the
## knockback weapons, because the fun is shoving him onto it rather than aiming at him.
##
## It arms itself once it has come to rest rather than the moment it is released: a mine
## that armed in mid-air would detonate against the hand that threw it, and a mine that
## needed a right-click to prime would just be a grenade with a different picture.

## Speed below which the mine counts as settled, and how long it has to stay that way.
@export var arm_speed: float = 40.0
@export var arm_seconds: float = 0.5

var _settled := 0.0
var _armed := false

## Right-click stays the base class's business — a mine has no fuse to prime, so the
## gesture is free to mean what it means everywhere else on the desk.
func right_click_is_mine() -> bool:
	return false

func _ready() -> void:
	super._ready()
	if explosion_area:
		# Armed or not, the area has to be watching, or `get_overlapping_bodies()` is empty
		# on the frame the mine finally arms and he is already standing on it.
		explosion_area.monitoring = true

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_primed:
		return

	if dragging or linear_velocity.length() > arm_speed:
		_settled = 0.0
		_armed = false
		return

	if not _armed:
		_settled += delta
		if _settled < arm_seconds:
			return
		_armed = true
		if sprite:
			# The same tell a primed grenade gets, slowed down: this one may sit there for
			# ten minutes, and a fast flash for ten minutes is a strobe on someone's desk.
			var tween := create_tween().set_loops()
			tween.tween_property(sprite, "modulate", Color(1.5, 0.7, 0.7), 0.9)
			tween.tween_property(sprite, "modulate", Color.WHITE, 0.9)
		return

	if explosion_area == null:
		return
	for body in explosion_area.get_overlapping_bodies():
		if body is Buddy:
			is_primed = true
			explode()
			return
