class_name IdleBrain
extends Node

## What Bonehead does when nobody is watching.
##
## Leave him alone long enough and he goes and finds a toy: he bounces on the trampoline,
## climbs into the hot tub, shuffles about in front of the boombox, eats the pizza someone
## left on the desk. It is the third pillar — an idle desktop that still looks *alive* —
## paying out as a small trickle of Hearts on top of whatever the automations are earning.
##
## **A component, not part of the buddy.** It sits beside `MoodComponent` and
## `GrimeComponent` in spirit but outside him in the tree: it finds him through the `buddy`
## group and drives him with forces, so nothing here needs a line in `buddy.gd` and nothing
## here can break him if it is removed. Toys are found through the `interactive` group for
## the same reason (docs/decisions.md D9).
##
## **He is a rigid body, so he is moved by pushing him.** Nothing in this file writes
## `global_position`, `linear_velocity` or `rotation` — the drag joint, the contact-impulse
## damage model and every collision assumption in the game are built on him being simulated
## rather than placed, and one teleport is enough to break all three. It does hold
## `lock_rotation` while it drives him, the way `NpcBase` does for its animals: a character,
## not a prop. The lock comes off the moment he stands down, so a throw still tumbles.
##
## ### The one rule about money
##
## **The brain pays only where the toy pays nothing for his presence.** A hot tub already
## pays `hearts_per_second_touching` while he is in it; a pizza already pays
## `hearts_per_contact` when he touches it; a sponge already pays for the grime it takes
## off. In all of those the brain's whole contribution is getting him there, and it emits
## nothing at all — paying "for the visit" on top would be a second payment for the same
## touch, which is the easiest bug in this feature and a money printer. It pays only for
## bouncing on a trampoline (which pays nothing for anything, ever) and for dancing at a
## placed generator (whose rate is paid whether he is there or not), because those are the
## two cases where nobody else is paying him.
##
## ### Why it pays on `kindness_sustained` and never on `kindness_given`
##
## A bounce looks like an act, and `kindness_given` is the signal for acts — but this act
## happens with nobody at the keyboard, and all three things that separate the two signals
## are about the player being present (docs/decisions.md D14, docs/economy.md):
##
## - the **combo** is a reward for repeated acts, and a routine that fires every second
##   inside a 1.5 s window would sit at the 3x ceiling for as long as the desk is empty;
## - **contracts count acts**, and a "be kind 150 times" daily should not complete itself
##   overnight — the same reason a boombox's flush is not a contract event;
## - **Dollars are earned by being present** (D31), so an unattended routine must not pay
##   `dollars_per_kind_act`.
##
## Everything else about the pipeline is identical, so mood, augments, mastery and Marrow
## all apply exactly as they do to a sponge.

const GROUP_IDLE_BRAIN := &"idle_brain"

# --- when he starts --------------------------------------------------------

## How long the player must leave him alone before he goes and finds something to do.
##
## Twenty-five seconds is longer than any pause *inside* active play — lining up a throw,
## reading a tooltip, choosing an augment, watching the whole two-second knockout beat — so
## he never wanders off under a player who is merely thinking, and short enough that a trip
## to the kettle finds him already busy when you get back.
const IDLE_SECONDS := 25.0

## How long he waits after being *offered* something, rather than after being left alone.
##
## Putting a toy on the desk used to call `_disturb()` like any other interaction, which
## reset the full twenty-five seconds — so "spawn a beach ball and watch him play with it",
## the most obvious thing a player will try, was the one sequence guaranteed to show nothing.
## The owner tried exactly that and reported the feature as broken. It was not broken; it was
## unreachable.
##
## Six seconds because it has to outlast the throw: a ball is usually spawned in the air and
## dropped, and him setting off before it has landed reads as him walking to where it is not.
const INVITED_SECONDS := 6.0

## How often he re-plans. Half a hertz.
##
## The search walks the `interactive` group, which is at most `item_limit` bodies plus him,
## so this is a few dozen comparisons twice a second-and-a-half against a 3% CPU budget held
## for eight hours. Steering runs in `_physics_process`, which is switched **off** unless he
## is actually going somewhere — when he has nothing to do this timer is the entire cost of
## the feature. It is also the payout cadence: one floating number every two seconds is
## quieter than automation's one a second, which is right for something nobody is watching.
const THINK_SECONDS := 2.0

# --- how long he stays -----------------------------------------------------

## How long one toy holds his attention, how long he mooches afterwards, and how long before
## he will pick the same toy again. Together these are the AFK income limiter: with a single
## toy on the desk he earns for twenty seconds in every eighty, and with several he rotates
## between them at roughly two thirds duty. **Leaving ten toys out therefore raises how
## *often* he is busy and never how much he earns at once** — he can only play with one
## thing at a time, which is what stops the desk becoming a multiplier.
const DWELL_SECONDS := 20.0
const WANDER_SECONDS := 6.0
const TOY_COOLDOWN := 60.0

## Given up on: he has stopped getting closer for this long. Better than a flat travel
## timeout, which has to be sized for the worst case — walking pace across a 3440px ultrawide
## is half a minute — and then wastes all of it on a toy sitting on a shelf he cannot climb.
const STALL_SECONDS := 8.0
## How much closer counts as progress. Anything smaller and a body jittering against a wall
## reads as walking.
const PROGRESS_EPSILON := 16.0

## How long the toy he was at when he was knocked out is off the menu.
##
## Bouncing used to pay Bones through the ordinary damage path as well as Hearts through this
## one — since D64 billed the mat's landings, about 17.6 damage a second and a knockout every
## twenty-five seconds or so, a Bones engine nobody bought. His own play is no longer a hit at
## all (D70, `Buddy.is_own_play`), so he cannot knock himself out on a toy; what can still put
## him down while he plays is somebody else's — a turret, an animal — and then five minutes off
## that toy reads correctly: he was flattened there, and gives it a wide berth for a while.
const KNOCKOUT_COOLDOWN := 300.0

## Above this many remembered toys, expired entries are swept. Items are spawned and binned
## all session and instance ids are never reused, so without a sweep this grows for every toy
## that has ever been on the desk — the same unbounded-dictionary leak the buddy's own hit
## cooldowns are swept for.
const COOLDOWN_SWEEP_AT := 32

# --- how he chooses --------------------------------------------------------

## Two toys within this of each other are "both right here", and the better-paying one wins.
## Nearest-first on its own would be twitchy; best-paying-first would walk him past the
## trampoline at his feet to reach the massage chair across the desk, every single time.
const TIE_BAND := 160.0

## How much slop counts as touching, on top of the two bodies' own rects.
const ARRIVE_SLACK := 20.0

# --- how he moves ----------------------------------------------------------

## Proportional gain on the gap between his current speed and his walking speed, on top of
## friction paid for up front (docs/plan-movement-hitboxes.md §2).
##
## Godot's default body friction is 1.0, so the floor resists a sliding body with about
## `mass * gravity` — near 3,000 for a 3-mass skeleton at the project's 980. The old gain of
## 30 was there to beat that, and a bare P-controller against a constant disturbance never
## reaches its target: he cruised at 84 px/s of the 117 the code derived, and the 10,500 N
## kick at every start tipped him onto a corner. Now `_walk` adds `direction * m * g` as
## feed-forward, so steady state is push = friction at zero gap and he cruises at the full
## walking speed, and this term only has to close the gap.
const WALK_GAIN := 12.0
## The push is clamped at this many g's worth of force. 2.5 bounds the reversal kick at
## 7,350 N (it was 21,000) and still starts him inside a tenth of a second.
const WALK_PUSH_G := 2.5
## The same clamp in the air, where there is no floor to pay: under his own weight, so wall
## friction (1.0) can never hold him up the side of the thing he hopped at.
const AIR_PUSH_G := 0.5

## A climb is the exception, not the gait. Clearance above a toy's top edge that one aims for
## — 12 px, not 28: the 28 was compensating for a rect that put his feet 32 px above where
## they are, and every landing was a 703-impulse fall — and the ceiling on one: 500 px/s is a
## rise of 128 px, his own height, so a missed climb lands at the fall floor rather than over
## it (docs/plan-movement-hitboxes.md §3).
const CLIMB_CLEARANCE := 12.0
const MAX_CLIMB_SPEED := 500.0
## Shortest gap between climb attempts, so a stall is four or five tries rather than fourteen;
## and the most per trip, because a bounded count is a stronger guarantee than a timer against
## a toy pinned somewhere he can never reach.
const CLIMB_INTERVAL := 1.5
const MAX_CLIMBS_PER_TRIP := 3
## How long "not reached" has to persist while playing before he tries a climb — the same
## "walking has stopped working" rule travelling already applies through its stall.
const CLIMB_PATIENCE := 1.5
## The lean, as a multiple of his own weight: over his friction (1.0), under his friction plus
## the lightest toy he walks to (the 0.3-mass rubber duck adds 0.1), so he creeps the last
## twenty pixels and stops against anything.
const LEAN_G := 1.05
## He does not set off lying on his side. Rotation is locked for the trip.
const START_UPRIGHT_DEG := 20.0

## The side-to-side shuffle he does at a boombox. Horizontal only, deliberately: a hopping
## dance lands him above `min_damage_impulse` every bar, and dancing must not hurt.
const JIG_SPEED := 60.0
const JIG_INTERVAL := 0.45

## Seconds between knocks of a ball. Slow enough to read as him playing with it rather than
## juggling, and long enough that the ball has come back down before he hits it again.
const BOP_INTERVAL := 0.9
## How much faster than the toy's own threshold he knocks it, so a ball that is already
## drifting still clears the check and a rounding error never eats a payout.
const BOP_SPEED_MARGIN := 1.35
## Floor on that, for a toy that asks for very little: a one-pixel nudge is not a bop.
const BOP_MIN_SPEED := 260.0

## Speed above which he counts as having actually moved during a think window. The brain-paid
## routines are paid for *doing* something, so a skeleton wedged under a trampoline earns
## nothing — the kindness-side twin of the damage cooldown and the sponge's clean-return.
const MOTION_FLOOR := 24.0

## How far from a wall he turns round while mooching.
const WANDER_MARGIN := 120.0

# --- what he earns ---------------------------------------------------------

## Kindness value per second while he is bouncing or dancing, before mood, augments, mastery
## and Marrow — the same pipeline every friendly item runs through.
##
## Anchored **below the boombox's own 0.6/s placed rate** (docs/economy.md), so buying the
## generator always beats hoping he plays with it, and at the duty cycles above a lone toy
## yields around 0.1 value/s — roughly 360/hour against the 2,160/hour the boombox pays for
## simply existing, and against 39/s (140,000/hour) from a single maxed Hearts capstone at
## `0.5 + cost/1500` over thirty levels. That is the ratio this number exists to hold: the
## kindness ladder must never collapse into "put a trampoline down and leave".
const PLAY_VALUE_PER_SECOND := 0.4

## What a weapon-side ball is worth as a destination: above nothing, and below every toy at
## the same distance that pays (see `_appeal`).
const WEAPON_BALL_APPEAL := 0.01

# --- routines --------------------------------------------------------------

## Plain ints rather than an enum, following `ItemData`: an enum used as a parameter type is
## a distinct type across script boundaries, so a caller passing `IdleBrain.Routine.SOAK`
## could not satisfy a `Routine` parameter declared elsewhere.
const ROUTINE_NONE := 0
const ROUTINE_BOUNCE := 1   ## trampoline — pays nothing on its own, so the brain pays
const ROUTINE_PLAY := 2     ## placed generator — pays whether he is there or not, so the brain pays
const ROUTINE_SOAK := 3     ## hot tub, massage chair — the toy pays per second of contact
const ROUTINE_SCRUB := 4    ## sponge — the toy pays for grime actually removed
const ROUTINE_NIBBLE := 5   ## pizza — the toy pays once, on contact
## Balls — the toy pays on contact, but only above a closing speed. He makes it himself.
##
## These used to return `ROUTINE_NONE` on the reasoning that "he cannot throw himself", so
## walking to one would be a wasted trip. True, and the conclusion was wrong: it left the
## tennis ball, the baseball, the kite and the party popper inert whenever the player was not
## personally throwing them, which is most of a game that is meant to run unattended. Seven
## of the eleven items in the Play tab did nothing for him at all.
##
## He does not throw it. He knocks it up off himself, and it pays on the way off — the toy's
## own check is the ball's speed, and an impulse gives it that in the frame it is still
## touching him. Then it falls back on him and pays again. Keepy-uppies.
const ROUTINE_BOP := 6
## A fidget toy (D57): something worked by hand rather than sat in or knocked about. The toy
## says what a second of it is worth (`idle_appeal()`) and does the using itself
## (`idle_use(buddy)`, on the think tick), paying through its own sustained trickle — so the
## brain gets him there and pays nothing, exactly as for a hot tub. Asked of the toy by its
## methods rather than its class, so a harm-side toy with the same two methods is walked to
## and used the same way.
const ROUTINE_FIDGET := 7

const PHASE_WATCHING := &"watching"
const PHASE_TRAVELLING := &"travelling"
const PHASE_PLAYING := &"playing"
const PHASE_WANDERING := &"wandering"

var _buddy: Buddy
var _target: Node2D
var _target_id: StringName = &""
var _routine := ROUTINE_NONE

var _phase: StringName = PHASE_WATCHING
var _phase_seconds := 0.0
var _stalled_seconds := 0.0
## Seconds spent "not reached" while playing, and climbs so far this trip — the two gates that
## make a climb the exception (docs/plan-movement-hitboxes.md §2).
var _lost_seconds := 0.0
var _climbs_this_trip := 0
var _best_distance := INF
var _moved_since_think := false

var _last_disturbance_msec := 0
## How long he must be left alone before starting. `IDLE_SECONDS` normally; `INVITED_SECONDS`
## when the player has just put a toy down for him (which is an offer, not an arrival).
var _wait_seconds := IDLE_SECONDS
## The toy just offered, and until when its own arrival is part of the offer. The shop drops a
## toy from the middle of the window, which is where he stands: the ball lands on his head and
## pays a catch, or a bowling ball lands a hit — and both read as the player arriving, so the
## offer that had just shortened the wait to six seconds put it straight back to twenty-five.
## "Spawn a ball and watch him play with it", again (D60).
var _offer_id: StringName = &""
var _offer_until_msec := 0
var _cooldowns: Dictionary = {}   ## toy instance id -> earliest msec he will go back

var _banked := 0.0
var _bank_position := Vector2.ZERO
## Everything the brain itself has paid, in kindness value, for the life of this node. The
## brain and the toy attribute to the same id, so without this nothing outside can tell whose
## payment a Heart was — and "never both" is the one rule about money this file keeps.
var paid_value := 0.0

var _gravity := 980.0
var _climb_timer := 0.0
var _jig_timer := 0.0
var _bop_timer := 0.0
var _wander_dir := 1.0

## Builds, names and installs the brain in one line, so `main.gd` gains exactly one call.
## Named explicitly because a node that comes out as `@Node@31` is invisible to a test and
## unreadable in the remote scene tree.
static func install(host: Node) -> IdleBrain:
	var brain := IdleBrain.new()
	brain.name = "IdleBrain"
	host.add_child(brain)
	return brain

func _ready() -> void:
	add_to_group(GROUP_IDLE_BRAIN)
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	_last_disturbance_msec = Time.get_ticks_msec()

	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kindness_given.connect(_on_kindness_given)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)
	EventBus.item_spawned.connect(_on_item_spawned)
	EventBus.item_despawned.connect(_on_item_despawned)
	EventBus.focus_mode_changed.connect(_on_focus_mode_changed)

	var timer := Timer.new()
	timer.name = "ThinkTimer"
	timer.wait_time = THINK_SECONDS
	timer.timeout.connect(_think)
	add_child(timer)
	timer.start()

	set_physics_process(false)

## Banked kindness is paid on the way out, whatever the exit — the same reason `FriendlyBase`
## flushes in `_exit_tree`. A prestige wipe or a scene change otherwise swallows up to one
## think window of Hearts.
func _exit_tree() -> void:
	_flush()
	if is_instance_valid(_buddy):
		_buddy.lock_rotation = false
		_buddy.end_own_play(true)

# --- the loop --------------------------------------------------------------

func _think() -> void:
	if not _resolve_buddy():
		return
	# Polled as well as taken from the bus: `buddy_state_changed(&"dragged")` fires once, so a
	# player who picks him up and holds him for a minute stamps the clock a minute ago.
	if _buddy.dragging or _is_busy_state():
		_disturb()
		return

	_phase_seconds += THINK_SECONDS
	if _phase == PHASE_WATCHING:
		_consider_starting()
	elif _phase == PHASE_TRAVELLING:
		_tick_travel()
	elif _phase == PHASE_PLAYING:
		_tick_play()
	elif _phase == PHASE_WANDERING:
		if _phase_seconds >= WANDER_SECONDS:
			_enter(PHASE_WATCHING)

func _consider_starting() -> void:
	if Time.get_ticks_msec() - _last_disturbance_msec < int(_wait_seconds * 1000.0):
		return
	# Rotation is locked for the trip, so setting off from his side would walk him across the
	# desk on his face. Nothing rights him but the out-of-bounds rescue; he waits.
	if absf(wrapf(_buddy.rotation, -PI, PI)) > deg_to_rad(START_UPRIGHT_DEG):
		return
	var pick := _choose_toy()
	if pick == null:
		return
	_target = pick
	_target_id = (pick as BaseDraggable).item_id
	_routine = _routine_for(pick as BaseDraggable)
	# Focus Mode Off is the promise that a player in a meeting can stop the desktop moving
	# *without giving up the income* (D21), so he skips the walk and is simply already there.
	_enter(PHASE_PLAYING if _focus_off() else PHASE_TRAVELLING)

func _tick_travel() -> void:
	if not is_instance_valid(_target):
		_finish(false)
		return
	var distance := _buddy.global_position.distance_to(_target.global_position)
	if distance < _best_distance - PROGRESS_EPSILON:
		_best_distance = distance
		_stalled_seconds = 0.0
		return
	_stalled_seconds += THINK_SECONDS
	if _stalled_seconds >= STALL_SECONDS:
		_finish(true)

func _tick_play() -> void:
	if not is_instance_valid(_target):
		_finish(false)
		return
	if _brain_pays(_routine) and (_focus_off() or _moved_since_think):
		_bank(PLAY_VALUE_PER_SECOND * THINK_SECONDS * _value_multiplier(),
			_buddy.global_position)
	_moved_since_think = false
	_flush()
	# A fidget toy is used, not sat in: on each tick he is at it, the toy does what he does
	# with it and pays for that itself — so this is still a routine the brain pays nothing for.
	if _routine == ROUTINE_FIDGET and (_focus_off() or _touching_target()):
		_target.call(&"idle_use", _buddy)
	# At Focus Off he is simply there and touches nothing (D21, D36), and every other kind toy
	# pays only for touch — so it is asked to pay for his presence instead, as itself (D70). The
	# brain still pays nothing it did not do. Food can be eaten by it, which ends the routine.
	elif _focus_off() and not _brain_pays(_routine) and not _in_contact():
		var friendly := _target as FriendlyBase
		if friendly:
			friendly.pay_presence(_buddy, THINK_SECONDS)
			if _phase != PHASE_PLAYING:
				return
	if _phase_seconds >= DWELL_SECONDS:
		_finish(true)

# --- moving him ------------------------------------------------------------

## Steering. Runs only while he is going somewhere and never when Focus Mode is Off, so the
## per-frame cost of this feature is zero for the whole of a session spent playing normally.
func _physics_process(delta: float) -> void:
	if _buddy == null or _phase == PHASE_WATCHING:
		return
	if _buddy.freeze or _buddy.dragging:
		# Picked up mid-stride: the stride ends this frame, not when the bob decays.
		if _buddy.art:
			_buddy.art.stop_travelling()
		return
	if _buddy.linear_velocity.length() > MOTION_FLOOR:
		_moved_since_think = true
	_climb_timer -= delta
	_jig_timer -= delta
	_bop_timer -= delta

	if _phase == PHASE_WANDERING:
		_walk(_wander_direction())
		return
	if not is_instance_valid(_target):
		return

	var reached := _touching_target()
	var direction := signf(_target.global_position.x - _buddy.global_position.x)
	if _phase == PHASE_TRAVELLING:
		if reached:
			_enter(PHASE_PLAYING)
		else:
			_walk(direction)
			# Only when walking has stopped working: a climb is a hop, and a hopping walk is
			# not a walk. `_climb` has its own gates on top of the stall.
			if _stalled_seconds > 0.0:
				_climb()
		return

	# A soak is sat *in* (D70). Once the toy has him — hopping in, sitting, or climbing out — it
	# is the toy's to move him, and the brain does not steer. Beside it, on his feet, he asks to
	# be let in; the toy hops him over its edge and pins him in the seat.
	if _routine == ROUTINE_SOAK:
		var seat := _target as FriendlyBase
		if seat and seat.is_hosting():
			_lost_seconds = 0.0
			return
		if seat and reached and _climb_timer <= 0.0 and _climbs_this_trip < MAX_CLIMBS_PER_TRIP \
				and _buddy.is_grounded():
			_climb_timer = CLIMB_INTERVAL
			_climbs_this_trip += 1
			if seat.take_in(_buddy):
				return
	# Playing. The steer never stops, so a skeleton who rolls out of the hot tub climbs back
	# in rather than sitting beside it earning nothing for the rest of his dwell — but with
	# the same patience the travelling branch has: walk first, and climb only once walking
	# has visibly stopped working.
	if not reached:
		_lost_seconds += delta
		_walk(direction)
		if _lost_seconds >= CLIMB_PATIENCE:
			_climb()
		return
	_lost_seconds = 0.0
	if _routine == ROUTINE_PLAY:
		_jig()
	elif not _in_contact():
		# "Reached" fires a little before real contact, and the toy pays only on real
		# contact. The last twenty pixels are a lean, not a walk.
		_lean(direction)
	elif _routine == ROUTINE_BOUNCE:
		# The mat does the work; this is only the shove that gets him going again once a
		# bounce has died out. The brain pays for the bouncing, in Hearts; the landings are his
		# own play and bill nothing (D70).
		_climb(true)
	elif _routine == ROUTINE_BOP:
		_bop()

## Pushed through his middle, bounded, with friction paid for up front. Central, because
## rotation is locked while the brain drives him: the old shove "at his feet" was aimed 32 px
## above them by a rect half his real size, and a 3x-friction push there tipped him onto a
## corner at every start. Feed-forward of `direction * m * g` (Godot's default friction of
## 1.0) plus a gentle proportional term means steady state is push = friction at zero gap, so
## he reaches the walking speed the code derives instead of settling 30% under it, and the
## clamp bounds the reversal kick when he crosses a toy's centre.
func _walk(direction: float) -> void:
	if is_zero_approx(direction):
		return
	# Tell his art which way he is going, every tick he is walking. He is still walking when
	# he is already at top speed — that is precisely when he is walking hardest — and
	# reporting travel only on the frames that happened to need force made the bob stutter at
	# exactly the moment it should have been steadiest.
	if _buddy.art:
		var top := _walk_speed()
		var effort := 1.0 if top <= 0.0 else clampf(absf(_buddy.linear_velocity.x) / top, 0.35, 1.0)
		_buddy.art.travel(direction, effort)
	var weight := _buddy.mass * _gravity
	var gap := direction * _walk_speed() - _buddy.linear_velocity.x
	# The feed-forward pays the floor's friction, and in the air there is no floor. Worse, the
	# full push pressed into the side of whatever he had just hopped at is a normal force of
	# over twice his weight, and friction against it held him up the side of a 40 px box for
	# the whole stall — every climb at anything with a vertical face failed that way (D60).
	# Airborne, the push is a nudge under his own weight: he slides off a wall rather than
	# hanging on it, and still has the air control a climb needs to get over the top.
	var grounded := _buddy.is_grounded()
	var limit := (WALK_PUSH_G if grounded else AIR_PUSH_G) * weight
	var feed := direction * weight if grounded else 0.0
	var push := clampf(feed + gap * _buddy.mass * WALK_GAIN, -limit, limit)
	_buddy.apply_central_force(Vector2(push, 0.0))

## The last twenty pixels. With his real rect, "reached" fires a little before contact, and
## `FriendlyBase` pays only on real collision — so he leans in: a push just over his own
## friction and under his friction plus the lightest toy he walks to, so he creeps and stops
## against anything, including a hot tub or a toy pinned on a wall.
func _lean(direction: float) -> void:
	if is_zero_approx(direction):
		return
	if _buddy.art:
		_buddy.art.travel(direction, 0.35)
	# Grounded only, for the reason `_walk` gives: a lean over his own weight against a toy's
	# side while he is off the floor is friction enough to hang him on it.
	var lean := LEAN_G if _buddy.is_grounded() else AIR_PUSH_G
	_buddy.apply_central_force(Vector2(direction * _buddy.mass * _gravity * lean, 0.0))

## Top walking speed, derived rather than picked: a body arriving at `min_damage_impulse`
## divided by its own mass is, by definition, the fastest one whose contact cannot register
## as a hit. So he can walk into a trampoline, a hot tub or the wall without any of it paying
## out — and if either the threshold or his mass is ever retuned this follows, where a
## hard-coded speed would quietly become an exploit.
func _walk_speed() -> float:
	return ItemDB.balance.min_damage_impulse / maxf(_buddy.mass, 0.01)

## One attempt at getting on top of whatever he is walking into. `v = sqrt(2 g h)` is the
## speed that just clears a rise of `h`, measured from his own feet to the toy's top edge —
## so the same line steps over a sponge and climbs into a hot tub without a table of heights.
##
## The exception, not the gait, so it is gated five ways: the interval; standing on something
## (a *contact*, from the buddy's own normals — a velocity test re-fired at the apex of any
## hop); pressed against something, which is what "walking has stopped working" looks like
## from here; a bounded count per trip; and only when the toy's top is actually above his
## feet, because a hop cannot help with a beanbag that is not. The trampoline routine passes
## `minimum_hop`: standing on the mat, the smallest hop is the shove that restarts a bounce.
func _climb(minimum_hop: bool = false) -> void:
	if _climb_timer > 0.0 or not is_instance_valid(_target):
		return
	if not _buddy.is_grounded():
		return
	if not minimum_hop:
		if _climbs_this_trip >= MAX_CLIMBS_PER_TRIP:
			return
		if absf(_buddy.linear_velocity.x) >= MOTION_FLOOR:
			return
	var feet := _buddy.get_interaction_rect().end.y
	var top := _rect_of(_target).position.y
	var rise := feet - top
	if rise <= 0.0 and not minimum_hop:
		return
	_climb_timer = CLIMB_INTERVAL
	_climbs_this_trip += 1
	var speed := minf(sqrt(2.0 * _gravity * (maxf(rise, 0.0) + CLIMB_CLEARANCE)), MAX_CLIMB_SPEED)
	_buddy.apply_central_impulse(Vector2(0.0, -_buddy.mass * speed))

## The dance. A shuffle rather than a hop, and never *into* the generator: steering him at a
## boombox would push it across the desk all night.
func _jig() -> void:
	if _jig_timer > 0.0:
		return
	_jig_timer = JIG_INTERVAL
	_wander_dir = -_wander_dir
	_buddy.apply_central_impulse(Vector2(_wander_dir * _buddy.mass * JIG_SPEED, 0.0))

## Knock the ball up off himself.
##
## The toy's own rule is that `hearts_per_contact` pays only above `min_contact_speed`, and
## it measures **the ball's** speed, not his. So the impulse pays in the frame it is applied,
## while the ball is still touching him — and again when it comes back down on him. He never
## has to throw anything, which is just as well.
##
## Aimed as `mass * (wanted - current)` rather than as a fixed shove: that is a hit rather
## than a nudge, so the result is the speed asked for whether the ball was sitting still or
## already rolling. A fixed impulse on a ball drifting downward can land under the threshold
## and pay nothing, which looks exactly like the feature not working.
##
## The ball's velocity is never assigned directly. Same rule as the buddy: everything here is
## simulated, and a body that gets its velocity written stops colliding the way the rest of
## the game assumes.
func _bop() -> void:
	if _bop_timer > 0.0 or not is_instance_valid(_target):
		return
	var ball := _target as RigidBody2D
	if ball == null:
		return
	_bop_timer = BOP_INTERVAL
	var friendly := _target as FriendlyBase
	var needed := friendly.min_contact_speed if friendly else 0.0
	var speed := maxf(needed * BOP_SPEED_MARGIN, BOP_MIN_SPEED)
	# Up, and a little back over him, so it comes down on him instead of beside him.
	var toward := signf(_buddy.global_position.x - ball.global_position.x)
	var wanted := Vector2(speed * 0.18 * toward, -speed)
	ball.apply_central_impulse((wanted - ball.linear_velocity) * ball.mass)
	# He heads it: a small hop, so the knock reads as him doing something rather than the
	# ball deciding to leave.
	_climb(true)

## Mooching. Turns round before the wall so he does not spend the whole wander leaning on it.
func _wander_direction() -> float:
	var rect := get_viewport().get_visible_rect()
	var x := _buddy.global_position.x
	if x < rect.position.x + WANDER_MARGIN:
		_wander_dir = 1.0
	elif x > rect.end.x - WANDER_MARGIN:
		_wander_dir = -1.0
	return _wander_dir

# --- choosing a toy --------------------------------------------------------

## Nearest wins; toys inside one `TIE_BAND` of each other are a tie and the better-paying one
## takes it. One pass, no sort, no allocation — this runs every think tick forever.
func _choose_toy() -> Node2D:
	var now := Time.get_ticks_msec()
	var here := _buddy.global_position
	var best: Node2D = null
	var best_band := 1 << 30
	var best_appeal := 0.0
	var desk := _arena()
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		var body := node as BaseDraggable
		# He is in the `interactive` group himself, and a toy in the player's hand is not on
		# offer.
		if body == null or body == _buddy or body.dragging:
			continue
		# Nor is one outside the walls: he walked into the wall at it, stalled eight seconds,
		# gave up, and tried again every cooldown (AI audit F).
		if desk.has_area() and not desk.has_point(body.global_position):
			continue
		if now < int(_cooldowns.get(body.get_instance_id(), 0)):
			continue
		var routine := _routine_for(body)
		if routine == ROUTINE_NONE:
			continue
		# A toy that would pay him nothing right now is not a destination — which is how a
		# sponge stops being interesting the moment he is clean, with no special case.
		var appeal := _appeal(body, routine)
		if appeal <= 0.0:
			continue
		var band := int(here.distance_to(body.global_position) / TIE_BAND)
		if band > best_band or (band == best_band and appeal <= best_appeal):
			continue
		best = body
		best_band = band
		best_appeal = appeal
	return best

## The desk his walls enclose (`WorldBounds.arena`), or no rect at all where there are no walls
## (D70). Asked of the walls rather than the viewport: a headless suite builds its own floor out
## past a 64x64 root, which is why the first version of this filter, on the visible rect, took
## loop_check's whole desk off the menu and was reverted. The walls in his own viewport, found by
## group, never by path.
func _arena() -> Rect2:
	for node in get_tree().get_nodes_in_group(WorldBounds.GROUP):
		var walls := node as WorldBounds
		if walls and walls.get_viewport() == get_viewport():
			return walls.arena()
	return Rect2()

## What he would do with it, read off the switches the item already declares rather than off
## its id — so a new friendly item is still a `.tres` and a scene (docs/decisions.md D8).
func _routine_for(body: BaseDraggable) -> int:
	if body is Trampoline:
		return ROUTINE_BOUNCE
	if body.has_method(&"idle_use"):
		return ROUTINE_FIDGET
	var friendly := body as FriendlyBase
	if friendly == null:
		# A ball that is not a kind item is still a ball. The bowling ball sits in the Play tab
		# and is a `WeaponBase`, so it pays **Bones** off the contact impulse rather than Hearts
		# (the beach ball was one too, until D64 made it a catch) — which is a payout, and
		# knocking one about is the most obvious thing in the world to do with it. He is a
		# skeleton; a bowling ball landing on him is the game.
		var toy := ItemDB.get_item(body.item_id)
		if body is WeaponBase and toy and toy.category == ItemData.CATEGORY_TOY:
			return ROUTINE_BOP
		return ROUTINE_NONE
	var item := ItemDB.get_item(body.item_id)
	# The whole kind half, not one drawer of it. This read `category != CATEGORY_FRIENDLY`
	# while Friendly was the only kind category there was, so the moment M3.7 split comfort,
	# food and ambience out of it, every hot tub and every plate of food would have become
	# invisible to him — and the twenty new leisure items would have arrived dead.
	if item == null or not item.is_kind():
		return ROUTINE_NONE
	# A duster or a towel pays while it touches him, exactly as a beanbag does — but it is
	# the player's to hold. Reading the switch alone would send him over to sit in it.
	if friendly.handheld:
		return ROUTINE_NONE
	# A ball that only pays above a closing speed. He cannot throw, but he can knock it up
	# off himself, which is the same thing as far as the toy's own check is concerned.
	if friendly.min_contact_speed > 0.0:
		return ROUTINE_BOP if friendly.hearts_per_contact > 0.0 else ROUTINE_NONE
	# Scrub before soak: the sponge now pays a touching trickle as well as its grime bonus,
	# and read in the other order he would sit in it like a beanbag.
	if friendly.cleans_grime:
		return ROUTINE_SCRUB
	if friendly.hearts_per_second_touching > 0.0:
		return ROUTINE_SOAK
	# Food is eaten. A toy that pays for contact and is not used up is played with: the rubber duck
	# fell through to here and he sat and ate it, over and over (AI audit G). He knocks it about
	# instead, which is what its contact pays for.
	if friendly.hearts_per_contact > 0.0:
		return ROUTINE_NIBBLE if friendly.consume_on_use else ROUTINE_BOP
	if friendly.hearts_per_second_placed > 0.0:
		return ROUTINE_PLAY
	return ROUTINE_NONE

## True only where nothing else is paying him for being there. See the header: this is the
## whole of the double-payment guard, and it is a property of the routine rather than a flag
## anyone has to remember to set.
func _brain_pays(routine: int) -> bool:
	return routine == ROUTINE_BOUNCE or routine == ROUTINE_PLAY

## Roughly what a second of it is worth, used only to break a distance tie — so it can be
## approximate, and is deliberately in kindness value rather than Hearts (no mood, no
## augments) because every candidate would be multiplied by the same ones anyway.
func _appeal(body: BaseDraggable, routine: int) -> float:
	if routine == ROUTINE_BOUNCE or routine == ROUTINE_PLAY:
		return PLAY_VALUE_PER_SECOND
	if routine == ROUTINE_FIDGET:
		return float(body.call(&"idle_appeal"))
	var friendly := body as FriendlyBase
	if friendly == null:
		# A weapon-side ball — the bowling ball, and the beach ball until D64. It was quoted as
		# zero, and `_choose_toy` skips anything worth zero, so the two balls `_routine_for` exists
		# to bring into play were never once walked to (D60). Measured, a bop does not pay for them
		# either: it lifts the ball a hand's height beside him rather than dropping it on him. So
		# he plays with one for its own sake — the least appealing thing on the desk, which
		# anything within `TIE_BAND` of it that pays him beats.
		return WEAPON_BALL_APPEAL if routine == ROUTINE_BOP else 0.0
	if routine == ROUTINE_SOAK:
		return friendly.hearts_per_second_touching
	if routine == ROUTINE_SCRUB:
		var b := ItemDB.balance
		var grime: float = _buddy.grime.value if _buddy.grime else 0.0
		return b.sponge_clean_rate * b.hearts_per_grime_cleaned * grime
	if routine == ROUTINE_NIBBLE:
		return friendly.hearts_per_contact / maxf(friendly.contact_cooldown, 0.1)
	if routine == ROUTINE_BOP:
		# Paced by the bop, not by the toy's cooldown — he cannot hit it faster than he
		# swings, so quoting the toy's rate would make a ball look better than it plays.
		return friendly.hearts_per_contact \
			/ maxf(friendly.contact_cooldown, BOP_INTERVAL)
	return 0.0

## The kindness-value multiplier, read the same way `FriendlyBase.value_multiplier()` reads
## it: an item's own value node should improve what he earns playing with it, or upgrading a
## trampoline would do nothing for the half of its life spent unattended.
func _value_multiplier() -> float:
	if _target_id == &"":
		return 1.0
	return Progression.get_modifier(_target_id, &"damage_mult")

# --- being interrupted -----------------------------------------------------

## Anything the player does to him ends the routine on the spot.
func _disturb() -> void:
	_last_disturbance_msec = Time.get_ticks_msec()
	# Back to the full wait. An arrival cancels an outstanding offer: if the player drops a
	# ball and then starts hitting him, they are playing with him, not leaving him to it.
	_wait_seconds = IDLE_SECONDS
	_offer_id = &""
	# The player is here, so what happens to him from now on is theirs, even if he is still
	# bouncing on after a routine that had already ended (D70).
	if is_instance_valid(_buddy):
		_buddy.end_own_play(true)
	if _phase != PHASE_WATCHING:
		_stand_down()

func _on_damage_dealt(info: HitInfo) -> void:
	# Three exemptions, all of them damage that nobody's hand caused. A trampoline landing is
	# a contact impulse like any other, and treating the toy he is playing with as the player
	# arriving would make bouncing the one routine he can never finish; `&"world"` is the
	# floor he comes down on after a climb.
	#
	# The third is the one that matters most, because without it the whole feature was dead:
	# a turret and an angry goose fire on their own schedule forever, so **one turret on the
	# desk meant the idle timer was reset every couple of seconds for the rest of the
	# session** and he never reached the twenty-five seconds a routine needs to start. The
	# player who bought automation to watch him potter about got the opposite.
	if info.source_id == &"world" or _is_current_toy(info.source_id) or _is_offer(info.source_id):
		return
	if _is_autonomous(info.source_id):
		return
	_disturb()

## Damage from something that acts by itself is not somebody arriving. Asked of the data
## rather than of a list of ids here, so a turret added next month is covered by the seed
## tool that writes it and never by an edit to this file.
func _is_autonomous(source_id: StringName) -> bool:
	var item := ItemDB.get_item(source_id)
	return item != null and item.is_autonomous

func _on_kindness_given(source_id: StringName, _value: float, _world_pos: Vector2) -> void:
	# The toy he is playing with paying him is not somebody arriving, and nor is the toy just
	# offered landing on him. Anything else is — a pet is the clearest "I am here" in the game.
	if _is_current_toy(source_id) or _is_offer(source_id):
		return
	_disturb()

func _on_buddy_state_changed(state: StringName) -> void:
	if state == &"knockout" and is_instance_valid(_target):
		_cool(_target, KNOCKOUT_COOLDOWN)
	if state == &"dragged" or _is_knockout_state(state):
		_disturb()

## Spawning something means a hand on the mouse. Despawning does not — the pizza he just ate
## despawns itself, and treating that as the player would interrupt him with his own dinner.
## Putting a toy down is not the player arriving — it is the player offering him something.
##
## Treated as a *shortened* wait rather than a reset: the clock is backdated so only
## `INVITED_SECONDS` remain, instead of the full `IDLE_SECONDS`. Anything he cannot use
## (a bat, a grenade, a turret) is still an arrival, because that is the player picking up a
## tool rather than giving him a thing.
##
## He is not interrupted if he is already busy. Dropping a second ball next to a buddy who is
## happily bouncing on a trampoline should not march him across the desk.
func _on_item_spawned(item: Node2D) -> void:
	var body := item as BaseDraggable
	if body == null or _routine_for(body) == ROUTINE_NONE:
		_disturb()
		return
	# Busy with something already: leave him to it. Dropping a second ball beside a buddy
	# happily bouncing on a trampoline should not march him across the desk.
	if _phase == PHASE_TRAVELLING or _phase == PHASE_PLAYING:
		return
	# Mooching counts as free. He has finished with something and is wandering with nothing
	# to do, so a toy arriving is exactly what he is waiting for — stand him down to watching
	# so the new thing is considered, rather than making him mooch out the remaining seconds.
	if _phase != PHASE_WATCHING:
		_stand_down()
	# The threshold moves, not the timestamp. Backdating the clock instead underflows in the
	# first twenty-five seconds of a session — `Time.get_ticks_msec()` is still smaller than
	# the head start, it clamps to zero, and the offer silently does nothing at exactly the
	# moment a new player is most likely to be trying it.
	_last_disturbance_msec = Time.get_ticks_msec()
	_wait_seconds = INVITED_SECONDS
	# For as long as he is being given to wait, what the toy does on arrival is the offer.
	_offer_id = body.item_id
	_offer_until_msec = _last_disturbance_msec + int(INVITED_SECONDS * 1000.0)

func _on_item_despawned(item: Node2D) -> void:
	if item == _target:
		_finish(false)

## Off stops him moving and keeps him earning; switching back on gives him his legs again.
## Neither may wait for the current dwell to run out — and neither may *restart* it, or a
## player toggling the setting could hold him on the best-paying toy on the desk forever.
func _on_focus_mode_changed(_intensity: int) -> void:
	set_physics_process(_phase != PHASE_WATCHING and not _focus_off())

## The brain's phase moved, with the routine and toy in force from here. The expression brain
## reads this — the whole Shimeji layer was invisible because he played `idle` throughout.
signal phase_changed(phase: StringName, routine: int, target_id: StringName)
## A routine ended and why: `done` (the dwell ran out), `stalled` (gave up getting there),
## `toy_gone` (it despawned under him), `disturbed` (the player arrived).
signal routine_ended(reason: StringName)

## How long since the player last did anything to him. The expression brain's "welcome
## back" and yawn both read it rather than keeping a second clock.
func seconds_since_disturbance() -> float:
	return float(Time.get_ticks_msec() - _last_disturbance_msec) / 1000.0

func _stand_down() -> void:
	_flush()
	# The player arrived: from here on what happens to him is theirs.
	if is_instance_valid(_buddy):
		_buddy.end_own_play(true)
	_let_out()
	# Deliberately no cooldown: he was interrupted, not bored, and a toy he never got to play
	# with should still be there when the player leaves again.
	_target = null
	_target_id = &""
	_routine = ROUTINE_NONE
	routine_ended.emit(&"disturbed")
	_enter(PHASE_WATCHING)

func _finish(cool: bool) -> void:
	_flush()
	# Still his own play until he comes to rest: a trampoline goes on throwing him after the dwell.
	_let_out()
	if is_instance_valid(_buddy):
		_buddy.end_own_play(false)
	var reason: StringName = &"toy_gone"
	if cool:
		reason = &"stalled" if _phase == PHASE_TRAVELLING else &"done"
	if cool and is_instance_valid(_target):
		_cool(_target, TOY_COOLDOWN)
	_target = null
	_target_id = &""
	_routine = ROUTINE_NONE
	routine_ended.emit(reason)
	_enter(PHASE_WANDERING)

## Out of whatever he is sitting in, with a hop over its side (D70). Nothing if he is not in it.
func _let_out() -> void:
	var seat := _target as FriendlyBase
	if seat and is_instance_valid(seat) and seat.is_hosting():
		seat.let_out(true)

func _enter(phase: StringName) -> void:
	_phase = phase
	_phase_seconds = 0.0
	_stalled_seconds = 0.0
	_lost_seconds = 0.0
	_climbs_this_trip = 0
	_best_distance = INF
	_moved_since_think = false
	_climb_timer = 0.0
	_jig_timer = 0.0
	set_physics_process(phase != PHASE_WATCHING and not _focus_off())
	if is_instance_valid(_buddy):
		# A character, not a prop, for exactly as long as the brain is driving him. Unlocked
		# the moment he stands down — synchronously on pick-up, through `dragged` →
		# `_disturb` → here — so the pin joint never swings a locked body and a throw still
		# tumbles exactly as it did.
		_buddy.lock_rotation = phase != PHASE_WATCHING
		# Whatever he does on the way there and at it is his own play, and is not a hit (D70).
		if phase == PHASE_TRAVELLING or phase == PHASE_PLAYING:
			_buddy.begin_own_play(_target)
		if phase == PHASE_WATCHING and _buddy.art:
			_buddy.art.stop_travelling()
	phase_changed.emit(phase, _routine, _target_id)

func _cool(toy: Node2D, seconds: float) -> void:
	var now := Time.get_ticks_msec()
	if _cooldowns.size() >= COOLDOWN_SWEEP_AT:
		for key in _cooldowns.keys():
			if now >= int(_cooldowns[key]):
				_cooldowns.erase(key)
	_cooldowns[toy.get_instance_id()] = now + int(seconds * 1000.0)

# --- paying ----------------------------------------------------------------

func _bank(value: float, at: Vector2) -> void:
	if value <= 0.0:
		return
	_banked += value
	_bank_position = at

func _flush() -> void:
	if _banked <= 0.0:
		return
	# Attributed to the toy, so its mastery, its augments and its tree all apply — and so the
	# floating number appears over the thing he is playing with.
	paid_value += _banked
	EventBus.kindness_sustained.emit(_target_id, _banked, _bank_position)
	_banked = 0.0

# --- helpers ---------------------------------------------------------------

## Resolved lazily rather than in `_ready()`: the brain is installed by `main.gd` and the
## buddy joins the group in his own `_ready()`, so the order is not something this file gets
## to assume. Found by group, never by path or by name (D9).
func _resolve_buddy() -> bool:
	if is_instance_valid(_buddy):
		return true
	_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	return _buddy != null

## Whether an id belongs to the toy he is playing with. The empty check is load-bearing: an
## item scene that forgot its id attributes as `&""`, and without this every such hit would
## be silently exempt from interrupting him for as long as he had no target.
func _is_current_toy(source_id: StringName) -> bool:
	return _target_id != &"" and source_id == _target_id

## Whether an id is the toy just put down for him, still arriving.
func _is_offer(source_id: StringName) -> bool:
	return _offer_id != &"" and source_id == _offer_id and Time.get_ticks_msec() < _offer_until_msec

func _is_busy_state() -> bool:
	return _buddy.state == &"dragged" or _is_knockout_state(_buddy.state)

func _is_knockout_state(state: StringName) -> bool:
	return state == &"knockout" or state == &"pile" or state == &"reassemble"

func _focus_off() -> bool:
	return Settings.focus_intensity == Settings.Intensity.OFF

## Close enough to be on it, in it or against it. The two rects overlapping is the honest
## question — a radius would have to be sized for the biggest prop in the roster and would
## then call him "arrived" a body's width from a sponge.
func _touching_target() -> bool:
	if not is_instance_valid(_target):
		return false
	if _rect_of(_target).grow(ARRIVE_SLACK).intersects(_buddy.get_interaction_rect()):
		return true
	# Or real contact, which is what the toy pays on — so "reached" and "paid" can never
	# disagree about whether he is there.
	return _in_contact()

## Actually touching it, as the physics server sees it — the same question
## `FriendlyBase._touching_buddy()` asks before it pays.
func _in_contact() -> bool:
	return is_instance_valid(_target) and _target in _buddy.get_colliding_bodies()

func _rect_of(node: Node2D) -> Rect2:
	var body := node as BaseDraggable
	if body:
		return body.get_interaction_rect()
	return Rect2(node.global_position, Vector2.ZERO)

# --- inspection ------------------------------------------------------------

## What he is doing, for the F3 overlay and for `loop_check`.
func phase_name() -> StringName:
	return _phase

## The toy he is playing with, or &"" for none.
func target_id() -> StringName:
	return _target_id

func current_routine() -> int:
	return _routine

## Brings the idle threshold forward so a test does not have to wait twenty-five real
## seconds, and `think_now()` runs a tick without waiting for the timer. Both change only
## *when* the ordinary path runs, never what it does.
func pretend_idle() -> void:
	_last_disturbance_msec = Time.get_ticks_msec() - int((IDLE_SECONDS + 1.0) * 1000.0)

func think_now() -> void:
	_think()
