class_name Weapon
extends BaseDraggable

## Melee weapons. Damage here is still the prototype's attacker-side estimate; the
## contact-impulse rewrite lands in M2 (docs/decisions.md D7). What changed in M0 is
## only that it no longer reads a shapeless free-falling body's velocity.

@export var AttackBox: AttackBox
@export var min_damage: int = 0
@export var max_damage: int = 40

## Scales this weapon's contribution once receiver-side damage lands.
@export var damage_mult: float = 1.0

func _on_attack_box_area_entered(area: Area2D) -> void:
	if not (area is HitBoxComponent):
		return
	var target := (area as HitBoxComponent).body
	if not (target is Character):
		return

	# Interim model: this body's own speed at the moment of contact, scaled by mass.
	# It is at least measuring the thing doing the hitting, unlike the old _attackBody
	# probe, which measured time-since-last-hit.
	var impact := linear_velocity.length() / 1000.0 * mass * damage_mult
	var damage := clampf(impact, float(min_damage), float(max_damage))
	target.hurtbox.damage(int(damage))
