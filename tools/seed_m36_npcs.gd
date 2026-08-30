extends Node

## Writes the NPC roster: four creatures that cross the desk and go for him on their own,
## their scenes, their tier-1 trees and their Hearts-priced automation capstones.
##
##   Godot --headless --path <project> res://tools/seed_m36_npcs.tscn [-- --force]
##
## An NPC is the first content in the game that *acts*. Everything else is a thing the player
## moves — swung, thrown, or put down and aimed by being put down. The argument for why that
## is dangerous to the economy, and what stops it, is in `Scripts/World/npc_base.gd`'s class
## comment and is worth restating once here: **the item costs Bones, the summon is temporary,
## and the capstone that keeps one around indefinitely costs Hearts** like every other
## capstone in the game (docs/decisions.md D2, D31). Take the lifetime off an NPC and it
## becomes a Bones-priced idle engine, which is the one hole D2 exists to close.
##
## **Why these four.** They differ by *verb*, not by damage: a brawler that hits the desk, a
## thrower that arms itself from whatever the player left lying about, a chaser that grabs
## hold and shakes, and a swarm that arrives four at a time. A roster that varied only
## `attack_impulse` would be one animal printed four times — which is the failure mode the
## turret category was also written to avoid.
##
## Same rules as every other seed tool: scenes are packed from script because hand-editing a
## `.tscn` is banned (D8), only files that do not already exist are written, and everything
## derivable is derived — a retune is an edit to the constants below rather than to sixteen
## resources.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const NpcBaseScript := preload("res://Scripts/World/npc_base.gd")
const NpcGorillaScript := preload("res://Scripts/World/npc_gorilla.gd")
const DraggableAreaScript := preload("res://Scripts/Bodies/draggable_area.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const NPCS_DIR := "res://Scenes/NPCs"
const ICONS_DIR := "res://Assets/sprites/icons"

## Every authored size below is in **art pixels**, the same space as the scale table in
## `docs/art-direction.md`, and is multiplied by this — exactly as the sprite is.
const ART_SCALE := 2.0

## Named in Project Settings: 1 world, 2 buddy, 3 item, 4 handle, 5 pickup, 6 sensor. An NPC
## is on the item layer and collides with the desk, him, and everything else on it — moving
## by forces through a world it can bump into is most of what makes it read as alive.
const LAYER_ITEM := 4
const ITEM_MASK := 1 | 2 | 4

## Tier-1 tree pricing, identical to `tools/seed_m35_trees.gd` so an NPC's tree and a katana's
## sit in the same panel without a visible seam.
const TREE_FLOOR := 50.0
const TREE_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## Capstone pricing, identical to `tools/seed_m35_engine.gd`'s Bones line — every NPC is a
## Bones item, so there is only the one line to reproduce: rate per level 1.0 + cost/500,
## price 800 + cost x 0.4, charged in **Hearts** whatever it automates.
const CAPSTONE_BASE_RATE := 1.0
const CAPSTONE_RATE_SLOPE := 1.0 / 500.0
const CAPSTONE_PRICE_FLOOR := 800.0
const CAPSTONE_PRICE_SLOPE := 0.4
const CAPSTONE_MAX_LEVELS := 30
const CAPSTONE_COST_GROWTH := 1.10

## The ladder hangs off the last rung of the Props category rather than off nothing, so a
## menagerie does not turn up in a first-afternoon shop full of things nobody can afford.
const LADDER_ROOT := &"desk_fan"

## Filed under Props (`CATEGORY_TOY`). They are not weapons, they are not kind, and they are
## not turrets; a category of their own would be better and is a one-line change to
## `ItemData` that this tool does not own — see the note in the handoff.
const CATEGORY := ItemDataScript.CATEGORY_TOY

## The roster, cheapest first. The order **is** the `requires` chain and the sort order.
##
##   body     mass, and the collider in art pixels: `rect` or `circle`, plus the grab region
##   npc      @export values on the NPC script — the whole of what makes these four differ
##   tree     tier-1 node names: damage, payout, rate
##   device   capstone id, name, description
##
## Damage per blow is `attack_impulse x 0.01` before multipliers (`balance.damage_per_impulse`)
## and is clamped on the receiver at half a knockout round, which is why the gorilla's number
## looks so much larger than the rest: it is a *blast* strength at the centre of a shockwave
## that falls off with the square of the distance, not the impulse he is handed.
const NPCS := {
	&"hornet": {
		"node": "_Hornets",
		"name": "Hornets",
		"description": "Four of them, and not one can be reasoned with.",
		"cost": 7500,
		"body": {"mass": 0.5, "circle": 7.0, "grab": Vector2(17, 17)},
		"npc": {
			"lifetime_seconds": 55.0,
			"flying": true,
			"move_speed": 400.0,
			"steer_gain": 8.0,
			"attack_range": 60.0,
			"attack_impulse": 620.0,
			"windup_seconds": 0.12,
			"attack_period": 0.7,
			# Four bodies per summon, spread around him so they read as a swarm rather than
			# as one hornet drawn four times in the same place.
			"swarm_count": 4,
			"spread_radius": 40.0,
		},
		"tree": ["Sharper Sting", "Swarm Levy", "Faster Wingbeat"],
		"device": [&"hornet_nest", "The Nest",
			"It is under the desk. It has been there for some time."],
	},
	&"raccoon": {
		"node": "_Raccoon",
		"name": "Raccoon",
		"description": "Arms itself with whatever you left on the desk. Including the bowling ball.",
		"cost": 14000,
		"body": {"mass": 7.0, "rect": Vector2(34, 26), "grab": Vector2(42, 34)},
		"npc": {
			"lifetime_seconds": 75.0,
			"move_speed": 190.0,
			"steer_gain": 5.0,
			"hop_speed": 240.0,
			# It fights from across the desk, which is the whole point of it: a thrower that
			# has to close the distance is a brawler with a longer animation.
			"attack_range": 260.0,
			# Deliberately the weakest blow in the roster for its price. What the raccoon is
			# worth is the *props* it throws — a hurled bowling ball pays as a bowling ball,
			# at whatever that item's own augments and mastery have made it worth.
			"attack_impulse": 3400.0,
			"windup_seconds": 0.35,
			"attack_period": 1.6,
			"throws_loose_items": true,
			"throw_reach": 320.0,
			"throw_speed": 900.0,
			"throw_lift": 260.0,
		},
		"tree": ["Heavier Throws", "Bin Rights", "Quicker Rummage"],
		"device": [&"raccoon_bin_route", "Bin Route",
			"Your desk is now a scheduled stop on a nightly round."],
	},
	&"goose": {
		"node": "_Goose",
		"name": "Goose",
		"description": "It has decided this is personal. It was always going to be personal.",
		"cost": 22000,
		"body": {"mass": 6.0, "rect": Vector2(30, 46), "grab": Vector2(40, 54)},
		"npc": {
			"lifetime_seconds": 70.0,
			"move_speed": 330.0,
			"steer_gain": 6.0,
			"hop_speed": 260.0,
			"attack_range": 78.0,
			"attack_impulse": 4200.0,
			"windup_seconds": 0.25,
			"attack_period": 2.4,
			# The grapple is the goose. It takes hold and shakes him for most of the gap
			# between blows, which is worth about half as much again as the blow itself.
			"grapple_seconds": 1.8,
		},
		"tree": ["Meaner Streak", "Nuisance Fees", "Shorter Temper"],
		"device": [&"goose_territory", "Nesting Site",
			"It has claimed the desk. There is no appeals process."],
	},
	&"gorilla": {
		"node": "_Gorilla",
		"name": "Gorilla",
		"description": "Four hundred pounds of considered opinion, crossing your desk.",
		"cost": 45000,
		"body": {"mass": 26.0, "rect": Vector2(52, 72), "grab": Vector2(60, 80)},
		"npc": {
			"lifetime_seconds": 90.0,
			# Slow, and slow to *turn*: a low steer gain is what weight actually feels like.
			# It keeps travelling for a moment after he has been carried somewhere else.
			"move_speed": 105.0,
			"steer_gain": 2.6,
			"hop_speed": 300.0,
			"attack_range": 100.0,
			# The strength at the centre of the shockwave, not the impulse he is handed —
			# see `NpcGorilla.slam_radius`, which is tuned against this number.
			"attack_impulse": 26000.0,
			# The longest tell in the game. An attack this size that lands with no warning is
			# a number appearing; half a second of raised arms is a moment, and it is the only
			# chance the player gets to pick him up and carry him out of the way.
			"windup_seconds": 0.55,
			"attack_period": 2.4,
			"slam_radius": 200.0,
			"slam_offset": Vector2(44.0, 22.0),
		},
		"tree": ["Silverback", "Zoo Damages", "Shorter Fuse"],
		"device": [&"gorilla_enclosure", "The Enclosure",
			"It lives here now. Nobody was asked."],
	},
}

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir in [ITEMS_DIR, AUGMENTS_DIR, NPCS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	_seed_scenes()
	_seed_items()
	_seed_trees()
	_seed_capstones()

	print("seed_m36_npcs: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- scenes ----------------------------------------------------------------

## Built by hand here rather than through `ItemBodyBuilder`, for one reason: that builder
## refuses to produce a body with no sprite, and **an NPC's art is loaded at runtime**
## (`NpcBase._build_art`) so that the code can ship before the pictures do. One consequence
## worth knowing: an art pass that adds `art/src/gorilla.aseprite` needs no scene rebuild.
func _seed_scenes() -> void:
	for id in NPCS:
		var path := "%s/%s.tscn" % [NPCS_DIR, id]
		# Checked before the build, not after: the root is freed by whoever writes it, so a
		# tree built for a file we then decline to write would leak the whole scene.
		if not _should_write(path):
			continue
		_save_scene(_build(id, NPCS[id]), path)

func _build(id: StringName, row: Dictionary) -> Node:
	var body: Dictionary = row["body"]
	var root := RigidBody2D.new()
	root.name = String(row["node"])
	root.set_script(_script_for(id))
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	root.mass = float(body["mass"])
	root.set(&"item_id", id)
	var properties: Dictionary = row["npc"]
	for key in properties:
		root.set(StringName(key), properties[key])

	# Nothing bounces off an animal and nothing slides one across the desk — a low-friction
	# gorilla skates when it walks, which reads as ice rather than as weight.
	var material := PhysicsMaterial.new()
	material.bounce = 0.0
	material.friction = 0.95
	root.physics_material_override = material

	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = _shape_from(body)
	root.add_child(collider)

	_add_grab(root, (body.get("grab", Vector2(20, 20)) as Vector2) * ART_SCALE)
	var handle := StaticBody2D.new()
	handle.name = "Handle"
	handle.visible = false
	# Handles collide with nothing: they are only ever the far end of the drag joint.
	handle.collision_layer = 0
	handle.collision_mask = 0
	root.add_child(handle)

	# `sprite` is deliberately left unset — see `_seed_scenes`.
	root.set(&"drag_area", root.get_node("DraggableArea"))
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	return root

## The gorilla is the only one of the four with behaviour of its own, because the slam is a
## different *verb* and not a bigger number. Everything else is `NpcBase` with different
## values in it, which is the rule the whole category is built on (docs/decisions.md D8) —
## kept out of the table above so that adding an NPC stays a row of data.
func _script_for(id: StringName) -> Script:
	return NpcGorillaScript if id == &"gorilla" else NpcBaseScript

func _shape_from(body: Dictionary) -> Shape2D:
	if body.has("circle"):
		var circle := CircleShape2D.new()
		circle.radius = float(body["circle"]) * ART_SCALE
		return circle
	var rect := RectangleShape2D.new()
	rect.size = (body.get("rect", Vector2(16, 16)) as Vector2) * ART_SCALE
	return rect

## The grab region is deliberately larger and simpler than the physics collider, which is the
## whole reason `DraggableArea` is its own node — and a hornet has to stay clickable while it
## is moving at 400 pixels a second.
func _add_grab(root: Node, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(size.x, 34.0), maxf(size.y, 34.0))
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape

	var area := Area2D.new()
	area.name = "DraggableArea"
	area.set_script(DraggableAreaScript)
	area.add_child(collider)
	root.add_child(area)

# --- items -----------------------------------------------------------------

## Gated rung by rung, derived from the table's order rather than typed out four times, so the
## chain cannot come apart when an NPC is inserted or repriced.
func _seed_items() -> void:
	var previous := LADDER_ROOT
	var order := 40
	for id in NPCS:
		_item(id, NPCS[id], previous, order)
		previous = id
		order += 10

func _item(id: StringName, row: Dictionary, requires: StringName, sort_order: int) -> void:
	var path := "%s/%s.tres" % [ITEMS_DIR, id]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = id
	item.display_name = row["name"]
	item.description = row["description"]
	item.category = CATEGORY
	item.cost = row["cost"]
	# Bones, and only Bones. It is a gorilla; buying it with kindness reads wrong, and a
	# Hearts price here would put an income source on the wrong side of D2's bargain.
	item.currency = ItemDataScript.CURRENCY_BONES
	item.scene = _require("%s/%s.tscn" % [NPCS_DIR, id])
	item.sort_order = sort_order
	# It attacks on its own, so its damage is not the player being at the desk. Filed as Toy
	# for the shop, which is exactly why `ItemData.is_autonomous` is a separate field.
	item.is_autonomous = true
	var gate: Array[StringName] = []
	gate.assign([requires])
	item.requires = gate
	var icon := "%s/%s.png" % [ICONS_DIR, id]
	if ResourceLoader.exists(icon):
		item.icon = ResourceLoader.load(icon)
	_save(item, path)

# --- trees -----------------------------------------------------------------

## Three tier-1 nodes each, priced by `seed_m35_trees.gd`'s rule.
##
## The third node is **attack rate**, under `cooldown_mult`, and not the `mass_mult` the rest
## of the physical roster gets: an NPC is never swung, so nothing in `NpcBase` reads its mass
## as damage, and a node whose effect_key nothing reads is a placebo — two of those shipped in
## M3 already. How often it comes at him is what an NPC actually is.
func _seed_trees() -> void:
	for id in NPCS:
		var row: Dictionary = NPCS[id]
		var names: Array = row["tree"]
		var base := TREE_FLOOR + float(row["cost"]) * TREE_SLOPE
		_tier_one("%s_damage" % id, id, names[0], &"damage_mult", 1.15,
			int(round(base)), 1.12, 0)
		_tier_one("%s_payout" % id, id, names[1], &"payout_mult", 1.12,
			int(round(base * PAYOUT_FRACTION)), 1.10, 1)
		_tier_one("%s_third" % id, id, names[2], &"cooldown_mult", 0.94,
			int(round(base * THIRD_FRACTION)), 1.09, 2)

func _tier_one(node_id: String, item_id: StringName, display_name: String,
		effect_key: StringName, effect_per_level: float, cost_base: int,
		cost_growth: float, sort_order: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, node_id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = StringName(node_id)
	node.item_id = item_id
	node.display_name = display_name
	node.effect_key = effect_key
	node.effect_per_level = effect_per_level
	node.max_levels = 10
	node.cost_base = cost_base
	node.cost_growth = cost_growth
	node.currency = AugmentNodeScript.CURRENCY_BONES
	node.sort_order = sort_order
	_save(node, path)

# --- capstones -------------------------------------------------------------

## One levelled device per NPC, **priced in Hearts** — and here it buys something the other
## categories' capstones do not: `NpcBase._is_permanent()` reads this node, so owning it is
## literally what stops the creature leaving when its lifetime runs out. That is the deal the
## whole category is built on written as one number: temporary for Bones, permanent for
## kindness.
##
## The device stands on a **pedestal** rather than a tripod. `DeviceLayer` composites the
## mount with the item's own sprite, and a gorilla bolted to a camera tripod is a joke that
## does not survive being looked at; a plinth reads as an enclosure.
func _seed_capstones() -> void:
	for id in NPCS:
		var row: Dictionary = NPCS[id]
		var device: Array = row["device"]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
		if not _should_write(path):
			continue
		var cost := float(row["cost"])
		var node := AugmentNodeScript.new()
		node.id = device[0]
		node.item_id = id
		node.display_name = device[1]
		node.description = device[2]
		node.tier = 3
		# A capstone's effect is its rate, so effect_key is inert here and effect_per_level
		# stays 1.0 — see AugmentNode.automation_rate.
		node.effect_key = &"payout_mult"
		node.effect_per_level = 1.0
		node.max_levels = CAPSTONE_MAX_LEVELS
		node.cost_base = int(round(CAPSTONE_PRICE_FLOOR + cost * CAPSTONE_PRICE_SLOPE))
		node.cost_growth = CAPSTONE_COST_GROWTH
		node.currency = AugmentNodeScript.CURRENCY_HEARTS
		node.is_automation = true
		# round(x * 100) / 100 rather than snappedf: snapping returns the double one ulp above
		# the value, which serialises as 2.8000000000000003 into a file people read.
		var rate := CAPSTONE_BASE_RATE + cost * CAPSTONE_RATE_SLOPE
		node.automation_rate = round(rate * 100.0) / 100.0
		node.requires_mastery = ItemDB.balance.mastery_automation_rank
		node.device_mount = &"pedestal"
		_save(node, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m36_npcs: cannot load %s — check the exact on-disk case" % path)
	return res

func _save_scene(root: Node, path: String) -> void:
	if root == null:
		return
	_claim(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("seed_m36_npcs: failed to pack %s" % path)
		root.free()
		return
	_save(packed, path)
	root.free()

## `owner` on every descendant, which is the one thing PackedScene.pack() will not do for you
## — without it the saved scene contains only its root.
func _claim(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_claim(child, owner)

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m36_npcs: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
