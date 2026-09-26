class_name BristleAbility
extends ProjectileAbility

## The morning star fires its own spikes at him and is bald until they grow back (D74): Bristle.
##
## A tap. The spikes that face him leave the head at once — the `spikes` nearest him, in a fan of
## `fan_degrees` aimed through his middle, flat and fast (`spike_speed`, a quarter of gravity) —
## and the ball is left bald on that side. Close to him the whole fan lands; from across the desk
## the outer spikes miss. Each is an `AbilityShot` that bills itself once, `spike_force` at the
## star's multiplier times `spike_mult`, and sticks in the desk where it misses.
##
## **The picture is the cooldown.** The spikes that fired are cut out of the sprite (found in the
## art, not listed: the opaque pixels outside the ball's core, grouped by the angle they point),
## and grow back one at a time over the cooldown with a pop — so a bald star says "not yet" from
## across the desk, with no pip to read. Only the picture changes; the colliders are the star's
## own throughout, so a swing with it is the swing it always was (swing_rig, D61).
##
## Row: `spikes`, `fan_degrees`, `spike_speed`, `spike_force`, `spike_mult`, `shove`.

## Opaque pixels this far from the ball's centre, in art pixels, are spikes; nearer is the ball.
## Measured off the art: the ball is 19 art px across, so a core of 9.5 leaves a bald disc.
const CORE_RADIUS := 9.5
## The haft leaves the ball straight down; nothing within this many degrees of it is a spike.
const HAFT_DEGREES := 25.0
## Spikes further apart than this, in degrees around the ball, are different spikes.
const SPIKE_GAP_DEGREES := 12.0
## Fewer pixels than this in a group is a corner of the ball.
const MIN_SPIKE_PIXELS := 4

## Built once per texture and shared by every star on the desk: `{path: {"spikes": [...],
## "centre": Vector2, "masks": {mask: ImageTexture}}}`. A static holding textures would read as a
## leak at shutdown (ExplosionUtil's note), so it is emptied when the last star leaves.
static var _art := {}
static var _stars := 0

## Every spike in the art: its angle (radians, y down), its tip (art px) and its pixels.
var _spikes: Array = []
var _centre := Vector2.ZERO
var _original: Texture2D
var _present := 0
var _regrow: Timer
var _shots: Array[WeakRef] = []

## For the suites: spikes fired, and how many of the last fan hit him.
var last_fired := 0
var last_hits := 0

func _ready() -> void:
	super._ready()
	_stars += 1
	_regrow = Timer.new()
	_regrow.name = "Regrow"
	_regrow.one_shot = false
	_regrow.timeout.connect(_grow_one)
	add_child(_regrow)

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot):
			shot.queue_free()
	_shots.clear()
	_stars -= 1
	if _stars <= 0:
		_art.clear()

func pip_fill() -> float:
	return -1.0

## A tap: the spikes left on the press. (The archetype's release drives a golf ball.)
func _on_release(_seconds: float) -> void:
	pass

func _on_dropped() -> void:
	pass

func spikes_total() -> int:
	_learn()
	return _spikes.size()

func spikes_present() -> int:
	_learn()
	var n := 0
	for i in _spikes.size():
		if _present & (1 << i):
			n += 1
	return n

func shots_in_flight() -> int:
	var n := 0
	for ref in _shots:
		var shot := ref.get_ref() as AbilityShot
		if shot and is_instance_valid(shot) and not shot.spent and not shot.landed:
			n += 1
	return n

func _on_press() -> void:
	_learn()
	var him := him_world()
	if _spikes.is_empty() or him == Vector2.INF:
		finish(0.2)
		return
	last_hits = 0
	var centre := _centre_world()
	var aim := (him - centre).normalized()
	# The spikes that face him, nearest first: those are the ones that fly.
	var order: Array = []
	for i in _spikes.size():
		var tip := _art_to_world(_spikes[i]["tip"])
		order.append([absf((tip - centre).normalized().angle_to(aim)), i])
	order.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var count := mini(int(num("spikes", 5)), order.size())
	var chosen: Array = []
	for k in count:
		chosen.append(order[k][1])
	# Laid out across the fan in the order they sit around the ball, so the fan does not cross.
	chosen.sort_custom(func(a, b) -> bool:
		return _side_of(a, centre, aim) < _side_of(b, centre, aim))
	var fan := deg_to_rad(num("fan_degrees", 20.0))
	var speed := num("spike_speed", 1500.0)
	# The fan is laid out at him as a fan from the ball's centre would be — spread by the distance —
	# but each spike is aimed from its own tip at its place in it, so a spike on the far side of
	# the ball is not a spike aimed past him.
	var across := aim.orthogonal()
	var reach := centre.distance_to(him)
	var host := body.get_parent() if body.get_parent() else body
	for k in chosen.size():
		var i: int = chosen[k]
		var t := 0.0 if chosen.size() == 1 else float(k) / float(chosen.size() - 1) - 0.5
		var shot := AbilityShot.new()
		shot.name = "Spike"
		shot.look = AbilityShot.SPIKE
		shot.ability = weakref(self)
		shot.force = num("spike_force", 900.0)
		shot.mult = num("spike_mult", 1.0)
		shot.shove = num("shove", 0.35)
		shot.slot = i
		shot.gravity_scale = 0.25
		shot.mass = 0.1
		shot.lifetime = 1.6
		shot.after_hit = AbilityShot.DROP
		shot.after_world = AbilityShot.STICK
		host.add_child(shot)
		var tip := _art_to_world(_spikes[i]["tip"])
		var mark := him + across * (tan(fan * 0.5) * reach * 2.0 * t)
		shot.global_position = tip
		shot.linear_velocity = (mark - tip).normalized() * speed + body.linear_velocity * 0.3
		_shots.append(weakref(shot))
		_present &= ~(1 << i)
	last_fired = chosen.size()
	_show_spikes()
	# The star bucks back off the volley.
	body.apply_central_impulse(-aim * body.mass * 90.0)
	var fx := fx()
	if fx:
		fx.ring(centre, 36.0, Color.WHITE, 0.14, 2.0)
		fx.chips(centre, AbilityShot.IRON_EDGE, 6, 240.0)
		fx.puff(centre, 4, WorldFX.SOOT, 50.0, 0.4)
	sound(&"twang", -4.0, 0.62)
	sound(&"whoosh", -8.0, 1.5)
	tell(&"incoming", him)
	finish()
	# The cooldown is the regrowth: one spike back per step of it.
	var gone := _spikes.size() - spikes_present()
	if gone > 0:
		_regrow.start(maxf(_cooldown_seconds / float(gone + 1), 0.05))

## Where spike `i` sits across the line to him: negative on one side, positive on the other.
func _side_of(i: int, centre: Vector2, aim: Vector2) -> float:
	var tip := _art_to_world(_spikes[i]["tip"])
	return aim.cross((tip - centre).normalized())

func shot_hit(shot: AbilityShot, him: Buddy, at: Vector2, heading: Vector2) -> void:
	if him == null or body == null:
		return
	strike(shot.force, heading, at, shot.mult, shot.shove)
	last_hits += 1
	paid_off.emit(&"bristle")
	# Each spike in him counted on the badge over him (D77).
	show_state(&"bristled")
	var fx := fx()
	if fx:
		fx.chips(at, Color("f2ead8"), 3, 200.0)
		fx.ring(at, 18.0, Color.WHITE, 0.1, 2.0)
	sound(&"impact_metal", -10.0, 1.5)

func shot_landed(_shot: AbilityShot, at: Vector2) -> void:
	var fx := fx()
	if fx:
		fx.chips(at, WorldFX.DUST, 2, 90.0)
	sound(&"tock", -18.0, 0.7)

func _grow_one() -> void:
	for i in _spikes.size():
		if not (_present & (1 << i)):
			_present |= 1 << i
			_show_spikes()
			if body and body.is_inside_tree():
				var fx := fx()
				if fx:
					fx.chips(_art_to_world(_spikes[i]["tip"]), AbilityShot.IRON_EDGE, 2, 70.0)
				sound(&"pop", -18.0, 0.7 + 0.1 * float(i))
			break
	if spikes_present() >= _spikes.size():
		_regrow.stop()

func _on_cooled() -> void:
	# Whatever is still missing comes back with the cooldown, so ready always looks ready.
	_regrow.stop()
	if not _spikes.is_empty():
		_present = (1 << _spikes.size()) - 1
		_show_spikes()
	super._on_cooled()

# --- the art --------------------------------------------------------------------------------

## Finds the spikes in the star's own picture, once per texture.
func _learn() -> void:
	if not _spikes.is_empty():
		return
	var s := sprite()
	if s == null or s.texture == null:
		return
	_original = s.texture
	var key := _original.resource_path if _original.resource_path != "" else str(_original.get_instance_id())
	if not _art.has(key):
		_art[key] = _read_art(_original)
	var art: Dictionary = _art[key]
	_spikes = art["spikes"]
	_centre = art["centre"]
	_present = (1 << _spikes.size()) - 1

## The ball's centre is the centroid of the opaque pixels near the top of the picture's head; the
## spikes are what stands out from it, grouped by the direction they point.
static func _read_art(texture: Texture2D) -> Dictionary:
	var image := texture.get_image()
	if image == null:
		return {"spikes": [], "centre": Vector2.ZERO, "masks": {}}
	if image.is_compressed():
		image.decompress()
	var w := image.get_width()
	var h := image.get_height()
	# The head: the widest band of rows in the top half. Its centre is the ball's.
	var widest := 0
	var head_y := 0
	for y in h / 2:
		var n := 0
		for x in w:
			if image.get_pixel(x, y).a > 0.5:
				n += 1
		if n > widest:
			widest = n
			head_y = y
	var sum := Vector2.ZERO
	var count := 0
	for y in range(maxi(0, head_y - 8), mini(h, head_y + 9)):
		for x in w:
			if image.get_pixel(x, y).a > 0.5:
				sum += Vector2(x, y)
				count += 1
	var centre := sum / float(maxi(count, 1)) + Vector2(0.5, 0.5)
	var loose: Array = []
	for y in h:
		for x in w:
			if image.get_pixel(x, y).a <= 0.5:
				continue
			var p := Vector2(x + 0.5, y + 0.5) - centre
			if p.length() <= CORE_RADIUS or p.length() > CORE_RADIUS * 2.2:
				continue
			var angle := p.angle()
			if absf(rad_to_deg(angle_difference(angle, PI * 0.5))) <= HAFT_DEGREES:
				continue
			loose.append([angle, Vector2i(x, y), p.length()])
	loose.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var spikes: Array = []
	for entry in loose:
		var last: Dictionary = spikes.back() if not spikes.is_empty() else {}
		if last.is_empty() or rad_to_deg(angle_difference(float(last["last"]), float(entry[0]))) > SPIKE_GAP_DEGREES:
			spikes.append({"angle": entry[0], "last": entry[0], "pixels": [], "tip": Vector2.ZERO, "reach": 0.0})
			last = spikes.back()
		last["last"] = entry[0]
		(last["pixels"] as Array).append(entry[1])
		if float(entry[2]) > float(last["reach"]):
			last["reach"] = entry[2]
			last["tip"] = Vector2(entry[1]) + Vector2(0.5, 0.5)
	# The first and last groups are one spike if it straddles the seam at +-180 degrees.
	if spikes.size() > 1 and rad_to_deg(angle_difference(float(spikes.back()["last"]),
			float(spikes[0]["angle"]) + TAU)) <= SPIKE_GAP_DEGREES:
		var tail: Dictionary = spikes.pop_back()
		(spikes[0]["pixels"] as Array).append_array(tail["pixels"])
		if float(tail["reach"]) > float(spikes[0]["reach"]):
			spikes[0]["tip"] = tail["tip"]
	# A pixel or two standing proud of the core is a corner of the ball, not a spike.
	spikes = spikes.filter(func(spike: Dictionary) -> bool: return (spike["pixels"] as Array).size() >= MIN_SPIKE_PIXELS)
	return {"spikes": spikes, "centre": centre, "masks": {}, "image": image}

## The star with only the spikes in `_present`, built once per combination.
func _show_spikes() -> void:
	var s := sprite()
	if s == null or _original == null:
		return
	var all := (1 << _spikes.size()) - 1
	if _present == all:
		s.texture = _original
		return
	var key := _original.resource_path if _original.resource_path != "" else str(_original.get_instance_id())
	var art: Dictionary = _art.get(key, {})
	if art.is_empty():
		return
	var masks: Dictionary = art["masks"]
	if not masks.has(_present):
		var image := (art["image"] as Image).duplicate() as Image
		for i in _spikes.size():
			if _present & (1 << i):
				continue
			for pixel in _spikes[i]["pixels"]:
				image.set_pixelv(pixel, Color(0, 0, 0, 0))
		masks[_present] = ImageTexture.create_from_image(image)
	s.texture = masks[_present]

## An art pixel on the star's sprite, in the world.
func _art_to_world(art_px: Vector2) -> Vector2:
	var s := sprite()
	if s == null or s.texture == null:
		return com_world()
	var local := art_px - s.texture.get_size() * 0.5 if s.centered else art_px
	return s.to_global(local + s.offset)

func _centre_world() -> Vector2:
	return _art_to_world(_centre)
