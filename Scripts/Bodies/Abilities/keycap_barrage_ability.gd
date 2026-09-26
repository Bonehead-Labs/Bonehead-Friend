class_name KeycapBarrageAbility
extends ProjectileAbility

## Eight keycaps pop off the keyboard, rain down on him, and clack back on (D74): Keycap Barrage.
##
## A tap. `caps` caps leave their keys at once in a fountain — each on the high arc that lands it
## on the top of his head `rain_seconds` later, one after another `stagger` apart, spread across
## `spread` px of him — and he has nowhere to go but under them. The keys they came off show bare
## switches until they are back. Each cap is an `AbilityShot` that bills itself once, a light hit:
## `cap_force` at the keyboard's multiplier times `cap_mult`. Then, whether it found him or the
## desk, it lies a moment, and flies home to its own key, which it hits with a clack. The effect
## is over when the last one is home (or `home_seconds` has passed).
##
## The morning star's Bristle is the other volley: that one is a flat fan straight at him and the
## star grows its spikes back where they were. These go up, come down, and come back.
##
## Row: `caps`, `rain_seconds`, `stagger`, `spread`, `cap_force`, `cap_mult`, `shove`,
## `home_after`, `home_seconds`.

const KEY_TOP := Color(0.949, 0.816, 0.420)
const KEY_SKIRT := Color(0.663, 0.443, 0.247)

## Every keyboard shares the same picture, so the keys are found once.
static var _found := {}

var _slots: Array[Vector2] = []
var _out: Array[bool] = []
var _shots: Array[WeakRef] = []
var _bare: BareKeys
var _t := 0.0

## For the suites: caps fired, caps that hit him, caps home.
var fired := 0
var hits := 0
var home := 0

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot):
			shot.queue_free()
	_shots.clear()

func pip_fill() -> float:
	return -1.0

func caps_out() -> int:
	var n := 0
	for out in _out:
		if out:
			n += 1
	return n

func _on_press() -> void:
	_learn_keys()
	var him := buddy()
	if him == null or _slots.is_empty():
		finish(0.2)
		return
	fired = 0
	hits = 0
	home = 0
	_t = 0.0
	var rect := him.get_interaction_rect()
	var gravity := _gravity
	var count := mini(int(num("caps", 8)), _slots.size())
	var host := body.get_parent() if body.get_parent() else body
	var spread := num("spread", 50.0)
	_out.resize(_slots.size())
	for i in count:
		var slot := _slots[i]
		var from := body.to_global(slot)
		# Across the top of him, shuffled so the rain does not sweep one way.
		var across := -spread + 2.0 * spread * float((i * 5) % count) / float(maxi(count - 1, 1))
		var target := Vector2(rect.get_center().x + across, rect.position.y + 8.0)
		var flight := num("rain_seconds", 0.8) + num("stagger", 0.05) * float(i)
		var v := (target - from) / flight - Vector2(0.0, gravity) * (0.5 * flight)
		var shot := AbilityShot.new()
		shot.name = "Keycap"
		shot.look = AbilityShot.KEYCAP
		shot.ability = weakref(self)
		shot.force = num("cap_force", 800.0)
		shot.mult = num("cap_mult", 1.0)
		shot.shove = num("shove", 0.25)
		shot.slot = i
		shot.mass = 0.05
		shot.lifetime = num("home_seconds", 2.4) - 0.6
		shot.after_hit = AbilityShot.HOME
		shot.after_world = AbilityShot.HOME
		shot.home_node = body
		shot.home_local = slot
		shot.home_after = num("home_after", 0.45)
		host.add_child(shot)
		shot.global_position = from
		shot.linear_velocity = v
		shot.angular_velocity = randf_range(-14.0, 14.0)
		_shots.append(weakref(shot))
		_out[i] = true
		fired += 1
	_show_bare()
	run(true)
	var fx := fx()
	if fx:
		fx.ring(body.global_position, 50.0, Color.WHITE, 0.16, 2.0)
		fx.puff(body.global_position, 6, WorldFX.DUST, 60.0, 0.4)
	sound(&"rattle", -4.0, 1.5)
	sound(&"pop", -6.0, 0.8)
	tell(&"incoming", rect.get_center())

func _on_tick(delta: float) -> void:
	_t += delta
	if caps_out() == 0 or _t >= num("home_seconds", 2.4) + 1.0:
		_all_home()

## A tap: letting go is nothing — the caps are already in the air. (The archetype's release
## drives a golf ball.)
func _on_release(_seconds: float) -> void:
	pass

## Dropped mid-barrage, the caps still come home: to the keyboard, wherever it is.
func _on_dropped() -> void:
	pass

func shot_hit(shot: AbilityShot, him: Buddy, at: Vector2, heading: Vector2) -> void:
	if him == null or body == null:
		return
	strike(shot.force, heading, at, shot.mult, shot.shove)
	hits += 1
	if hits == 1:
		paid_off.emit(&"keycap_barrage")
	# Each cap that found him counted on the badge over him (D77).
	show_state(&"keyed")
	var fx := fx()
	if fx:
		fx.chips(at, KEY_TOP, 2, 160.0)
	sound(&"impact_plastic", -8.0, 1.3 + 0.05 * float(shot.slot))

func shot_landed(_shot: AbilityShot, at: Vector2) -> void:
	sound(&"tock", -16.0, 1.2 + randf() * 0.4)
	var fx := fx()
	if fx:
		fx.chips(at, KEY_SKIRT, 1, 60.0)

func shot_home(shot: AbilityShot) -> void:
	if shot.slot >= 0 and shot.slot < _out.size():
		_out[shot.slot] = false
	home += 1
	_show_bare()
	if body and body.is_inside_tree():
		var fx := fx()
		if fx:
			fx.ring(body.to_global(_slots[shot.slot]), 10.0, Color.WHITE, 0.1, 1.0)
	sound(&"ui_click", -6.0, 0.9 + 0.08 * float(home % 5), 0.05)

func _all_home() -> void:
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot):
			shot.queue_free()
	_shots.clear()
	for i in _out.size():
		_out[i] = false
	_show_bare()
	finish()

func _on_stop() -> void:
	for i in _out.size():
		_out[i] = false
	_show_bare()

## The keys the caps come off: runs of three lit pixels with the skirt colour under them, on the
## first row of the picture that has enough of them. Body-local, at each key's middle.
func _learn_keys() -> void:
	if not _slots.is_empty():
		return
	var s := sprite()
	if s == null or s.texture == null:
		return
	var key := s.texture.resource_path
	if not _found.has(key):
		_found[key] = _read_keys(s.texture, int(num("caps", 8)))
	for art_px in _found[key]:
		var local: Vector2 = (art_px as Vector2) - s.texture.get_size() * 0.5 if s.centered else art_px
		_slots.append(body.to_local(s.to_global(local + s.offset)))
	_out.resize(_slots.size())
	_out.fill(false)

static func _read_keys(texture: Texture2D, want: int) -> Array:
	var image := texture.get_image()
	var out: Array = []
	if image == null:
		return out
	if image.is_compressed():
		image.decompress()
	for y in image.get_height() - 2:
		var runs: Array = []
		var x := 0
		while x < image.get_width() - 2:
			if _is(image.get_pixel(x, y), KEY_TOP) and _is(image.get_pixel(x + 1, y), KEY_TOP) \
					and _is(image.get_pixel(x + 2, y), KEY_TOP) and _is(image.get_pixel(x + 1, y + 1), KEY_SKIRT):
				runs.append(Vector2(x + 1.5, y + 1.5))
				x += 3
			else:
				x += 1
		if runs.size() >= want:
			for i in want:
				out.append(runs[int(float(i) * float(runs.size()) / float(want))])
			return out
	return out

static func _is(c: Color, want: Color) -> bool:
	return c.a > 0.5 and absf(c.r - want.r) < 0.03 and absf(c.g - want.g) < 0.03 and absf(c.b - want.b) < 0.03

func _show_bare() -> void:
	if _bare == null:
		if caps_out() == 0:
			return
		_bare = BareKeys.new()
		_bare.name = "BareKeys"
		_bare.z_index = 1
		body.add_child(_bare)
	var bare: Array[Vector2] = []
	for i in _out.size():
		if _out[i]:
			bare.append(_slots[i])
	_bare.show_keys(bare)

## The switches under the missing caps: a dark well with the stem's cross in it, where each cap
## was. Drawn in the keyboard's frame, so they stay on it however it is held.
class BareKeys extends Node2D:
	var _keys: Array[Vector2] = []

	func show_keys(keys: Array[Vector2]) -> void:
		_keys = keys
		visible = not keys.is_empty()
		queue_redraw()

	func _draw() -> void:
		for at in _keys:
			var p := at.round()
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color("141210"))
			draw_rect(Rect2(p - Vector2(1, 3), Vector2(2, 6)), Color("c8382e"))
			draw_rect(Rect2(p - Vector2(3, 1), Vector2(6, 2)), Color("c8382e"))
