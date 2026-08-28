extends Control

## Interim item menu. Replaced entirely in M2 by ItemDB + data-driven tiles
## (docs/decisions.md D8) — every item here still costs three coordinated edits to add.
##
## What M0 fixed: cursor powers are found by group instead of absolute node path
## (the "/root/BaseLevel/_Gun" pattern that shipped a crash), and freed items now
## release their slot instead of permanently burning it.

const ITEM_LIMIT := 10
const SPAWN_POSITION := Vector2(600, 100)

const GROUP_SPAWNED := &"spawned_item"
const GROUP_FIST := &"power_fist"
const GROUP_GUN := &"power_gun"
const GROUP_MISSILE := &"power_missile"

var baseball_bat_scene: PackedScene = preload("res://Scenes/Bodies/BaseballBat.tscn")
var mace_scene: PackedScene = preload("res://Scenes/Bodies/_Mace.tscn")
var dynamite_scene: PackedScene = preload("res://Scenes/Bodies/_Dynamite.tscn")
var grenade_scene: PackedScene = preload("res://Scenes/Bodies/_Grenade.tscn")

var active_items: Array[Node2D] = []

func _on_toggle_items_pressed() -> void:
	visible = not visible
	process_mode = Node.PROCESS_MODE_ALWAYS if visible else Node.PROCESS_MODE_DISABLED
	# The overlay makes the whole window clickable while a panel is open.
	EventBus.ui_panel_changed.emit(&"items" if visible else &"")

# --- spawning --------------------------------------------------------------

func spawn_item(item_scene: PackedScene) -> void:
	_prune_freed_items()
	if active_items.size() >= ITEM_LIMIT:
		return

	var host := get_tree().current_scene
	if host == null:
		return

	var item := item_scene.instantiate() as Node2D
	item.global_position = SPAWN_POSITION
	# The trash bin only deletes members of this group, so anything spawnable must join it.
	item.add_to_group(GROUP_SPAWNED)
	host.add_child(item)

	active_items.append(item)
	EventBus.item_spawned.emit(item)

## Freed items used to leave their slot occupied forever, so a player who binned ten
## things could never spawn anything again.
func _prune_freed_items() -> void:
	active_items = active_items.filter(func(i: Node2D) -> bool: return is_instance_valid(i))

# --- cursor powers ---------------------------------------------------------

func _power(group: StringName) -> Node:
	return get_tree().get_first_node_in_group(group)

## Only one cursor power can be live at a time.
func _toggle_power(group: StringName) -> void:
	var target := _power(group)
	if target == null:
		push_warning("item_menu: no cursor power in group %s" % group)
		return

	var was_active: bool = target.active
	for other_group in [GROUP_FIST, GROUP_GUN, GROUP_MISSILE]:
		var other := _power(other_group)
		if other and other != target:
			other.make_inactive()

	if was_active:
		target.make_inactive()
		# Tells the overlay to stop treating the whole window as a click target.
		EventBus.cursor_power_changed.emit(&"")
	else:
		target.make_active()
		EventBus.cursor_power_changed.emit(group)

# --- button handlers -------------------------------------------------------

func _on_baseball_icon_pressed() -> void:
	spawn_item(baseball_bat_scene)

func _on_mace_icon_pressed() -> void:
	spawn_item(mace_scene)

func _on_grenade_icon_pressed() -> void:
	spawn_item(grenade_scene)

func _on_dynamite_icon_pressed() -> void:
	spawn_item(dynamite_scene)

func _on_gun_icon_pressed() -> void:
	_toggle_power(GROUP_GUN)

func _on_missle_icon_pressed() -> void:
	_toggle_power(GROUP_MISSILE)

func _on_fist_icon_pressed() -> void:
	_toggle_power(GROUP_FIST)
