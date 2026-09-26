class_name TickleAbility
extends SustainAbility

## The feather duster's Tickle (docs/decisions.md D78): hold right with it on him and it flutters,
## and he cannot stop giggling.
##
## A sustain, the chainsaw's archetype turned inside out: the same hold, the same fuel and the same
## tick, and where the saw's chain grinds this one tickles. While right is held the duster
## flutters — its picture shivers and rocks on the hand, faster as it comes up to speed over
## `spin_up` — and feathers drift off it. Every `tick_seconds` that its feathers are on him (its
## shapes in him, a contact, or its tip within `reach`) he giggles: one act of kindness worth
## `giggle_value`, paid on the bus as a pet is (the combo climbs with each one), a few hearts off
## him, and his `tickled` row — squirming, blissful, for as long as it keeps coming. `fuel_seconds`
## of fluttering to a use.
##
## Nothing here touches his body or bills him: a tickle is an act, and the duster's own rate for
## being held against him goes on paying as it always did. The giggles are what the ability adds.
##
## Row: `fuel_seconds`, `spin_up`, `tick_seconds`, `giggle_value`, `reach`, `flutter`.

const FEATHER := Color("f7b2d9")
const FEATHER_LIGHT := Color("d9a0ff")

var _feathers: GPUParticles2D
var _sprite_rot := INF

## For the suites: the giggles it paid for this run.
var giggles := 0

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(1.0 - _t / maxf(num("fuel_seconds", 2.4), 0.01), 0.0, 1.0)

func _on_press() -> void:
	_rev = 0.0
	_t = 0.0
	_next_tick = num("tick_seconds", 0.3) * 0.5
	giggles = 0
	grinds = 0
	peak_rev = 0.0
	run(true)
	# Where the feathers are: the end of it furthest from the hand.
	_feathers = emitter("feathers", &"chip", FEATHER, 10, body.to_local(tip_world()),
		Vector2(0, -40), 150.0, 1.1, Vector2(0, 50))
	emit_from(_feathers, true)
	sound(&"flutter", -8.0, 1.0)
	AbilityCues.activation(self, tip_world())
	AbilityCues.state(self, true, tip_world())
	_update_pip()

func _on_tick(delta: float) -> void:
	_t += delta
	_rev = minf(1.0, _rev + delta / maxf(num("spin_up", 0.25), 0.01))
	peak_rev = maxf(peak_rev, _rev)
	_shake_sprite()
	_next_tick -= delta
	if _next_tick <= 0.0:
		_next_tick = num("tick_seconds", 0.3)
		_engine_tick()
	if _t >= num("fuel_seconds", 2.4):
		finish()

## The focus went with right held (D70): the flutter stops, as if right had been let go.
func _on_focus_lost() -> bool:
	finish()
	return true

## One flutter: a rustle, and if the feathers are on him, a giggle.
func _engine_tick() -> void:
	sound(&"flutter", lerpf(-16.0, -9.0, _rev), 0.9 + 0.4 * _rev, 0.08)
	var him := buddy()
	if him == null or _rev < 0.5:
		return
	if not _on_him(him):
		return
	giggles += 1
	var at := him.get_interaction_rect().get_center() + Vector2(randf_range(-14.0, 14.0), -20.0)
	give(num("giggle_value", 0.8), at)
	notice_player()
	var fx := fx()
	if fx:
		fx.burst(at, &"heart", WorldFX.kind_colour(body.juice_tier), 2 + body.juice_tier, 110.0, 0.6)
		fx.chips(tip_world(), FEATHER_LIGHT, 2, 120.0)
	if giggles % 2 == 1:
		sound(&"giggle", -6.0, 1.0 + 0.04 * float(mini(giggles, 8)))
	tell(&"tickled", at)
	AbilityCues.payoff(self, &"tickle", at, "hee!" if giggles == 1 else "")

## The feathers are on him: a shape of it inside him, a contact, or the tip within `reach`.
func _on_him(him: Buddy) -> bool:
	return body.get_colliding_bodies().has(him) or overlaps_him() \
		or touches_him(tip_world(), num("reach", 14.0))

## The flutter: the picture shivers and rocks about the hand, faster as it comes up to speed —
## the picture only, so the body the hand holds is exactly where it was.
func _shake_sprite() -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_rest == Vector2.INF:
		_sprite_rest = s.position
		_sprite_rot = s.rotation
	var k := Settings.intensity_scale()
	var amp := (0.5 + 1.0 * _rev) * k
	s.position = _sprite_rest + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)).round()
	s.rotation = _sprite_rot + sin(_t * TAU * lerpf(6.0, 14.0, _rev)) * num("flutter", 0.3) * _rev * k

func _on_stop() -> void:
	emit_from(_feathers, false)
	var s := sprite()
	if s and _sprite_rot != INF:
		s.rotation = _sprite_rot
	_sprite_rot = INF
	super._on_stop()
	AbilityCues.state(self, false, tip_world())
