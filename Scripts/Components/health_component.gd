class_name HealthComponent
extends Node

## Bonehead's knockout meter.
##
## Deliberately NOT hit points: it fills with damage and, when full, triggers the knockout
## beat. There is no fail state in this game (docs/game-design.md pillar 1), so nothing
## here can kill anything — "health" would be the wrong word for what the bar means.

signal damaged(amount: float, total: float)
signal knocked_out(round_damage: float)
signal meter_reset()

## Damage needed to collapse him. Overwritten from balance.tres at boot; the export is the
## fallback for a scene opened on its own in the editor.
@export var max_damage: float = 400.0

var damage: float = 0.0
var down: bool = false

func fill_fraction() -> float:
	if max_damage <= 0.0:
		return 0.0
	return clampf(damage / max_damage, 0.0, 1.0)

## Returns true if this hit was the one that knocked him out.
func apply_damage(amount: float) -> bool:
	if amount <= 0.0 or down:
		return false
	damage += amount
	damaged.emit(amount, damage)
	if damage >= max_damage:
		down = true
		knocked_out.emit(damage)
		return true
	return false

func reset_meter() -> void:
	damage = 0.0
	down = false
	meter_reset.emit()
