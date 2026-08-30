class_name FriendlyBase
extends BaseDraggable

## Everything on the kindness side of the toy box, as one class with three switches.
##
## The friendly catalog has three shapes and only three (docs/economy.md): a burst on
## touch (pizza), sustained payment while something is true (sponge scrubbing, boombox
## playing), and a consumable that leaves when used. Each is an exported number here, so a
## new friendly item is a `.tres` plus a scene with different values in it — never a script
## (docs/decisions.md D8). One class also means the combo window, the mood nudge and the
## Hearts payout behave identically across the whole friendly roster, which matters
## because Economy applies the same pipeline to all of them.

## One-off Hearts when he first touches this, then nothing until `contact_cooldown` has
## passed. Pizza. Zero disables.
@export var hearts_per_contact: float = 0.0
@export var contact_cooldown: float = 1.0

## Hearts per second while he is touching it. Zero disables.
@export var hearts_per_second_touching: float = 0.0

## Hearts per second simply for existing in the world — the boombox and the rest of the
## Hearts generators. This is the shape every automation capstone will take, which is why
## it is a plain rate on a spawned object rather than anything cleverer.
@export var hearts_per_second_placed: float = 0.0

## Grime removed per second of contact. The sponge, and only the sponge. Payment is on
## grime *actually removed*, so scrubbing a clean skeleton earns nothing.
@export var cleans_grime: bool = false

## Vanishes once it has paid out. Food.
@export var consume_on_use: bool = false

## Minimum closing speed for `hearts_per_contact` to pay. The baseball's catch mechanic:
## he catches a *throw*, so resting a ball against him — or dropping it from one pixel up —
## must be worth nothing. Zero disables the check, which is what the pizza wants.
@export var min_contact_speed: float = 0.0

## How long the item sits in the world before it stops paying its placed rate. Zero means
## forever. Nothing uses it yet; it exists so a consumable generator does not need a new
## class when one appears.
@export var lifetime_seconds: float = 0.0

## Sustained kindness is banked and flushed on this interval rather than emitted every
## physics frame. Sixty payouts a second would put sixty floating numbers a second through
## the FX pool and sixty signals a second on the bus, for a rate the player experiences as
## one smooth trickle.
const FLUSH_SECONDS := 0.5

var _next_contact_msec := 0
var _age := 0.0
var _banked := 0.0
var _bank_position := Vector2.ZERO
var _since_flush := 0.0

## Speed on the previous tick. The contact that matters has already been solved by the time
## _physics_process runs, so the ball is *slower* than it was when it hit him — reading only
## the current speed would reject exactly the hardest throws, which are the ones that lose
## the most speed on impact.
var _previous_speed := 0.0

func _ready() -> void:
	super._ready()
	# get_colliding_bodies() is only populated when the body is reporting contacts. A few is
	# plenty: we only ever ask whether one specific body is in the list.
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 4)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_age += delta
	if lifetime_seconds > 0.0 and _age > lifetime_seconds:
		_despawn()
		return

	var value := value_multiplier()
	if hearts_per_second_placed > 0.0:
		_bank(hearts_per_second_placed * value * delta, global_position)

	var buddy := _touching_buddy()
	if buddy != null:
		if hearts_per_second_touching > 0.0:
			_bank(hearts_per_second_touching * value * delta, buddy.global_position)

		if cleans_grime and buddy.grime:
			var removed := buddy.grime.clean(ItemDB.balance.sponge_clean_rate * delta)
			if removed > 0.0:
				# The *pay* scales, not the scrubbing. Scrubbing faster would be a nerf
				# dressed as an upgrade: grime is finite, so a sponge that removes it twice
				# as fast earns the same Hearts in half the time and then has nothing left
				# to clean.
				_bank(removed * ItemDB.balance.hearts_per_grime_cleaned * value,
					buddy.global_position)

		if hearts_per_contact > 0.0 and _approach_speed() >= min_contact_speed:
			var now := Time.get_ticks_msec()
			if now >= _next_contact_msec:
				var gap := contact_cooldown * Progression.get_modifier(item_id, &"cooldown_mult")
				_next_contact_msec = now + int(gap * 1000.0)
				_pay_event(hearts_per_contact * value, buddy.global_position)
				if consume_on_use:
					_flush()
					_despawn()
					return

	_previous_speed = linear_velocity.length()
	_since_flush += delta
	if _since_flush >= FLUSH_SECONDS:
		_flush()

## The kindness-value multiplier, which on this side of the economy is what `damage_mult`
## means (docs/economy.md).
##
## It scales the *value* emitted rather than the Hearts paid, so it is a different node from
## the flat payout multiplier beside it in the tree: MoodComponent nudges his mood by the
## same number, so a better-loved item buys mood as well as Hearts. Without this every
## friendly item's damage node was a placebo — which two of them shipped as in M3, and is
## half the reason M3.5 exists.
func value_multiplier() -> float:
	if item_id == &"":
		return 1.0
	return Progression.get_modifier(item_id, &"damage_mult")

## Kindness goes on the bus as a *value*, not as Hearts. Economy is the only thing allowed
## to mint currency, and it is what applies the combo, the mood curve, the augments and
## prestige — exactly as it does for damage (docs/economy.md, one pipeline).
func _approach_speed() -> float:
	return maxf(linear_velocity.length(), _previous_speed)

func _pay_event(value: float, at: Vector2) -> void:
	if value <= 0.0:
		return
	EventBus.kindness_given.emit(item_id, value, at)

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

func _touching_buddy() -> Buddy:
	for body in get_colliding_bodies():
		if body is Buddy:
			return body as Buddy
	return null

func _despawn() -> void:
	EventBus.item_despawned.emit(self)
	queue_free()

## Banked kindness is paid on the way out, whatever the exit. A sponge binned mid-scrub, or
## evicted by the item limit, otherwise silently swallows up to FLUSH_SECONDS of Hearts —
## and the trash bin and the spawner both free items without going through _despawn().
func _exit_tree() -> void:
	_flush()
