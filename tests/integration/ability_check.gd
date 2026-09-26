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
	# D78's kind rows pay on the bus: what they emit, and the Hearts it came back as.
	EventBus.kindness_given.connect(_on_kind_act)
	EventBus.kindness_sustained.connect(_on_kind_rate)
	EventBus.payout.connect(_on_kind_payout)

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
	await _the_d78_rows()
	await _d78_focus_lost()

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
		# D78: the same button beyond the melee drawer — never on a gun or a power, whose right is
		# already theirs (D56, D72). The fidget toys are asked in the D78 suite, by what they are.
		_check("%s is an item in the melee drawer, or in one D78 opened" % id,
			item != null and (item.category == ItemData.CATEGORY_WEAPON
				or D78_DRAWERS.has(item.category)))
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
		_look_is_sound(StringName(row.get("id", &"")), String(row.get("name", "")))

## How it reads (D77), from the data: a misspelled icon falls back to the generic one without a
## word, and a green accent is keyed out with the chroma backdrop (D38) — so both are checked here,
## for every ability, with or without a row of its own in `AbilityLooks`.
func _look_is_sound(ability_id: StringName, display_name: String) -> void:
	var look := AbilityLooks.look_for(ability_id, display_name)
	var colours: Array[Color] = [look["colour"]]
	var icons: Array[StringName] = []
	var states: Dictionary = (look["states"] as Dictionary).duplicate()
	if not (look["cue"] as Dictionary).is_empty():
		states[&"cue"] = look["cue"]
	for event in states:
		var spec: Dictionary = states[event]
		if bool(spec.get("none", false)):
			continue
		icons.append(StringName(spec.get("icon", &"pow")))
		if spec.has("colour"):
			colours.append(AbilityLooks.colour_of(spec["colour"]))
	var unknown := icons.filter(func(icon: StringName) -> bool: return not AbilityFX.ICONS.has(icon))
	var burst := StringName(look["burst"])
	var burst_known := AbilityFX.ICONS.has(burst) or burst == &"chip" \
		or ResourceLoader.exists("%s/%s.png" % [UIStyle.GLYPH_DIR, burst])
	_check("%s's badges and burst are drawn icons (%s)" % [ability_id, str(icons)],
		unknown.is_empty() and burst_known)
	var green := colours.filter(func(c: Color) -> bool: return c.h > 0.2 and c.h < 0.45 and c.s > 0.5)
	_check("and none of its colours is a green the chroma key would eat", green.is_empty())
	_check("and it calls out a word as it starts (\"%s\")" % look["call"], not String(look["call"]).is_empty())

# --- one weapon -------------------------------------------------------------------------------

func _check_ability(id: StringName) -> void:
	var row := AbilityTable.row_for(id)
	_suite("%s — %s (%s)" % [id, row.get("name", ""), row.get("archetype", "")])
	# D78: anything that is not a melee weapon has a life of its own below — a ball is not swung
	# through him to learn what an ordinary hit is, and a sponge pays Hearts, not hits.
	var item := ItemDB.get_item(id)
	if item and item.category != ItemData.CATEGORY_WEAPON:
		await _check_held_ability(id)
		return
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
	# How it reads (D77): the ready glint, a sprite drawn once, on the weapon in the hand.
	var glint := ability.ready_glint()
	_check("held and ready, it wears its ready glint", glint != null and glint.visible)
	_check("and the glint costs nothing: no tick of its own", glint == null or not glint.is_processing())
	# An ordinary swing first, to know what an ordinary hit of this weapon is worth.
	_buddy.health.reset_meter()
	var ordinary := await _ordinary_hit(body)
	_check("an ordinary swing lands (%.1f a hit)" % ordinary, ordinary > 0.0)
	await _mouse_to(_centre() + Vector2(-260.0, -60.0), 900.0)
	await _steady(body, 60)
	_buddy.health.reset_meter()
	await _settle_him()
	_hits.clear()
	_claimed.clear()
	_faces.clear()
	_pipeline_bad.clear()
	var before_uses := ability.uses

	var measured := {}
	# A hooked row that is used differently from its archetype brings a driver of its own, because
	# what the player does with it is not what the archetype's driver does. The blades name theirs
	# for the ability (`_drive_<ability id>`), the blunt and desk nine for the weapon
	# (`_drive_<item id>`: a bat's middle is aimed, a staple gun is held down, a tyre iron is thrown
	# away from him). A hook with neither falls back to its archetype's.
	var own_driver := "_drive_%s" % row.get("id", "")
	if not has_method(own_driver) and row.has("script"):
		own_driver = "_drive_%s" % id
	match &"hooked" if has_method(own_driver) else archetype:
		&"hooked":
			measured = await call(own_driver, body, ability)
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
		&"transform":
			measured = await _drive_transform(body, ability as TransformAbility)
		&"tether":
			measured = await _drive_tether(body, ability as TetherAbility)
		&"clamp":
			measured = await _drive_clamp(body, ability as ClampAbility)
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

	# --- how it read (D77) -----------------------------------------------------------------
	var look := ability.look()
	_check("it called out \"%s\" as it began" % look["call"], ability.fx_said.has(String(look["call"])))
	# A state is what landing did to him, so an ability that failed to land (already a failure
	# above) is not failed twice for it.
	_check("it put a state over his head (%s)" % str(ability.fx_states),
		not ability.fx_states.is_empty() or ability.payoffs == 0)
	_check("its payoff was drawn where it landed (%d drawn for %d payoffs)" % [ability.fx_landed,
		ability.payoffs], ability.payoffs == 0 or ability.fx_landed > 0)
	var own_words := [String(look["call"]), String(look["go"])]
	var landing_words := ability.fx_said.filter(func(w: String) -> bool: return not own_words.has(w))
	_check("and a word for it (%s)" % str(landing_words), ability.payoffs == 0
		or not landing_words.is_empty())

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
	glint = ability.ready_glint()
	_check("and the ready glint is gone while it cools", glint == null or not glint.visible)
	var readied := ability.fx_readied
	var wait := int((ability.cooldown_left() + 0.3) * 60.0)
	await _await_cond(func() -> bool: return ability.is_ready(), wait + 60)
	_check("it is ready again when the cooldown is up", ability.is_ready())
	_check("and the pip is gone", pip == null or not pip.visible)
	glint = ability.ready_glint()
	_check("and the glint is back, with a pop", not ability.is_ready() or (glint != null and glint.visible
		and ability.fx_readied == readied + 1))

	# --- at rest, and away -----------------------------------------------------------------
	_release(MOUSE_BUTTON_LEFT)
	await _await_still(body, 90)
	await _step(4)
	_check("put down and idle, nothing of it runs", not ability.is_busy())
	_check("and its glint is not drawn on the desk", glint == null or not glint.visible)
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
	# How it reads (D77): the owner's own example of an ability that was not obvious.
	var halo := stars as StunAbility.Halo
	var all_out := halo.shown() if halo else 0
	_check("five of them, all out as the daze begins (%d)" % all_out, all_out == StunAbility.Halo.STARS)
	_check("under a badge over his head that counts the daze down",
		AbilityFX.states_on(_buddy).has(&"dazed"))
	await _expect_face(&"dazed", &"dazed")
	var follow := 0
	var fewest := all_out
	while ability.is_dazed() and follow < 4:
		await _sweep_through(900.0, 1300.0)
		follow += 1
		if is_instance_valid(halo) and ability.is_dazed():
			fewest = mini(fewest, halo.shown())
	_check("the stars go out one by one as it wears off (%d of %d left at the fewest)" % [fewest, all_out],
		fewest < all_out)
	_check("the follow-ups while he is dazed are x%.2f (%d)" % [ability.num("bonus_mult", 1.4),
		ability.dazed_hits], ability.dazed_hits == 0 or _boosted_hits(body, ability.num("bonus_mult", 1.4)) >= 1)
	var growing := true
	for i in range(1, ability.follow_weights.size()):
		var bigger := ability.follow_weights[i] > ability.follow_weights[i - 1]
		growing = growing and (bigger or i >= StunAbility.FOLLOW_MOST)
	_check("each follow-up is called out bigger than the last (%s)" % str(ability.follow_weights),
		ability.follow_weights.size() == ability.dazed_hits and growing)
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

# --- the blades (hooked rows, driven by ability id) -------------------------------------------

## Momentum: right held, the hand swings it back and forth through him; the grip is loose, the
## chain climbs with each hit that did not stop it, and letting go puts the grip back.
func _drive_momentum(body: WeaponBase, ability: MomentumAbility) -> Dictionary:
	var damp_before := body.angular_damp
	var mode_before := body.angular_damp_mode
	await _approach(body, Vector2(-220.0, -40.0))
	_press(MOUSE_BUTTON_RIGHT)
	await _step(2)
	_check("right held loosens the grip (damping %.2f -> %.2f)" % [damp_before, body.angular_damp],
		ability.is_active() and body.angular_damp == 0.0
		and body.angular_damp_mode == RigidBody2D.DAMP_MODE_REPLACE)
	for i in 4:
		if not ability.is_active() or _buddy.health.down:
			break
		await _sweep_through(900.0, 1300.0)
	_check("the chain climbs with hits that do not stop it (best %d, %d hits, broken %d)"
		% [ability.best_chain, ability.chain_hits, ability.chains_broken], ability.best_chain >= 2)
	_check("and a later hit is billed higher than x1", _boosted_hits(body, 1.0 + ability.num("step_mult", 0.15)) >= 1)
	_release(MOUSE_BUTTON_RIGHT)
	await _step(2)
	_check("letting go ends it and gives the grip back", not ability.is_active()
		and is_equal_approx(body.angular_damp, damp_before) and body.angular_damp_mode == mode_before)
	return {"hits": _hits.size(), "chain": ability.best_chain, "broken": ability.chains_broken}

## Embed: thrown from 250 px, it goes in, rides him, ticks, and drops out at his feet.
func _drive_embed(body: WeaponBase, ability: EmbedAbility) -> Dictionary:
	await _approach(body, Vector2(-250.0, -80.0))
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	_check("right throws it out of the hand", not body.dragging and ability.is_active())
	var hit := await _await_cond(func() -> bool: return ability.lodged, 60)
	_check("it goes in (%.0f px/s thrown, %.0f)" % [ability.last_throw_speed, ability.last_hit], hit)
	await _step(3)
	var local := _buddy.global_transform.affine_inverse() * body.global_transform
	await _step(12)
	var later := _buddy.global_transform.affine_inverse() * body.global_transform
	_check("and rides with him (%.1f px drift in his frame)" % local.origin.distance_to(later.origin),
		ability.is_lodged() and local.origin.distance_to(later.origin) < 1.0 and body.freeze
		and body.collision_layer == 0)
	_check("the throw is billed once, as its own impulse (%.0f)" % ability.last_hit,
		_hits_with_impulse(ability.last_hit) == 1)
	await _expect_face(&"skewered", &"skewered")
	await _await_cond(func() -> bool: return not ability.is_lodged(), 240)
	await _step(3)
	var ticks := _hits_with_impulse(ability.num("tick_force", 600.0))
	_check("it worked in, a hit a tick (%d ticks, %d billed)" % [ability.ticks, ticks],
		ability.ticks >= 4 and ticks == ability.ticks)
	_check("then came out (%s), unfrozen, its layers back" % ability.came_out,
		not body.freeze and body.collision_layer != 0 and ability.came_out != &"")
	await _await_cond(func() -> bool: return not ability.is_active(), 240)
	_check("and the exception came off once it was clear", not body.get_collision_exceptions().has(_buddy))
	return {"throw": ability.last_hit, "ticks": ability.ticks, "out": String(ability.came_out),
		"hits": _hits.size()}

## Brush Clear: a prop in front of the hand and one behind it; one swipe throws him and the one in
## front away from the hand, and leaves the one behind alone.
func _drive_brush_clear(body: WeaponBase, ability: BrushClearAbility) -> Dictionary:
	await _approach(body, Vector2(-200.0, -20.0))
	var hand := _mouse
	var front := _prop(hand + Vector2(105.0, 40.0))
	var behind := _prop(hand + Vector2(-110.0, 40.0))
	await _step(20)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _await_cond(func() -> bool: return ability.last_origin != Vector2.INF or not ability.is_active(), 40)
	await _step()
	_check("one swipe cleared the cone (%d thrown)" % ability.last_swept, ability.last_swept >= 2)
	_check("him away from the hand (%.0f px/s handed, moving %.0f)" % [ability.last_push,
		_buddy.linear_velocity.x], ability.last_push > 0.0 and _buddy.linear_velocity.x > 50.0)
	_check("the prop in front with him (%.0f, %.0f)" % [front.linear_velocity.x, front.linear_velocity.y],
		front.linear_velocity.x > 100.0 and front.linear_velocity.y < 0.0)
	_check("and not the one behind (%.0f px/s)" % behind.linear_velocity.length(),
		behind.linear_velocity.length() < 40.0)
	await _step(3)
	_check("billed as the impulse it handed him", _hit_with_impulse(_buddy.mass * ability.last_push) != null)
	await _expect_face(&"swept", &"swept")
	var him := await _peak_speed(20)
	front.queue_free()
	behind.queue_free()
	return {"push": ability.last_push, "swept": ability.last_swept, "him": him, "hits": _hits.size()}

## Reap: from beside him at chest height, one press: the hand drops and sweeps, the hook takes
## his feet, and he goes head over heels.
func _drive_reap(body: WeaponBase, ability: ReapAbility) -> Dictionary:
	await _approach(body, Vector2(-170.0, -30.0))
	var top := _buddy.global_position.y
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	var low := 0.0
	var contact_hits := 0
	for i in 40:
		await _step()
		low = maxf(low, ability.hand_world().y - _mouse.y)
		if ability.caught_him:
			break
		contact_hits = _hits.size()
	_check("the hand went down to the desk (%.0f px)" % low, low >= 60.0)
	_check("and the hook caught his feet without shoving him first (%d contact hits)" % contact_hits,
		ability.caught_him and contact_hits == 0)
	var turned := 0.0
	var rise := 0.0
	for i in 50:
		turned += absf(_buddy.angular_velocity) / 60.0
		rise = maxf(rise, top - _buddy.global_position.y)
		await _step()
	_check("head over heels (%.1f rad turned, %.0f px up)" % [turned, rise], turned >= 2.0 and rise >= 15.0)
	_check("billed as the reap's own impulse at x%.2f" % ability.num("reap_mult", 1.2),
		_hit_with_impulse(ability.last_reap) != null)
	_check("and where he lands is the sickle's", _claimed_seen or _buddy.impacts_claimed_by() == _id)
	await _expect_face(&"upended", &"upended")
	await _await_cond(func() -> bool: return not ability.is_active(), 120)
	_check("the exception comes off and the hand is its own again",
		not body.get_collision_exceptions().has(_buddy) and body.hand_offset == Vector2.ZERO)
	return {"reap": ability.last_reap, "turned": turned, "rise": rise, "hits": _hits.size()}

## Soul Reap: right held, a quick stroke toward him from 430 px: the ghost leaves the blade and goes
## through him while the scythe is still far away.
func _drive_soul_reap(body: WeaponBase, ability: SoulReapAbility) -> Dictionary:
	await _approach(body, Vector2(-430.0, -60.0))
	_press(MOUSE_BUTTON_RIGHT)
	await _step(10)
	_check("right held arms it", ability.is_active() and ability.last_ghost_speed == 0.0)
	# The swing: a quick stroke of the hand toward him that stops well short of him.
	await _mouse_to(_centre() + Vector2(-130.0, -60.0), 1800.0)
	var left := await _await_cond(func() -> bool: return not ability.is_active(), 20)
	_release(MOUSE_BUTTON_RIGHT)
	_check("a swing lets the ghost go (%.0f px/s%s)" % [ability.last_ghost_speed,
		", bent onto him" if ability.assisted else ""], left and not ability.fizzled and ability.last_ghost_speed > 0.0)
	var reaped := await _await_cond(func() -> bool: return ability.reaps > 0, 60)
	var gap := ability.tip_world().distance_to(_centre())
	_check("it reaps him at range (%.0f px from the blade)" % gap, reaped and gap >= 100.0)
	await _step(3)
	_check("billed once, as its own impulse (%.0f)" % ability.last_strike,
		_hits_with_impulse(ability.last_strike) == 1)
	_check("his soul is tugged out", _buddy.get_node_or_null("SoulWisp") != null)
	await _expect_face(&"soul_reaped", &"soul_reaped")
	return {"ghost": ability.last_ghost_speed, "reap": ability.last_strike, "gap": gap, "hits": _hits.size()}

## En Garde: right held, it points itself at him; lunges along the blade are thrusts, x2.
func _drive_en_garde(body: WeaponBase, ability: EnGardeAbility) -> Dictionary:
	await _approach(body, Vector2(-200.0, -40.0))
	_press(MOUSE_BUTTON_RIGHT)
	await _await_cond(func() -> bool: return ability.aim_error() <= 0.1, 60)
	_check("on guard, it swings onto him and points at him (%.2f rad off)" % ability.aim_error(),
		ability.aim_error() <= 0.25)
	await _expect_face(&"en_garde", &"squared_up")
	for i in 3:
		if not ability.is_active() or _buddy.health.down:
			break
		await _mouse_to(_centre() + Vector2(-60.0, -40.0), 1100.0)
		await _step(4)
		await _mouse_to(_centre() + Vector2(-200.0, -40.0), 600.0)
		await _step(10)
	await _step(3)
	_check("a lunge along the blade is a thrust, x%.1f (%d thrusts)" % [ability.num("thrust_mult", 2.0),
		ability.thrusts], ability.thrusts >= 1 and _boosted_hits(body, ability.num("thrust_mult", 2.0)) >= 1)
	_release(MOUSE_BUTTON_RIGHT)
	await _step(2)
	_check("letting go ends it", not ability.is_active())
	return {"thrusts": ability.thrusts, "swipes": ability.swipes, "aim": ability.best_aim, "hits": _hits.size()}

## Flurry: right held beside him, the hand following him, for as long as it lasts.
func _drive_flurry(body: WeaponBase, ability: FlurryAbility) -> Dictionary:
	await _approach(body, Vector2(-95.0, -10.0))
	_press(MOUSE_BUTTON_RIGHT)
	for i in 150:
		if not ability.is_active():
			break
		_move(_mouse.move_toward(_centre() + Vector2(-95.0, -10.0), 600.0 / 60.0))
		await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step(3)
	_check("it jabbed about six a second (%d jabs)" % ability.jabs,
		ability.jabs >= int(ability.num("jab_rate", 6.0) * ability.num("fuel_seconds", 2.0)) - 1)
	_check("and the jabs landed as real contacts (%d landed, %d billed)" % [ability.jabs_landed, _hits.size()],
		ability.jabs_landed >= 4 and ability.struck.is_empty())
	_check("the hand is its own again", body.hand_offset == Vector2.ZERO and not ability.is_active())
	return {"jabs": ability.jabs, "landed": ability.jabs_landed, "hits": _hits.size()}

## Snap: one tap from 300 px: three tips, straight, and the knife never leaves the hand.
func _drive_snap(body: WeaponBase, ability: SnapAbility) -> Dictionary:
	await _approach(body, Vector2(-300.0, -40.0))
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	# The first tip, sampled in flight: a straight line.
	var tip: Node2D = null
	for i in 6:
		await _step()
		for node in _stage.get_children():
			if String(node.name).begins_with("BladeTip"):
				tip = node
				break
		if tip:
			break
	var path: Array[Vector2] = []
	for i in 4:
		if is_instance_valid(tip) and not (tip as SnapAbility.Shard).spent:
			path.append(tip.global_position)
		await _step()
	var straight := path.size() >= 3 and absf((path[1] - path[0]).cross(path[path.size() - 1] - path[0])) \
		<= 2.0 * path[0].distance_to(path[path.size() - 1])
	_check("a tip flies dead straight (%d samples)" % path.size(), straight)
	await _await_cond(func() -> bool: return ability.flicked >= int(ability.num("shots", 3.0)), 40)
	_check("three of them, and the knife stays in the hand (%d)" % ability.flicked,
		ability.flicked == int(ability.num("shots", 3.0)) and body.dragging)
	await _await_cond(func() -> bool: return ability.tips_hit >= 2, 60)
	await _step(3)
	_check("they hit him, each billed once (%d hit)" % ability.tips_hit,
		ability.tips_hit >= 2 and _hits_with_impulse(ability.num("tip_force", 1300.0)) == ability.tips_hit)
	return {"tips": ability.flicked, "hit": ability.tips_hit, "hits": _hits.size()}

## Special Delivery: thrown from 260 px, point first and straight; x2 on him; stuck where it lands,
## nothing running; and the cooldown starts when it is fetched.
func _drive_special_delivery(body: WeaponBase, ability: DeliveryAbility) -> Dictionary:
	await _approach(body, Vector2(-260.0, -60.0))
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	_check("right throws it out of the hand", not body.dragging and ability.in_flight())
	var hit := await _await_cond(func() -> bool: return ability.point_hits > 0, 60)
	_check("point first all the way (%.2f rad off its flight at worst)" % ability.worst_heading,
		ability.worst_heading <= 0.35)
	_check("and the point arrives (%.0f)" % ability.last_hit, hit)
	await _step(3)
	var chop := _hit_with_impulse(ability.last_hit)
	_check("billed once, x%.1f on the point" % ability.num("point_mult", 2.0), chop != null
		and _hits_with_impulse(ability.last_hit) == 1 and absf(_mult_of(chop)
		- Progression.damage_mult_for(_id, body.damage_mult) * ability.num("point_mult", 2.0)) < 0.01)
	await _expect_face(&"delivered", &"pricked")
	var stuck := await _await_cond(func() -> bool: return ability.is_stuck(), 180)
	_check("it sticks where it lands (%s)" % ability.stuck_at.round(), stuck)
	await _step(60)
	_check("and waits there: nothing runs, and no cooldown yet", body.freeze and not ability.is_busy()
		and not ability.is_cooling() and ability.is_active())
	var fetch := body.get_node_or_null("AbilityStateFetch") as Node2D
	_check("a badge over its handle says to fetch it (D77), drawn once and never ticked",
		ability.is_waiting_to_be_fetched() and fetch != null and fetch.visible and not fetch.is_processing())
	await _grab(body)
	await _step(2)
	_check("fetched, the badge is gone", fetch == null or not is_instance_valid(fetch)
		or fetch.is_queued_for_deletion())
	_check("fetched, the cooldown starts", ability.fetched and ability.is_cooling() and body.dragging
		and not body.freeze)
	return {"speed": ability.last_throw_speed, "point": ability.last_hit, "hits": _hits.size()}

## The hand to where a blade's ability starts, round him rather than through him — over his head,
## across, and down — and him still again before anything is counted, so a blade carried into
## place is never measured as its ability.
func _approach(body: WeaponBase, offset: Vector2) -> void:
	var over := _buddy.get_interaction_rect().position.y - 220.0
	await _mouse_to(Vector2(_mouse.x, minf(_mouse.y, over)), 700.0)
	await _mouse_to(Vector2(_centre().x + offset.x, over), 700.0)
	await _mouse_to(_centre() + offset, 500.0)
	await _steady(body, 60)
	await _settle_him()
	# He may have been nudged on the way: once more, the short way.
	await _mouse_to(_centre() + offset, 400.0)
	await _steady(body, 60)
	_hits.clear()
	_faces.clear()
	_pipeline_bad.clear()

## A plain free body on the item layer, for a swipe to throw.
func _prop(at: Vector2) -> RigidBody2D:
	var prop := RigidBody2D.new()
	prop.name = "Prop"
	prop.collision_layer = 4
	prop.collision_mask = 1 | 4
	prop.mass = 1.0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(20, 20)
	shape.shape = box
	prop.add_child(shape)
	_stage.add_child(prop)
	prop.global_position = at
	return prop

# --- what each hit carried -------------------------------------------------------------------

func _on_payout(currency: StringName, amount: float, _at: Vector2, source_id: StringName) -> void:
	if source_id != _id or _id == &"" or currency != Economy.BONES:
		return
	var b := ItemDB.balance
	_pending = {"paid": amount, "unit": Economy.payout_for(1.0, source_id) * b.bones_per_damage
		* Economy.grime_multiplier()}

var _claimed_seen := false
var _claimed: Array[HitInfo] = []

func _on_damage(info: HitInfo) -> void:
	if _id == &"" or info.source_id != _id:
		_pending = {}
		return
	_hits.append(info)
	if is_instance_valid(_buddy) and _buddy.impacts_claimed_by() == _id:
		_claimed_seen = true
		_claimed.append(info)
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
	# A whirl's and a flurry's hits are ordinary contacts, many to a use.
	if archetype == &"spin" or (body.ability and body.ability.ability_id() == &"flurry"):
		extra += maxf(plain - ordinary, 0.0)
	if archetype == &"transform":
		extra += _heavier(body, ordinary)
	# A tether's payoff is where it throws him: the landings it claimed, which a home run's claim is
	# not counted for because its hit was already billed x2.5.
	if archetype == &"tether":
		for info in _claimed:
			var own := false
			for impulse in struck:
				own = own or absf(info.raw_impulse - impulse) <= 0.5
			if not own:
				extra += info.amount
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
	# Every weapon is measured on a desk that nothing before it has touched, so it measures the same
	# alone as it does twenty-five weapons into the run (D74 fixes). Two things carried over.
	#
	# The frame: the first weapon's stage was built from `_ready` and every later one after
	# `_free_stage`'s last tick, so the first stood him on the desk one physics step later than the
	# rest. It is built straight after a physics tick every time.
	#
	# The physics space: one SubViewport, one World2D, every body of every weapon so far added to
	# and taken out of the same broadphase, whose history orders the contacts the solver works
	# through — a difference in the last bits that a soft-jointed swing magnifies. The cricket bat
	# middled him alone and led with its handle in the full run, the cleaver's ordinary hit read 17
	# alone and 42 in the run, the scythe's ghost reaped him alone and missed by 80 px in the run.
	# Each weapon gets a World2D of its own.
	await get_tree().physics_frame
	_view.world_2d = World2D.new()
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
	var first := Vector2.INF
	for i in 90:
		await _step()
		if i == 0:
			first = _buddy.global_position
		if i > 3 and _buddy.is_grounded() and _buddy.linear_velocity.length() < 2.0:
			break
	# Every desk starts step for step the same, and unshaken: a weapon measured first and the same
	# weapon measured after another are measured on the same desk, through the same picture.
	_check("the desk is not still shaking from the last weapon",
		_view.canvas_transform == Transform2D.IDENTITY)
	if _stage_first == Vector2.INF:
		_stage_first = first
	else:
		_check("the desk started him exactly as it did for the first weapon (%s)" % first,
			first == _stage_first)

## Where he was one step into the first desk.
var _stage_first := Vector2.INF

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
	# A jolt offsets the whole picture by up to 9 px at random, timed on the wall clock, and a
	# stepped suite outruns it: a weapon aimed while the desk still shakes from the one before is
	# aimed up to 9 px off, which is the cricket bat's middle missing and the scythe's ghost
	# reaping short. It only showed once the mace's Lead Heart, which jolts the desk on every blow,
	# ran first. Wait it out.
	var fx := WorldFX.of(_buddy)
	for i in 600:
		if fx == null or not fx.is_shaking():
			break
		await _step()
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
		for left in ["GhostBlade", "BladeTip"]:
			if String(node.name).begins_with(left) and not node.is_queued_for_deletion():
				return "a %s" % left
		if node is AbilityShot and not node.is_queued_for_deletion():
			return "a %s" % String(node.name).to_lower()
	for child in _buddy.get_children():
		if String(child.name).begins_with("SoulWisp") and not child.is_queued_for_deletion():
			return "his soul, still out"
		for mark in ["StapleMarks", "BlueScreenScan", "AbilitySteam", "AbilityState", "IaidoCut"]:
			if String(child.name).begins_with(mark) and not child.is_queued_for_deletion():
				return "%s still on him" % mark
	if not _buddy.get_collision_exceptions().is_empty():
		return "an exception on him"
	for node in _stage.get_children():
		if node is ClampAbility.Headphones and not node.is_queued_for_deletion():
			return "his headphones still on the desk"
	if _phones_off():
		return "his headphones still hidden"
	if _buddy.get_node_or_null("PunchedHole") != null:
		return "a hole still in him"
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

## Middle It: lit, then swept through him until the middle meets him — an edge first if the hand
## finds one — and the middled hit is x2.5 and sends him straight up.
func _drive_cricket_bat(body: WeaponBase, ability: MiddleItAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-220.0, -70.0), 700.0)
	# Hanging from the hand, blade down, before the light goes on: where the middle hangs below the
	# hand is what the sweeps aim with. (A bat balanced on its grip stays balanced, and a sweep at
	# the height of his middle then passes over his head.)
	for i in 120:
		_move(_mouse)
		await _step()
		if i > 30 and ability.middle_world().y > _mouse.y + 30.0 and body.linear_velocity.length() < 25.0:
			break
	var hang := ability.middle_world().y - _mouse.y
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	var glow := body.get_node_or_null("MiddleGlow") as Node2D
	_check("a tap lights the middle of the face", ability.is_armed() and glow != null and glow.visible)
	var edges := 0
	var start_y := _buddy.global_position.y
	var rise := 0.0
	var drift := 0.0
	var six_frame := -1
	var rides := 0.0
	for attempt in 2:
		if ability.sixes > 0 or not ability.is_active():
			break
		var him := _centre()
		await _mouse_to(Vector2(him.x - 360.0, him.y - hang - 30.0), 1800.0)
		# Not knocked out by an edge before it: a six he cannot take is not a six measured.
		_buddy.health.reset_meter()
		# A run-up at the sweep's own unhurried speed. Trailing behind a moving hand the bat tilts
		# back, and how far below the hand its middle rides then is what the sweep aims with: the
		# middle at his middle. (Measured: a fast flat sweep leads with the handle, a hand held
		# high grazes his skull with the toe, and a bat's hang at rest varies run to run.)
		while _mouse.x < him.x - 230.0:
			_move(_mouse + Vector2(450.0 / 60.0, 0.0))
			await _step()
		rides = ability.middle_world().y - _mouse.y
		var line := him.y - rides
		while _mouse.x < him.x + 200.0 and ability.sixes == 0 and ability.is_active():
			_move(Vector2(_mouse.x + 450.0 / 60.0, move_toward(_mouse.y, line, 4.0)))
			await _step()
		if ability.sixes == 0 and ability.last_blade_t >= 0.0:
			edges += 1
	# From the six: how high he goes, how much of the swing's sideways push was left on him, and
	# where he comes down (a rise of 450 px is two seconds in the air).
	for i in 170:
		if ability.sixes > 0 and six_frame < 0:
			six_frame = i
		rise = maxf(rise, start_y - _buddy.global_position.y)
		if six_frame >= 0 and i - six_frame <= 3:
			drift = maxf(drift, absf(_buddy.linear_velocity.x))
		await _step()
	_check("a hit off the middle is a six (the blade met him at %.2f of its length)" % ability.last_blade_t,
		ability.sixes == 1)
	_check("billed at x%.2f on top of its own" % ability.num("middle_mult", 2.5),
		_boosted_hits(body, ability.num("middle_mult", 2.5)) >= 1)
	_check("and he goes straight up (%.0f px, %.0f px/s sideways at most)" % [rise, drift],
		rise >= 120.0 and drift < ability.num("six_speed", 950.0) * 0.6)
	_check("where he comes down is the bat's", _claimed_seen)
	await _expect_face(&"six", &"launched")
	_check("and the light goes out", glow == null or not glow.visible)
	return {"blade_t": ability.last_blade_t, "rise": rise, "six": ability.last_six, "edges": edges,
		"rides": rides, "hits": _hits.size()}

## Flatten: laid down on the desk beside him and rolled across him and back: two passes, two
## flattenings, and he is squashed on his sprite, not shoved along the desk.
func _drive_rolling_pin(body: WeaponBase, ability: FlattenAbility) -> Dictionary:
	var floor_y := _buddy.get_interaction_rect().end.y
	var him_x := _centre().x
	await _mouse_to(Vector2(him_x - 190.0, floor_y - 60.0), 700.0)
	await _steady(body, 60)
	var start_x := _buddy.global_position.x
	_press(MOUSE_BUTTON_RIGHT)
	await _step(24)
	_check("held, it lies down level (%.0f degrees off)" % ability.level_error, ability.level_error <= 25.0)
	var low := ability.com_world().y
	_check("on the desk (%.0f px above it)" % (floor_y - low), floor_y - low <= 45.0)
	var squashed := 1.0
	var legs := [Vector2(him_x + 150.0, floor_y - 60.0), Vector2(him_x - 190.0, floor_y - 60.0)]
	for leg in legs:
		var guard := 0
		while _mouse.distance_to(leg) > 8.0 and guard < 200:
			_move(_mouse.move_toward(leg, 500.0 / 60.0))
			await _step()
			guard += 1
			if _buddy.art:
				squashed = minf(squashed, _buddy.art._squash.y)
	for i in 12:
		await _step()
		if _buddy.art:
			squashed = minf(squashed, _buddy.art._squash.y)
	_release(MOUSE_BUTTON_RIGHT)
	await _step(3)
	_check("rolled across him and back: two passes (%d)" % ability.passes, ability.passes >= 2)
	_check("each billed once, x%.1f, as its own impulse" % ability.num("flatten_mult", 1.5),
		_boosted_strikes(body, ability.num("flatten_mult", 1.5)) >= 2)
	_check("he is flattened on his sprite (squash %.2f)" % squashed, squashed <= 0.6)
	await _expect_face(&"flattened", &"flattened")
	var moved := absf(_buddy.global_position.x - start_x)
	_check("rolled over, not shoved along (%.0f px)" % moved, moved <= 90.0)
	await _await_cond(func() -> bool: return not ability.is_active(), 90)
	_check("the exception comes off once it is clear of him",
		not body.get_collision_exceptions().has(_buddy))
	_check("and the hand is its own again", body.hand_offset == Vector2.ZERO)
	return {"passes": ability.passes, "speed": ability.last_roll_speed, "impulse": ability.last_flatten,
		"squash": squashed, "moved": moved}

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

## Ricochet: thrown from 250 px with the hand still, it goes into the desk, banks at him and hits
## him harder than a straight throw, and is left where it falls.
func _drive_tyre_iron(body: WeaponBase, ability: RicochetAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-250.0, -80.0), 700.0)
	await _steady(body, 60)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	_check("right throws it out of the hand", not body.dragging and ability.in_flight())
	var done := await _await_cond(func() -> bool: return not ability.is_active(), 300)
	await _step(3)
	await _expect_face(&"incoming", &"blast")
	_check("it banked off the world (%d banks, first at %s)" % [ability.banks_done(),
		ability.bank_points[0].round() if not ability.bank_points.is_empty() else "none"],
		ability.banks_done() >= 1)
	_check("and hit him (%d, at %s)" % [ability.throw_hits, ability.hit_mults], ability.throw_hits >= 1)
	var banked_hit := false
	for m in ability.hit_mults:
		banked_hit = banked_hit or m > 1.0
	_check("a hit after a bank is worth more than a straight one", banked_hit)
	var billed_ok := true
	for impulse in ability.struck:
		billed_ok = billed_ok and _hits_with_impulse(impulse) == 1
	_check("each hit billed once, as its own impulse", billed_ok and not ability.struck.is_empty())
	_check("it comes to rest and the throw is over", done)
	_check("it does not come back: you fetch it", not body.dragging)
	_check("the exception comes off", not body.get_collision_exceptions().has(_buddy))
	return {"banks": ability.banks_done(), "hits": ability.throw_hits, "mults": str(ability.hit_mults),
		"flight": ability.last_flight}

## Pinpoint: held until the crosshair locks on his skull, let go, and the beak goes into that spot,
## x2.5, touching nothing else on the way and barely moving him.
func _drive_war_pick(body: WeaponBase, ability: PinpointAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-130.0, -60.0), 700.0)
	await _steady(body, 60)
	_press(MOUSE_BUTTON_RIGHT)
	await _step(4)
	var cross := ability.get_node_or_null("PinpointCrosshair") as Node2D
	_check("held, a crosshair appears at the beak", cross != null and cross.visible and ability.is_aiming())
	await _step(int(ability.num("charge_seconds", 0.8) * 60.0) + 8)
	var skull := _buddy.get_interaction_rect()
	_check("and walks onto his skull and locks (%s)" % ability.spot().round(),
		ability.is_locked_on() and skull.grow(4.0).has_point(ability.spot()))
	await _expect_face(&"targeted", &"aimed_at")
	var before_hits := _hits.size()
	_release(MOUSE_BUTTON_RIGHT)
	var struck := await _await_cond(func() -> bool: return ability.last_pick > 0.0 or not ability.is_driving(), 40)
	var shove := await _peak_speed(20)
	_check("let go, the beak goes into that spot (within %.0f px)" % ability.last_miss,
		struck and ability.last_pick > 0.0)
	var pick := _hit_with_impulse(ability.last_pick)
	_check("billed once at x%.2f, as its own impulse (%.0f)" % [ability.num("pick_mult", 2.5), ability.last_pick],
		pick != null and _hits_with_impulse(ability.last_pick) == 1 and absf(_mult_of(pick)
		- Progression.damage_mult_for(_id, body.damage_mult) * ability.num("pick_mult", 2.5)) < 0.01)
	_check("touching nothing else on the way (%d contact hits)" % (_hits.size() - before_hits - 1),
		_hits.size() - before_hits == 1)
	_check("and all of it on the spot: he barely moves (%.0f px/s)" % shove, shove <= 400.0)
	await _await_cond(func() -> bool: return not ability.is_active(), 120)
	_check("the exception comes off", not body.get_collision_exceptions().has(_buddy))
	_check("and the hand is its own again", body.hand_offset == Vector2.ZERO)
	return {"miss": ability.last_miss, "point": ability.last_point_speed, "pick": ability.last_pick,
		"him": shove}

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

## Blue Screen: refused out of reach; in reach he is a statue, swung at until he reboots — nothing
## lands and nothing moves him — and then every stored swing is dealt on one frame, x1.3.
func _drive_monitor(body: WeaponBase, ability: BlueScreenAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-560.0, -40.0), 900.0)
	await _steady(body, 30)
	var refused := ability.denied
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("out of reach, the press is refused", ability.denied == refused + 1 and not ability.is_active())
	await _mouse_to(_centre() + Vector2(-150.0, -30.0), 900.0)
	await _steady(body, 40)
	var frames: Array[int] = []
	var impulses: Array[float] = []
	var on_hit := func(info: HitInfo) -> void:
		if info.source_id == _id:
			frames.append(Engine.get_physics_frames())
			impulses.append(info.raw_impulse)
	EventBus.damage_dealt.connect(on_hit)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step(2)
	var at := _buddy.global_position
	_check("in reach, a tap freezes him", ability.is_frozen())
	var screen := body.get_node_or_null("BlueScreen") as Node2D
	_check("the screen goes blue", screen != null and screen.visible)
	await _expect_face(&"frozen", &"frozen")
	_check("staring, his animation held",
		_buddy.art != null and _buddy.art.body != null and is_zero_approx(_buddy.art.body.speed_scale))
	# Swung at him back and forth until the freeze is up, as a player does with a statue.
	var drift := 0.0
	var dealt_frozen := 0
	var swings := 0
	while ability.is_frozen() and swings < 8:
		var him := _centre()
		var target := Vector2(him.x + (200.0 if swings % 2 == 0 else -220.0), him.y - 40.0)
		while _mouse.distance_to(target) > 1.0 and ability.is_frozen():
			_move(_mouse.move_toward(target, 1100.0 / 60.0))
			await _step()
			if ability.is_frozen():
				drift = maxf(drift, _buddy.global_position.distance_to(at))
				dealt_frozen = frames.size()
		swings += 1
	_check("swung through: %d stored, none dealt while he was frozen" % ability.last_stored,
		ability.last_stored >= 2 and dealt_frozen == 0)
	_check("and a statue does not move (%.1f px)" % drift, drift <= 2.0)
	await _await_cond(func() -> bool: return not ability.is_active(), 120)
	await _step(3)
	EventBus.damage_dealt.disconnect(on_hit)
	# The dump's own hits are the ones it handed him; anything after is the monitor still swinging.
	var dump_frames := {}
	for i in frames.size():
		for impulse in ability.struck:
			if absf(impulses[i] - impulse) <= 0.5:
				dump_frames[frames[i]] = true
	_check("he comes back and all %d land at once, on one frame (%d frames)" % [ability.last_stored,
		dump_frames.size()], ability.last_dumped == ability.last_stored and dump_frames.size() == 1)
	_check("each once, at x%.2f" % ability.num("dump_mult", 1.3),
		_boosted_strikes(body, ability.num("dump_mult", 1.3)) == ability.last_stored)
	_check("and it throws him (%.0f px/s)" % ability.last_dump_speed, ability.last_dump_speed > 0.0)
	_check("he is not frozen any more", not _buddy.freeze)
	return {"stored": ability.last_stored, "dealt": frames.size(), "drift": drift,
		"thrown": ability.last_dump_speed}

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

# --- transform, tether and clamp (D74, the new archetypes) -----------------------------------

## Lead Heart and Ignite: one tap changes it for its seconds. Then the hand works on him as a
## player's would — a heavy one swung through him, one that passes through him drawn slowly back
## and forth inside him — and it changes back when its time is up, weight and all.
func _drive_transform(body: WeaponBase, ability: TransformAbility) -> Dictionary:
	var mass := body.mass
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("a tap changes it (%.1f s left)" % ability.time_left(), ability.is_changed())
	var weight := ability.num("mass_mult", 1.0)
	_check("it weighs %.1fx what it did (%.1f -> %.1f kg)" % [weight, mass, body.mass],
		is_equal_approx(body.mass, mass * weight))
	var light := ability.sprite().get_node_or_null("AbilityLight") as CanvasItem if ability.sprite() else null
	_check("and it glows", light != null and light.visible)
	var contact := 0
	if ability.is_phased():
		_check("it goes through him", body.get_collision_exceptions().has(_buddy))
		var him := _centre()
		var side := -1.0
		for i in 8:
			if not ability.is_changed():
				break
			him = _centre()
			await _mouse_to(Vector2(him.x + 70.0 * side, him.y + 10.0), 260.0)
			side = -side
		for info in _hits:
			var own := false
			for impulse in ability.struck:
				own = own or absf(info.raw_impulse - impulse) <= 0.5
			if not own:
				contact += 1
		_check("drawn through him it burns him (%d burns, %.2f s inside)"
			% [ability.burns, ability.inside_seconds], ability.burns >= 3)
		_check("each burn billed as its own impulse at x%.2f" % ability.num("burn_mult", 1.0),
			_hits_with_impulse(ability.num("burn_force", 700.0)) >= 3)
		_check("and the blade never touched him (%d contact hits)" % contact, contact == 0)
		await _expect_face(&"scorched", &"scorched")
	else:
		var swings := 0
		while ability.is_changed() and swings < 4 and ability.blows < 2:
			await _sweep_through(900.0, 1300.0)
			swings += 1
		await _step(3)
		_check("its blows land (%d)" % ability.blows, ability.blows >= 1)
		_check("billed at x%.2f on top of its own" % ability.num("hit_mult", 1.0),
			_boosted_hits(body, ability.num("hit_mult", 1.0)) >= 1)
		await _expect_face(&"crushed", &"crushed")
	await _await_cond(func() -> bool: return not ability.is_changed(), 360)
	_check("it changes back when its time is up", not ability.is_changed())
	_check("and its weight with it (%.1f kg)" % body.mass, is_equal_approx(body.mass, mass))
	_check("the light goes out", light == null or not light.visible)
	await _await_cond(func() -> bool: return not ability.is_active(), 90)
	_check("the exception comes off once it is clear of him",
		not body.get_collision_exceptions().has(_buddy))
	return {"blows": ability.blows, "burns": ability.burns, "inside": ability.inside_seconds,
		"kg": ability.peak_mass, "hits": _hits.size()}

## The three tethers, each used the way its line says.
func _drive_tether(body: WeaponBase, ability: TetherAbility) -> Dictionary:
	if ability is HookTether:
		return await _drive_hook(body, ability as HookTether)
	if ability is PryTether:
		return await _drive_pry(body, ability as PryTether)
	return await _drive_wrap(body, ability)

## Wrap: right held while it is swung through him; caught, he is swung round on it by the hand, and
## letting go of right flings him.
func _drive_wrap(body: WeaponBase, ability: TetherAbility) -> Dictionary:
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("right arms the chain", ability.is_armed())
	var swings := 0
	while ability.is_armed() and swings < 3:
		await _sweep_through(900.0, 1300.0)
		swings += 1
	await _step(2)
	_check("a hit with it armed wraps him (%d caught)" % ability.catches, ability.is_holding())
	_check("and he and it do not collide while he is on it",
		body.get_collision_exceptions().has(_buddy))
	await _expect_face(&"wrapped", &"wrapped")
	# The hand goes up into the open and round: he is the ball on the chain.
	var start := _buddy.global_position
	var centre := Vector2(640.0, 380.0)
	await _mouse_to(centre + Vector2(120.0, 0.0), 1200.0)
	var gap := 0.0
	var travelled := 0.0
	var last := start
	for i in 50:
		if not ability.is_holding():
			break
		var a := TAU * float(i) / 36.0
		_move(centre + Vector2(cos(a) * 120.0, sin(a) * 70.0))
		await _step()
		gap = maxf(gap, ability.him_world().distance_to(ability.com_world()))
		travelled += _buddy.global_position.distance_to(last)
		last = _buddy.global_position
	var rope := ability.num("rope", 0.0)
	_check("he is kept on the chain (never %.0f px from the head, the chain is %.0f)" % [gap, rope],
		gap <= rope + 60.0)
	_check("round with the hand (%.0f px travelled)" % travelled, travelled >= 200.0)
	_release(MOUSE_BUTTON_RIGHT)
	await _step(3)
	_check("letting go of right flings him (%.0f px/s)" % ability.last_fling,
		ability.flung and ability.last_fling >= 400.0)
	_check("and where he lands is the flail's", _buddy.impacts_claimed_by() == _id)
	await _expect_face(&"flung", &"launched")
	await _step(90)
	var landed := 0.0
	for info in _claimed:
		landed += info.amount
	await _await_cond(func() -> bool: return not ability.is_active(), 90)
	_check("the exception comes off once they are clear", not body.get_collision_exceptions().has(_buddy))
	return {"caught": ability.catches, "held": ability.held_for, "peak": ability.peak_speed,
		"fling": ability.last_fling, "landed": landed, "hits": _hits.size()}

## Hook and Spike: from 230 px off, a tap; the hook catches him and reels him onto the spike.
func _drive_hook(body: WeaponBase, ability: HookTether) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-230.0, -60.0), 700.0)
	await _steady(body, 60)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	_check("a tap throws the hook (his body %.0f px from the spike)" % ability.last_gap,
		ability.is_reaching() or ability.catches > 0)
	var caught := await _await_cond(func() -> bool: return ability.catches > 0 or not ability.is_active(), 40)
	_check("it catches him (%.0f px out)" % ability.last_reach, caught and ability.catches > 0)
	await _expect_face(&"hooked", &"hooked")
	await _await_cond(func() -> bool: return ability.spiked or not ability.is_holding(), 90)
	_check("he is reeled onto the spike (at %.0f px/s)" % ability.last_arrival, ability.spiked)
	await _step(3)
	var spike := _hit_with_impulse(ability.last_spike)
	_check("billed once, as its own impulse at x%.2f (%.0f)" % [ability.num("spike_mult", 1.5),
		ability.last_spike], spike != null and _hits_with_impulse(ability.last_spike) == 1
		and absf(_mult_of(spike) - Progression.damage_mult_for(_id, body.damage_mult)
		* ability.num("spike_mult", 1.5)) < 0.01)
	await _expect_face(&"spiked", &"launched")
	var thrown := await _peak_speed(20)
	await _await_cond(func() -> bool: return not ability.is_active(), 90)
	_check("the exception comes off once they are clear", not body.get_collision_exceptions().has(_buddy))
	return {"reach": ability.last_reach, "arrival": ability.last_arrival, "spike": ability.last_spike,
		"thrown": thrown, "hits": _hits.size()}

## Pry: refused anywhere but against him; the claw against him, right held and the hand pulled down,
## he rises; let go and he pops.
func _drive_pry(body: WeaponBase, ability: PryTether) -> Dictionary:
	var refused := ability.denied
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("away from him the press is refused", ability.denied == refused + 1 and not ability.is_active())
	# The claw to his near lower side: carried there by the hand, which is wherever puts it there.
	# The crowbar hangs from the hand with the claw at the bottom. Carried slowly across to him with
	# the hand a bar's length above his lower half, from whichever side has room, the claw meets his
	# side — the way a player does it, and without sweeping him along the desk first.
	var side := -1.0 if _centre().x > float(VIEW_SIZE.x) * 0.5 else 1.0
	var bar := ability.grip_world().distance_to(ability.tip_world())
	var level := _buddy.get_interaction_rect().end.y - 40.0 - bar
	await _mouse_to(Vector2(_centre().x + side * 150.0, level), 600.0)
	await _steady(body, 60)
	for i in 300:
		if ability.touches_him(ability.tip_world(), ability.num("reach", 30.0) - 8.0):
			break
		level = _buddy.get_interaction_rect().end.y - 40.0 - bar
		var to := Vector2(_centre().x, level)
		_move(_mouse.move_toward(to, clampf(_mouse.distance_to(to) / 30.0, 1.5, 8.0)))
		await _step()
	var top := _buddy.global_position.y
	var claw := ability.tip_world()
	var rect := _buddy.get_interaction_rect()
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("with the claw against him it wedges (claw %s, him %s)" % [claw.round(), rect],
		ability.is_holding())
	await _expect_face(&"pried", &"pried")
	var hand := _mouse
	await _mouse_to(hand + Vector2(0.0, 70.0), 220.0)
	await _step(10)
	var rise := top - _buddy.global_position.y
	_check("pulling the hand down levers him up (%.0f px, %.0f%% of the way)" % [rise,
		ability.lift() * 100.0], rise >= 30.0 and ability.lift() >= 0.5)
	_check("tipped away from the bar (%.0f degrees)" % rad_to_deg(_buddy.global_rotation),
		absf(_buddy.global_rotation) >= deg_to_rad(5.0))
	_release(MOUSE_BUTTON_RIGHT)
	await _step(3)
	_check("letting go pops him up and over (%.0f px/s)" % ability.last_pop, ability.popped)
	var pry := _hit_with_impulse(ability.last_pull)
	_check("the pry billed once at x%.2f (%.0f)" % [ability.num("pry_mult", 1.3), ability.last_pull],
		pry != null and _hits_with_impulse(ability.last_pull) == 1)
	await _expect_face(&"flung", &"launched")
	var peak := await _peak_speed(40)
	await _step(60)
	await _await_cond(func() -> bool: return not ability.is_active(), 90)
	_check("the exception comes off once they are clear", not body.get_collision_exceptions().has(_buddy))
	return {"lift": ability.last_lift, "rise": rise, "pop": ability.last_pop, "pull": ability.last_pull,
		"peak": peak, "hits": _hits.size()}

## The three clamps: the jaws brought to him the way a player brings them, a tap, and what the bite
## does — a hole and confetti, his headphones off and back on, or a crank as the hand goes round.
func _drive_clamp(body: WeaponBase, ability: ClampAbility) -> Dictionary:
	var head := bool(ability.row.get("snip_head", false))
	await _jaws_to_him(body, ability, head)
	_check("the jaws are on him (%s, him %s)" % [ability.jaw_world().round(),
		_buddy.get_interaction_rect()], ability.in_jaws())
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	var bites := int(ability.num("bites", 1.0))
	await _await_cond(func() -> bool: return ability.bites_closed >= bites, 60)
	var decided := func() -> bool: return ability._phase != ClampAbility.BITING or not ability.is_active()
	await _await_cond(decided, 30)
	await _step(2)
	_check("a tap closes the jaws %d times (%d)" % [bites, ability.bites_closed], ability.bites_closed == bites)
	_check("and they land on him (%d)" % ability.bites_landed, ability.bites_landed >= 1)
	_check("each bite billed as its own impulse at x%.2f" % ability.num("bite_mult", 1.0),
		_hits_with_impulse(ability.last_bite) == ability.bites_landed)
	var measured := {"bites": ability.bites_landed, "bite": ability.last_bite}
	if ability.num("hole_seconds", 0.0) > 0.0:
		var hole := _buddy.get_node_or_null("PunchedHole")
		_check("it leaves a hole in him", hole != null)
		await _expect_face(&"punched", &"punched")
		await _step(int(ability.num("hole_seconds", 3.0) * 60.0) + 10)
		_check("and the hole closes when its time is up", not is_instance_valid(hole)
			or hole.is_queued_for_deletion())
	if head:
		_check("a snip at his head takes his headphones off", ability.snipped)
		_check("his own are hidden while they are off", _phones_off())
		var phones: Node = null
		for node in _stage.get_children():
			if node is ClampAbility.Headphones:
				phones = node
		_check("and they are on the desk", phones != null)
		await _expect_face(&"snipped", &"snipped")
		# Glum for as long as they are off, once the gasp and the glare have had their second.
		var glum := func() -> bool: return _faces.any(func(pair: Array) -> bool:
			return pair[0] == &"bareheaded" and pair[1] == &"bareheaded")
		await _await_cond(glum, 150)
		await _expect_face(&"bareheaded", &"bareheaded")
		# Their return is checked where anything left behind is (`_leftovers`): it outlasts the
		# cooldown, and the shears are binned before it — which is the point, since the headphones
		# have to find their own way home.
	if ability.num("hold_seconds", 0.0) > 0.0:
		_check("the first bite clamps on", ability.is_clamped())
		_check("and they do not collide while it is on", body.get_collision_exceptions().has(_buddy))
		# The hand goes round him: he turns like a nut.
		var start := _buddy.global_rotation
		var centre := _centre()
		var radius := maxf(_mouse.distance_to(centre), 110.0)
		var a0 := (_mouse - centre).angle()
		for i in 130:
			if not ability.is_clamped():
				break
			var a := a0 + TAU * 1.4 * float(i) / 120.0
			_move(_centre() + Vector2(cos(a), sin(a)) * radius)
			await _step()
		_check("circling the hand turns him (%.1f turns)" % ability.turns, ability.turns >= 0.75)
		_check("every half turn a crank (%d)" % ability.cranks, ability.cranks >= 1)
		_check("each billed as its own impulse at x%.2f" % ability.num("crank_mult", 1.0),
			_hits_with_impulse(ability.num("crank_force", 1500.0)) == ability.cranks)
		await _expect_face(&"cranked", &"cranked")
		await _await_cond(func() -> bool: return not ability.is_active(), 180)
		_check("it lets go when its time is up", not ability.is_clamped())
		_check("the hand is its own again", body.hand_offset == Vector2.ZERO)
		_check("the exception comes off once they are clear", not body.get_collision_exceptions().has(_buddy))
		measured["turns"] = ability.turns
		measured["cranks"] = ability.cranks
		measured["rotated"] = rad_to_deg(_buddy.global_rotation - start)
	measured["hits"] = _hits.size()
	return measured

## The jaws brought to him the way a player brings them: the weapon hanging still from the hand,
## the hand at the height that puts the jaws level with the point — the side of his head for shears
## after his headphones, his side otherwise — and then across to him, slowly as it nears, until he
## is between them. Across and not along a feedback on the jaws: a weapon pushed at him pushes him
## along the desk ahead of it, and the jaws chase him into the wall.
func _jaws_to_him(body: WeaponBase, ability: ClampAbility, head: bool) -> void:
	for i in 120:
		if _buddy.is_grounded() and _buddy.linear_velocity.length() < 5.0:
			break
		await _step()
	# Lifted clear first, so it hangs freely from the hand; then the hand put where that hang sets
	# the jaws level with the point and well clear of him; then across to him, level and slowly,
	# until he is between them. A weapon resting on the desk does not follow a hand that goes down,
	# and one pushed at him pushes him along the desk ahead of it. The point is his head for shears
	# after his headphones — wherever his head is: after a few swings he is as likely lying on his
	# side, head to one side, as standing — and his middle otherwise.
	var rect := _buddy.get_interaction_rect()
	var aim := _buddy.to_global(Vector2(0.0, -40.0)) if head else _centre() + Vector2(0.0, 10.0)
	var along := aim.x - _centre().x
	var side := signf(along) if absf(along) > 20.0 else (-1.0 if _centre().x > float(VIEW_SIZE.x) * 0.5 else 1.0)
	var clear := Vector2(aim.x + side * 150.0, rect.position.y - 90.0)
	await _mouse_to(clear, 600.0)
	await _hang_still(body)
	var hang := ability.jaw_world() - ability.hand_world()
	var point := Vector2(aim.x + side * 110.0, aim.y)
	await _mouse_to((point - hang).clamp(Vector2(10, 10), Vector2(VIEW_SIZE) - Vector2(10, 10)), 400.0)
	await _hang_still(body)
	for i in 400:
		if ability.in_jaws():
			break
		_move(_mouse + Vector2(-side * 1.5, 0.0))
		await _step()

## Until it hangs still from the hand: slow in both speed and spin for a sixth of a second. A
## pendulum is slow at the end of every swing, so a speed alone catches it mid-swing.
func _hang_still(body: RigidBody2D) -> void:
	var calm := 0
	for i in 240:
		_move(_mouse)
		await _step()
		calm = calm + 1 if body.linear_velocity.length() < 12.0 and absf(body.angular_velocity) < 0.4 else 0
		if calm >= 10:
			return

func _phones_off() -> bool:
	if not is_instance_valid(_buddy) or _buddy.art == null or _buddy.art.body == null:
		return false
	var material := _buddy.art.body.material as ShaderMaterial
	if material == null:
		return false
	var value = material.get_shader_parameter(&"phones_off")
	return value != null and float(value) > 0.5

## What a weapon made heavier added beyond its multiplier: each boosted blow, unboosted, less an
## ordinary hit. The weight is in the swing, so it is in the impulse he measured, not in a number.
func _heavier(body: WeaponBase, ordinary: float) -> float:
	var base := Progression.damage_mult_for(_id, body.damage_mult)
	var extra := 0.0
	for info in _hits:
		var m := _mult_of(info) / base
		if m > 1.0005 and not _capped(info):
			extra += maxf(info.amount / m - ordinary, 0.0)
	return extra

# --- D78: beyond the melee drawer ---------------------------------------------------------------
#
# The same button on a ball, a care item, a box of donuts and two charges. Each row gets the life a
# weapon's does — it carries its ability, nothing runs at rest, the bin grammar holds, one use is
# one use, his face answers, everything goes through the real pipeline, the cooldown is refused and
# comes back, nothing is left behind — measured by what it is rather than by an ordinary swing:
#
#   - a kind row by the kindness it paid, on the bus, as Hearts, and never a hit; its `worth` is the
#     part of that the item would not have paid without it, in pets;
#   - a charge by its blast against an ordinary blast of the same charge, placed the ordinary way;
#   - the bowling ball, which is a `WeaponBase`, by an ordinary hit as a weapon is.

## Where a charge sticks or lands moves its blast by this much of an ordinary one, run to run: a
## sticky bomb clicked at 3.7 s is on a different part of him than one that went at 2.2 s.
const FUSE_NOISE := 0.5

## Every drawer the right button may be given in (D78): all but the guns and the powers, whose
## right is already theirs (D56, D72).
const D78_DRAWERS: Array[int] = [ItemData.CATEGORY_THROWABLE, ItemData.CATEGORY_FRIENDLY,
	ItemData.CATEGORY_TOY, ItemData.CATEGORY_TURRET, ItemData.CATEGORY_CRITTER,
	ItemData.CATEGORY_COMFORT, ItemData.CATEGORY_FOOD, ItemData.CATEGORY_AMBIENCE]

## What the item under test emitted on the bus, and the Hearts it came back as.
var _kind_acts: Array[float] = []
var _kind_rates: Array[float] = []
var _kind_hearts := 0

func _on_kind_act(source_id: StringName, value: float, _at: Vector2) -> void:
	if _id != &"" and source_id == _id:
		_kind_acts.append(value)

func _on_kind_rate(source_id: StringName, value: float, _at: Vector2) -> void:
	if _id != &"" and source_id == _id:
		_kind_rates.append(value)

func _on_kind_payout(currency: StringName, amount: float, _at: Vector2, source_id: StringName) -> void:
	if _id != &"" and source_id == _id and currency == Economy.HEARTS and amount > 0.0:
		_kind_hearts += 1

func _reset_probes() -> void:
	_hits.clear()
	_claimed.clear()
	_claimed_seen = false
	_faces.clear()
	_pipeline_bad.clear()
	_kind_acts.clear()
	_kind_rates.clear()
	_kind_hearts = 0

func _sum(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total

func _damage_total() -> float:
	var total := 0.0
	for info in _hits:
		total += info.amount
	return total

## The rows D78 added, as data: each on a side it can pay on, a kind row no faster than D67's
## ceiling, and none on a thing whose right while held is already its own.
func _the_d78_rows() -> void:
	_suite("D78: the rows beyond the melee drawer")
	var count := 0
	for id in AbilityTable.item_ids():
		var item := ItemDB.get_item(id)
		if item == null or item.category == ItemData.CATEGORY_WEAPON:
			continue
		count += 1
		var row := AbilityTable.row_for(id)
		var kind := AbilityTable.is_kind(id)
		_check("%s's row is %s, and the item is bought with %s" % [id, "kind" if kind else "harm",
			item.currency_id()], kind == (item.currency == ItemData.CURRENCY_HEARTS and item.is_kind()))
		if kind:
			_check("%s pays %.2f value a second at most, under D67's ceiling of %.1f" % [id,
				AbilityTable.kindness_rate(id), AbilityTable.KIND_CEILING],
				AbilityTable.kindness_rate(id) <= AbilityTable.KIND_CEILING + 0.0001)
			_check("and adds no damage to the sim", is_equal_approx(AbilityTable.damage_uplift(id, 1.5), 1.0))
		else:
			_check("%s adds no kindness to the sim" % id, is_equal_approx(AbilityTable.kindness_uplift(id, 3.0), 1.0))
		var node: Node = item.scene.instantiate() if item.scene else null
		var draggable := node is BaseDraggable
		var own_right := node is HeldGun or node is FidgetToy
		if node:
			for child in node.get_children():
				if child is GestureZones and (child as GestureZones).action_enabled:
					own_right = true
			node.free()
		_check("%s is a thing in the hand, whose right press was not already its own" % id,
			draggable and not own_right)
		if row.get("archetype", &"") == &"fuse":
			_check("%s, a fuse, is on a charge" % id, item.category == ItemData.CATEGORY_THROWABLE)
	_check("%d rows beyond the melee drawer" % count, count >= 8)

## One D78 row, on a desk of its own.
func _check_held_ability(id: StringName) -> void:
	var row := AbilityTable.row_for(id)
	var kind := AbilityTable.is_kind(id)
	var fuse := StringName(row.get("archetype", &"")) == &"fuse"
	_id = id
	_clear_slot()
	SaveManager.load_game()
	await _build_stage()
	_own(id)
	_catch.take()
	seed(hash(String(id)))
	_reset_probes()

	# A charge is measured against an ordinary blast of itself, set off the ordinary way first.
	var ordinary := 0.0
	if fuse:
		ordinary = await _ordinary_blast(id)
		_check("an ordinary blast lands (%.1f)" % ordinary, ordinary > 0.0)

	var body := await _spawn_any(id, _centre() + Vector2(-260.0, -150.0))
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

	# --- lying on the desk ---------------------------------------------------------------
	await _await_still(body, 60)
	_check("at rest nothing of it runs", not ability.is_busy())
	if fuse:
		_check("right on it lying there is still its fuse, never the bin (D59)",
			body.right_click_is_mine() and not body.click_would_bin(false) and body.click_would_bin(true))
	else:
		_check("right on it lying there is still the bin",
			not body.right_click_is_mine() and body.click_would_bin(false) and body.click_would_bin(true))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	_check("a right press on it unheld is not the ability", not ability.take(press) and ability.uses == 0)

	# --- in the hand -----------------------------------------------------------------------
	if not await _grab(body):
		_check("its grab region takes a click", false)
		await _free_stage()
		return
	_check("held, right is its own and Shift+right is still the bin",
		body.right_click_is_mine() and not body.click_would_bin(false) and body.click_would_bin(true))
	# How it reads (D77), the same four stages as a melee weapon's, through `AbilityCues`.
	var glint := ability.ready_glint()
	_check("held and ready, it wears its ready glint", glint != null and glint.visible)
	_check("and the glint costs nothing: no tick of its own", glint == null or not glint.is_processing())
	if body is WeaponBase:
		_buddy.health.reset_meter()
		ordinary = await _ordinary_hit(body as WeaponBase)
		_check("an ordinary swing lands (%.1f a hit)" % ordinary, ordinary > 0.0)
	await _settle_him()
	_reset_probes()
	var before_uses := ability.uses
	# Held by reference: a charge goes with its blast and takes its ability with it.
	var said := ability.fx_said
	var shown := ability.fx_states
	var paid := ability.fx_paid
	var look := ability.look()

	var driver := "_drive_%s" % row.get("id", "")
	if not has_method(driver):
		_check("a driver for %s — add `%s` before this ability can ship" % [row.get("id", ""), driver],
			false)
		await _free_stage()
		return
	var measured: Dictionary = await call(driver, body, ability)
	# A charge is spent with its blast: its ability goes with it, and is never read once it may be.
	var uses := int(measured.get("uses", -1))
	if uses < 0 and not fuse and is_instance_valid(ability):
		uses = ability.uses
	_check("one use was counted", uses == before_uses + 1)

	# --- how it read (D77) ---------------------------------------------------------------------
	_check("it called out \"%s\" as it began" % look["call"], said.has(String(look["call"])))
	_check("it put a state up, over him or over itself (%s)" % str(shown), not shown.is_empty())
	_check("its payoff was drawn where it landed (%s)" % str(paid), not paid.is_empty())
	var own_words := [String(look["call"]), String(look["go"])]
	var landing_words := said.filter(func(w: String) -> bool: return not own_words.has(w))
	_check("and a word for it (%s)" % str(landing_words), not landing_words.is_empty())

	# --- what it paid ----------------------------------------------------------------------
	await _step(20)
	var consumed := fuse or _gone(body) or not is_instance_valid(ability)
	var worth := 0.0
	var declared := float(row.get("worth", 0.0))
	if kind:
		_check("a kind ability bills him nothing (%d hits)" % _hits.size(), _hits.is_empty())
		var events := _kind_acts.size() + _kind_rates.size()
		_check("everything it paid went on the bus and came back as Hearts (%d events, %d payouts)"
			% [events, _kind_hearts], events > 0 and _kind_hearts == events)
		worth = float(measured.get("extra", ability.given_extra if not consumed else 0.0))
		_check("one use added %.1f value of its own, and the row says %.1f (x%.1f slack)"
			% [worth, declared, WORTH_SLACK], worth > 0.0 and worth <= declared * WORTH_SLACK)
	else:
		_check("every hit was paid through the pipeline to the unit%s"
			% ("" if _pipeline_bad.is_empty() else ": " + _pipeline_bad[0]), _pipeline_bad.is_empty())
		if not consumed and body is WeaponBase:
			var bad_mult := _bad_multiplier(body as WeaponBase)
			_check("every hit it caused carries a multiplier the data allows%s" % bad_mult, bad_mult == "")
			worth = _extra_damage(body as WeaponBase, archetype, ordinary) / maxf(ordinary, 0.01)
		else:
			worth = float(measured.get("blast", 0.0)) / maxf(ordinary, 0.01) - 1.0
		_check("one use added %.2f ordinary %s' worth, and the row says %.2f (x%.1f slack)"
			% [worth, "blasts" if fuse else "hits", declared, WORTH_SLACK],
			worth <= maxf(declared, 0.05) * WORTH_SLACK + (FUSE_NOISE if fuse else 0.0))

	if consumed:
		# A charge is gone with its blast; there is no cooldown to wait out and nothing to bin.
		_check("it is used up, and gone from the desk", _gone(body))
	else:
		# --- the cooldown ---------------------------------------------------------------
		if not body.dragging:
			await _grab(body)
		await _await_cond(func() -> bool: return not ability.is_active(), 600)
		_check("its effect ends", not ability.is_active())
		_check("and it is cooling down (%.1f s)" % ability.cooldown_left(), ability.is_cooling())
		var used := ability.uses
		var refused := ability.denied
		_press(MOUSE_BUTTON_RIGHT)
		await _step(2)
		_release(MOUSE_BUTTON_RIGHT)
		await _step(2)
		_check("a press inside the cooldown is refused", ability.uses == used and ability.denied == refused + 1)
		_check("and does not throw it away", not _gone(body) and body.dragging)
		var pip := ability.get_node_or_null("AbilityPip") as Node2D
		_check("the pip is drawn by the hand while it cools", pip != null and pip.visible)
		glint = ability.ready_glint()
		_check("and the ready glint is gone while it cools", glint == null or not glint.visible)
		var readied := ability.fx_readied
		var wait := int((ability.cooldown_left() + 0.3) * 60.0)
		await _await_cond(func() -> bool: return ability.is_ready(), wait + 60)
		_check("it is ready again when the cooldown is up", ability.is_ready())
		_check("and the pip is gone", pip == null or not pip.visible)
		glint = ability.ready_glint()
		_check("and the glint is back, with a pop", not ability.is_ready() or (glint != null
			and glint.visible and ability.fx_readied == readied + 1))
		# What an ability puts back when it is ready again, if it puts anything back: a candle.
		var after := "_after_cooldown_%s" % row.get("id", "")
		if has_method(after):
			await call(after, body, ability)

		# --- at rest, and away ------------------------------------------------------------
		_release(MOUSE_BUTTON_LEFT)
		await _await_still(body, 90)
		await _step(4)
		_check("put down and idle, nothing of it runs", not ability.is_busy())
		_check("and its glint is not drawn on the desk", glint == null or not glint.visible)
		if await _grab(body):
			_move(_grab_point(body))
			await _step(2)
			_press(MOUSE_BUTTON_RIGHT, true)
			_release(MOUSE_BUTTON_RIGHT, true)
			await _step(3)
			_check("Shift+right in the hand bins it", _gone(body))
	_release_all()
	var errors := _catch.take()
	_check("nothing was pushed to the error log%s" % ("" if errors.is_empty() else ": " + errors[0]),
		errors.is_empty())
	await _step(60)
	_check("and nothing of it is left behind", _leftovers() == "" and _d78_leftovers() == "")

	measured.erase("uses")
	measured.erase("extra")
	measured["ordinary"] = ordinary
	measured["worth"] = worth
	_report.append("%-14s %s" % [id, _format(measured)])
	await _free_stage()

func _spawn_any(id: StringName, at: Vector2) -> BaseDraggable:
	EventBus.spawn_requested.emit(id, at)
	var node: Node = _spawner._active.back() if not _spawner._active.is_empty() else null
	await _step(2)
	return node as BaseDraggable

## What D78's abilities could leave behind that D74's could not: a drop, a donut, a light, a towel
## still over him.
func _d78_leftovers() -> String:
	if not is_instance_valid(_stage):
		return ""
	for node in _stage.get_children():
		if node is AbilityShot and not node.is_queued_for_deletion():
			return "a %s" % String(node.name).to_lower()
	if is_instance_valid(_buddy) and _buddy.get_collision_exceptions().size() > 0:
		return "an exception on him"
	return ""

## The charge set off the ordinary way, for what an ordinary blast of it is worth: lit, and put on
## him (a sticky bomb) or let go beside him (anything else).
func _ordinary_blast(id: StringName) -> float:
	var probe := await _spawn_any(id, _centre() + Vector2(-260.0, -150.0)) as ThrowableBase
	if probe == null:
		return 0.0
	await _await_still(probe, 60)
	if not await _grab(probe):
		probe.bin_myself()
		return 0.0
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	if probe is StickyBomb:
		await _stick_on_him(probe as StickyBomb)
	else:
		# Let go just clear of his side, above the desk, the best an ordinary throw can do without
		# touching him: carried in against him it shoves him out of its own blast (107 px, measured),
		# and dropped on his head it bills the bump.
		var rect := _buddy.get_interaction_rect()
		var beside := Vector2(rect.position.x - 30.0, rect.get_center().y - 20.0)
		await _mouse_to(Vector2(_mouse.x, rect.position.y - 120.0), 800.0)
		await _mouse_to(Vector2(beside.x, rect.position.y - 120.0), 800.0)
		await _mouse_to(beside, 500.0)
		await _steady(probe, 30)
		_release(MOUSE_BUTTON_LEFT)
	# Only the blast: carrying it into place may have bumped him, which is its own contact.
	_hits.clear()
	# A plain loop, not `_await_cond`: a lambda holding the charge errors every frame once it is freed.
	for i in 480:
		if _gone(probe):
			break
		await _step()
	await _step(60)
	var total := _damage_total()
	_hits.clear()
	await _settle_him()
	return total

## Carried into him until it sticks, then let go of.
func _stick_on_him(bomb: StickyBomb) -> void:
	await _mouse_to(_centre() + Vector2(-160.0, -30.0), 800.0)
	await _steady(bomb, 30)
	for i in 90:
		if bomb.is_stuck():
			break
		_move(_mouse.move_toward(_centre(), 10.0))
		await _step()
	_release(MOUSE_BUTTON_LEFT)
	await _step(4)

# --- D78 drivers --------------------------------------------------------------------------------

## Strike: bowled from beside him at desk height, it rolls in along the desk, billed once at its
## multiplier, and he goes over like a pin, his landing the ball's.
func _drive_strike(body: BaseDraggable, ability: StrikeAbility) -> Dictionary:
	var start := Vector2(_centre().x - 330.0, _centre().y)
	await _mouse_to(Vector2(_mouse.x, start.y - 60.0), 700.0)
	await _mouse_to(start, 700.0)
	await _steady(body, 60)
	await _settle_him()
	_reset_probes()
	var turned_from := _buddy.rotation
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("a tap bowls it: it leaves the hand", not body.dragging and ability.is_active())
	var peak := 0.0
	for i in 180:
		peak = maxf(peak, absf(body.linear_velocity.x))
		if ability.strikes > 0 or not ability.is_active():
			break
		await _step()
	_check("it rolls along the desk at him (%.0f px/s)" % peak, peak >= ability.num("roll_speed", 900.0) * 0.6)
	_check("and it reaches him: a strike", ability.strikes == 1)
	var claimed := _buddy.impacts_claimed_by() == _id
	await _step(3)
	var hit := _hit_with_impulse(ability.last_hit)
	var base := Progression.damage_mult_for(_id, (body as WeaponBase).damage_mult)
	var want := base * ability.num("strike_mult", 1.5)
	_check("the strike is billed once as its own impulse, at x%.2f" % ability.num("strike_mult", 1.5),
		_hits_with_impulse(ability.last_hit) == 1 and hit != null
		and (_capped(hit) or absf(_mult_of(hit) - want) <= 0.001 * want))
	var turned := 0.0
	for i in 50:
		turned = maxf(turned, absf(angle_difference(turned_from, _buddy.rotation)))
		await _step()
	_check("he goes over like a pin (%.2f rad)" % turned, turned >= 0.6)
	_check("and where he comes down is the ball's", claimed)
	await _expect_face(&"bowled", &"bowled")
	await _await_cond(func() -> bool: return not ability.is_active(), 240)
	_check("it stays where it rolled: a bowling ball is fetched", not body.dragging)
	return {"speed": peak, "arrived": ability.arrived_at, "strike": ability.last_hit, "turned": turned,
		"hits": _hits.size()}

## Curveball: pitched from 300 px, it breaks down into his hands, pays two catches, and he throws
## it back to the hand that is still holding left.
func _drive_curveball(body: BaseDraggable, ability: CurveballAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-300.0, -30.0), 700.0)
	await _steady(body, 60)
	await _settle_him()
	_reset_probes()
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("a tap pitches it (%.0f px/s)" % ability.last_throw_speed, not body.dragging and ability.is_active())
	await _await_cond(func() -> bool: return ability.catches > 0 or not ability.is_active(), 150)
	_check("it breaks late (%.0f px/s of bend)" % ability.bend, ability.broke and ability.bend >= 150.0)
	_check("and drops into his hands: caught", ability.catches == 1)
	var catch_value := ability._catch_value()
	var curve := ability.num("curve_mult", 2.0)
	_check("a curveball pays two catches (%.1f), one of them its own (%.1f)" % [ability.given,
		ability.given_extra], is_equal_approx(ability.given, catch_value * curve)
		and is_equal_approx(ability.given_extra, catch_value * (curve - 1.0)))
	await _expect_face(&"caught_it", &"catch")
	await _await_cond(func() -> bool: return ability.thrown_back or not ability.is_active(), 90)
	_check("he throws it back", ability.thrown_back)
	await _await_cond(func() -> bool: return body.dragging or not ability.is_active(), 240)
	_check("and it comes home to the hand", ability.caught and body.dragging)
	return {"speed": ability.last_throw_speed, "bend": ability.bend, "caught": ability.catches,
		"home": ability.caught}

## Keepy-Uppy: lobbed from beside him, he heads it up four times and the last one home.
func _drive_keepy_uppy(body: BaseDraggable, ability: KeepyUppyAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-220.0, -60.0), 700.0)
	await _steady(body, 60)
	await _settle_him()
	_reset_probes()
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("a tap lobs it", not body.dragging and ability.is_active())
	await _await_cond(func() -> bool: return ability.headed_home or not ability.is_active(), 480)
	var want := int(ability.num("headers", 4))
	_check("he heads it up %d times (%d)" % [want, ability.count], ability.count == want)
	_check("each header an act on the bus (%d acts)" % _kind_acts.size(), _kind_acts.size() >= ability.count)
	_check("up over his skull each time (%.0f px at best)" % ability.peak_height, ability.peak_height >= 80.0)
	await _expect_face(&"header", &"heading")
	await _await_cond(func() -> bool: return body.dragging or not ability.is_active(), 240)
	_check("and the last one comes home to the hand", ability.headed_home and body.dragging)
	return {"headers": ability.count, "peak": ability.peak_height, "home": body.dragging}

## Wring: held over a grimy skeleton for its whole fuel, it rains; the drops take grime off, paid as
## the sponge pays for it, the first a rinse; he shakes himself dry.
func _drive_wring(body: BaseDraggable, ability: WringAbility) -> Dictionary:
	var over := Vector2(_centre().x, _buddy.get_interaction_rect().position.y - 70.0)
	await _mouse_to(Vector2(_mouse.x, over.y), 700.0)
	await _mouse_to(over, 600.0)
	await _steady(body, 60)
	await _settle_him()
	# Not so much that it all comes off: clean through, he sparkles instead of shaking dry (both are
	# a `shake_off`, and the sparkle is the heavier row).
	_buddy.grime.add(1.0)
	var grime_before := _buddy.grime.value
	var s := ability.sprite()
	var rest := s.scale if s else Vector2.ONE
	_reset_probes()
	_press(MOUSE_BUTTON_RIGHT)
	var hold := int((ability.num("fuel_seconds", 2.0) + 0.2) * 60.0)
	for i in hold:
		var here := Vector2(_centre().x, _buddy.get_interaction_rect().position.y - 70.0)
		_move(here + Vector2(8.0 * sin(float(i) * 0.15), 0.0))
		await _step()
		if i == 40:
			_check("squeezed, it is flatter in the hand", s == null or s.scale.y < rest.y * 0.95)
	_release(MOUSE_BUTTON_RIGHT)
	await _await_cond(func() -> bool: return not ability.is_active(), 180)
	var cleaned := grime_before - _buddy.grime.value
	_check("it rains: %d drops" % ability.drops, ability.drops >= 15)
	_check("and they land on him (%d)" % ability.landed, ability.landed >= 5)
	_check("taking grime off him (%.3f of %.3f)" % [cleaned, grime_before], cleaned >= 0.1
		and is_equal_approx(cleaned, ability.cleaned))
	var paid := _sum(_kind_rates) / ability.kind_value()
	var want := ability.cleaned * ItemDB.balance.hearts_per_grime_cleaned
	_check("paid exactly as the sponge pays for grime (%.2f, the rule says %.2f)" % [paid, want],
		absf(paid - want) <= 0.001 * maxf(want, 1.0))
	_check("and the rinse is one act of its own (%.1f)" % ability.given_extra,
		_kind_acts.size() == 1 and is_equal_approx(ability.given_extra, ability.num("rinse_value", 2.0)))
	_check("the sponge is itself again", s == null or s.scale.is_equal_approx(rest))
	await _expect_face(&"showered", &"showered")
	await _expect_face(&"shake_dry", &"shaking_dry")
	return {"drops": ability.drops, "landed": ability.landed, "cleaned": cleaned}

## Tickle: its feathers on his side, held for its whole fuel: he giggles every tick, an act each.
func _drive_tickle(body: BaseDraggable, ability: TickleAbility) -> Dictionary:
	var rect := _buddy.get_interaction_rect()
	var at := Vector2(rect.position.x + 6.0, rect.get_center().y - 12.0)
	await _mouse_to(Vector2(_mouse.x, rect.position.y - 120.0), 700.0)
	await _mouse_to(Vector2(at.x - 60.0, rect.position.y - 120.0), 700.0)
	await _mouse_to(at, 400.0)
	await _steady(body, 40)
	await _settle_him()
	var s := ability.sprite()
	var rest_rot := s.rotation if s else 0.0
	_reset_probes()
	_press(MOUSE_BUTTON_RIGHT)
	var hold := int((ability.num("fuel_seconds", 2.4) + 0.2) * 60.0)
	for i in hold:
		var r := _buddy.get_interaction_rect()
		_move(Vector2(r.position.x + 6.0, r.get_center().y - 12.0) + Vector2(0.0, 6.0 * sin(float(i) * 0.3)))
		await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _await_cond(func() -> bool: return not ability.is_active(), 60)
	_check("it flutters on him and he giggles (%d)" % ability.giggles, ability.giggles >= 4)
	_check("every giggle one act (%d acts)" % _kind_acts.size(), _kind_acts.size() == ability.giggles)
	_check("worth %.1f each" % ability.num("giggle_value", 0.8),
		is_equal_approx(ability.given_extra, ability.giggles * ability.num("giggle_value", 0.8)))
	_check("the duster is still again", s == null or is_equal_approx(s.rotation, rest_rot))
	await _expect_face(&"tickled", &"tickled")
	return {"giggles": ability.giggles, "peak_rev": ability.peak_rev}

## Swaddle: tossed from 200 px, it wraps round his shoulders and rides him; warm the whole time,
## then it slides off.
func _drive_swaddle(body: BaseDraggable, ability: SwaddleAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-200.0, -60.0), 700.0)
	await _steady(body, 60)
	await _settle_him()
	_reset_probes()
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("a tap throws it", not body.dragging and ability.is_active())
	await _await_cond(func() -> bool: return ability.is_wrapped() or not ability.is_active(), 120)
	_check("round his shoulders", ability.is_wrapped())
	await _step(5)
	var local0 := _buddy.to_local(body.global_position)
	_buddy.apply_central_impulse(Vector2(220.0, -120.0) * _buddy.mass)
	await _step(20)
	var drift := local0.distance_to(_buddy.to_local(body.global_position))
	_check("it rides him (%.1f px drift in his frame)" % drift, ability.is_wrapped() and drift <= 1.5)
	await _expect_face(&"swaddled", &"swaddled")
	await _await_cond(func() -> bool: return not ability.is_wrapped(), 420)
	var seconds := ability.num("wrap_seconds", 5.0)
	_check("it comes off when its time is up (%.2f s on him)" % ability.wrap_time,
		ability.came_off == &"time" and ability.wrap_time >= seconds - 0.1)
	var warm := _sum(_kind_rates) / ability.kind_value()
	var want := ability.num("warm_rate", 3.0) * seconds
	_check("warm the whole time: %.1f, the rate says %.1f" % [warm, want], absf(warm - want) <= want * 0.1)
	_check("and the wrap itself one act (%d)" % _kind_acts.size(), _kind_acts.size() == 1)
	return {"wrapped": ability.wrap_time, "warm": warm, "drift": drift}

## Donut Toss: one tap from 220 px; the donut goes over and into him, one helping from the box.
func _drive_donut_toss(body: BaseDraggable, ability: DonutTossAbility) -> Dictionary:
	var box := body as FriendlyBase
	var eaten := box._eaten
	await _mouse_to(_centre() + Vector2(-220.0, -40.0), 700.0)
	await _steady(body, 60)
	await _settle_him()
	_reset_probes()
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("a tap flips a donut out and it stays in the hand", ability.tossed == 1 and body.dragging)
	await _await_cond(func() -> bool: return not ability.is_active(), 180)
	_check("into his mouth", ability.caught_donuts == 1)
	_check("one helping from the box (%d left)" % ability.helpings(), box._eaten == eaten + 1)
	var helping := box.hearts_per_contact
	var bonus := ability.num("fed_bonus", 1.0)
	_check("paid as the helping the box would have (%.1f) and the hand-fed bonus (%.1f)"
		% [ability.given, ability.given_extra], is_equal_approx(ability.given, helping + bonus)
		and is_equal_approx(ability.given_extra, bonus) and _kind_acts.size() == 1)
	await _expect_face(&"fed", &"eat")
	return {"tossed": ability.tossed, "caught": ability.caught_donuts, "left": ability.helpings()}

## Remote: lit by the first press as ever, put on the clicker by the second; stuck to him it waits
## out its fuse, and a click on it sets it off.
func _drive_remote(body: BaseDraggable, ability: RemoteFuse) -> Dictionary:
	var bomb := body as StickyBomb
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("the first right press lights it, as it always did", bomb.is_primed and ability.uses == 0
		and not ability.is_active())
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("right again puts it on the clicker", ability.holds_fuse() and ability.uses == 1)
	var led := body.get_node_or_null("RemoteLed") as Node2D
	_check("a light on it", led != null and led.visible)
	var uses := ability.uses
	await _stick_on_him(bomb)
	_check("thrown into him, it sticks", bomb.is_stuck())
	# Carried into him it bumped him, which is the bomb's own contact: the fuse is what is watched.
	_hits.clear()
	await _step(int((bomb.throwable_delay + 0.8) * 60.0))
	_check("its fuse runs out and it does not go (%.1f s on the clicker)" % ability.held_for,
		not _gone(bomb) and ability.holds_fuse() and _hits.is_empty())
	_check("and it rides him", ability.rode_him and bomb.is_stuck())
	await _expect_face(&"ticking", &"ticking")
	var base := Progression.damage_mult_for(_id, bomb.damage_mult)
	_move(_grab_point(bomb))
	await _step(2)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	var went: StringName = ability.went if is_instance_valid(ability) else &""
	_release(MOUSE_BUTTON_RIGHT)
	_check("a click on it sets it off, there and then (%s)" % went, went == &"clicked")
	await _step(30)
	_check("and it went off on him (%d hits)" % _hits.size(), _hits.size() >= 1)
	var bad := false
	for info in _hits:
		bad = bad or (not _capped(info) and absf(_mult_of(info) - base) > 0.001 * base)
	_check("every hit at the charge's own multiplier", not bad)
	return {"uses": uses, "blast": _damage_total(), "hits": _hits.size()}

## Airburst: lit, set, carried over his head and let go: it bursts over him and the bomblets land on
## a ring round his feet.
func _drive_airburst(body: BaseDraggable, ability: AirburstFuse) -> Dictionary:
	var bomb := body as ClusterBomb
	var submunitions := bomb.submunitions
	var height := ability.num("height", 60.0)
	var ring := ability.num("ring", 70.0)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("the first right press lights it, as it always did", bomb.is_primed and ability.uses == 0)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("right again sets it to burst", ability.holds_fuse() and ability.uses == 1)
	var uses := ability.uses
	var rect := _buddy.get_interaction_rect()
	var over := Vector2(rect.get_center().x, rect.position.y - 150.0)
	await _mouse_to(Vector2(_mouse.x, over.y), 900.0)
	await _mouse_to(over, 900.0)
	await _steady(bomb, 20)
	_check("held over him, it waits in the hand", not _gone(bomb) and ability.holds_fuse())
	_hits.clear()
	_release(MOUSE_BUTTON_LEFT)
	for i in 120:
		if not is_instance_valid(ability) or ability.went != &"":
			break
		await _step()
	var went: StringName = ability.went if is_instance_valid(ability) else &"gone"
	var burst: Vector2 = ability.burst_over if is_instance_valid(ability) else Vector2.INF
	var points: Array[Vector2] = []
	if is_instance_valid(ability):
		points = ability.points.duplicate()
	_check("let go over him, it bursts overhead (%s)" % went, went == &"over_him")
	_check("well over his skull (%.0f px over his middle)" % (-burst.y if burst != Vector2.INF else 0.0),
		burst != Vector2.INF and -burst.y >= rect.size.y * 0.5 + height)
	rect = _buddy.get_interaction_rect()
	var on_ring := points.size() == submunitions
	for p in points:
		on_ring = on_ring and absf(p.x - rect.get_center().x) <= ring + 4.0 and absf(p.y - rect.end.y) <= 24.0
	_check("its %d bomblets sent to a ring round his feet" % points.size(), on_ring)
	await _step(80)
	var landed := 0
	for info in _hits:
		for p in points:
			if info.position.distance_to(p) <= 1.0:
				landed += 1
				break
	_check("and they land round him (%d of %d reach him)" % [landed, points.size()], landed >= 2)
	return {"uses": uses, "blast": _damage_total(), "hits": _hits.size(),
		"height": -burst.y if burst != Vector2.INF else 0.0}

## Make a Wish: held up beside his face, gathered to full and let go; he blows the candles out, the
## wish is one act, the cake is not eaten, and the candles are lit again after the cooldown.
func _drive_make_a_wish(body: BaseDraggable, ability: MakeAWishAbility) -> Dictionary:
	var rect := _buddy.get_interaction_rect()
	var at := Vector2(rect.position.x - 130.0, rect.position.y + 10.0)
	await _mouse_to(Vector2(_mouse.x, rect.position.y - 80.0), 700.0)
	await _mouse_to(at, 600.0)
	await _steady(body, 60)
	await _settle_him()
	var s := ability.sprite() as Sprite2D
	var lit := s.texture if s else null
	_reset_probes()
	_press(MOUSE_BUTTON_RIGHT)
	var hold := int((ability.num("charge_seconds", 1.2) + 0.2) * 60.0)
	for i in hold:
		_move(_mouse)
		await _step()
	_check("held up to him, the wish gathers (%.2f)" % ability.charge(), ability.charge() >= 0.99)
	var glow := s.get_node_or_null("WishGlow") as Node2D if s else null
	_check("and the flames swell", glow != null and glow.visible)
	_release(MOUSE_BUTTON_RIGHT)
	await _expect_face(&"wish", &"wishing")
	await _await_cond(func() -> bool: return ability.is_blown_out() or not ability.is_active(), 90)
	_check("he blows them out", ability.is_blown_out() and ability.wishes == 1)
	var unlit := s.texture if s else null
	var flame: Vector2 = (ability.row.get("wicks", [Vector2(27, 18)]) as Array)[0]
	var gone := unlit != null and unlit != lit and unlit.get_image().get_pixelv(Vector2i(flame)).a < 0.01 \
		and lit.get_image().get_pixelv(Vector2i(flame)).a > 0.5
	_check("and the flames are gone from the picture", gone)
	_check("the wish is one act of its own (%.1f)" % ability.given_extra,
		_kind_acts.size() == 1 and is_equal_approx(ability.given_extra, ability.num("wish_value", 8.0)))
	_check("and the cake is still his to eat", not _gone(body))
	return {"charge": ability.last_charge, "wishes": ability.wishes}

## And when the cooldown is up, the candles are lit again.
func _after_cooldown_make_a_wish(_body: BaseDraggable, ability: MakeAWishAbility) -> void:
	var s := ability.sprite() as Sprite2D
	_check("the candles relight when the cooldown is up", not ability.is_blown_out() and s != null
		and s.texture == ability._lit_texture and s.texture.get_image().get_pixelv(
		Vector2i((ability.row.get("wicks", [Vector2(27, 18)]) as Array)[0])).a > 0.5)

## Serve: held, it is tossed up; let go at the top of the toss and it goes flat and fast at him, an
## ace; he takes it, it pays his catch and the ace's share, and he volleys it home to the hand.
func _drive_serve(body: BaseDraggable, ability: ServeAbility) -> Dictionary:
	await _mouse_to(_centre() + Vector2(-280.0, -20.0), 700.0)
	await _steady(body, 60)
	await _settle_him()
	_reset_probes()
	var from := body.global_position
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("held, it is tossed up out of the hand", not body.dragging and ability.is_active())
	var top := from.y
	for i in 120:
		top = minf(top, body.global_position.y)
		if ability.timing_now() >= 0.98 or ability._t >= ability._apex_seconds:
			break
		await _step()
	_check("up it goes (%.0f px)" % (from.y - top), from.y - top >= 80.0)
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_check("let go at the top, it is an ace's timing (%.2f) and flat and fast (%.0f px/s)"
		% [ability.timing, ability.serve_speed], ability.timing >= ability.num("ace", 0.8)
		and ability.serve_speed >= ability.num("max_speed", 1150.0) * 0.9)
	await _await_cond(func() -> bool: return ability.returned > 0 or not ability.is_active(), 120)
	_check("he takes it: an ace (%d)" % ability.aces, ability.returned == 1 and ability.aces == 1)
	var catch_value := float(body.get(&"hearts_per_contact"))
	var bonus := ability.num("ace_value", 6.0) * ability.timing
	_check("his catch (%.1f) and the ace's share (%.1f), one act" % [catch_value, ability.given_extra],
		_kind_acts.size() == 1 and is_equal_approx(ability.given, catch_value + bonus)
		and is_equal_approx(ability.given_extra, bonus))
	await _expect_face(&"volley", &"volleying")
	await _await_cond(func() -> bool: return body.dragging or not ability.is_active(), 240)
	_check("and he volleys it home to the hand", ability.caught and body.dragging)
	return {"toss": from.y - top, "timing": ability.timing, "speed": ability.serve_speed,
		"aces": ability.aces}

## D70's rule for anything held down: losing the focus is letting go, never the release that did not
## come. Each D78 ability that runs while right is held is pressed, the window loses the focus, and it
## must have let go — the flutter and the squeeze stopped, the wish fizzled, the toss a fault — and
## the right button must not be left held down inside it.
const D78_HELD: Array[StringName] = [&"feather_duster", &"sponge", &"birthday_cake", &"tennis_ball"]

func _d78_focus_lost() -> void:
	var only := _only()
	var ran := false
	for id in D78_HELD:
		if not only.is_empty() and not only.has(String(id)):
			continue
		if not ran:
			_suite("D78: losing the focus is letting go (D70)")
			ran = true
		_id = id
		_clear_slot()
		SaveManager.load_game()
		await _build_stage()
		_own(id)
		var body := await _spawn_any(id, _centre() + Vector2(-260.0, -150.0))
		if body == null or body.ability == null or not await _grab(body):
			_check("%s is in the hand with its ability" % id, false)
			await _free_stage()
			continue
		var ability := body.ability
		await _mouse_to(_centre() + Vector2(-170.0, -60.0), 700.0)
		await _steady(body, 40)
		_press(MOUSE_BUTTON_RIGHT)
		await _step(20)
		var was_active := ability.is_active()
		body.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _step(3)
		var let_go := not ability.right_held()
		match id:
			&"feather_duster":
				_check("the duster: fluttering, the focus goes and it stops", was_active
					and let_go and not ability.is_active())
			&"sponge":
				var wring := ability as WringAbility
				_check("the sponge: wringing, the focus goes and it stops squeezing", was_active
					and let_go and not wring.is_raining())
			&"birthday_cake":
				var wish := ability as MakeAWishAbility
				_check("the cake: gathering a wish, the focus goes and nothing is wished", was_active
					and let_go and wish.fizzled == 1 and wish.wishes == 0 and not wish.is_blown_out())
			&"tennis_ball":
				var serve := ability as ServeAbility
				_check("the tennis ball: tossed, the focus goes and it is a fault, not a serve",
					was_active and let_go and serve.faults == 1 and serve.serve_speed == 0.0)
		_release(MOUSE_BUTTON_RIGHT)
		await _step(4)
		_check("and the release when it comes back does nothing more", ability.uses == 1)
		_release_all()
		await _free_stage()
