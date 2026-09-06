class_name TurretBase
extends BaseDraggable

## A gun you put down on the desk and then stop thinking about. It finds Bonehead by
## itself and fires at him on a timer for as long as it is on screen.
##
## ## Why the turret costs Bones and its capstone costs Hearts
##
## Automation is Hearts-priced, everywhere, always (docs/decisions.md D2, restated in D31).
## *You cannot stop working for your money without being kind to him* is the bargain that
## makes this game something other than Interactive Buddy with a shop, and a turret is the
## one shape of content that can walk straight around it: a thing bought with damage money
## that then earns money on its own. So the category is split down the middle, deliberately,
## and all three halves are load-bearing:
##
## - The **item** costs Bones. It is a gun. Buying it with love reads wrong.
## - A **placed** turret fires only while the game is open and contributes **no offline
##   income whatsoever**. Nothing here banks, accrues, or is written to the save: its
##   earnings are whatever damage it lands while somebody is watching. It is an active-play
##   amplifier — it multiplies the session you are sitting in, not the eight hours you were
##   asleep.
## - Its **automation capstone** — the upgrade that makes it work while you are away — costs
##   Hearts, priced by the same rule as every other capstone in the game.
##
## Give this class an offline rate and the first bullet becomes a Bones-priced idle engine,
## which is the one hole in the economy D2 exists to close. The absence of that code is the
## feature.
##
## ## How it hurts him
##
## A shot is a point blast at wherever he is standing, reported through `Buddy.take_impulse`
## — the same door a gunshot uses and the same number the contact solver would have handed
## him, so a turret is measured on the receiver exactly as a bat swing is (D7). That also
## means a turret shoves the loose props around, which is most of the comedy, and shoves
## *itself* when it is standing close enough, which is the recoil.

## Floor on the gap between shots. Ten levels of a 0.94 fire-rate node compounds to 0.54 and
## an exclusive branch can halve it again; without a floor a stacked build eventually asks
## for one shot per physics frame, which is sixty shape queries a second from one object on
## a desk budgeted at 3% CPU.
const MIN_INTERVAL := 0.05

## How fast the lean follows the target, per second. Slow enough to read as a machine
## turning rather than as a sprite snapping between two angles.
const LEAN_LERP := 6.0

## Seconds between shots, before the fire-rate augment.
##
## This is the turret's whole identity. A nail gun at 0.14 and a mortar at 3.6 are two
## different toys built from the same four numbers; a roster that varies only `blast_force`
## is one gun printed eight times.
@export var fire_interval: float = 1.0

## The shot, as a blast centred on him. Radius is how forgiving it is, force is how hard it
## hits — and because damage is the impulse he receives, force *is* the damage.
@export var blast_radius: float = 32.0
@export var blast_force: float = 900.0

## Folded into the impulse he is handed, exactly as a weapon's multiplier is.
@export var damage_mult: float = 1.0

## Pellets per shot, scattered inside `spread` around him. One is a rail gun; six is a swarm
## launcher. Several small blasts rather than one large one, because that is what makes a
## salvo feel like a salvo instead of like a bigger number.
@export var pellets: int = 1
@export var spread: float = 0.0

## How far the turret reaches, in world pixels. **This is the placement decision.** A turret
## that can hit anything from anywhere makes where you set it down irrelevant; a flamethrower
## with 150 of reach has to be carried over and put next to him, and a rail gun does not.
@export var max_range: float = 400.0

## How far the picture leans toward its target, in degrees. The turret has one sprite and no
## separate barrel node, so the lean *is* the aim readout — a device that fires with no tell
## at all reads as the desk hurting him by itself.
@export var aim_lean_degrees: float = 12.0

## The kick on firing, in world pixels, and how fast the sprite walks it off.
@export var recoil_pixels: float = 3.0
@export var recoil_recovery: float = 24.0

var _since_shot := 0.0
var _lean := 0.0
var _recoil := 0.0
## Which way it last pointed, as -1 or +1. Never zero, so a shot fired at a buddy standing
## exactly overhead still kicks somewhere.
var _facing := 1.0

## Resolved once and kept. A group lookup every physics frame, times a desk's worth of
## turrets, is a measurable cost in a game that is expected to be left running for eight
## hours; `is_instance_valid` re-resolves it after a knockout frees and rebuilds anything.
var _buddy: Buddy = null

func _ready() -> void:
	super._ready()
	# Staggered, so eight turrets bought in the same minute do not settle into one
	# synchronised volley — which reads as a single weapon rather than as eight machines —
	# and so their shape queries land on different frames.
	_since_shot = randf() * fire_interval

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var target := _target()
	_animate(delta, target)

	# Capped at the interval rather than accumulated freely. An uncapped timer means a turret
	# left alone while he is out of range banks an hour of shots and empties the lot into him
	# the moment he wanders past.
	var interval := _interval()
	_since_shot = minf(_since_shot + delta, interval)
	if target == null or _since_shot < interval:
		return
	_since_shot = 0.0
	_fire(target)

## Him, if he is in reach. Found by group and never by path: he lives in a different scene
## from this one, and a path across that boundary is the pattern that shipped an export
## crash (docs/decisions.md D9).
func _target() -> Buddy:
	if not is_instance_valid(_buddy):
		_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	if _buddy == null:
		return null
	if global_position.distance_to(_buddy.global_position) > max_range:
		return null
	return _buddy

## Fire rate is what a turret's third tier-1 node buys, under the same `cooldown_mult` key a
## cursor power's rate node uses — so "the gap between shots gets shorter" reads identically
## wherever it is bought.
func _interval() -> float:
	var gap := fire_interval
	if item_id != &"":
		gap *= Progression.get_modifier(item_id, &"cooldown_mult")
	return maxf(gap, MIN_INTERVAL)

func _fire(target: Buddy) -> void:
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	var mult := effective_damage_mult()
	var at := target.global_position
	for i in maxi(1, pellets):
		var point := at
		if pellets > 1 and spread > 0.0:
			point += Vector2.RIGHT.rotated(randf() * TAU) * randf() * spread
		for hit in ExplosionUtil.point_blast(space, point, blast_radius, blast_force):
			var body: Node = hit["body"]
			if body is Buddy:
				(body as Buddy).take_impulse(float(hit["impulse"]), item_id, mult, point)
	if _animating():
		_recoil = recoil_pixels
	# The line the shot took, for a tenth of a second. Without it a turret was a device
	# that leaned and a buddy that flinched, with nothing between them.
	var fx := WorldFX.of(self)
	if fx:
		fx.tracer(global_position, at)
	# Quiet and wide: the fastest turret fires twenty times a second, and this is the
	# background of the desk, not the event of the desk.
	AudioManager.play(&"turret_fire", 0.16, -16.0)
	EventBus.threat_changed.emit(&"turret", global_position, 1.0)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

## What Bonehead multiplies the notional impulse by, read the same way a weapon reads it.
func effective_damage_mult() -> float:
	return Progression.damage_mult_for(item_id, damage_mult)

## Motion stops when Focus Mode is Off (docs/decisions.md D21). **The firing does not.**
## That is the contract every automation in this game keeps: a player who set Focus Mode
## because they are in a meeting meant "stop moving", not "stop earning".
##
## The Off branch parks the sprite rather than simply skipping the frame. A turret caught
## mid-lean when the setting changed would otherwise keep that lean for the rest of the
## session, and an animation frozen off-centre reads as a bug rather than as stillness.
func _animate(delta: float, target: Buddy) -> void:
	if sprite == null:
		return
	if not _animating():
		sprite.rotation = 0.0
		sprite.position = Vector2.ZERO
		_lean = 0.0
		_recoil = 0.0
		return

	var want := 0.0
	if target != null:
		# In body-local space, so a turret that has been knocked onto its side still leans
		# toward him rather than toward wherever the world's right hand side happens to be.
		_facing = -1.0 if to_local(target.global_position).x < 0.0 else 1.0
		want = _facing * deg_to_rad(aim_lean_degrees)
	_lean = lerpf(_lean, want, clampf(delta * LEAN_LERP, 0.0, 1.0))
	_recoil = maxf(_recoil - recoil_recovery * delta, 0.0)
	sprite.rotation = _lean
	sprite.position = Vector2(-_facing * _recoil, 0.0)

func _animating() -> bool:
	return Settings.focus_intensity != Settings.Intensity.OFF
