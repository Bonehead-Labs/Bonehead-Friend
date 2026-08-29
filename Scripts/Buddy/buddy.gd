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

const GROUP_BUDDY := &"buddy"

## How far outside the visible area he may get before being rescued.
const OUT_OF_BOUNDS_MARGIN := 1200.0

## Contacts reported per physics tick. Four is the architecture's number; eight costs
## nothing measurable and stops a busy pile-up silently dropping the hit that mattered.
const MAX_CONTACTS := 8

@export var health: HealthComponent
@export var face: AnimatedSprite2D

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

func _ready() -> void:
	super._ready()
	add_to_group(GROUP_BUDDY)
	initial_position = global_position

	contact_monitor = true
	max_contacts_reported = MAX_CONTACTS

	if health:
		health.max_damage = ItemDB.balance.knockout_damage
		health.knocked_out.connect(_on_knocked_out)

func _process(_delta: float) -> void:
	# Failsafe if he escapes the world. Measured against the actual viewport, because the
	# window is resizable — a fixed distance is meaningless when the play area can be
	# anything from 320x240 to an ultrawide. The prototype's check tested y < -2000, which
	# is *upward*: the one direction gravity guarantees he will not go.
	var bounds := get_viewport().get_visible_rect().grow(OUT_OF_BOUNDS_MARGIN)
	if not bounds.has_point(global_position):
		_return_home()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _pending_hits.is_empty():
		return
	var hits := _pending_hits.duplicate()
	_pending_hits.clear()
	for info in hits:
		_deal(info)

# --- damage ----------------------------------------------------------------

func _integrate_forces(state_: PhysicsDirectBodyState2D) -> void:
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
	health.apply_damage(info.amount)

## Who to bill the hit to, and by how much. Anything without a script is still a weapon —
## it just has no multiplier and no mastery.
func _attribute(src: Object) -> Array:
	if src is WeaponBase:
		var w := src as WeaponBase
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

# --- knockout --------------------------------------------------------------

## The round's climax. Economy pays the bonus off buddy_state_changed — Economy is the
## only thing in the game allowed to mint currency, so the buddy announces rather than
## awards. The collapse animation and bone pile land in M3.
func _on_knocked_out(_round_damage: float) -> void:
	_set_state(&"knockout")
	_end_drag()
	await get_tree().create_timer(ItemDB.balance.knockout_downtime).timeout
	if not is_instance_valid(self):
		return
	_return_home()
	health.reset_meter()
	_cooldowns.clear()
	_set_state(&"idle")

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
