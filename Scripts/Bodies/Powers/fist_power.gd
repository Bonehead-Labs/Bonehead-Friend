class_name FistPower
extends CursorPowerBase

## The starter cursor power: a physical fist that chases the mouse and hits things by
## being a rigid body, plus a punch on click.
##
## The fist body is a WeaponBase so Bonehead attributes its contact impulses like any
## other weapon — the fist earns Bones and mastery through exactly the same path a bat
## does, with no special case anywhere in the damage pipeline.

## Parked far off-screen when inactive. The prototype disabled _physics_process *before*
## the parking branch could run, stranding an invisible collider in the play area that
## the player kept bumping into.
const PARKING_POSITION := Vector2(-10000, -10000)

@export var body: WeaponBase
@export var follow_speed: float = 2000.0
## The fist only re-aims once the mouse has moved this far, so a jittering cursor does
## not make it spin.
@export var leeway_radius: float = 50.0
@export var punch_impulse: float = 6000.0

var _last_rotation: float = 0.0
var _previous_mouse: Vector2 = Vector2.ZERO

func _ready() -> void:
	super._ready()
	if body:
		body.gravity_scale = 0.0

func _on_activated() -> void:
	if body == null:
		return
	_previous_mouse = get_global_mouse_position()
	body.global_position = _previous_mouse
	body.visible = true
	body.freeze = false
	set_physics_process(true)

func _on_deactivated() -> void:
	set_physics_process(false)
	if body == null:
		return
	body.visible = false
	body.global_position = PARKING_POSITION
	body.linear_velocity = Vector2.ZERO
	body.freeze = true

func _physics_process(_delta: float) -> void:
	if not active or body == null:
		return
	var mouse := get_global_mouse_position()

	# Velocity rather than direct positioning, so the fist still collides properly and
	# the impulse Bonehead measures is real.
	var to_mouse := mouse - body.global_position
	body.linear_velocity = to_mouse.normalized() * follow_speed if to_mouse.length() > leeway_radius else Vector2.ZERO

	if _previous_mouse.distance_to(mouse) > leeway_radius:
		_last_rotation = (mouse - _previous_mouse).angle() + PI / 2.0
		_previous_mouse = mouse
	body.rotation = _last_rotation

func fire(at: Vector2) -> void:
	if body == null:
		return
	# A click adds a real impulse rather than dealing damage directly, so the punch is
	# measured on the receiver like everything else.
	var dir := at - body.global_position
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.DOWN
	body.apply_impulse(dir * punch_impulse * effective_damage_mult(), Vector2.ZERO)
	# The punch itself: sparks off the knuckles, a ring from the second tier.
	var fx := WorldFX.of(self)
	if fx:
		var tier := Progression.juice_tier(item_id)
		fx.shot(body.global_position, tier >= 2, tier)
