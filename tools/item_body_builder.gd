class_name ItemBodyBuilder
extends RefCounted

## Builds one draggable item body — sprite, authored colliders, grab region, handle, blast
## area — from a plain dictionary, so a seed tool is a *table* and nothing else.
##
## Extracted from `tools/seed_bodies.gd` (which still carries its own copy for the four
## bodies it has always owned) when the roster went from four melee weapons to thirty and
## several tools needed the same factory at once. A build tool that has to reproduce a
## hundred lines of node wiring to add a hammer is a tool nobody adds a hammer to.
##
## **Everything here is in art pixels** — the same space as the scale table in
## `docs/art-direction.md` — and is multiplied by `ART_SCALE`, exactly as the sprite is.
## Physics is authored, never derived (docs/decisions.md D25): a box around the whole
## picture is right for a grenade and wrong for a sword, and rebuilding the prototype's bat
## from its sprite alone is what turned it from a bat into a plank on a string.
##
## The spec:
##
##   name            node name, e.g. "_Katana"
##   id              item id, the join key into ItemData/augments/mastery
##   script          WeaponBase, ThrowableBase, or a subclass of either
##   mass            kilograms-ish; damage is contact impulse and impulse is mass x velocity
##   properties      extra @export values to set on the root
##   blast_radius    0 for a melee weapon; >0 adds an ExplosionArea
##   shapes          [{capsule|rect|circle, at, rot}] — omit for a box around the sprite
##   com             centre of mass, so a weapon swings with weight where the weight is
##   grip            where the drag joint pins, so it pivots around your hand
##   grab            {size, at} — the click target, usually over the handle
##   sprite          optional res:// override; defaults to Assets/sprites/items/<id>.png

const DraggableAreaScript := preload("res://Scripts/Bodies/draggable_area.gd")
const EffectsPlayerScript := preload("res://Scripts/Components/effects_player.gd")

const SPRITES_DIR := "res://Assets/sprites/items"
const ART_SCALE := 2.0

const LAYER_ITEM := 4
const ITEM_MASK := 1 | 2 | 4          # world | buddy | item
const LAYER_SENSOR := 32              # blast area only ever sees buddy + items
const BLAST_MASK := 2 | 4

## Returns the packed root, or null if the sprite is missing — a body with no picture is an
## invisible object the player collides with, which is worse than no body at all.
static func build(spec: Dictionary) -> Node:
	var id: StringName = spec.get("id", &"")
	var sprite_path: String = spec.get("sprite", "%s/%s.png" % [SPRITES_DIR, id])
	if not ResourceLoader.exists(sprite_path):
		push_error("ItemBodyBuilder: no sprite at %s for '%s'" % [sprite_path, id])
		return null
	var texture := ResourceLoader.load(sprite_path) as Texture2D
	if texture == null:
		push_error("ItemBodyBuilder: %s did not load as a texture" % sprite_path)
		return null

	var root := RigidBody2D.new()
	root.name = String(spec.get("name", "_%s" % id))
	root.set_script(spec.get("script"))
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	root.mass = float(spec.get("mass", 4.0))
	root.contact_monitor = true
	root.max_contacts_reported = 4
	root.set(&"item_id", id)

	var bounce := float(spec.get("bounce", -1.0))
	if bounce >= 0.0:
		var physics := PhysicsMaterial.new()
		physics.bounce = bounce
		physics.friction = float(spec.get("friction", 0.8))
		root.physics_material_override = physics

	var properties: Dictionary = spec.get("properties", {})
	for key in properties:
		root.set(StringName(key), properties[key])

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	root.add_child(sprite)

	var collider := _add_colliders(root, spec, texture)
	_add_grab(root, spec, texture)
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

	# Wired, which the first version of the original forgot: `sprite` is what a primed
	# explosive flashes and what a detonated one hides, so a null here is a charge with no
	# tell that it is live and a picture that outlives its own blast.
	root.set(&"sprite", sprite)
	root.set(&"drag_area", root.get_node("DraggableArea"))
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	root.set(&"Effects_Player", effects)

	var blast_radius := float(spec.get("blast_radius", 0.0))
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

	return root

## Authored shapes when the table has them, a box around the sprite's own opaque bounds when
## it does not. The fallback is correct for a grenade and a ball and nothing else.
static func _add_colliders(root: Node, spec: Dictionary, texture: Texture2D) -> CollisionShape2D:
	var first: CollisionShape2D = null
	var shapes: Array = spec.get("shapes", [])
	if not shapes.is_empty():
		for entry in shapes:
			var piece := CollisionShape2D.new()
			piece.name = "CollisionShape2D" if first == null \
				else "CollisionShape2D%d" % root.get_child_count()
			piece.shape = shape_from(entry)
			piece.position = (entry.get("at", Vector2.ZERO) as Vector2) * ART_SCALE
			# Degrees, because the table is read by people. Anything whose art is not
			# axis-aligned — a katana, a scythe, a pickaxe — needs it, and a capsule that
			# cannot be turned has to become a box around the diagonal, which is a bounding
			# box around a sword.
			piece.rotation = deg_to_rad(float(entry.get("rot", 0.0)))
			root.add_child(piece)
			if first == null:
				first = piece
		root.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
		root.center_of_mass = (spec.get("com", Vector2.ZERO) as Vector2) * ART_SCALE
		root.set(&"grip_offset", (spec.get("grip", Vector2.ZERO) as Vector2) * ART_SCALE)
		return first

	var extent := content_size(texture) * ART_SCALE
	var shape := RectangleShape2D.new()
	shape.size = extent
	first = CollisionShape2D.new()
	first.name = "CollisionShape2D"
	first.shape = shape
	root.add_child(first)
	return first

## The grab region is deliberately larger and simpler than the physics collider, which is
## the whole reason DraggableArea is its own node — and whatever the shape, it has to be
## clickable while tumbling.
static func _add_grab(root: Node, spec: Dictionary, texture: Texture2D) -> void:
	var shape := RectangleShape2D.new()
	var at := Vector2.ZERO
	if spec.has("grab"):
		var grab: Dictionary = spec["grab"]
		shape.size = (grab.get("size", Vector2(24, 24)) as Vector2) * ART_SCALE
		at = (grab.get("at", Vector2.ZERO) as Vector2) * ART_SCALE
	else:
		var extent := content_size(texture) * ART_SCALE
		shape.size = Vector2(maxf(extent.x + 16.0, 40.0), maxf(extent.y + 16.0, 40.0))
	shape.size = Vector2(maxf(shape.size.x, 34.0), maxf(shape.size.y, 34.0))

	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	collider.position = at

	var area := Area2D.new()
	area.name = "DraggableArea"
	area.set_script(DraggableAreaScript)
	area.add_child(collider)
	root.add_child(area)

static func shape_from(entry: Dictionary) -> Shape2D:
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
	rect.size = (entry.get("rect", Vector2(16, 16)) as Vector2) * ART_SCALE
	return rect

## Opaque bounds of the sprite, which is what a derived collider should match — the cell
## around it is empty space by design (the scale table sizes content, not cells).
static func content_size(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	if image == null:
		return Vector2(texture.get_width(), texture.get_height())
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Vector2(image.get_width(), image.get_height())
	return Vector2(used.size)

## Packs and writes a built root. Sets `owner` on every descendant, which is the one thing
## PackedScene.pack() will not do for you and without which the saved scene contains only
## its root.
static func save_scene(root: Node, path: String) -> bool:
	if root == null:
		return false
	_claim(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("ItemBodyBuilder: failed to pack %s" % path)
		root.free()
		return false
	var err := ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("ItemBodyBuilder: failed to write %s (error %d)" % [path, err])
		return false
	return true

static func _claim(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_claim(child, owner)
