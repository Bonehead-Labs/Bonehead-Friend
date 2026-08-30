extends Node

## Rebuilds Explosion.tscn onto the generated animation.
##
## The prototype's explosion was an untextured `CPUParticles2D` — a spray of white squares.
## `art-direction.md` lists a real explosion in the VFX set, and it is the effect the
## grenade, the dynamite and the missile all share, so it is the highest-traffic VFX in the
## game. `EffectsPlayer.explosion_effect()` already instances this scene and frees it after
## `EXPLOSION_LIFETIME`, so nothing else has to change.

const FRAMES := "res://art/src/explosion.aseprite"

func _ready() -> void:
	var frames := ResourceLoader.load(FRAMES) as SpriteFrames
	if frames == null:
		push_error("seed_explosion: %s did not import as SpriteFrames" % FRAMES)
		get_tree().quit()
		return
	# One-shot: an explosion that loops is a campfire.
	if frames.has_animation(&"explosion"):
		frames.set_animation_loop(&"explosion", false)

	var root := Node2D.new()
	root.name = "Explosion"

	var sprite := AnimatedSprite2D.new()
	sprite.name = "_particleEffect"   # kept: EffectsPlayer looks this node up by name
	sprite.sprite_frames = frames
	sprite.animation = &"explosion"
	sprite.autoplay = "explosion"
	sprite.scale = Vector2(2, 2)
	root.add_child(sprite)
	sprite.owner = root

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("seed_explosion: pack failed")
		root.free(); get_tree().quit(); return
	var err := ResourceSaver.save(packed, "res://Scenes/Effects/Explosion.tscn")
	root.free()
	print("seed_explosion: %s" % ("wrote Explosion.tscn" if err == OK else "failed (%d)" % err))
	get_tree().quit()
