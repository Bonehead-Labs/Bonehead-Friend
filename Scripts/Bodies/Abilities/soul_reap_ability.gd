class_name SoulReapAbility
extends ProjectileAbility

## The scythe's Soul Reap (D74, the blades): hold right and swing, and a **ghost of the blade**
## leaves it at the swing's speed and flies on along the swing — through anything, through him —
## and on its way through him it tugs his soul half out of him for a moment.
##
## Every other ranged ability aims itself: the golf ball's arc is solved for you, the boxcutter's
## tips go straight at him. This one goes **where you swung**. The player's swing is the aim and
## the throw both, so a scythe reaps at range only for someone who swings it at him.
##
## **Armed** while right is held, for at most `arm_seconds`: the blade goes pale and sheds wisps.
## The first tick the **hand** moves faster than `release_speed` px/s — a flick of the stroke — the
## ghost leaves the blade in the direction the hand is going, at the hand's speed times 1.2 held
## between `ghost_min` and `ghost_max`, turning as the scythe was turning. The hand, not the blade:
## a heavy head turning on the grip flings its point every which way, and the first ghosts flew up
## off a stroke aimed straight at him. A stroke that already points within `assist_degrees` of him
## is bent onto him — a forgiving aim, not an automatic one. Let go of right, or run out of time,
## before a stroke is fast enough, and it fizzles: half a cooldown.
##
## **The ghost bills itself, once** (the golf ball's rule): it touches nothing, sweeps the segment
## it flew each step for him, and the step it crosses him it hands over `reap_force` scaled by its
## speed (0.6x to 1.4x of `reap_speed`) through `Buddy.take_impulse` at the scythe's multiplier times
## `reap_mult`, with only `shove` of it as a shove — a soul is taken, not a skeleton thrown. It fades
## after `ghost_range` px.
##
## Row: `arm_seconds`, `release_speed`, `ghost_min`, `ghost_max`, `ghost_range`, `assist_degrees`,
## `reap_force`, `reap_speed`, `reap_mult`, `shove`.

const GHOST := Color("bff6ea")
const GHOST_DEEP := Color("5fd6c2")

var _t := 0.0
var _last_hand := Vector2.INF
var _hand_v := Vector2.ZERO
var _wisps: GPUParticles2D
var _glow_was := Color.WHITE
var _glowing := false

## For the suites: the ghost's speed and heading, whether it was bent onto him, and its reap.
var last_ghost_speed := 0.0
var last_heading := Vector2.ZERO
var assisted := false
var reaps := 0
var fizzled := false

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(1.0 - _t / maxf(num("arm_seconds", 2.0), 0.01), 0.0, 1.0)

func _can_start() -> bool:
	return true

func _on_press() -> void:
	_t = 0.0
	_last_hand = Vector2.INF
	_hand_v = Vector2.ZERO
	fizzled = false
	assisted = false
	last_ghost_speed = 0.0
	last_strike = 0.0
	run(true)
	threaten(true)
	_wisps = emitter("wisps", &"ecto", GHOST, 8, body._find_tip(), Vector2(0, -30), 180.0, 0.6,
		Vector2(0, -40))
	emit_from(_wisps, true)
	var s := sprite()
	if s:
		_glow_was = s.self_modulate
		s.self_modulate = _glow_was.lerp(GHOST, 0.45)
		_glowing = true
	sound(&"wail", -18.0, 1.6, 0.0)
	_update_pip()

func _on_tick(delta: float) -> void:
	_t += delta
	var hand := hand_world()
	if _last_hand != Vector2.INF and delta > 0.0:
		# Lightly smoothed, so one jittery frame is not a flick.
		_hand_v = _hand_v.lerp((hand - _last_hand) / delta, 0.6)
	_last_hand = hand
	if _hand_v.length() >= num("release_speed", 600.0):
		_reap(tip_world(), _hand_v)
		return
	if _t >= num("arm_seconds", 2.0):
		_fizzle()

func _on_release(_seconds: float) -> void:
	if _active:
		_fizzle()

func _on_dropped() -> void:
	_fizzle()

func _fizzle() -> void:
	fizzled = true
	var fx := fx()
	if fx:
		fx.puff(tip_world(), 5, GHOST, 40.0, 0.6)
	finish(num("cooldown", 4.0) * 0.5)

## The ghost leaves the blade, heading the way the hand was going.
func _reap(tip: Vector2, v: Vector2) -> void:
	var heading := v.normalized()
	var speed := clampf(v.length() * 1.2, num("ghost_min", 700.0), num("ghost_max", 1300.0))
	var him := him_world()
	if him != Vector2.INF:
		var to := him - tip
		var off := absf(heading.angle_to(to))
		if off <= deg_to_rad(num("assist_degrees", 30.0)) and to.length() <= num("ghost_range", 620.0):
			heading = to.normalized()
			assisted = true
	last_heading = heading
	last_ghost_speed = speed
	var ghost := Ghost.new()
	ghost.name = "GhostBlade"
	ghost.ability = weakref(self)
	ghost.source = body.item_id
	ghost.force = num("reap_force", 2600.0) * clampf(speed / maxf(num("reap_speed", 1000.0), 1.0), 0.6, 1.4)
	ghost.mult = base_mult() * num("reap_mult", 1.0)
	ghost.shove = num("shove", 0.15)
	ghost.reach = num("ghost_range", 620.0)
	ghost.velocity = heading * speed
	ghost.spin = clampf(omega_of_body(), -12.0, 12.0)
	var s := sprite()
	if s:
		ghost.texture = _silhouette(s.texture)
		ghost.picture = s.transform
		ghost.centered = s.centered
		ghost.offset = s.offset
		ghost.flip_h = s.flip_h
	var host := body.get_parent() if body.get_parent() else body
	host.add_child(ghost)
	ghost.global_transform = body.global_transform
	_balls.append(weakref(ghost))
	var fx := fx()
	if fx:
		fx.ring(tip, 24.0, GHOST, 0.2, 2.0)
	sound(&"wail", -6.0, 1.15, 0.05)
	sound(&"whoosh", -10.0, 0.7)
	finish()

func omega_of_body() -> float:
	return body.angular_velocity

## The scythe's picture as a flat shape, every opaque pixel white, for the ghost to be tinted: a
## multiplied copy of the art was a dim scythe, not a ghost of one. Made once per scythe, and freed
## with it.
var _ghost_picture: Texture2D
var _ghost_from: Texture2D

func _silhouette(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	if _ghost_picture and _ghost_from == texture:
		return _ghost_picture
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a
			if a > 0.05:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_ghost_picture = ImageTexture.create_from_image(image)
	_ghost_from = texture
	return _ghost_picture

func _reaped(impulse: float, at: Vector2, heading: Vector2) -> void:
	reaps += 1
	last_strike = impulse
	struck.append(impulse)
	if struck.size() > 32:
		struck.pop_front()
	billed.append(num("reap_mult", 1.0))
	if billed.size() > 16:
		billed.pop_front()
	payoffs += 1
	paid_off.emit(&"soul_reap")
	var him := buddy()
	if him:
		var soul := SoulWisp.new()
		soul.name = "SoulWisp"
		soul.top_level = true
		soul.z_index = 32
		soul.target = him
		soul.pull = heading
		soul.texture = UIStyle.glyph(&"ecto")
		him.add_child(soul)
	var fx := fx()
	if fx:
		fx.ring(at, 60.0, GHOST, 0.3, 3.0)
		fx.burst(at, &"ecto", GHOST, 5, 160.0)
		fx.shake(3.0)
	sound(&"shing", -6.0, 0.6)
	sound(&"wail", -4.0, 0.8, 0.0)
	tell(&"soul_reaped", at)

func _on_stop() -> void:
	emit_from(_wisps, false)
	var s := sprite()
	if s and _glowing:
		s.self_modulate = _glow_was
	_glowing = false

## The ghost of the blade: the scythe's own picture, pale and see-through, flying straight on
## along the swing and turning as it turned, with two fainter copies of itself behind. Touches
## nothing; looks for him along the segment it flew each step, and reaps him once.
class Ghost extends Node2D:
	const LIFE := 1.2
	const ECHOES := 2

	var ability: WeakRef
	var source: StringName = &""
	var force := 2600.0
	var mult := 1.0
	var shove := 0.15
	var reach := 620.0
	var velocity := Vector2.ZERO
	var spin := 0.0
	var texture: Texture2D
	var picture := Transform2D.IDENTITY
	var centered := true
	var offset := Vector2.ZERO
	var flip_h := false
	var spent := false
	var _flown := 0.0
	var _age := 0.0
	var _echoes: Array[Transform2D] = []

	func _ready() -> void:
		z_index = 31
		top_level = true

	func _physics_process(delta: float) -> void:
		if BaseDraggable.physics_frozen:
			return
		_age += delta
		var from := global_position
		_echoes.push_front(global_transform)
		while _echoes.size() > ECHOES:
			_echoes.pop_back()
		global_position += velocity * delta
		rotation += spin * delta
		_flown += from.distance_to(global_position)
		if not spent:
			_sweep(from, global_position)
		if _flown >= reach or _age >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _sweep(from: Vector2, to: Vector2) -> void:
		if from.is_equal_approx(to):
			return
		var query := PhysicsRayQueryParameters2D.create(from, to, WeaponAbility.BUDDY_LAYER)
		query.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		var him := hit.get("collider") as Buddy
		if him == null:
			return
		spent = true
		var at: Vector2 = hit.get("position", to)
		him.apply_central_impulse(velocity.normalized() * force * shove)
		him.take_impulse(force, source, mult, at)
		var owner_ability := ability.get_ref() as SoulReapAbility if ability else null
		if owner_ability:
			owner_ability._reaped(force, at, velocity.normalized())

	func _draw() -> void:
		if texture == null:
			return
		var fade := clampf(1.0 - _flown / maxf(reach, 1.0), 0.0, 1.0)
		var inverse := global_transform.affine_inverse()
		for i in _echoes.size():
			var tint := GHOST_DEEP
			tint.a = 0.4 * fade / float(i + 1)
			_blit(inverse * _echoes[i], tint)
		var front := GHOST
		front.a = 0.8 * fade
		_blit(Transform2D.IDENTITY, front)

	func _blit(at: Transform2D, tint: Color) -> void:
		draw_set_transform_matrix(at * picture)
		var size := texture.get_size()
		var origin := offset - size * 0.5 if centered else offset
		var rect := Rect2(origin, size)
		if flip_h:
			rect = Rect2(Vector2(origin.x + size.x, origin.y), Vector2(-size.x, size.y))
		draw_texture_rect(texture, rect, false, tint)
		draw_set_transform_matrix(Transform2D.IDENTITY)

## His soul, tugged half out of him along the ghost's path and snapping back: three wisps that
## drift out `pull` and return over half a second, then it frees itself. A child of his, so it goes
## where he goes; top level, so it stays upright over him.
class SoulWisp extends Node2D:
	const LIFE := 0.55
	var target: Buddy
	var pull := Vector2.RIGHT
	var texture: Texture2D
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE or not is_instance_valid(target):
			queue_free()
			return
		var rect := target.get_interaction_rect()
		global_position = Vector2(rect.get_center().x, rect.position.y + 20.0).round()
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var k := clampf(_age / LIFE, 0.0, 1.0)
		# Out fast, back slower: most of the way out by a third, home by the end.
		var out := sin(PI * pow(k, 0.6)) * 44.0
		var half := texture.get_size() * 0.5
		for i in 3:
			var trail := pull * out * (1.0 - 0.25 * float(i))
			var tint := GHOST if i == 0 else GHOST_DEEP
			tint.a = (0.85 - 0.25 * float(i)) * (1.0 - k * 0.5)
			var grow := 2.0 - 0.4 * float(i)
			draw_set_transform(trail.round(), 0.0, Vector2(grow, grow))
			draw_texture(texture, -half, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
