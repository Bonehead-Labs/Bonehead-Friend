class_name Missle
extends Node2D

var target: Vector2
@export var speed: float = 100.0
@export var damage: float = 10.0
@export var explosion_area: Area2D
@export var max_force: float = 10000.0
var is_primed: bool = false

func _ready():
    pass

func set_target():
    if Input.is_action_just_pressed("mouse_left") and is_primed:
        target = get_global_mouse_position()
        is_primed = false
        pass

func _process(delta):
    pass

func _physics_process(delta):
    pass
