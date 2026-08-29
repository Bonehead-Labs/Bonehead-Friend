class_name EffectsPlayer extends Node

## Per-entity VFX: the hit flash and the explosion burst. Screen-wide effects (floating
## numbers, hit-stop) belong to FXLayer, which is pooled and Focus-Mode gated; this stays
## for effects that are attached to one node.

## How long an explosion node lives before freeing itself. Must outlast the
## particle lifetime in Explosion.tscn.
const EXPLOSION_LIFETIME := 2.0

@export var sprite: AnimatedSprite2D
@export var ExplosionScene: PackedScene = preload("res://Scenes/Effects/Explosion.tscn")

func hit_effect() -> void:
	if sprite == null:
		return
	sprite.modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

func heal_effect() -> void:
	if sprite == null:
		return
	sprite.modulate = Color.GREEN
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

func death_effect() -> void:
	pass

func explosion_effect(at: Vector2) -> void:
	if ExplosionScene == null:
		return
	var explosion := ExplosionScene.instantiate()
	# Parent to the current scene so the explosion outlives the exploding item.
	var host := get_tree().current_scene
	if host == null:
		return
	host.add_child(explosion)
	explosion.global_position = at
	var particles := explosion.get_node_or_null("_particleEffect") as CPUParticles2D
	if particles:
		particles.emitting = true
	# Every explosion used to leak its node permanently. In a game left running all day
	# that is an unbounded node count.
	explosion.get_tree().create_timer(EXPLOSION_LIFETIME).timeout.connect(
		func() -> void:
			if is_instance_valid(explosion):
				explosion.queue_free()
	)
