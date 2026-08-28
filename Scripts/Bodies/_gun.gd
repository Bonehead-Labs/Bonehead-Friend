class_name Gun
extends Node2D

## Cursor power: crosshair that shoves nearby bodies. Consolidated into CursorPowerBase
## in M2, where the three gun types get distinct textures and real damage.

enum cursor_type {
	PISTOL,
	SHOTGUN,
	RIFLE,
}

@export var gun_type: cursor_type = cursor_type.PISTOL
@export var active: bool = false
@export var fire_area: Area2D
@export var Effects_Player: EffectsPlayer

## Offset from the hotspot of the crosshair cursor to its centre.
const CURSOR_OFFSET := Vector2(17, 17)
const FIRE_FORCE := 1000.0

# All three still point at the same texture — the variety is stubbed until M2.
var pistol_texture: Texture2D = preload("res://Assets/Crosshair Basic.png")
var shotgun_texture: Texture2D = preload("res://Assets/Crosshair Basic.png")
var rifle_texture: Texture2D = preload("res://Assets/Crosshair Basic.png")

func _ready() -> void:
	add_to_group(&"power_gun")

func make_active() -> void:
	active = true
	Input.set_custom_mouse_cursor(get_cursor_texture())

func make_inactive() -> void:
	active = false
	Input.set_custom_mouse_cursor(null)

func get_cursor_texture() -> Texture2D:
	match gun_type:
		cursor_type.PISTOL: return pistol_texture
		cursor_type.SHOTGUN: return shotgun_texture
		cursor_type.RIFLE: return rifle_texture
	return null

func _process(_delta: float) -> void:
	if active and fire_area:
		fire_area.global_position = get_global_mouse_position() + CURSOR_OFFSET

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and not event.is_echo():
		fire()

func fire() -> void:
	if fire_area == null:
		return
	# Random upward-ish shove. Becomes directional, damaging fire in M2.
	var direction := Vector2.UP.rotated(randf_range(-PI / 4.0, PI / 4.0))
	for body in fire_area.get_overlapping_bodies():
		if body is RigidBody2D:
			body.apply_impulse(direction * FIRE_FORCE, Vector2.ZERO)
	if Effects_Player:
		Effects_Player.explosion_effect(fire_area.global_position)
