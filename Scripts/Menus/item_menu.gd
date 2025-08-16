extends Control
@onready var item_limit: int = 10
@onready var item_count: int = 0
@onready var cursor_item_active: bool = false
var baseball_bat_scene: PackedScene = preload("res://Scenes/bodies/BaseballBat.tscn")
var mace_scene: PackedScene = preload("res://Scenes/bodies/_Mace.tscn")
#var gun_scene: PackedScene = preload("res://Scenes/Cursor_Powers/_gun.tscn")
var missle_launcher_scene: PackedScene = preload("res://Scenes/Cursor_Powers/missle_pointer.tscn")
var dynamite_scene: PackedScene = preload("res://Scenes/Bodies/_Dynamite.tscn")
var hand_grenade_scene: PackedScene = preload("res://Scenes/Bodies/_Grenade.tscn")
var fist_scene: PackedScene = preload("res://Scenes/Cursor_Powers/_fist.tscn")

var active_items: Array = []

func _ready() -> void:
	pass

func _on_toggle_items_pressed() -> void:
	if !visible:
		visible = true
		process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED


func spawn_item(item_scene: PackedScene) -> void:
	if item_count < item_limit:
		var item = item_scene.instantiate()
		item.global_position = Vector2(600,100)
		get_tree().current_scene.add_child(item)
		item_count += 1
		active_items.append(item)
	else:
		print("Item limit reached")
		

func activate_power(power_scene: PackedScene) -> void:
	power_scene.make_active()

func _on_baseball_icon_pressed() -> void:
	spawn_item(baseball_bat_scene)


func _on_mace_icon_pressed() -> void:
	spawn_item(mace_scene)


func _on_gun_icon_pressed() -> void:
	get_node("../BaseLevel/_Gun").make_active()
