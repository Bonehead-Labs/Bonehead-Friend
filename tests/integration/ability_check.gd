extends Node

## Every held weapon's ability, used the way a player uses it, on a desk of its own (D74).
##
##   Godot --headless --path <project> res://tests/integration/ability_check.tscn
##   ... ability_check.tscn -- --only=baseball_bat,katana      (a subset, while working)
##   ... ability_check.tscn -- --faces                          (the beat he wore at each event)
##
## For every row in `AbilityTable` — enumerated, never listed — a fresh desk in a 1280x720
## SubViewport (the real `WorldBounds`, `ItemSpawner` and `WorldFX`, one buddy), a fresh save, the
## weapon bought through the shop's own path, and then synthetic input at real positions: the
## weapon picked up by its grab region, swung through him once the ordinary way to measure an
## ordinary hit, carried to where its ability wants it, and worked with the right button — pressed,
## held, let go — exactly as the row's `controls` line says. Then:
##
##   - it does nothing while the weapon lies on the desk, and right on it there still bins it;
##   - held, right is its own and Shift+right still bins it;
##   - its effect, measured: a launch, a lunge and a cut, a daze, a grind, a wave, a ball, a whirl,
##     a throw that comes back to the hand;
##   - every hit it causes is billed by him at a multiplier the data allows, and paid through the
##     real pipeline to the unit (the probe reads the multipliers inside Economy's grant, before
##     his mood and grime move — CLAUDE.md, signal handler order);
##   - his face answers it with the row the brain maps it to;
##   - a second press inside the cooldown is refused and does not bin the weapon, and it is ready
##     again when the cooldown says;
##   - nothing of it runs at rest, and nothing is left behind when the weapon is binned;
##   - what one use paid, in ordinary hits of the same weapon, is not more than half again what the
##     row's `worth` tells `pacing_sim` it pays.
##
## Real-time physics like item_check: every wait is a physics frame. Its own save slot and settings
## file, from the first line (D51).

const TEST_SLOT := "ability_check_slot"
const SETTINGS_PATH := "user://settings_ability_check.cfg"
const VIEW_SIZE := Vector2i(1280, 720)
const HOME := Vector2(640, 657)
const BUDDY := preload("res://Scenes/Buddy/buddy.tscn")
## How far a measured "worth" may run past the row's before the row is understating (x1.5).
const WORTH_SLACK := 1.5

var _passed := 0
var _failed := 0
var _view: SubViewport
var _stage: Node2D
var _spawner: ItemSpawner
var _buddy: Buddy
var _catch: Catch
var _mouse := Vector2.ZERO
var _held := 0

## The weapon under test, and what it did.
var _id: StringName = &""
var _hits: Array[HitInfo] = []
var _pending := {}
var _pipeline_bad: Array[String] = []
var _faces: Array = []
var _report: Array[String] = []

class Catch extends Logger:
	var _mutex := Mutex.new()
	var _lines: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		_mutex.lock()
		_lines.append("%s %s %s (%s:%d %s)" % [kind, code, rationale, file.get_file(), line, function])
		_mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		if not error:
			return
		_mutex.lock()
		_lines.append(message.strip_edges())
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _lines
		_lines = PackedStringArray()
		_mutex.unlock()
		return out

func _ready() -> void:
	# Its own preferences file, first (D51).
	Settings.config_path = SETTINGS_PATH
	# Normal: the pip, the emitters and his Normal-gated rows are part of what is checked. Sound is
	# muted instead of switched off, as in item_check — the dummy driver's finished playbacks read
	# as leaks at exit.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	AudioManager._set_muted(true)
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()
	_catch = Catch.new()
	OS.add_logger(_catch)
	EventBus.payout.connect(_on_payout)
	EventBus.damage_dealt.connect(_on_damage)

	_view = SubViewport.new()
	_view.name = "Desk"
	_view.size = VIEW_SIZE
	_view.handle_input_locally = true
	_view.physics_object_picking = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_view.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)

	print("")
	print("Bonehead Friend — ability check")
	print("===============================")
	_the_table_is_whole()

	var only := _only()
	for id in AbilityTable.item_ids():
		if not only.is_empty() and not only.has(String(id)):
			continue
		await _check_ability(id)

	print("")
	print("  measured")
	for line in _report:
		print("    %s" % line)
	print("")
	print("===============================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	OS.remove_logger(_catch)
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

func _only() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--only="):
			return String(arg).trim_prefix("--only=").split(",", false)
	return PackedStringArray()

# --- the table ----------------------------------------------------------------------------

func _the_table_is_whole() -> void:
	_suite("the table")
	for archetype in AbilityTable.ARCHETYPES:
		var script := load(AbilityTable.ARCHETYPES[archetype]) as Script
		var probe = script.new() if script else null
		_check("the %s archetype loads and is a WeaponAbility" % archetype, probe is WeaponAbility)
		if probe:
			probe.free()
	var names := {}
	for id in AbilityTable.item_ids():
		var row := AbilityTable.row_for(id)
		var item := ItemDB.get_item(id)
		_check("%s is an item in the melee drawer" % id,
			item != null and item.category == ItemData.CATEGORY_WEAPON)
		_check("%s names an archetype the table knows" % id,
			AbilityTable.ARCHETYPES.has(StringName(row.get("archetype", &""))))
		for key in ["id", "name", "controls", "cooldown", "busy", "worth"]:
			_check("%s's row has %s" % [id, key], row.has(key))
		var line := String(row.get("controls", ""))
		_check("%s's line teaches it (%s)" % [id, line],
			line.begins_with("Hold · Right: %s — " % row.get("name", "")))
		_check("and the shop carries that line", item != null and item.controls == line)
		_check("%s's ability has a name of its own" % id, not names.has(row.get("id", &"")))
		names[row.get("id", &"")] = true

# --- one weapon -------------------------------------------------------------------------------

func _check_ability(id: StringName) -> void:
	var row := AbilityTable.row_for(id)
	_suite("%s — %s (%s)" % [id, row.get("name", ""), row.get("archetype", "")])
	_id = id
	_clear_slot()
	SaveManager.load_game()
	await _build_stage()
	_own(id)
	_catch.take()
	seed(hash(String(id)))
	var body := await _spawn(id, _centre() + Vector2(-260.0, -150.0))
	if body == null:
		_check("%s spawns" % id, false)
		await _free_stage()
		return
	var ability := body.ability
	var archetype := StringName(row.get("archetype", &""))
	_check("it carries its ability, the %s archetype" % archetype,
		ability != null and ability.archetype() == archetype and ability.row == row)
	if ability == null:
		await _free_stage()
		return

	# --- lying on the desk -------------------------------------------------------------
	await _await_still(body, 60)
	_check("at rest nothing of it runs", not ability.is_busy())
	_check("right on it lying there is still the bin",
		not body.right_click_is_mine() and body.click_would_bin(false) and body.click_would_bin(true))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	_check("a right press on it unheld is not the ability", not ability.take(press) and ability.uses == 0)

	# --- in the hand -------------------------------------------------------------------
	if not await _grab(body):
		_check("its grab region takes a click", false)
		await _free_stage()
		return
	_check("held, right is its own and Shift+right is still the bin",
		body.right_click_is_mine() and not body.click_would_bin(false) and body.click_would_bin(true))
	# An ordinary swing first, to know what an ordinary hit of this weapon is worth.
	_buddy.health.reset_meter()
	var ordinary := await _ordinary_hit(body)
	_check("an ordinary swing lands (%.1f a hit)" % ordinary, ordinary > 0.0)
	await _mouse_to(_centre() + Vector2(-260.0, -60.0), 900.0)
	await _steady(body, 60)
	_buddy.health.reset_meter()
	await _settle_him()
	_hits.clear()
	_faces.clear()
	_pipeline_bad.clear()
	var before_uses := ability.uses

	var measured := {}
	# A weapon whose row names a hook of its archetype drives by a method of its own,
	# `_drive_<item id>`, because what the player does with it is not what the archetype's
	# driver does: a bat's middle is aimed, a staple gun is held down, a tyre iron is thrown away
	# from him. A hook with no driver of its own falls back to its archetype's.
	var own := "_drive_%s" % id
	var driver: StringName = &"hook" if row.has("script") and has_method(own) else archetype
	match driver:
		&"hook":
			measured = await Callable(self, own).call(body, ability)
		&"charge":
			measured = await _drive_charge(body, ability as ChargeAbility)
		&"dash":
			measured = await _drive_dash(body, ability as DashAbility)
		&"stun":
			measured = await _drive_stun(body, ability as StunAbility)
		&"sustain":
			measured = await _drive_sustain(body, ability as SustainAbility)
		&"shockwave":
			measured = await _drive_shockwave(body, ability as ShockwaveAbility)
		&"projectile":
			measured = await _drive_projectile(body, ability as ProjectileAbility)
		&"spin":
			measured = await _drive_spin(body, ability as SpinAbility)
		&"throw":
			measured = await _drive_throw(body, ability as ThrowAbility)
		_:
			# A new archetype arrives with its driver here, or this fails by name — the same
			# rule item_check keeps for a class with no row in DRIVERS.
			_check("a driver for the %s archetype — add one before this ability can ship" % archetype,
				false)
			await _free_stage()
			return
	if _gone(body):
		_check("it is still on the desk after its ability", false)
		await _free_stage()
		return
	_check("one use was counted", ability.uses == before_uses + 1)

	# --- what it paid ----------------------------------------------------------------------
	await _step(20)
	_check("every hit was paid through the pipeline to the unit%s"
		% ("" if _pipeline_bad.is_empty() else ": " + _pipeline_bad[0]), _pipeline_bad.is_empty())
	var bad_mult := _bad_multiplier(body)
	_check("every hit it caused carries a multiplier the data allows%s" % bad_mult, bad_mult == "")
	var worth := _extra_damage(body, archetype, ordinary) / maxf(ordinary, 0.01)
	var declared := float(row.get("worth", 0.0))
	_check("one use added %.1f ordinary hits' worth, and the row says %.1f (x%.1f slack)"
		% [worth, declared, WORTH_SLACK], worth <= declared * WORTH_SLACK)

	# --- the cooldown -------------------------------------------------------------------
	if not body.dragging:
		await _grab(body)
	await _await_cond(func() -> bool: return not ability.is_active(), 240)
	_check("its effect ends", not ability.is_active())
	_check("and it is cooling down (%.1f s)" % ability.cooldown_left(), ability.is_cooling())
	var uses := ability.uses
	var refused := ability.denied
	_press(MOUSE_BUTTON_RIGHT)
	await _step(2)
	_release(MOUSE_BUTTON_RIGHT)
	await _step(2)
	_check("a press inside the cooldown is refused", ability.uses == uses and ability.denied == refused + 1)
	_check("and does not throw the weapon away", not _gone(body) and body.dragging)
	var pip := ability.get_node_or_null("AbilityPip") as Node2D
	_check("the pip is drawn by the hand while it cools", pip != null and pip.visible)
	var wait := int((ability.cooldown_left() + 0.3) * 60.0)
	await _await_cond(func() -> bool: return ability.is_ready(), wait + 60)
	_check("it is ready again when the cooldown is up", ability.is_ready())
	_check("and the pip is gone", pip == null or not pip.visible)

	# --- at rest, and away -----------------------------------------------------------------
	_release(MOUSE_BUTTON_LEFT)
	await _await_still(body, 90)
	await _step(4)
	_check("put down and idle, nothing of it runs", not ability.is_busy())
	if await _grab(body):
		_move(_grab_point(body))
		await _step(2)
		_press(MOUSE_BUTTON_RIGHT, true)
		_release(MOUSE_BUTTON_RIGHT, true)
		await _step(3)
		_check("Shift+right in the hand bins it", _gone(body))
	var errors := _catch.take()
	_check("nothing was pushed to the error log%s" % ("" if errors.is_empty() else ": " + errors[0]),
		errors.is_empty())
	await _step(60)
	_check("and nothing of it is left behind", _leftovers() == "")

	measured["ordinary"] = ordinary
	measured["worth"] = worth
	_report.append("%-14s %s" % [id, _format(measured)])
	await _free_stage()

func _format(m: Dictionary) -> String:
	var parts: Array[String] = []
	for key in m:
		var value = m[key]
		parts.append("%s %s" % [key, ("%.2f" % value) if value is float else str(value)])
	return ", ".join(parts)

# --- the eight --------------------------------------------------------------------------------

## Home Run: wound up to full, let go beside him, and the armed hit lands x2.5 and throws him.
func _drive_charge(body: WeaponBase, ability: ChargeAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-120.0, -30.0), 700.0)
	await _steady(body, 40)
	_press(MOUSE_BUTTON_RIGHT)
	await _step(3)
	_check("right held winds it up", ability.is_active() and ability.charge() > 0.0)
	_check("he sees it coming", ability.is_threatening())
	await _step(int(ability.num("charge_seconds", 0.9) * 60.0) + 8)
	_check("a full charge (%.2f)" % ability.charge(), ability.charge() >= 0.99)
	var lever := ability.com_world() - ability.grip_world()
	_check("cocked back, the head away from him (%.0f, %.0f)" % [lever.x, lever.y],
		lever.x < 0.0 and lever.y < 0.0)
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("letting go arms the hit", ability.is_armed() or ability.payoffs > 0)
	# The whip carries the head round; if it met air, the hand follows through, as a player's does.
	var landed := await _await_cond(func() -> bool: return ability.payoffs > 0, 12)
	if not landed:
		await _mouse_to(_centre() + Vector2(160.0, -30.0), 1300.0)
		landed = await _await_cond(func() -> bool: return ability.payoffs > 0, 20)
	_check("the armed hit lands", landed)
	# The hit is dealt on his physics tick after the one that attributed it.
	await _step(3)
	var boosted := _boosted_hits(body, ability.num("hit_mult", 2.5))
	_check("billed at x%.2f on top of its own multiplier" % ability.num("hit_mult", 2.5), boosted >= 1)
	var launch := await _peak_speed(40)
	_check("it throws him (%.0f px/s, %.0f handed over)" % [launch, ability.last_launch],
		launch >= ability.last_launch * 0.6 and ability.last_launch > 0.0)
	_check("and where he comes down is the bat's", _buddy.impacts_claimed_by() == _id \
		or _claimed_seen)
	await _expect_face(&"home_run", &"launched")
	return {"hits": _hits.size(), "launch": launch, "mult": ability.num("hit_mult", 2.5)}

## Iaido: from 200 px off, one press: the hand lunges through him, the blade never touches him,
## and the cut lands 0.3 s later.
func _drive_dash(body: WeaponBase, ability: DashAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-200.0, -20.0), 700.0)
	await _steady(body, 60)
	var start := body.global_position
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	var contact_hits := 0
	var crossed := false
	for i in 50:
		await _step()
		if ability.is_cutting() and body.get_collision_exceptions().has(_buddy):
			crossed = true
		if ability.last_cut > 0.0:
			break
		contact_hits = _hits.size()
	await _step(3)
	_check("the hand lunged (%.0f px)" % ability.last_lunge, ability.last_lunge >= 150.0)
	_check("and the blade went through him without touching him (%d contact hits)" % contact_hits,
		crossed and contact_hits == 0)
	_check("the cut landed after it (%.0f)" % ability.last_cut, ability.last_cut > 0.0)
	var cut := _hit_with_impulse(ability.last_cut)
	_check("billed as exactly that impulse", cut != null)
	await _expect_face(&"sliced", &"sliced")
	var shove := await _peak_speed(20)
	await _await_cond(func() -> bool: return not ability.is_active(), 90)
	_check("the exception comes off once it is clear of him",
		not body.get_collision_exceptions().has(_buddy))
	_check("and the hand is its own again", body.hand_offset == Vector2.ZERO)
	return {"lunge": ability.last_lunge, "blade": ability.last_peak_speed, "cut": ability.last_cut,
		"him": shove, "moved": body.global_position.distance_to(start)}

## BONG: rung, swung into him, and he is dazed; the follow-ups are x1.4 while it lasts.
func _drive_stun(body: WeaponBase, ability: StunAbility) -> Dictionary:
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("right rings it and arms it", ability.is_armed())
	var swings := 0
	while not ability.is_dazed() and swings < 3 and ability.is_active():
		await _sweep_through(900.0, 1300.0)
		swings += 1
	await _step(3)
	_check("the next hit is the BONG and he is dazed", ability.is_dazed())
	_check("billed at x%.2f" % ability.num("bong_mult", 1.5),
		_boosted_hits(body, ability.num("bong_mult", 1.5)) >= 1)
	var stars := _buddy.get_node_or_null("DazeStars")
	_check("stars circle his head", stars is Node2D and (stars as Node2D).is_visible_in_tree())
	await _expect_face(&"dazed", &"dazed")
	var follow := 0
	while ability.is_dazed() and follow < 4:
		await _sweep_through(900.0, 1300.0)
		follow += 1
	_check("the follow-ups while he is dazed are x%.2f (%d)" % [ability.num("bonus_mult", 1.4),
		ability.dazed_hits], ability.dazed_hits == 0 or _boosted_hits(body, ability.num("bonus_mult", 1.4)) >= 1)
	await _await_cond(func() -> bool: return not ability.is_active(), 240)
	await _step(60)
	_check("and when it wears off the stars go", not is_instance_valid(stars) or stars.is_queued_for_deletion())
	return {"hits": _hits.size(), "dazed_hits": ability.dazed_hits, "bong": ability.num("bong_mult", 1.5)}

## Rev: the bar held on him with right down; it grinds a hit a tick until right comes up.
func _drive_sustain(body: WeaponBase, ability: SustainAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-70.0, 0.0), 500.0)
	await _steady(body, 30)
	_press(MOUSE_BUTTON_RIGHT)
	await _step(4)
	_check("right held starts the engine", ability.is_active() and ability.revs() > 0.0)
	# Leaned in, the way a player keeps a saw on something.
	for i in 60:
		_move(_centre() + Vector2(-70.0 + 20.0 * sin(float(i) * 0.2), 0.0))
		await _step()
	_check("it grinds him (%d grinds)" % ability.grinds, ability.grinds >= 3)
	var ticks := 0
	for info in _hits:
		if is_equal_approx(info.raw_impulse, ability.num("grind_force", 380.0)):
			ticks += 1
	_check("each grind billed as its own impulse (%d)" % ticks, ticks >= 3)
	await _expect_face(&"grinding", &"cooking")
	_release(MOUSE_BUTTON_RIGHT)
	await _step(2)
	_check("letting go stops it", not ability.is_active())
	return {"grinds": ability.grinds, "hits": _hits.size(), "rev": ability.peak_rev}

## Ground Pound: held low beside him, one press drives the head into the desk and the desk throws
## him up.
func _drive_shockwave(body: WeaponBase, ability: ShockwaveAbility) -> Dictionary:
	var floor_y := _buddy.get_interaction_rect().end.y
	await _mouse_to(Vector2(_centre().x - 100.0, floor_y - 150.0), 600.0)
	await _steady(body, 90)
	var top := _buddy.global_position.y
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _await_cond(func() -> bool: return ability.last_impact != Vector2.INF or not ability.is_active(), 60)
	_check("the head met the desk (%s)" % ability.last_impact, ability.last_impact != Vector2.INF)
	_check("and the desk threw him (%.0f px/s)" % ability.last_pop, ability.last_pop > 0.0)
	var rise := 0.0
	for i in 40:
		await _step()
		rise = maxf(rise, top - _buddy.global_position.y)
	_check("up (%.0f px)" % rise, rise >= 10.0)
	var wave := _hit_with_impulse(_buddy.mass * ability.last_pop)
	_check("billed as the impulse it handed him", wave != null)
	await _expect_face(&"quaked", &"quaked")
	return {"pop": ability.last_pop, "rise": rise, "lifted": ability.last_lifted, "hits": _hits.size()}

## Drive: teed up at full power from 300 px, the dots run through him and so does the ball.
func _drive_projectile(body: WeaponBase, ability: ProjectileAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-320.0, -40.0), 700.0)
	await _steady(body, 40)
	_press(MOUSE_BUTTON_RIGHT)
	await _step(int(ability.num("charge_seconds", 0.8) * 60.0) + 6)
	_check("held, the power fills (%.2f)" % ability.power(), ability.power() >= 0.99)
	var near := false
	var him := ability.him_world()
	for p in ability.preview_points():
		near = near or p.distance_to(him) <= 50.0
	_check("the dotted arc runs through him", near)
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("letting go drives a ball (%.0f px/s)" % ability.last_speed, ability.balls_in_flight() == 1)
	await _expect_face(&"fore", &"startled")
	var landed := await _await_cond(func() -> bool: return ability.payoffs > 0, 90)
	_check("the ball hits him (%.0f)" % ability.last_strike, landed)
	await _step(3)
	_check("billed once, as its own impulse", _hits_with_impulse(ability.last_strike) == 1)
	return {"speed": ability.last_speed, "ball": ability.last_strike, "hits": _hits.size()}

## Whirlwind: held beside him, one press whirls it through him again and again — the hand
## following him as each blow knocks him on, the way a player chases him with it.
func _drive_spin(body: WeaponBase, ability: SpinAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-95.0, -40.0), 600.0)
	await _steady(body, 30)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	for i in 150:
		if not ability.is_active():
			break
		var want := _centre() + Vector2(-95.0, -40.0)
		_move(_mouse.move_toward(want, 900.0 / 60.0))
		await _step()
	_check("it whirled (%.1f rad/s, %.1f turns)" % [ability.peak_spin, ability.turns],
		ability.peak_spin >= ability.num("spin_rate", 20.0) * 0.7 and ability.turns >= 1.0)
	_check("through him again and again (%d hits)" % ability.spin_hits, ability.spin_hits >= 2)
	_check("and stopped when it said", not ability.is_active())
	return {"spin": ability.peak_spin, "turns": ability.turns, "hits": ability.spin_hits}

## Tomahawk: thrown from 250 px, it hits him, turns and comes back to the hand still holding left.
func _drive_throw(body: WeaponBase, ability: ThrowAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-250.0, -80.0), 700.0)
	await _steady(body, 60)
	var hand := _mouse
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	_check("right throws it out of the hand", not body.dragging and ability.in_flight())
	var hit := await _await_cond(func() -> bool: return ability.throw_hits > 0, 60)
	_check("it hits him (%.0f px/s thrown)" % ability.last_throw_speed, hit)
	await _step(3)
	var chop := _hit_with_impulse(ability.last_hit)
	_check("billed once, as its own impulse at x%.2f (%.0f)" % [ability.num("throw_mult", 1.3), ability.last_hit],
		chop != null and _hits_with_impulse(ability.last_hit) == 1 and absf(_mult_of(chop)
		- Progression.damage_mult_for(_id, body.damage_mult) * ability.num("throw_mult", 1.3)) < 0.01)
	await _expect_face(&"incoming", &"blast")
	var back := await _await_cond(func() -> bool: return not ability.is_active(), 240)
	_check("it comes back (%.2f s)" % ability.last_trip, back)
	_check("and the hand still holding left catches it", ability.caught and body.dragging)
	_check("at the hand", ability.grip_world().distance_to(hand) <= 120.0)
	return {"speed": ability.last_throw_speed, "hits": ability.throw_hits, "trip": ability.last_trip}

# --- the blunt and desk nine (D74, second pass) --------------------------------------------
#
# Each drives its own hook the way its line says, and asserts the thing that makes it itself.

## Bristle: tapped from 180 px, the five spikes facing him fly, the fan lands, the star is bald on
## that side, and they come back one at a time over the cooldown.
func _drive_morning_star(body: WeaponBase, ability: BristleAbility) -> Dictionary:
	# The head hangs below the hand: held here, it is level with his middle and clear of the desk.
	await _mouse_to(_centre() + Vector2(-180.0, -100.0), 700.0)
	await _steady(body, 60)
	var total := ability.spikes_total()
	_check("its picture has spikes to fire (%d found in the art)" % total, total >= 5)
	var shapes := _shape_sizes(body)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	_check("a tap fires the %d spikes facing him" % int(ability.num("spikes", 5)),
		ability.last_fired == int(ability.num("spikes", 5)))
	_check("and the star is bald where they were (%d of %d left)" % [ability.spikes_present(), total],
		ability.spikes_present() == total - ability.last_fired)
	_check("only the picture changed: its colliders are its own", _shape_sizes(body) == shapes)
	await _await_cond(func() -> bool: return ability.shots_in_flight() == 0, 60)
	await _step(3)
	_check("the fan lands on him (%d of %d)" % [ability.last_hits, ability.last_fired], ability.last_hits >= 3)
	_check("each spike billed once, as its own impulse",
		_hits_with_impulse(ability.num("spike_force", 900.0)) == ability.last_hits)
	await _expect_face(&"incoming", &"blast")
	var gap := ability.cooldown_left()
	await _await_cond(func() -> bool: return ability.cooldown_left() <= gap * 0.45, int(gap * 60.0) + 30)
	var midway := ability.spikes_present()
	_check("halfway through the cooldown some have grown back (%d)" % midway,
		midway > total - ability.last_fired and midway < total)
	return {"fired": ability.last_fired, "landed": ability.last_hits, "spikes": total,
		"midway": midway, "hits": _hits.size()}

## Staple Gun: held from 260 px until the strip runs out: twenty staples, straight, most in him,
## each billed once; the empty strip is the reload.
func _drive_stapler(body: WeaponBase, ability: StapleGunAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-260.0, -40.0), 700.0)
	await _steady(body, 40)
	_press(MOUSE_BUTTON_RIGHT)
	await _step(30)
	_check("held, it fires (%d staples in half a second)" % ability.fired, ability.fired >= 2)
	_check("he sees it pointed at him", ability.is_threatening())
	var strip := int(ability.num("strip", 20))
	var marks_seen := false
	for i in int(strip / ability.num("rate", 5.0) * 60.0) + 40:
		if not ability.is_active():
			break
		marks_seen = marks_seen or _buddy.get_node_or_null("StapleMarks") != null
		await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step(30)
	marks_seen = marks_seen or _buddy.get_node_or_null("StapleMarks") != null
	_check("the whole strip, then it stops (%d)" % ability.fired, ability.fired == strip and not ability.is_active())
	_check("most of them in him (%d)" % ability.landed, ability.landed >= int(strip * 0.6))
	_check("each billed once, as its own impulse (%d)" % _hits_with_impulse(ability.num("staple_force", 420.0)),
		_hits_with_impulse(ability.num("staple_force", 420.0)) == ability.landed)
	_check("and they stay in him a while", marks_seen)
	_check("the empty strip is the full reload (%.1f s)" % ability.cooldown_left(),
		ability.cooldown_left() >= ability.num("cooldown", 6.0) * 0.8)
	return {"fired": ability.fired, "landed": ability.landed, "hits": _hits.size()}

## Keycap Barrage: tapped from 260 px, eight caps go up and come down on him, the keys show bare
## switches, and every cap flies home.
func _drive_mechanical_keyboard(body: WeaponBase, ability: KeycapBarrageAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-260.0, -60.0), 700.0)
	await _steady(body, 60)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step(2)
	var bare := body.get_node_or_null("BareKeys") as Node2D
	_check("a tap pops %d caps off (%d out)" % [int(ability.num("caps", 8)), ability.caps_out()],
		ability.fired == int(ability.num("caps", 8)) and ability.caps_out() == ability.fired)
	_check("and the keys they left are bare", bare != null and bare.visible)
	await _expect_face(&"incoming", &"blast")
	var back := await _await_cond(func() -> bool: return not ability.is_active(), 300)
	await _step(3)
	_check("they rain down on him (%d of %d)" % [ability.hits, ability.fired], ability.hits >= 4)
	_check("each billed once, as its own impulse",
		_hits_with_impulse(ability.num("cap_force", 800.0)) == ability.hits)
	_check("and every one flies home (%d)" % ability.home, back and ability.home == ability.fired)
	_check("the keys are whole again", bare == null or not bare.visible)
	return {"caps": ability.fired, "hits": ability.hits, "home": ability.home}

## Hot Coffee: tapped from 240 px, the spatter reaches him, scalds him once, stains him, and the
## steam bites twice more.
func _drive_office_mug(body: WeaponBase, ability: HotCoffeeAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-240.0, -60.0), 700.0)
	await _steady(body, 60)
	var grime_before := _buddy.grime.value if _buddy.grime else 0.0
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	_check("a tap throws the coffee (%d drops)" % ability.thrown, ability.thrown == int(ability.num("drops", 7)))
	var scalded := await _await_cond(func() -> bool: return ability.scalds > 0, 60)
	await _step(3)
	_check("it reaches him and scalds him, once", scalded and ability.scalds == 1
		and _hits_with_impulse(ability.num("scald_force", 900.0)) == 1)
	_check("and stains him (grime %.3f -> %.3f)" % [grime_before, _buddy.grime.value],
		_buddy.grime.value > grime_before)
	_check("he steams", _buddy.get_node_or_null("AbilitySteam") != null)
	await _expect_face(&"scalded", &"scalded")
	await _await_cond(func() -> bool: return not ability.is_active(), 150)
	await _step(3)
	_check("the steam bites %d more times (%d)" % [int(ability.num("steam_ticks", 2)), ability.steam_hits],
		ability.steam_hits == int(ability.num("steam_ticks", 2))
		and _hits_with_impulse(ability.num("steam_force", 450.0)) == ability.steam_hits)
	_check("and stops", _buddy.get_node_or_null("AbilitySteam") == null)
	return {"drops": ability.thrown, "scald": ability.scalds, "steam": ability.steam_hits,
		"grime": ability.last_grime}

## The weapon's collision shapes as sizes, to compare before and after.
func _shape_sizes(body: WeaponBase) -> Array:
	var out := []
	for child in body.get_children():
		var cs := child as CollisionShape2D
		if cs and cs.shape:
			out.append([cs.shape.get_rect(), cs.disabled])
	return out

## Hits the ability handed him itself (`strike`) at a multiplier `m` on top of the weapon's own.
func _boosted_strikes(body: WeaponBase, m: float) -> int:
	var base := Progression.damage_mult_for(_id, body.damage_mult)
	var n := 0
	for info in _hits:
		var own := false
		for impulse in body.ability.struck:
			own = own or absf(info.raw_impulse - impulse) <= 0.5
		if own and (_capped(info) or absf(_mult_of(info) - base * m) <= 0.001 * base * m):
			n += 1
	return n

# --- what each hit carried -------------------------------------------------------------------

func _on_payout(currency: StringName, amount: float, _at: Vector2, source_id: StringName) -> void:
	if source_id != _id or _id == &"" or currency != Economy.BONES:
		return
	var b := ItemDB.balance
	_pending = {"paid": amount, "unit": Economy.payout_for(1.0, source_id) * b.bones_per_damage
		* Economy.grime_multiplier()}

var _claimed_seen := false

func _on_damage(info: HitInfo) -> void:
	if _id == &"" or info.source_id != _id:
		_pending = {}
		return
	_hits.append(info)
	if is_instance_valid(_buddy) and _buddy.impacts_claimed_by() == _id:
		_claimed_seen = true
	if _pending.is_empty():
		_pipeline_bad.append("a hit of %.2f paid nothing" % info.amount)
		return
	var want := info.amount * float(_pending["unit"])
	if absf(float(_pending["paid"]) - want) > 1.0e-6 * maxf(1.0, want):
		_pipeline_bad.append("a hit of %.2f paid %.4f, the pipeline says %.4f"
			% [info.amount, float(_pending["paid"]), want])
	_pending = {}

## A hit's multiplier, read back off it: the amount over what the impulse is worth at x1.
func _mult_of(info: HitInfo) -> float:
	var b := ItemDB.balance
	return info.amount / maxf(info.raw_impulse * b.damage_per_impulse, 0.0001)

func _capped(info: HitInfo) -> bool:
	var b := ItemDB.balance
	return info.amount >= b.knockout_damage * b.max_hit_fraction - 0.001

func _boosted_hits(body: WeaponBase, boost: float) -> int:
	var base := Progression.damage_mult_for(_id, body.damage_mult)
	var n := 0
	for info in _hits:
		if not _capped(info) and absf(_mult_of(info) - base * boost) <= 0.001 * base * boost:
			n += 1
		elif _capped(info) and boost > 1.0:
			n += 1
	return n

## Every hit at the weapon's own multiplier times one of those its ability billed through.
func _bad_multiplier(body: WeaponBase) -> String:
	var base := Progression.damage_mult_for(_id, body.damage_mult)
	var allowed := body.ability.multipliers() if body.ability else [1.0]
	for info in _hits:
		if _capped(info):
			continue
		var got := _mult_of(info)
		var ok := false
		for m in allowed:
			ok = ok or absf(got - base * float(m)) <= 0.001 * base * float(m)
		if not ok:
			return ": x%.3f where the data allows %s" % [got / base, allowed]
	return ""

## What one use added, in damage: the whole of every hit the ability handed him itself (`strike`),
## the boost on every hit it multiplied — `amount x (1 - 1/m)` — and for a whirl, its own contacts
## less the one swing it stands in for. A landing it claimed was always going to be billed to the
## world, so it adds nothing.
func _extra_damage(body: WeaponBase, archetype: StringName, ordinary: float) -> float:
	var base := Progression.damage_mult_for(_id, body.damage_mult)
	var struck: Array[float] = body.ability.struck if body.ability else []
	var extra := 0.0
	var plain := 0.0
	for info in _hits:
		var own := false
		for impulse in struck:
			own = own or absf(info.raw_impulse - impulse) <= 0.5
		if own:
			extra += info.amount
			continue
		var m := _mult_of(info) / base
		if _capped(info):
			m = 1.0
			for b in body.ability.billed:
				m = maxf(m, b)
		if m > 1.0005:
			extra += info.amount * (1.0 - 1.0 / m)
		else:
			plain += info.amount
	if archetype == &"spin":
		extra += maxf(plain - ordinary, 0.0)
	return extra

func _hit_with_impulse(impulse: float) -> HitInfo:
	for info in _hits:
		if absf(info.raw_impulse - impulse) <= 0.5:
			return info
	return null

func _hits_with_impulse(impulse: float) -> int:
	var n := 0
	for info in _hits:
		if absf(info.raw_impulse - impulse) <= 0.5:
			n += 1
	return n

## His face answers the ability: a watcher connected after his brain, so what it reads is what
## the brain chose (item_check's `_expect_face`).
func _on_ability_face(item_id: StringName, event: StringName, _at: Vector2) -> void:
	if item_id == _id and is_instance_valid(_buddy) and _buddy.expression:
		_faces.append([event, _buddy.expression.beat_id()])
		if OS.get_cmdline_user_args().has("--faces"):
			print("      face %s -> %s  beat %s state %s locked %s dist %.0f" % [event, _buddy.expression.beat_id(), _buddy.expression._beat.get("id", ""), _buddy.state, _buddy.expression.is_locked(), _buddy.global_position.distance_to(_at)])

func _expect_face(event: StringName, row: StringName) -> void:
	await _step(3)
	var seen := false
	var wore: Array = []
	for pair in _faces:
		if pair[0] == event:
			wore.append(pair[1])
			seen = seen or pair[1] == row
	_check("he answers `%s` with `%s` (%s)" % [event, row, wore], seen)

# --- the stage and the hand -------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node2D.new()
	_stage.name = "Stage"
	var bounds := WorldBounds.new()
	bounds.name = "Bounds"
	_stage.add_child(bounds)
	_spawner = ItemSpawner.new()
	_spawner.name = "ItemSpawner"
	_spawner.world = _stage
	_spawner.add_to_group(&"item_spawner")
	_stage.add_child(_spawner)
	var fx := WorldFX.new()
	fx.name = "WorldFX"
	_stage.add_child(fx)
	_buddy = BUDDY.instantiate() as Buddy
	_buddy.position = HOME
	_stage.add_child(_buddy)
	_view.add_child(_stage)
	# After his brain, which connected as he entered the tree.
	EventBus.ability_event.connect(_on_ability_face)
	_claimed_seen = false
	_mouse = Vector2(40, 40)
	_held = 0
	_move(_mouse)
	for i in 90:
		await _step()
		if i > 3 and _buddy.is_grounded() and _buddy.linear_velocity.length() < 2.0:
			break

func _free_stage() -> void:
	if EventBus.ability_event.is_connected(_on_ability_face):
		EventBus.ability_event.disconnect(_on_ability_face)
	_release_all()
	_id = &""
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_buddy = null
	_spawner = null
	await get_tree().process_frame
	await get_tree().physics_frame

func _own(id: StringName) -> void:
	var item := ItemDB.get_item(id)
	if item == null or Progression.is_unlocked(id):
		return
	for req in item.requires:
		_own(req)
	Economy.grant(item.currency_id(), float(item.cost))
	Progression.purchase_item(id)

func _spawn(id: StringName, at: Vector2) -> WeaponBase:
	EventBus.spawn_requested.emit(id, at)
	var node: Node = _spawner._active.back() if not _spawner._active.is_empty() else null
	await _step(2)
	return node as WeaponBase

func _centre() -> Vector2:
	return _buddy.get_interaction_rect().get_center()

func _step(frames: int = 1) -> void:
	for i in frames:
		await get_tree().physics_frame

func _await_cond(condition: Callable, frames: int) -> bool:
	for i in frames:
		if condition.call():
			return true
		await _step()
	return condition.call()

func _gone(body) -> bool:
	return body == null or not is_instance_valid(body) or (body as Node).is_queued_for_deletion()

func _await_still(body, frames: int) -> void:
	for i in frames:
		if _gone(body) or (body as RigidBody2D).linear_velocity.length() < 3.0:
			return
		await _step()

func _steady(body, frames: int) -> void:
	for i in frames:
		if _gone(body) or (i > 6 and (body as RigidBody2D).linear_velocity.length() < 25.0):
			return
		_move(_mouse)
		await _step()

## He stops moving — and is back on his feet from any knockout the swing before gave him — before
## the next measurement starts. Nothing bills him while he is down.
func _settle_him() -> void:
	for i in 600:
		if not ExpressionBrain.KNOCKOUT_STATES.has(_buddy.state) and not _buddy.health.down:
			break
		await _step()
	_buddy.health.reset_meter()
	for i in 90:
		if _buddy.linear_velocity.length() < 5.0 and _buddy.is_grounded():
			return
		await _step()

func _peak_speed(frames: int) -> float:
	var peak := 0.0
	for i in frames:
		peak = maxf(peak, _buddy.linear_velocity.length())
		await _step()
	return peak

func _move(to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = to
	e.global_position = to
	e.relative = to - _mouse
	e.button_mask = _held
	_mouse = to
	_view.push_input(e, true)

func _press(button: MouseButton, shift: bool = false) -> void:
	_held |= 1 << (int(button) - 1)
	_button(button, true, shift)

func _release(button: MouseButton, shift: bool = false) -> void:
	_held &= ~(1 << (int(button) - 1))
	_button(button, false, shift)

func _release_all() -> void:
	if _held & 2:
		_release(MOUSE_BUTTON_RIGHT)
	if _held & 1:
		_release(MOUSE_BUTTON_LEFT)

func _button(button: MouseButton, pressed: bool, shift: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	e.button_mask = _held
	e.position = _mouse
	e.global_position = _mouse
	_view.push_input(e, true)

func _mouse_to(target: Vector2, speed: float) -> void:
	var stride := speed / float(Engine.physics_ticks_per_second)
	var guard := 0
	while _mouse.distance_to(target) > stride and guard < 400:
		_move(_mouse.move_toward(target, stride))
		await _step()
		guard += 1
	_move(target)
	await _step()

func _grab_point(body: BaseDraggable) -> Vector2:
	if body.drag_area:
		for child in body.drag_area.get_children():
			if child is CollisionShape2D:
				return (child as CollisionShape2D).global_position
	return body.global_position

func _grab(body: BaseDraggable) -> bool:
	if _gone(body):
		return false
	if _held & 1:
		_release(MOUSE_BUTTON_LEFT)
		await _step()
	_move(_grab_point(body))
	await _step(2)
	if body.drag_area and not body.drag_area.is_hovered:
		_move(_grab_point(body))
		await _step(2)
	_press(MOUSE_BUTTON_LEFT)
	await _step()
	return body.dragging

## The hand swept straight through him and back, at chest height.
func _sweep_through(out_speed: float, back_speed: float) -> void:
	var him := _centre()
	await _mouse_to(Vector2(him.x - 220.0, him.y - 40.0), out_speed)
	await _mouse_to(Vector2(him.x + 200.0, him.y - 40.0), back_speed)

## Two ordinary passes through him with the ability idle: the mean hit, in damage.
func _ordinary_hit(body: WeaponBase) -> float:
	_hits.clear()
	for i in 3:
		await _sweep_through(900.0, 1300.0)
		if _hits.size() >= 2:
			break
	await _step(10)
	var total := 0.0
	for info in _hits:
		total += info.amount
	var mean := total / float(_hits.size()) if not _hits.is_empty() else 0.0
	_hits.clear()
	return mean

## Anything the weapon or its ability left in the world once it is gone: an emitter on him, a
## ball, a tee, an exception.
func _leftovers() -> String:
	if not is_instance_valid(_buddy):
		return ""
	for child in _buddy.get_children():
		if String(child.name).begins_with("DazeStars") and not child.is_queued_for_deletion():
			return "stars still on him"
	for node in _stage.get_children():
		if node is RigidBody2D and String(node.name).begins_with("GolfBall") and not node.is_queued_for_deletion():
			return "a golf ball"
		if node is AbilityShot and not node.is_queued_for_deletion():
			return "a %s" % String(node.name).to_lower()
	for child in _buddy.get_children():
		for mark in ["StapleMarks", "BlueScreenScan", "AbilitySteam"]:
			if String(child.name).begins_with(mark) and not child.is_queued_for_deletion():
				return "%s still on him" % mark
	if not _buddy.get_collision_exceptions().is_empty():
		return "an exception on him"
	if _buddy.freeze and not ExpressionBrain.KNOCKOUT_STATES.has(_buddy.state):
		return "he is still frozen"
	return ""

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
		# `print`, not `printerr`: the suite's own Logger reads the error stream.
		print("    FAIL %s" % what)
