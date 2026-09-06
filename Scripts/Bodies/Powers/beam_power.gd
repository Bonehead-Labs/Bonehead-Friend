class_name BeamPower
extends CursorPowerBase

## The magnifying glass: a sustained beam that cooks him while the button is held.
##
## Every other weapon in the game is an *impulse* — a swing, a blast, a punch — and damage
## is measured on the receiver from that impulse (docs/decisions.md D7). A sunbeam has no
## impulse at all, and that is the point of it: it is the first thing in the roster that
## hurts him without moving him, so it works on a buddy pinned in a corner, mid-drag, or
## sitting in a hot tub, where every knockback weapon shoves its own target out of range.
##
## It still reports damage through `Buddy.take_impulse`, because that is the one door into
## the payout pipeline. What it hands over is a notional impulse per tick rather than a
## measured collision — the same trick `GunPower` uses, minus the shove.

## Notional impulse per second of contact, before augments. Read as damage: the receiver
## converts it with `damage_per_impulse` exactly as it does a bat.
@export var impulse_per_second: float = 2600.0

## How often the beam pays. Faster ticks are smoother and cost more signals; four a second
## is fast enough that the payout numbers read as a stream and slow enough that eight hours
## of it is not eight hours of bus traffic.
@export var tick_seconds: float = 0.25

## Extra reach around his interaction box, so a beam does not wink out on the exact pixel
## his outline ends. Matches the open hand's generosity for the same reason.
@export var reach_padding: float = 12.0

var _burning := false
var _next_tick_msec := 0
## Where the beam is pointed. Tracked from the events themselves rather than polled from
## `get_global_mouse_position()`, so a pushed event can drive it — the OS cursor cannot be
## moved by a test or by a capture tool.
var _aim := Vector2.ZERO

func _on_activated() -> void:
	set_process(true)

func _on_deactivated() -> void:
	set_process(false)
	_burning = false

## Watches every release and every motion, not only the unhandled ones: a release consumed
## by a panel still ends the beam, and the aim has to keep up with a drag that leaves him.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim = (event as InputEventMouseMotion).position
	if not _burning:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_burning = false

func _process(_delta: float) -> void:
	if not active or not _burning:
		return
	if not can_fire_at(_aim):
		return
	_burn_if_ready(_aim)

func fire(at: Vector2) -> void:
	_aim = at
	_burning = true
	_burn_if_ready(at)

func _burn_if_ready(at: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_tick_msec:
		return
	var interval := tick_seconds * Progression.get_modifier(item_id, &"cooldown_mult")
	_next_tick_msec = now + int(interval * 1000.0)
	_burn(at)

func _burn(at: Vector2) -> void:
	var buddy := _buddy()
	if buddy == null:
		return
	# The tick's worth of damage, so a cooldown augment that doubles the tick rate does not
	# also double the damage — it makes the same damage arrive in smaller, more frequent
	# pieces, which is what a fire-rate upgrade should mean on a beam.
	buddy.take_impulse(impulse_per_second * tick_seconds, item_id, effective_damage_mult(), at)
	# Heat off the spot. The beam has no impulse and so no chips of its own; without this
	# the sunbeam was a number and a face and nothing at the point being cooked.
	var fx := WorldFX.of(self)
	if fx:
		fx.heat(at)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

## Declining a click leaves it unhandled, so the world still sees it — the same contract
## the open hand relies on to stay draggable everywhere except on top of him.
func can_fire_at(at: Vector2) -> bool:
	var buddy := _buddy()
	if buddy == null:
		return false
	return buddy.get_interaction_rect().grow(reach_padding).has_point(at)

## By group, never by path — the buddy lives in a different scene from this power
## (docs/decisions.md D9).
func _buddy() -> Buddy:
	return get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
