class_name ThrowableBase
extends BaseDraggable

## Grenades and dynamite: prime with right-click while dragging, explode after a delay.
##
## The blast applies a real impulse to everything in range and reports that impulse to
## Bonehead through the same receiver-side path a bat swing uses, so explosives need no
## damage model of their own.

@export var damage_mult: float = 1.0
@export var throwable_delay: float = 3.0
@export var explosion_area: Area2D
@export var max_force: float = 10000.0

var is_primed: bool = false

## Right-click primes the fuse, so the base class must not spend it on despawning.
func right_click_is_mine() -> bool:
	return true

func _ready() -> void:
	super._ready()
	if explosion_area:
		explosion_area.monitoring = false

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if is_primed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and dragging:
		prime_explosion()

func prime_explosion() -> void:
	if is_primed:
		return
	is_primed = true
	if explosion_area:
		explosion_area.monitoring = true
	# The fuse is lit: he can see it too.
	EventBus.threat_changed.emit(&"fuse", global_position, 1.0)
	# And so can the player: sparks off the fuse until it goes, more for an upgraded charge.
	var fx := WorldFX.of(self)
	if fx:
		var fuse := fx.aura(self, &"chip", WorldFX.HEAT, 4 + 2 * juice_tier, "Fuse", Vector2(3, 3))
		fuse.position = grip_offset
		fuse.lifetime = 0.5
	if sprite:
		# Simple readable tell that it is live; the fuse animation lands with the art pass.
		var tween := create_tween().set_loops()
		tween.tween_property(sprite, "modulate", Color(1.6, 0.6, 0.6), throwable_delay * 0.25)
		tween.tween_property(sprite, "modulate", Color.WHITE, throwable_delay * 0.25)
	# A bound method, not an `await`. The player can bin a primed grenade before it goes off,
	# and a coroutine resumed on a freed instance prints "Resumed function after await, but
	# script is gone" before any guard inside it can run; a Callable bound to the node is
	# simply dropped when the node dies.
	get_tree().create_timer(throwable_delay).timeout.connect(explode)

func explode() -> void:
	# An explosive's "use" is the detonation, not the hit: one that went off in an empty
	# corner of the desk was still spent, and the mine and the firework — which cannot be
	# aimed at all — would otherwise count only their lucky days. Emitted here rather than
	# from Bonehead's attribution step, which sees only the blasts that reached him.
	if item_id != &"":
		EventBus.contract_event.emit(&"use:%s" % item_id, 1)
	# Before the blast, so a flinch at the bang is not overwritten by the hit a frame later.
	EventBus.threat_changed.emit(&"fuse", global_position, 0.0)
	_retire()
	if explosion_area:
		for hit in ExplosionUtil.apply_blast(explosion_area, global_position, max_force):
			var body: Node = hit["body"]
			if body is Buddy:
				(body as Buddy).take_impulse(float(hit["impulse"]), item_id,
					effective_damage_mult(), global_position)
		explosion_area.monitoring = false
	if Effects_Player:
		Effects_Player.explosion_effect(global_position, 1.0 + 0.25 * juice_tier)
	if sprite:
		sprite.visible = false
	EventBus.item_despawned.emit(self)
	get_tree().create_timer(0.5).timeout.connect(queue_free)

## What is left of the charge stops being a body, before its own blast goes off.
##
## The blast area masks the item layer — it has to, to throw the rest of the desk about — so
## it reports the charge that owns it. At zero distance `ExplosionUtil` falls back to straight
## up at the undiminished `max_force`, and the hidden casing then spent the half second before
## it freed itself as an invisible projectile, still colliding: 6,878 px/s measured on a grenade,
## and 18,571 by the same arithmetic on the concussion charge — faster per frame than a wall is
## thick (D59).
## Frozen, it takes no impulse; with no layers it touches nothing on the way out; and with no
## pickable grab region it cannot be picked up, binned or stand in a power's way while hidden.
func _retire() -> void:
	if dragging:
		_end_drag()
	freeze = true
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	if drag_area:
		drag_area.set_deferred(&"input_pickable", false)

func effective_damage_mult() -> float:
	return Progression.damage_mult_for(item_id, damage_mult)
