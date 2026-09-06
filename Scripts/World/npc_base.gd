class_name NpcBase
extends BaseDraggable

## Something that walks onto the desk and goes for him by itself.
##
## Every other body in the roster is a thing the player moves: a bat is swung, a grenade is
## thrown, a turret is aimed by being put down. An NPC is the first content that *acts* — it
## finds Bonehead, crosses the desk under its own power, winds up, and hits him while the
## player watches. That is the whole reason it is worth having, and it is also what makes it
## dangerous to the economy, so both halves are written down here.
##
## ## Why an NPC costs Bones, leaves on a timer, and is made permanent with Hearts
##
## Automation is Hearts-priced, everywhere, always (docs/decisions.md D2, restated in D31,
## and again in `TurretBase` for the same reason). *You cannot stop working for your money
## without being kind to him* is the bargain that makes this something other than Interactive
## Buddy with a shop, and a creature that fights for you is the exact shape of content that
## can walk around it. So the category is split down the middle, deliberately:
##
## - The **item** costs Bones. It is a gorilla. Buying it with kindness reads wrong.
## - A **summoned** NPC is temporary. `lifetime_seconds` runs down and it walks off the desk.
##   It banks nothing, accrues nothing offline and is written to no save: its earnings are
##   whatever it lands while somebody is watching. It amplifies the session the player is
##   sitting in — it is not a second idle engine wearing fur.
## - The **capstone** that keeps one around indefinitely costs Hearts, priced by the same
##   rule as every other capstone in the game (`tools/seed_m36_npcs.gd`).
##
## Give this class an offline rate, or take the lifetime off it, and a Bones-priced idle
## engine is exactly what it becomes. The timer is not a nerf; it is the load-bearing part.
##
## ## How it hurts him
##
## Every blow is handed to `Buddy.take_impulse()` — the same door a gunshot, a blast and a
## turret shot use, and the same kind of number the contact solver hands him off a bat
## (docs/decisions.md D7). Damage is measured on the receiver; nothing here decides what a
## hit is worth. The shove that goes with it is a real impulse on his body, exactly as
## `ExplosionUtil` applies one, so what the player sees and what the payout says come from
## the same number rather than from two that can drift apart.
##
## ## What it costs to leave running
##
## The performance budget is a release gate: under 3% CPU idle, under 8% under load. An NPC
## is the first thing in the game with an opinion of its own to run, so it **thinks at 5 Hz**
## (`DECIDE_SECONDS`) and not per frame — a per-frame decision for a four-hornet swarm is 240
## evaluations a second, forever, for a choice that cannot meaningfully change between two
## frames 16 ms apart. Between decisions it steers toward one cached point with one force,
## which is a subtraction and a multiply. Nothing here uses `_process` at all.
##
## ## The roster is data
##
## Four NPCs share this class: a brawler, a thrower, a chaser that grapples and a swarm. What
## differs between them is the numbers below and three switches (`throws_loose_items`,
## `grapple_seconds`, `swarm_count`), the way `FriendlyBase` carries the whole kindness roster
## on three switches. Adding a fifth NPC must stay a `.tres` and a scene (docs/decisions.md
## D8); only a genuinely different *verb* earns a subclass, which is what `NpcGorilla` is.

## How often an NPC re-decides what it is doing. Five times a second: fast enough that it
## reacts to him being picked up and carried away within a walking pace, cheap enough that a
## desk full of them costs nothing measurable over an eight-hour session.
const DECIDE_SECONDS := 0.2

## Focus Mode Off halves the thinking rate as well as the walking speed. The setting means
## "stop moving about", so the thing that decides where to move can afford to be lazier too.
const FOCUS_OFF_TICK_SCALE := 2.0

## How much of its speed an NPC keeps when Focus Mode is Off. Not zero: the standing contract
## for everything that acts on its own is that Off stops it *shouting*, never stops it earning
## (docs/decisions.md D21, and `TurretBase`, which keeps firing). An NPC that could not close
## the distance could not land a blow, so it shambles instead of charging.
const FOCUS_OFF_MOVE_SCALE := 0.3

## Sticky band around `attack_range`. Once in melee an NPC keeps swinging out to 1.4x its
## reach, and only past that does it walk again — without the band it flips between the walk
## and the swing every tick at exactly the boundary, which reads as a stutter rather than as
## an animal.
const RANGE_HYSTERESIS := 1.4

## Floor on the pause between blows, matching `TurretBase.MIN_INTERVAL`'s reasoning: ten
## levels of a 0.94 rate node compounds to 0.54 and an exclusive branch can halve it again,
## and nothing in this game may end up asking for an attack per physics frame.
const MIN_RECOVER_SECONDS := 0.25

## Grapple shakes land on their own clock rather than on the decision tick, because the tick
## slows down under Focus Mode Off and the payout must not.
const GRAPPLE_SHAKE_SECONDS := 0.35
const GRAPPLE_SHAKE_FRACTION := 0.3

## How close to the edge counts as gone, and how long a departure may take before it is over
## regardless. The play area is walled on all four sides (`WorldBounds`), so an NPC cannot
## literally walk off the desk — it walks *at* the edge and is dismissed on arrival. The reach
## has to clear the widest body's half-width or the biggest animal never arrives at all and
## every gorilla leaves by the timeout instead.
const LEAVE_REACH := 90.0
const LEAVE_TIMEOUT := 14.0

## A swarm is one summon, however many bodies arrive. Capped because each body is a full NPC
## with a full NPC's decisions behind it, and a table typo is not allowed to put twenty of
## them on the desk at once.
const MAX_SWARM := 6

## Vertical bias on a blow. A punch straight along the ground slides him into a wall, and the
## wall is where he stops being visible; lifting him makes the hit read and lets the props on
## the desk take part.
const BLOW_LIFT := 0.45

## Sprite scale, matching every other item body: the art is drawn at half the size it is
## shown at, so a whole-number zoom keeps it on the pixel grid.
const ART_SCALE := 2.0

const STATE_IDLE := &"idle"
const STATE_APPROACH := &"approach"
const STATE_ATTACK := &"attack"
const STATE_RECOVER := &"recover"

## Body animation per state. A state with no entry keeps whatever is playing, which is what
## makes a partial art pass survivable — the same rule `BuddyArt` follows.
##
## **`recover` has no entry on purpose.** The swing is a one-shot, and recovery begins the
## instant the blow lands; naming an animation here would cut the attack off after a single
## frame and the tell would be the only part of it anyone ever saw.
const STATE_ANIMATION := {
	&"idle": &"idle",
	&"approach": &"walk",
	&"attack": &"attack",
}

## Played once and stopped. The Aseprite importer marks **every** tag as looping, which is
## right for a walk cycle and wrong for a swing: a looping attack never lets the animal stand
## up again.
const ONE_SHOT: Array[StringName] = [&"windup", &"attack"]

## Where the art is looked for, in that order. Neither has to exist — an NPC with no picture
## is still a working NPC, because a half-finished art pass must leave a playable game.
const FRAMES_PATH := "res://art/src/%s.aseprite"
## A generated walk cycle, as a grid rather than a strip: `rd_advanced_animation__walking`
## returns 8 frames of 48x48 laid out 4 across and 2 down. A slicer that assumes one long
## row finds four frames and half an animal, which is why the layout is a constant here
## rather than inferred from the image's width.
const SHEET_PATH := "res://Assets/sprites/npc/%s_walk.png"
const SHEET_COLUMNS := 4
const SHEET_ROWS := 2
const SPRITE_PATH := "res://Assets/sprites/items/%s.png"

# --- what it is ------------------------------------------------------------

## Seconds on the desk before it leaves. Overridden by the automation capstone, which is the
## upgrade that buys permanence — see `_is_permanent()`.
@export var lifetime_seconds: float = 90.0

## Top speed in world pixels per second, and how hard it corrects toward that speed. A low
## `steer_gain` is what "heavy and slow to turn" actually is: the gorilla keeps travelling
## for a moment after he has moved, and the goose does not.
@export var move_speed: float = 140.0
@export var steer_gain: float = 4.0

## Ignores gravity and steers in both axes. The swarm flies; everything else walks.
@export var flying: bool = false

## Upward speed of a leap, in pixels per second, when the target is above and it is standing
## on something. Zero for anything that cannot jump.
@export var hop_speed: float = 0.0
@export var hop_trigger_height: float = 90.0

## Where it stands relative to him, as a radius it picks a random point in once. Without it
## four hornets converge on one pixel and read as one hornet.
@export var spread_radius: float = 0.0

# --- how it fights ---------------------------------------------------------

## How close it has to be to swing, in world pixels. This is the NPC's identity as much as
## its damage is: a raccoon that throws from 260 away and a goose that has to be on top of
## him are two different animals built from the same numbers.
@export var attack_range: float = 96.0

## The impulse a blow hands him. Damage is `impulse x damage_per_impulse x mult` measured on
## the receiver, so **this is the damage**, and it is clamped there at half a knockout round
## however large it gets.
@export var attack_impulse: float = 3000.0

## Folded into that impulse, exactly as a weapon's multiplier is.
@export var damage_mult: float = 1.0

## The tell. An attack that lands with no wind-up is a number appearing; half a second of
## raised arms is a moment, and it is the only warning the player gets to pick him up.
@export var windup_seconds: float = 0.4

## Seconds from the start of one wind-up to the start of the next, before the rate augment.
@export var attack_period: float = 2.0

## Holds on after a blow lands and shakes him for this long. Zero disables. The hold is
## applied as repeated impulses rather than as a real joint: he *freezes* for the whole
## knockout beat (`Buddy._on_knocked_out`), and a joint pinned to a frozen body is precisely
## the bug his drag guard exists to prevent.
@export var grapple_seconds: float = 0.0

## Picks up whatever the player left lying about and throws that instead of striking. The
## damage then belongs to the thing thrown — a hurled bowling ball pays as a bowling ball,
## which is correct, and is why this needs no damage model of its own.
@export var throws_loose_items: bool = false
@export var throw_reach: float = 320.0
@export var throw_speed: float = 900.0
@export var throw_lift: float = 260.0

## Bodies that arrive per summon, including this one. Above one, the extras are instanced as
## children of this node so that dismissing the summon dismisses the whole flight.
@export var swarm_count: int = 1

var state: StringName = STATE_IDLE

## Resolved once and kept, then re-resolved if it goes stale. A group lookup five times a
## second per body is small and pointless; a node path across a scene boundary is banned
## outright (docs/decisions.md D9) and is what shipped an export crash once already.
var _buddy: Buddy = null

var _age := 0.0
var _since_decide := 0.0
var _target_point := Vector2.ZERO
var _offset := Vector2.ZERO
var _facing := 1.0
## Sticky half of the range hysteresis: true while it is close enough to keep swinging.
var _in_melee := false

var _leaving := false
var _leaving_for := 0.0
var _exit_x := 0.0

## Invalidated whenever the world changes under a swing in progress — the player grabs it,
## its lifetime runs out, it is dismissed. A wind-up is an `await`, and a coroutine that
## resumes into a world that has moved on lands a punch from a creature the player is
## holding in their hand.
var _swing_token := 0

var _grapple_until_msec := 0
var _next_shake_msec := 0

var _capstone_id := &""
var _is_swarm_child := false
var _swarm_pending := false

## The animated half of the art, when there is one. Kept typed so the one-shot and
## change-guard rules below do not have to re-test the node every frame.
var _body: AnimatedSprite2D = null
var _can_flip := false

func _ready() -> void:
	super._ready()
	# An animal that has been thrown across the desk must not carry on walking upside down.
	# Locking rotation is what separates a character from a prop; the prop rules (D25's
	# authored shapes, a centre of mass in the head) are for things that are swung.
	lock_rotation = true
	if flying:
		gravity_scale = 0.0
		# Otherwise a flyer accumulates the whole session's steering and orbits the window.
		linear_damp = 2.0

	if spread_radius > 0.0:
		# Capped under the reach. A body parked at its own spread point while the reach is
		# measured to his centre would sit permanently just out of range of the thing it is
		# standing next to — walking forever and never swinging.
		_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0) \
			* minf(spread_radius, attack_range * 0.6)

	_capstone_id = _find_capstone()
	_swarm_pending = swarm_count > 1 and not _is_swarm_child
	# Staggered, so four hornets hatched in the same frame do not all think on the same one
	# forever after — which is both a visible synchronised twitch and an avoidable spike.
	_since_decide = randf() * DECIDE_SECONDS
	_target_point = global_position

	_build_art()
	_play_state()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_age += delta
	if _leaving:
		_leaving_for += delta

	_shake_grapple()

	_since_decide += delta
	if _since_decide >= _decide_interval():
		_since_decide = 0.0
		_decide()

	_steer()

# --- deciding --------------------------------------------------------------

func _decide_interval() -> float:
	return DECIDE_SECONDS * (FOCUS_OFF_TICK_SCALE if _quiet() else 1.0)

func _decide() -> void:
	if _swarm_pending:
		_swarm_pending = false
		_hatch_swarm()

	if not is_instance_valid(_buddy):
		_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy

	# Asked here rather than every physics frame: a permanent NPC would otherwise put two
	# dictionary lookups through `Progression` sixty times a second for the rest of the
	# session, to answer a question that changes when the player buys something.
	if not _leaving and _age >= lifetime_seconds and not _is_permanent():
		_begin_leaving()

	if _leaving:
		_target_point = Vector2(_exit_x, global_position.y)
		if absf(global_position.x - _exit_x) <= LEAVE_REACH or _leaving_for >= LEAVE_TIMEOUT:
			_despawn()
		return

	# The player has it by the scruff. Everything else is the pin joint's business.
	if dragging:
		_in_melee = false
		_set_state(STATE_IDLE)
		return

	# A swing owns the animal from wind-up to recovery. Re-deciding mid-beat is what turns a
	# telegraphed attack back into a number appearing.
	if state == STATE_ATTACK or state == STATE_RECOVER:
		return

	if not _can_target(_buddy):
		_in_melee = false
		_target_point = global_position
		_set_state(STATE_IDLE)
		return

	_target_point = _buddy.global_position + _offset
	var distance := global_position.distance_to(_buddy.global_position)
	if distance <= attack_range * (RANGE_HYSTERESIS if _in_melee else 1.0):
		_in_melee = true
		_attack()
		return

	_in_melee = false
	_set_state(STATE_APPROACH)
	_maybe_hop()

## Him, if he is there and still standing. A downed buddy is not a target: `take_impulse`
## refuses while he is out, so an NPC that kept swinging through the knockout beat would be
## billing `use:` contract events for blows that cannot land.
func _can_target(buddy: Buddy) -> bool:
	if not is_instance_valid(buddy):
		return false
	return buddy.health == null or not buddy.health.down

# --- moving ----------------------------------------------------------------

## One force toward one cached point. Deliberately dumb: there is no path to find on a desk
## with a floor and four walls, and steering that costs a subtraction is steering that can
## run for eight hours.
##
## No `delta` anywhere in here. A force is integrated over the step by the solver, so scaling
## it by the frame time as well would make the NPC's speed depend on the physics tick rate —
## which Low Power mode changes under it.
func _steer() -> void:
	if dragging or freeze:
		return
	# Planted while winding up and while recovering — an animal that keeps walking through
	# its own swing has no weight.
	if state == STATE_ATTACK or state == STATE_RECOVER:
		return

	var to_target := _target_point - global_position
	var speed := move_speed * (FOCUS_OFF_MOVE_SCALE if _quiet() else 1.0)
	var gain := mass * steer_gain
	if flying:
		if to_target.length() < 4.0:
			return
		var desired := to_target.normalized() * speed
		apply_central_force((desired - linear_velocity) * gain)
		_face(to_target.x)
		return

	# Walkers steer in x only. Vertical force on a body under gravity is a jetpack, and the
	# one legitimate way up is the hop.
	if absf(to_target.x) < 6.0:
		return
	var desired_x := signf(to_target.x) * speed
	apply_central_force(Vector2((desired_x - linear_velocity.x) * gain, 0.0))
	_face(to_target.x)

func _maybe_hop() -> void:
	if flying or hop_speed <= 0.0 or _buddy == null:
		return
	if _buddy.global_position.y > global_position.y - hop_trigger_height:
		return
	# Only from something solid. Testing the vertical speed rather than the contacts keeps
	# this off `contact_monitor`, which an NPC otherwise has no use for at all.
	if absf(linear_velocity.y) > 40.0:
		return
	apply_central_impulse(Vector2(0.0, -hop_speed * mass))

func _face(direction_x: float) -> void:
	if absf(direction_x) < 1.0:
		return
	_facing = signf(direction_x)
	if _can_flip:
		sprite.set(&"flip_h", _facing < 0.0)

# --- attacking -------------------------------------------------------------

## Wind up, land the blow, recover. The wind-up is an `await` rather than a countdown in the
## decision tick because it has to line up with an animation whose length is authored in
## Aseprite, and a 5 Hz tick would quantise a 0.4 s tell to the wrong side of half a frame.
func _attack() -> void:
	var token := _swing_token
	var tree := get_tree()
	# Turned before the wind-up, not during the walk: steering stops for the whole swing, so
	# an animal that did not face him here would spend the tell facing the way it arrived.
	if is_instance_valid(_buddy):
		_face(_buddy.global_position.x - global_position.x)
	_set_state(STATE_ATTACK)
	_play(&"windup")
	# The tell has a voice. Heavier animals are lower: pitch by mass, so a gorilla's roar
	# and a hornet's are the same synthesised breath an octave apart.
	AudioManager.play(&"npc_roar", 0.12, -8.0, clampf(2.4 / maxf(sqrt(mass), 0.8), 0.6, 1.8))
	# And a face: the buddy's expression watches the tell.
	EventBus.threat_changed.emit(&"windup", global_position, 1.0)
	# Bound methods, not awaits: an animal binned mid-swing would have its coroutine resumed
	# on a freed instance, which errors before any guard inside it runs. A Callable bound to
	# the node is dropped with it, and the token still catches every other way the swing can
	# stop belonging to the world it started in.
	tree.create_timer(windup_seconds).timeout.connect(_swing.bind(token))

func _swing(token: int) -> void:
	if not _swing_still_valid(token):
		return
	_play(&"attack")
	if is_instance_valid(_buddy) and _land_blow(_buddy):
		# Only a blow that connected is billed. A contract that counts uses of the gorilla is
		# counting attacks on him, not swings at the air where he was.
		EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	EventBus.threat_changed.emit(&"windup", global_position, 0.0)

	_set_state(STATE_RECOVER)
	get_tree().create_timer(_recover_seconds()).timeout.connect(_recovered.bind(token))

func _recovered(token: int) -> void:
	if not _swing_still_valid(token):
		return
	_set_state(STATE_IDLE)

## Whether the swing that started this still belongs to the world it started in.
func _swing_still_valid(token: int) -> bool:
	if is_queued_for_deletion():
		return false
	return token == _swing_token and not dragging and not _leaving

## The pause after a blow. `attack_period` is measured wind-up to wind-up, so the tell is
## paid for out of the cycle rather than added to it — otherwise a long telegraph would make
## a slow animal slower still, and the rate node would buy less on the animals that need it.
func _recover_seconds() -> float:
	var gap := attack_period
	if item_id != &"":
		# The same `cooldown_mult` key a turret's fire-rate node and a cursor power's rate
		# node use, so "the gap gets shorter" reads identically wherever it is bought.
		gap *= Progression.get_modifier(item_id, &"cooldown_mult")
	return maxf(gap - windup_seconds, MIN_RECOVER_SECONDS)

## The blow itself. Returns true only if it actually connected.
##
## Overridden by anything whose attack is a different *verb* rather than a different number —
## see `NpcGorilla`, whose slam is a shockwave through the desk.
func _land_blow(buddy: Buddy) -> bool:
	if not _can_target(buddy):
		return false
	if throws_loose_items and _hurl_loose_item(buddy):
		return true

	var to_him := buddy.global_position - global_position
	if to_him.length() > attack_range * RANGE_HYSTERESIS:
		return false
	var dir := to_him.normalized() if to_him.length() > 1.0 else Vector2(_facing, 0.0)
	dir = (dir + Vector2.UP * BLOW_LIFT).normalized()

	buddy.apply_impulse(dir * attack_impulse, Vector2.ZERO)
	buddy.take_impulse(attack_impulse, item_id, effective_damage_mult(),
		buddy.global_position - dir * 18.0)

	if grapple_seconds > 0.0:
		var now := Time.get_ticks_msec()
		_grapple_until_msec = now + int(grapple_seconds * 1000.0)
		_next_shake_msec = now + int(GRAPPLE_SHAKE_SECONDS * 1000.0)
	return true

## Throws whatever the player left on the desk. Sets the prop's velocity outright, as
## `Trampoline` does for the same reason: what happens next is a real physics throw, and the
## damage is then measured off the contact like any other thrown thing.
func _hurl_loose_item(buddy: Buddy) -> bool:
	var best: RigidBody2D = null
	var best_distance := throw_reach
	for node in get_tree().get_nodes_in_group(GROUP_SPAWNED):
		var body := node as RigidBody2D
		if body == null or body == self or body is NpcBase:
			continue
		if body.freeze:
			continue
		# Never out of the player's hand. Fighting the drag joint would look like a bug and
		# feel like one.
		if body is BaseDraggable and (body as BaseDraggable).dragging:
			continue
		var distance := global_position.distance_to(body.global_position)
		if distance < best_distance:
			best = body
			best_distance = distance
	if best == null:
		return false

	var to_him := buddy.global_position - best.global_position
	if to_him.length() < 1.0:
		return false
	best.linear_velocity = to_him.normalized() * throw_speed + Vector2.UP * throw_lift
	best.angular_velocity = randf_range(-8.0, 8.0)
	_face(to_him.x)
	return true

## The hold, paid out as discrete shakes on a fixed clock.
##
## **The floor is not a nicety.** `Buddy.take_impulse` discards anything under
## `balance.min_damage_impulse` outright, so a grapple that divided its strength into small
## enough pieces would be a mechanic that visibly does something and silently pays nothing.
func _shake_grapple() -> void:
	if _grapple_until_msec == 0:
		return
	var now := Time.get_ticks_msec()
	if now >= _grapple_until_msec or dragging or not is_instance_valid(_buddy) \
			or not _can_target(_buddy):
		_grapple_until_msec = 0
		return
	if now < _next_shake_msec:
		return
	_next_shake_msec = now + int(GRAPPLE_SHAKE_SECONDS * 1000.0)

	var shake := maxf(attack_impulse * GRAPPLE_SHAKE_FRACTION,
		ItemDB.balance.min_damage_impulse * 1.05)
	var to_me := global_position - _buddy.global_position
	var dir := to_me.normalized() if to_me.length() > 1.0 else Vector2.UP
	# Dragged toward the thing holding him and rattled sideways, so a grapple reads as being
	# shaken rather than as being hit repeatedly from the same angle.
	dir = (dir + Vector2(randf_range(-0.6, 0.6), -0.25)).normalized()
	_buddy.apply_impulse(dir * shake, Vector2.ZERO)
	_buddy.take_impulse(shake, item_id, effective_damage_mult(), _buddy.global_position)

## What Bonehead multiplies the impulse by, read the way a weapon and a turret both read it.
func effective_damage_mult() -> float:
	return Progression.damage_mult_for(item_id, damage_mult)

# --- arriving and leaving --------------------------------------------------

## The extras of a swarm, instanced from the item's own scene rather than duplicated.
##
## `duplicate()` copies `@export` node references as raw pointers into the original's
## children, so a duplicated hornet would flip the *first* hornet's sprite and be dragged by
## the first hornet's grab region. Instancing the PackedScene resolves them properly.
##
## They are children so that dismissing the summon — right-click, the clear-desk button, the
## item limit, a Reincarnation — takes the whole flight with it. `top_level` keeps their
## physics independent of the parent's transform. They are deliberately not registered with
## `ItemSpawner`: a swarm is one summon against the item limit, not four.
func _hatch_swarm() -> void:
	var item := ItemDB.get_item(item_id)
	if item == null or item.scene == null:
		push_warning("NpcBase: '%s' wants a swarm but has no scene to make one from" % item_id)
		return
	for i in mini(swarm_count, MAX_SWARM) - 1:
		var instance := item.scene.instantiate()
		var copy := instance as NpcBase
		if copy == null:
			push_error("NpcBase: '%s' scene is not an NpcBase" % item_id)
			instance.free()
			return
		copy.item_id = item_id
		copy.name = "%s%d" % [name, i + 1]
		copy._is_swarm_child = true
		copy.top_level = true
		copy.add_to_group(GROUP_SPAWNED)
		add_child(copy)
		copy.global_position = global_position + Vector2(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * maxf(spread_radius, 24.0)

## Its time is up: it stops fighting and walks at the nearest edge.
func _begin_leaving() -> void:
	if _leaving:
		return
	_leaving = true
	_leaving_for = 0.0
	# The swing in flight is abandoned rather than allowed to land. Otherwise the last thing
	# a departing NPC does is hit him from off screen.
	_swing_token += 1
	_grapple_until_msec = 0
	_in_melee = false
	var width := get_viewport().get_visible_rect().size.x
	_exit_x = 0.0 if global_position.x < width * 0.5 else width
	_set_state(STATE_APPROACH)

## Whether the capstone that keeps one around has been bought and left switched on.
##
## Read live rather than resolved at spawn: buying the Enclosure while the gorilla is already
## on the desk should keep *that* gorilla, and switching it off should let the next one go
## home. The augment id is resolved once, because `ItemDB.augments_for` builds a new array on
## every call and this is asked five times a second.
func _is_permanent() -> bool:
	if _capstone_id == &"":
		return false
	return Progression.augment_level(_capstone_id) > 0 \
		and Progression.is_automation_enabled(_capstone_id)

func _find_capstone() -> StringName:
	if item_id == &"":
		return &""
	for node in ItemDB.augments_for(item_id):
		if node.is_automation:
			return node.id
	return &""

func _despawn() -> void:
	_swing_token += 1
	EventBus.item_despawned.emit(self)
	queue_free()

## Picking one up cancels whatever it was in the middle of. Without this a gorilla grabbed
## mid-wind-up lands its punch from the player's own cursor.
func _start_drag() -> void:
	super._start_drag()
	_swing_token += 1
	_grapple_until_msec = 0
	_in_melee = false
	_set_state(STATE_IDLE)

# --- art -------------------------------------------------------------------

## Built here rather than baked into the scene, because the code ships before the pictures do
## and both halves have to work on their own: an art pass that adds `gorilla.aseprite` needs
## no scene rebuild, and a build with neither file is a working, invisible gorilla rather
## than a crash on spawn.
func _build_art() -> void:
	if sprite == null or sprite.get_parent() != self:
		_make_art()
	# Resolved from whatever ended up there — built here, or authored in the scene by a later
	# art pass. Both have to work, and the one-shot rule has to be applied either way.
	_body = sprite as AnimatedSprite2D
	_can_flip = sprite is Sprite2D or sprite is AnimatedSprite2D
	if _body != null and _body.sprite_frames != null:
		_unloop(_body.sprite_frames)

func _make_art() -> void:
	var frames := _load_frames()
	if frames != null:
		var animated := AnimatedSprite2D.new()
		# Named explicitly. A node that comes out as @AnimatedSprite2D@24 cannot be found by
		# a test and cannot be read in the remote scene tree.
		animated.name = "Art"
		animated.sprite_frames = frames
		animated.scale = Vector2(ART_SCALE, ART_SCALE)
		add_child(animated)
		sprite = animated
		return

	var path := SPRITE_PATH % item_id
	if not ResourceLoader.exists(path):
		push_warning("NpcBase: no art for '%s' at %s or %s"
			% [item_id, FRAMES_PATH % item_id, path])
		return
	var still := Sprite2D.new()
	still.name = "Art"
	still.texture = ResourceLoader.load(path)
	still.scale = Vector2(ART_SCALE, ART_SCALE)
	add_child(still)
	sprite = still

## A walk cycle sliced out of a generated spritesheet, when there is no hand-authored
## `.aseprite` to prefer. Built rather than imported because the sheet is a plain PNG: the
## Aseprite Wizard route needs an Aseprite source, and the generator does not produce one.
##
## Only `walk` comes from here. Everything else the state machine asks for falls back to
## whatever `walk` is showing, which is the same "a missing animation is a pose that does
## not change, never a crash" rule the buddy's own art driver follows.
func _load_sheet_frames() -> SpriteFrames:
	var path := SHEET_PATH % item_id
	if item_id == &"" or not ResourceLoader.exists(path):
		return null
	var sheet := ResourceLoader.load(path) as Texture2D
	if sheet == null:
		return null
	var frame_size := Vector2i(sheet.get_width() / SHEET_COLUMNS, sheet.get_height() / SHEET_ROWS)
	if frame_size.x <= 0 or frame_size.y <= 0:
		push_warning("NpcBase: %s is too small to slice into %dx%d"
			% [path, SHEET_COLUMNS, SHEET_ROWS])
		return null

	var frames := SpriteFrames.new()
	frames.add_animation(&"walk")
	frames.set_animation_speed(&"walk", 10.0)
	for index in SHEET_COLUMNS * SHEET_ROWS:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(
			Vector2(index % SHEET_COLUMNS, index / SHEET_COLUMNS) * Vector2(frame_size),
			Vector2(frame_size))
		frames.add_frame(&"walk", atlas)
	frames.remove_animation(&"default")
	return frames

func _load_frames() -> SpriteFrames:
	var path := FRAMES_PATH % item_id
	if item_id == &"" or not ResourceLoader.exists(path):
		return _load_sheet_frames()
	var frames := ResourceLoader.load(path) as SpriteFrames
	if frames == null:
		push_warning("NpcBase: %s exists but did not import as SpriteFrames" % path)
	return frames

func _unloop(frames: SpriteFrames) -> void:
	for animation in ONE_SHOT:
		if frames.has_animation(animation):
			frames.set_animation_loop(animation, false)

func _set_state(value: StringName) -> void:
	if state == value:
		return
	state = value
	_play_state()

func _play_state() -> void:
	_play(STATE_ANIMATION.get(state, &""))

## Missing animations are skipped rather than treated as an error: most of the inventory is
## unbuilt at any given moment, and a partial art pass has to leave a playable game.
func _play(animation: StringName) -> void:
	if _body == null or animation == &"" or _body.sprite_frames == null:
		return
	if not _body.sprite_frames.has_animation(animation):
		return
	# `play()` restarts from frame 0. Called unguarded from a decision that runs five times a
	# second, a walk cycle would sit on its first frame forever.
	if _body.animation == animation and _body.is_playing():
		return
	_body.play(animation)

## Whether the game has been told to stop moving about (docs/decisions.md D21).
func _quiet() -> bool:
	return Settings.focus_intensity == Settings.Intensity.OFF
