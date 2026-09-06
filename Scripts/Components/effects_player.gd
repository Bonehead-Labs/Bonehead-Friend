class_name EffectsPlayer extends Node

## Per-entity VFX: the hit flash and the explosion burst. Screen-wide effects (floating
## numbers, hit-stop) belong to FXLayer, which is pooled and Focus-Mode gated; this stays
## for effects that are attached to one node.

## How long an explosion node lives before freeing itself. Must outlast the
## particle lifetime in Explosion.tscn.
const EXPLOSION_LIFETIME := 2.0

@export var sprite: AnimatedSprite2D
@export var ExplosionScene: PackedScene = preload("res://Scenes/Effects/Explosion.tscn")

const FLASH_SECONDS := 0.1

## Flashes claim `self_modulate` and never touch `modulate`. GrimeComponent tints the same
## sprite through `modulate`, and the two multiply — so a hit landing on a filthy buddy
## flashes and then returns to *grimy*, rather than scrubbing him clean by resetting the
## wrong property to white.
var _flash_token := 0

func hit_effect() -> void:
	await _flash(Color.RED)

## Overlapping hits are common in a pile-up. Each flash takes a token and only the newest
## one is allowed to clear the tint, so an early timer cannot end a later flash and leave
## him stuck red.
func _flash(colour: Color) -> void:
	if sprite == null:
		return
	_flash_token += 1
	var token := _flash_token
	sprite.self_modulate = colour
	await get_tree().create_timer(FLASH_SECONDS).timeout
	if is_instance_valid(sprite) and token == _flash_token:
		sprite.self_modulate = Color.WHITE

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
	# The effect is a generated animation, found by what it is rather than by name: the
	# scene was rebuilt once and a name lookup across its boundary is the same bug as an
	# absolute node path (CLAUDE.md).
	var animation := _find_animation(explosion)
	if animation and animation.sprite_frames:
		# An explosion must never loop. The Aseprite importer marks every animation as
		# looping, so the effect replayed for the whole life of the node — a 0.5s animation
		# inside a 1.5s node is three explosions for one grenade. Set on the shared
		# SpriteFrames deliberately: there is no case where a looping explosion is right.
		animation.sprite_frames.set_animation_loop(&"explosion", false)
		animation.animation_finished.connect(explosion.queue_free)
		animation.play(&"explosion")
	# Every explosion used to leak its node permanently. In a game left running all day
	# that is an unbounded node count — so a timer frees it whether or not the animation
	# ever finishes. A *bound method*, not a lambda: a lambda capturing `explosion` holds a
	# bare object id, and when the animation has already freed the node the callable
	# validates its captures before running, prints "Lambda capture at index 0 was freed"
	# and hands the body a null — once per explosion, fifteen per cluster throw, and no
	# `is_instance_valid` inside the body can ever see it. A Callable bound to the node is
	# disconnected for free when the node dies.
	explosion.get_tree().create_timer(EXPLOSION_LIFETIME).timeout.connect(explosion.queue_free)

static func _find_animation(root: Node) -> AnimatedSprite2D:
	if root is AnimatedSprite2D:
		return root
	for child in root.get_children():
		var found := _find_animation(child)
		if found:
			return found
	return null
