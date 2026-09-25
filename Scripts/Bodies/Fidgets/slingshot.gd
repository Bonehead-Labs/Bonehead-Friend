class_name Slingshot
extends WeaponBase

## A slingshot (D66, the stretch D56 left). A gun you aim yourself: filed under Guns, bought
## with Bones, and the one gun in the drawer that does not point itself at him.
##
## - **Left holds the Y.** It hangs fork-up from the crotch, where the hand is.
## - **Hold right while holding it** and the frame plants where it is, stood upright; the pouch
##   is now the cursor, and pulling it back stretches the bands from the prong tips. A dotted
##   line shows where the shot will go.
## - **Let go of right and it fires** a pellet from the fork, away from the pouch, as fast as
##   the draw was long. The pellet is a real body: it falls, it bounces off the desk, and it
##   pays Bones when it hits him — by how hard it was drawn, the way a gun's shot does (D7).
## - **He sees it drawn at him** and cowers, the held gun's `aim` threat (D56), for as long as
##   the dotted line runs through him.
##
## A pellet bills itself, once, on the frame it reaches him: it collides with the world and
## nothing else, and sweeps the segment it flew each step for him. A fast pellet bouncing off
## him is exactly the contact D59's F1 never bills, and a pellet that hit the desk after him
## must not count twice.
##
## Nothing runs a frame at rest beyond the base class's own. The pellets free themselves when
## they come to rest or time out, and the slingshot frees any still flying when it is binned.

@export var gestures: GestureZones
## The bands and pouch at rest, hidden while it is drawn.
@export var rest_bands: Sprite2D
## The pouch the cursor pulls, shown while it is drawn.
@export var pouch: Sprite2D
@export var pellet_texture: Texture2D
## Body-local world px, with the frame upright: the two band knots and where a shot leaves.
@export var prong_left: Vector2 = Vector2(-10, -20)
@export var prong_right: Vector2 = Vector2(10, -20)
@export var fork: Vector2 = Vector2(0, -14)
## The furthest back the pouch goes, world px, and the pellet's speed at none and all of it.
@export var max_draw: float = 110.0
@export var min_speed: float = 420.0
@export var max_speed: float = 1500.0
## The impulse a pellet from a full draw hands him — and so its damage (D7). A pellet is billed
## at the slingshot's own `damage_mult` (WeaponBase), augment included: one multiplier for the
## thing, whether the pellet or the frame is what reached him, so a hit always carries the
## number the data says it does (item_check asserts exactly that of every hit).
@export var shot_force: float = 1700.0
## How much of the shot is also a shove.
@export var shove: float = 0.35
## A new pellet is in the pouch this long after a shot, before the "time between uses" node.
@export var reload_seconds: float = 0.6

## Less of a draw than this fires nothing: the bands just snap.
const MIN_SHARE := 0.15
## The dotted line: a dot every this long along the flight, and this many at most.
const DOT_SECONDS := 0.045
const DOTS := 18
## The collision layers a pellet sweeps for him on (buddy only), and what it bounces off.
const BUDDY_LAYER := 2
const WORLD_LAYER := 1
## He knows it is drawn at him if the path passes this near his middle.
const THREAT_REACH := 48.0
const THREAT_REFRESH_MSEC := 500
const BAND_COLOUR := Color("e8862c")
const DOT_COLOUR := Color("fcfcee")

var _drawing := false
var _pouch_at := Vector2.ZERO
var _loaded_msec := 0
var _bands: Array[Line2D] = []
var _dots: Dots
var _pellets: Array[WeakRef] = []
var _threatening := false
var _threat_refresh_msec := 0
var _buddy: Buddy

## Shots fired, for the suite. Never read by the simulation.
var shots_fired := 0

func _ready() -> void:
	super._ready()
	if gestures:
		gestures.gesture.connect(_on_gesture)
	if pouch:
		pouch.top_level = true
		pouch.visible = false

func is_drawn() -> bool:
	return _drawing

func is_loaded() -> bool:
	return Time.get_ticks_msec() >= _loaded_msec

## Where the pouch is in the world, while drawn.
func pouch_position() -> Vector2:
	return _pouch_at

func fork_position() -> Vector2:
	return to_global(fork)

## The dots the preview is showing, in the world.
func preview_points() -> PackedVector2Array:
	return _dots.points if _dots else PackedVector2Array()

# --- the hand ------------------------------------------------------------------

func _on_gesture(g: GestureZones.Gesture) -> void:
	match g.kind:
		GestureZones.ACTION:
			draw_back(g.world)
		GestureZones.CARRY:
			if _drawing:
				_pull_to(g.world)
		GestureZones.ACTION_END:
			loose()

## Plants the frame upright where it is and puts the pouch in the hand.
func draw_back(at: Vector2) -> void:
	if not dragging or _drawing:
		return
	_drawing = true
	freeze = true
	global_rotation = 0.0
	if rest_bands:
		rest_bands.visible = false
	_build_bands()
	for band in _bands:
		band.visible = true
	if pouch:
		pouch.visible = true
	if _dots:
		_dots.visible = true
	AudioManager.play(&"squeak", 0.05, -18.0, 0.55)
	_pull_to(at)

func _pull_to(at: Vector2) -> void:
	var from := fork_position()
	_pouch_at = from + (at - from).limit_length(max_draw)
	_update_bands()
	_update_preview()

## Right comes up: the pellet goes, if there is one and the draw was a draw.
func loose() -> void:
	if not _drawing:
		return
	_drawing = false
	var from := fork_position()
	var pull := from - _pouch_at
	var share := clampf(pull.length() / maxf(max_draw, 1.0), 0.0, 1.0)
	freeze = false
	for band in _bands:
		band.visible = false
	if pouch:
		pouch.visible = false
	if _dots:
		_dots.visible = false
		_dots.points = PackedVector2Array()
	if rest_bands:
		rest_bands.visible = true
	_set_threat(false)
	if share < MIN_SHARE or not is_loaded() or pull.length_squared() <= 0.0:
		AudioManager.play(&"twang", 0.05, -18.0, 1.6)
		return
	fire(pull.normalized() * lerpf(min_speed, max_speed, share), share)

## A pellet from the fork at `velocity`, worth `share` of a full shot.
func fire(velocity: Vector2, share: float) -> Pellet:
	var pellet := Pellet.new()
	pellet.name = "Pellet"
	pellet.source = item_id
	pellet.texture = pellet_texture
	pellet.force = shot_force * share
	pellet.mult = effective_damage_mult()
	pellet.shove = shove
	var host := get_parent() if get_parent() else self
	host.add_child(pellet)
	pellet.global_position = fork_position()
	pellet.linear_velocity = velocity
	_pellets.append(weakref(pellet))
	_loaded_msec = Time.get_ticks_msec() + int(_reload() * 1000.0)
	shots_fired += 1
	# A small kick back into the hand.
	apply_central_impulse(-velocity.normalized() * 60.0 * mass)
	AudioManager.play(&"twang", 0.06, lerpf(-12.0, -4.0, share), lerpf(1.2, 0.85, share))
	if item_id != &"":
		EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	return pellet

func _reload() -> float:
	var gap := reload_seconds
	if item_id != &"":
		gap *= Progression.get_modifier(item_id, &"cooldown_mult")
	return maxf(gap, 0.05)

## Let go of the frame mid-draw and it fires: there is no hand left to hold the bands.
func _end_drag() -> void:
	super._end_drag()
	if _drawing:
		loose()

func _exit_tree() -> void:
	_set_threat(false)
	# Pellets are the world's, not ours, so they outlive a binned slingshot unless told.
	for ref in _pellets:
		var pellet := ref.get_ref() as Node
		if pellet and is_instance_valid(pellet):
			pellet.queue_free()
	_pellets.clear()

# --- the bands and the dotted line ---------------------------------------------

func _build_bands() -> void:
	if not _bands.is_empty():
		return
	for i in 2:
		var band := Line2D.new()
		band.name = "Band%d" % i
		# World space: the pouch is at the cursor, not on the frame.
		band.top_level = true
		band.width = 2.0
		band.default_color = BAND_COLOUR
		band.antialiased = false
		band.z_index = 1
		add_child(band)
		_bands.append(band)
	_dots = Dots.new()
	_dots.name = "Preview"
	_dots.top_level = true
	_dots.z_index = 30
	_dots.colour = DOT_COLOUR
	add_child(_dots)
	if pouch:
		pouch.z_index = 2

func _update_bands() -> void:
	var knots := [to_global(prong_left), to_global(prong_right)]
	for i in _bands.size():
		var band := _bands[i]
		band.clear_points()
		band.add_point((knots[i] as Vector2).round())
		band.add_point(_pouch_at.round())
	if pouch:
		pouch.global_position = _pouch_at.round()
		var along := fork_position() - _pouch_at
		pouch.global_rotation = along.angle() + PI * 0.5 if along.length_squared() > 1.0 else 0.0

## Where the shot will go, as a dotted arc: the same launch `loose` would give it, under the
## same gravity, until it leaves the window.
func _update_preview() -> void:
	if _dots == null:
		return
	var from := fork_position()
	var pull := from - _pouch_at
	var share := clampf(pull.length() / maxf(max_draw, 1.0), 0.0, 1.0)
	var points := PackedVector2Array()
	if share >= MIN_SHARE and pull.length_squared() > 0.0:
		var v := pull.normalized() * lerpf(min_speed, max_speed, share)
		var g := Vector2(0.0, float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)))
		var view := get_viewport_rect().grow(40.0)
		for i in range(1, DOTS + 1):
			var t := DOT_SECONDS * float(i)
			var p := from + v * t + g * (0.5 * t * t)
			if not view.has_point(p):
				break
			points.append(p)
	_dots.points = points
	_dots.queue_redraw()
	_set_threat(_passes_him(points))

func _passes_him(points: PackedVector2Array) -> bool:
	if not is_instance_valid(_buddy):
		_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	if _buddy == null:
		return false
	var middle := _buddy.global_transform * _buddy.center_of_mass
	for p in points:
		if p.distance_to(middle) <= THREAT_REACH:
			return true
	return false

## He knows it is drawn at him (D56's `aim`): edges and a half-second refresh, never per frame.
func _set_threat(on: bool) -> void:
	var now := Time.get_ticks_msec()
	if on == _threatening and (not on or now < _threat_refresh_msec):
		return
	_threatening = on
	_threat_refresh_msec = now + THREAT_REFRESH_MSEC
	if is_inside_tree():
		EventBus.threat_changed.emit(&"aim", global_position, 1.0 if on else 0.0)

func is_threatening() -> bool:
	return _threatening

## The dotted line. Two-pixel squares, so it reads as dots at 1x and not as a smear.
class Dots extends Node2D:
	var points := PackedVector2Array()
	var colour := Color.WHITE

	func _draw() -> void:
		for p in points:
			draw_rect(Rect2(p.round() - Vector2(2, 2), Vector2(4, 4)), Color.BLACK)
			draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(2, 2)), colour)

## One pellet. It collides with the world only — walls and the desk — and looks for him along
## the segment it flew each step, so it hits him exactly once whatever its speed.
class Pellet extends RigidBody2D:
	const LIFETIME := 3.0
	const REST_SECONDS := 0.6
	const RADIUS := 4.0

	var source: StringName = &""
	var mult := 1.0
	var force := 1000.0
	var shove := 0.35
	var texture: Texture2D
	var spent := false
	var _age := 0.0
	var _still := 0.0
	var _last := Vector2.INF

	func _ready() -> void:
		collision_layer = 0
		collision_mask = Slingshot.WORLD_LAYER
		mass = 0.08
		continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		var material := PhysicsMaterial.new()
		material.bounce = 0.35
		material.friction = 0.7
		physics_material_override = material
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = RADIUS
		shape.shape = circle
		add_child(shape)
		var picture := Sprite2D.new()
		picture.name = "Sprite"
		picture.texture = texture
		picture.scale = Vector2(2, 2)
		add_child(picture)

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		var here := global_position
		if not spent and _last != Vector2.INF:
			_sweep(_last, here)
		_last = here
		if linear_velocity.length() < 25.0:
			_still += delta
			if _still >= REST_SECONDS:
				queue_free()
		else:
			_still = 0.0

	func _sweep(from: Vector2, to: Vector2) -> void:
		if from.is_equal_approx(to):
			return
		var query := PhysicsRayQueryParameters2D.create(from, to, Slingshot.BUDDY_LAYER)
		query.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		var him := hit.get("collider") as Buddy
		if him == null:
			return
		spent = true
		var at: Vector2 = hit.get("position", to)
		var heading := linear_velocity.normalized()
		him.apply_central_impulse(heading * force * shove)
		him.take_impulse(force, source, mult, at)
		var fx := WorldFX.of(self)
		if fx:
			fx.shot(at, false, 0)
		# Off him, most of its speed spent.
		global_position = at - heading * RADIUS
		linear_velocity = -heading * linear_velocity.length() * 0.25
