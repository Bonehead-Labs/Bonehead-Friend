class_name EffectsPlayer extends Node

@export var sprite: AnimatedSprite2D
@export var Character: CharacterBody2D

func hit_effect():
	sprite.modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color.WHITE
	
func heal_effect():
	sprite.modulate = Color.GREEN
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color.WHITE
	
func death_effect():
	pass
	