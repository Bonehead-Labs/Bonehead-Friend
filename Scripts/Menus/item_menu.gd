extends Control

var item_database: Dictionary

func _ready() -> void:
    item_database = {
        "baseball_bat": {
            "item_name": "baseball_bat",
            "item_description": "This is item 1",
            "item_icon": ""
        },
        "mace": {
            "item_name": "mace",
            "item_description": "This is item 2",
            "item_icon": ""
        },
        "fist": {
            "item_name": "fist",
            "item_description": "This is item 3",
        },
        "gun": {
            "item_name": "gun",
            "item_description": "This is item 4",
            "item_icon": ""
        },
        "missle_pointer": {
            "item_name": "knife",
            "item_description": "This is item 5",
        },
        "grenade": {
            "item_name": "grenade",
            "item_description": "This is item 6",
            "item_icon": ""
        },
        "dynamite": {
            "item_name": "dynamite",
            "item_description": "This is item 7",
        }
    }

func _on_toggle_items_pressed() -> void:
    if !visible:
        visible = true
        process_mode = Node.PROCESS_MODE_ALWAYS
    else:
        visible = false
        process_mode = Node.PROCESS_MODE_DISABLED
