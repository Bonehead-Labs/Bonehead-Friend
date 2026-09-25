class_name HotCoffeeAbility
extends ProjectileAbility

## A flick of the wrist and the mug's coffee arcs out over him (D74): Hot Coffee.
##
## A tap. The mug is flicked toward him (`whip`) and its coffee leaves the rim as a splash of
## `drops` drops on the low arc through his middle — the golf ball's solution, at the least speed
## that reaches him or `splash_speed`, whichever is more — each a little faster or slower than the
## last, so it lands as a spatter and not a bullet. The first drop to reach him **scalds** him: one
## light hit, `scald_force` at the mug's multiplier times `scald_mult` through `Buddy.take_impulse`
## (D7), and `grime` added to him (D46: coffee stains; the sponge has something to do). Then he
## steams for `steam_seconds` — puffs rising off him, his crying, shivering `scalded` face — and
## the steam bites `steam_ticks` more times, lighter (`steam_force`). The other drops splat.
##
## The only ability that dirties him, and the only one that goes on hurting after it has landed.
##
## Row: `drops`, `splash_speed`, `whip`, `scald_force`, `scald_mult`, `shove`, `grime`,
## `steam_seconds`, `steam_ticks`, `steam_force`.

var _shots: Array[WeakRef] = []
var _scalded := false
var _steam_left := 0.0
var _steam_next := 0.0
var _ticks_left := 0
var _steam: GPUParticles2D
var _steam_host: Buddy
var _next_tell := 0.0
var _t := 0.0

## For the suites: drops thrown and the scald's numbers.
var thrown := 0
var scalds := 0
var steam_hits := 0
var last_grime := 0.0

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot):
			shot.queue_free()
	_shots.clear()
	_stop_steam()

func pip_fill() -> float:
	return -1.0

func is_steaming() -> bool:
	return _active and _steam_left > 0.0

## The rim: the top of the mug's biggest box, at its middle.
func _rim() -> Vector2:
	if body.collider and body.collider.shape:
		var rect := body.collider.shape.get_rect()
		var xf := body.collider.transform
		return body.to_global(xf * Vector2(rect.get_center().x, rect.position.y))
	return body.global_position

## The least speed that reaches `to` from `from` on some arc — then a little more, so the low arc
## exists and it is a splash, not a lob.
func _speed_to(from: Vector2, to: Vector2) -> float:
	var dx := absf(to.x - from.x)
	var rise := from.y - to.y
	var g := _gravity
	var need := sqrt(maxf(g * (sqrt(dx * dx + rise * rise) + rise), 1.0))
	return maxf(num("splash_speed", 620.0), need * 1.12)

func _on_press() -> void:
	var him := buddy()
	if him == null:
		finish(0.2)
		return
	_t = 0.0
	_scalded = false
	_steam_left = 0.0
	_ticks_left = 0
	thrown = 0
	scalds = 0
	steam_hits = 0
	last_grime = 0.0
	var from := _rim()
	var target := him.get_interaction_rect().get_center()
	var speed := _speed_to(from, target)
	var v := launch_velocity(from, speed)
	# The wrist: the mug tips toward him as the coffee leaves it.
	whip(signf(v.x) * num("whip", 9.0))
	var host := body.get_parent() if body.get_parent() else body
	var count := int(num("drops", 7))
	for i in count:
		var k := 0.0 if count <= 1 else float(i) / float(count - 1) - 0.5
		var shot := AbilityShot.new()
		shot.name = "Coffee"
		shot.look = AbilityShot.COFFEE
		shot.ability = weakref(self)
		shot.force = num("scald_force", 900.0)
		shot.mult = num("scald_mult", 1.0)
		shot.shove = num("shove", 0.2)
		shot.slot = i
		shot.mass = 0.03
		shot.lifetime = 1.6
		shot.after_hit = AbilityShot.SPLAT
		shot.after_world = AbilityShot.SPLAT
		host.add_child(shot)
		shot.global_position = from + Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0))
		# A spatter, not a bullet: faster and slower drops, a few degrees either side.
		shot.linear_velocity = (v * (1.0 + 0.22 * k)).rotated(deg_to_rad(randf_range(-5.0, 5.0)))
		_shots.append(weakref(shot))
		thrown += 1
	run(true)
	var fx := fx()
	if fx:
		fx.chips(from, AbilityShot.COFFEE_LIGHT, 4, 180.0)
		fx.puff(from, 3, Color.WHITE, 40.0, 0.5)
	sound(&"slosh", -4.0, 1.2)
	tell(&"incoming", target)

func _on_tick(delta: float) -> void:
	_t += delta
	if _steam_left > 0.0:
		_steam_left -= delta
		_steam_next -= delta
		_next_tell -= delta
		if _next_tell <= 0.0:
			_next_tell = 0.35
			var him := buddy()
			if him:
				tell(&"scalded", him.get_interaction_rect().get_center())
		if _ticks_left > 0 and _steam_next <= 0.0:
			_steam_tick()
		if _steam_left <= 0.0:
			_stop_steam()
			finish()
		return
	# Every drop missed: done once they have all come down.
	if _t >= 1.4:
		finish()

func shot_hit(shot: AbilityShot, him: Buddy, at: Vector2, heading: Vector2) -> void:
	if him == null or body == null:
		return
	if _scalded:
		_splat(at)
		return
	_scalded = true
	scalds += 1
	strike(shot.force, heading, at, shot.mult, shot.shove)
	if him.grime:
		var before := him.grime.value
		him.grime.add(num("grime", 0.04))
		last_grime = him.grime.value - before
	_steam_left = num("steam_seconds", 1.2)
	_ticks_left = int(num("steam_ticks", 2))
	_steam_next = _steam_left / float(_ticks_left + 1)
	_next_tell = 0.0
	_start_steam(him)
	_splat(at)
	var fx := fx()
	if fx:
		fx.puff(at, 6, Color.WHITE, 70.0, 0.7)
	sound(&"sizzle", -2.0, 1.0)
	paid_off.emit(&"hot_coffee")

func shot_landed(_shot: AbilityShot, at: Vector2) -> void:
	_splat(at)

func _splat(at: Vector2) -> void:
	var fx := fx()
	if fx:
		fx.chips(at, AbilityShot.COFFEE_LIGHT, 3, 150.0)
		fx.chips(at, AbilityShot.COFFEE_DARK, 2, 90.0)
	sound(&"splash", -16.0, 1.4, 0.1)

## The steam biting again: a lighter hit, straight up off him.
func _steam_tick() -> void:
	_ticks_left -= 1
	_steam_next = num("steam_seconds", 1.2) / float(int(num("steam_ticks", 2)) + 1)
	var him := buddy()
	if him == null:
		return
	var at := him.get_interaction_rect().get_center()
	strike(num("steam_force", 450.0), Vector2.UP, at, num("scald_mult", 1.0), 0.0)
	steam_hits += 1
	var fx := fx()
	if fx:
		fx.puff(at + Vector2(0, -20), 4, Color.WHITE, 50.0, 0.6)
	sound(&"sizzle", -10.0, 1.3)

## Steam off him: white puffs rising from his skull, his child so it goes where he goes, taken off
## when the steam stops or the mug leaves the desk.
func _start_steam(him: Buddy) -> void:
	if not is_instance_valid(_steam):
		var rect := him.get_interaction_rect()
		_steam = emitter("steam", &"chip", Color("f4f1e6"), 18,
			him.to_local(Vector2(rect.get_center().x, rect.position.y + 20.0)), Vector2(0, -70), 50.0, 0.8,
			Vector2(0, -60), false, him)
		_steam_host = him
	emit_from(_steam, true)

func _stop_steam() -> void:
	if is_instance_valid(_steam):
		_steam.queue_free()
	_steam = null
	_steam_host = null

## A tap: letting go is nothing — the coffee is already out of the mug. (The archetype's release
## drives a golf ball.)
func _on_release(_seconds: float) -> void:
	pass

func _on_dropped() -> void:
	# The coffee is already out of the mug.
	pass

func _on_stop() -> void:
	_steam_left = 0.0
	_stop_steam()
