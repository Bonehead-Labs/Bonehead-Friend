class_name EffectsPlayer extends Node

@export var sprite: AnimatedSprite2D
@export var Character: Node2D
@export var ExplosionScene: PackedScene = preload("res://Scenes/Effects/Explosion.tscn")


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
	
func explosion_effect():
	var explosion = ExplosionScene.instantiate()
	explosion.global_position = Character.global_position
