class_name ItemSpawner
extends Node

## Turns `spawn_requested` into actual nodes, and owns the item limit.
##
## A node rather than an autoload because it needs a parent to instance into. It tags
## everything it creates into groups (`spawned_item`, and `interactive` via BaseDraggable)
## which is how the trash bin, the world bounds and the item counter find things without
## a single node path (docs/decisions.md D9).

const GROUP_SPAWNED := &"spawned_item"

## Fraction of the window to drop things at when no position is given. A fraction rather
## than the prototype's fixed (600, 100), which is outside the window entirely in a small
## play area.
const DEFAULT_SPAWN_FRACTION := Vector2(0.5, 0.2)

signal item_count_changed(count: int, limit: int)

## Where spawned bodies are parented. Set by main.gd.
@export var world: Node2D

var _active: Array[Node2D] = []
## Cursor powers are instanced once and kept — they are a mode, not an object.
var _powers: Dictionary = {}  ## StringName -> CursorPowerBase
var _active_power: StringName = &""

func _ready() -> void:
	EventBus.spawn_requested.connect(_on_spawn_requested)
	EventBus.item_despawned.connect(_on_item_despawned)
	EventBus.prestige_performed.connect(_on_prestige)

## A Reincarnation wipes what the player owns, so it has to wipe what is on the desk too.
##
## Without this the equipped cursor power kept firing at full damage and full payout after
## the reset — Progression had forgotten the pistol, ItemSpawner had not — and every weapon
## already lying on screen stayed a usable weapon carrying its pre-prestige augment
## multipliers. The shop meanwhile correctly re-priced all of it as unowned.
func _on_prestige(_marrow: float) -> void:
	if _active_power != &"":
		_active_power = &""
		EventBus.cursor_power_changed.emit(&"")
	for node in _active.duplicate():
		if is_instance_valid(node):
			EventBus.item_despawned.emit(node)
			node.queue_free()
	_active.clear()
	item_count_changed.emit(0, item_limit())

## Everything on the desk, gone. The HUD's item counter is the button for it.
##
## Same path as a prestige wipe rather than a second one: the despawn signal is what keeps
## the counter, the friendly items' banked kindness and anything else watching in step.
func clear_desk() -> int:
	var cleared := 0
	for node in _active.duplicate():
		if not is_instance_valid(node):
			continue
		# Asked rather than freed behind its back. Duck-typed because `_active` holds whatever
		# was spawned and not everything on the desk is a BaseDraggable.
		if node.has_method("bin_myself"):
			node.bin_myself()
		else:
			EventBus.item_despawned.emit(node)
			node.queue_free()
		cleared += 1
	_active.clear()
	item_count_changed.emit(0, item_limit())
	return cleared

func item_count() -> int:
	_prune()
	return _active.size()

## Base limit plus whatever the Mastery Pool checkpoints have granted. Read live rather
## than cached: a checkpoint can land mid-session, and a limit that only grows on restart
## is a reward the player never sees arrive.
func item_limit() -> int:
	return ItemDB.balance.item_limit + Progression.item_limit_bonus()

func active_power() -> StringName:
	return _active_power

## The live instance of a cursor power, or null if it has never been equipped. Powers are
## instanced lazily and kept, so this is also how anything else reaches one without a path.
func get_power(item_id: StringName) -> CursorPowerBase:
	var power = _powers.get(item_id)
	return power if is_instance_valid(power) else null

# --- requests --------------------------------------------------------------

func _on_spawn_requested(item_id: StringName, at: Vector2) -> void:
	var item := ItemDB.get_item(item_id)
	if item == null:
		push_warning("ItemSpawner: unknown item '%s'" % item_id)
		return
	if not Progression.is_unlocked(item_id):
		return
	if item.is_cursor_power():
		_toggle_power(item)
	else:
		_spawn_body(item, at)

## Only one power can be live at a time. Each power enforces that on itself by listening
## to the bus, so this only has to say which one is current.
func _toggle_power(item: ItemData) -> void:
	_ensure_power(item)
	_active_power = &"" if _active_power == item.id else item.id
	EventBus.cursor_power_changed.emit(_active_power)

func _ensure_power(item: ItemData) -> void:
	if _powers.has(item.id) and is_instance_valid(_powers[item.id]):
		return
	if item.scene == null:
		push_error("ItemSpawner: cursor power '%s' has no scene" % item.id)
		return
	var power := item.scene.instantiate()
	if not (power is CursorPowerBase):
		push_error("ItemSpawner: '%s' is not a CursorPowerBase" % item.id)
		power.queue_free()
		return
	(power as CursorPowerBase).item_id = item.id
	_host().add_child(power)
	_powers[item.id] = power

func _spawn_body(item: ItemData, at: Vector2) -> void:
	_prune()
	if _active.size() >= item_limit():
		# Oldest out. Silently refusing is worse: the player clicks and nothing happens.
		var oldest := _active.pop_front() as Node2D
		if is_instance_valid(oldest):
			EventBus.item_despawned.emit(oldest)
			oldest.queue_free()

	var node := item.scene.instantiate() as Node2D
	if node == null:
		push_error("ItemSpawner: '%s' scene is not a Node2D" % item.id)
		return
	# Stamped here as well as in the scene, so an item whose scene forgot its id still
	# attributes damage, mastery and augments correctly.
	if node is BaseDraggable:
		(node as BaseDraggable).item_id = item.id
	node.add_to_group(GROUP_SPAWNED)

	var host := _host()
	host.add_child(node)
	node.global_position = at if at != Vector2.ZERO else _default_position()

	_active.append(node)
	EventBus.item_spawned.emit(node)
	item_count_changed.emit(_active.size(), item_limit())

# --- bookkeeping -----------------------------------------------------------

func _on_item_despawned(node: Node2D) -> void:
	_active.erase(node)
	item_count_changed.emit(_active.size(), item_limit())

## Freed items used to leave their slot occupied forever, so a player who binned ten
## things could never spawn anything again.
func _prune() -> void:
	var before := _active.size()
	_active = _active.filter(func(n: Node2D) -> bool: return is_instance_valid(n))
	if _active.size() != before:
		item_count_changed.emit(_active.size(), item_limit())

func _default_position() -> Vector2:
	return get_viewport().get_visible_rect().size * DEFAULT_SPAWN_FRACTION

func _host() -> Node:
	return world if world != null else get_parent()

## Re-applies augment levels to everything already on screen, so a Weight upgrade bought
## with the bat in hand is felt on the next swing rather than the next spawn.
func refresh_augments() -> void:
	_prune()
	for node in _active:
		if node is WeaponBase:
			(node as WeaponBase).apply_augments()
