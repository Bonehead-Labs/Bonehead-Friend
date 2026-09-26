class_name AbilityCues
extends RefCounted

## The three moments every ability has, named once (docs/decisions.md D78): it **starts**, it is
## **in a state** the player should be able to see from across the desk (a bomb on the clicker, a
## towel round him, a duster fluttering), and it **pays off** (a strike, a catch, a header, a
## donut in his mouth).
##
## A shared readability vocabulary for abilities — the ready tell, the callout, the state visual,
## the payoff — is being built on another branch (`wt/fx-abilities`). This is not a second one. It
## is the seam D78's abilities call at those three moments, so that at the merge these three bodies
## are pointed at that vocabulary and every D78 ability speaks it without being touched. Until
## then each ability draws its own effects, as D74's do, and these only record: `payoff` emits the
## ability's `paid_off`, which the suites and the capture tool already listen for, and `word` is the
## callout the vocabulary will print ("STRIKE!", "3!").
##
## Static, and free of state, so the merge is a change to this file alone.

## An activation began: right pressed and taken, at `at` in the world.
static func activation(ability: WeaponAbility, at: Vector2) -> void:
	if ability == null:
		return
	ability.cue_count += 1
	ability.last_cue = &"activation"
	ability.last_cue_at = at

## A state the ability holds for a while began (`on`) or ended.
static func state(ability: WeaponAbility, on: bool, at: Vector2) -> void:
	if ability == null:
		return
	ability.cue_count += 1
	ability.last_cue = &"state_on" if on else &"state_off"
	ability.last_cue_at = at

## It landed. `event` is what the suites know it by; `word` is the callout, empty for none.
static func payoff(ability: WeaponAbility, event: StringName, at: Vector2, word: String = "") -> void:
	if ability == null:
		return
	ability.cue_count += 1
	ability.last_cue = &"payoff"
	ability.last_cue_at = at
	ability.last_word = word
	ability.paid_off.emit(event)
