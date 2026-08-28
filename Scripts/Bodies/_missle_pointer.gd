class_name MisslePointer
extends Node2D

## Cursor power: click to call in a missile. Consolidated into CursorPowerBase, renamed
## to Missile (correct spelling) and given a real spawn origin in M2.

## Missiles fly in from off the top of the play area.
const SPAWN_OFFSET := Vector2(0, -800)

@export var active: bool = false
@export var cooldown_seconds: float = 1.0

var crosshair_texture: Texture2D = preload("res://Assets/Missle-Crosshair.png")
var missle_scene: PackedScene = preload("res://Scenes/Cursor_Powers/_missle.tscn")
var in_cooldown: bool = false

func _ready() -> void:
	add_to_group(&"power_missile")
	if active:
		Input.set_custom_mouse_cursor(crosshair_texture)

func make_active() -> void:
	active = true
	Input.set_custom_mouse_cursor(crosshair_texture)

func make_inactive() -> void:
	active = false
	Input.set_custom_mouse_cursor(null)

func _process(_delta: float) -> void:
	if not active or in_cooldown:
		return
	if not Input.is_action_just_pressed("mouse_left"):
		return
	_fire()

func _fire() -> void:
	var target := get_global_mouse_position()
	var missle := missle_scene.instantiate()
	missle.global_position = target + SPAWN_OFFSET
	var host := get_tree().current_scene
	if host == null:
		return
	host.add_child(missle)
	missle.set_target()

	in_cooldown = true
	await get_tree().create_timer(cooldown_seconds).timeout
	in_cooldown = false
