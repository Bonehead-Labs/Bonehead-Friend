class_name FlattenAbility
extends SustainAbility

## The rolling pin goes down on the desk and rolls over him (D74): Flatten.
##
## Hold right and the pin lays itself down — a torque about the grip that holds it level, pointing
## at him, the held gun's PD scaled by the inertia about the grip (D56) — and the hand drops so
## it rides on the desk (`BaseDraggable.hand_offset`, the ground pound's mechanism): it rolls
## where you steer it, a puff of flour off the desk as it goes. For as long as it is down he and
## the pin do not collide, so it goes *over* him rather than shoving him along, and while it is
## over him the hand rides up on top of him.
##
## **A pass flattens him.** Each time the pin's barrel crosses his middle, rolling, he is squashed
## flat — a code motion on his sprite through `BuddyArt`'s accumulators (`flatten`, his
## `flattened` row), never a tween on his body — and billed once: `roll_force` scaled by how fast
## it was rolling (0.6x to 1.4x of `roll_speed`), through `Buddy.take_impulse` at the pin's
## multiplier times `flatten_mult` (D7). Back and forth over him is a pass each way, no faster than
## `pass_gap`. He springs back up with a boing.
##
## The chainsaw's Rev is the other sustain: that one holds still and grinds. This one moves.
##
## Row: `fuel_seconds`, `lay_frequency`, `lay_accel`, `ride_px`, `over_px`, `reach`, `roll_force`,
## `roll_speed`, `flatten_mult`, `pass_gap`, `shove`.

const ROLLING := 0
const SETTLE := 1

var _phase := ROLLING
var _offset := Vector2.ZERO
var _floor_y := INF
var _gravity_accel := 980.0
var _side_was := 0.0
var _since_pass := 99.0
var _excepted: Buddy
var _flour: GPUParticles2D
var _rumble := 0.0
var _last_com := Vector2.INF
## Which way it lies, chosen once as it goes down — at him — and kept: a pin that turned to face
## him every time it crossed him would spin end over end at the moment it should be rolling.
var _lay_side := 1.0

## For the suites: passes over him, the last one's speed and impulse, and how level it lay.
var passes := 0
var last_roll_speed := 0.0
var last_flatten := 0.0
var level_error := 0.0

func _ready() -> void:
	super._ready()
	_gravity_accel = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func is_rolling() -> bool:
	return _active and _phase == ROLLING

func _on_press() -> void:
	_t = 0.0
	_phase = ROLLING
	passes = 0
	last_roll_speed = 0.0
	last_flatten = 0.0
	_since_pass = 99.0
	_side_was = 0.0
	_rumble = 0.0
	_last_com = Vector2.INF
	_floor_y = _probe_floor(hand_world())
	var at := him_world()
	_lay_side = 1.0 if at == Vector2.INF or at.x >= grip_world().x else -1.0
	var him := buddy()
	if him:
		body.add_collision_exception_with(him)
		_excepted = him
	run(true)
	threaten(true)
	_flour = emitter("flour", &"chip", Color("f4f1e6"), 10, Vector2.ZERO, Vector2(0, -40), 160.0, 0.5,
		Vector2(0, 200))
	sound(&"whoosh", -12.0, 0.6)
	_update_pip()

func _on_release(_seconds: float) -> void:
	_lift()

func _on_tick(delta: float) -> void:
	_t += delta
	_since_pass += delta
	if _phase == SETTLE:
		# Let go on top of him: the exception stays until the pin is clear of him (D61).
		if not overlaps_him() or _t >= 1.0:
			finish()
		return
	_lay(delta)
	_press_down()
	_roll(delta)
	if _t >= num("fuel_seconds", 2.5):
		_lift()

## Holds the pin level, pointing the way it went down: at him.
func _lay(_delta: float) -> void:
	var grip := grip_world()
	var arm := com_world() - grip
	if arm.length_squared() < 1.0:
		return
	var target := Vector2(_lay_side, 0.0)
	var err := wrapf(target.angle() - arm.angle(), -PI, PI)
	level_error = absf(rad_to_deg(err))
	var inertia := pivot_inertia()
	var w := num("lay_frequency", 12.0)
	var pd := inertia * (w * w * err - 2.0 * 0.9 * w * body.angular_velocity)
	var cap := inertia * num("lay_accel", 300.0)
	var hold := -arm.x * body.mass * _gravity_accel * body.gravity_scale
	body.apply_torque(hold + clampf(pd, -cap, cap))

## The hand drops until the pin rides on the desk — or on top of him while it is over him.
func _press_down() -> void:
	var cursor := hand_world() - _offset
	var radius := num("ride_px", 16.0)
	var target_y := _floor_y - radius
	if _over_him():
		target_y -= num("over_px", 34.0)
	var want := Vector2(0.0, target_y - cursor.y) if _floor_y != INF else Vector2.ZERO
	# Never more than `reach` below the cursor: held high above the desk, it rolls on air.
	want.y = clampf(want.y, -num("reach", 240.0), num("reach", 240.0))
	_set_offset(_offset.lerp(want, 0.35))

## Rolling: flour off the desk, a rumble that climbs with speed, and a pass each time the barrel
## crosses his middle.
func _roll(_delta: float) -> void:
	var com := com_world()
	var speed := 0.0
	if _last_com != Vector2.INF:
		speed = absf(com.x - _last_com.x) * float(Engine.physics_ticks_per_second)
	_last_com = com
	var on_desk := _floor_y != INF and absf(com.y - (_floor_y - num("ride_px", 16.0))) < 28.0
	if _flour:
		_flour.position = body.to_local(com + Vector2(0, num("ride_px", 16.0)))
		emit_from(_flour, on_desk and speed > 80.0)
	_rumble -= _delta
	if speed > 80.0 and _rumble <= 0.0 and (on_desk or _over_him()):
		_rumble = clampf(0.14 - speed / 6000.0, 0.05, 0.14)
		sound(&"whirr", -12.0, 0.7 + clampf(speed / 900.0, 0.0, 0.8), 0.05)
	var him := buddy()
	if him == null:
		return
	var middle := him.get_interaction_rect().get_center().x
	var side := signf(com.x - middle)
	if _side_was != 0.0 and side != 0.0 and side != _side_was and _low_enough(him) \
			and speed >= 60.0 and _since_pass >= num("pass_gap", 0.35):
		_flatten(him, speed, -side)
	if side != 0.0:
		_side_was = side

## Low enough to be rolling over him, not waved above his head.
func _low_enough(him: Buddy) -> bool:
	var rect := him.get_interaction_rect()
	return com_world().y >= rect.position.y - 10.0

func _over_him() -> bool:
	var him := buddy()
	if him == null:
		return false
	var rect := him.get_interaction_rect().grow_individual(12.0, 0.0, 12.0, 0.0)
	var com := com_world()
	return com.x >= rect.position.x and com.x <= rect.end.x

func _flatten(him: Buddy, speed: float, direction: float) -> void:
	passes += 1
	_since_pass = 0.0
	last_roll_speed = speed
	var share := clampf(speed / maxf(num("roll_speed", 450.0), 1.0), 0.6, 1.4)
	last_flatten = num("roll_force", 1500.0) * share
	var rect := him.get_interaction_rect()
	var at := Vector2(rect.get_center().x, rect.end.y - 10.0)
	strike(last_flatten, Vector2(direction, 0.0), at, num("flatten_mult", 1.5), num("shove", 0.1))
	grinds += 1
	paid_off.emit(&"flatten")
	var fx := fx()
	if fx:
		fx.puff(Vector2(rect.position.x, rect.end.y), 5, Color("f4f1e6"), 90.0, 0.5)
		fx.puff(Vector2(rect.end.x, rect.end.y), 5, Color("f4f1e6"), 90.0, 0.5)
		fx.chips(at, Color("f2ead8"), 6, 200.0)
		fx.shake(3.0)
	sound(&"squish", -2.0, 1.0)
	tell(&"flattened", at)
	# He springs back up at the end of his row, a boing to go with it. Only a sound on a timer:
	# nothing here touches him after the pass.
	if is_inside_tree():
		get_tree().create_timer(0.8).timeout.connect(_boing)

func _boing() -> void:
	sound(&"boing", -8.0, 1.1)

## Up off the desk: the hand is its own again, and the exception comes off once the pin is clear.
func _lift() -> void:
	_set_offset(Vector2.ZERO)
	emit_from(_flour, false)
	threaten(false)
	_phase = SETTLE
	_t = 0.0

func _set_offset(offset: Vector2) -> void:
	var delta := offset - _offset
	_offset = offset
	body.hand_offset = offset
	if body.dragging and body.handle:
		body.handle.global_position += delta

func _probe_floor(from: Vector2) -> float:
	if not body.is_inside_tree():
		return INF
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2.DOWN * 900.0, WORLD_LAYER,
		[body.get_rid()])
	query.hit_from_inside = true
	var hit := body.get_world_2d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector2).y if hit.has("position") else INF

func _on_dropped() -> void:
	_set_offset(Vector2.ZERO)
	if _phase != SETTLE:
		_phase = SETTLE
		_t = 0.0

func _on_stop() -> void:
	emit_from(_flour, false)
	_offset = Vector2.ZERO
	if body:
		body.hand_offset = Vector2.ZERO
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null
	_rev = 0.0

func pip_fill() -> float:
	if not _active or _phase != ROLLING:
		return -1.0
	return clampf(1.0 - _t / maxf(num("fuel_seconds", 2.5), 0.01), 0.0, 1.0)
