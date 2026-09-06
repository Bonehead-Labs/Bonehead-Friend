class_name ClusterBomb
extends ThrowableBase

## One charge that becomes several: the casing goes off where it landed and throws a burst
## of smaller blasts around it, each of them its own hit down the same receiver-side damage
## path a bat swing uses (docs/decisions.md D7).
##
## **Three items share this class and only the numbers separate them** (D8). `spread` and
## `submunition_interval` between them cover the whole "many small bangs" family:
##
##   nail bomb       wide spread, almost no interval — one shotgun blast of tiny charges
##   cluster bomb    wide spread, a short beat      — the casing opens and they walk outwards
##   napalm charge   almost no spread, a long interval — a burning patch of desk that keeps
##                   paying for as long as he is standing in it
##
## Why the family exists at all: a single hit is capped at
## `knockout_damage x max_hit_fraction`, half a knockout, so the top of the explosives ladder
## cannot escalate by hitting harder. It escalates by hitting *more times* and reaching
## further, and this is the class that does the first of those.
##
## The submunitions are shape queries against the physics space, not spawned bodies. A real
## sub-charge would have to be built, parented, drawn and freed fourteen times for one napalm
## charge, and it would sit in desk slots the player paid for.

## How many blasts follow the casing's own, and how far apart in time.
@export var submunitions: int = 5
@export var submunition_interval: float = 0.14

## Scatter radius in world units, around wherever the casing came to rest.
@export var spread: float = 150.0

@export var submunition_radius: float = 110.0
@export var submunition_force: float = 8000.0

var _burst := false

func explode() -> void:
	if _burst:
		return
	_burst = true

	if explosion_area:
		_report(ExplosionUtil.apply_blast(explosion_area, global_position, max_force),
			global_position)
		explosion_area.monitoring = false
	if Effects_Player:
		Effects_Player.explosion_effect(global_position, 1.0 + 0.25 * juice_tier)

	# The casing stops being an object on the desk here rather than at the end of the burst.
	# A napalm charge burns for six seconds, and the slot the player spent on it should come
	# back when the thing they threw stops existing, not when it stops paying.
	if sprite:
		sprite.visible = false
	# Dropped before it is frozen. The base class can leave a drag joint attached because
	# it frees itself half a second later; a napalm charge burns for six, and that is six
	# seconds of an invisible frozen body pinned to a handle still chasing the cursor.
	if dragging:
		_end_drag()
	freeze = true
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	if drag_area:
		drag_area.set_deferred(&"monitoring", false)
	EventBus.item_despawned.emit(self)

	# One physics frame before the first submunition, whatever the interval: the casing's
	# own blast has just been applied, and the next blast should measure its distances
	# against where that one put everything. Bound methods rather than awaits throughout: the
	# player can bin a burning charge and the desk can be cleared under it, and a coroutine
	# resumed on a freed instance errors before any guard inside it runs, where a Callable
	# bound to the node is simply dropped with it.
	get_tree().physics_frame.connect(_begin_scatter, CONNECT_ONE_SHOT)

var _scatter_origin := Vector2.ZERO

func _begin_scatter() -> void:
	if not is_inside_tree():
		return
	_scatter_origin = global_position
	_submunition(0)

## Fires submunition `i` and schedules the next, or frees the casing after the last.
func _submunition(i: int) -> void:
	if not is_inside_tree():
		return
	while i < submunitions:
		# sqrt on the radius, or the scatter piles up in the middle: drawing r uniformly
		# over [0, spread] is not drawing uniformly over the disc.
		var at := _scatter_origin + Vector2.RIGHT.rotated(randf() * TAU) * (spread * sqrt(randf()))
		_report(ExplosionUtil.point_blast(get_world_2d().direct_space_state, at,
			submunition_radius, submunition_force), at)
		if Effects_Player:
			Effects_Player.explosion_effect(at, 0.6 + 0.15 * juice_tier)
		i += 1
		if i < submunitions and submunition_interval > 0.0:
			get_tree().create_timer(submunition_interval).timeout.connect(_submunition.bind(i))
			return
	queue_free()

## Hands each blast home the way a grenade's does: the impulse it actually applied, reported
## to the receiver, which decides what it costs him. Never a second damage model.
func _report(hits: Array[Dictionary], at: Vector2) -> void:
	var mult := effective_damage_mult()
	for hit in hits:
		var body: Node = hit["body"]
		if body is Buddy:
			(body as Buddy).take_impulse(float(hit["impulse"]), item_id, mult, at)
