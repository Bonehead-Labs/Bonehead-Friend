extends Node

## Writes the second five fidget toys (docs/decisions.md D66): their scenes, their ItemData,
## their augment trees and their Hearts-priced automation capstones.
##
##   Godot --headless --path <project> res://tools/seed_m39_toys2.tscn [-- --force] [-- --only=slinky,yo_yo]
##
## Same rules as every seed tool, and as `seed_m39_fidgets.gd`, whose table this follows: scenes
## are packed from script because hand-editing a `.tscn` is banned, only files that do not
## already exist are written (`--force` rewrites; `--only` limits it to some ids, which is how
## one toy is re-seeded without touching the other four), and every number that can be derived
## is derived — tree prices from `seed_m35_trees.gd`'s rule, capstones from `seed_m35_engine.gd`'s.
##
## Two of the five are on the harm side and three on the kind, so a row says which: `side`
## decides the drawer's currency, the tree's currency and the capstone's rate rule, exactly as
## `seed_m39_guns.gd` splits its kind and harm guns.
##
## **Everything spatial here is in grid pixels** — column and row of the text grid in
## `art/pixel/<id>.txt`, from its top-left corner, so every point can be read straight off the
## drawing — and `_art()` converts to art pixels from the sprite's centre the way
## `art/tools/pixel_sprite.py` centres a grid in its cell. Colliders are the picture (D55): a box
## around the body sprite's own opaque pixels, except the yo-yo, which is round and is a circle
## (D61's audit measures it).

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const GestureZonesScript := preload("res://Scripts/Bodies/gesture_zones.gd")
const SlinkyScript := preload("res://Scripts/Bodies/Fidgets/slinky.gd")
const NewtonsCradleScript := preload("res://Scripts/Bodies/Fidgets/newtons_cradle.gd")
const PullBackCarScript := preload("res://Scripts/Bodies/Fidgets/pull_back_car.gd")
const YoYoScript := preload("res://Scripts/Bodies/Fidgets/yo_yo.gd")
const SlingshotScript := preload("res://Scripts/Bodies/Fidgets/slingshot.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const SCENES_DIR := "res://Scenes/Fidgets"
const SPRITES_DIR := "res://Assets/sprites/items"
const ICONS_DIR := "res://Assets/sprites/icons"
const CELL := 64
const ART_SCALE := 2.0

## Tier-1 tree pricing, identical to `tools/seed_m35_trees.gd`.
const TREE_FLOOR := 50.0
const TREE_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## Capstones by `tools/seed_m35_engine.gd`'s two rules, charged in Hearts whatever they make.
const CAPSTONE_RATE := {&"harm": [1.0, 1.0 / 500.0], &"kind": [0.5, 1.0 / 1500.0]}
const CAPSTONE_PRICE := {&"harm": 0.4, &"kind": 0.5}
const CAPSTONE_FLOOR := 800.0
const CAPSTONE_LEVELS := 30
const CAPSTONE_GROWTH := 1.10

## How many rings a stretched slinky is drawn with: two of each of its six colours.
const SLINKY_RINGS := 12
## The cradle's five balls, 7 grid px apart, the middle one drawn at column 23.
const CRADLE_SLOTS := 5
const CRADLE_PITCH := 7.0

## One row per toy. Prices sit in each drawer's own neighbourhood and in each side's curve.
##
##   grid     the drawing's size, for `_art()`
##   body     mass, bounce, friction, and `sprite` when the body's picture is a part rather
##            than the shop's `main`; `circle` for a round collider, in grid px
##   zones    GestureZones rows, `at` in grid px (converted); `action` for right-while-held
const TOYS := {
	&"slinky": {
		"node": "_Slinky", "script": SlinkyScript, "side": &"kind",
		"name": "Slinky",
		"description": "It walks down stairs. You do not have stairs. It walks anyway.",
		"controls": "Hold it, then hold right-click and pull · Right-drag it where it lies · Throw it and it walks",
		# Play, between the bubble wrap (120) and the stress ball (450): the second-cheapest toy
		# on the shelf, because a boing is a small thing done often.
		"category": ItemData.CATEGORY_TOY, "cost": 350, "sort": 71,
		"grid": Vector2(18, 16),
		"body": {"mass": 0.35, "bounce": 0.3, "friction": 0.8},
		"properties": {"boing_value": 6.0, "full_stretch": 170.0, "max_stretch": 260.0,
			"walk_value": 0.5, "walk_span": 34.0},
		# The whole stack is the grip for a right-drag on the desk; hovering it is the toy, not a
		# button, so it shows the grab.
		"zones": [{"id": &"coil", "rect": Vector2(16, 16), "at": Vector2(9, 8), "right": "claim",
			"backing": true}],
		"action": true,
		"tree": ["Rainbow Plastic", "Boing Rates", "Looser Coil"],
		"device": [&"slinky_stairs", "Endless Stairs",
			"A staircase that goes round in a loop. It walks down it all day."],
	},
	&"newtons_cradle": {
		"node": "_NewtonsCradle", "script": NewtonsCradleScript, "side": &"kind",
		"name": "Newton's Cradle",
		"description": "Five steel balls and a law of physics. He finds it very soothing.",
		"controls": "Right-drag an end ball out and let go",
		# Mood, between the wind chimes (1,600) and the lava lamp (8,000): an executive desk
		# toy, and the thing on the desk that calms him down.
		"category": ItemData.CATEGORY_AMBIENCE, "cost": 5000, "sort": 35,
		"grid": Vector2(47, 28),
		"body": {"mass": 1.6, "bounce": 0.05, "friction": 0.9, "sprite": "frame"},
		"properties": {"clack_value": 0.6, "swing_seconds": 0.52, "restitution": 0.9,
			"lock_rotation": true},
		# The end balls, at rest: columns 9 and 37, row 19.5 the middle of a ball.
		"zones": [
			{"id": &"ball_l", "circle": 4.5, "at": Vector2(9.5, 19.5), "right": "claim"},
			{"id": &"ball_r", "circle": 4.5, "at": Vector2(37.5, 19.5), "right": "claim"},
		],
		"action": false,
		# Where the middle string meets the bar: the top edge of row 5, at column 23's middle.
		"pivot": Vector2(23.5, 5.0),
		"tree": ["Polished Steel", "Executive Rates", "Harder Steel"],
		"device": [&"newtons_cradle_magnet", "Hidden Magnet",
			"A magnet under the plinth that keeps the end balls going. Nobody tell him."],
	},
	&"pull_back_car": {
		"node": "_PullBackCar", "script": PullBackCarScript, "side": &"kind",
		"name": "Pull-Back Car",
		"description": "Pull it back and let it go. If it reaches him, he gets a ride.",
		"controls": "Right-drag it backwards to wind it, then let go · Send it at him for a ride",
		# Play, between the fortune ball (2,400) and the jack-in-the-box (6,000).
		"category": ItemData.CATEGORY_TOY, "cost": 3000, "sort": 77,
		"grid": Vector2(32, 16),
		"body": {"mass": 0.8, "bounce": 0.1, "friction": 0.35},
		# Upright always — a car on its roof is not a car — and frozen kinematic, so the ride can
		# move it at its own pace with him on it.
		"properties": {"ride_value": 24.0, "max_speed": 540.0, "run_seconds": 2.4,
			"full_pull": 150.0, "ride_seconds": 1.6, "ride_speed": 230.0,
			"lock_rotation": true, "freeze_mode": RigidBody2D.FREEZE_MODE_KINEMATIC},
		"zones": [{"id": &"car", "rect": Vector2(30, 15), "at": Vector2(16, 8), "right": "claim",
			"backing": true}],
		"action": false,
		# The rear wheel's middle, the grid corner (8, 12); the front one is 16 further on.
		"wheel": Vector2(8, 12),
		"wheelbase": 16.0,
		"tree": ["Racing Stripes", "Ride Fares", "Tighter Spring"],
		"device": [&"pull_back_car_track", "Loop Track",
			"A figure-of-eight track. The car goes round, and he goes round on it."],
	},
	&"yo_yo": {
		"node": "_YoYo", "script": YoYoScript, "side": &"harm",
		"name": "Yo-Yo",
		"description": "Down, up, down, and then into his skull. Sleep it for a trick shot.",
		"controls": "Hold · Right-click to throw it · Keep right held and it sleeps",
		# Melee, with the office and kitchen blunt things (the stapler is 1,750), gated behind
		# the frying pan the way they are.
		"category": ItemData.CATEGORY_WEAPON, "cost": 1500, "sort": 43,
		"requires": [&"frying_pan"],
		"grid": Vector2(34, 34),
		"body": {"mass": 0.8, "bounce": 0.4, "friction": 0.6, "sprite": "disc",
			"circle": 7.0},
		"properties": {"damage_mult": 1.3, "string_length": 170.0, "trick_seconds": 1.5,
			"trick_mult": 2.5, "min_bonk_speed": 300.0},
		"parts": [{"name": "Tail", "part": "tail", "as": "tail"}],
		"zones": [],
		"action": true,
		"tree": ["Brass Rims", "Street Tricks", "Ball Bearing"],
		"device": [&"yo_yo_machine", "Trick Machine",
			"A little motor that walks the dog all day, and bonks him on the way back."],
	},
	&"slingshot": {
		"node": "_Slingshot", "script": SlingshotScript, "side": &"harm",
		"name": "Slingshot",
		"description": "Pull back, aim, let go. The one gun in the drawer you aim yourself.",
		"controls": "Hold · Hold right and pull back to aim · Let go of right to fire",
		# Guns, first and cheapest in the drawer and ungated: a stick and a band, before the
		# revolver (1,500). Not cheaper: at 800 it was the first Bones buy after the pistol, and the
		# pacing simulator put the first Reincarnation at 10:06 against a ten-hour ceiling; anywhere
		# from 1,000 to 2,500 lands it at 9:48-9:49 (D66).
		"category": ItemData.CATEGORY_GUN, "cost": 1200, "sort": 5,
		"grid": Vector2(18, 23),
		"body": {"mass": 0.5, "bounce": 0.15, "friction": 0.9, "sprite": "frame"},
		"properties": {"damage_mult": 1.0, "shot_force": 1700.0, "max_draw": 110.0,
			"reload_seconds": 0.6},
		# Held at the crotch of the Y, with the weight in the handle below it, so it hangs
		# fork-up. The band knots are the prongs' inner tips; a shot leaves between them.
		"grip": Vector2(9, 12), "com": Vector2(9, 16),
		"prongs": [Vector2(4.5, 1.5), Vector2(13.5, 1.5)],
		"fork": Vector2(9, 3.5),
		"parts": [{"name": "Bands", "part": "bands", "as": "rest_bands"},
			{"name": "Pouch", "part": "pouch", "as": "pouch", "visible": false, "loose": true}],
		"zones": [],
		"action": true,
		"tree": ["Steel Shot", "Target Practice", "Pellet Pouch"],
		"device": [&"slingshot_catapult", "Catapult Stand",
			"Bolted down, self-loading, pointed at him. It is not sporting."],
	},
}

var _force := false
var _only: PackedStringArray = []
var _written := 0
var _skipped := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_force = args.has("--force")
	for arg in args:
		if String(arg).begins_with("--only="):
			_only = String(arg).trim_prefix("--only=").split(",", false)
	for dir in [ITEMS_DIR, AUGMENTS_DIR, SCENES_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)
	_seed_scenes()
	_seed_items()
	_seed_trees()
	_seed_capstones()
	print("seed_m39_toys2: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

func _ids() -> Array:
	var out: Array = []
	for id in TOYS:
		if _only.is_empty() or _only.has(String(id)):
			out.append(id)
	return out

# --- geometry ----------------------------------------------------------------

## Grid pixels to art pixels from the sprite's centre, as pixel_sprite.py places a drawing.
static func _art(point: Vector2, grid: Vector2) -> Vector2:
	var left := floorf((CELL - grid.x) / 2.0)
	var top := floorf((CELL - grid.y) / 2.0)
	return point + Vector2(left, top) - Vector2(CELL, CELL) * 0.5

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	for id in _ids():
		var path := "%s/%s.tscn" % [SCENES_DIR, id]
		if not _should_write(path):
			continue
		var row: Dictionary = TOYS[id]
		var root := ItemBodyBuilder.build(_spec(id, row))
		if root == null:
			continue
		_add_parts(root, id, row)
		_add_zones(root, row)
		if ItemBodyBuilder.save_scene(root, path):
			_written += 1
			print("  wrote %s" % path)

func _spec(id: StringName, row: Dictionary) -> Dictionary:
	var body: Dictionary = row["body"]
	var grid: Vector2 = row["grid"]
	var properties: Dictionary = (row.get("properties", {}) as Dictionary).duplicate()
	var spec := {
		"name": row["node"],
		"id": id,
		"script": row["script"],
		"mass": body["mass"],
		"bounce": body.get("bounce", 0.1),
		"friction": body.get("friction", 0.8),
		"properties": properties,
	}
	if body.has("sprite"):
		spec["sprite"] = "%s/%s_%s.png" % [SPRITES_DIR, id, body["sprite"]]
	if body.has("circle"):
		# Round, and centred: the disc is drawn dead centre of its grid.
		spec["shapes"] = [{"circle": body["circle"], "at": Vector2.ZERO}]
		spec["com"] = Vector2.ZERO
		spec["grip"] = Vector2.ZERO
	if row.has("grip"):
		properties["grip_offset"] = _art(row["grip"], grid) * ART_SCALE
		properties["center_of_mass_mode"] = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
		properties["center_of_mass"] = _art(row["com"], grid) * ART_SCALE
	if row.has("prongs"):
		var prongs: Array = row["prongs"]
		properties["prong_left"] = _art(prongs[0], grid) * ART_SCALE
		properties["prong_right"] = _art(prongs[1], grid) * ART_SCALE
		properties["fork"] = _art(row["fork"], grid) * ART_SCALE
		properties["pellet_texture"] = _require("%s/%s_pellet.png" % [SPRITES_DIR, id])
	return spec

func _add_parts(root: Node, id: StringName, row: Dictionary) -> void:
	var grid: Vector2 = row["grid"]
	for part in row.get("parts", []):
		var node := Sprite2D.new()
		node.name = part["name"]
		node.texture = _require("%s/%s_%s.png" % [SPRITES_DIR, id, part["part"]])
		node.scale = Vector2(ART_SCALE, ART_SCALE)
		node.visible = bool(part.get("visible", true))
		root.add_child(node)
		root.set(StringName(part["as"]), node)
	match id:
		&"slinky":
			_add_coil(root, id)
		&"newtons_cradle":
			_add_balls(root, id, grid, row["pivot"])
		&"pull_back_car":
			_add_wheels(root, id, grid, row["wheel"], float(row["wheelbase"]))

## The stretched coil's rings, under one node the toy lifts into the world's space. Hidden: the
## stack is its own drawing until it is pulled.
func _add_coil(root: Node, id: StringName) -> void:
	var coil := Node2D.new()
	coil.name = "Coil"
	coil.visible = false
	root.add_child(coil)
	for i in SLINKY_RINGS:
		var ring := Sprite2D.new()
		ring.name = "Ring%d" % i
		ring.texture = _require("%s/%s_ring%d.png" % [SPRITES_DIR, id, i % 6])
		ring.scale = Vector2(ART_SCALE, ART_SCALE)
		coil.add_child(ring)
	root.set(&"coil", coil)

## Five balls from one drawing: each is the middle slot's picture moved along the bar, turning
## about the top of its own string. In front of the frame, so a pulled ball crosses an upright.
func _add_balls(root: Node, id: StringName, grid: Vector2, pivot_grid: Vector2) -> void:
	var layer := Node2D.new()
	layer.name = "Balls"
	layer.z_index = 1
	root.add_child(layer)
	var texture := _require("%s/%s_ball.png" % [SPRITES_DIR, id])
	var pivot := _art(pivot_grid, grid)
	for slot in CRADLE_SLOTS:
		var ball := Sprite2D.new()
		ball.name = "Ball%d" % slot
		ball.texture = texture
		ball.scale = Vector2(ART_SCALE, ART_SCALE)
		var shift := Vector2(CRADLE_PITCH * float(slot - CRADLE_SLOTS / 2), 0.0)
		ball.position = (pivot + shift) * ART_SCALE
		ball.offset = -pivot
		layer.add_child(ball)
	root.set(&"balls", layer)

## The two wheels over the drawn ones, each turning about its own middle.
func _add_wheels(root: Node, id: StringName, grid: Vector2, wheel_grid: Vector2,
		wheelbase: float) -> void:
	var texture := _require("%s/%s_wheel.png" % [SPRITES_DIR, id])
	var hub := _art(wheel_grid, grid)
	for i in 2:
		var wheel := Sprite2D.new()
		wheel.name = "RearWheel" if i == 0 else "FrontWheel"
		wheel.texture = texture
		wheel.scale = Vector2(ART_SCALE, ART_SCALE)
		wheel.position = (hub + Vector2(wheelbase * float(i), 0.0)) * ART_SCALE
		wheel.offset = -hub
		root.add_child(wheel)
		root.set(&"rear_wheel" if i == 0 else &"front_wheel", wheel)

func _add_zones(root: Node, row: Dictionary) -> void:
	var grid: Vector2 = row["grid"]
	var table: Array = []
	for zone in row.get("zones", []):
		var converted: Dictionary = (zone as Dictionary).duplicate()
		converted["at"] = _art(zone["at"], grid)
		table.append(converted)
	var zones := GestureZonesScript.new() as Node
	zones.name = "GestureZones"
	zones.set(&"zones", table)
	zones.set(&"action_enabled", bool(row.get("action", false)))
	root.add_child(zones)
	root.set(&"gestures", zones)

# --- items -----------------------------------------------------------------

func _seed_items() -> void:
	for id in _ids():
		var row: Dictionary = TOYS[id]
		var path := "%s/%s.tres" % [ITEMS_DIR, id]
		if not _should_write(path):
			continue
		var kind: bool = row["side"] == &"kind"
		var item := ItemDataScript.new()
		item.id = id
		item.display_name = row["name"]
		item.description = row["description"]
		item.controls = row["controls"]
		item.category = row["category"]
		item.cost = row["cost"]
		item.currency = ItemDataScript.CURRENCY_HEARTS if kind else ItemDataScript.CURRENCY_BONES
		item.scene = _require("%s/%s.tscn" % [SCENES_DIR, id])
		item.sort_order = row["sort"]
		if row.has("requires"):
			var gate: Array[StringName] = []
			gate.assign(row["requires"])
			item.requires = gate
		var icon := "%s/%s.png" % [ICONS_DIR, id]
		if ResourceLoader.exists(icon):
			item.icon = ResourceLoader.load(icon)
		_save(item, path)

# --- trees -----------------------------------------------------------------

## Three tier-1 nodes each, every one read by the toy's own script — a node whose effect_key
## nothing reads is a placebo, and this project has shipped two of those:
##
##   damage_mult    the kind toys' kindness value (FidgetToy.pay_act / pay_sustained); the
##                  yo-yo's bonk and the slingshot's pellet (Progression.damage_mult_for)
##   payout_mult    what is earned, applied by Economy to every source
##   cooldown_mult  "time between uses", as each toy means it: a full boing is a shorter pull,
##                  a clack loses less, a full wind is a shorter pull, a shorter sleep is a
##                  trick, a new pellet is in the pouch sooner
func _seed_trees() -> void:
	for id in _ids():
		var row: Dictionary = TOYS[id]
		var names: Array = row["tree"]
		var kind: bool = row["side"] == &"kind"
		var currency := AugmentNodeScript.CURRENCY_HEARTS if kind else AugmentNodeScript.CURRENCY_BONES
		var base := TREE_FLOOR + float(row["cost"]) * TREE_SLOPE
		_tier_one("%s_damage" % id, id, names[0], &"damage_mult", 1.15, base, 1.12, 0, currency)
		_tier_one("%s_payout" % id, id, names[1], &"payout_mult", 1.12,
			base * PAYOUT_FRACTION, 1.10, 1, currency)
		_tier_one("%s_pace" % id, id, names[2], &"cooldown_mult", 0.94,
			base * THIRD_FRACTION, 1.09, 2, currency)

func _tier_one(node_id: String, item_id: StringName, display_name: String,
		effect_key: StringName, effect_per_level: float, cost_base: float,
		cost_growth: float, sort_order: int, currency: int) -> void:
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
	node.cost_base = int(round(cost_base))
	node.cost_growth = cost_growth
	node.currency = currency
	node.sort_order = sort_order
	_save(node, path)

# --- capstones -------------------------------------------------------------

## One levelled device per toy, by the engine's rule for its side, priced in Hearts. All five
## stand on the tripod, as `seed_m35_engine._mount_for` decides for everything outside Care.
func _seed_capstones() -> void:
	for id in _ids():
		var row: Dictionary = TOYS[id]
		var device: Array = row["device"]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
		if not _should_write(path):
			continue
		var side: StringName = row["side"]
		var cost := float(row["cost"])
		var rate_rule: Array = CAPSTONE_RATE[side]
		var node := AugmentNodeScript.new()
		node.id = device[0]
		node.item_id = id
		node.display_name = device[1]
		node.description = device[2]
		node.tier = 3
		node.effect_key = &"payout_mult"
		node.effect_per_level = 1.0
		node.max_levels = CAPSTONE_LEVELS
		node.cost_base = int(round(CAPSTONE_FLOOR + cost * float(CAPSTONE_PRICE[side])))
		node.cost_growth = CAPSTONE_GROWTH
		node.currency = AugmentNodeScript.CURRENCY_HEARTS
		node.is_automation = true
		var rate := float(rate_rule[0]) + cost * float(rate_rule[1])
		node.automation_rate = round(rate * 100.0) / 100.0
		node.requires_mastery = ItemDB.balance.mastery_automation_rank
		node.device_mount = &"tripod"
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
		push_error("seed_m39_toys2: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m39_toys2: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
