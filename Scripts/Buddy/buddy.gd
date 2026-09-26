class_name Buddy
extends BaseDraggable

## Bonehead. A single rigid body by design (docs/decisions.md D4) — the uplift is
## animation, not simulated dismemberment.
##
## **He measures his own damage.** Every hit in the game is a contact impulse read here,
## not a number a weapon decided to deal (docs/decisions.md D7). The prototype read the
## velocity of a shapeless body nested inside the weapon, which free-fell under gravity
## and therefore measured time-since-last-hit; a later commit then tuned around the
## artefact. Measuring on the receiver is physically correct, halves the code, and makes
## any rigid body a weapon — a dropped bowling ball pays correctly with no special case.
##
## He also owns his mood and his grime, and persists both: they are his state, and the
## save file's `buddy` block is written from here rather than from Economy, which only
## mirrors the two values off the bus so the payout pipeline can multiply by them.

const GROUP_BUDDY := &"buddy"

## How far outside the visible area he may get before being rescued.
const OUT_OF_BOUNDS_MARGIN := 1200.0

## Contacts reported per physics tick. Four is the architecture's number; eight costs
## nothing measurable and stops a busy pile-up silently dropping the hit that mattered.
const MAX_CONTACTS := 8

## How long a hit or a pet holds him in a reaction state before he settles back to idle,
## when the art pass has not built that animation yet. `hurt` is 6 frames and `happy` is 8 —
## both already run past this — so `_reaction_seconds` prefers `art.animation_length()` and
## only falls back to this constant for a state with no tag to time against.
const REACTION_FALLBACK_SECONDS := 0.45

@export var health: HealthComponent
@export var mood: MoodComponent
@export var grime: GrimeComponent
@export var face: AnimatedSprite2D
@export var art: BuddyArt
@export var expression: ExpressionBrain

var initial_position: Vector2
var state: StringName = &"idle"

## Per-source hit cooldowns, keyed by collider instance id. Two bats each get their own,
## which a per-item-id cooldown would not.
var _cooldowns: Dictionary = {}

## **The half of a hit the engine never reports** (docs/decisions.md D64). A contact carries the
## impulse of the step *before* the one it is reported in, and only when the solver recognised
## it as the same contact — within one pixel on both bodies. So a hit that parts them inside one
## step, or slides across him as it lands, reports zero and then nothing. That was the fist, every
## thrown ball and the trampoline's landing. His own momentum says what the step did to him, and
## the engine's report one step later says how much of that it knows about; the rest was a
## contact it will never report, and it is billed to that contact.
##
## His velocity as the step about to run begins — read after every script has had its say, by
## `StepStart`, so a blast or a hop applied this frame is not mistaken for something that hit him.
var _step_v := Vector2.ZERO
var _step_v_fresh := false
## **Asleep, he is not told about the step that wakes him.** Godot calls back only a body that was
## awake when the step began, so a ball thrown at him while he dozes is solved in a step he never
## hears about, and by the next read his velocity already has the hit in it. So while he sleeps
## the read stands still — `_span_asleep` — and the first callback after he wakes covers both
## steps; `_span_woke` says the contacts it reports belong to that span too.
var _span_asleep := false
var _span_woke := false
## The last solved step, held until the engine has had its one chance to report it: the impulse
## his contacts handed him (his momentum change, less gravity and damping), and which colliders
## were touching him, where, and from which side. `_ledger_known` is what the engine has already
## reported of it, when the span began in a step he slept through.
var _ledger_known := Vector2.ZERO
var _ledger_dp := Vector2.ZERO
var _ledger_count := 0
var _ledger_src := PackedInt64Array()
var _ledger_normal := PackedVector2Array()
var _ledger_at := PackedVector2Array()
var _ledger_share := PackedFloat32Array()
var _ledger_cap := PackedFloat32Array()
## A reported impulse under this is the engine saying "a new contact", not a measurement.
const REPORTED_EPSILON := 1.0
## The most a contact can hand him per unit of its normal impulse: friction caps the tangential
## part at `friction x normal`, and his friction is 1.0 (Godot combines by the minimum), so
## sqrt(1 + 1). A residual outside that cone is not something this contact could have done.
const FRICTION_CONE := 1.4142135
## The largest impulse a collision can make, per unit of the mass behind it and of closing
## speed: `(1 + e)` at a restitution of 1, times the friction cone. Anything past it was pushed
## in by something else — him squeezed against the floor by a bat — and the part the engine did
## not report of *that* is not a hit anything threw.
const APPROACH_CAP := 2.0 * FRICTION_CONE
## Runs last among every node's `_physics_process`, so what it reads is what the step starts from.
const STEP_START_PRIORITY := 1 << 30

## The last word before the physics step. A node of its own rather than a priority on him: his
## own `_physics_process` dispatches hits, and moving that to the end of the frame would move the
## whole payout pipeline with it.
class StepStart extends Node:
	var buddy: Buddy

	func _physics_process(_delta: float) -> void:
		buddy._note_step_start()

## Hits are collected inside _integrate_forces and dispatched from _physics_process.
## Emitting from inside the physics step would run the whole payout pipeline — including
## nodes being added to the tree for floating numbers — while the physics server is
## mid-solve.
var _pending_hits: Array[HitInfo] = []

## When the current hurt/happy expression lapses back to idle. A deadline checked in
## _process rather than a timer per event: hits arrive up to seven a second and this game
## is designed to be left running for eight hours, so one SceneTreeTimer per hit is a real
## allocation rate for something a single integer already answers.
var _reaction_until_msec := 0

## True for the whole collapse -> pile -> reassemble beat. The out-of-bounds rescue and the
## drag handler both stand down while it runs, or they fight the tween.
var _in_knockout := false

## Landing detection for the expression brain: his downward speed on the previous physics
## tick. Falling faster than `LANDING_SPEED` and then not falling is a landing.
var _prev_vy := 0.0
const LANDING_SPEED := 250.0
## Flung about while held faster than this reads as being shaken.
const SHAKE_SPEED := 900.0

## Standing on something, from the contact normals the damage loop already reads: any contact
## whose normal points up into him. Read by the idle brain's climb — a velocity test re-fires
## at the apex of a hop; a contact test does not. Stale while the body sleeps, and nothing
## reads it then. The sign convention is pinned by a loop_check assertion, because it is the
## one thing in docs/plan-movement-hitboxes.md nobody could verify on paper.
var _grounded := false
const GROUND_NORMAL_Y := -0.7

## Who is moving him without touching him (D65). The gravity vortex and the desk fan act on
## him through a field, so every impact they cause is with the world or with a prop, and a
## world impact was billed to `world` — which left both items earning nothing under their own
## name and their automation capstones unbuyable. While a field acts on him, and for a moment
## after, an impact with the world is billed to that field instead.
##
## Only *who* is billed changes, never *whether*: the floor is still the world's fall floor,
## and a prop that hits him is still billed to the prop, so nothing is billed twice and no
## impact pays that did not pay before. Picking him up hands him back to the player.
var _claim_id: StringName = &""
var _claim_mult := 1.0
var _claim_until_msec := 0
## Whether the field claiming him is acting with nobody holding it: a desk fan left blowing. Its
## claimed impact is then the world he was blown into, and it is the hand's only when the world's
## would be (D76) — `HitInfo.by_itself`. A vortex, a spell or an ability is held while it pulls.
var _claim_by_itself := false

## **His own play is never a hit** (D70). While the idle brain has him at a toy, the toy and the
## world are his own doing: the mat he bounces on, the floor he comes down on, a ball he bops
## onto his own head. D64 made the mat's landings billable, which is right for a player who
## throws him onto it and wrong for his own bouncing — that billed about 17.6 damage a second to
## an empty desk, a Bones engine nobody bought, on top of the Hearts the brain pays for the same
## bounce ("the toy or the brain pays, never both"; D2: what earns unattended is automation, and
## automation is bought with Hearts). So those contacts are not billed at all — not reassigned,
## not billed to someone else. Everything else still is: a bat, a turret, an animal, a pellet.
##
## Set by the brain when he sets off, and cleared the moment the player takes him or stands the
## routine down. When the routine simply ends it lasts until he comes to rest, because a skeleton
## bouncing on a trampoline keeps bouncing after the dwell is over.
var _own_play := false
var _own_play_toy := 0
var _own_play_until_still := false
## Slower than this, on the ground, for this many steps in a row, he has come to rest. Steps,
## not one reading: every trampoline landing stops him dead for the step before the mat throws
## him back up.
const OWN_PLAY_REST_SPEED := 30.0
const OWN_PLAY_REST_STEPS := 30
var _own_play_still_steps := 0

func begin_own_play(toy: Node) -> void:
	_own_play = true
	_own_play_until_still = false
	_own_play_toy = toy.get_instance_id() if is_instance_valid(toy) else 0

## `now` for a routine the player cut short; otherwise it lasts until he is still.
func end_own_play(now: bool) -> void:
	if now or not _own_play:
		_own_play = false
		_own_play_until_still = false
		_own_play_toy = 0
		return
	_own_play_until_still = true
	_own_play_still_steps = 0

## Whether a contact with `src` is his own play: the world, or the toy he is playing with.
func is_own_play(src: Object) -> bool:
	if not _own_play:
		return false
	var body := src as BaseDraggable
	if body == null:
		return true
	return _own_play_toy != 0 and body.get_instance_id() == _own_play_toy

func is_grounded() -> bool:
	return _grounded

## Called every physics frame a field acts on him; the claim runs `seconds` past the last.
## `by_itself` for a field nobody is holding (the desk fan, D76 amended).
func claim_impacts(source_id: StringName, damage_mult: float, seconds: float,
		by_itself: bool = false) -> void:
	_claim_id = source_id
	_claim_mult = damage_mult
	_claim_by_itself = by_itself
	_claim_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)

func impacts_claimed_by() -> StringName:
	return _claim_id if Time.get_ticks_msec() < _claim_until_msec and not dragging else &""

func _ready() -> void:
	super._ready()
	add_to_group(GROUP_BUDDY)
	initial_position = global_position

	contact_monitor = true
	max_contacts_reported = MAX_CONTACTS
	_ledger_src.resize(MAX_CONTACTS)
	_ledger_normal.resize(MAX_CONTACTS)
	_ledger_at.resize(MAX_CONTACTS)
	_ledger_share.resize(MAX_CONTACTS)
	_ledger_cap.resize(MAX_CONTACTS)
	var watch := StepStart.new()
	watch.name = "StepStart"
	watch.buddy = self
	watch.process_physics_priority = STEP_START_PRIORITY
	add_child(watch)

	_ensure_components()
	if health:
		health.max_damage = ItemDB.balance.knockout_damage
		health.knocked_out.connect(_on_knocked_out)

	EventBus.kindness_given.connect(_on_kindness_given)
	SaveManager.register_provider(self)

func _exit_tree() -> void:
	SaveManager.unregister_provider(self)

## Mood and grime are `@export` slots so the scene can author them once the art pass opens
## buddy.tscn (the grime overlay is a sprite layer there, not a tint). Until then they are
## built here, the same way main.gd builds the whole UI shell at boot — the alternative is
## a scene edit made outside the editor, which docs and CLAUDE.md both rule out.
func _ensure_components() -> void:
	if mood == null:
		mood = MoodComponent.new()
		mood.name = "MoodComponent"
		add_child(mood)
	if grime == null:
		grime = GrimeComponent.new()
		grime.name = "GrimeComponent"
		add_child(grime)
	if grime.puppet == null:
		grime.puppet = sprite

	# The face layer and the art driver, built here for the same reason the components are:
	# buddy.tscn cannot be edited outside the editor, and the art pass is when it gets
	# authored properly. Both are @export slots so authoring them later just works.
	if face == null and sprite:
		face = AnimatedSprite2D.new()
		face.name = "Face"
		face.scale = sprite.scale
		face.position = sprite.position
		# Above the body, below nothing else — the face is part of him, not an effect.
		face.z_index = sprite.z_index + 1
		add_child(face)
	# The face is deliberately not handed to GrimeComponent (D46): dirt over his expression
	# hid the thing that asks the player to clean it off. BuddyArt still installs the shared
	# material on Face for the wardrobe tints.

	if art == null:
		art = BuddyArt.new()
		art.name = "BuddyArt"
		art.body = sprite
		art.face = face
		add_child(art)
	if art.buddy == null:
		art.buddy = self

	# What he looks like he is feeling (docs/plan-expressive-buddy.md). After the art, so its
	# `_ready` can connect to the art's signals.
	if expression == null:
		expression = ExpressionBrain.new()
		expression.name = "ExpressionBrain"
		expression.buddy = self
		expression.art = art
		add_child(expression)
	if expression.buddy == null:
		expression.buddy = self
	if expression.art == null:
		expression.art = art

func _process(_delta: float) -> void:
	if _in_knockout:
		return
	_settle_reaction()
	# Failsafe if he escapes the world. Measured against the actual viewport, because the
	# window is resizable — a fixed distance is meaningless when the play area can be
	# anything from 320x240 to an ultrawide. The prototype's check tested y < -2000, which
	# is *upward*: the one direction gravity guarantees he will not go.
	var bounds := get_viewport().get_visible_rect().grow(OUT_OF_BOUNDS_MARGIN)
	if not bounds.has_point(global_position):
		_return_home()

## The knockout beat owns him completely while it runs. Without this, pressing on him
## mid-collapse pins a joint to a frozen body, holds `dragging` true through the whole beat
## while the reassemble tween writes his position, and snaps him to the cursor the instant
## the beat unfreezes him — with `idle` on the bus while he is in fact being dragged.
func _unhandled_input(event: InputEvent) -> void:
	# Where the cursor is, from the event and never polled: a synthetic event cannot move the
	# OS cursor, so anything that polls the cursor position is untestable by construction.
	var motion := event as InputEventMouseMotion
	if motion and expression and expression.attention() == ExpressionBrain.ATTEND_CURSOR:
		expression.notice_cursor(get_canvas_transform().affine_inverse() * motion.position)
	if _in_knockout:
		return
	super._unhandled_input(event)

## App focus and the cursor leaving the window, forwarded to the expression brain. Both are
## propagated to every node, so this is the natural place: the character notices himself.
func _notification(what: int) -> void:
	if expression == null:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			expression.notice_focus(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			expression.notice_focus(true)
		NOTIFICATION_WM_MOUSE_EXIT:
			expression.notice_hover(false)

## Picking him up and putting him down are states, not just physics. Before this, `dragged`
## was reachable only as a side effect — `_settle_reaction` picked it when a reaction lapsed
## mid-drag — and nothing ever set it back, so a hit taken while held left him in the dragged
## pose indefinitely, with his mood-driven idle unable to resume.
func _start_drag() -> void:
	super._start_drag()
	_claim_until_msec = 0
	# Whatever he was doing on his own, he is the player's now (D70).
	end_own_play(true)
	if not _in_knockout:
		_reaction_until_msec = 0
		_set_state(&"dragged")
		# Tested on `dragging` rather than on reaching here: BaseDraggable bails without a
		# handle, and a pick-up that did not happen must not tick a contract.
		if dragging:
			EventBus.contract_event.emit(&"pick_up", 1)
			if expression:
				expression.notice_drag(true)

func _end_drag() -> void:
	var was_dragging := dragging
	super._end_drag()
	if was_dragging and expression:
		expression.notice_drag(false)
	if was_dragging and not _in_knockout and state == &"dragged":
		_set_state(&"idle")

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if dragging and expression and linear_velocity.length_squared() > SHAKE_SPEED * SHAKE_SPEED:
		expression.notice_shake()
	if _pending_hits.is_empty():
		return
	var hits := _pending_hits.duplicate()
	_pending_hits.clear()
	for info in hits:
		_deal(info)

# --- damage ----------------------------------------------------------------

func _integrate_forces(state_: PhysicsDirectBodyState2D) -> void:
	# A landing is a fall that stopped. Before the damage early-out: the sub-threshold
	# contacts it discards are exactly the ones a soft landing is made of.
	var vy := state_.linear_velocity.y
	if _prev_vy > LANDING_SPEED and vy < LANDING_SPEED * 0.2:
		if expression:
			expression.notice_landing(_prev_vy)
		# Where his feet are, for the dust (WorldFX). The bottom of his interaction rect, so
		# it sits on whatever he landed on rather than at his centre of mass.
		var rect := get_interaction_rect()
		EventBus.buddy_landed.emit(Vector2(rect.get_center().x, rect.end.y), _prev_vy)
	if expression:
		expression.notice_airborne(state_.get_contact_count() == 0 and not freeze,
			state_.linear_velocity)
	_prev_vy = vy
	var contacts := state_.get_contact_count()
	_grounded = false
	for i in contacts:
		if state_.get_contact_local_normal(i).y < GROUND_NORMAL_Y:
			_grounded = true
			break
	if _own_play_until_still:
		var still := _grounded and state_.linear_velocity.length() < OWN_PLAY_REST_SPEED
		_own_play_still_steps = _own_play_still_steps + 1 if still else 0
		if _own_play_still_steps >= OWN_PLAY_REST_STEPS:
			end_own_play(true)
	if health == null or health.down:
		_ledger_count = 0
		_step_v_fresh = false
		_span_asleep = false
		_span_woke = false
		return
	var b := ItemDB.balance
	for i in contacts:
		var src := state_.get_contact_collider_object(i)
		# One impact, one measurement. A body landing flat — and with rotation locked while
		# the idle brain drives him, he lands flat — splits one impact across two manifold
		# points on the same collider, each carrying half. He took the whole of it, so the
		# points are summed per collider; a free body landing on a corner is the same sum
		# with one term. Earlier points already folded this collider in, so skip repeats.
		# Quadratic in at most eight contacts, and it allocates nothing.
		var repeat := false
		for j in i:
			if state_.get_contact_collider_object(j) == src:
				repeat = true
				break
		if repeat:
			continue
		var total := state_.get_contact_impulse(i)
		for k in range(i + 1, contacts):
			if state_.get_contact_collider_object(k) == src:
				total += state_.get_contact_impulse(k)
		var impulse := total.length()
		# Cheapest reject first: resting contact is 49 a tick.
		if impulse < b.min_damage_impulse:
			continue
		# Then who put the energy in — before the cooldown, so a self-contact that is
		# discarded here never stamps the cooldown a real hit would then eat.
		if impulse < _min_impulse_for(src, b):
			continue
		# His own play is not billed (D70). Before the cooldown, which it must not stamp.
		if is_own_play(src):
			continue
		if not _cooldown_ready(src, b.damage_cooldown):
			continue
		# get_contact_local_position is global despite the name: "local" distinguishes
		# this body's contact point from the collider's, not the coordinate space.
		hit_at = state_.get_contact_local_position(i)
		var attribution := _attribute(src)
		hit_at = Vector2.INF
		_queue_hit(impulse, attribution[0], attribution[1], state_.get_contact_local_position(i),
			attribution.size() > 2 and bool(attribution[2]))
	# The step before this one, now that the engine has said all it will about it; then this
	# step, held for the same question next time. After a sleep the one still held is from
	# before it, and what this callback reports is the step that woke him, not that one.
	if _span_woke:
		_ledger_count = 0
	_settle_ledger(state_, b)
	_open_ledger(state_)

func _note_step_start() -> void:
	var rid := get_rid()
	var asleep: bool = PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_SLEEPING)
	# Asleep is at rest: whatever he was doing on his own is over (D70).
	if asleep and _own_play_until_still:
		end_own_play(true)
	if _step_v_fresh and _span_asleep:
		# Asleep at the last read and no callback since: the span stays open from there.
		_span_woke = _span_woke or not asleep
		_span_asleep = asleep
		return
	_step_v = PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	_step_v_fresh = true
	_span_asleep = asleep
	_span_woke = false

## The impulse a contact reports, as he received it. The sign of a reported impulse depends on
## which body the solver paired first; a contact only ever pushes, so the one he received points
## out of the collider, along his contact normal.
func _received(state_: PhysicsDirectBodyState2D, i: int) -> Vector2:
	var impulse := state_.get_contact_impulse(i)
	return impulse if impulse.dot(state_.get_contact_local_normal(i)) >= 0.0 else -impulse

## Holds the step just solved: what his contacts handed him, and who was touching him.
##
## `v_end - v_start` is everything that changed his velocity inside the step. Gravity and
## damping are taken off exactly as Godot applies them (`v * (1 - damp dt) + g dt`, damping
## first); the drag joint cannot be, so nothing is held while he is held. What is left is the
## sum of his contacts' impulses — including the ones the engine will report next step, which
## `_settle_ledger` takes back out. Woken inside the span, it is two steps long, and what this
## callback reports is the first of them.
func _open_ledger(state_: PhysicsDirectBodyState2D) -> void:
	_ledger_count = 0
	var fresh := _step_v_fresh
	var woke := _span_woke
	_step_v_fresh = false
	_span_asleep = false
	_span_woke = false
	if not fresh or dragging or freeze:
		return
	var dt := state_.step
	var expected := _step_v * maxf(0.0, 1.0 - dt * state_.total_linear_damp) + state_.total_gravity * dt
	_ledger_dp = (state_.linear_velocity - expected) * mass
	_ledger_known = Vector2.ZERO
	if woke:
		for i in state_.get_contact_count():
			if state_.get_contact_impulse(i).length() >= REPORTED_EPSILON:
				_ledger_known += _received(state_, i)
	for i in state_.get_contact_count():
		var id := state_.get_contact_collider_id(i)
		var slot := -1
		for s in _ledger_count:
			if _ledger_src[s] == id:
				slot = s
				break
		if slot < 0:
			slot = _ledger_count
			_ledger_count += 1
			_ledger_src[slot] = id
			_ledger_normal[slot] = Vector2.ZERO
			_ledger_at[slot] = state_.get_contact_local_position(i)
			_ledger_cap[slot] = 0.0
		var normal := state_.get_contact_local_normal(i)
		_ledger_normal[slot] += normal
		# Both velocities are the ones the solver started from, before this contact was solved.
		var closing := (state_.get_contact_collider_velocity_at_position(i)
			- state_.get_contact_local_velocity_at_position(i)).dot(normal)
		if closing > 0.0:
			# The mass behind the blow. For a free body, its own: that is the most it can hand
			# him, and it hands him all of it when he is standing on the desk and cannot give.
			# For the world, his: the desk does not move, so all a wall can return is what he
			# brought — a bat pressing him into it is the bat's hit, not the floor's.
			var other := state_.get_contact_collider_object(i) as RigidBody2D
			var behind := other.mass if other and not other.freeze else mass
			_ledger_cap[slot] = maxf(_ledger_cap[slot], APPROACH_CAP * behind * closing)
	for s in _ledger_count:
		_ledger_normal[s] = _ledger_normal[s].normalized()

## Bills what the engine did not report of the step `_open_ledger` held (D64).
##
## Every contact the engine recognised this step carries last step's impulse, and that part of
## the momentum is already accounted for — the loop above bills it, so it is subtracted here and
## never billed twice. What is left belongs to the colliders that touched him then and report
## nothing now: they parted, or slid, or were replaced by a new contact. One such collider takes
## the lot, as long as it could have delivered it — pushing him away from itself, and inside the
## friction cone (his friction is 1.0, so tangential no larger than normal). Several split it by
## their normals, solved non-negative, the normal part only. No share is larger than the
## collision its approach could have made (`APPROACH_CAP`), which is what keeps the floor under
## a bat pressing him into it from being billed as a fall. Then the same floor, the same
## per-source cooldown and the same attribution as a reported contact.
func _settle_ledger(state_: PhysicsDirectBodyState2D, b: BalanceData) -> void:
	var count := _ledger_count
	_ledger_count = 0
	if count == 0:
		return
	var contacts := state_.get_contact_count()
	var known := _ledger_known
	for s in count:
		_ledger_share[s] = 0.0
	for i in contacts:
		if state_.get_contact_impulse(i).length() < REPORTED_EPSILON:
			continue
		known += _received(state_, i)
		var id := state_.get_contact_collider_id(i)
		for s in count:
			if _ledger_src[s] == id:
				_ledger_share[s] = -1.0
	var unknown := 0
	for s in count:
		if _ledger_share[s] >= 0.0:
			unknown += 1
	if unknown == 0:
		return
	var residual := _ledger_dp - known
	var size := residual.length()
	# Cheapest reject first, as above.
	if size < b.min_damage_impulse:
		return
	if unknown == 1:
		for s in count:
			if _ledger_share[s] < 0.0:
				continue
			var normal_part := residual.dot(_ledger_normal[s])
			if normal_part > 0.0 and size <= normal_part * FRICTION_CONE + REPORTED_EPSILON:
				_ledger_share[s] = size
	else:
		# Projected Gauss-Seidel on `residual = sum(a_s n_s)`, a_s >= 0. Eight contacts at most
		# and eight sweeps: exact for two, and a floor and a prop is the case that matters.
		for sweep in 8:
			for s in count:
				if _ledger_share[s] < 0.0:
					continue
				var left := residual
				for k in count:
					if _ledger_share[k] > 0.0:
						left -= _ledger_normal[k] * _ledger_share[k]
				_ledger_share[s] = maxf(0.0, _ledger_share[s] + left.dot(_ledger_normal[s]))
	for s in count:
		var share := minf(_ledger_share[s], _ledger_cap[s])
		if share < b.min_damage_impulse:
			continue
		var src := instance_from_id(_ledger_src[s])
		# Freed since: a charge that went off, a pizza that was eaten. Nothing left to bill.
		if src == null:
			continue
		if share < _min_impulse_for(src, b):
			continue
		if is_own_play(src):
			continue
		if not _cooldown_ready(src, b.damage_cooldown):
			continue
		hit_at = _ledger_at[s]
		var attribution := _attribute(src)
		hit_at = Vector2.INF
		_queue_hit(share, attribution[0], attribution[1], _ledger_at[s],
			attribution.size() > 2 and bool(attribution[2]))

## Damage from a source that is not a contact — an explosion's blast, a gunshot. Fed the
## same kind of impulse the contact solver produces so there is one damage model, not two.
func take_impulse(impulse: float, source_id: StringName, damage_mult: float, at: Vector2) -> void:
	if health == null or health.down:
		return
	if impulse < ItemDB.balance.min_damage_impulse:
		return
	_queue_hit(impulse, source_id, damage_mult, at)

func _queue_hit(impulse: float, source_id: StringName, damage_mult: float, at: Vector2,
		by_itself: bool = false) -> void:
	var b := ItemDB.balance
	var amount := EconomyMath.damage_from_impulse(impulse, b.min_damage_impulse, b.damage_per_impulse, damage_mult)
	if amount <= 0.0:
		return
	# One pathological impulse — a tunnelling collision, a physics blow-up — must not pay
	# out a whole round.
	amount = minf(amount, b.knockout_damage * b.max_hit_fraction)
	var info := HitInfo.new(amount, source_id, at, impulse)
	info.by_itself = by_itself
	_pending_hits.append(info)

func _deal(info: HitInfo) -> void:
	if health == null or health.down:
		return
	EventBus.damage_dealt.emit(info)
	if Effects_Player:
		Effects_Player.hit_effect()
	# After the bus, so mood and grime have already taken the hit into account and a
	# knockout on this frame finds the state it is supposed to pay out against.
	_react(&"hurt")
	health.apply_damage(info.amount)

## The floor this contact has to clear, by what he touched (docs/plan-movement-hitboxes.md).
## The world and kind items need a fall; harm-side items need a swing. Asked of the data, so a
## new comfort item is classified by the seed tool that wrote it and never by an edit here.
##
## **Kind means kind and bought with Hearts** (D64). The Play drawer is on the kind side of the
## shop and sells three things bought with Bones that earn Bones — the bowling ball, the
## trampoline and the desk fan — and the drawer was asking a thrown bowling ball for the fall
## floor, as if it were a beanbag he climbed on to. The currency is what says whose side a
## thing is on; it used to take a `Trampoline` special case here to say the same of the mat.
## An unknown or empty id is treated as harm — conservative. This is the seam the per-part
## floor plugs into when the multi-hitbox lands (plan §5).
func _min_impulse_for(src: Object, b: BalanceData) -> float:
	var body := src as BaseDraggable
	var harm_side := true
	if body == null:
		# A scriptless StaticBody2D: the walls, the test floor. The world never swings.
		harm_side = false
	elif body is NpcBase:
		# **An animal's blow is telegraphed; its body is not a weapon** (D70, AI audit E). Every
		# animal strikes through `take_impulse` a wind-up after its tell, and its body brushing
		# him on the way in was billed like a swung bat as well — a goose arriving, a hornet
		# buzzing past — with no tell at all. So its body faces the fall floor: a bump is free,
		# and an animal the player throws at him still lands.
		harm_side = false
	else:
		var item := ItemDB.get_item(body.item_id)
		if item != null and item.is_kind() and item.currency == ItemData.CURRENCY_HEARTS:
			harm_side = false
	return EconomyMath.contact_floor(harm_side, b.min_damage_impulse, b.min_fall_impulse)

## His real body. `BaseDraggable`'s version scales the shape by the *body's* transform, and he
## is the one body in the roster whose collider carries its size on the node (44x60 at scale
## 2, offset (0,2)) — so it reported 44x60 for an 88x120 box, and the idle brain pushed 32 px
## above his feet, measured every climb from the wrong place and could never call a beanbag
## against his side "reached". Overridden here rather than fixed for everyone: several
## authored weapons have off-centre colliders too, nothing reads their rect today, and a
## silent change to it is not this commit's business.
func get_interaction_rect() -> Rect2:
	if collider == null or collider.shape == null:
		return super.get_interaction_rect()
	var xf := collider.global_transform
	var extent := Vector2(48, 48)
	if collider.shape.has_method("get_rect"):
		var r: Rect2 = collider.shape.get_rect()
		if r.size.length() > 0.0:
			extent = (r.size * 0.5 * xf.get_scale()).abs()
	elif collider.shape is CircleShape2D:
		var radius: float = (collider.shape as CircleShape2D).radius
		extent = Vector2(radius, radius) * xf.get_scale().abs()
	return Rect2(xf.origin - extent, extent * 2.0)

## Who to bill the hit to, and by how much. Anything without a script is still a weapon —
## it just has no multiplier and no mastery.
func _attribute(src: Object) -> Array:
	if src is WeaponBase:
		var w := src as WeaponBase
		# Both gates have already run by the time attribution does, so this is the honest
		# count of swings that landed — the contract board's "land 120 hits with the mace".
		w.register_use()
		return [w.item_id, w.effective_damage_mult()]
	if src is ThrowableBase:
		var t := src as ThrowableBase
		return [t.item_id, t.effective_damage_mult()]
	# An animal or a turret that runs into him is billed at its own multiplier, the same one
	# its blows and shots already carry. It was a flat 1.0, so a hornet's body-check ignored the
	# "Sharper Sting" the player had bought for it, measured by item_check (D59). Duck-typed:
	# the method is the contract, and the classes that have one are not a list kept here.
	if src is BaseDraggable and src.has_method(&"effective_damage_mult"):
		return [(src as BaseDraggable).item_id, float(src.call(&"effective_damage_mult"))]
	if src is BaseDraggable:
		return [(src as BaseDraggable).item_id, 1.0]
	# The world, unless a field is throwing him into it (D65) — and whether that field is one
	# nobody is holding, which Economy then judges as it judges the world (D76 amended).
	if impacts_claimed_by() != &"":
		return [_claim_id, _claim_mult, _claim_by_itself]
	return [&"world", 1.0]

## Where the contact being billed touched him, while `_attribute` asks its weapon for a
## multiplier; INF the rest of the time. For a weapon whose multiplier depends on *where* on it the
## hit landed — the cricket bat's middle (D74) — because by the time a hit the ledger bills is
## attributed, a step late (D64), the weapon has already moved off him, and where it is then says
## nothing about where it touched.
var hit_at := Vector2.INF

## Above this many tracked sources, expired entries are swept. Items are spawned and binned
## all session; without a sweep this dictionary grows for every object that ever touched him,
## which in a game designed to idle for eight hours is an unbounded leak.
const COOLDOWN_SWEEP_AT := 64

## A weapon left leaning against him produces a contact impulse every tick. The cooldown
## is what stops that farming Bones while the player is away from the desk.
##
## **Counted in physics steps, not on the wall clock** (D74 fixes). Contacts happen in steps, and
## the engine runs steps in bursts — two to a drawn frame at the 30 fps idle cap, more in Low Power
## or after a hitch — so a wall-clock cooldown lasted a different number of steps from one frame to
## the next, and which of a sweep's contacts it let through depended on the frame rate and the
## load: the cleaver's ordinary hit measured 17.3 at 30 fps and 20.7 at 15, and its lodged blade
## drifted past the suite's limit only at 15. `damage_cooldown` seconds of steps, rounded up.
func _cooldown_ready(src: Object, cooldown: float) -> bool:
	var key := src.get_instance_id() if src != null else 0
	var now := Engine.get_physics_frames()
	if now < int(_cooldowns.get(key, 0)):
		return false
	if _cooldowns.size() >= COOLDOWN_SWEEP_AT:
		_sweep_cooldowns(now)
	_cooldowns[key] = now + cooldown_steps(cooldown)
	return true

## Seconds of cooldown as physics steps: 0.15 s is 9 at 60 Hz. Zero stays zero, so a suite that
## turns the cooldown off still sees a second bill in the same step.
static func cooldown_steps(seconds: float) -> int:
	return ceili(seconds * float(Engine.physics_ticks_per_second) - 0.001) if seconds > 0.0 else 0

func _sweep_cooldowns(now: int) -> void:
	for key in _cooldowns.keys():
		if now >= int(_cooldowns[key]):
			_cooldowns.erase(key)

# --- kindness --------------------------------------------------------------

func _on_kindness_given(_source_id: StringName, _value: float, _world_pos: Vector2) -> void:
	_react(&"happy")

## A short-lived expression state. Knockout outranks it: a pet landing mid-collapse must
## not pull him out of the beat.
func _react(reaction: StringName) -> void:
	if _in_knockout:
		return
	_set_state(reaction)
	_reaction_until_msec = Time.get_ticks_msec() + int(_reaction_seconds(reaction) * 1000.0)

## The art's own timing when it exists, so `happy` (8 frames) and `hurt` (6 frames) each hold
## for as long as they actually play rather than being cut off at a fixed duration — the
## same pattern `_beat_time` already uses for the knockout.
func _reaction_seconds(reaction: StringName) -> float:
	if art:
		var animation: StringName = art.STATE_ANIMATION.get(reaction, reaction)
		if art.has_animation(animation):
			var length := art.animation_length(animation)
			if length > 0.0:
				return length
	return REACTION_FALLBACK_SECONDS

## Lets a lapsed expression fall back to idle. Called from _process, which is also where
## the knockout guard already lives.
func _settle_reaction() -> void:
	if _reaction_until_msec == 0 or Time.get_ticks_msec() < _reaction_until_msec:
		return
	_reaction_until_msec = 0
	# Whichever is true *now* — he may have been put down during the reaction.
	_set_state(&"dragged" if dragging else &"idle")

# --- knockout --------------------------------------------------------------

## The round's climax: tip over, lie in a heap while the fountain pays out, reassemble.
##
## Economy pays the bonus off buddy_state_changed(&"knockout") — Economy is the only thing
## in the game allowed to mint currency, so the buddy announces rather than awards. That
## emit therefore has to stay the first thing this does; the animation hangs off it.
func _on_knocked_out(_round_damage: float) -> void:
	if _in_knockout:
		return
	_in_knockout = true
	_reaction_until_msec = 0
	_end_drag()
	_set_state(&"knockout")

	var b := ItemDB.balance
	var tree := get_tree()

	# Frozen for the whole beat so the collapse is a scripted, repeatable animation rather
	# than whatever the solver does with a body full of accumulated impulse. D4: the
	# knockout is choreography, not simulated dismemberment.
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	global_rotation = 0.0

	# The art topples him now, so the body must NOT also be rotated — doing both would turn
	# a sprite that has already fallen sideways on its side again. The tween version of this
	# beat is the fallback for a build with no art, which is what `_beat_time` picks between.
	#
	# Three timers chained through bound methods rather than three awaits. A coroutine
	# resumed on a freed instance prints an error before the `is_instance_valid(self)` guard
	# it was written for can run; a Callable bound to the node is dropped with the node.
	tree.create_timer(_beat_time(&"collapse", b.knockout_collapse_time)).timeout.connect(_knockout_pile)

func _knockout_pile() -> void:
	_set_state(&"pile")
	AudioManager.play(&"clatter", 0.2)
	get_tree().create_timer(ItemDB.balance.knockout_downtime).timeout.connect(_knockout_reassemble)

func _knockout_reassemble() -> void:
	_set_state(&"reassemble")
	AudioManager.play(&"rattle", 0.2)
	# Moved rather than tweened: he is invisible mid-reassembly anyway (a heap of bones on
	# the floor), so sliding the heap across the screen would read as the pile skating.
	global_position = _home_position()
	var b := ItemDB.balance
	get_tree().create_timer(_beat_time(&"reassemble", b.knockout_reassemble_time)).timeout.connect(_knockout_stand)

func _knockout_stand() -> void:
	freeze = false
	linear_velocity = Vector2.ZERO
	health.reset_meter()
	_cooldowns.clear()
	_in_knockout = false
	_set_state(&"idle")

## How long to hold a phase of the knockout: the animation's own length when the art exists,
## the balance knob when it does not. Reading the animation keeps the beat and the art in
## sync through any retiming in Aseprite, and keeps the game playable before an art pass.
func _beat_time(animation: StringName, fallback: float) -> float:
	if art and art.has_animation(animation):
		var length := art.animation_length(animation)
		if length > 0.0:
			return length
	return fallback

func _set_state(value: StringName) -> void:
	if state == value:
		return
	state = value
	EventBus.buddy_state_changed.emit(value)

# --- placement -------------------------------------------------------------

## Somewhere sensible inside the current window, which is not necessarily where the scene
## authored him — that position assumes a 1280x720 window.
func _home_position() -> Vector2:
	var rect := get_viewport().get_visible_rect()
	var inset := rect.grow(-96.0)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		inset = rect
	return initial_position.clamp(inset.position, inset.end)

func _return_home() -> void:
	global_position = _home_position()
	global_rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

# --- save ------------------------------------------------------------------

## Mood and grime are the player's *position* in the two loops the M3 systems added, so
## they persist. Mood decays toward neutral anyway, but a save that resets it silently
## hands back the 0.6x trough at the start of every session.
func to_save() -> Dictionary:
	return {"buddy": {
		"mood": mood.value if mood else 0.0,
		"grime": grime.value if grime else 0.0,
	}}

func from_save(root: Dictionary) -> void:
	var block: Dictionary = root.get("buddy", {})
	if mood:
		mood.set_value(float(block.get("mood", 0.0)))
	if grime:
		grime.set_value(float(block.get("grime", 0.0)))

## He leaves a white trail when flung — bone, not gold.
func trail_colour() -> Color:
	return Color.WHITE
