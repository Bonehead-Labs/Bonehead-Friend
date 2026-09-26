class_name AbilityCues
extends RefCounted

## The three moments every ability has, named once (docs/decisions.md D78): it **starts**, it is
## **in a state** the player should be able to see from across the desk (a bomb on the clicker, a
## towel round him, a duster fluttering), and it **pays off** (a strike, a catch, a header, a
## donut in his mouth).
##
## The seam between D78's abilities and D77's vocabulary (`AbilityFX`, `AbilityLooks`): D78 built
## it so that its eleven would speak that vocabulary the day the two met, without being touched, and
## these three bodies are where they meet. Each still records what it heard, for the suites.
##
## - `activation` is where the ability says it started. Inside the press, `WeaponAbility` draws the
##   flare and calls out its name itself (D77); this only moves the flare to `at` — a cake's wicks,
##   a ball in the hand — rather than the glint. Anywhere else it draws both there.
## - `state` puts the ability's badge up (`on`) and takes it down: the look's state for the
##   ability's own id, over him or, if the look says `over: weapon`, over the thing itself (a charge
##   on the clicker). It lasts while the ability says it is on, and never past the effect.
## - `payoff` draws the payoff at `at` and calls out `word` ("STRIKE!", "3!"), then emits the
##   ability's `paid_off`, which the suites and the capture tool already listen for.
##
## Static, and free of state: what it draws lives on the ability and in `AbilityFX`.

## An activation began: right pressed and taken, at `at` in the world.
static func activation(ability: WeaponAbility, at: Vector2) -> void:
	if ability == null:
		return
	ability.cue_count += 1
	ability.last_cue = &"activation"
	ability.last_cue_at = at
	ability.fx_cue_activation(at)

## A state the ability holds for a while began (`on`) or ended.
static func state(ability: WeaponAbility, on: bool, at: Vector2) -> void:
	if ability == null:
		return
	ability.cue_count += 1
	ability.last_cue = &"state_on" if on else &"state_off"
	ability.last_cue_at = at
	ability.fx_cue_state(on)

## It landed. `event` is what the suites know it by; `word` is the callout, empty for none.
static func payoff(ability: WeaponAbility, event: StringName, at: Vector2, word: String = "") -> void:
	if ability == null:
		return
	ability.cue_count += 1
	ability.last_cue = &"payoff"
	ability.last_cue_at = at
	ability.last_word = word
	if at.is_finite():
		ability.fx_at = at
	ability.fx_word = word
	ability.paid_off.emit(event)
