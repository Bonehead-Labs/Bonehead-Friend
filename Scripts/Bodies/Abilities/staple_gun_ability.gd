class_name StapleGunAbility
extends ProjectileAbility

## Hold right and the stapler staples him, `rate` a second, dead straight (D74): Staple Gun.
##
## The one melee ability you hold down to keep firing. Each staple leaves the stapler's mouth —
## whichever end of it is nearer him — at `staple_speed` with no gravity, straight at his middle,
## with a chunk and a jolt of the stapler's head. A strip holds `strip` staples; the pip is the
## strip running down, and letting go keeps what is left for the next press after a short gap.
## The strip running out is the reload: the row's cooldown, and a full strip after it.
##
## Each staple is an `AbilityShot` that bills itself once — `staple_force` at the stapler's
## multiplier times `staple_mult` — and one that lands on him **stays in him** for a few seconds,
## drawn on him (`StapleMarks`, a child of his that rides and turns with him and is taken off when
## the stapler goes), so a strip emptied into him leaves him looking like a notice board.
##
## Row: `rate`, `strip`, `staple_speed`, `staple_force`, `staple_mult`, `shove`, `pause`.

var _left := -1
var _next_shot := 0.0
var _shots: Array[WeakRef] = []
var _marks: StapleMarks
var _sprite_rest := Vector2.INF
var _chomp := 0.0

## For the suites: staples fired and landed this press.
var fired := 0
var landed := 0

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot):
			shot.queue_free()
	_shots.clear()
	if is_instance_valid(_marks):
		_marks.queue_free()
	_marks = null

func strip_left() -> int:
	return _left if _left >= 0 else int(num("strip", 20))

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(float(strip_left()) / maxf(num("strip", 20), 1.0), 0.0, 1.0)

func is_firing() -> bool:
	return _active

func _on_press() -> void:
	if _left < 0:
		_left = int(num("strip", 20))
	fired = 0
	landed = 0
	_next_shot = 0.0
	run(true)
	threaten(true)
	_update_pip()

func _on_release(_seconds: float) -> void:
	_stop_firing()

func _on_dropped() -> void:
	_stop_firing()

func _on_tick(delta: float) -> void:
	_next_shot -= delta
	if _chomp > 0.0:
		_chomp -= delta
		if _chomp <= 0.0:
			_rest_sprite()
	if _next_shot <= 0.0:
		_next_shot += 1.0 / maxf(num("rate", 5.0), 0.5)
		_fire()

func _fire() -> void:
	if strip_left() <= 0:
		_stop_firing()
		return
	var him := him_world()
	if him == Vector2.INF:
		_stop_firing()
		return
	var mouth := _mouth()
	# Straight, but not all through one hole: each at a point of his chest a little off the last.
	var scatter := Vector2(randf_range(-10.0, 10.0), randf_range(-26.0, 18.0))
	var aim := (him + scatter - mouth).normalized()
	var shot := AbilityShot.new()
	shot.name = "Staple"
	shot.look = AbilityShot.STAPLE
	shot.ability = weakref(self)
	shot.force = num("staple_force", 420.0)
	shot.mult = num("staple_mult", 1.0)
	shot.shove = num("shove", 0.15)
	shot.gravity_scale = 0.0
	shot.mass = 0.02
	shot.lifetime = 1.2
	shot.after_hit = AbilityShot.SPLAT
	shot.after_world = AbilityShot.STICK
	var host := body.get_parent() if body.get_parent() else body
	host.add_child(shot)
	shot.global_position = mouth
	shot.linear_velocity = aim * num("staple_speed", 1400.0)
	_shots.append(weakref(shot))
	_left -= 1
	fired += 1
	# The head snaps down: a kick on the body away from him, and the picture jolts a pixel.
	body.apply_central_impulse(-aim * body.mass * 40.0)
	_chomp_sprite()
	var fx := fx()
	if fx:
		fx.chips(mouth, AbilityShot.STEEL, 1, 120.0)
	sound(&"staple", -6.0, 1.0 + 0.02 * float(fired % 4), 0.06)
	_update_pip()
	if _left <= 0:
		# Empty: a dry click, and the reload is the cooldown.
		sound(&"tock", -10.0, 2.2)
		_left = -1
		finish()

## Let go with staples left: they stay in the strip, and the next press is a short gap away.
func _stop_firing() -> void:
	if not _active:
		return
	if _left > 0:
		finish(num("pause", 0.4))
	else:
		_left = -1
		finish()

func _on_stop() -> void:
	_rest_sprite()

## The end of the stapler nearer him: its mouth, as far as a staple is concerned.
func _mouth() -> Vector2:
	var s := sprite()
	var reach := 28.0
	if body.collider and body.collider.shape:
		reach = body.collider.shape.get_rect().size.x * 0.5
	var a := body.to_global(Vector2(reach, 4.0))
	var b := body.to_global(Vector2(-reach, 4.0))
	var him := him_world()
	if him == Vector2.INF or s == null:
		return a
	return a if a.distance_squared_to(him) <= b.distance_squared_to(him) else b

func shot_hit(shot: AbilityShot, him: Buddy, at: Vector2, heading: Vector2) -> void:
	if him == null or body == null:
		return
	strike(shot.force, heading, at, shot.mult, shot.shove)
	landed += 1
	if landed == 1:
		paid_off.emit(&"staple")
	# The strip counted into him on the badge over him (D77).
	show_state(&"stapled")
	if not is_instance_valid(_marks):
		_marks = StapleMarks.new()
		_marks.name = "StapleMarks"
		_marks.z_index = 2
		him.add_child(_marks)
	# Driven in: the mark sits a staple's length inside his outline, on the bone, not in the air
	# beside it where his collider's box ends.
	_marks.add(him.to_local(at + heading * 12.0), heading.angle() - him.global_rotation)
	var fx := fx()
	if fx:
		fx.chips(at, Color("f2ead8"), 2, 150.0)
	sound(&"tock", -12.0, 1.7)

func shot_landed(_shot: AbilityShot, at: Vector2) -> void:
	var fx := fx()
	if fx:
		fx.chips(at, AbilityShot.STEEL, 1, 80.0)

func _chomp_sprite() -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_rest == Vector2.INF:
		_sprite_rest = s.position
	s.position = _sprite_rest + Vector2(0, 2) * Settings.intensity_scale()
	_chomp = 0.05

func _rest_sprite() -> void:
	var s := sprite()
	if s and _sprite_rest != Vector2.INF:
		s.position = _sprite_rest
	_sprite_rest = Vector2.INF
	_chomp = 0.0

## The staples in him: up to `MOST`, each where it went in and at the angle it went in, fading
## after a few seconds. His child, so it moves and turns with him; frees itself when empty.
class StapleMarks extends Node2D:
	const MOST := 12
	const STAY := 3.0
	var _marks: Array = []

	func add(local: Vector2, angle: float) -> void:
		_marks.append([local.round(), angle, 0.0])
		while _marks.size() > MOST:
			_marks.pop_front()
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		for mark in _marks:
			mark[2] = float(mark[2]) + delta
		while not _marks.is_empty() and float(_marks[0][2]) >= STAY:
			_marks.pop_front()
		if _marks.is_empty():
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		for mark in _marks:
			draw_set_transform(mark[0], mark[1])
			draw_rect(Rect2(-3, -5, 5, 10), AbilityShot.OUTLINE)
			draw_rect(Rect2(-2, -4, 3, 2), AbilityShot.STEEL)
			draw_rect(Rect2(-2, 2, 3, 2), AbilityShot.STEEL)
			draw_rect(Rect2(0, -4, 1, 8), AbilityShot.STEEL)
		draw_set_transform(Vector2.ZERO, 0.0)
