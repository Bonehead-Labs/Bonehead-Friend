class_name DonutTossAbility
extends ProjectileAbility

## The donut box's Donut Toss (docs/decisions.md D78): a tap, and one donut flips out of the box
## in your hand, up and over, into his mouth.
##
## The golf club's archetype, fired on the press as the mug's coffee is: the donut is an
## `AbilityShot` (drawn, icing and sprinkles, big enough to follow) lobbed on the **high** arc onto
## his head — a flip, not a throw — at the least speed that gets there, or `toss_speed`, whichever
## is more. It collides with the world and nothing else and sweeps for him, so it is caught once or
## not at all. Caught, it is **one of the box's six helpings**, eaten: the box pays that helping
## exactly as it would have if he had got his teeth into the box (`hearts_per_contact`, one act),
## plus `fed_bonus` for being hand-fed, and the box has one fewer. The sixth empties it and it is
## gone. A donut that misses lands on the desk in crumbs and costs the box nothing.
##
## So the box is worth what it always was, a helping at a time, from across the desk — the bonus
## is the ability's whole `worth`. A tap with nobody in `reach`, or an empty box, is refused.
##
## Row: `toss_speed`, `reach`, `fed_bonus`, `spin`.

var _shots: Array[WeakRef] = []
var _t := 0.0
var _flying := false

## For the suites: donuts tossed, caught and missed.
var tossed := 0
var caught_donuts := 0
var missed := 0

func _exit_tree() -> void:
	super._exit_tree()
	for ref in _shots:
		var shot := ref.get_ref() as Node
		if shot and is_instance_valid(shot):
			shot.queue_free()
	_shots.clear()

func pip_fill() -> float:
	return -1.0

func _box() -> FriendlyBase:
	return body as FriendlyBase

## Helpings left in the box.
func helpings() -> int:
	var box := _box()
	if box == null:
		return 0
	return maxi(box.servings - box._eaten, 0)

func _can_start() -> bool:
	var him := buddy()
	if him == null or helpings() <= 0:
		return false
	return com_world().distance_to(_mouth(him)) <= num("reach", 380.0)

## Where a donut goes in: the top of his skull, a little in from his face.
func _mouth(him: Buddy) -> Vector2:
	var rect := him.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.22)

## The lid: the top of the box's biggest box, at its middle.
func _lid() -> Vector2:
	if body.collider and body.collider.shape and body.collider.shape.has_method("get_rect"):
		var rect: Rect2 = body.collider.shape.get_rect()
		return body.to_global(body.collider.transform * Vector2(rect.get_center().x, rect.position.y))
	return com_world()

## The high arc from `from` onto `to`: a flip that comes down on him, never a line into his face.
## The least speed that has one, a fifth more so the high arc exists, or `toss_speed`.
func _lob(from: Vector2, to: Vector2) -> Vector2:
	var dx := to.x - from.x
	var rise := from.y - to.y
	var side := 1.0 if dx >= 0.0 else -1.0
	var x := absf(dx)
	var g := _gravity
	var need := sqrt(maxf(g * (sqrt(x * x + rise * rise) + rise), 1.0))
	var speed := maxf(num("toss_speed", 480.0), need * 1.2)
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * rise * v2)
	var angle := PI * 0.35
	if x > 1.0 and disc >= 0.0:
		angle = atan((v2 + sqrt(disc)) / (g * x))
	return Vector2(cos(angle) * side, -sin(angle)) * speed

func _on_press() -> void:
	var him := buddy()
	if him == null:
		finish(0.2)
		return
	_t = 0.0
	_flying = true
	var from := _lid()
	var v := _lob(from, _mouth(him))
	var host := body.get_parent() if body.get_parent() else body
	var shot := AbilityShot.new()
	shot.name = "Donut"
	shot.look = AbilityShot.DONUT
	shot.ability = weakref(self)
	shot.force = 0.0
	shot.mult = 0.0
	shot.shove = 0.0
	shot.mass = 0.05
	shot.lifetime = 2.5
	shot.after_hit = AbilityShot.SPLAT
	shot.after_world = AbilityShot.SPLAT
	host.add_child(shot)
	shot.global_position = from + Vector2(0, -6)
	shot.linear_velocity = v
	_shots.append(weakref(shot))
	tossed += 1
	run(true)
	# The box flicks up as the donut leaves it.
	whip(signf(v.x) * num("spin", 5.0))
	var fx := fx()
	if fx:
		fx.chips(from, AbilityShot.DOUGH, 3, 120.0)
	sound(&"pop", -6.0, 0.8)
	AbilityCues.activation(self, from)
	# Something is coming to him to catch, head or wear: whatever routine he was in stands down.
	notice_player()
	tell(&"donut_incoming", _mouth(him))

## Gone once the donut is down, in him or on the desk.
func _on_tick(delta: float) -> void:
	_t += delta
	if not _flying or _t >= 2.6:
		finish()

## A tap: the donut is out of the box on the press. (The archetype's release drives a golf ball.)
func _on_release(_seconds: float) -> void:
	pass

func _on_dropped() -> void:
	pass

## In his mouth: a helping from the box, and the hand-fed bonus.
func shot_hit(_shot: AbilityShot, him: Buddy, at: Vector2, _heading: Vector2) -> void:
	_flying = false
	var box := _box()
	if him == null or box == null:
		return
	caught_donuts += 1
	box._eaten += 1
	var helping := box.hearts_per_contact
	give(helping + num("fed_bonus", 1.0), at, helping)
	var fx := fx()
	if fx:
		fx.chips(at, AbilityShot.DOUGH, 5, 150.0)
		fx.chips(at, AbilityShot.ICING, 3, 120.0)
		fx.burst(at, &"heart", WorldFX.kind_colour(body.juice_tier), 3, 110.0, 0.6)
	sound(&"crunch", -4.0, 1.1)
	tell(&"fed", at)
	AbilityCues.payoff(self, &"donut_toss", at, "yum!")
	if box._eaten >= box.servings:
		# The last one: the box is empty and goes, as it would have if he had eaten it.
		finish()
		box._flush()
		box._despawn.call_deferred()

func shot_landed(_shot: AbilityShot, at: Vector2) -> void:
	_flying = false
	missed += 1
	var fx := fx()
	if fx:
		fx.chips(at, AbilityShot.DOUGH, 4, 90.0)
		fx.chips(at, AbilityShot.SPRINKLES[1], 2, 70.0)
	sound(&"crunch", -14.0, 1.4)

func _on_stop() -> void:
	super._on_stop()
