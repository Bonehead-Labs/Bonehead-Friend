extends Node

## Headless walk of the M2 gate loop: hit -> earn -> buy -> augment -> save -> reload.
##
##   Godot --headless --path <project> res://tests/integration/loop_check.tscn
##
## A scene rather than a `-s` script, because the whole point is to exercise the autoloads
## — Economy, Progression and ItemDB are exactly what `-s` cannot reach, and they are
## where a regression in the payout chain would actually live.
##
## It runs against its own save slot and deletes it afterwards, so it never touches the
## save of whoever is running it. Exits non-zero on the first failure.

const TEST_SLOT := "loop_check_slot"

var _passed := 0
var _failed := 0

## Hits observed on the bus during the physics check, so the assertion is about what the
## contact solver actually produced rather than about a balance that other tests move.
var _observed: Array[HitInfo] = []

func _ready() -> void:
	# Focus Mode OFF silences AudioManager and FXLayer for the run. This check is about
	# the economy, and the headless dummy audio driver hands its stream playbacks back
	# after the engine's leak check has already run — which reports them as leaks and
	# would mask a real one.
	Settings.focus_intensity = Settings.Intensity.OFF

	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	# Start from a clean sheet rather than whatever the previous run left in memory.
	SaveManager.load_game()

	print("")
	print("Bonehead Friend — loop check")
	print("============================")

	_content_loaded()
	_starters_are_owned()
	var earned := _hitting_him_pays()
	_augments_change_the_payout(earned)
	_shop_refuses_what_you_cannot_afford()
	_spawning_and_the_item_limit()
	_knockout_pays_and_resets()
	await _real_physics_produces_hits()
	await _save_survives_a_restart()

	print("")
	print("============================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

# --- the loop --------------------------------------------------------------

func _content_loaded() -> void:
	_suite("content")
	_check("items loaded from res://Data", ItemDB.all_items().size() >= 7)
	_check("balance loaded", ItemDB.balance != null and ItemDB.balance.mood_curve != null)
	_check("the bat exists", ItemDB.get_item(&"baseball_bat") != null)
	_check("the bat has a three-node tree", ItemDB.augments_for(&"baseball_bat").size() == 3)
	_check("every item has a scene or is a power", ItemDB.all_items().all(
		func(i: ItemData) -> bool: return i.scene != null))

func _starters_are_owned() -> void:
	_suite("starters")
	# Free items are granted on every load, so adding one later needs no save migration.
	_check("bat is owned from boot", Progression.is_unlocked(&"baseball_bat"))
	_check("grenade is owned from boot", Progression.is_unlocked(&"grenade"))
	_check("fist is owned from boot", Progression.is_unlocked(&"fist"))
	_check("the mace is not free", not Progression.is_unlocked(&"mace"))

## Returns the Bones a single reference hit is worth, for the augment comparison.
func _hitting_him_pays() -> float:
	_suite("hit -> earn")
	var before := Economy.balance_of(Economy.BONES)
	var damage := 40.0
	EventBus.damage_dealt.emit(HitInfo.new(damage, &"baseball_bat", Vector2(100, 100), 4000.0))
	var earned := Economy.balance_of(Economy.BONES) - before

	var expected := damage * ItemDB.balance.bones_per_damage * Economy.mood_multiplier()
	_check("a hit pays Bones", earned > 0.0)
	_check("payout matches the documented chain", is_equal_approx(earned, expected))
	_check("lifetime tracks the payout", Economy.lifetime_of(Economy.BONES) >= earned)
	_check("round damage banked for the knockout", Economy.round_damage >= damage)
	return earned

func _augments_change_the_payout(base_payout: float) -> void:
	_suite("buy -> augment")
	# Enough for a few levels, granted rather than farmed so the check stays fast.
	Economy.grant(Economy.BONES, 5000.0)

	var cost := Progression.next_augment_cost(&"bat_payout")
	var wallet := Economy.balance_of(Economy.BONES)
	var bought := Progression.purchase_augment(&"bat_payout", 1)
	_check("one level bought", bought == 1)
	_check("level recorded", Progression.augment_level(&"bat_payout") == 1)
	_check("wallet charged exactly the quoted cost",
		is_equal_approx(Economy.balance_of(Economy.BONES), wallet - cost))

	var node := ItemDB.get_augment(&"bat_payout")
	_check("modifier reflects the purchase",
		is_equal_approx(Progression.get_modifier(&"baseball_bat", &"payout_mult"), node.effect_per_level))
	_check("other items are unaffected",
		is_equal_approx(Progression.get_modifier(&"mace", &"payout_mult"), 1.0))

	# The same hit must now pay more. This is the whole gate in one assertion.
	var before := Economy.balance_of(Economy.BONES)
	EventBus.damage_dealt.emit(HitInfo.new(40.0, &"baseball_bat", Vector2(100, 100), 4000.0))
	var after_augment := Economy.balance_of(Economy.BONES) - before
	_check("the same hit now pays more", after_augment > base_payout)
	_check("it pays exactly the augment's multiple",
		is_equal_approx(after_augment, base_payout * node.effect_per_level))

	var bulk := Progression.purchase_augment(&"bat_damage", 10)
	_check("bulk buy is capped by the wallet, not by max_levels", bulk >= 1 and bulk <= 10)

func _shop_refuses_what_you_cannot_afford() -> void:
	_suite("shop rules")
	var mace := ItemDB.get_item(&"mace")
	while Economy.balance_of(Economy.BONES) > 0.0:
		Economy.spend(Economy.BONES, Economy.balance_of(Economy.BONES))
	_check("broke cannot buy the mace", not Progression.purchase_item(&"mace"))
	_check("and does not own it", not Progression.is_unlocked(&"mace"))

	Economy.grant(Economy.BONES, float(mace.cost))
	_check("exactly enough buys it", Progression.purchase_item(&"mace"))
	_check("and it is now owned", Progression.is_unlocked(&"mace"))
	_check("buying twice is refused", not Progression.purchase_item(&"mace"))
	_check("the price was actually deducted", Economy.balance_of(Economy.BONES) < 1.0)

func _spawning_and_the_item_limit() -> void:
	_suite("spawning")
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if spawner == null:
		_check("item spawner present", false)
		return

	for i in ItemDB.balance.item_limit + 3:
		EventBus.spawn_requested.emit(&"baseball_bat", Vector2(200, 100))
	_check("item limit holds", spawner.item_count() <= ItemDB.balance.item_limit)

	EventBus.spawn_requested.emit(&"fist", Vector2.ZERO)
	_check("cursor power equips", spawner.active_power() == &"fist")
	EventBus.spawn_requested.emit(&"fist", Vector2.ZERO)
	_check("cursor power toggles back off", spawner.active_power() == &"")
	_check("an unowned power cannot be equipped", not _try_equip(&"pistol", spawner))

func _try_equip(item_id: StringName, spawner: ItemSpawner) -> bool:
	EventBus.spawn_requested.emit(item_id, Vector2.ZERO)
	return spawner.active_power() == item_id

func _knockout_pays_and_resets() -> void:
	_suite("knockout")
	Economy.round_damage = 400.0
	var before := Economy.balance_of(Economy.BONES)
	EventBus.buddy_state_changed.emit(&"knockout")
	_check("knockout pays a bonus", Economy.balance_of(Economy.BONES) > before)
	_check("round damage resets", Economy.round_damage == 0.0)

## The one piece that cannot be checked with a synthetic signal: whether
## _integrate_forces turns a real collision into a real HitInfo. This is the correction
## D7 exists for, so it is worth simulating rather than trusting.
func _real_physics_produces_hits() -> void:
	_suite("contact impulse")
	var buddy := get_tree().get_first_node_in_group(&"buddy") as Buddy
	if buddy == null:
		_check("buddy present", false)
		return

	# The item-limit section left ten bats hanging in the air (nothing had stepped the
	# physics yet). Letting them rain down would knock him out mid-measurement and every
	# assertion after that would be about a buddy who is already down.
	_clear_spawned()
	_observed.clear()
	EventBus.damage_dealt.connect(_observe)

	# Drop him onto the scene's own floor. WorldBounds is deliberately NOT in this scene:
	# it derives the walls from the viewport, and a headless viewport is 64x64, so the
	# generated box would sit inside the buddy rather than under him.
	buddy.health.reset_meter()
	buddy.global_position = Vector2(320, 100)
	buddy.linear_velocity = Vector2.ZERO
	buddy.angular_velocity = 0.0
	for i in 90:
		await get_tree().physics_frame
	_check("a real collision produced a hit", not _observed.is_empty())
	_check("the impulse cleared the damage floor", _observed.any(
		func(h: HitInfo) -> bool: return h.raw_impulse >= ItemDB.balance.min_damage_impulse))
	_check("world contact is attributed, not anonymous", _observed.any(
		func(h: HitInfo) -> bool: return h.source_id != &""))

	# Now a weapon, to prove attribution reaches the item id the augments are keyed on.
	_observed.clear()
	buddy.health.reset_meter()
	buddy.linear_velocity = Vector2.ZERO
	EventBus.spawn_requested.emit(&"mace", buddy.global_position + Vector2(6, -300))
	for i in 120:
		await get_tree().physics_frame
	_check("a dropped weapon is attributed to its item id", _observed.any(
		func(h: HitInfo) -> bool: return h.source_id == &"mace"))

	# A missile strike: a cursor power, a kinematic projectile and a blast, all landing on
	# the same receiver-side path a bat swing uses.
	# Wait out any knockout still in flight from the mace. Its coroutine ends in
	# _return_home(), which would teleport him out from under the missile mid-measurement.
	while buddy.health.down:
		await get_tree().physics_frame
	_observed.clear()
	_clear_spawned()
	buddy.health.reset_meter()
	Economy.grant(Economy.BONES, float(ItemDB.get_item(&"missile").cost))
	_check("the missile can be bought", Progression.purchase_item(&"missile"))
	EventBus.spawn_requested.emit(&"missile", Vector2.ZERO)
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	var power := spawner.get_power(&"missile") if spawner else null
	_check("the missile power instantiates", power != null)
	if power:
		power.fire(buddy.global_position)
		for i in 150:
			await get_tree().physics_frame
		_check("a missile strike damages him", not _observed.is_empty())
		_check("and is attributed to the missile", _observed.any(
			func(h: HitInfo) -> bool: return h.source_id == &"missile"))

	# Resting contact must not farm. He is settled on the floor by now.
	_clear_spawned()
	buddy.health.reset_meter()
	_observed.clear()
	for i in 120:
		await get_tree().physics_frame
	_check("resting contact does not farm damage", _observed.size() <= 1)

	EventBus.damage_dealt.disconnect(_observe)

func _observe(info: HitInfo) -> void:
	_observed.append(info)

func _clear_spawned() -> void:
	for node in get_tree().get_nodes_in_group(&"spawned_item"):
		if is_instance_valid(node):
			EventBus.item_despawned.emit(node)
			node.queue_free()

func _save_survives_a_restart() -> void:
	_suite("save -> reload")
	Economy.grant(Economy.BONES, 1234.0)
	var bones := Economy.balance_of(Economy.BONES)
	var damage_levels := Progression.augment_level(&"bat_damage")
	_check("save written", SaveManager.save_game())

	# Simulate a restart: wipe the live state, then load it back.
	Economy.from_save({})
	Progression.from_save({})
	_check("state actually cleared", Economy.balance_of(Economy.BONES) == 0.0)
	await get_tree().process_frame

	SaveManager.load_game()
	_check("Bones restored", is_equal_approx(Economy.balance_of(Economy.BONES), bones))
	_check("augment levels restored", Progression.augment_level(&"bat_damage") == damage_levels)
	_check("purchased items restored", Progression.is_unlocked(&"mace"))
	_check("starters still granted after a reload", Progression.is_unlocked(&"baseball_bat"))
	_check("modifier cache rebuilt from the loaded save",
		Progression.get_modifier(&"baseball_bat", &"payout_mult") > 1.0)

# --- harness ---------------------------------------------------------------

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _suite(name_: String) -> void:
	print("")
	print("  %s" % name_)

func _check(what: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("    ok   %s" % what)
	else:
		_failed += 1
		printerr("    FAIL %s" % what)
