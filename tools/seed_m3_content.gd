extends Node

## Writes M3's progression content: personalities, the contract board, the remaining item
## roster, and the augment trees and automation capstones that go with them.
##
##   Godot --headless --path <project> res://tools/seed_m3_content.tscn [-- --force | --only id,id]
##
## Same rules as the other seed tools: scenes are packed from script because hand-editing
## .tscn is banned (CLAUDE.md), and only files that do not already exist are written, so
## retuning a number in the inspector is never silently reverted by a re-run.
##
## **No art here either.** New props are flat Polygon2D placeholders, like M3's friendly
## items. The art pass swaps each for an AnimatedSprite2D and nothing else changes.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const ContractDataScript := preload("res://Scripts/Data/contract_data.gd")
const PersonalityDataScript := preload("res://Scripts/Data/personality_data.gd")
const WeaponBaseScript := preload("res://Scripts/Bodies/weapon_base.gd")
const FriendlyBaseScript := preload("res://Scripts/Bodies/friendly_base.gd")
const GunPowerScript := preload("res://Scripts/Bodies/Powers/gun_power.gd")
const DraggableAreaScript := preload("res://Scripts/Bodies/draggable_area.gd")

const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const CONTRACTS_DIR := "res://Data/Contracts"
const PERSONALITIES_DIR := "res://Data/Personalities"
const PROPS_DIR := "res://Scenes/Props"
const POWERS_DIR := "res://Scenes/Powers"

const LAYER_ITEM := 4
const ITEM_MASK := 1 | 2 | 4  # world | buddy | item

var _force := false
## `--only id,id`: rewrite those ids' scenes and items and nothing else (D61, D64). The way to
## re-seed one row after it changes — `--force` would also rewrite every personality, contract
## and tree this tool owns, including the ones later milestones refined.
var _only := PackedStringArray()
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	var only_at := OS.get_cmdline_user_args().find("--only")
	if only_at >= 0 and only_at + 1 < OS.get_cmdline_user_args().size():
		_only = OS.get_cmdline_user_args()[only_at + 1].split(",", false)
	for dir in [ITEMS_DIR, AUGMENTS_DIR, CONTRACTS_DIR, PERSONALITIES_DIR, PROPS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	_seed_personalities()
	_seed_contracts()
	_seed_scenes()
	_seed_items()
	_seed_augments()

	print("seed_m3_content: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- personalities ---------------------------------------------------------

## Five personalities, five different optimal rhythms. Each is only a mood curve sampled
## over (mood + 100) / 200 — despair at x=0, neutral at 0.5, bliss at 1.0.
##
## Stoic is the balance default and the first-run personality. The other four deliberately
## disagree about *where* the money is, so a run after a Reincarnation asks the player to
## play differently rather than to play the same way faster.
func _seed_personalities() -> void:
	_personality(&"stoic", "Stoic", "Takes it all in his stride. Pays at both extremes and worst in the middle — the honest seesaw.",
		[2.0, 1.2, 0.6, 1.2, 2.0], 0)
	_personality(&"masochist", "Masochist", "Enjoys it, worryingly. Misery pays far better than bliss, so there is little reason to cheer him up beyond keeping him clean.",
		[2.8, 1.6, 0.6, 0.9, 1.1], 10)
	_personality(&"diva", "Diva", "Demands to be adored. Bliss pays far better than misery — the run where you mostly put the bat down.",
		[1.1, 0.9, 0.6, 1.6, 2.8], 20)
	_personality(&"zen", "Zen", "Unbothered either way. A shallow curve that never pays 2x and never drops to 0.6 — the personality for a run you want to mostly idle.",
		[1.4, 1.2, 1.0, 1.2, 1.4], 30)
	_personality(&"goth", "Goth", "Happiest when slightly miserable. The peak sits off-centre, which breaks every habit the other four teach.",
		[1.6, 2.2, 1.0, 0.8, 1.4], 40)

func _personality(id: StringName, display_name: String, description: String,
		points: Array, sort_order: int) -> void:
	var path := "%s/%s.tres" % [PERSONALITIES_DIR, id]
	if not _should_write(path):
		return
	var res := PersonalityDataScript.new()
	res.id = id
	res.display_name = display_name
	res.description = description
	res.mood_curve = _curve(points)
	res.sort_order = sort_order
	_save(res, path)

## Five evenly spaced points, baked. Baked because the payout pipeline samples this on every
## hit and sample_baked is a lookup where sample() is a solve.
func _curve(points: Array) -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 3.0
	for i in points.size():
		curve.add_point(Vector2(float(i) / float(points.size() - 1), float(points[i])))
	curve.bake()
	return curve

# --- contracts -------------------------------------------------------------

## Targets are first-draft and sized against the balance targets in docs/economy.md: a daily
## should be a session's work, not a week's. Retune from playtest CSVs.
func _seed_contracts() -> void:
	# Rewards are Dollars since D31 — a day's work is a few hundred, a week's a few
	# thousand, against cosmetics priced in the low thousands. They used to be one to five
	# Ectoplasm, which bought nothing at all.
	_contract(&"daily_damage", "Occupational Therapy", "Deal 5,000 damage.",
		&"deal_damage", 5000, ContractDataScript.PERIOD_DAILY, 400, 0)
	_contract(&"daily_kindness", "Bedside Manner", "Be kind to him 150 times.",
		&"kindness", 150, ContractDataScript.PERIOD_DAILY, 400, 10)
	_contract(&"daily_knockouts", "Ten Rounds", "Knock him out 10 times.",
		&"knockout", 10, ContractDataScript.PERIOD_DAILY, 500, 20)
	_contract(&"daily_petting", "Good Boy", "Pet him 200 times.",
		&"pet", 200, ContractDataScript.PERIOD_DAILY, 400, 30)
	_contract(&"weekly_damage", "Full Body Workout", "Deal 100,000 damage.",
		&"deal_damage", 100000, ContractDataScript.PERIOD_WEEKLY, 2500, 40)
	_contract(&"weekly_shopping", "Retail Therapy", "Buy 5 new toys.",
		&"purchase", 5, ContractDataScript.PERIOD_WEEKLY, 2000, 50)

func _contract(id: StringName, display_name: String, description: String, goal_key: StringName,
		target: int, period: int, reward: int, sort_order: int) -> void:
	var path := "%s/%s.tres" % [CONTRACTS_DIR, id]
	if not _should_write(path):
		return
	var res := ContractDataScript.new()
	res.id = id
	res.display_name = display_name
	res.description = description
	res.goal_key = goal_key
	res.target = target
	res.period = period
	res.reward_dollars = reward
	res.sort_order = sort_order
	_save(res, path)

# --- scenes ----------------------------------------------------------------

func _seed_scenes() -> void:
	# Melee and props. Mass is what turns a swing into a contact impulse, so it is the main
	# thing that differentiates these — a bowling ball hurts because it is heavy, not
	# because it has a bigger number attached to it (docs/decisions.md D7).
	_save_scene(_build_prop("FryingPan", &"frying_pan", WeaponBaseScript, Color(0.30, 0.31, 0.35),
		Vector2(46, 18), 6.0, {"damage_mult": 0.75}, 0.2),
		"%s/frying_pan.tscn" % PROPS_DIR)
	_save_scene(_build_prop("BowlingBall", &"bowling_ball", WeaponBaseScript, Color(0.16, 0.14, 0.22),
		Vector2(34, 34), 14.0, {"damage_mult": 1.0}, 0.15),
		"%s/bowling_ball.tscn" % PROPS_DIR)
	# The beach ball is a catch, like the baseball, and not a weapon (D64). It was a WeaponBase
	# in the Play drawer, so the receiver asked a 0.4 kg ball for the 1,500 fall floor — about
	# 2,200 px/s — and it never paid anything, while its description said "it hurts nobody".
	# Cheaper per catch and easier to catch than the baseball: a gentle toss, or him heading it.
	_save_scene(_build_prop("BeachBall", &"beach_ball", FriendlyBaseScript, Color(0.95, 0.45, 0.45),
		Vector2(40, 40), 0.4,
		{"hearts_per_contact": 4.0, "contact_cooldown": 0.5, "min_contact_speed": 200.0}, 0.7),
		"%s/beach_ball.tscn" % PROPS_DIR)

	# The baseball is the Interactive Buddy homage: throw it at him and he catches it. It is
	# a FriendlyBase with a speed gate, so only a real throw pays — dropping it on his head
	# from one pixel up is not a catch.
	_save_scene(_build_prop("Baseball", &"baseball", FriendlyBaseScript, Color(0.93, 0.92, 0.88),
		Vector2(20, 20), 0.8,
		{"hearts_per_contact": 6.0, "contact_cooldown": 0.35, "min_contact_speed": 420.0},
		0.55), "%s/baseball.tscn" % PROPS_DIR)

	# The shotgun is a GunPower with pellets. Same class as the pistol, different numbers —
	# which is the point of having a class at all.
	var shotgun := Node2D.new()
	shotgun.name = "ShotgunPower"
	shotgun.set_script(GunPowerScript)
	shotgun.set(&"item_id", &"shotgun")
	shotgun.set(&"blast_radius", 40.0)
	shotgun.set(&"blast_force", 2200.0)
	shotgun.set(&"pellets", 5)
	shotgun.set(&"spread", 64.0)
	shotgun.set(&"cooldown_seconds", 0.75)
	# Its own reticle, and not the pistol's: four brackets around an area rather than a
	# point on one (art/tools/make_crosshairs.py). Equipping it used to leave the ordinary
	# arrow on screen, so the one cursor power whose shot does *not* land where you point
	# was also the one with no aiming affordance at all. The hotspot is the reticle's centre
	# dot; get it wrong and every pellet spread is offset from where the player aimed.
	var reticle := "res://Assets/sprites/cursors/shotgun.png"
	if ResourceLoader.exists(reticle):
		shotgun.set(&"cursor_texture", ResourceLoader.load(reticle))
		shotgun.set(&"cursor_hotspot", Vector2(32, 32))
	_save_scene(shotgun, "%s/shotgun_power.tscn" % POWERS_DIR)

## One draggable body with a placeholder shape, a grab region and a drag handle — the same
## skeleton every item scene in the project has.
func _build_prop(node_name: String, item_id: StringName, script: Script, colour: Color,
		extent: Vector2, body_mass: float, properties: Dictionary, bounce: float) -> Node:
	var root := RigidBody2D.new()
	root.name = node_name
	root.set_script(script)
	root.collision_layer = LAYER_ITEM
	root.collision_mask = ITEM_MASK
	root.mass = body_mass
	root.contact_monitor = true
	root.max_contacts_reported = 4

	# Bounce lives on a PhysicsMaterial, which is also the difference between a beach ball
	# and a bowling ball being fun.
	var physics := PhysicsMaterial.new()
	physics.bounce = bounce
	physics.friction = 0.8
	root.physics_material_override = physics

	for key in properties:
		root.set(StringName(key), properties[key])

	var round_shape := extent.x == extent.y
	root.add_child(_visual_for(item_id, colour, extent, round_shape))

	# The collider is the picture (D55) — measured off the sprite's own opaque pixels rather
	# than a hand-typed extent that the art then moved away from. The frying pan's box was
	# 46x18 inside a 116x60 picture: a sixth of the thing you were swinging.
	var solid := _collider_extent(item_id, extent)
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	# Round only when the art really is round, decided by the art and not by the typed
	# numbers happening to be square.
	if round_shape and absf(solid.x - solid.y) <= 2.0:
		var circle := CircleShape2D.new()
		circle.radius = maxf(solid.x, solid.y) * 0.5
		collider.shape = circle
	else:
		var box := RectangleShape2D.new()
		box.size = solid
		collider.shape = box
	root.add_child(collider)

	var grab_shape := RectangleShape2D.new()
	grab_shape.size = Vector2(maxf(solid.x + 12.0, 34.0), maxf(solid.y + 12.0, 34.0))
	var grab_collider := CollisionShape2D.new()
	grab_collider.name = "CollisionShape2D"
	grab_collider.shape = grab_shape

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

	root.set(&"drag_area", drag_area)
	root.set(&"handle", handle)
	root.set(&"collider", collider)
	return root


## The item's generated sprite, if it has one. Items without art keep their flat Polygon2D
## placeholder, so a half-finished art pass still leaves every item visible and playable.
## How much bigger the sprite is drawn than its art pixels; the collider has to agree.
const ART_SCALE := 2.0

## The collider is the picture (D55). See the long note in `tools/seed_friendly.gd` — this
## file had the same fault, writing a typed art-pixel extent into a world-pixel shape while
## drawing the sprite at 2x.
func _collider_extent(item_id: StringName, fallback: Vector2) -> Vector2:
	var texture := _art_for(item_id)
	if texture == null:
		return fallback
	var used := texture.get_image().get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return fallback
	return Vector2(used.size) * ART_SCALE

func _art_for(item_id: StringName) -> Texture2D:
	var path := "res://Assets/sprites/items/%s.png" % item_id
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D

## Sprite when art exists, coloured block when it does not. Sprites are authored at their
## true pixel size (docs/art-direction.md scale table) and rendered at 2x like everything
## else, so the node carries the scale rather than the asset.
func _visual_for(item_id: StringName, colour: Color, extent: Vector2,
		round_shape: bool = false) -> Node2D:
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
	visual.polygon = _disc(extent.x * 0.5) if round_shape else _rounded_box(extent)
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

func _disc(radius: float, segments: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segments:
		out.append(Vector2.RIGHT.rotated(TAU * float(i) / float(segments)) * radius)
	return out

func _save_scene(root: Node, path: String) -> void:
	if not _should_write(path):
		root.free()
		return
	# Every descendant needs `owner` set to the root or pack() writes the root alone.
	_claim(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("seed_m3_content: failed to pack %s" % path)
		root.free()
		return
	var err := ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("seed_m3_content: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)

func _claim(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_claim(child, owner_node)

# --- items -----------------------------------------------------------------

## Prices are the catalog's (docs/game-design.md). Sort orders slot each new item into its
## existing category between the ones already there.
func _seed_items() -> void:
	_item(&"frying_pan", "Frying Pan", "A tremendous flat clang. Sends him further than it hurts him.",
		ItemDataScript.CATEGORY_WEAPON, 250, ItemDataScript.CURRENCY_BONES,
		"%s/frying_pan.tscn" % PROPS_DIR, 5)
	_item(&"shotgun", "Shotgun", "Five pellets in a spread. Close range is the whole idea.",
		ItemDataScript.CATEGORY_CURSOR_POWER, 2200, ItemDataScript.CURRENCY_BONES,
		"%s/shotgun_power.tscn" % POWERS_DIR, 15)
	_item(&"bowling_ball", "Bowling Ball", "Fourteen kilos of bad news. Drop it from height.",
		ItemDataScript.CATEGORY_TOY, 700, ItemDataScript.CURRENCY_BONES,
		"%s/bowling_ball.tscn" % PROPS_DIR, 10)
	# Hearts, like every other kind toy in the Play drawer (D64): it is a catch, and a toy you
	# are nice to him with is bought with kindness.
	_item(&"beach_ball", "Beach Ball", "Almost weightless and absurdly bouncy. He loves it and it hurts nobody.",
		ItemDataScript.CATEGORY_TOY, 100, ItemDataScript.CURRENCY_HEARTS,
		"%s/beach_ball.tscn" % PROPS_DIR, 0)
	_item(&"baseball", "Baseball", "Throw it and he catches it without moving. Harder throws are worth more.",
		ItemDataScript.CATEGORY_TOY, 120, ItemDataScript.CURRENCY_HEARTS,
		"%s/baseball.tscn" % PROPS_DIR, 15)

func _item(id: StringName, display_name: String, description: String, category: int,
		cost: int, currency: int, scene_path: String, sort_order: int) -> void:
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
	_save(item, path)

# --- augments --------------------------------------------------------------

## Trees for the items that carry the milestone, plus the first two automation capstones.
##
## Every tree is the same three tier-1 nodes (damage / payout / rate or weight), because the
## identical shape is what makes a per-item tree nearly free — one UI, one data pattern, and
## a new weapon's tree is three .tres files (docs/economy.md).
func _seed_augments() -> void:
	_tier1(&"mace", "Crushing Blow", "Bone Tax", "Denser Head", 90, 70, 55)
	_tier1(&"pistol", "Hollow Point", "Bounty", "Quick Draw", 110, 85, 70, &"cooldown_mult", 0.94)
	_tier1(&"grenade", "Bigger Bang", "Shrapnel Salvage", "Heavier Casing", 80, 65, 50)
	_tier1(&"frying_pan", "Cast Iron", "Clang Collector", "Thicker Base", 70, 55, 45)
	_tier1(&"open_hand", "Gentler Touch", "Warm Welcome", "Faster Strokes", 30, 25, 20,
		&"cooldown_mult", 0.94, AugmentNodeScript.CURRENCY_HEARTS)

	# --- Tier 2: the bat's exclusive branch ---
	#
	# Three flavours from one weapon at almost no content cost, and the one that converts
	# damage payout into Hearts is the design's own joke made buyable: a bat that is nice
	# to him. Needs mastery 10, which is the first place mastery gates anything.
	_branch(&"bat_slugger", &"baseball_bat", "Slugger", "Hits like a truck and pays like one.",
		&"damage_mult", 1.6, 900)
	_branch(&"bat_bonecutter", &"baseball_bat", "Bone Cutter", "Less force, far better rates.",
		&"payout_mult", 1.8, 900)
	_branch(&"bat_pillow", &"baseball_bat", "Pillow Bat", "Does almost nothing, and he loves you for it.",
		&"damage_mult", 0.35, 900)

	# --- Capstones: automation ---
	#
	# Hearts-priced and Mastery-gated, which is D2's spine: you cannot stop working for your
	# money without being nice to him. Prestige is deliberately NOT required — see the note
	# in docs/decisions.md D17.
	_capstone(&"bat_sentry", &"baseball_bat", "Bat Sentry",
		"A bat on a tripod that swings at him while you work.", 900, 2.5, 25)
	_capstone(&"boombox_playlist", &"boombox", "Endless Playlist",
		"The boombox keeps itself going, and keeps paying, while the game is closed.", 1400, 0.8, 25)

func _tier1(item_id: StringName, damage_name: String, payout_name: String, third_name: String,
		damage_cost: int, payout_cost: int, third_cost: int,
		third_key: StringName = &"mass_mult", third_effect: float = 1.08,
		currency: int = AugmentNodeScript.CURRENCY_BONES) -> void:
	_augment("%s_damage" % item_id, item_id, damage_name, &"damage_mult", 1.15, damage_cost, 1.12, 0, currency)
	_augment("%s_payout" % item_id, item_id, payout_name, &"payout_mult", 1.12, payout_cost, 1.10, 1, currency)
	_augment("%s_third" % item_id, item_id, third_name, third_key, third_effect, third_cost, 1.09, 2, currency)

func _augment(id: String, item_id: StringName, display_name: String, effect_key: StringName,
		effect_per_level: float, cost_base: int, cost_growth: float, sort_order: int,
		currency: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = StringName(id)
	node.item_id = item_id
	node.display_name = display_name
	node.effect_key = effect_key
	node.effect_per_level = effect_per_level
	node.max_levels = 10
	node.cost_base = cost_base
	node.cost_growth = cost_growth
	node.currency = currency
	node.sort_order = sort_order
	_save(node, path)

func _branch(id: StringName, item_id: StringName, display_name: String, description: String,
		effect_key: StringName, effect: float, cost: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = id
	node.item_id = item_id
	node.display_name = display_name
	node.description = description
	node.tier = 2
	node.effect_key = effect_key
	node.effect_per_level = effect
	node.max_levels = 1
	node.cost_base = cost
	node.cost_growth = 1.0
	node.currency = AugmentNodeScript.CURRENCY_BONES
	node.exclusive_group = &"flavour"
	node.requires_mastery = 10
	_save(node, path)

func _capstone(id: StringName, item_id: StringName, display_name: String, description: String,
		cost: int, rate: float, mastery: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = id
	node.item_id = item_id
	node.display_name = display_name
	node.description = description
	node.tier = 3
	# A capstone's effect is its rate, not a multiplier, so effect_key is inert here and
	# effect_per_level stays 1.0 — see AugmentNode.automation_rate.
	node.effect_key = &"payout_mult"
	node.effect_per_level = 1.0
	node.max_levels = 1
	node.cost_base = cost
	node.cost_growth = 1.0
	node.currency = AugmentNodeScript.CURRENCY_HEARTS
	node.is_automation = true
	node.automation_rate = rate
	node.requires_mastery = mastery
	_save(node, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if not _only.is_empty():
		return _only.has(path.get_file().get_basename())
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m3_content: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m3_content: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
