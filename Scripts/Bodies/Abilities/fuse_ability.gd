class_name FuseAbility
extends WeaponAbility

## A lit charge's second right press (docs/decisions.md D78): it takes the fuse over.
##
## Every explosive already uses right while held: it lights the fuse (`ThrowableBase`), and D59
## made Shift+right the bin for them. So an explosive's ability is not the first press — that stays
## the fuse, untouched, and this archetype declines it (`_wants_press`) so it reaches the charge
## exactly as before. It is the **second**: right again while the charge is lit and still in the
## hand. From then the charge no longer goes off when its timer says. It goes when the ability says
## (`go`) — a click on it, the moment it is over him — or after `wait_seconds` whatever happens,
## so a charge on hold can never be left live on the desk.
##
## Nothing here bills him. The blast is the charge's own, down its own receiver-side path (D7), at
## its own multiplier: an explosive's ability changes *when* and *where*, never how hard. The
## charge asks `holds_fuse` before it goes (`ThrowableBase.fuse_held`), which is the whole of the
## change to the explosives.
##
## Consumed: the charge is gone after the blast, so there is no cooldown to wait out. A press while
## it is not lit is not this ability's; a press while it is held is `_press_again`'s.
##
## Row: `wait_seconds`, and the hook's own.

var _holding := false
var _t := 0.0

## For the suites: why it went, and how long it was held.
var went := &""
var held_for := 0.0

func charge() -> ThrowableBase:
	return body as ThrowableBase

## The fuse is on hold: the charge's own timer is ignored until `go`.
func holds_fuse() -> bool:
	return _active and _holding

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(1.0 - _t / maxf(num("wait_seconds", 10.0), 0.01), 0.0, 1.0)

## The first right press on an unlit charge is its fuse, not this.
func _wants_press() -> bool:
	var c := charge()
	return c != null and c.is_primed

func _can_start() -> bool:
	var c := charge()
	return c != null and c.is_primed and not c.is_queued_for_deletion()

func _on_press() -> void:
	_holding = true
	_t = 0.0
	went = &""
	held_for = 0.0
	run(true)
	AbilityCues.activation(self, com_world())
	AbilityCues.state(self, true, com_world())
	_on_hold()

## A tap: nothing happens on the release.
func _on_release(_seconds: float) -> void:
	pass

## Out of the hand is where a charge on hold is meant to be.
func _on_dropped() -> void:
	pass

func _on_tick(delta: float) -> void:
	_t += delta
	held_for = _t
	if _t >= num("wait_seconds", 10.0):
		go(&"timeout")
		return
	_on_holding(delta)

## Now: the fuse lets go and the charge goes off, here, the ordinary way.
func go(why: StringName) -> void:
	if not _active:
		return
	went = why
	_holding = false
	var c := charge()
	var at := com_world()
	_before_go()
	finish(0.0)
	AbilityCues.state(self, false, at)
	if c and is_instance_valid(c) and not c.is_queued_for_deletion():
		c.explode()

# --- the hook's --------------------------------------------------------------------------

## The fuse was just taken over.
func _on_hold() -> void:
	pass

## Every tick while it is held.
func _on_holding(_delta: float) -> void:
	pass

## Just before the charge goes.
func _before_go() -> void:
	pass
