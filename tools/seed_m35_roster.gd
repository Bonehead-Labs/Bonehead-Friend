extends Node

## Writes M3.5-A's roster expansion: the twelve committed-but-missing catalog items, their
## scenes where they need one, and the `requires` chain that keeps a 28-item shop from
## arriving all at once on hour one.
##
##   Godot --headless --path <project> res://tools/seed_m35_roster.tscn [-- --force]
##
## The melee and explosive bodies are **not** here — katana, mine and firework are built by
## `seed_bodies.gd`, which owns the authored `PHYSICS` table (D25). What is here is
## everything that table has no opinion about: the Hearts generators, the two toys and the
## four cursor powers.
##
## Same rules as every other seed tool: scenes are packed from script because hand-editing
## `.tscn` is banned, and only files that do not already exist are written.
##
## **Why these twelve.** `game-design.md` committed a 24-item catalog and M3 shipped 16, so
## hours two to eight of a session had nothing left to buy: total catalog spend was 9,810
## and the most expensive thing in the game was 2,500 Bones. These are the missing rungs,
## at the prices the catalog already named — the ladder now runs to 40,000.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const FriendlyBaseScript := preload("res://Scripts/Bodies/friendly_base.gd")
const DraggableAreaScript := preload("res://Scripts/Bodies/draggable_area.gd")
const WindSourceScript := preload("res://Scripts/Bodies/wind_source.gd")
const TrampolineScript := preload("res://Scripts/Bodies/trampoline.gd")
const BeamPowerScript := preload("res://Scripts/Bodies/Powers/beam_power.gd")
const GunPowerScript := preload("res://Scripts/Bodies/Powers/gun_power.gd")
const VortexPowerScript := preload("res://Scripts/Bodies/Powers/vortex_power.gd")
const LightningPowerScript := preload("res://Scripts/Bodies/Powers/lightning_power.gd")

const ITEMS_DIR := "res://Data/Items"
const FRIENDLY_DIR := "res://Scenes/Friendly"
const PROPS_DIR := "res://Scenes/Props"
const POWERS_DIR := "res://Scenes/Powers"
const BODIES_DIR := "res://Scenes/Bodies"
const SPRITES_DIR := "res://Assets/sprites/items"
const CURSORS_DIR := "res://Assets/sprites/cursors"

const ART_SCALE := 2.0

const LAYER_WORLD := 1
const LAYER_BUDDY := 2
const LAYER_ITEM := 4
const ITEM_MASK := LAYER_WORLD | LAYER_BUDDY | LAYER_ITEM
const LAYER_SENSOR := 32
const WIND_MASK := LAYER_BUDDY | LAYER_ITEM

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir in [ITEMS_DIR, FRIENDLY_DIR, PROPS_DIR, POWERS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	_seed_scenes()
	_seed_items()

	print("seed_m35_roster: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	# The three Hearts generators the friendly economy was missing. All three are
	# FriendlyBase with different switches thrown, which is the whole point of that class:
	# a generator is data, not a script (D8).
	#
	# Each one earns differently on purpose. The fountain pays for *existing* and burns out,
	# so it is a consumable you re-buy; the hot tub pays only while he is in it, so it wants
	# him carried over and dropped in; the chair pays best of all and pays for contact, so
	# the top of the ladder still asks the player to do something.
	_save_scene(_build_friendly("ChocolateFountain", &"chocolate_fountain",
		Vector2(31, 50), 5.0, {
			"hearts_per_second_placed": 2.2,
			"lifetime_seconds": 600.0,
		}), "%s/chocolate_fountain.tscn" % FRIENDLY_DIR)
	_save_scene(_build_friendly("HotTub", &"hot_tub", Vector2(72, 70), 14.0, {
			"hearts_per_second_touching": 9.0,
			"hearts_per_second_placed": 0.8,
		}), "%s/hot_tub.tscn" % FRIENDLY_DIR)
	_save_scene(_build_friendly("MassageChair", &"massage_chair", Vector2(80, 76), 18.0, {
			"hearts_per_second_touching": 20.0,
			"hearts_per_contact": 60.0,
			"contact_cooldown": 4.0,
		}), "%s/massage_chair.tscn" % FRIENDLY_DIR)

	_save_scene(_build_trampoline(), "%s/trampoline.tscn" % PROPS_DIR)
	_save_scene(_build_fan(), "%s/desk_fan.tscn" % PROPS_DIR)

	# The four cursor powers. Three need a class of their own — a beam that dwells, a pull
	# that has no shot at all, and a strike that chains — and the minigun is the pistol's
	# class with its trigger held down.
	_save_scene(_build_power("MagnifyingGlassPower", &"magnifying_glass", BeamPowerScript, {
			"impulse_per_second": 2600.0,
			"tick_seconds": 0.25,
		}), "%s/magnifying_glass_power.tscn" % POWERS_DIR)
	_save_scene(_build_power("MinigunPower", &"minigun", GunPowerScript, {
			"blast_radius": 34.0,
			"blast_force": 1500.0,
			"pellets": 1,
			"cooldown_seconds": 0.08,
			"auto_fire": true,
		}), "%s/minigun_power.tscn" % POWERS_DIR)
	_save_scene(_build_power("GravityVortexPower", &"gravity_vortex", VortexPowerScript, {
			"pull_force": 2400.0,
			"radius": 260.0,
			"cooldown_seconds": 0.0,
		}), "%s/gravity_vortex_power.tscn" % POWERS_DIR)
	_save_scene(_build_power("LightningPower", &"lightning", LightningPowerScript, {
			"blast_radius": 72.0,
			"blast_force": 9000.0,
			"chains": 3,
			"cooldown_seconds": 1.6,
		}), "%s/lightning_power.tscn" % POWERS_DIR)

## A FriendlyBase generator: sprite, body collider, grab region, handle. `extent` is in art
## pixels like everything else and is scaled here, exactly as the sprite is.
func _build_friendly(node_name: String, item_id: StringName, extent: Vector2,
		body_mass: float, properties: Dictionary) -> Node:
	var root := RigidBody2D.new()
	root.name = node_name
	root.set_script(FriendlyBaseScript)
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	root.mass = body_mass
	root.contact_monitor = true
	root.max_contacts_reported = 4
	root.set(&"item_id", item_id)
	for key in properties:
		root.set(StringName(key), properties[key])

	var sprite := _sprite_for(item_id)
	if sprite:
		root.add_child(sprite)

	var shape := RectangleShape2D.new()
	shape.size = extent * ART_SCALE
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	root.add_child(collider)

	_add_grab(root, extent * ART_SCALE + Vector2(12, 12))
	var handle := _add_handle(root)

	root.set(&"sprite", sprite)
	root.set(&"drag_area", root.get_node("DraggableArea"))
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	return root

func _build_trampoline() -> Node:
	var root := RigidBody2D.new()
	root.name = "Trampoline"
	root.set_script(TrampolineScript)
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	# Heavy on purpose: a trampoline that is launched by what it launches is a see-saw.
	root.mass = 22.0
	root.contact_monitor = true
	root.max_contacts_reported = 6

	var physics := PhysicsMaterial.new()
	physics.bounce = 0.2
	physics.friction = 0.9
	root.physics_material_override = physics
	root.set(&"item_id", &"trampoline")

	var sprite := _sprite_for(&"trampoline")
	if sprite:
		root.add_child(sprite)

	# The collider is the *mat*, not the picture: the legs are drawn but nothing should
	# bounce off them, and a box around the whole sprite would launch him off the frame.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70, 12) * ART_SCALE
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	collider.position = Vector2(0, -12) * ART_SCALE
	root.add_child(collider)

	_add_grab(root, Vector2(80, 46) * ART_SCALE)
	var handle := _add_handle(root)
	root.set(&"sprite", sprite)
	root.set(&"drag_area", root.get_node("DraggableArea"))
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	return root

func _build_fan() -> Node:
	var root := RigidBody2D.new()
	root.name = "DeskFan"
	root.set_script(WindSourceScript)
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	root.mass = 7.0
	root.contact_monitor = true
	root.max_contacts_reported = 4
	root.set(&"item_id", &"desk_fan")
	root.set(&"force", 900.0)
	root.set(&"blow_direction", Vector2.RIGHT)

	var sprite := _sprite_for(&"desk_fan")
	if sprite:
		root.add_child(sprite)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(21, 28) * ART_SCALE
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	root.add_child(collider)

	# The throw: a long box in front of the grille, on the sensor layer so it pushes bodies
	# without ever being one. Its width *is* the fan's reach — `WindSource._reach()` reads
	# it back off the shape, so the number and the picture cannot disagree.
	var wind_shape := RectangleShape2D.new()
	wind_shape.size = Vector2(220, 60) * ART_SCALE
	var wind_collider := CollisionShape2D.new()
	wind_collider.name = "CollisionShape2D"
	wind_collider.shape = wind_shape
	wind_collider.position = Vector2(wind_shape.size.x * 0.5, 0)

	var wind := Area2D.new()
	wind.name = "WindArea"
	wind.collision_layer = LAYER_SENSOR
	wind.collision_mask = WIND_MASK
	wind.monitoring = true
	wind.add_child(wind_collider)
	root.add_child(wind)

	_add_grab(root, Vector2(33, 40) * ART_SCALE)
	var handle := _add_handle(root)
	root.set(&"sprite", sprite)
	root.set(&"drag_area", root.get_node("DraggableArea"))
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	root.set(&"wind_area", wind)
	return root

## A cursor power: a bare Node2D with a script, its reticle and its numbers. No body, no
## collider — the power is a mode the cursor is in (docs/architecture.md).
func _build_power(node_name: String, item_id: StringName, script: Script,
		properties: Dictionary) -> Node:
	var root := Node2D.new()
	root.name = node_name
	root.set_script(script)
	root.set(&"item_id", item_id)
	for key in properties:
		root.set(StringName(key), properties[key])

	# Every cursor power must change what the player sees, or the tool with no world sprite
	# is invisible and the arrow keeps lying about what a click will do (loop_check asserts
	# it). The reticles are plotted, not generated — art/tools/make_crosshairs.py.
	var reticle := "%s/%s.png" % [CURSORS_DIR, item_id]
	if ResourceLoader.exists(reticle):
		root.set(&"cursor_texture", ResourceLoader.load(reticle))
		root.set(&"cursor_hotspot", Vector2(32, 32))
	else:
		push_error("seed_m35_roster: no reticle at %s — run make_crosshairs.py first" % reticle)
	return root

func _sprite_for(item_id: StringName) -> Sprite2D:
	var path := "%s/%s.png" % [SPRITES_DIR, item_id]
	if not ResourceLoader.exists(path):
		push_error("seed_m35_roster: no sprite at %s" % path)
		return null
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = ResourceLoader.load(path)
	sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	return sprite

## The grab region is deliberately larger and simpler than the physics collider, which is
## the whole reason DraggableArea is its own node.
func _add_grab(root: Node, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(size.x, 40.0), maxf(size.y, 40.0))
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape

	var area := Area2D.new()
	area.name = "DraggableArea"
	area.set_script(DraggableAreaScript)
	area.add_child(collider)
	root.add_child(area)

## Handles collide with nothing — they exist only to be the far end of the pin joint.
func _add_handle(root: Node) -> StaticBody2D:
	var handle := StaticBody2D.new()
	handle.name = "Handle"
	handle.visible = false
	handle.collision_layer = 0
	handle.collision_mask = 0
	root.add_child(handle)
	return handle

# --- items -----------------------------------------------------------------

## The catalog's own prices, and the catalog's own order.
##
## `requires` is the other half of this milestone's answer to "a 28-item shop on hour one is
## noise": every ladder gates its next rung behind the one below, so the Cursor page opens
## showing a fist, a pistol and a locked shotgun rather than eight things a new player
## cannot afford and cannot tell apart. The field has existed since M2 and was empty on
## all sixteen items.
func _seed_items() -> void:
	var W := ItemDataScript.CATEGORY_WEAPON
	var T := ItemDataScript.CATEGORY_THROWABLE
	var C := ItemDataScript.CATEGORY_CURSOR_POWER
	var F := ItemDataScript.CATEGORY_FRIENDLY
	var Y := ItemDataScript.CATEGORY_TOY
	var HEARTS := ItemDataScript.CURRENCY_HEARTS

	_item(&"katana", "Katana", "Fast, precise and unreasonably sharp. Cuts where the bat clubs.",
		W, 3500, "%s/katana.tscn" % BODIES_DIR, 15, [&"mace"])
	_item(&"mine", "Mine", "Place it, then put him on it. The only explosive he sets off himself.",
		T, 2500, "%s/mine.tscn" % BODIES_DIR, 20, [&"dynamite"])
	_item(&"firework", "Firework Rocket", "Lights, flies where it likes, and goes off there.",
		T, 6000, "%s/firework.tscn" % BODIES_DIR, 30, [&"mine"])

	_item(&"magnifying_glass", "Magnifying Glass",
		"Hold the beam on him and he cooks. Hurts without ever shoving him.",
		C, 4000, "%s/magnifying_glass_power.tscn" % POWERS_DIR, 25, [&"shotgun"])
	_item(&"minigun", "Minigun", "Hold the trigger. Keep holding it.",
		C, 9000, "%s/minigun_power.tscn" % POWERS_DIR, 30, [&"magnifying_glass"])
	_item(&"gravity_vortex", "Gravity Vortex",
		"Drags him and every loose thing on the desk into one spinning knot.",
		C, 15000, "%s/gravity_vortex_power.tscn" % POWERS_DIR, 35, [&"minigun"])
	_item(&"lightning", "Lightning",
		"Strikes where you point and jumps to whatever is standing nearby.",
		C, 40000, "%s/lightning_power.tscn" % POWERS_DIR, 40, [&"gravity_vortex"])

	_item(&"chocolate_fountain", "Chocolate Fountain",
		"Pays Hearts just for running. Runs out, eventually.",
		F, 5000, "%s/chocolate_fountain.tscn" % FRIENDLY_DIR, 40, [&"boombox"], HEARTS)
	_item(&"hot_tub", "Hot Tub", "Put him in it. He will not want to come out.",
		F, 12000, "%s/hot_tub.tscn" % FRIENDLY_DIR, 50, [&"chocolate_fountain"], HEARTS)
	_item(&"massage_chair", "Massage Chair", "The best thing that has ever happened to him.",
		F, 30000, "%s/massage_chair.tscn" % FRIENDLY_DIR, 60, [&"hot_tub"], HEARTS)

	_item(&"trampoline", "Trampoline", "Everything that lands on it leaves faster than it arrived.",
		Y, 1800, "%s/trampoline.tscn" % PROPS_DIR, 20, [&"bowling_ball"])
	_item(&"desk_fan", "Desk Fan", "Changes the arc of everything you throw. Including the miss.",
		Y, 3000, "%s/desk_fan.tscn" % PROPS_DIR, 30, [&"trampoline"])

func _item(id: StringName, display_name: String, description: String, category: int,
		cost: int, scene_path: String, sort_order: int, requires: Array,
		currency: int = ItemDataScript.CURRENCY_BONES) -> void:
	var path := "%s/%s.tres" % [ITEMS_DIR, id]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = id
	item.display_name = display_name
	item.description = description
	item.category = category
	item.cost = cost
	item.currency = currency
	item.scene = _require(scene_path)
	item.sort_order = sort_order
	var gate: Array[StringName] = []
	gate.assign(requires)
	item.requires = gate
	var icon := "res://Assets/sprites/icons/%s.png" % id
	if ResourceLoader.exists(icon):
		item.icon = ResourceLoader.load(icon)
	_save(item, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m35_roster: cannot load %s — check the exact on-disk case" % path)
	return res

func _save_scene(root: Node, path: String) -> void:
	if not _should_write(path):
		root.free()
		return
	_claim(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("seed_m35_roster: failed to pack %s" % path)
		root.free()
		return
	_save(packed, path)
	root.free()

## `owner` on every descendant, which is the one thing PackedScene.pack() will not do for
## you — without it the saved scene contains only its root.
func _claim(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_claim(child, owner)

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m35_roster: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
