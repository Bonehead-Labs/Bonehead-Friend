class_name HeldGun
extends WeaponBase

## A gun you hold (docs/decisions.md D56). Left holds it, right fires it, and it points itself
## at him — but it is a body on a string, not a cursor, so it has weight: it lags when you
## swing it, it kicks when it fires, and a long burst climbs off him.
##
## Every gun in the game is one of these (D71). The cursor pistol, shotgun and minigun were
## retired into held guns under the same ids, because the owner, after an evening with these:
## "they feel excellent, so much so that cursor powers should not have guns anymore". The
## cursor is for powers; a gun is a thing on the desk that you pick up, that he can see
## pointed at him, and that you can drop.
##
## Four things a gun can have beyond D56's trigger, each off unless its numbers say otherwise:
## a **magazine** that runs dry and reloads (the double barrel's two, the tommy gun's drum), a
## **spin-up** before a rotary gun fires and a spin-down that lets a quick re-press fire at
## once (the minigun), **heat** that locks the trigger when it overflows (the ray gun), and a
## **lob**: a gun whose shot falls lays its barrel on the arc that lands on him rather than on
## the straight line (the grenade launcher, the flare gun, the harpoon, the foam darts). What a
## shot *is* beyond a ray, a squirt or a bubble belongs to a subclass (`Scripts/Bodies/Guns/`).
##
## ## How it aims
##
## A PD controller on **torque**, never on `rotation` and never by overwriting
## `angular_velocity` — D54's fist wrote its velocity every frame and so erased every impulse
## anything gave it, including its own punch. Torque composes with everything else in the
## solver: the recoil impulse, a bat knocking it sideways, the hand swinging it. The gains are
## scaled by the gun's moment of inertia *about the grip*, so every gun has the natural
## frequency it was authored with (`aim_frequency`) whatever it weighs, and the torque is
## capped at `aim_max_accel` of that inertia, which is what lets a knock actually knock it.
## Gravity about the grip is cancelled on top — that is the hand holding it level.
##
## It aims the **barrel line**, not the grip, at his centre of mass: the barrel sits above the
## hand, so pointing the grip at him would put every shot a barrel-height high.
##
## ## How it fires
##
## Along the barrel's *actual* direction, which is the whole reason recoil and lag matter: a
## shot fired while the gun is still swinging back onto him goes where the gun is pointing.
## A hitscan ray from the authored muzzle; a hit on him goes through `Buddy.take_impulse`
## exactly as a cursor gun's does (D7), and anything else it hits is shoved through its
## centre of mass (D54). The kind guns use the same trigger and the same aim: the water
## pistol's spray scrubs through `GrimeComponent.clean` and banks Hearts the way the sponge
## does, and the bubble blaster's bubbles drift to him and pop into a kind act.
##
## ## How it turns round
##
## Mirrored about the barrel's own axis through the grip when the barrel swings past vertical,
## so a gun aimed left is never upside down. Mirroring about that line keeps the grip where
## the hand is — mirroring about anything else would move the joint's anchor and yank the
## body, the D54 bug again — and keeps the barrel pointing the same way, so the aim does not
## jump. The sprite, every collider, the grab region, the centre of mass and the muzzle all
## mirror together; the scenes are built with the body's origin *at* the grip to make that a
## sign flip (`tools/seed_m39_guns.gd`).
##
## Nothing here runs while it is lying on the desk: the base class's drag chase and trail are
## the only per-frame work, exactly as for a bat (the idle budget is 3% CPU).

## Radians of barrel from the vertical at which it rolls over, with hysteresis: it turns to
## face left once the barrel points more than this far past straight up or down, and back
## once it points the same distance the other way. About ten degrees each side.
const FLIP_AT := 0.17

## Inside this many radians of the true aim line, he knows it is pointed at him.
const THREAT_RADIANS := 0.2
## The threat is re-asserted this often while it holds, so a hit that interrupts his cower
## gives way to it again, and so it lapses by itself if the gun vanishes without a word.
const THREAT_REFRESH_MSEC := 500

## Floor on the gap between shots, for the same reason as the turret's: a stacked fire-rate
## build must not ask for a ray cast every physics frame.
const MIN_INTERVAL := 0.05

## The collision layers a shot can land on: world, buddy, item. Never handles or sensors.
const SHOT_MASK := 1 | 2 | 4

## Sustained kindness (the water pistol) is banked and flushed on this interval, like the
## sponge's (FriendlyBase.FLUSH_SECONDS): one payout per half second, not one per squirt.
const FLUSH_SECONDS := 0.5

## The water, off the roster palette (teal light).
const WATER := Color("7fe3df")

@export_group("Aim")
## Natural frequency of the aim, rad/s. Settle time is roughly 3 / (damping x frequency):
## 26 is a light gun on him in a fifth of a second, 13 a long rifle in two fifths.
@export var aim_frequency: float = 20.0
@export var aim_damping: float = 0.8
## The most angular acceleration the hand will spend correcting, rad/s². This is the weight:
## below it the aim is a spring, above it the gun swings and has to be caught.
@export var aim_max_accel: float = 240.0
## Share of gravity's pull about the grip the hand cancels. One holds it level; less lets the
## muzzle sag while the aim fights it.
@export var gravity_hold: float = 1.0

@export_group("Shot")
## Where the shot leaves and where a spent case leaves, in body-local world pixels with the
## gun drawn facing right. The origin is the grip.
@export var muzzle: Vector2 = Vector2(30, -6)
@export var ejector: Vector2 = Vector2(4, -8)
## Whether it throws a spent case at all. A revolver keeps its cases and a muzzle-loader has
## none.
@export var ejects: bool = true
## `bullet` fires rays, `water` squirts, `bubble` blows bubbles.
@export var shot_kind: StringName = &"bullet"
@export var fire_interval: float = 0.4
## Held trigger. Semi-automatic guns fire once per press.
@export var auto_fire: bool = false
@export var pellets: int = 1
## Half-angle of the cone each pellet is scattered in, in degrees.
@export var spread_degrees: float = 0.0
## The impulse a shot hands him — and so its damage, because damage is the impulse he
## receives (D7). A pellet's, for a shotgun.
@export var shot_force: float = 3000.0
## Multiplier on the shot's damage, before the damage augment. `damage_mult` (WeaponBase) is
## the *contact* multiplier: a gun swung into him is a lump of metal, not a gunshot.
@export var shot_mult: float = 1.0
## How much of `shot_force` is also the physical shove, on him and on anything else hit.
@export var shove: float = 1.0
@export var shot_range: float = 700.0
## A pump or a bolt: this long after the shot, it clacks and throws the case. Zero ejects the
## case with the shot.
@export var pump_delay: float = 0.0
## The desk jolts by this many pixels on a shot (WorldFX.shake is capped and Normal-only).
@export var shake_pixels: float = 0.0

@export_group("Recoil")
## Backwards along the barrel, applied at the muzzle — so with the barrel above the hand it
## also climbs, the way a real one does.
@export var recoil_kick: float = 300.0
## Extra angular impulse lifting the muzzle, on top of what the kick does about the grip.
@export var recoil_climb: float = 400.0
## A burst's drift: each shot raises the aim by this much, up to `climb_max`, and it bleeds
## away at `climb_recovery` rad/s once the trigger rests. Zero for a gun fired one at a time.
@export var climb_per_shot: float = 0.0
@export var climb_max: float = 0.0
@export var climb_recovery: float = 1.5

@export_group("Kind")
## The water pistol: grime removed per squirt that lands, and Hearts value per squirt that
## lands on top — a clean skeleton still likes being squirted.
@export var squirt_clean: float = 0.03
@export var squirt_value: float = 0.25
## The bubble blaster: the value of one bubble reaching him, and how fast it drifts.
@export var bubble_value: float = 1.0
@export var bubble_speed: float = 90.0
@export var bubble_texture: Texture2D

@export_group("Magazine")
## Rounds before it has to reload; zero never reloads. A revolver's six are drawn, not counted:
## a magazine is here for the guns whose rhythm *is* the reload.
@export var magazine: int = 0
## Seconds from the last round to a full magazine, before the rate node, which shortens it too.
@export var reload_time: float = 1.0
## The cases come out at the reload rather than with each shot: a break-action throws both.
@export var eject_on_reload: bool = false

@export_group("Spin")
## Seconds of held trigger before a rotary gun fires its first round. Zero fires at once.
@export var spin_up: float = 0.0
## Seconds to run down from full speed once the trigger is let go. Pressed again before it has
## stopped and it fires at once — which is how a minigun is fought: in bursts, spun.
@export var spin_down: float = 0.8
## The shudder of the barrels at full speed, rad/s² of jitter about the grip.
@export var spin_shudder: float = 0.0
## The second frame of the barrels, shown every other beat while they turn.
@export var spin_sprite: Sprite2D

@export_group("Heat")
## Share of the gauge each shot adds. Zero is a gun that never heats.
@export var heat_per_shot: float = 0.0
## Share of the gauge shed a second.
@export var heat_cooling: float = 0.5
## Seconds the trigger is dead after the gauge overflows.
@export var overheat_lock: float = 1.5

@export_group("Lob")
## A shot that is a body rather than a ray: its speed, and how much of gravity it feels. When
## both are set the aim lays the barrel on the low arc through him, not the straight line.
@export var projectile_speed: float = 0.0
@export var projectile_gravity: float = 0.0

@export_group("Look")
## The shot's line. Clear means the juice tier's colour (D41); the ray gun's beam is a tracer.
@export var tracer_colour: Color = Color(0, 0, 0, 0)
@export var tracer_width: float = 2.0
@export var tracer_time: float = 0.08

@export_group("Sound")
@export var fire_sound: StringName = &"turret_fire"
@export var fire_pitch: float = 1.0
@export var fire_volume_db: float = -8.0

## A heat gauge at full, off the roster palette's red.
const HOT := Color(1.0, 0.55, 0.45)

## Share of full speed a rotary gun still fires at while it runs down.
const SPIN_HOLDS := 0.35

## +1 drawn as authored, -1 mirrored about the barrel line.
var _flip := 1.0
## What each mirrored node looks like unmirrored: node -> [position, rotation].
var _rest: Dictionary = {}
var _rest_com := Vector2.ZERO

var _trigger_held := false
var _next_shot_msec := 0
var _last_shot_msec := 0
## The burst's accumulated climb, radians of aim offset toward the gun's top.
var _climb := 0.0
var _gravity := 980.0

var _buddy: Buddy = null
var _aim_error := 0.0
var _threatening := false
var _threat_refresh_msec := 0

var _banked := 0.0
var _bank_position := Vector2.ZERO
var _since_flush := 0.0

var _kind_known := false
var _kind := false

## Rounds left, or -1 for a full magazine not yet counted into.
var _rounds := -1
## When the reload in progress ends, or 0 with none.
var _reload_until_msec := 0
## 0 stopped, 1 up to speed.
var _spin := 0.0
var _spin_phase := 0.0
## Up to speed since it last reached it, and not yet run down past `SPIN_HOLDS`: a rotary gun
## fires only from full speed, and keeps firing — or fires at once when pressed again — for as
## long as the barrels are still turning fast.
var _spun := false
## The gauge as last written, and when; read through `heat_level`, which cools it by the clock,
## so a gun lying on the desk does no work to cool down.
var _heat := 0.0
var _heat_msec := 0
var _overheat_until_msec := 0

## Shots fired, for the suite and the F3 overlay. Never read by the simulation.
var shots_fired := 0

func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	_record_rest()
	set_process_input(false)

## Whether this is one of the kind guns, read off the item's category like every other
## side question (ItemData.is_kind) rather than off a second flag that could disagree.
func is_kind_gun() -> bool:
	if not _kind_known and item_id != &"":
		var item := ItemDB.get_item(item_id)
		_kind = item != null and item.is_kind()
		_kind_known = true
	return _kind

# --- the trigger ---------------------------------------------------------------

## Right-click is the trigger while it is in your hand, so the base class must not spend it on
## binning. Shift+right still bins — that is not ours to take (BaseDraggable.click_would_bin).
func right_click_is_mine() -> bool:
	return true

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_RIGHT or not click.pressed:
		return
	if click.shift_pressed or not dragging or is_queued_for_deletion():
		return
	pull_trigger()
	get_viewport().set_input_as_handled()

## Every release, not only the unhandled ones: a release over a panel is consumed by the
## panel, and a stream that only stopped on an unhandled release would keep firing at a
## cursor that is now on the shop page (the cursor minigun learned this first). Only listened
## for while the trigger is down.
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		release_trigger()

func pull_trigger() -> void:
	if not dragging:
		return
	_trigger_held = true
	set_process_input(true)
	if spin_up > 0.0 and _spin <= 0.0:
		AudioManager.play(&"whirr", 0.04, -8.0, 0.7)
	if not fire():
		# A trigger that does nothing must still say why: a dry click while it reloads or
		# cools. A rotary gun spinning up has said so already.
		var now := Time.get_ticks_msec()
		if is_reloading(now) or is_overheated(now):
			AudioManager.play(&"wheel_tick", 0.05, -12.0, 0.8)

## The trigger comes up when the game loses focus (D70): alt-tab with it held and the release
## goes to the other window, so a full-auto gun kept firing at him, and paying Bones, until the
## player came back and clicked.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _trigger_held:
		release_trigger()

func release_trigger() -> void:
	_trigger_held = false
	set_process_input(false)
	_flush()

func trigger_held() -> bool:
	return _trigger_held

func _end_drag() -> void:
	# Let go of at speed, a harm gun is a throw (`_meet_him_in_flight`). Read before the joint goes,
	# which changes nothing this frame but says what the hand was doing.
	_flight_steps = THROW_STEPS if not is_kind_gun() and linear_velocity.length() > THROW_SPEED else 0
	super._end_drag()
	release_trigger()
	_set_threat(false)
	_spin = 0.0
	_spun = false
	if spin_sprite:
		spin_sprite.visible = false

func _exit_tree() -> void:
	_flush()
	_set_threat(false)

# --- per frame, only while held --------------------------------------------------

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Not while the hit-stop has physics switched off (D54): an impulse or a torque applied to a
	# stopped world accumulates and lands all at once when it resumes.
	if _flight_steps > 0 and not physics_frozen:
		_fly(delta)
	if not dragging:
		return
	if physics_frozen:
		return
	var since := Time.get_ticks_msec() - _last_shot_msec
	if not _trigger_held or since > int(_interval() * 1500.0):
		_climb = move_toward(_climb, 0.0, climb_recovery * delta)
	if spin_up > 0.0:
		_turn_barrels(delta)
	_hold_aim()
	if _trigger_held and auto_fire:
		fire()
	if heat_per_shot > 0.0 and sprite:
		sprite.modulate = Color.WHITE.lerp(HOT, heat_level())
	if _banked > 0.0:
		_since_flush += delta
		if _since_flush >= FLUSH_SECONDS:
			_flush()

# --- thrown --------------------------------------------------------------------------
#
# **A thrown gun bills its own hit** (item audit F1's last case, the thrown guns). A harm gun thrown
# into him is a lump of metal and is billed its contact multiplier, as anything that hits him is —
# but only if the engine lets it arrive. Godot's cast-ray CCD sees a fast body about to cross into
# another inside the step and cuts its velocity, for good, to what reaches the contact point and no
# further (`_test_ccd`: the gap to him plus 1% of its length, per step). Measured on the SMG: 1,313
# px/s the step before, 82 px/s at the contact, 58 of momentum handed to him and nothing billed. How
# much of a throw survived was the gap to him when its last step began — anywhere from nothing to
# the whole step's 22 px — so a throw paid or did not by where the frame boundary fell, on every gun
# short enough for the CCD to call fast.
#
# So a gun let go of at speed is watched for the step in which it would reach him — its own shapes
# swept along that step's motion, which is exactly the motion the CCD casts — and that collision is
# solved here, from its `_physics_process`, before `Buddy.StepStart` (D64, D74): the impulse of a
# collision at the contact point with the engine's own restitution (the two bounces summed, clamped
# to 1) and both bodies' mass and inertia. The gun takes its half, and `Buddy.take_contact` hands
# him his and bills it through the floor, the cooldown and `_attribute` a reported contact goes
# through. The gun is then moving off him, so the CCD has nothing to cut and no contact follows to
# bill it twice. A gun already touching him, or thrown slowly, is left to the engine as before.

## Out of the hand faster than this, it is a throw. The suite's throws leave at 580 to 880 px/s; a
## gun put down, or let go of while held still, is not one.
const THROW_SPEED := 300.0
## How long a throw is watched: a second of physics steps, then it is a gun lying on the desk.
const THROW_STEPS := 60

## Physics steps of the current throw still watched; 0 when it is not in the air from a throw.
var _flight_steps := 0
## For the suites: the impulse the last throw's collision handed him, 0 before one lands.
var last_throw_hit := 0.0

func _fly(delta: float) -> void:
	_flight_steps -= 1
	if dragging or linear_velocity.length() < THROW_SPEED:
		_flight_steps = 0
		return
	if _meet_him_in_flight(delta):
		_flight_steps = 0

## Solves the collision with him that this step would have made, if it makes one. True if it did.
func _meet_him_in_flight(delta: float) -> bool:
	if not is_inside_tree():
		return false
	if not is_instance_valid(_buddy):
		_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	if _buddy == null or _buddy.freeze or not _buddy.is_inside_tree():
		return false
	var space := get_world_2d().direct_space_state
	# What the CCD will cast: this step's velocity, gravity included, over one step.
	var motion := (linear_velocity + get_gravity() * delta) * delta
	var first := 1.0
	var hit := {}
	for child in get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = cs.shape
		query.transform = cs.global_transform
		query.motion = motion
		query.collision_mask = WeaponAbility.BUDDY_LAYER
		query.exclude = [get_rid()]
		var fractions := space.cast_motion(query)
		if fractions.size() < 2 or fractions[1] >= first:
			continue
		if fractions[1] <= 0.0:
			# Already touching him: an ordinary contact, which the engine solves at full speed.
			return false
		first = fractions[1]
		query.transform = cs.global_transform.translated(motion * fractions[1])
		query.motion = Vector2.ZERO
		query.margin = 1.0
		hit = space.get_rest_info(query)
	if hit.is_empty() or int(hit.get("collider_id", 0)) != _buddy.get_instance_id():
		return false
	var me := PhysicsServer2D.body_get_direct_state(get_rid())
	var his := PhysicsServer2D.body_get_direct_state(_buddy.get_rid())
	if me == null or his == null:
		return false
	# The rest info's normal is his surface's, pointing out of him at the gun.
	var n := -(hit["normal"] as Vector2).normalized()
	var point: Vector2 = hit["point"]
	var r_me := point - (global_position + me.center_of_mass)
	var r_him := point - (_buddy.global_position + his.center_of_mass)
	var v_me := me.linear_velocity + Vector2(-r_me.y, r_me.x) * me.angular_velocity
	var v_him := his.linear_velocity + Vector2(-r_him.y, r_him.x) * his.angular_velocity
	var closing := (v_me - v_him).dot(n)
	if closing <= 0.0:
		return false
	var arm_me := r_me.cross(n)
	var arm_him := r_him.cross(n)
	var k := me.inverse_mass + his.inverse_mass + arm_me * arm_me * me.inverse_inertia \
		+ arm_him * arm_him * his.inverse_inertia
	if k <= 0.0:
		return false
	var e := clampf(_bounce_of(self) + _bounce_of(_buddy), 0.0, 1.0)
	var j := (1.0 + e) * closing / k
	apply_impulse(-n * j, point - global_position)
	last_throw_hit = j
	_buddy.take_contact(self, n * j, point)
	return true

static func _bounce_of(body: RigidBody2D) -> float:
	return body.physics_material_override.bounce if body.physics_material_override else 0.0

## A rotary gun: up to speed while the trigger is held, down again when it is not, shuddering
## in the hand while it turns, and the barrels drawn turning.
func _turn_barrels(delta: float) -> void:
	if _trigger_held:
		_spin = minf(1.0, _spin + delta / _spin_up_seconds())
	else:
		_spin = maxf(0.0, _spin - delta / maxf(spin_down, 0.05))
	if _spin >= 1.0:
		_spun = true
	elif _spin < SPIN_HOLDS:
		_spun = false
	if _spin <= 0.0:
		if spin_sprite and spin_sprite.visible:
			spin_sprite.visible = false
		return
	if spin_shudder > 0.0:
		var arm := global_transform * center_of_mass - global_position
		apply_torque_impulse(randf_range(-1.0, 1.0) * spin_shudder * _spin * delta * _pivot_inertia(arm))
	_spin_phase += _spin * delta * 24.0
	if spin_sprite:
		spin_sprite.visible = int(_spin_phase) % 2 == 1

## Seconds to full speed, which the rate node shortens as it shortens every other wait.
func _spin_up_seconds() -> float:
	var up := spin_up
	if item_id != &"":
		up *= Progression.get_modifier(item_id, &"cooldown_mult")
	return maxf(up, 0.05)

func spin() -> float:
	return _spin

func is_spun() -> bool:
	return _spun

func _hold_aim() -> void:
	var com := global_transform * center_of_mass
	var arm := com - global_position
	# The hand holding it up: gravity's torque about the grip, cancelled.
	var torque := -arm.x * mass * _gravity * gravity_scale * gravity_hold
	var target := _target_point()
	var want := 0.0 if _flip > 0.0 else PI
	var true_want := want
	if target != Vector2.INF:
		true_want = _aim_angle(target)
		# The burst's climb raises the aim toward the gun's own top, which is local -y as drawn
		# and +y mirrored: a negative rotation as drawn, a positive one mirrored.
		want = true_want - _flip * _climb
	var err := wrapf(want - global_rotation, -PI, PI)
	_aim_error = wrapf(true_want - global_rotation, -PI, PI)
	var inertia := _pivot_inertia(arm)
	var w := aim_frequency
	var pd := inertia * (w * w * err - 2.0 * aim_damping * w * angular_velocity)
	var cap := inertia * aim_max_accel
	torque += clampf(pd, -cap, cap)
	apply_torque(torque)
	_update_flip()
	if target != Vector2.INF and not is_kind_gun():
		var reach := global_position.distance_to(target) <= shot_range
		_set_threat(reach and absf(_aim_error) < THREAT_RADIANS)

## The rotation that lays the barrel line through `target`. The barrel runs along local +x at
## `muzzle.y` from the grip, so the line is offset from the hand by that much and the angle
## is corrected by asin(offset / distance) — nothing at range, a few degrees up close.
func _aim_angle(target: Vector2) -> float:
	if projectile_speed > 0.0 and projectile_gravity > 0.0:
		return _lob_angle(target)
	var to := target - global_position
	var distance := to.length()
	var offset := muzzle.y * _flip
	var correction := 0.0
	if distance > absf(offset) + 1.0:
		correction = asin(clampf(offset / distance, -0.95, 0.95))
	return to.angle() - correction

## The launch angle of the low arc from the muzzle through `target`, for a shot that falls.
## A shot lobbed at him from the muzzle along the barrel lands on him without anyone aiming
## high, which is the D56 promise — the gun aims itself — kept for the guns whose shot drops.
## Out of reach, it lobs at forty-five degrees and falls short, which is what a player would
## do and what a grenade that bounces the rest of the way is for. No offset correction: the
## shot leaves from the muzzle itself along the barrel, so the barrel's angle *is* the launch.
func _lob_angle(target: Vector2) -> float:
	var from := muzzle_position()
	var dx := target.x - from.x
	# Godot's y points down; `rise` is how far the target is above the muzzle.
	var rise := from.y - target.y
	var x := absf(dx)
	var v := projectile_speed
	var g := _gravity * projectile_gravity
	var theta := PI * 0.25
	if x > 1.0:
		var reach := v * v * v * v - g * (g * x * x + 2.0 * rise * v * v)
		if reach >= 0.0:
			theta = atan((v * v - sqrt(reach)) / (g * x))
	var side := 1.0 if dx >= 0.0 else -1.0
	return Vector2(cos(theta) * side, -sin(theta)).angle()

## Moment of inertia about the grip: the body's own about its centre of mass, which the
## physics server computed from the authored shapes and the current mass, plus m r².
func _pivot_inertia(arm: Vector2) -> float:
	var inertia := mass * 400.0
	var state := PhysicsServer2D.body_get_direct_state(get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	return inertia + mass * arm.length_squared()

## His centre of mass, found by group and never by path (D9), or INF with nobody to aim at.
func _target_point() -> Vector2:
	if not is_instance_valid(_buddy):
		_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	if _buddy == null:
		return Vector2.INF
	return _buddy.global_transform * _buddy.center_of_mass

## Radians between where the barrel points and where it would point dead on him, burst climb
## excluded. For the suite and the threat.
func aim_error() -> float:
	return _aim_error

func barrel_direction() -> Vector2:
	return global_transform.x.normalized()

func muzzle_position() -> Vector2:
	return to_global(Vector2(muzzle.x, muzzle.y * _flip))

func is_flipped() -> bool:
	return _flip < 0.0

## He knows it is pointed at him: the expression brain's `aim` threat (D56). Edges and a
## half-second refresh, never every frame.
func _set_threat(on: bool) -> void:
	var now := Time.get_ticks_msec()
	if on == _threatening and (not on or now < _threat_refresh_msec):
		return
	_threatening = on
	_threat_refresh_msec = now + THREAT_REFRESH_MSEC
	if is_inside_tree():
		EventBus.threat_changed.emit(&"aim", global_position, 1.0 if on else 0.0)

func is_threatening() -> bool:
	return _threatening

# --- turning round -------------------------------------------------------------

func _record_rest() -> void:
	_rest_com = center_of_mass
	for node in _mirrored_nodes():
		_rest[node] = [node.position, node.rotation]

func _mirrored_nodes() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child in get_children():
		if child is CollisionShape2D or child is Sprite2D:
			out.append(child)
		elif child is Area2D:
			for part in child.get_children():
				if part is CollisionShape2D:
					out.append(part)
	return out

func _update_flip() -> void:
	var facing := barrel_direction().x
	if _flip > 0.0 and facing < -FLIP_AT:
		set_flip(true)
	elif _flip < 0.0 and facing > FLIP_AT:
		set_flip(false)

## Mirror about the barrel's axis through the grip. Public for the suite.
func set_flip(mirrored: bool) -> void:
	var side := -1.0 if mirrored else 1.0
	if side == _flip:
		return
	_flip = side
	center_of_mass = Vector2(_rest_com.x, _rest_com.y * side)
	for node in _rest:
		if not is_instance_valid(node):
			continue
		var rest: Array = _rest[node]
		var at: Vector2 = rest[0]
		node.position = Vector2(at.x, at.y * side)
		node.rotation = float(rest[1]) * side
		if node is Sprite2D:
			(node as Sprite2D).flip_v = mirrored
	if _trail:
		_trail_tip = _find_tip()

# --- firing ----------------------------------------------------------------------

func _interval() -> float:
	var gap := fire_interval
	if item_id != &"":
		gap *= Progression.get_modifier(item_id, &"cooldown_mult")
	return maxf(gap, MIN_INTERVAL)

## One shot, if it is in your hand and ready. Returns whether it fired.
##
## Not refused during a hit-stop: a ray query and an impulse are both safe while the server is
## paused (the impulse lands when it resumes), and a click that silently did nothing is the
## worst thing a trigger can do. A held stream does pause for it, because `_physics_process`
## returns first — which reads as the stop it is.
func fire() -> bool:
	if not dragging:
		return false
	var now := Time.get_ticks_msec()
	if not ready_to_fire(now):
		return false
	# A stream keeps its phase: the next shot is due one gap after the last one was *due*, not
	# after the frame that happened to fire it, or every gap rounds up to whole physics frames
	# and an 85 ms gun fires every 100 ms. Within a frame of it, so an idle trigger cannot bank
	# a burst of catch-up shots.
	var gap := int(_interval() * 1000.0)
	var frame := int(1000.0 / float(Engine.physics_ticks_per_second))
	_next_shot_msec = maxi(_next_shot_msec + gap, now + gap - frame)
	_last_shot_msec = now
	var from := muzzle_position()
	var dir := barrel_direction()
	_shoot(from, dir)
	_recoil(dir)
	shots_fired += 1
	_spend_round(now)
	_add_heat(now)
	AudioManager.play(fire_sound, 0.08, fire_volume_db, fire_pitch)
	if item_id != &"":
		EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	return true

## Whether a pull now would fire: the gap since the last shot, a reload, the barrels' speed,
## the heat. Subclasses add their own (a harpoon that is still out).
func ready_to_fire(now: int) -> bool:
	if now < _next_shot_msec:
		return false
	if is_reloading(now):
		return false
	if spin_up > 0.0 and not _spun:
		return false
	if is_overheated(now):
		return false
	return true

## What one pull puts into the world. The three D56 kinds here; a subclass whose shot is a body
## overrides it.
func _shoot(from: Vector2, dir: Vector2) -> void:
	match shot_kind:
		&"water":
			_squirt(from, dir)
		&"bubble":
			_blow(from, dir)
		_:
			_bullets(from, dir)

# --- the magazine --------------------------------------------------------------------------

func rounds_left() -> int:
	if magazine <= 0:
		return -1
	return magazine if _rounds < 0 else _rounds

## Whether it is reloading at `now`. A reload whose time has come is finished here, by the
## clock, so a gun put down mid-reload is loaded when it is picked up without having done any
## work on the desk.
func is_reloading(now: int) -> bool:
	if _reload_until_msec <= 0:
		return false
	if now < _reload_until_msec:
		return true
	_reload_until_msec = 0
	_rounds = magazine
	return false

func _spend_round(now: int) -> void:
	if magazine <= 0:
		return
	_rounds = rounds_left() - 1
	if _rounds > 0:
		return
	var seconds := _reload_seconds()
	_reload_until_msec = now + int(seconds * 1000.0)
	# A break-action opens as it runs dry and throws its cases then.
	if eject_on_reload:
		AudioManager.play(&"reel_stop", 0.05, -6.0, 0.8)
		for i in magazine:
			_eject_case()
	# The sound of it closing, when it is done; the state is the clock's (above).
	get_tree().create_timer(seconds).timeout.connect(_reloaded)

func _reloaded() -> void:
	if not is_inside_tree():
		return
	AudioManager.play(&"clack", 0.05, -8.0, 0.9)

func _reload_seconds() -> float:
	var seconds := reload_time
	if item_id != &"":
		seconds *= Progression.get_modifier(item_id, &"cooldown_mult")
	return maxf(seconds, MIN_INTERVAL)

# --- heat ----------------------------------------------------------------------------------

## The gauge now, cooled by the clock since it was last written.
func heat_level(now: int = -1) -> float:
	if heat_per_shot <= 0.0:
		return 0.0
	if now < 0:
		now = Time.get_ticks_msec()
	return maxf(0.0, _heat - heat_cooling * float(now - _heat_msec) / 1000.0)

func is_overheated(now: int) -> bool:
	return now < _overheat_until_msec

func _add_heat(now: int) -> void:
	if heat_per_shot <= 0.0:
		return
	_heat = heat_level(now) + heat_per_shot
	_heat_msec = now
	if _heat < 1.0:
		return
	_heat = 1.0
	_overheat_until_msec = now + int(overheat_lock * 1000.0)
	AudioManager.play(&"scratch", 0.05, -8.0, 1.4)
	var fx := WorldFX.of(self)
	if fx:
		fx.puff(muzzle_position(), 6, WorldFX.DUST, 55.0, 0.8)

func _bullets(from: Vector2, dir: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var mult := shot_damage_mult()
	var tier := juice_tier
	var fx := WorldFX.of(self)
	var count := maxi(1, pellets)
	var spread := deg_to_rad(spread_degrees)
	for i in count:
		# A cone filled evenly and jittered, so a spread reads as a pattern rather than as
		# nine shots that happened to go the same way.
		var lane := 0.0 if count == 1 else lerpf(-1.0, 1.0, float(i) / float(count - 1))
		var angle := spread * clampf(lane + randf_range(-0.35, 0.35), -1.0, 1.0) if count > 1 \
			else randf_range(-spread, spread)
		var heading := dir.rotated(angle)
		var hit := _cast(space, from, from + heading * shot_range)
		var end: Vector2 = hit.get("position", from + heading * shot_range)
		var body: Object = hit.get("collider")
		if body is RigidBody2D:
			(body as RigidBody2D).apply_central_impulse(heading * shot_force * shove)
			if body is Buddy:
				(body as Buddy).take_impulse(shot_force, item_id, mult, end)
		if fx:
			if i < 3:
				fx.tracer(from, end, _tracer_colour(tier), tracer_time,
					tracer_width + 0.6 * float(tier))
			if not hit.is_empty() and i < 4:
				fx.shot(end, count > 1, tier)
	if fx:
		fx.shot(from, false, mini(tier, 1))
		if shake_pixels > 0.0:
			fx.shake(shake_pixels)
			fx.puff(from, 4, WorldFX.SOOT, 70.0, 0.6)
	if pump_delay > 0.0:
		get_tree().create_timer(pump_delay).timeout.connect(_pump)
	else:
		_eject()

## The authored colour when there is one (the ray gun's green), and the juice tier's otherwise.
func _tracer_colour(tier: int) -> Color:
	if tracer_colour.a > 0.0:
		return tracer_colour.lerp(WorldFX.harm_colour(tier), 0.25 * float(tier))
	return WorldFX.harm_colour(tier) if tier > 0 else WorldFX.TRACER

## A pump or a bolt working: the clack and the case, a beat after the shot.
func _pump() -> void:
	if not is_inside_tree():
		return
	AudioManager.play(&"reel_stop", 0.06, -6.0, 0.7)
	_eject()

func _eject() -> void:
	if not ejects:
		return
	_eject_case()

func _eject_case() -> void:
	var fx := WorldFX.of(self)
	if fx:
		fx.chips(to_global(Vector2(ejector.x, ejector.y * _flip)), WorldFX.GOLD, 1, 150.0)

## The water pistol: a short squirt that scrubs him and pays like the sponge — grime removed
## times `hearts_per_grime_cleaned`, scaled by the item's value multiplier, banked and paid
## as sustained kindness. Kind, so it pushes rather than hurts: the shove is the water.
func _squirt(from: Vector2, dir: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var heading := dir.rotated(randf_range(-1.0, 1.0) * deg_to_rad(spread_degrees))
	var hit := _cast(space, from, from + heading * shot_range)
	var end: Vector2 = hit.get("position", from + heading * shot_range)
	var body: Object = hit.get("collider")
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_impulse(heading * shot_force * shove)
	if body is Buddy:
		var buddy := body as Buddy
		var value := value_multiplier()
		var removed := buddy.grime.clean(squirt_clean) if buddy.grime else 0.0
		_bank((removed * ItemDB.balance.hearts_per_grime_cleaned + squirt_value) * value, end)
	var fx := WorldFX.of(self)
	if fx:
		fx.tracer(from, end, WATER, 0.1, 3.0)
		fx.chips(end, WATER, 3, 110.0)

## The bubble blaster: one bubble, launched along the barrel, that drifts over to him.
func _blow(from: Vector2, dir: Vector2) -> void:
	var bubble := Bubble.new()
	bubble.name = "Bubble"
	bubble.texture = bubble_texture
	bubble.scale = Vector2(2, 2)
	bubble.source = item_id
	bubble.value = bubble_value * value_multiplier()
	bubble.speed = bubble_speed
	bubble.velocity = dir.rotated(randf_range(-1.0, 1.0) * deg_to_rad(spread_degrees)) \
		* bubble_speed * 1.6
	bubble.z_index = 20
	var host := get_parent() if get_parent() else self
	host.add_child(bubble)
	bubble.global_position = from

func _cast(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to, SHOT_MASK, [get_rid()])
	# Point-blank counts: a muzzle pressed into him starts the ray inside his shape.
	query.hit_from_inside = true
	query.collide_with_areas = false
	return space.intersect_ray(query)

## The kick: backwards along the barrel at the muzzle, plus the climb. The recoil node
## (`recoil_mult`) scales all three, and nothing else reads that key — so it is measured in
## the gun suite rather than trusted.
func _recoil(dir: Vector2) -> void:
	var k := recoil_multiplier()
	apply_impulse(-dir * recoil_kick * k, muzzle_position() - global_position)
	apply_torque_impulse(-_flip * recoil_climb * k)
	if climb_per_shot > 0.0:
		_climb = minf(_climb + climb_per_shot * k * randf_range(0.7, 1.3), climb_max)

func recoil_multiplier() -> float:
	if item_id == &"":
		return 1.0
	return Progression.get_modifier(item_id, &"recoil_mult")

## What a shot's impulse is multiplied by, the damage augment included.
func shot_damage_mult() -> float:
	return Progression.damage_mult_for(item_id, shot_mult)

## Kind guns pay no Bones for being thrown at him: Bonehead multiplies the contact impulse by
## this, and zero pays nothing (`Buddy._queue_hit` drops a zero hit). A water pistol bounced
## off his skull is a toy landing on him, not an attack.
func effective_damage_mult() -> float:
	if is_kind_gun():
		return 0.0
	return super.effective_damage_mult()

func register_use() -> void:
	if not is_kind_gun():
		super.register_use()

## The kindness-value multiplier, which on the kind side is what `damage_mult` means
## (FriendlyBase.value_multiplier).
func value_multiplier() -> float:
	if item_id == &"":
		return 1.0
	return Progression.get_modifier(item_id, &"damage_mult")

func _bank(value: float, at: Vector2) -> void:
	if value <= 0.0:
		return
	_banked += value
	_bank_position = at

func _flush() -> void:
	_since_flush = 0.0
	if _banked <= 0.0:
		return
	EventBus.kindness_sustained.emit(item_id, _banked, _bank_position)
	_banked = 0.0

func trail_colour() -> Color:
	return WorldFX.kind_colour(juice_tier) if is_kind_gun() else WorldFX.harm_colour(juice_tier)

func aura_glyph() -> StringName:
	return &"heart" if is_kind_gun() else &"chip"

## One bubble. It drifts toward his middle, rising a little, and pops into a kind act when it
## reaches him — or into nothing after a few seconds, so a desk with nobody on it does not
## fill with bubbles. Physics-ticked so the suite can count on it.
class Bubble extends Sprite2D:
	const LIFETIME := 6.0
	const STEER := 1.8
	const RISE := 12.0
	const COLOUR := Color("ffa6c1")

	var velocity := Vector2.ZERO
	var value := 1.0
	var source := &""
	var speed := 90.0
	var _age := 0.0
	var _buddy: Buddy

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			_pop(false)
			return
		if not is_instance_valid(_buddy):
			_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
		if _buddy:
			if _buddy.get_interaction_rect().has_point(global_position):
				_pop(true)
				return
			var to := (_buddy.global_transform * _buddy.center_of_mass) - global_position
			velocity = velocity.lerp(to.normalized() * speed, clampf(delta * STEER, 0.0, 1.0))
		velocity.y -= RISE * delta
		global_position += velocity * delta

	func _pop(landed: bool) -> void:
		if landed:
			EventBus.kindness_given.emit(source, value, global_position)
		var fx := WorldFX.of(self)
		if fx:
			fx.ring(global_position, 16.0, COLOUR, 0.15, 1.0)
		queue_free()

	func _draw() -> void:
		# Only when the art is missing: a ring in the bubble's colour rather than nothing.
		if texture == null:
			draw_arc(Vector2.ZERO, 4.0, 0.0, TAU, 12, COLOUR, 1.0, false)
