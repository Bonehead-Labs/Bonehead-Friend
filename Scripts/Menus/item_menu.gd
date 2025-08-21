extends Control
@onready var item_limit: int = 10
@onready var item_count: int = 0
@onready var cursor_item_active: bool = false
var baseball_bat_scene: PackedScene = preload("res://Scenes/Bodies/BaseballBat.tscn")
var mace_scene: PackedScene = preload("res://Scenes/Bodies/_Mace.tscn")
var missle_launcher_scene: PackedScene = preload("res://Scenes/Cursor_Powers/missle_pointer.tscn")
var dynamite_scene: PackedScene = preload("res://Scenes/Bodies/_Dynamite.tscn")
var grenade_scene: PackedScene = preload("res://Scenes/Bodies/_Grenade.tscn")
var fist_scene: PackedScene = preload("res://Scenes/Cursor_Powers/_fist.tscn")

@onready var missle_launcher = get_node_or_null("/root/BaseLevel/MisslePointer")
@onready var gun = get_node_or_null("/root/BaseLevel/_Gun")
@onready var fist = get_node_or_null("/root/BaseLevel/_Fist")
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
		

func _on_baseball_icon_pressed() -> void:
	spawn_item(baseball_bat_scene)


func _on_mace_icon_pressed() -> void:
	spawn_item(mace_scene)


func _on_gun_icon_pressed() -> void:
	if missle_launcher and missle_launcher.active == true:
		missle_launcher.make_inactive()
	if gun and gun.gun_active == false:
		gun.make_active()
	elif gun and gun.gun_active == true:
		gun.make_inactive()
	else:
		print("Gun node not found at /root/BaseLevel/_Gun")


func _on_missle_icon_pressed() -> void:
	if gun and gun.gun_active == true:
		gun.make_inactive()
	if missle_launcher and missle_launcher.active == false:
		missle_launcher.make_active()
	elif missle_launcher and missle_launcher.active == true:
		missle_launcher.make_inactive()
	else:
		print("Gun node not found at /root/BaseLevel/MisslePointer")


func _on_fist_icon_pressed() -> void:
	gun.make_inactive()
	missle_launcher.make_inactive()
	if fist and fist.active == false:
		fist.make_active()
	elif fist and fist.active == true:
		fist.make_inactive()
	else:
		print("Fist node not found at /root/BaseLevel/_Fist")


func _on_grenade_icon_pressed() -> void:
	spawn_item(grenade_scene)


func _on_dynamite_icon_pressed() -> void:
	spawn_item(dynamite_scene)
