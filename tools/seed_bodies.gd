extends Node

## Rebuilds the prototype weapon and throwable scenes onto the generated art.
##
##   Godot --headless --path <project> res://tools/seed_bodies.tscn [-- --force]
##
## `Scenes/Bodies/*.tscn` were hand-authored in the prototype: an `AnimatedSprite2D` holding
## a one-frame `SpriteFrames` of a sprite drawn to fill its 64x64 cell, at a 2x node scale
## with colliders eyeballed to match. That is why a hand grenade rendered 55 px tall next to
## a 63 px buddy. New sprites cannot reach those scenes without rebuilding them, so this
## does — from the scale table, with colliders derived from the sprite rather than guessed.
##
## Mass is deliberately unchanged from the prototype values. Damage is contact impulse and
## impulse is mass times velocity (docs/decisions.md D7), so re-authoring the visuals must
## not quietly re-tune the combat — `loop_check` asserts the payout chain and would catch it,
## but the intent matters more than the assertion.

const WeaponBaseScript := preload("res://Scripts/Bodies/weapon_base.gd")
const ThrowableBaseScript := preload("res://Scripts/Bodies/throwable_base.gd")
const DraggableAreaScript := preload("res://Scripts/Bodies/draggable_area.gd")
const EffectsPlayerScript := preload("res://Scripts/Components/effects_player.gd")

const BODIES_DIR := "res://Scenes/Bodies"
const SPRITES_DIR := "res://Assets/sprites/items"

## Physics, authored per item rather than derived from the sprite's outline.
##
## All values are in **art pixels** — the same space as the scale table in
## `docs/art-direction.md` — and are multiplied by ART_SCALE here, exactly as the sprite is.
##
## A box around the whole picture is the right shape for a crate and the wrong shape for
## everything else. The prototype bat had four things this table brings back, and losing
## them is what turned it from a bat into a plank:
##
##   `shapes`  a capsule for the barrel and a small rect for the grip, not one box
##   `com`     centre of mass up in the barrel, so it swings with weight in the head
##   `grip`    where the drag joint pins — at the handle, so it pivots around your hand
##   `grab`    the drag region, over the handle rather than over the whole silhouette
##
## Anything not listed falls back to a box around the sprite's opaque bounds, pinned and
## balanced at its centre, which is correct for a grenade and a ball.
const PHYSICS := {
	&"baseball_bat": {
		"shapes": [
			{"capsule": Vector2(10, 30), "at": Vector2(0, -10)},
			{"rect": Vector2(6, 18), "at": Vector2(0, 16)},
		],
		"com": Vector2(0, -12),
		"grip": Vector2(0, 18),
		"grab": {"size": Vector2(16, 28), "at": Vector2(0, 14)},
	},
	&"mace": {
		"shapes": [
			{"circle": 13.0, "at": Vector2(0, -10)},
			{"rect": Vector2(6, 18), "at": Vector2(0, 14)},
		],
		"com": Vector2(0, -11),
		"grip": Vector2(0, 16),
		"grab": {"size": Vector2(16, 26), "at": Vector2(0, 13)},
	},
}

const ART_SCALE := 2.0

const LAYER_ITEM := 4
const ITEM_MASK := 1 | 2 | 4          # world | buddy | item
const LAYER_SENSOR := 32              # blast area only ever sees buddy + items
const BLAST_MASK := 2 | 4

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")

	# name, id, script, mass, damage_mult, extra properties, blast radius (0 = not a throwable)
	_body("_BaseballBat", &"baseball_bat", WeaponBaseScript, 8.0, {"damage_mult": 1.0}, 0.0)
	_body("_Mace", &"mace", WeaponBaseScript, 12.0, {"damage_mult": 1.4}, 0.0)
	_body("_Grenade", &"grenade", ThrowableBaseScript, 1.2,
		{"damage_mult": 1.0, "throwable_delay": 3.0, "max_force": 10000.0}, 120.0)
	_body("_Dynamite", &"dynamite", ThrowableBaseScript, 1.6,
		{"damage_mult": 1.5, "throwable_delay": 3.0, "max_force": 16000.0}, 180.0)

	print("seed_bodies: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _body(node_name: String, item_id: StringName, script: Script, body_mass: float,
		properties: Dictionary, blast_radius: float) -> void:
	var path := "%s/%s.tscn" % [BODIES_DIR, node_name.trim_prefix("_").to_snake_case()]
	if not _should_write(path):
		return

	var sprite_path := "%s/%s.png" % [SPRITES_DIR, item_id]
	var texture := ResourceLoader.load(sprite_path) as Texture2D
	if texture == null:
		push_error("seed_bodies: no sprite at %s" % sprite_path)
		return

	var root := RigidBody2D.new()
	root.name = node_name
	root.set_script(script)
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	root.mass = body_mass
	root.contact_monitor = true
	root.max_contacts_reported = 4
	root.set(&"item_id", item_id)
	for key in properties:
		root.set(StringName(key), properties[key])

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	root.add_child(sprite)

	var physics: Dictionary = PHYSICS.get(item_id, {})
	var collider: CollisionShape2D = null
	if physics.has("shapes"):
		# Authored: one CollisionShape2D per entry, so a bat is a barrel and a grip rather
		# than a rectangle enclosing both.
		for entry in physics["shapes"]:
			var piece := CollisionShape2D.new()
			piece.name = "CollisionShape2D" if collider == null else "CollisionShape2D%d" % root.get_child_count()
			piece.shape = _shape_from(entry)
			piece.position = (entry["at"] as Vector2) * ART_SCALE
			root.add_child(piece)
			if collider == null:
				collider = piece
		root.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
		root.center_of_mass = (physics["com"] as Vector2) * ART_SCALE
		root.set(&"grip_offset", (physics["grip"] as Vector2) * ART_SCALE)
	else:
		# Derived from the sprite's own opaque bounds, at the same scale, rather than a
		# hand-tuned rectangle that drifts every time the art changes. Right for a grenade,
		# a ball and anything else with no handle.
		var extent := _content_size(texture) * ART_SCALE
		var shape := RectangleShape2D.new()
		shape.size = extent
		collider = CollisionShape2D.new()
		collider.name = "CollisionShape2D"
		collider.shape = shape
		root.add_child(collider)

	var grab_shape := RectangleShape2D.new()
	var grab_at := Vector2.ZERO
	if physics.has("grab"):
		var grab: Dictionary = physics["grab"]
		grab_shape.size = (grab["size"] as Vector2) * ART_SCALE
		grab_at = (grab["at"] as Vector2) * ART_SCALE
	else:
		# A grab region no smaller than a comfortable click target: the dynamite is 26 px
		# tall and nobody can reliably click 26 px while it is tumbling.
		var extent := _content_size(texture) * ART_SCALE
		grab_shape.size = Vector2(maxf(extent.x + 16.0, 40.0), maxf(extent.y + 16.0, 40.0))
	# Whatever the shape, it has to be clickable.
	grab_shape.size = Vector2(maxf(grab_shape.size.x, 34.0), maxf(grab_shape.size.y, 34.0))
	var grab_collider := CollisionShape2D.new()
	grab_collider.name = "CollisionShape2D"
	grab_collider.shape = grab_shape
	grab_collider.position = grab_at

	var drag_area := Area2D.new()
	drag_area.name = "DraggableArea"
	drag_area.set_script(DraggableAreaScript)
	drag_area.add_child(grab_collider)
	root.add_child(drag_area)

	var handle := StaticBody2D.new()
	handle.name = "Handle"
	handle.visible = false
	handle.collision_layer = 0
	handle.collision_mask = 0
	root.add_child(handle)

	var effects := Node.new()
	effects.name = "EffectsPlayer"
	effects.set_script(EffectsPlayerScript)
	root.add_child(effects)

	# Wired, which the first version forgot. `sprite` is what a primed grenade flashes and
	# what an exploded one hides, so a null here is an explosive with no tell that it is
	# live and a sprite that outlives its own blast.
	root.set(&"sprite", sprite)
	root.set(&"drag_area", drag_area)
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	root.set(&"Effects_Player", effects)

	if blast_radius > 0.0:
		var blast_shape := CircleShape2D.new()
		blast_shape.radius = blast_radius
		var blast_collider := CollisionShape2D.new()
		blast_collider.name = "CollisionShape2D"
		blast_collider.shape = blast_shape

		var blast := Area2D.new()
		blast.name = "ExplosionArea"
		blast.collision_layer = 0
		blast.collision_mask = BLAST_MASK
		blast.monitoring = false
		blast.add_child(blast_collider)
		root.add_child(blast)
		root.set(&"explosion_area", blast)

	_save_scene(root, path)

static func _shape_from(entry: Dictionary) -> Shape2D:
	if entry.has("circle"):
		var circle := CircleShape2D.new()
		circle.radius = float(entry["circle"]) * ART_SCALE
		return circle
	if entry.has("capsule"):
		var size: Vector2 = entry["capsule"]
		var capsule := CapsuleShape2D.new()
		capsule.radius = size.x * 0.5 * ART_SCALE
		capsule.height = size.y * ART_SCALE
		return capsule
	var rect := RectangleShape2D.new()
	rect.size = (entry["rect"] as Vector2) * ART_SCALE
	return rect

## Opaque bounds of the sprite, which is what the collider should match — the cell around it
## is empty space by design (the scale table sizes content, not cells).
func _content_size(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Vector2(image.get_width(), image.get_height())
	return Vector2(used.size)

func _save_scene(root: Node, path: String) -> void:
	_claim(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("seed_bodies: failed to pack %s" % path)
		root.free()
		return
	var err := ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("seed_bodies: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)

func _claim(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_claim(child, owner_node)

func _should_write(path: String) -> bool:
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false
