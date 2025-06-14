class_name Gun
extends Node2D

enum cursor_type {
	PISTOL, 
	SHOTGUN, 
	RIFLE
}

@export var gun_type: cursor_type = cursor_type.PISTOL
@export var gun_active: bool = false
@export var fire_area: Area2D
@export var Effects_Player: EffectsPlayer


var pistol_texture: Texture2D = preload("res://Assets/Crosshair Basic.png")
var shotgun_texture: Texture2D = preload("res://Assets/Crosshair Basic.png")
var rifle_texture: Texture2D = preload("res://Assets/Crosshair Basic.png")




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



func _process(delta: float) -> void:
	if gun_active:
		fire_area.global_position = get_global_mouse_position() + Vector2(17,17) # Crosshair offset



func _input(event: InputEvent) -> void:
	if gun_active:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			fire()
			Effects_Player.explosion_effect(fire_area.global_position)


func fire() -> void:
	# Random direction vector
	var direction = Vector2.UP.rotated(randf_range(-PI/4, PI/4))
	var force_strength = 1000.0

	# Apply force to bodies in the fire area
	for body in fire_area.get_overlapping_bodies():
		if body is RigidBody2D:
			body.apply_impulse(direction * force_strength, Vector2.ZERO)
