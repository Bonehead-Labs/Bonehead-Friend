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

func _ready() -> void:
	super._ready()
	add_to_group(GROUP_BUDDY)
	initial_position = global_position

	contact_monitor = true
	max_contacts_reported = MAX_CONTACTS

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
	if grime.face == null:
		grime.face = face

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
	if expression:
		if _prev_vy > LANDING_SPEED and vy < LANDING_SPEED * 0.2:
			expression.notice_landing(_prev_vy)
		expression.notice_airborne(state_.get_contact_count() == 0 and not freeze,
			state_.linear_velocity)
	_prev_vy = vy
	if health == null or health.down:
		return
	var b := ItemDB.balance
	for i in state_.get_contact_count():
		var impulse: float = state_.get_contact_impulse(i).length()
		if impulse < b.min_damage_impulse:
			continue
		var src := state_.get_contact_collider_object(i)
		if not _cooldown_ready(src, b.damage_cooldown):
			continue
		var attribution := _attribute(src)
		# get_contact_local_position is global despite the name: "local" distinguishes
		# this body's contact point from the collider's, not the coordinate space.
		_queue_hit(impulse, attribution[0], attribution[1], state_.get_contact_local_position(i))

## Damage from a source that is not a contact — an explosion's blast, a gunshot. Fed the
## same kind of impulse the contact solver produces so there is one damage model, not two.
func take_impulse(impulse: float, source_id: StringName, damage_mult: float, at: Vector2) -> void:
	if health == null or health.down:
		return
	if impulse < ItemDB.balance.min_damage_impulse:
		return
	_queue_hit(impulse, source_id, damage_mult, at)

func _queue_hit(impulse: float, source_id: StringName, damage_mult: float, at: Vector2) -> void:
	var b := ItemDB.balance
	var amount := EconomyMath.damage_from_impulse(impulse, b.min_damage_impulse, b.damage_per_impulse, damage_mult)
	if amount <= 0.0:
		return
	# One pathological impulse — a tunnelling collision, a physics blow-up — must not pay
	# out a whole round.
	amount = minf(amount, b.knockout_damage * b.max_hit_fraction)
	_pending_hits.append(HitInfo.new(amount, source_id, at, impulse))

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
	if src is BaseDraggable:
		return [(src as BaseDraggable).item_id, 1.0]
	return [&"world", 1.0]

## Above this many tracked sources, expired entries are swept. Items are spawned and binned
## all session; without a sweep this dictionary grows for every object that ever touched him,
## which in a game designed to idle for eight hours is an unbounded leak.
const COOLDOWN_SWEEP_AT := 64

## A weapon left leaning against him produces a contact impulse every tick. The cooldown
## is what stops that farming Bones while the player is away from the desk.
func _cooldown_ready(src: Object, cooldown: float) -> bool:
	var key := src.get_instance_id() if src != null else 0
	var now := Time.get_ticks_msec()
	if now < int(_cooldowns.get(key, 0)):
		return false
	if _cooldowns.size() >= COOLDOWN_SWEEP_AT:
		_sweep_cooldowns(now)
	_cooldowns[key] = now + int(cooldown * 1000.0)
	return true

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
	await tree.create_timer(_beat_time(&"collapse", b.knockout_collapse_time)).timeout

	if not is_instance_valid(self):
		return
	_set_state(&"pile")
	AudioManager.play(&"clatter", 0.2)
	await tree.create_timer(b.knockout_downtime).timeout

	if not is_instance_valid(self):
		return
	_set_state(&"reassemble")
	AudioManager.play(&"rattle", 0.2)
	# Moved rather than tweened: he is invisible mid-reassembly anyway (a heap of bones on
	# the floor), so sliding the heap across the screen would read as the pile skating.
	global_position = _home_position()
	await tree.create_timer(_beat_time(&"reassemble", b.knockout_reassemble_time)).timeout

	if not is_instance_valid(self):
		return
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
