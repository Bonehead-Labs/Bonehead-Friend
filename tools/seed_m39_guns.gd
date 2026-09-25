extends Node

## Writes the held guns (docs/decisions.md D56): seven guns you pick up with the left button
## and fire with the right, their scenes, their trees and their Hearts-priced capstones.
##
##   Godot --headless --path <project> res://tools/seed_m39_guns.tscn [-- --force]
##
## Five hurt him and are bought with Bones, in their own shop drawer (`CATEGORY_GUN`). Two are
## kind — the water pistol and the bubble blaster — and are bought with Hearts and filed under
## Care beside the sponge, because they are something you do to him with your own hands and
## nothing he walks over and uses (IdleBrain has no routine for them, and needs none).
##
## Same rules as every other seed tool: scenes are packed from script because hand-editing a
## `.tscn` is banned, only files that do not already exist are written, and the numbers that
## can be derived — tree prices, capstone rates — are derived by the rules the rest of the
## roster was priced with.
##
## ## The physics table, and why the grip is the origin
##
## Every coordinate below is in **grid** pixels: column and row of the text grid in
## `art/pixel/<id>.txt`, measured from its top-left corner, so a point can be read straight
## off the drawing. `grid` is the drawing's size; the builder centres it in its 64 cell the
## same way `art/tools/pixel_sprite.py` does, and converts.
##
## After the body is built, everything is moved so that **the grip is the body's origin**.
## `HeldGun` mirrors a gun about the barrel's own axis through the grip when it swings round
## to face left, so that it is never upside down; with the grip at the origin that mirror is a
## sign flip on every child's y, and the grip — where the drag joint pins it to your hand —
## never moves. Mirroring about anything else would move the joint's anchor and yank the body.
##
## - `muzzle` is the bore at the end of the barrel: where a shot leaves, and the line the aim
##   lays on him. `ejector` is where a spent case leaves; none for a revolver or a muzzle-
##   loader.
## - `com` is where the weight is, and it is always forward of the hand and up in the gun:
##   gravity is cancelled by the aim, so it is the inertia about the grip that is felt — a
##   long heavy gun swings round slowly and is hard to stop.
## - `grab` covers the whole gun: you can pick it up by the barrel. The joint still pins at the
##   grip, so it hangs from your hand however you took it.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const HeldGunScript := preload("res://Scripts/Bodies/held_gun.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const GUNS_DIR := "res://Scenes/Guns"
const ICONS_DIR := "res://Assets/sprites/icons"
const SPRITES_DIR := "res://Assets/sprites/items"

const CELL := 64
const ART_SCALE := 2.0

## Tier-1 pricing, identical to `tools/seed_m35_trees.gd`: base = 50 + price x 0.045, the payout
## node at 0.78 of that and the rate node at 0.61. The two gun-only nodes sit between.
const TREE_FLOOR := 50.0
const TREE_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const RATE_FRACTION := 0.61
const WEIGHT_FRACTION := 0.5
const STEADY_FRACTION := 0.55

## Capstones by `tools/seed_m35_engine.gd`'s two rules, charged in Hearts whatever they make.
const CAPSTONE_RATE := {&"bones": [1.0, 1.0 / 500.0], &"hearts": [0.5, 1.0 / 1500.0]}
const CAPSTONE_PRICE := {&"bones": 0.4, &"hearts": 0.5}
const CAPSTONE_FLOOR := 800.0
const CAPSTONE_LEVELS := 30
const CAPSTONE_GROWTH := 1.10

## The harm guns hang off the cursor pistol, as the turrets do: shoot him by hand first.
const LADDER_ROOT := &"pistol"

const GUNS := {
	&"revolver": {
		"node": "_Revolver", "name": "Revolver", "cost": 1500, "sort": 10,
		"description": "Six chambers, one skeleton. It kicks like a mule, and so does he.",
		"controls": "Hold · Right-click to fire",
		"grid": Vector2(28, 16),
		"body": {
			"mass": 1.6,
			"grip": Vector2(6, 11), "com": Vector2(12, 5),
			"muzzle": Vector2(28, 4.5), "ejector": Vector2.ZERO,
			"shapes": [
				{"rect": Vector2(10, 8), "at": Vector2(10, 5)},
				{"rect": Vector2(13, 4), "at": Vector2(21.5, 4.5)},
				{"rect": Vector2(6, 7), "at": Vector2(5, 12)},
			],
			"grab": {"size": Vector2(28, 16), "at": Vector2(14, 8)},
		},
		# One heavy shot at a time. The kick is the feature: most of a second to walk it back.
		"gun": {
			"damage_mult": 0.5, "shot_mult": 1.1, "shot_force": 3200.0, "shove": 1.0,
			"fire_interval": 0.42, "auto_fire": false, "pellets": 1, "spread_degrees": 0.8,
			"shot_range": 800.0, "ejects": false,
			"aim_frequency": 20.0, "aim_damping": 0.8, "aim_max_accel": 260.0,
			"recoil_kick": 720.0, "recoil_climb": 3200.0,
			"fire_sound": &"turret_fire", "fire_pitch": 0.75, "fire_volume_db": -4.0,
		},
		"tree": ["Magnum Loads", "Wanted Posters", "Fan the Hammer", "Heavy Frame", "Steady Hand"],
		"device": [&"revolver_quick_draw", "Quick-Draw Rig",
			"A spring holster that draws, fires and holsters again, all afternoon."],
	},
	&"smg": {
		"node": "_SMG", "name": "SMG", "cost": 5000, "sort": 20,
		"description": "Holds a lot, fires all of it, and climbs off him if you keep the trigger down.",
		"controls": "Hold · Hold right to fire",
		"grid": Vector2(30, 16),
		"body": {
			"mass": 1.8,
			"grip": Vector2(8, 10), "com": Vector2(14, 5),
			"muzzle": Vector2(29, 4), "ejector": Vector2(17, 1),
			"shapes": [
				{"rect": Vector2(17, 7), "at": Vector2(13.5, 3.5)},
				{"rect": Vector2(7, 4), "at": Vector2(25.5, 4)},
				{"rect": Vector2(5, 6), "at": Vector2(2.5, 4)},
				{"rect": Vector2(5, 7), "at": Vector2(7.5, 10.5)},
				{"rect": Vector2(5, 9), "at": Vector2(16.5, 11.5)},
			],
			"grab": {"size": Vector2(30, 16), "at": Vector2(15, 8)},
		},
		# The stream: small shots, many of them, and a climb that builds through a burst so a
		# long one sprays. Tap it and it stays on him; hold it and you are chasing him with it.
		"gun": {
			"damage_mult": 0.4, "shot_mult": 1.0, "shot_force": 1100.0, "shove": 0.5,
			"fire_interval": 0.085, "auto_fire": true, "pellets": 1, "spread_degrees": 3.5,
			"shot_range": 650.0,
			"aim_frequency": 24.0, "aim_damping": 0.8, "aim_max_accel": 300.0,
			"recoil_kick": 140.0, "recoil_climb": 430.0,
			"climb_per_shot": 0.035, "climb_max": 0.4, "climb_recovery": 1.4,
			"fire_sound": &"turret_fire", "fire_pitch": 1.3, "fire_volume_db": -12.0,
		},
		"tree": ["Hollow Points", "Spray Fees", "Lighter Bolt", "Weighted Stock", "Muzzle Brake"],
		"device": [&"smg_spray_rig", "Spray Rig",
			"Bolted to a bench and pointed at him. The trigger is taped down."],
	},
	&"pump_shotgun": {
		"node": "_PumpShotgun", "name": "Pump Shotgun", "cost": 12000, "sort": 30,
		"description": "Six pellets, then the pump, then six more. Get close.",
		"controls": "Hold · Right-click to fire",
		"grid": Vector2(46, 11),
		"body": {
			"mass": 3.2,
			"grip": Vector2(13, 6.5), "com": Vector2(20, 4),
			"muzzle": Vector2(46, 3), "ejector": Vector2(18, 2),
			"shapes": [
				{"rect": Vector2(13, 8), "at": Vector2(6.5, 6)},
				{"rect": Vector2(8, 8), "at": Vector2(17, 4)},
				{"rect": Vector2(25, 6), "at": Vector2(33.5, 4)},
			],
			"grab": {"size": Vector2(46, 10), "at": Vector2(23, 5)},
		},
		# A spread and a pump delay. Point blank it is the biggest hit on this side of the
		# drawer; across the desk most of it misses.
		"gun": {
			"damage_mult": 0.5, "shot_mult": 1.0, "shot_force": 1500.0, "shove": 0.6,
			"fire_interval": 0.95, "auto_fire": false, "pellets": 6, "spread_degrees": 7.0,
			"shot_range": 420.0, "pump_delay": 0.4, "shake_pixels": 2.0,
			"aim_frequency": 16.0, "aim_damping": 0.8, "aim_max_accel": 200.0,
			"recoil_kick": 2970.0, "recoil_climb": 18500.0,
			"fire_sound": &"turret_fire", "fire_pitch": 0.6, "fire_volume_db": -2.0,
		},
		"tree": ["Buckshot", "Clean-Up Rates", "Slick Pump", "Steel Receiver", "Recoil Pad"],
		"device": [&"pump_shotgun_pump_engine", "Pump Engine",
			"A little motor works the pump, so nobody has to."],
	},
	&"hunting_rifle": {
		"node": "_HuntingRifle", "name": "Hunting Rifle", "cost": 28000, "sort": 40,
		"description": "One slow, perfect shot that picks him up and puts him somewhere else.",
		"controls": "Hold · Right-click to fire",
		"grid": Vector2(56, 13),
		"body": {
			"mass": 3.8,
			"grip": Vector2(13, 7.5), "com": Vector2(24, 6),
			"muzzle": Vector2(56, 6), "ejector": Vector2(22, 4),
			"shapes": [
				{"rect": Vector2(16, 8), "at": Vector2(8, 7)},
				{"rect": Vector2(29, 6), "at": Vector2(30.5, 7)},
				{"rect": Vector2(11, 3), "at": Vector2(50.5, 5.5)},
				{"rect": Vector2(17, 4), "at": Vector2(26.5, 1.5)},
			],
			"grab": {"size": Vector2(56, 12), "at": Vector2(28, 6)},
		},
		# The fling. The hardest single hit in the drawer and the slowest gun to swing round —
		# the long barrel is a long lever, which is the inertia the aim has to fight.
		"gun": {
			"damage_mult": 0.6, "shot_mult": 1.3, "shot_force": 6500.0, "shove": 1.0,
			"fire_interval": 1.5, "auto_fire": false, "pellets": 1, "spread_degrees": 0.0,
			"shot_range": 1400.0, "pump_delay": 0.55, "shake_pixels": 3.0,
			"aim_frequency": 13.0, "aim_damping": 0.8, "aim_max_accel": 160.0,
			"recoil_kick": 5900.0, "recoil_climb": 33000.0,
			"fire_sound": &"turret_fire", "fire_pitch": 0.5, "fire_volume_db": 0.0,
		},
		"tree": ["Big Game Rounds", "Trophy Fees", "Smooth Bolt", "Heavy Barrel", "Bipod"],
		"device": [&"hunting_rifle_blind", "Hunting Blind",
			"A camouflaged stand, and a rifle with all the patience you do not have."],
	},
	&"blunderbuss": {
		"node": "_Blunderbuss", "name": "Blunderbuss", "cost": 65000, "sort": 50,
		"description": "A brass bell full of whatever was in the drawer. Hold on tight.",
		"controls": "Hold · Right-click to fire",
		"grid": Vector2(42, 13),
		"body": {
			"mass": 4.2,
			"grip": Vector2(9, 8), "com": Vector2(22, 5.5),
			"muzzle": Vector2(42, 5), "ejector": Vector2.ZERO,
			"shapes": [
				{"rect": Vector2(16, 7), "at": Vector2(8, 8.5)},
				{"rect": Vector2(18, 6), "at": Vector2(25, 6)},
				{"rect": Vector2(8, 9), "at": Vector2(38, 4.5)},
			],
			"grab": {"size": Vector2(42, 12), "at": Vector2(21, 6.5)},
		},
		# The comedy cone: nine pellets over forty degrees, a kick that throws the gun back past
		# your shoulder, smoke, and a jolt. The slowest reload in the game, because it is a
		# muzzle-loader and you would not want two of these a second anyway.
		"gun": {
			"damage_mult": 0.6, "shot_mult": 1.2, "shot_force": 1300.0, "shove": 1.0,
			"fire_interval": 1.8, "auto_fire": false, "pellets": 9, "spread_degrees": 20.0,
			"shot_range": 320.0, "shake_pixels": 5.0, "ejects": false,
			"aim_frequency": 13.5, "aim_damping": 0.8, "aim_max_accel": 170.0,
			"recoil_kick": 7900.0, "recoil_climb": 23000.0,
			"fire_sound": &"explode_small", "fire_pitch": 1.25, "fire_volume_db": -4.0,
		},
		"tree": ["More Nails", "Salvage Rights", "Quick Powder", "Brass Ballast", "Braced Stock"],
		"device": [&"blunderbuss_carriage", "Cannon Carriage",
			"Wheels, a slow match, and a very long piece of string."],
	},
	&"water_pistol": {
		"node": "_WaterPistol", "name": "Water Pistol", "cost": 350, "sort": 40,
		"kind": true,
		"description": "Squirt him clean. Pays for every speck of grime it washes off, and he likes it anyway.",
		"controls": "Hold · Hold right to squirt",
		"grid": Vector2(26, 16),
		"body": {
			"mass": 0.8,
			"grip": Vector2(5, 12), "com": Vector2(11, 5),
			"muzzle": Vector2(26, 7.5), "ejector": Vector2.ZERO,
			"shapes": [
				{"rect": Vector2(10, 4), "at": Vector2(11, 2)},
				{"rect": Vector2(20, 6), "at": Vector2(12, 7)},
				{"rect": Vector2(4, 3), "at": Vector2(23.5, 7.5)},
				{"rect": Vector2(6, 6), "at": Vector2(4.5, 12.5)},
			],
			"grab": {"size": Vector2(26, 16), "at": Vector2(13, 8)},
		},
		"gun": {
			"damage_mult": 0.0, "shot_mult": 0.0, "shot_force": 60.0, "shove": 1.0,
			"shot_kind": &"water", "fire_interval": 0.1, "auto_fire": true,
			"spread_degrees": 2.0, "shot_range": 300.0, "ejects": false,
			"squirt_clean": 0.012, "squirt_value": 0.15,
			"aim_frequency": 26.0, "aim_damping": 0.85, "aim_max_accel": 340.0,
			"recoil_kick": 8.0, "recoil_climb": 20.0,
			"fire_sound": &"splash", "fire_pitch": 1.8, "fire_volume_db": -18.0,
		},
		"tree": ["Warm Water", "Car Wash Tips", "Bigger Pump"],
		"device": [&"water_pistol_sprinkler", "Garden Sprinkler",
			"A sprinkler turned on him. He pretends to mind."],
	},
	&"bubble_blaster": {
		"node": "_BubbleBlaster", "name": "Bubble Blaster", "cost": 2400, "sort": 50,
		"kind": true, "requires": &"water_pistol",
		"description": "Blows slow bubbles that drift over and pop on him. Every one is a little kindness.",
		"controls": "Hold · Hold right to blow bubbles",
		"grid": Vector2(27, 14),
		"body": {
			"mass": 1.0,
			"grip": Vector2(5, 10), "com": Vector2(13, 6),
			"muzzle": Vector2(21.5, 4.5), "ejector": Vector2.ZERO,
			"shapes": [
				{"rect": Vector2(15, 5), "at": Vector2(9.5, 5)},
				{"circle": 4.5, "at": Vector2(21.5, 4.5)},
				{"rect": Vector2(5, 6), "at": Vector2(5, 10.5)},
				{"rect": Vector2(5, 5), "at": Vector2(12.5, 10.5)},
			],
			"grab": {"size": Vector2(27, 14), "at": Vector2(13.5, 7)},
		},
		"gun": {
			"damage_mult": 0.0, "shot_mult": 0.0, "shot_force": 0.0, "shove": 0.0,
			"shot_kind": &"bubble", "fire_interval": 0.4, "auto_fire": true,
			"spread_degrees": 6.0, "shot_range": 400.0, "ejects": false,
			"bubble_value": 1.2, "bubble_speed": 80.0,
			"aim_frequency": 22.0, "aim_damping": 0.85, "aim_max_accel": 300.0,
			"recoil_kick": 10.0, "recoil_climb": 30.0,
			"fire_sound": &"splash", "fire_pitch": 2.4, "fire_volume_db": -16.0,
		},
		"tree": ["Rainbow Mixture", "Pop Rewards", "Wider Wand"],
		"device": [&"bubble_blaster_fan", "Bubble Fan",
			"A fan and a dish of mixture. Bubbles, forever, at nobody's effort."],
	},
}

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir in [ITEMS_DIR, AUGMENTS_DIR, GUNS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)
	_seed_scenes()
	_seed_items()
	_seed_trees()
	_seed_capstones()
	print("seed_m39_guns: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- geometry ----------------------------------------------------------------

## Grid pixels to art pixels from the sprite's centre, as pixel_sprite.py places a drawing.
static func _art(point: Vector2, grid: Vector2) -> Vector2:
	var left := floorf((CELL - grid.x) / 2.0)
	var top := floorf((CELL - grid.y) / 2.0)
	return point + Vector2(left, top) - Vector2(CELL, CELL) * 0.5

# --- scenes ------------------------------------------------------------------

func _seed_scenes() -> void:
	for id in GUNS:
		var path := "%s/%s.tscn" % [GUNS_DIR, id]
		# Before the build: `save_scene` frees what it is handed, and a root built for a file
		# we then decline to write would leak.
		if not _should_write(path):
			continue
		var row: Dictionary = GUNS[id]
		var root := ItemBodyBuilder.build(_spec(id, row))
		if root == null:
			continue
		_origin_at_grip(root, row)
		if ItemBodyBuilder.save_scene(root, path):
			_written += 1
			print("  wrote %s" % path)

func _spec(id: StringName, row: Dictionary) -> Dictionary:
	var body: Dictionary = row["body"]
	var grid: Vector2 = row["grid"]
	var shapes: Array = []
	for shape in body["shapes"]:
		var converted: Dictionary = (shape as Dictionary).duplicate()
		converted["at"] = _art(shape["at"], grid)
		shapes.append(converted)
	var grab: Dictionary = body["grab"]
	var properties: Dictionary = (row["gun"] as Dictionary).duplicate()
	var grip := _art(body["grip"], grid)
	properties["muzzle"] = (_art(body["muzzle"], grid) - grip) * ART_SCALE
	var ejector: Vector2 = body["ejector"]
	if ejector != Vector2.ZERO:
		properties["ejector"] = (_art(ejector, grid) - grip) * ART_SCALE
	if properties.get("shot_kind", &"bullet") == &"bubble":
		var bubble := "%s/%s_bubble.png" % [SPRITES_DIR, id]
		if ResourceLoader.exists(bubble):
			properties["bubble_texture"] = ResourceLoader.load(bubble)
	return {
		"name": row["node"],
		"id": id,
		"script": HeldGunScript,
		"mass": body["mass"],
		# Metal and plastic on a desk: a little bounce, a lot of friction, so a dropped gun
		# lands and stays rather than skating off.
		"bounce": 0.15,
		"friction": 0.9,
		"shapes": shapes,
		"com": _art(body["com"], grid),
		"grip": grip,
		"grab": {"size": grab["size"], "at": _art(grab["at"], grid)},
		"properties": properties,
	}

## Moves everything so the grip is the body's origin (see the header). The grab region's
## shape moves, not the Area2D, because `HeldGun` mirrors the shapes it finds under it.
func _origin_at_grip(root: Node, row: Dictionary) -> void:
	var body: Dictionary = row["body"]
	var shift := _art(body["grip"], row["grid"]) * ART_SCALE
	for child in root.get_children():
		if child is Sprite2D or child is CollisionShape2D:
			(child as Node2D).position -= shift
		elif child is Area2D:
			for part in child.get_children():
				if part is CollisionShape2D:
					(part as Node2D).position -= shift
	var rigid := root as RigidBody2D
	rigid.center_of_mass -= shift
	root.set(&"grip_offset", Vector2.ZERO)

# --- items -------------------------------------------------------------------

func _seed_items() -> void:
	var previous := LADDER_ROOT
	for id in GUNS:
		var row: Dictionary = GUNS[id]
		var kind := bool(row.get("kind", false))
		var requires: StringName = row.get("requires", &"")
		if not kind:
			requires = previous
			previous = StringName(id)
		_item(id, row, kind, requires)

func _item(id: StringName, row: Dictionary, kind: bool, requires: StringName) -> void:
	var path := "%s/%s.tres" % [ITEMS_DIR, id]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = id
	item.display_name = row["name"]
	item.description = row["description"]
	item.controls = row["controls"]
	# A harm gun in its own drawer; a kind one under Care, beside the sponge.
	item.category = ItemDataScript.CATEGORY_FRIENDLY if kind else ItemDataScript.CATEGORY_GUN
	item.cost = row["cost"]
	item.currency = ItemDataScript.CURRENCY_HEARTS if kind else ItemDataScript.CURRENCY_BONES
	item.scene = _require("%s/%s.tscn" % [GUNS_DIR, id])
	item.sort_order = row["sort"]
	if requires != &"":
		var gate: Array[StringName] = []
		gate.assign([requires])
		item.requires = gate
	var icon := "%s/%s.png" % [ICONS_DIR, id]
	if ResourceLoader.exists(icon):
		item.icon = ResourceLoader.load(icon)
	_save(item, path)

# --- trees -------------------------------------------------------------------

## Five tier-1 nodes on a harm gun, three on a kind one.
##
## The two a harm gun adds are the ones a gun is actually about, and **both are read**:
## `mass_mult` by `WeaponBase.apply_augments` (a heavier gun is kicked less far by the same
## recoil, because the recoil is an impulse), and `recoil_mult` by `HeldGun._recoil`, which
## scales the kick, the climb and a burst's drift. An augment nothing reads is a placebo, and
## two have shipped in this project already; the gun suite measures both.
func _seed_trees() -> void:
	for id in GUNS:
		var row: Dictionary = GUNS[id]
		var names: Array = row["tree"]
		var kind := bool(row.get("kind", false))
		var currency := AugmentNodeScript.CURRENCY_HEARTS if kind else AugmentNodeScript.CURRENCY_BONES
		var base := TREE_FLOOR + float(row["cost"]) * TREE_SLOPE
		_tier_one("%s_damage" % id, id, names[0], &"damage_mult", 1.15, base, 1.12, 0, currency)
		_tier_one("%s_payout" % id, id, names[1], &"payout_mult", 1.12,
			base * PAYOUT_FRACTION, 1.10, 1, currency)
		_tier_one("%s_rate" % id, id, names[2], &"cooldown_mult", 0.94,
			base * RATE_FRACTION, 1.09, 2, currency)
		if kind:
			continue
		_tier_one("%s_weight" % id, id, names[3], &"mass_mult", 1.08,
			base * WEIGHT_FRACTION, 1.09, 3, currency)
		_tier_one("%s_steady" % id, id, names[4], &"recoil_mult", 0.92,
			base * STEADY_FRACTION, 1.09, 4, currency)

func _tier_one(node_id: String, item_id: StringName, display_name: String,
		effect_key: StringName, effect_per_level: float, cost_base: float,
		cost_growth: float, sort_order: int, currency: int) -> void:
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
	_save_if_new(node, "%s/%s.tres" % [AUGMENTS_DIR, node_id])

# --- capstones ---------------------------------------------------------------

## One levelled device per gun, priced in Hearts by the engine's rule. A harm gun's device
## stands on the tripod, a kind one's on the pedestal, like the rest of the roster.
func _seed_capstones() -> void:
	for id in GUNS:
		var row: Dictionary = GUNS[id]
		var device: Array = row["device"]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
		if not _should_write(path):
			continue
		var kind := bool(row.get("kind", false))
		var money := &"hearts" if kind else &"bones"
		var cost := float(row["cost"])
		var rate_rule: Array = CAPSTONE_RATE[money]
		var node := AugmentNodeScript.new()
		node.id = device[0]
		node.item_id = id
		node.display_name = device[1]
		node.description = device[2]
		node.tier = 3
		node.effect_key = &"payout_mult"
		node.effect_per_level = 1.0
		node.max_levels = CAPSTONE_LEVELS
		node.cost_base = int(round(CAPSTONE_FLOOR + cost * float(CAPSTONE_PRICE[money])))
		node.cost_growth = CAPSTONE_GROWTH
		node.currency = AugmentNodeScript.CURRENCY_HEARTS
		node.is_automation = true
		var rate := float(rate_rule[0]) + cost * float(rate_rule[1])
		node.automation_rate = round(rate * 100.0) / 100.0
		node.requires_mastery = ItemDB.balance.mastery_automation_rank
		node.device_mount = &"pedestal" if kind else &"tripod"
		_save(node, path)

# --- io ----------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

func _save_if_new(resource: Resource, path: String) -> void:
	if not _should_write(path):
		return
	_save(resource, path)

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m39_guns: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m39_guns: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
