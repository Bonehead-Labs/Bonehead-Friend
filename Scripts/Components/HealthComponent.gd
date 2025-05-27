class_name HealthComponent
extends Node2D

var Health: int
@export var Max_Health: int
@export var Entity: Node2D

signal EntityKilled
signal EntityDamaged
signal EntityHealed

func _ready() -> void:
	Health = Max_Health

func ReduceHealth(amount):
	Health -= amount
	EntityDamaged.emit()
	if Health <= 0:
		EntityKilled.emit()

	
func IncreaseHealth(amount):
	Health += amount
	EntityHealed.emit()
	if Health >= Max_Health:
		Health = Max_Health
