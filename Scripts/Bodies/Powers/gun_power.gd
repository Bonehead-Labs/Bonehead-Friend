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

## Held trigger. The pistol and the shotgun are one shot per click; the minigun is the
## genre's "numbers go up" weapon and has to be a stream, which is a held button rather
## than a clicking finger. Everything else about it is the same class with different
## numbers, which is the point of having a class at all.
@export var auto_fire: bool = false

var _holding := false
## Where the stream is pointed. Tracked from the events rather than polled from
## `get_global_mouse_position()`, so a pushed event can drive it — the OS cursor cannot be
## moved by a test or a capture tool.
var _aim := Vector2.ZERO

func _on_activated() -> void:
	set_process(auto_fire)

func _on_deactivated() -> void:
	set_process(false)
	_holding = false

## Every release and every motion, not only the unhandled ones: a release consumed by a
## panel still has to stop the stream, or the minigun keeps firing at a cursor that is now
## on the shop page.
func _input(event: InputEvent) -> void:
	if not auto_fire:
		return
	if event is InputEventMouseMotion:
		_aim = (event as InputEventMouseMotion).position
	if _holding and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_holding = false

func _process(_delta: float) -> void:
	if not active or not _holding:
		return
	if _cooldown_ready():
		_shoot(_aim)

func fire(at: Vector2) -> void:
	_aim = at
	_holding = auto_fire
	_shoot(at)

func _shoot(at: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var mult := effective_damage_mult()
	var tier := Progression.juice_tier(item_id)
	var fx := WorldFX.of(self)
	for i in maxi(1, pellets):
		var point := at
		if pellets > 1 and spread > 0.0:
			point += Vector2.RIGHT.rotated(randf() * TAU) * randf() * spread
		for hit in ExplosionUtil.point_blast(space, point, blast_radius, blast_force):
			var target: Node = hit["body"]
			if target is Buddy:
				(target as Buddy).take_impulse(float(hit["impulse"]), item_id, mult, point)
		# Sparks where the shot landed, hit or miss — a miss that shows nothing reads as a
		# click that did nothing.
		if fx:
			fx.shot(point, pellets > 1, tier)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)
