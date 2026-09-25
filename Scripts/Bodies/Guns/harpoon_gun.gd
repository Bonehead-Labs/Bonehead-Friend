class_name HarpoonGun
extends HeldGun

## A harpoon gun (docs/decisions.md D71). Right fires a barbed harpoon on a line. If it sticks
## in him, **hold right to reel him in**, and while it is in him **the line is a line**: walk
## the gun away and he comes too. Reeled all the way, the harpoon tears out — the second hit —
## and winds home. A miss winds straight home. Dropped, the gun lets go of the line.
##
## The verb the roster lacked: nothing else holds on to him. Everything before this either hits
## him and is done or pulls him with a field (the vortex, the fan); this pulls him by a point
## on his body, from your hand, for as long as you choose.
##
## ## The line
##
## A rope, not a joint. Longer than the gap it goes slack; shorter and it pulls him back toward
## the muzzle — cancelling the part of his motion that runs away from the hand and closing the
## stretch at `line_stiffness` a second. **Each step's pull is capped under the damage floor**
## (`line_pull`), because the pull is not a contact: D64's ledger sees his momentum change and
## would ask what touched him for it. Under the floor, it is never anybody's hit. Through his
## centre of mass (D54): a harpoon in his arm that also spun him would be the weird sudden
## movement again. The hand feels a share of it.
##
## ## What pays
##
## - **The strike**: the harpoon's impulse at the gun's shot multiplier, the way a shot is.
## - **What the line does to him**: while it is taut or reeling, his impacts with the world are
##   billed to the harpoon gun (`Buddy.claim_impacts`, D65's rule: only *who* is billed moves,
##   never whether — the floor is still the fall floor).
## - **The tear**: reeled all the way in, it rips out for `rip_share` of the strike.
##
## The gun bills everything it causes at one multiplier: `damage_mult` equals `shot_mult` in its
## row (tools/seed_m39_guns.gd), because the reel deliberately brings him to the gun, and the
## gun is what he then meets. The slingshot's rule (D66).

@export_group("Harpoon")
@export var harpoon_texture: Texture2D
## Pixels a second the line comes in while right is held.
@export var reel_speed: float = 380.0
## Reeled this close, the harpoon tears out and winds home.
@export var reel_min: float = 70.0
## The most impulse the line hands him in one physics step. Under the damage floor (350).
@export var line_pull: float = 240.0
## How fast a stretched line closes, per second, as a share of the stretch.
@export var line_stiffness: float = 9.0
## Share of the line's pull felt in the hand.
@export var hand_share: float = 0.3
## Share of the strike the tear is worth.
@export var rip_share: float = 0.6
@export var line_colour: Color = Color("fcfcee")
## The harpoon drawn lying on the rail, hidden while it is out on its line.
@export var loaded_sprite: Sprite2D

## Seconds his impacts stay the gun's after the line last pulled.
const CLAIM_SECONDS := 0.6
## Winding home, px/s.
const WIND_SPEED := 1500.0

var _harpoon: Harpoon = null
var _line: Line2D
var _line_length := 0.0
var _reeling := false
## Times it has torn out of him, for the suite.
var rips := 0

## Out of the gun: in flight, stuck in him, or winding home.
func harpoon_out() -> bool:
	return is_instance_valid(_harpoon) and not _harpoon.is_queued_for_deletion()

func harpoon_in_him() -> bool:
	return harpoon_out() and _harpoon.stuck_to() is Buddy and not _harpoon.winding

func line_length() -> float:
	return _line_length

func is_reeling() -> bool:
	return _reeling and harpoon_in_him()

func ready_to_fire(now: int) -> bool:
	return not harpoon_out() and super.ready_to_fire(now)

## The same trigger does both: loaded, it fires; in him, it reels for as long as it is held.
func pull_trigger() -> void:
	if not dragging:
		return
	if harpoon_in_him():
		_trigger_held = true
		set_process_input(true)
		_reeling = true
		AudioManager.play(&"ratchet", 0.05, -8.0, 0.9)
		return
	super.pull_trigger()

func release_trigger() -> void:
	super.release_trigger()
	_reeling = false

func _end_drag() -> void:
	super._end_drag()
	# No hand on the gun, no hand on the line.
	if harpoon_out() and not _harpoon.winding:
		_wind_home()

func _shoot(from: Vector2, dir: Vector2) -> void:
	var harpoon := Harpoon.new()
	harpoon.name = "Harpoon"
	harpoon.gun = self
	harpoon.source = item_id
	harpoon.mult = shot_damage_mult()
	harpoon.force = shot_force
	harpoon.shove = shove
	harpoon.texture = harpoon_texture
	harpoon.radius = 3.0
	harpoon.bounce = 0.0
	harpoon.lifetime = shot_range / maxf(projectile_speed, 1.0) + 0.5
	harpoon.gravity_scale = projectile_gravity
	harpoon.z_index = 20
	var host := get_parent() if get_parent() else self
	host.add_child(harpoon)
	harpoon.global_position = from
	harpoon.linear_velocity = dir * projectile_speed
	harpoon.picture.rotation = dir.angle()
	_harpoon = harpoon
	_reeling = false
	if loaded_sprite:
		loaded_sprite.visible = false
	AudioManager.play(&"zip", 0.05, -8.0, 0.8)

## The line, every physics frame the harpoon is out — held or not, so a harpoon in flight from
## a gun just dropped still winds home on a line you can see.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not harpoon_out():
		if _harpoon != null:
			_harpoon = null
		if _line and _line.visible:
			_line.visible = false
		return
	if not physics_frozen and harpoon_in_him():
		_haul(delta)
	_draw_line()

## Called by the harpoon the step it reaches him.
func _on_stuck(him: Buddy) -> void:
	_line_length = maxf(reel_min, muzzle_position().distance_to(_harpoon.global_position) * 1.05)
	him.claim_impacts(item_id, shot_damage_mult(), CLAIM_SECONDS)
	# Held since the shot: the reel starts now.
	_reeling = _trigger_held

## The line pulling him, and the reel.
func _haul(delta: float) -> void:
	var him := _harpoon.stuck_to() as Buddy
	if him == null or him.dragging or not dragging:
		_wind_home()
		return
	var anchor := _harpoon.global_position
	var hand := muzzle_position()
	var gap := anchor.distance_to(hand)
	if gap > shot_range * 1.3:
		# Walked away with faster than the line could bring him: it tears free, unpaid.
		_wind_home()
		return
	if _reeling:
		_line_length = maxf(reel_min, _line_length - reel_speed * delta)
	if gap > _line_length and gap > 1.0:
		var toward := (hand - anchor) / gap
		var closing := (him.linear_velocity - linear_velocity).dot(toward)
		var want := (gap - _line_length) * line_stiffness - closing
		var pull := minf(line_pull, him.mass * maxf(0.0, want))
		if pull > 0.0:
			him.apply_central_impulse(toward * pull)
			apply_impulse(-toward * pull * hand_share, hand - global_position)
			him.claim_impacts(item_id, shot_damage_mult(), CLAIM_SECONDS)
	elif _reeling:
		him.claim_impacts(item_id, shot_damage_mult(), CLAIM_SECONDS)
	if _line_length <= reel_min + 0.5 and gap <= reel_min + 28.0:
		_tear_out(him, anchor, hand)

## Reeled all the way: it rips out, which is the second hit, and winds home.
func _tear_out(him: Buddy, anchor: Vector2, hand: Vector2) -> void:
	var toward := (hand - anchor).normalized()
	him.take_impulse(shot_force * rip_share, item_id, shot_damage_mult(), anchor)
	him.apply_central_impulse(toward * minf(line_pull, shot_force * rip_share * 0.1))
	rips += 1
	var fx := WorldFX.of(self)
	if fx:
		fx.chips(anchor, Color("fcfcee"), 5, 180.0)
	AudioManager.play(&"zip", 0.05, -6.0, 1.3)
	_wind_home()

func _wind_home() -> void:
	_reeling = false
	if harpoon_out():
		_harpoon.wind_home()

## Called by the harpoon when it is back in the barrel.
func _on_home() -> void:
	_harpoon = null
	_line_length = 0.0
	AudioManager.play(&"clack", 0.05, -8.0, 1.1)
	if _line:
		_line.visible = false
	if loaded_sprite:
		loaded_sprite.visible = true

func _draw_line() -> void:
	if _line == null:
		_line = Line2D.new()
		_line.name = "Line"
		_line.width = 2.0
		_line.default_color = line_colour
		_line.top_level = true
		_line.z_index = 19
		add_child(_line)
	_line.visible = true
	_line.points = PackedVector2Array([muzzle_position(), _harpoon.tail_position()])

func _exit_tree() -> void:
	super._exit_tree()
	if is_instance_valid(_harpoon):
		_harpoon.queue_free()
	_harpoon = null

## The harpoon: flies nearly flat, sticks in him, winds home along the line.
class Harpoon extends GunProjectile:
	## World px past his outline that the harpoon's middle sits: the head is in.
	const EMBED := 10.0

	var gun: HarpoonGun
	var winding := false

	func _ready() -> void:
		super._ready()
		# A harpoon that meets the desk is a miss: it does not bounce about, it comes home.
		contact_monitor = true
		max_contacts_reported = 1

	## The end the line is tied to: behind the head, along the way it points.
	func tail_position() -> Vector2:
		return global_position - Vector2.RIGHT.rotated(picture.rotation) * 16.0 if picture \
			else global_position

	func _on_him(him: Buddy, at: Vector2, heading: Vector2) -> void:
		him.apply_central_impulse(heading * force * shove)
		him.take_impulse(force, source, mult, at)
		# The barbed head in him, the shaft out of him.
		stick_to(him, at + heading * EMBED)
		# Lengthen its life to the line's: it comes out when it is reeled or let go, not on a clock.
		lifetime = INF
		var fx := WorldFX.of(self)
		if fx:
			fx.shot(at, false, 0)
		AudioManager.play(&"impact_metal", 0.05, -6.0, 1.2)
		if is_instance_valid(gun):
			gun._on_stuck(him)

	func _flying(_delta: float, resting: bool) -> void:
		if winding:
			return
		var far := is_instance_valid(gun) and global_position.distance_to(gun.muzzle_position()) > gun.shot_range
		if resting or get_contact_count() > 0 or far:
			wind_home()

	func _expire() -> void:
		if winding or not is_instance_valid(gun):
			queue_free()
			return
		wind_home()

	func wind_home() -> void:
		if winding:
			return
		winding = true
		spent = true
		if _stuck_to == null:
			freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
			freeze = true
			collision_mask = 0
		_stuck_to = null
		lifetime = INF

	func _physics_process(delta: float) -> void:
		if not winding:
			super._physics_process(delta)
			return
		if not is_instance_valid(gun) or not gun.is_inside_tree():
			queue_free()
			return
		var home := gun.muzzle_position()
		var to := home - global_position
		var step := WIND_SPEED * delta
		if to.length() <= step:
			gun._on_home()
			queue_free()
			return
		global_position += to.normalized() * step
		if picture:
			picture.rotation = (-to).angle()
