class_name Gun
extends Node

enum cursor_type {
    PISTOL, 
    SHOTGUN, 
    RIFLE
}

@export var gun_type: cursor_type = cursor_type.PISTOL
@export var gun_active: bool = false


var pistol_texture: Texture2D = preload("res://Assets/Crosshair Basic.png")
var shotgun_texture: Texture2D = preload("res://Assets/Crosshair Shotgun.png")
var rifle_texture: Texture2D = preload("res://Assets/Crosshair Rifle.png")




func _ready() -> void:
    var cursor_texture: Texture2D
    match gun_type:
        cursor_type.PISTOL:
            cursor_texture = pistol_texture
        cursor_type.SHOTGUN:
            cursor_texture = shotgun_texture
        cursor_type.RIFLE:
            cursor_texture = rifle_texture
        _:
            cursor_texture = null


    if gun_active:
        Input.set_custom_mouse_cursor(cursor_texture)
    else:
        #reset crosshair to default
        Input.set_custom_mouse_cursor(null)
