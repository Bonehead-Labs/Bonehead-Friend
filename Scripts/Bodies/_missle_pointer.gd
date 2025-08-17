class_name MisslePointer
extends Node2D

@export var active: bool = false
var crosshair_texture: Texture2D = preload("res://Assets/Missle-Crosshair.png")
var missle_scene: PackedScene = preload("res://Scenes/Cursor_Powers/_missle.tscn")
var in_cooldown: bool = false

func _ready() -> void:
    if active:
        Input.set_custom_mouse_cursor(crosshair_texture)
    # else:
    #     #reset crosshair to default
    #     Input.set_custom_mouse_cursor(null)

func make_active() -> void:
    active = true
    Input.set_custom_mouse_cursor(crosshair_texture)

func make_inactive() -> void:
    active = false
    Input.set_custom_mouse_cursor(null)

func _process(delta: float) -> void:
    if active and not in_cooldown:
        if Input.is_action_just_pressed("mouse_left"):
            print("Missle fired")
            var missle = missle_scene.instantiate()
            missle.global_position = Vector2(600,-200)
            print("Missle Spawned")
            get_tree().current_scene.add_child(missle)
            missle.set_target()
            
            in_cooldown = true
            await get_tree().create_timer(1).timeout
            in_cooldown = false