extends Node

## Writes the first five fidget toys (docs/decisions.md D57): their scenes, their ItemData,
## their augment trees and their Hearts-priced automation capstones.
##
##   Godot --headless --path <project> res://tools/seed_m39_fidgets.tscn [-- --force]
##
## Same rules as every seed tool: scenes are packed from script because hand-editing a
## `.tscn` is banned, only files that do not already exist are written, and every number that
## can be derived is derived — tree prices from `seed_m35_trees.gd`'s rule, capstones from
## `seed_m35_engine.gd`'s.
##
## **Everything spatial here is in art pixels**, origin at the sprite's centre, y down — the
## space of the scale table, D25's physics table and the grids in `art/pixel/`. Every zone
## below was read off its grid, and each grid's header says which rows and columns it means.
## Colliders are not in the table at all: each body gets one box derived from its own opaque
## pixels (D55), which `loop_check` measures.
##
## A new fidget is a row here, a script under `Scripts/Bodies/Fidgets/`, and a grid.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const GestureZonesScript := preload("res://Scripts/Bodies/gesture_zones.gd")
const BubbleWrapScript := preload("res://Scripts/Bodies/Fidgets/bubble_wrap.gd")
const FidgetSpinnerScript := preload("res://Scripts/Bodies/Fidgets/fidget_spinner.gd")
const JackInTheBoxScript := preload("res://Scripts/Bodies/Fidgets/jack_in_the_box.gd")
const MagicEightBallScript := preload("res://Scripts/Bodies/Fidgets/magic_eight_ball.gd")
const StressBallScript := preload("res://Scripts/Bodies/Fidgets/stress_ball.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const SCENES_DIR := "res://Scenes/Fidgets"
const SPRITES_DIR := "res://Assets/sprites/items"
const ICONS_DIR := "res://Assets/sprites/icons"
const ART_SCALE := 2.0

## Tier-1 tree pricing, identical to `tools/seed_m35_trees.gd`.
const TREE_FLOOR := 50.0
const TREE_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## Capstone pricing, identical to `tools/seed_m35_engine.gd`'s Hearts line.
const CAPSTONE_BASE_RATE := 0.5
const CAPSTONE_RATE_SLOPE := 1.0 / 1500.0
const CAPSTONE_PRICE_FLOOR := 800.0
const CAPSTONE_PRICE_SLOPE := 0.5
const CAPSTONE_MAX_LEVELS := 30
const CAPSTONE_COST_GROWTH := 1.10

## The bubble slots on `art/pixel/bubble_wrap.txt`: four columns and two rows, 9 art px apart,
## the first centred at (-14, -5). Nine wide rather than the bubble's eight, so neighbouring
## zones touch and a stroke never falls into the one-pixel gap between two bubbles.
static func _bubble_zones() -> Array:
	var out: Array = []
	for r in 2:
		for c in 4:
			out.append({"id": StringName("b%d" % (r * 4 + c)), "rect": Vector2(9, 9),
				"at": Vector2(9 * c - 14, 9 * r - 5), "left": "tap", "right": "claim"})
	# The film under them, last so the bubbles win: a right-stroke may start on it, and it is
	# part of the toy rather than a button, so hovering it shows the grab.
	out.append({"id": &"sheet", "rect": Vector2(39, 21), "at": Vector2(-0.5, -0.5),
		"right": "claim", "backing": true})
	return out

## One row per toy. Prices sit in the Play drawer's own neighbourhood — between the rubber
## duck at 60 and the bubble machine at 15,000 — and rise with how much each one pays.
##
##   parts   extra sprites, each on the toy's shared grid: {name, part, z, pivot, visible, as}.
##           `pivot` (art px) is what the part turns about; `as` names the export it fills.
const FIDGETS := {
	&"bubble_wrap": {
		"node": "_BubbleWrap",
		"script": BubbleWrapScript,
		"name": "Bubble Wrap",
		"description": "Eight bubbles. He wants to pop every one of them, and so do you.",
		"controls": "Click a bubble to pop it · Right-drag across the sheet to pop a run",
		"cost": 120,
		"sort": 70,
		"body": {"mass": 0.3, "bounce": 0.05, "friction": 0.9, "sprite": "sheet"},
		# A sheet lies flat. Free to turn, it went up on its edge the first time he hopped at
		# it, and "on top of it" stopped meaning anything.
		"properties": {"pop_value": 2.0, "regrow_seconds": 4.0, "lock_rotation": true},
		"bubbles": true,
		"action": false,
		"tree": ["Thicker Plastic", "Packing Rates", "Faster Regrowth"],
		"device": [&"bubble_wrap_press", "Bubble Press",
			"A roller that puffs the sheet back up and pops it again. Somebody has to."],
	},
	&"stress_ball": {
		"node": "_StressBall",
		"script": StressBallScript,
		"name": "Stress Ball",
		"description": "Squeeze it until you feel better. Or throw it at him; he always catches.",
		"controls": "Hold it, then hold right-click to squeeze · Throw it at him",
		"cost": 450,
		"sort": 72,
		"body": {"mass": 0.25, "bounce": 0.45, "friction": 0.8},
		"properties": {"squeeze_value": 5.0, "full_squeeze_seconds": 1.0, "catch_value": 10.0,
			"min_catch_speed": 240.0},
		"parts": [{"name": "Squeeze", "part": "squeeze", "visible": false, "as": "squeeze_sprite"}],
		"action": true,
		"tree": ["Softer Foam", "Squeeze Rates", "Stretchier Skin"],
		"device": [&"stress_ball_press", "Squeeze Press",
			"Squeezes it for him, slowly, all day. He finds this very calming."],
	},
	&"fidget_spinner": {
		"node": "_FidgetSpinner",
		"script": FidgetSpinnerScript,
		"name": "Fidget Spinner",
		"description": "It does nothing at all, very quickly. He cannot look away from it.",
		"controls": "Right-drag across an arm to spin it",
		"cost": 1200,
		"sort": 74,
		"body": {"mass": 0.4, "bounce": 0.2, "friction": 0.8},
		"properties": {"max_spin": 38.0, "decay_seconds": 9.0, "watch_value": 0.8},
		# The body turns about the hub, grid pixel (13, 13) of a 27x22 drawing: (-0.5, 2.5).
		"rotor_pivot": Vector2(-0.5, 2.5),
		"parts": [{"name": "Cap", "part": "cap"}],
		"zones": [{"id": &"arms", "circle": 14.0, "at": Vector2(-0.5, 2.5), "right": "claim"}],
		"action": false,
		"tree": ["Heavier Weights", "Show-Off Rates", "Ceramic Bearings"],
		"device": [&"fidget_spinner_jet", "Air Jet",
			"A little nozzle that keeps it spinning in front of him while you are away."],
	},
	&"magic_eight_ball": {
		"node": "_MagicEightBall",
		"script": MagicEightBallScript,
		"name": "Fortune Ball",
		"description": "Ask it anything. He believes every single word it says.",
		"controls": "Pick it up and shake it · Right-click to read it",
		"cost": 2400,
		"sort": 76,
		"body": {"mass": 0.6, "bounce": 0.3, "friction": 0.8},
		"properties": {"shakes_needed": 4.0, "answer_value": 14.0},
		"zones": [{"id": &"ball", "circle": 10.5, "at": Vector2.ZERO, "right": "tap"}],
		"action": true,
		"tree": ["Clearer Window", "Fortune Fees", "Looser Dice"],
		"device": [&"magic_eight_ball_oracle", "Oracle Stand",
			"Shakes itself on the hour and reads him the answer. It is always good news."],
	},
	&"jack_in_the_box": {
		"node": "_JackInTheBox",
		"script": JackInTheBoxScript,
		"name": "Jack-in-the-Box",
		"description": "Wind it and wait. He knows exactly what happens, and jumps every time.",
		"controls": "Right-drag circles on the crank · Right-click the lid to put him back",
		"cost": 6000,
		"sort": 78,
		"body": {"mass": 1.2, "bounce": 0.05, "friction": 0.9, "sprite": "box"},
		"properties": {"laugh_value": 30.0},
		# On the 36x24 grid (art = grid - (18, 12)): the lid's hinge is the grid corner (6, 3)
		# and the crank's axle the grid corner (31, 13). The jack is drawn inside the box and
		# sits behind it until he is out.
		"parts": [
			{"name": "Jack", "part": "jack", "z": -1, "as": "jack"},
			{"name": "Lid", "part": "lid", "pivot": Vector2(-12, -9), "as": "lid"},
			{"name": "Crank", "part": "crank", "pivot": Vector2(13, 1), "as": "crank"},
		],
		"zones": [
			{"id": &"crank", "circle": 7.0, "at": Vector2(13, 1), "right": "claim"},
			# The lid and the jack above it, live only while he is out.
			{"id": &"lid", "rect": Vector2(26, 24), "at": Vector2(0, -20), "right": "tap"},
		],
		"action": false,
		"tree": ["Bigger Spring", "Surprise Fees", "Shorter Tune"],
		"device": [&"jack_in_the_box_key", "Clockwork Key",
			"Winds itself, pops itself, resets itself. He still jumps."],
	},
}

var _force := false
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir in [ITEMS_DIR, AUGMENTS_DIR, SCENES_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)
	_seed_scenes()
	_seed_items()
	_seed_trees()
	_seed_capstones()
	print("seed_m39_fidgets: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	for id in FIDGETS:
		var path := "%s/%s.tscn" % [SCENES_DIR, id]
		if not _should_write(path):
			continue
		var row: Dictionary = FIDGETS[id]
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
	var spec := {
		"name": row["node"],
		"id": id,
		"script": row["script"],
		"mass": body["mass"],
		"bounce": body.get("bounce", 0.1),
		"friction": body.get("friction", 0.8),
		"properties": row.get("properties", {}),
	}
	# The body's own sprite, when the toy's main picture is the shop's assembled one rather
	# than the thing that collides: the sheet under the bubbles, the box under the lid.
	if body.has("sprite"):
		spec["sprite"] = "%s/%s_%s.png" % [SPRITES_DIR, id, body["sprite"]]
	return spec

func _add_parts(root: Node, id: StringName, row: Dictionary) -> void:
	var sprite := root.get_node("Sprite") as Sprite2D
	if row.has("rotor_pivot"):
		_pivot(sprite, row["rotor_pivot"])
		root.set(&"rotor", sprite)
	for part in row.get("parts", []):
		var node := Sprite2D.new()
		node.name = part["name"]
		node.texture = _require("%s/%s_%s.png" % [SPRITES_DIR, id, part["part"]])
		node.scale = Vector2(ART_SCALE, ART_SCALE)
		node.z_index = int(part.get("z", 0))
		node.visible = bool(part.get("visible", true))
		if part.has("pivot"):
			_pivot(node, part["pivot"])
		root.add_child(node)
		if part.has("as"):
			root.set(StringName(part["as"]), node)
	if row.get("bubbles", false):
		var layer := Node2D.new()
		layer.name = "Bubbles"
		root.add_child(layer)
		var texture := _require("%s/%s_bubble.png" % [SPRITES_DIR, id])
		# The bubble part is drawn in slot 0; every other slot is the same sprite moved.
		for r in 2:
			for c in 4:
				var bubble := Sprite2D.new()
				bubble.name = "Bubble%d" % (r * 4 + c)
				bubble.texture = texture
				bubble.scale = Vector2(ART_SCALE, ART_SCALE)
				bubble.position = Vector2(9 * c, 9 * r) * ART_SCALE
				layer.add_child(bubble)
		root.set(&"bubble_layer", layer)

## Turns a part about `pivot` (art px from the sprite's centre) rather than about its middle:
## the node goes to the pivot and the picture is offset back by the same amount, so at zero
## rotation nothing has moved.
func _pivot(node: Sprite2D, pivot: Vector2) -> void:
	node.position = pivot * ART_SCALE
	node.offset = -pivot

func _add_zones(root: Node, row: Dictionary) -> void:
	var zones := GestureZonesScript.new() as Node
	zones.name = "GestureZones"
	var table: Array = _bubble_zones() if row.get("bubbles", false) else row.get("zones", [])
	zones.set(&"zones", table)
	zones.set(&"action_enabled", bool(row.get("action", false)))
	root.add_child(zones)
	root.set(&"gestures", zones)

# --- items -----------------------------------------------------------------

func _seed_items() -> void:
	for id in FIDGETS:
		var row: Dictionary = FIDGETS[id]
		var path := "%s/%s.tres" % [ITEMS_DIR, id]
		if not _should_write(path):
			continue
		var item := ItemDataScript.new()
		item.id = id
		item.display_name = row["name"]
		item.description = row["description"]
		item.controls = row["controls"]
		# Play: toys he is given, beside the balls and the kite. They are worked by hand and he
		# works them himself when he is left alone, which is the Play tab's promise (0f04aa5).
		item.category = ItemDataScript.CATEGORY_TOY
		item.cost = row["cost"]
		item.currency = ItemDataScript.CURRENCY_HEARTS
		item.scene = _require("%s/%s.tscn" % [SCENES_DIR, id])
		item.sort_order = row["sort"]
		var icon := "%s/%s.png" % [ICONS_DIR, id]
		if ResourceLoader.exists(icon):
			item.icon = ResourceLoader.load(icon)
		_save(item, path)

# --- trees -----------------------------------------------------------------

## Three tier-1 nodes each, and every one of them read by the toy's own script — a node whose
## effect_key nothing reads is a placebo, and this project has shipped two of those:
##
##   damage_mult    the kindness value of everything it pays (`FidgetToy.pay_act` /
##                  `pay_sustained` multiply by `value_multiplier()`)
##   payout_mult    Hearts earned, applied by Economy to every source
##   cooldown_mult  "time between uses", as each toy means it: a bubble grows back sooner, a
##                  spinner runs down slower, the tune is shorter, fewer shakes ready the
##                  ball, a squeeze fills faster
func _seed_trees() -> void:
	for id in FIDGETS:
		var row: Dictionary = FIDGETS[id]
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
	node.currency = AugmentNodeScript.CURRENCY_HEARTS
	node.sort_order = sort_order
	_save(node, path)

# --- capstones -------------------------------------------------------------

## One levelled device per toy, by `seed_m35_engine.gd`'s Hearts rule. Written here rather than
## added to that tool's table, because the rule there is per-tool by design ("every content
## tool writes the capstones for the items it owns"), and `loop_check`'s "every item has an
## automation capstone" is the guard.
func _seed_capstones() -> void:
	for id in FIDGETS:
		var row: Dictionary = FIDGETS[id]
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
		node.effect_key = &"payout_mult"
		node.effect_per_level = 1.0
		node.max_levels = CAPSTONE_MAX_LEVELS
		node.cost_base = int(round(CAPSTONE_PRICE_FLOOR + cost * CAPSTONE_PRICE_SLOPE))
		node.cost_growth = CAPSTONE_COST_GROWTH
		node.currency = AugmentNodeScript.CURRENCY_HEARTS
		node.is_automation = true
		var rate := CAPSTONE_BASE_RATE + cost * CAPSTONE_RATE_SLOPE
		node.automation_rate = round(rate * 100.0) / 100.0
		node.requires_mastery = ItemDB.balance.mastery_automation_rank
		# A toy, so the tripod, as `seed_m35_engine._mount_for` decides for everything that is
		# not in the Care drawer.
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
		push_error("seed_m39_fidgets: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m39_fidgets: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
