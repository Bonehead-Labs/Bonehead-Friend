extends RigidBody2D
@export var _Sprite: Sprite2D
@export var follow_Speed: float = 2000.0  # Increased for faster movement
@export var leeway_radius: float = 50.0  # Small radius for mouse movement detection
@export var active: bool = false

var last_rotation: float = 0.0  # Store the last rotation value
var previous_mouse_position: Vector2  # Track previous mouse position

func _ready():
    previous_mouse_position = get_global_mouse_position()
    gravity_scale = 0.0
    make_inactive()

func _physics_process(delta: float) -> void:        
    if active:
        fist_physics(delta)
    else:
        global_position = Vector2(-1000,-1000)


func make_active() -> void:
    active = true
    _Sprite.visible = true
    set_physics_process(true)
    
func make_inactive() -> void:
    active = false
    _Sprite.visible = false
    set_physics_process(false)


func fist_physics(delta):
    var mouse_position = get_global_mouse_position()
    
    # Use physics-based movement with linear_velocity instead of direct position setting
    var direction_to_mouse = (mouse_position - global_position)
    var distance_to_mouse = direction_to_mouse.length()
    
    # Apply velocity to move toward mouse (this maintains physics interactions)
    if distance_to_mouse > leeway_radius:
        linear_velocity = direction_to_mouse.normalized() * follow_Speed
    else:
        linear_velocity = Vector2.ZERO
    
    # Calculate distance between current and previous mouse position
    var mouse_movement_distance = previous_mouse_position.distance_to(mouse_position)
    
    # Only update rotation if mouse has moved beyond the leeway radius
    if mouse_movement_distance > leeway_radius:
        var direction = (mouse_position - previous_mouse_position).normalized()
        last_rotation = direction.angle() + PI/2
        previous_mouse_position = mouse_position
    
    # Apply the rotation (either updated or last stored value)
    rotation = last_rotation