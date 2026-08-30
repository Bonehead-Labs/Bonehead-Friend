extends Node

## Writes M3's kindness content: the open hand, the sponge, the pizza and the boombox,
## as scenes plus their ItemData.
##
##   Godot --headless --path <project> res://tools/seed_friendly.tscn [-- --force]
##
## Scenes are *packed from script* rather than hand-written, because hand-editing .tscn is
## banned (CLAUDE.md) and there is no editor available to a headless agent. The nodes below
## are the same ones the editor would author; `owner` is set on every descendant, which is
## the one thing PackedScene.pack() will not do for you and without which the saved scene
## contains only its root.
##
## **These carry no art.** Every visual here is a flat Polygon2D in a placeholder colour.
## `docs/art-direction.md` calls for sprites authored at true pixel size, and the M3 art
## pass replaces each Polygon2D with an AnimatedSprite2D — nothing else in these scenes
## changes when it does.
##
## Like seed_data.gd this writes only files that do not already exist, so retuning a value
## in the inspector is never silently reverted by re-running it.
##
## M3's new tuning knobs need no seeding: Godot omits default-valued properties from a
## .tres and fills them from the script on load, so balance.tres picks up mood_per_damage,
## grime_max_penalty and the rest automatically, and they are inspector-visible with their
## defaults. Only a value someone has actually changed is ever written to that file.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const FriendlyBaseScript := preload("res://Scripts/Bodies/friendly_base.gd")
const DraggableAreaScript := preload("res://Scripts/Bodies/draggable_area.gd")
const OpenHandScript := preload("res://Scripts/Bodies/Powers/open_hand_power.gd")

const ITEMS_DIR := "res://Data/Items"
const SCENES_DIR := "res://Scenes/Friendly"
const POWERS_DIR := "res://Scenes/Powers"

## Named layers, as bit masks. Never bare numbers in gameplay code — but a scene builder is
## exactly where the numbers have to be written down once (docs/architecture.md).
const LAYER_WORLD := 1
const LAYER_BUDDY := 2
const LAYER_ITEM := 4
const ITEM_MASK := LAYER_WORLD | LAYER_BUDDY | LAYER_ITEM

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	DirAccess.make_dir_recursive_absolute(ITEMS_DIR)
	DirAccess.make_dir_recursive_absolute(SCENES_DIR)

	_seed_scenes()
	_seed_items()

	print("seed_friendly: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	_save_scene(_build_open_hand(), "%s/open_hand_power.tscn" % POWERS_DIR)
	_save_scene(_build_friendly(
		"Sponge", &"sponge", Color(0.95, 0.85, 0.35), Vector2(30, 22), 0.6,
		{"cleans_grime": true}), "%s/sponge.tscn" % SCENES_DIR)
	_save_scene(_build_friendly(
		"Pizza", &"pizza", Color(0.90, 0.55, 0.20), Vector2(34, 24), 0.5,
		{"hearts_per_contact": 25.0, "contact_cooldown": 0.5, "consume_on_use": true}),
		"%s/pizza.tscn" % SCENES_DIR)
	_save_scene(_build_friendly(
		"Boombox", &"boombox", Color(0.35, 0.36, 0.44), Vector2(46, 30), 4.0,
		{"hearts_per_second_placed": 0.6}), "%s/boombox.tscn" % SCENES_DIR)

func _build_open_hand() -> Node:
	var root := Node2D.new()
	root.name = "OpenHandPower"
	root.set_script(OpenHandScript)
	root.set(&"item_id", &"open_hand")
	# The cursor becomes the hand. Every other power says what it is by replacing the
	# pointer, and the one that reaches out to touch him was the one still showing an
	# arrow — the kindness half of the game with no affordance at all. Its own icon,
	# hotspot at the middle of the palm.
	var hand := "res://Assets/sprites/icons/open_hand.png"
	if ResourceLoader.exists(hand):
		root.set(&"cursor_texture", ResourceLoader.load(hand))
		root.set(&"cursor_hotspot", Vector2(16, 16))
	return root

## One FriendlyBase body with a placeholder shape, a grab region and a drag handle — the
## same five-node skeleton every existing item scene has.
func _build_friendly(node_name: String, item_id: StringName, colour: Color, extent: Vector2,
		body_mass: float, properties: Dictionary) -> Node:
	var root := RigidBody2D.new()
	root.name = node_name
	root.set_script(FriendlyBaseScript)
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	root.mass = body_mass
	root.contact_monitor = true
	root.max_contacts_reported = 4
	for key in properties:
		root.set(StringName(key), properties[key])

	root.add_child(_visual_for(item_id, colour, extent))

	var shape := RectangleShape2D.new()
	shape.size = extent
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	root.add_child(collider)

	# The grab region is deliberately larger and simpler than the physics collider, which
	# is the whole reason DraggableArea is its own node.
	var grab_shape := RectangleShape2D.new()
	grab_shape.size = extent + Vector2(12, 12)
	var grab_collider := CollisionShape2D.new()
	grab_collider.name = "CollisionShape2D"
	grab_collider.shape = grab_shape

	var drag_area := Area2D.new()
	drag_area.name = "DraggableArea"
	drag_area.set_script(DraggableAreaScript)
	drag_area.add_child(grab_collider)
	root.add_child(drag_area)

	# Handles collide with nothing — they exist only to be the far end of the pin joint.
	var handle := StaticBody2D.new()
	handle.name = "Handle"
	handle.visible = false
	handle.collision_layer = 0
	handle.collision_mask = 0
	root.add_child(handle)

	root.set(&"drag_area", drag_area)
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	return root

## A box with its corners cut off. Not art — just enough silhouette that four placeholder
## props are distinguishable from each other at a glance during the playtest.

## The item's generated sprite, if it has one. Items without art keep their flat Polygon2D
## placeholder, so a half-finished art pass still leaves every item visible and playable.
func _art_for(item_id: StringName) -> Texture2D:
	var path := "res://Assets/sprites/items/%s.png" % item_id
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D

## Sprite when art exists, coloured block when it does not. Sprites are authored at their
## true pixel size (docs/art-direction.md scale table) and rendered at 2x like everything
## else, so the node carries the scale rather than the asset.
func _visual_for(item_id: StringName, colour: Color, extent: Vector2) -> Node2D:
	var texture := _art_for(item_id)
	if texture:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.scale = Vector2(2, 2)
		return sprite
	var visual := Polygon2D.new()
	visual.name = "Placeholder"
	visual.color = colour
	visual.polygon = _rounded_box(extent)
	return visual

func _rounded_box(extent: Vector2) -> PackedVector2Array:
	var h := extent * 0.5
	var c := minf(extent.x, extent.y) * 0.25
	return PackedVector2Array([
		Vector2(-h.x + c, -h.y), Vector2(h.x - c, -h.y),
		Vector2(h.x, -h.y + c), Vector2(h.x, h.y - c),
		Vector2(h.x - c, h.y), Vector2(-h.x + c, h.y),
		Vector2(-h.x, h.y - c), Vector2(-h.x, -h.y + c),
	])

func _save_scene(root: Node, path: String) -> void:
	if not _should_write(path):
		root.free()
		return
	# Every descendant needs `owner` set to the root or pack() writes the root alone. This
	# is the single most common way a script-built scene silently comes out empty.
	_claim(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("seed_friendly: failed to pack %s" % path)
		root.free()
		return
	var err := ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("seed_friendly: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)

func _claim(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_claim(child, owner_node)

# --- items -----------------------------------------------------------------

## Catalog prices from docs/game-design.md. The open hand is free because it is the only
## Hearts source a new player has — everything else on this list is bought with Hearts, so
## without a free one the second currency could never start.
func _seed_items() -> void:
	_item(&"open_hand", "Open Hand", "Hold the button on Bonehead and stroke. He likes it.",
		0, "%s/open_hand_power.tscn" % POWERS_DIR, 0, true)
	_item(&"sponge", "Sponge", "Scrubs the soot off. Grime quietly suppresses your Bones income.",
		40, "%s/sponge.tscn" % SCENES_DIR, 10, false)
	_item(&"pizza", "Pizza", "A whole one, for him. Instant Hearts and a very good mood.",
		400, "%s/pizza.tscn" % SCENES_DIR, 20, false)
	_item(&"boombox", "Boombox", "Leave it playing. He dances, and Hearts trickle in on their own.",
		1200, "%s/boombox.tscn" % SCENES_DIR, 30, false)

func _item(id: StringName, display_name: String, description: String, cost: int,
		scene_path: String, sort_order: int, as_power: bool) -> void:
	var path := "%s/%s.tres" % [ITEMS_DIR, id]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = id
	item.display_name = display_name
	item.description = description
	item.category = ItemDataScript.CATEGORY_FRIENDLY
	item.cost = cost
	item.currency = ItemDataScript.CURRENCY_HEARTS
	item.scene = _require(scene_path)
	item.sort_order = sort_order
	item.equips_as_cursor_power = as_power
	_save(item, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

## res:// paths are case-sensitive in exported builds and resolve fine in the editor on
## Windows, which is how a wrong-case path shipped a crash once already (CLAUDE.md).
func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_friendly: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_friendly: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
