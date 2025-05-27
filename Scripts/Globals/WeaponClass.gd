class_name Weapon
extends BaseDraggable

@export var AttackBox: AttackBox
# Body attached to weapon's attack box, to determine velocity
@export var _attackBody: RigidBody2D
@export var min_damage: int = 0
@export var max_damage: int= 40

func _on_attack_box_area_entered(area:Area2D) -> void:
	var impact_strength = 0
	if area is HitBoxComponent:
		var body = area.body
		if body.has_method("Character"):
			print(_attackBody.linear_velocity.length())
			impact_strength = _attackBody.linear_velocity.length()/1000 * mass
			_attackBody.linear_velocity = Vector2.ZERO
			print("Impact Strength: ", impact_strength)
			var damage = clamp(impact_strength, min_damage, max_damage)
			print("Damage: ", damage)
			body.hurtbox.damage(damage)
