class_name MeteorShowerPower
extends SpellPower

## The meteor shower (D72): hold the button and burning rocks come down from above the top of
## the window, slanting in, each one landing somewhere near the cursor and going off where it
## lands. A barrage you steer, where every other harm power is one shot or one beam.
##
## Each landing is a blast: he is handed its impulse through `take_impulse`, the lightning and
## the missile's door (D7), measured with the same falloff every blast in the game uses. What it
## *shoves* is `shove_share` of that. A single strike can throw him across the desk because it is
## one strike; a shower that did the same would hit him once and then rain on the place he had
## been. Rocked rather than thrown, he stays under it — the beam's argument for a notional
## impulse (`BeamPower`), made for a barrage.
##
## A meteor already in the air when the button comes up — or when the power is put away — still
## lands; a shower that stopped mid-sky would be rocks vanishing. The rocks are a pool of
## `pool_size`, built on the first cast and parked after, each with its own fire and smoke that
## only emit while it falls. Nothing is instanced per meteor, and nothing processes once the
## last one has landed.

@export var meteor_texture: Texture2D
## Seconds between meteors while the button is held, before "Denser Shower".
@export var interval: float = 0.25
@export var blast_radius: float = 70.0
@export var blast_force: float = 2400.0
## How much of the blast pushes: the rest is the part only he measures.
@export var shove_share: float = 0.4
## How far from the cursor a meteor may land.
@export var spread: float = 46.0
@export var fall_speed: float = 1500.0
## Sideways travel per pixel of fall: they come in slanting, from the upper left.
@export var slant: float = 0.35
@export var pool_size: int = 8

var _rocks: Array[Rock] = []
var _next_msec := 0
var _in_air := 0

func is_live() -> bool:
	return _in_air > 0

func can_fire_at(_at: Vector2) -> bool:
	return true

func fire(at: Vector2) -> void:
	_aim = at
	_held = true
	_build()
	_next_msec = 0
	_call_one()
	set_physics_process(true)
	_update_input()

func _released(_at: Vector2) -> void:
	_update_input()

func _spell_deactivated(_was_held: bool) -> void:
	# The rocks in the air keep falling; no new ones are called.
	pass

## The time from one meteor to the next, as "Denser Shower" has it.
func gap_seconds() -> float:
	return interval * Progression.get_modifier(item_id, &"cooldown_mult")

func next_msec() -> int:
	return _next_msec

func _physics_process(delta: float) -> void:
	if _held and active and Time.get_ticks_msec() >= _next_msec:
		_call_one()
	for rock in _rocks:
		if not rock.live:
			continue
		rock.t += delta / rock.duration
		if rock.t >= 1.0:
			_land(rock)
			continue
		rock.position = rock.from.lerp(rock.to, rock.t)
		rock.spin(delta)
	if _in_air <= 0 and not (_held and active):
		set_physics_process(false)
		_update_input()

func _call_one() -> void:
	_next_msec = Time.get_ticks_msec() + int(gap_seconds() * 1000.0)
	var rock: Rock = null
	for candidate in _rocks:
		if not candidate.live:
			rock = candidate
			break
	if rock == null:
		# Every rock is still falling. The next one is due the moment one lands.
		return
	var view := get_viewport().get_visible_rect()
	var to := _aim + Vector2.RIGHT.rotated(randf() * TAU) * randf() * spread
	var top := view.position.y - 60.0
	var from := Vector2(to.x - (to.y - top) * slant, top)
	rock.launch(from, to, maxf(0.12, from.distance_to(to) / fall_speed), _effects_on())
	_in_air += 1
	AudioManager.play(&"meteor", 0.15, -16.0)

func _land(rock: Rock) -> void:
	var at := rock.to
	rock.park()
	_in_air = maxi(0, _in_air - 1)
	var space := get_world_2d().direct_space_state
	var mult := effective_damage_mult()
	for hit in ExplosionUtil.point_blast(space, at, blast_radius, blast_force * shove_share):
		var target: Node = hit["body"]
		if target is Buddy:
			var him := target as Buddy
			him.take_impulse(ExplosionUtil.blast_strength(him.global_position.distance_to(at),
				blast_radius, blast_force), item_id, mult, at)
	var fx := _fx()
	if fx:
		var tier := _tier()
		fx.boom(at, 0.45 + 0.05 * float(tier))
		fx.chips(at, WorldFX.HEAT.lerp(WorldFX.harm_colour(tier), 0.5), 6 + 2 * tier, 260.0)
	AudioManager.play(&"explode_small", 0.2, -10.0)
	_use()

func _build() -> void:
	if not _rocks.is_empty():
		return
	var tier := _tier()
	var colour := WorldFX.HEAT.lerp(WorldFX.harm_colour(tier), 0.5) if tier > 0 else WorldFX.HEAT
	for i in pool_size:
		var rock := Rock.new()
		rock.name = "Meteor%d" % i
		rock.z_index = 33
		add_child(rock)
		# Fire and smoke, each its own emitter: the fire dense and short-lived so it reads as a
		# burning tail rather than a dotted line, the smoke slower and dark behind it.
		var fire := _emitter("Fire", _chip(), colour, 110 + 20 * tier, 0.35, -80.0, 70.0,
			Vector2(6, 6), 1.5, 3.0)
		var smoke := _emitter("Smoke", _chip(), WorldFX.SOOT, 36, 0.8, -40.0, 30.0,
			Vector2(5, 5), 2.0, 3.5)
		for emitter in [fire, smoke]:
			(emitter.process_material as ParticleProcessMaterial).spread = 180.0
			remove_child(emitter)
		rock.build(meteor_texture, [smoke, fire], colour)
		_rocks.append(rock)

## One meteor: a tumbling rock, a tapered tail of fire behind it, and embers it sheds as it
## falls. Parked invisible between uses.
class Rock extends Node2D:
	var live := false
	var t := 0.0
	var duration := 1.0
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var _sprite: Sprite2D
	var _tail: Line2D
	var _trails: Array = []

	## The rock and its tail are hidden between uses; the node itself stays visible, so the
	## embers already shed keep falling after it lands instead of vanishing with it.
	func build(texture: Texture2D, trails: Array, colour: Color) -> void:
		for emitter in trails:
			(emitter as GPUParticles2D).z_index = -1
			add_child(emitter)
			_trails.append(emitter)
		_tail = Line2D.new()
		_tail.name = "Tail"
		_tail.antialiased = false
		_tail.width = 16.0
		_tail.visible = false
		var gradient := Gradient.new()
		gradient.set_color(0, WorldFX.HARM_TIERS[2])
		gradient.set_color(1, SpellPower.HOLY)
		gradient.add_point(0.5, colour)
		_tail.gradient = gradient
		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 0.1))
		taper.add_point(Vector2(1.0, 1.0))
		_tail.width_curve = taper
		add_child(_tail)
		_sprite = Sprite2D.new()
		_sprite.name = "Rock"
		_sprite.texture = texture
		_sprite.scale = Vector2(3, 3)
		_sprite.visible = false
		add_child(_sprite)

	func launch(start: Vector2, end: Vector2, seconds: float, effects: bool) -> void:
		from = start
		to = end
		t = 0.0
		duration = seconds
		live = true
		position = start
		var back := (start - end).normalized() * 120.0
		_tail.points = PackedVector2Array([back, Vector2.ZERO])
		_tail.visible = true
		_sprite.visible = true
		_sprite.rotation = randf() * TAU
		for emitter in _trails:
			(emitter as GPUParticles2D).emitting = effects

	func spin(delta: float) -> void:
		_sprite.rotation += delta * 9.0

	func park() -> void:
		live = false
		_sprite.visible = false
		_tail.visible = false
		for emitter in _trails:
			(emitter as GPUParticles2D).emitting = false
