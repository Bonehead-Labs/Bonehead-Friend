class_name HitBoxComponent extends Area2D

@export var health_component: HealthComponent
@export var body: BaseDraggable

func damage(attack: int):
	if health_component:
		health_component.ReduceHealth(attack)
