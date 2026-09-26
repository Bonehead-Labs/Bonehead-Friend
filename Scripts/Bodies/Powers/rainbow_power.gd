class_name RainbowPower
extends SpellPower

## The rainbow (D72): press on him, drag to where he should land, and let go. A rainbow arcs
## from him over to the desk under that spot, and he slides down it — up over the top and down
## the far side, slowing as he arrives so he steps off it rather than falling.
##
## The ride is the kind act: it pays through `kindness_given` the moment the rainbow is drawn,
## which is also the player arriving as far as his idle brain is concerned. He rides it on the
## world layer alone — through the props, not into them — so a kind power can never ram him
## into a bat and bill the bat, and the arc is kept inside the play area so it can never put
## him into a wall. It ends on the desk under the cursor, not at the cursor, because a ride that
## ended in mid-air would drop him, and a fall of more than 128 px is billed as damage.

## The ride, as a kind act.
@export var ride_value: float = 14.0
## Shorter than this and there is no rainbow; longer and it is cut to this.
@export var min_span: float = 90.0
@export var max_span: float = 900.0
## His speed along the arc, and the bounds on how long a ride takes.
@export var ride_speed: float = 520.0
@export var min_ride: float = 0.7
@export var max_ride: float = 2.4
## How high the arc stands, as a share of how far it goes, plus a fixed rise.
@export var arch: float = 0.45
@export var rise: float = 50.0
## Seconds between rainbows, before "Quicker Arcs".
@export var recast_seconds: float = 1.5
@export var reach_padding: float = 20.0

const BAND_COLOURS: Array[Color] = [Color("ff4d2e"), Color("ff8c1a"), Color("ffc247"),
	Color("7ee07e"), Color("5ab8ff"), Color("b58cff")]
const BAND_WIDTH := 5.0
const SAMPLES := 28
const LAYER_WORLD := 1

const RESTING := 0
const DRAWING := 1
const RIDING := 2
const FADING := 3

var _phase := RESTING
var _start := Vector2.ZERO
var _end := Vector2.ZERO
var _control := Vector2.ZERO
var _t := 0.0
var _ride_seconds := 1.0
var _started_msec := 0
var _recast_msec := 0
var _saved_mask := 0
var _saved_layer := 0
var _rider: Buddy
var _bands: Array[Line2D] = []
var _preview: Line2D
var _stars: GPUParticles2D

func is_live() -> bool:
	return _phase == RIDING or _phase == FADING

func is_riding() -> bool:
	return _phase == RIDING

func can_fire_at(at: Vector2) -> bool:
	return (_phase == RESTING or _phase == FADING) and _reachable(_buddy()) \
		and _on_him(at, reach_padding)

func fire(at: Vector2) -> void:
	var buddy := _buddy()
	if buddy == null:
		return
	if Time.get_ticks_msec() < _recast_msec:
		_fizzle(at, WorldFX.kind_colour(0))
		return
	_build()
	if _phase == FADING:
		_hide_bands()
	_phase = DRAWING
	_held = true
	_start = buddy.global_position
	_moved(at)
	_update_input()

func _moved(at: Vector2) -> void:
	if _phase != DRAWING:
		return
	var buddy := _buddy()
	if buddy == null:
		return
	var end := _landing(buddy, at)
	var control := _apex(_start, end)
	var points := PackedVector2Array()
	for i in SAMPLES + 1:
		points.append(_bezier(_start, control, end, float(i) / float(SAMPLES)).round())
	_preview.points = points
	_preview.visible = _start.distance_to(end) >= min_span

func _released(at: Vector2) -> void:
	if _phase != DRAWING:
		return
	_preview.visible = false
	var buddy := _buddy()
	if not _reachable(buddy):
		_phase = RESTING
		_update_input()
		return
	_end = _landing(buddy, at)
	if _start.distance_to(_end) < min_span:
		var fx := _fx()
		if fx:
			fx.puff(_end, 4, WorldFX.kind_colour(0), 40.0, 0.4)
		_phase = RESTING
		_update_input()
		return
	_ride(buddy)

func _spell_deactivated(_was_held: bool) -> void:
	# A rainbow half-drawn goes; one he is on, he finishes.
	if _phase == DRAWING:
		_preview.visible = false
		_phase = RESTING

## Alt-tab mid-draw is not a cast: the half-drawn rainbow goes, and nothing is paid.
func _hold_lost() -> void:
	_spell_deactivated(true)

func _exit_tree() -> void:
	if _phase == RIDING and is_instance_valid(_rider):
		_rider.collision_mask = _saved_mask
		_rider.collision_layer = _saved_layer

## Where he steps off: the desk under the cursor, inside the play area, no further from him than
## `max_span`. Found by a ray down the world layer, so a shelf or a lid would count; at worst it is
## the floor.
func _landing(buddy: Buddy, at: Vector2) -> Vector2:
	var view := get_viewport().get_visible_rect()
	var rect := buddy.get_interaction_rect()
	var half := rect.size.x * 0.5 + 8.0
	var x := clampf(at.x, view.position.x + half, view.end.x - half)
	var reach := x - _start.x
	if absf(reach) > max_span:
		x = _start.x + signf(reach) * max_span
	var ground := view.end.y
	var space := get_world_2d().direct_space_state
	if space:
		var ray := PhysicsRayQueryParameters2D.create(Vector2(x, minf(at.y, view.end.y - 4.0)),
			Vector2(x, view.end.y + 400.0), LAYER_WORLD)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			ground = (hit["position"] as Vector2).y
	# From his feet to his origin, so it is his feet that land on the ground.
	var lift := rect.end.y - buddy.global_position.y
	return Vector2(x, ground - lift - 2.0)

## The top of the arc, kept under the top of the play area with room for his head.
func _apex(from: Vector2, to: Vector2) -> Vector2:
	var view := get_viewport().get_visible_rect()
	var mid := from.lerp(to, 0.5)
	var y := minf(from.y, to.y) - (arch * from.distance_to(to) + rise)
	# A quadratic's peak is halfway to its control point, so the control may sit above the view.
	var highest := view.position.y + 70.0
	var peak := 0.5 * mid.y + 0.5 * y
	if peak < highest:
		y = 2.0 * highest - mid.y
	return Vector2(mid.x, y)

static func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)

func _ride(buddy: Buddy) -> void:
	_phase = RIDING
	_rider = buddy
	_start = buddy.global_position
	_control = _apex(_start, _end)
	var length := 0.0
	var last := _start
	for i in range(1, SAMPLES + 1):
		var p := _bezier(_start, _control, _end, float(i) / float(SAMPLES))
		length += last.distance_to(p)
		last = p
	_ride_seconds = clampf(length / ride_speed, min_ride, max_ride)
	_t = 0.0
	_started_msec = Time.get_ticks_msec()
	_recast_msec = _started_msec + int(recast_seconds * Progression.get_modifier(item_id, &"cooldown_mult") * 1000.0)
	# Out of every layer and scanning only the world: a contact happens when either body scans
	# the other, so leaving his own layer is what stops a prop running into him on the way.
	_saved_mask = buddy.collision_mask
	_saved_layer = buddy.collision_layer
	buddy.collision_mask = LAYER_WORLD
	buddy.collision_layer = 0
	_draw_bands(0.0)
	EventBus.kindness_given.emit(item_id, ride_value * effective_damage_mult(), buddy.global_position)
	_notice_player()
	_face(&"rainbow_ride")
	AudioManager.play(&"rainbow", 0.0, -6.0)
	_use()
	if _stars:
		_stars.global_position = buddy.global_position
	_emitting(_stars, true)
	set_physics_process(true)
	_update_input()

## When the next rainbow can be drawn, for the suite.
func recast_msec() -> int:
	return _recast_msec

func _physics_process(delta: float) -> void:
	var elapsed := float(Time.get_ticks_msec() - _started_msec) / 1000.0
	if _phase == FADING:
		var left := 1.0 - elapsed / 0.5
		if left <= 0.0:
			_hide_bands()
			_phase = RESTING
			set_physics_process(false)
			_update_input()
			return
		for band in _bands:
			band.width = maxf(1.0, roundf(BAND_WIDTH * left))
		return
	if _phase != RIDING:
		set_physics_process(false)
		_update_input()
		return
	var buddy := _rider
	if not is_instance_valid(buddy) or not _reachable(buddy) or buddy.freeze:
		_finish(false)
		return
	_draw_bands(minf(1.0, elapsed / 0.3))
	_t = minf(1.0, _t + delta / _ride_seconds)
	# Eased at both ends: he tips over the start, runs down the far side, and slows to a step.
	var s := _t * _t * (3.0 - 2.0 * _t)
	var target := _bezier(_start, _control, _end, s)
	var want := ((target - buddy.global_position) / maxf(delta, 0.001)).limit_length(1600.0)
	_steer(buddy, want, 60000.0, delta)
	_upright(buddy, 8.0)
	if _stars:
		_stars.global_position = buddy.global_position
	if _t >= 1.0:
		_finish(true)

func _finish(arrived: bool) -> void:
	var buddy := _rider
	_rider = null
	_phase = FADING
	_started_msec = Time.get_ticks_msec()
	_emitting(_stars, false)
	if not is_instance_valid(buddy):
		return
	buddy.collision_mask = _saved_mask
	buddy.collision_layer = _saved_layer
	if not arrived:
		return
	# Stepped off, not dropped: whatever speed the last step of the ride left him is taken away.
	buddy.apply_central_impulse(-buddy.linear_velocity * buddy.mass * 0.8)
	var fx := _fx()
	if fx:
		fx.burst(buddy.global_position, &"star", WorldFX.GOLD, 8 + 2 * _tier(), 160.0, 0.7)
	_face(&"rainbow_landed")

func _draw_bands(reveal: float) -> void:
	var count := maxi(2, int(ceil(float(SAMPLES) * reveal)) + 1)
	var centre := PackedVector2Array()
	var normals := PackedVector2Array()
	for i in SAMPLES + 1:
		var t := float(i) / float(SAMPLES)
		centre.append(_bezier(_start, _control, _end, t))
		var ahead := _bezier(_start, _control, _end, minf(1.0, t + 0.02))
		var behind := _bezier(_start, _control, _end, maxf(0.0, t - 0.02))
		normals.append((ahead - behind).orthogonal().normalized())
	# The arc runs under him: the bands sit below the path of his centre, so he rides on top.
	var drop := _rider.get_interaction_rect().end.y - _rider.global_position.y if is_instance_valid(_rider) else 50.0
	for b in _bands.size():
		var points := PackedVector2Array()
		var offset := drop + BAND_WIDTH * (float(b) - float(_bands.size() - 1) * 0.5) + 14.0
		for i in mini(count, SAMPLES + 1):
			var n := normals[i]
			if n.y < 0.0:
				n = -n
			points.append((centre[i] + n * offset).round())
		_bands[b].points = points
		_bands[b].width = BAND_WIDTH
		_bands[b].visible = true

func _hide_bands() -> void:
	for band in _bands:
		band.visible = false

func _build() -> void:
	if not _bands.is_empty():
		return
	for i in BAND_COLOURS.size():
		var band := Line2D.new()
		band.name = "Band%d" % i
		band.default_color = BAND_COLOURS[i]
		band.antialiased = false
		band.joint_mode = Line2D.LINE_JOINT_ROUND
		band.z_index = -1
		band.visible = false
		add_child(band)
		_bands.append(band)
	_preview = Line2D.new()
	_preview.name = "Preview"
	_preview.default_color = HOLY
	_preview.width = 2.0
	_preview.antialiased = false
	_preview.z_index = 34
	_preview.visible = false
	add_child(_preview)
	_stars = _emitter("RideStars", UIStyle.glyph(&"star"), WorldFX.GOLD, 8, 0.7, 120.0, 40.0,
		Vector2(10, 10), 0.5, 0.9, true)
