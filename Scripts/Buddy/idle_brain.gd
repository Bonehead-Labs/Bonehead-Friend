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
## rather than placed, and one teleport is enough to break all three.
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

## How long the toy that knocked him out is off the menu.
##
## Bouncing pays Bones through the ordinary damage path as well as Hearts through this one —
## the trampoline throws him at the mat and the mat is a contact impulse like any other — and
## left alone that compounds into a knockout roughly every twenty-five seconds of bouncing,
## which is a real Bones engine rather than a garnish. Five minutes bounds it to one round in
## six, and it reads correctly too: he knocks himself silly and then gives the thing a wide
## berth for a while.
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

## Proportional gain on the gap between his current speed and his walking speed.
##
## It has to beat friction before he moves at all: Godot's default body friction is 1.0, so
## the floor resists a sliding body with about `mass * gravity` — near 3,000 for a 3-mass
## skeleton at the project's 980 — and a polite nudge does nothing whatsoever. At a full gap
## this reaches roughly three times that, which starts him inside a fifth of a second, and it
## settles on its own because the push shrinks as the gap closes.
const WALK_GAIN := 30.0

## Vertical speed below which he counts as standing on something. Only used to decide whether
## a climb would do anything; nothing here needs to know what he is standing *on*.
const GROUNDED_SPEED := 50.0

## Clearance above a toy's top edge that a climb aims for, and the ceiling on one.
## 640 px/s is a rise of about 209 px, which is taller than anything in the roster.
const CLIMB_CLEARANCE := 28.0
const MAX_CLIMB_SPEED := 640.0
## Shortest gap between climb attempts, so a stall is four or five tries rather than sixty.
const CLIMB_INTERVAL := 0.55

## The side-to-side shuffle he does at a boombox. Horizontal only, deliberately: a hopping
## dance lands him above `min_damage_impulse` every bar, and dancing must not hurt.
const JIG_SPEED := 60.0
const JIG_INTERVAL := 0.45

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
var _best_distance := INF
var _moved_since_think := false

var _last_disturbance_msec := 0
var _cooldowns: Dictionary = {}   ## toy instance id -> earliest msec he will go back

var _banked := 0.0
var _bank_position := Vector2.ZERO

var _gravity := 980.0
var _climb_timer := 0.0
var _jig_timer := 0.0
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
	if Time.get_ticks_msec() - _last_disturbance_msec < int(IDLE_SECONDS * 1000.0):
		return
	var pick := _choose_toy()
	if pick == null:
		return
	_target = pick
	_target_id = (pick as BaseDraggable).item_id
	_routine = _routine_for(pick as BaseDraggable)
	# Focus Mode Off is the promise that a player in a meeting can stop the desktop moving
	# *without giving up the income* (D21), so he skips the walk and is simply already there.
	# The one thing it cannot deliver is the Bones a real bounce would have earned, because
	# that comes from a physical impact that did not happen.
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
	if _phase_seconds >= DWELL_SECONDS:
		_finish(true)

# --- moving him ------------------------------------------------------------

## Steering. Runs only while he is going somewhere and never when Focus Mode is Off, so the
## per-frame cost of this feature is zero for the whole of a session spent playing normally.
func _physics_process(delta: float) -> void:
	if _buddy == null or _phase == PHASE_WATCHING or _buddy.freeze or _buddy.dragging:
		return
	if _buddy.linear_velocity.length() > MOTION_FLOOR:
		_moved_since_think = true
	_climb_timer -= delta
	_jig_timer -= delta

	if _phase == PHASE_WANDERING:
		_walk(_wander_direction())
		return
	if not is_instance_valid(_target):
		return

	var reached := _touching_target()
	if _phase == PHASE_TRAVELLING:
		if reached:
			_enter(PHASE_PLAYING)
		else:
			_walk(signf(_target.global_position.x - _buddy.global_position.x))
			# Only when walking has stopped working: a climb costs him a landing, and a
			# hopping walk would put one impact above `min_damage_impulse` under him every
			# stride — a Bones firehose dressed up as locomotion.
			if _stalled_seconds > 0.0:
				_climb()
		return

	# Playing. The steer never stops, so a skeleton who rolls out of the hot tub climbs back
	# in rather than sitting beside it earning nothing for the rest of his dwell.
	if not reached:
		_walk(signf(_target.global_position.x - _buddy.global_position.x))
		_climb()
	elif _routine == ROUTINE_BOUNCE:
		# The mat does the work; this is only the shove that gets him going again once a
		# bounce has died out.
		_climb()
	elif _routine == ROUTINE_PLAY:
		_jig()

## Pushed at his feet rather than through his middle: a horizontal shove at the centre of a
## box standing on a floor is a torque before it is a translation, and the first thing it does
## is tip him onto his face.
func _walk(direction: float) -> void:
	if is_zero_approx(direction):
		return
	# Tell his art which way he is going before the early-out below. He is still walking when
	# he is already at top speed and needs no push this tick — that is precisely when he is
	# walking hardest — and reporting travel only on the frames that happened to need force
	# made the bob stutter at exactly the moment it should have been steadiest.
	if _buddy.art:
		var top := _walk_speed()
		var effort := 1.0 if top <= 0.0 else clampf(absf(_buddy.linear_velocity.x) / top, 0.35, 1.0)
		_buddy.art.travel(direction, effort)
	var gap := direction * _walk_speed() - _buddy.linear_velocity.x
	if absf(gap) < 1.0:
		return
	_buddy.apply_force(Vector2(gap * _buddy.mass * WALK_GAIN, 0.0), _foot_offset())

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
func _climb() -> void:
	if _climb_timer > 0.0 or not is_instance_valid(_target):
		return
	if absf(_buddy.linear_velocity.y) > GROUNDED_SPEED:
		return
	_climb_timer = CLIMB_INTERVAL
	var feet := _buddy.get_interaction_rect().end.y
	var top := _rect_of(_target).position.y
	var rise := maxf(0.0, feet - top) + CLIMB_CLEARANCE
	var speed := minf(sqrt(2.0 * _gravity * rise), MAX_CLIMB_SPEED)
	_buddy.apply_central_impulse(Vector2(0.0, -_buddy.mass * speed))

## The dance. A shuffle rather than a hop, and never *into* the generator: steering him at a
## boombox would push it across the desk all night.
func _jig() -> void:
	if _jig_timer > 0.0:
		return
	_jig_timer = JIG_INTERVAL
	_wander_dir = -_wander_dir
	_buddy.apply_central_impulse(Vector2(_wander_dir * _buddy.mass * JIG_SPEED, 0.0))

## Mooching. Turns round before the wall so he does not spend the whole wander leaning on it.
func _wander_direction() -> float:
	var rect := get_viewport().get_visible_rect()
	var x := _buddy.global_position.x
	if x < rect.position.x + WANDER_MARGIN:
		_wander_dir = 1.0
	elif x > rect.end.x - WANDER_MARGIN:
		_wander_dir = -1.0
	return _wander_dir

## Below his centre of mass in world space, which is where a sliding body wants to be pushed.
## `apply_force`'s offset is not rotated by the body, so this stays under him however he has
## ended up lying.
func _foot_offset() -> Vector2:
	return Vector2(0.0, _buddy.get_interaction_rect().size.y * 0.5)

# --- choosing a toy --------------------------------------------------------

## Nearest wins; toys inside one `TIE_BAND` of each other are a tie and the better-paying one
## takes it. One pass, no sort, no allocation — this runs every think tick forever.
func _choose_toy() -> Node2D:
	var now := Time.get_ticks_msec()
	var here := _buddy.global_position
	var best: Node2D = null
	var best_band := 1 << 30
	var best_appeal := 0.0
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		var body := node as BaseDraggable
		# He is in the `interactive` group himself, and a toy in the player's hand is not on
		# offer.
		if body == null or body == _buddy or body.dragging:
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

## What he would do with it, read off the switches the item already declares rather than off
## its id — so a new friendly item is still a `.tres` and a scene (docs/decisions.md D8).
func _routine_for(body: BaseDraggable) -> int:
	if body is Trampoline:
		return ROUTINE_BOUNCE
	var friendly := body as FriendlyBase
	if friendly == null:
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
	# He cannot throw himself. The baseball's catch pays only above a closing speed he has no
	# way to produce on foot, so walking to it would be a wasted trip every time.
	if friendly.min_contact_speed > 0.0:
		return ROUTINE_NONE
	# Scrub before soak: the sponge now pays a touching trickle as well as its grime bonus,
	# and read in the other order he would sit in it like a beanbag.
	if friendly.cleans_grime:
		return ROUTINE_SCRUB
	if friendly.hearts_per_second_touching > 0.0:
		return ROUTINE_SOAK
	if friendly.hearts_per_contact > 0.0:
		return ROUTINE_NIBBLE
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
	var friendly := body as FriendlyBase
	if friendly == null:
		return 0.0
	if routine == ROUTINE_SOAK:
		return friendly.hearts_per_second_touching
	if routine == ROUTINE_SCRUB:
		var b := ItemDB.balance
		var grime: float = _buddy.grime.value if _buddy.grime else 0.0
		return b.sponge_clean_rate * b.hearts_per_grime_cleaned * grime
	if routine == ROUTINE_NIBBLE:
		return friendly.hearts_per_contact / maxf(friendly.contact_cooldown, 0.1)
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
	if info.source_id == &"world" or _is_current_toy(info.source_id):
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
	# The toy he is playing with paying him is not somebody arriving. Anything else is — a pet
	# is the clearest "I am here" in the game.
	if _is_current_toy(source_id):
		return
	_disturb()

func _on_buddy_state_changed(state: StringName) -> void:
	if state == &"knockout" and is_instance_valid(_target):
		_cool(_target, KNOCKOUT_COOLDOWN)
	if state == &"dragged" or _is_knockout_state(state):
		_disturb()

## Spawning something means a hand on the mouse. Despawning does not — the pizza he just ate
## despawns itself, and treating that as the player would interrupt him with his own dinner.
func _on_item_spawned(_item: Node2D) -> void:
	_disturb()

func _on_item_despawned(item: Node2D) -> void:
	if item == _target:
		_finish(false)

## Off stops him moving and keeps him earning; switching back on gives him his legs again.
## Neither may wait for the current dwell to run out — and neither may *restart* it, or a
## player toggling the setting could hold him on the best-paying toy on the desk forever.
func _on_focus_mode_changed(_intensity: int) -> void:
	set_physics_process(_phase != PHASE_WATCHING and not _focus_off())

func _stand_down() -> void:
	_flush()
	# Deliberately no cooldown: he was interrupted, not bored, and a toy he never got to play
	# with should still be there when the player leaves again.
	_target = null
	_target_id = &""
	_routine = ROUTINE_NONE
	_enter(PHASE_WATCHING)

func _finish(cool: bool) -> void:
	_flush()
	if cool and is_instance_valid(_target):
		_cool(_target, TOY_COOLDOWN)
	_target = null
	_target_id = &""
	_routine = ROUTINE_NONE
	_enter(PHASE_WANDERING)

func _enter(phase: StringName) -> void:
	_phase = phase
	_phase_seconds = 0.0
	_stalled_seconds = 0.0
	_best_distance = INF
	_moved_since_think = false
	_climb_timer = 0.0
	_jig_timer = 0.0
	set_physics_process(phase != PHASE_WATCHING and not _focus_off())

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
	return _rect_of(_target).grow(ARRIVE_SLACK).intersects(_buddy.get_interaction_rect())

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
