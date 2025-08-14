extends Control
@onready var item_limit: int = 10
@onready var item_count: int = 0
var baseball_bat_scene: PackedScene = preload("res://Scenes/bodies/BaseballBat.tscn")

func _ready() -> void:
    pass

func _on_toggle_items_pressed() -> void:
    if !visible:
        visible = true
        process_mode = Node.PROCESS_MODE_ALWAYS
    else:
        visible = false
        process_mode = Node.PROCESS_MODE_DISABLED


func _on_baseball_icon_pressed() -> void:
    if item_count < item_limit:
        var bat = baseball_bat_scene.instantiate()
        bat.global_position = Vector2(600,100)
        get_tree().current_scene.add_child(bat)
        item_count += 1
    else:
        print("Item limit reached")
