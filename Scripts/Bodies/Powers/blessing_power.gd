class_name BlessingPower
extends SpellPower

## The blessing (D72): click him and a halo settles over his head. The click is a kind act, and
## for as long as the halo stays — `halo_seconds`, renewed by the next blessing — hearts rain
## down on him from it and he is paid a trickle for being under it.
##
## A spell you leave on him, where every other kind thing in the game is either held (the hand,
## the brush) or put on the desk. The cast pays through `kindness_given`, so it is an act — the
## combo, the contracts, the Dollars — and the halo through `kindness_sustained`, a rate outside
## the combo for exactly the reason a boombox is (docs/economy.md). Both lift his mood; he wears
## the blessed look for as long as the halo is up, and calms under it.
##
## The halo goes when the blessing is put away. A spell that kept paying after the wand was
## holstered would be a generator bought at a spell's price.

@export var halo_texture: Texture2D
## The cast, as a kind act.
@export var bless_value: float = 12.0
## How long a halo stays, from the last blessing.
@export var halo_seconds: float = 8.0
## Kindness per second while the halo is up, paid every `flush_seconds`.
@export var halo_rate: float = 2.0
@export var flush_seconds: float = 0.5
## Seconds between blessings, before "Quicker Grace".
@export var recast_seconds: float = 2.5
@export var reach_padding: float = 16.0

var _until_msec := 0
var _next_flush_msec := 0
var _recast_msec := 0
var _halo: Sprite2D
var _rain: GPUParticles2D
var _sparkle: GPUParticles2D

func is_live() -> bool:
	return _until_msec > 0

func can_fire_at(at: Vector2) -> bool:
	return _reachable(_buddy()) and _on_him(at, reach_padding)

func fire(at: Vector2) -> void:
	var buddy := _buddy()
	if buddy == null:
		return
	var now := Time.get_ticks_msec()
	if now < _recast_msec:
		_fizzle(at, WorldFX.GOLD)
		return
	_recast_msec = now + int(recast_seconds * Progression.get_modifier(item_id, &"cooldown_mult") * 1000.0)
	_build()
	var head := _head(buddy)
	EventBus.kindness_given.emit(item_id, bless_value * effective_damage_mult(), head)
	if _until_msec == 0:
		_next_flush_msec = now + int(flush_seconds * 1000.0)
	_until_msec = now + int(halo_seconds * 1000.0)
	_halo.visible = true
	_halo.global_position = head
	_rain.global_position = head + Vector2(0.0, 6.0)
	_sparkle.global_position = buddy.get_interaction_rect().get_center()
	_emitting(_rain, true)
	_emitting(_sparkle, true)
	var fx := _fx()
	if fx:
		fx.ring(head, 40.0, WorldFX.GOLD, 0.3, 2.0)
		fx.burst(head, &"star", WorldFX.GOLD, 6 + 2 * _tier(), 140.0, 0.8)
	AudioManager.play(&"bless", 0.03, -6.0)
	_face(&"blessed", head)
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	set_process(true)
	_update_input()

## When the next blessing can be given, for the suite.
func recast_msec() -> int:
	return _recast_msec

func _spell_deactivated(_was_held: bool) -> void:
	_end()

func _process(_delta: float) -> void:
	var buddy := _buddy()
	var now := Time.get_ticks_msec()
	if _until_msec == 0 or now >= _until_msec or buddy == null:
		_end()
		return
	var head := _head(buddy)
	# A slow bob, on whole pixels.
	_halo.global_position = (head + Vector2(0.0, sin(float(now) / 320.0) * 2.0)).round()
	if _rain:
		_rain.global_position = head + Vector2(0.0, 6.0)
		_sparkle.global_position = buddy.get_interaction_rect().get_center()
	if now >= _next_flush_msec:
		_next_flush_msec += int(flush_seconds * 1000.0)
		# Only while the halo is over *him*: one that has lost him mid-knockout pays nothing.
		if _reachable(buddy):
			EventBus.kindness_sustained.emit(item_id,
				halo_rate * flush_seconds * effective_damage_mult(), head)
			_face(&"blessed", head)

func _end() -> void:
	if _until_msec == 0:
		set_process(false)
		_update_input()
		return
	_until_msec = 0
	if _halo:
		_halo.visible = false
		var fx := _fx()
		if fx:
			fx.puff(_halo.global_position, 5, WorldFX.GOLD, 40.0, 0.5)
	_emitting(_rain, false)
	_emitting(_sparkle, false)
	set_process(false)
	_update_input()

## Just above his skull, which is the top of his real box.
func _head(buddy: Buddy) -> Vector2:
	var rect := buddy.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y - 16.0)

func _build() -> void:
	if _halo != null:
		return
	_halo = Sprite2D.new()
	_halo.name = "Halo"
	_halo.texture = halo_texture
	_halo.scale = Vector2(2, 2)
	_halo.z_index = 31
	_halo.visible = false
	add_child(_halo)
	var tier := _tier()
	# Hearts that fall from the halo over him: the one kind effect in the game that rains
	# rather than rises.
	_rain = _emitter("HeartRain", UIStyle.glyph(&"heart"), WorldFX.kind_colour(tier), 9 + 2 * tier,
		1.2, 150.0, 30.0, Vector2(26, 3), 1.0, 1.5)
	_rain.process_material.set(&"direction", Vector3(0, 1, 0))
	# And a gold shimmer over the whole of him, the look of being blessed rather than rained on.
	_sparkle = _emitter("HaloSparkle", UIStyle.glyph(&"star"), WorldFX.GOLD, 6 + 2 * tier, 0.9,
		-20.0, 16.0, Vector2(34, 46), 0.6, 1.0, true)
