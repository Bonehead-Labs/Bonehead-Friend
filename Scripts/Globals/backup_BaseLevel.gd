class_name BaseLevel extends Node

# @export var main_menu: Control
# @export var item_menu: Control
# @onready var main_menu_open: bool = false
@onready var item_menu: Control = get_node("Menus/ItemMenu")

func _ready() -> void:
	pass




