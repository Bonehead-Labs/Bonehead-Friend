extends Node

## Every item in the catalog, one at a time, on a desk of its own, used the way a player
## uses it (docs/decisions.md D59).
##
##   Godot --headless --path <project> res://tests/integration/item_check.tscn
##   ... item_check.tscn -- --only=grenade,baseball_bat     (a subset, while working)
##
## Why this exists. A whole shop tab did nothing for weeks because nothing looked at it; every
## explosion in the game applied zero force for a release because of a node-name lookup; a
## starter power's damage augment was a placebo; the fist erased its own punch. Each of those
## was found by a person, late. Every one of them is a sentence of the form "this item does
## not do what it says", and that sentence can be asked of all hundred items in a few minutes.
##
## How. For every `ItemData` in `ItemDB` — enumerated, never listed, so a merged item is
## covered the day it lands — a fresh stage in a 1280x720 SubViewport (the real `WorldBounds`,
## a real `ItemSpawner`, one buddy, nothing else), a fresh save, the item bought through the
## shop's own path, and then the item used with synthetic input at real positions: a bat is
## grabbed by its grab region and swung through him, a grenade is primed by a right-click
## while held and dropped beside him, a turret is put down and left, a pizza is dropped on his
## head, a hot tub has him carried over and put in it, a held gun is picked up, left to aim
## itself and fired with the right button, and a fidget toy is worked through its own click
## zones — a bubble tapped, a crank circled. Then everything it claims is asserted
## against what was measured: the right currency through the real pipeline, the contract
## event, mastery, the effect, that it stays in the world, that nothing it does goes past the
## speed a wall can hold, that it pushes no errors, that Shift+right-click bins it and that
## nothing of it is left behind.
##
## Twice per item. The second run buys one level of each of its augment keys and ranks it to
## the mastery that lights its aura, then measures whether each key changed the thing it is
## sold as changing. A key nothing reads is a placebo the player paid for.
##
## **Drivers are chosen by exact script class**, never by `is`: a `HeldGun` extending
## `WeaponBase` is a different toy, and driving it as a bat would pass it without exercising
## the one thing that is new about it. A class with no driver is a failure that names it.
##
## Real-time physics, like loop_check. Every wait is a physics frame and every long clock the
## game keeps — a fuse, a turret's interval, a critter's lifetime — is skewed rather than
## waited out, and the authored value is written into the report instead.

const TEST_SLOT := "item_check_slot"
const SETTINGS_PATH := "user://settings_item_check.cfg"
const REPORT_PATH := "user://item_check_report.md"
const VIEW_SIZE := Vector2i(1280, 720)
## Where he stands at the start of every stage: on the floor (the bottom of the view), feet
## down, so he is still within a few frames instead of falling into place.
const HOME := Vector2(640, 657)
## Anything outside this has left the world: the walls are the view's edges, and the ceiling
## sits `WorldBounds.HEADROOM` above the top.
const ARENA := Rect2(-60.0, -470.0, 1400.0, 1250.0)
## 250 px a physics frame. Past it a body crosses the 256 px wall in one step, which is the
## physical definition of "can tunnel out". D54's runaway launch measured 24,729.
const SPEED_CEILING := 15000.0
## A fuse, skewed. The authored length goes into the report.
const FUSE_SKEW := 0.35
## How close a measured multiplier has to be to the one the data promises.
const TOLERANCE := 0.03

const BUDDY := preload("res://Scenes/Buddy/buddy.tscn")

## Exact script class -> driver. A new class is a new row here, on purpose.
const DRIVERS := {
	&"WeaponBase": &"_drive_weapon",
	&"ThrowableBase": &"_drive_explosive",
	&"ClusterBomb": &"_drive_explosive",
	&"BlackHoleCharge": &"_drive_black_hole",
	&"Firework": &"_drive_firework",
	&"StickyBomb": &"_drive_sticky",
	&"ProximityMine": &"_drive_mine",
	&"FriendlyBase": &"_drive_friendly",
	&"Trampoline": &"_drive_trampoline",
	&"WindSource": &"_drive_wind",
	&"TurretBase": &"_drive_turret",
	&"NpcBase": &"_drive_critter",
	&"NpcGorilla": &"_drive_critter",
	&"FistPower": &"_drive_fist",
	&"GunPower": &"_drive_gun",
	&"BeamPower": &"_drive_beam",
	&"LightningPower": &"_drive_strike",
	&"MissilePower": &"_drive_strike",
	&"VortexPower": &"_drive_vortex",
	&"OpenHandPower": &"_drive_pet",
	# D56: all seven held guns, harm and kind. Which of the three things a shot is, and which
	# side it pays on, the driver reads off the gun and the item.
	&"HeldGun": &"_drive_held_gun",
	# D57: one row per toy, each working its own zones through `GestureZones` with the helpers
	# under "drivers: the fidget layer". A new toy class is a row here and a driver built from
	# them; its currency is decided by `_pays_hearts`, not by this table.
	&"BubbleWrap": &"_drive_bubble_wrap",
	&"StressBall": &"_drive_stress_ball",
	&"FidgetSpinner": &"_drive_spinner",
	&"MagicEightBall": &"_drive_fortune_ball",
	&"JackInTheBox": &"_drive_jack",
	# The second five fidget toys (D66).
	&"Slinky": &"_drive_slinky",
	&"NewtonsCradle": &"_drive_cradle",
	&"PullBackCar": &"_drive_car",
	&"YoYo": &"_drive_yoyo",
	&"Slingshot": &"_drive_slingshot",
	# D72: the supernatural powers, harm and kind. Which currency each pays is `HEARTS_CLASSES`.
	&"TelekinesisPower": &"_drive_telekinesis",
	&"TimeStopPower": &"_drive_time_stop",
	&"MeteorShowerPower": &"_drive_meteors",
	&"SmitePower": &"_drive_smite",
	&"BlessingPower": &"_drive_blessing",
	&"LevitationPower": &"_drive_levitation",
	&"RainbowPower": &"_drive_rainbow",
}

## Classes that pay Hearts. Everything else is on the harm side of the pipeline and pays Bones
## — including the bowling ball, the trampoline and the fan, which are sold on the kind side of
## the shop for Bones and earn through damage at the swing floor (Buddy `_min_impulse_for`, D64).
## Read through `_pays_hearts`, which adds every `FidgetToy` and the kind `HeldGun`s.
const HEARTS_CLASSES: Array[StringName] = [&"FriendlyBase", &"OpenHandPower",
	&"Slinky", &"NewtonsCradle", &"PullBackCar",
	&"BlessingPower", &"LevitationPower", &"RainbowPower"]

## Classes that cannot be aimed, so a run where it missed him is the item working as sold
## ("it rewards letting go") rather than a failure. What it earned is reported, not asserted.
const UNAIMED: Array[StringName] = [&"Firework"]

## Findings this suite measures and D59 records but does not fix, because each one is a design
## or balance call rather than a local bug (docs/item-audit-2026-09.md). A known finding is
## reported, not failed — and one that stops reproducing IS a failure, so this table cannot go
## stale: fix the item, delete its line.
const KNOWN := {
	"flamethrower/hits": "~F2 D54's 18 px impact inset leaves the shot under the damage floor",
	"flamethrower/earns": "~F2 D54's 18 px impact inset leaves the shot under the damage floor",
	"flamethrower/mastery": "~F2 D54's 18 px impact inset leaves the shot under the damage floor",
	"flamethrower/aug_damage_mult": "~F2 D54's 18 px impact inset leaves the shot under the damage floor",
	"flamethrower/aug_payout_mult": "~F2 D54's 18 px impact inset leaves the shot under the damage floor",

	# The held guns and the fidget toys (D56, D57), added to the suite after it was written.
	"revolver/thrown": "~F1 a hit that parts in one physics step is never billed (D7's contact impulse)",
	"smg/thrown": "~F1 a hit that parts in one physics step is never billed (D7's contact impulse)",
	"pump_shotgun/thrown": "~F1 a hit that parts in one physics step is never billed (D7's contact impulse)",
	"hunting_rifle/thrown": "~F1 a hit that parts in one physics step is never billed (D7's contact impulse)",
	"blunderbuss/thrown": "~F1 a hit that parts in one physics step is never billed (D7's contact impulse)",
	"magic_eight_ball/aug_cooldown_mult": "F10 a shake is a whole reversal: 4 x 0.94^n still rounds up to 4 until level 5",
}

var _passed := 0
var _failed := 0
var _known := 0

var _view: SubViewport
var _stage: Node2D
var _spawner: ItemSpawner
var _fx: FxSpy
var _buddy: Buddy
var _catch: Catch

## The run being measured, or null between runs. Every probe is a no-op while it is null.
var _run: Run
var _frame := 0
var _mouse := Vector2.ZERO
var _held := 0
## What Economy had just paid, read inside the grant, waiting for the event that caused it.
var _pending := {}
var _rows: Array[Dictionary] = []
## `-- --trace`: every tenth frame, where he and the item are and what has been billed. For
## working out why an item failed, which the assertions alone cannot say.
var _trace := false

# --- the three helpers the suite is built on --------------------------------------------

## Everything pushed to the error log while an item runs. `push_warning` and `push_error` are
## invisible to a headless run unless something is listening, and "a warning nobody read" is
## exactly how every explosion in the game went forceless for a release.
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

## The world's effects node, with a note of everything it was asked to draw. An item's effect
## is the half of its contract that no payout shows: a turret that pays but draws no tracer
## is a gun that looks like the desk hurting him by itself.
class FxSpy extends WorldFX:
	var calls := {}
	var tracers: Array = []
	var booms: Array[Vector2] = []
	var shots: Array[Vector2] = []
	var bursts: Array[StringName] = []
	var auras: Array[String] = []
	var reactions: Array[StringName] = []

	func forget() -> void:
		calls.clear()
		tracers.clear()
		booms.clear()
		shots.clear()
		bursts.clear()
		auras.clear()
		reactions.clear()

	func count(key: String) -> int:
		return int(calls.get(key, 0))

	func _note(key: String) -> void:
		calls[key] = count(key) + 1

	func _on_damage_dealt(info: HitInfo) -> void:
		reactions.append(info.source_id)
		super(info)

	func burst(at: Vector2, glyph: StringName, colour: Color, count_: int, speed: float,
			lifetime: float = 0.7) -> void:
		_note("burst")
		bursts.append(glyph)
		super(at, glyph, colour, count_, speed, lifetime)

	func shot(at: Vector2, spread: bool = false, tier: int = 0) -> void:
		_note("shot")
		shots.append(at)
		super(at, spread, tier)

	func heat(at: Vector2, tier: int = 0) -> void:
		_note("heat")
		super(at, tier)

	func boom(at: Vector2, size: float = 1.0) -> void:
		_note("boom")
		booms.append(at)
		super(at, size)

	func tracer(from: Vector2, to: Vector2, colour: Color = TRACER, time: float = 0.1,
			width: float = 2.0) -> void:
		_note("tracer")
		var him := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Node2D
		tracers.append([from, to, him.global_position if him else to])
		super(from, to, colour, time, width)

	func bolt(points: PackedVector2Array, colour: Color = BOLT, width: float = 3.0,
			forks: int = 0) -> void:
		_note("bolt")
		super(points, colour, width, forks)

	func aura(parent: Node2D, glyph: StringName, colour: Color, amount: int, node_name: String,
			box: Vector2 = Vector2(10, 10), orbit: float = 0.0) -> GPUParticles2D:
		_note("aura")
		auras.append(node_name)
		return super(parent, glyph, colour, amount, node_name, box, orbit)

## One item, one phase, and everything measured while it ran.
class Run:
	var item: ItemData
	var cls: StringName
	var upgraded := false
	var authored := {}
	var aug := {}               ## effect_key -> the node bought for it
	var body: Node = null
	var power: CursorPowerBase = null
	var hits: Array[HitInfo] = []
	var stray_hits := 0
	var stray := {}              ## source id -> hits billed to anything else
	var hit_frames: Array[int] = []
	var bones := 0.0
	var hearts := 0.0
	var acts: Array[float] = []
	var act_gaps: Array[int] = []
	var sustained := 0.0
	var sustained_events := 0
	var pipeline_bad: Array[String] = []
	var damage_bad: Array[String] = []
	var measured_damage := 0
	var contracts := {}
	var fuse_lit := false
	var fuse_out := false
	var use_frame := -1
	var kick := 0.0
	var peak_him := 0.0
	var peak_it := 0.0
	var escaped := ""
	var cooldown := -1.0
	var mass := -1.0
	var touch_seconds := 0.0
	var notes: Array[String] = []
	var failures: Array[String] = []
	var known: Array[String] = []
	var errors: PackedStringArray = []
	var leaks: Array[String] = []
	var seconds := 0.0
	var last_v := Vector2.ZERO
	var xp := 0.0
	var grime_start := 0.0
	var grime_seen := -1.0
	var grime_removed := 0.0
	## Whether the kindness value was checked against the data, and whether it held.
	var value_checked := false
	var value_ok := true
	## A field's strength (D65): the acceleration a free, weightless probe took in its first
	## step inside the vortex's pull or the fan's wind. -1 is unmeasured.
	var field := -1.0
	## The fist's top speed chasing a cursor that jumped, in open air. -1 is unmeasured.
	var speed := -1.0
	## Each kind act's mood lift, against `MoodMath` with the item's `mood_mult` in it.
	var mood_before := 0.0
	var mood_want := 0.0
	var mood_checked := false
	var mood_ok := true
	var mood_bad := ""

	func uses() -> int:
		return int(contracts.get("use:%s" % item.id, 0))

	func contract(key: String) -> int:
		return int(contracts.get(key, 0))

	func label() -> String:
		return "upgraded" if upgraded else "plain"

# --- the run ----------------------------------------------------------------------------

func _ready() -> void:
	# Its own preferences file, on the first line (D51): putting an item on the desk can fire a
	# one-off hint, and a hint saves every setting.
	Settings.config_path = SETTINGS_PATH
	# Normal, not Off: auras, ambient life and a turret's aim are all gated on Focus Mode, and
	# they are part of what is being checked. Sound is muted instead — the headless dummy
	# driver reports finished playbacks as leaks at exit, which would bury a real one.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	AudioManager._set_muted(true)
	SaveManager.slot_name = TEST_SLOT
	_clear_slot()
	SaveManager.load_game()

	_catch = Catch.new()
	OS.add_logger(_catch)
	_connect_probes()

	_view = SubViewport.new()
	_view.name = "Desk"
	_view.size = VIEW_SIZE
	_view.handle_input_locally = true
	_view.physics_object_picking = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	# A SubViewport with no container above it never learns the mouse is inside it, and physics
	# picking — which is how a grab region knows it is hovered — is gated on exactly that.
	_view.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)

	print("")
	print("Bonehead Friend — item check")
	print("============================")

	var only := _only()
	_trace = OS.get_cmdline_user_args().has("--trace")
	var started := Time.get_ticks_msec()
	var checked := 0
	for item in ItemDB.all_items():
		if not only.is_empty() and not only.has(String(item.id)):
			continue
		await _check_item(item)
		checked += 1

	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	_write_report(seconds)
	print("")
	print("============================")
	print("%d items in %.0f s — passed: %d   failed: %d   known: %d" % [checked, seconds,
		_passed, _failed, _known])
	print("report: %s" % ProjectSettings.globalize_path(REPORT_PATH))
	OS.remove_logger(_catch)
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

func _only() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--only="):
			return String(arg).trim_prefix("--only=").split(",", false)
	return PackedStringArray()

func _check_item(item: ItemData) -> void:
	var cls := _class_of(item)
	print("")
	print("  %s  (%s, %s)" % [item.id, cls, _category_name(item.category)])
	var row := {"id": item.id, "class": cls, "category": _category_name(item.category),
		"verdict": "", "plain": null, "upgraded": null, "augments": {}}
	var driver: StringName = DRIVERS.get(cls, &"")
	if driver == &"":
		# Loud, and first: the whole point of enumerating the catalog is that nothing merged
		# can slip past it untested.
		_failed += 1
		print("    FAIL no driver for %s — add one to DRIVERS before this item can ship" % cls)
		row["verdict"] = "FAIL: no driver for %s" % cls
		_rows.append(row)
		return

	var plain := await _phase(item, cls, driver, false)
	var upgraded := await _phase(item, cls, driver, true)
	row["plain"] = plain
	row["upgraded"] = upgraded
	row["augments"] = _judge_augments(plain, upgraded)

	var failures: Array[String] = []
	failures.append_array(plain.failures)
	failures.append_array(upgraded.failures)
	var known: Array[String] = []
	known.append_array(plain.known)
	known.append_array(upgraded.known)
	if not failures.is_empty():
		row["verdict"] = "FAIL: " + "; ".join(failures)
	elif not known.is_empty():
		row["verdict"] = "known: " + ", ".join(known)
	else:
		row["verdict"] = "pass"
	_rows.append(row)

## One item on one fresh desk: a fresh save, a fresh stage, the item bought, driven, judged,
## and cleared away.
func _phase(item: ItemData, cls: StringName, driver: StringName, upgraded: bool) -> Run:
	_fresh_save()
	await _build_stage()
	var run := Run.new()
	run.item = item
	run.cls = cls
	run.upgraded = upgraded
	run.authored = _authored(item)
	if not _own(item.id):
		_expect(run, "buy", false, "it can be bought through the shop (%s)" % Progression.can_purchase(item.id))
	if upgraded:
		_upgrade(run)
	# Seeded per item: a shotgun's spread, a nail bomb's scatter and an animal's stance are all
	# `randf()`, and a suite that passes on some runs and not others says nothing.
	seed(hash(String(item.id)))
	_buddy.health.reset_meter()
	_fx.forget()
	_catch.take()
	_pending = {}
	var baseline := _node_ids()
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var started := Time.get_ticks_msec()
	print("    — %s" % run.label())

	_run = run
	if not upgraded and not item.is_cursor_power():
		await _the_bin_gesture_works(run)
	await Callable(self, driver).call(run)
	_judge(run)
	await _teardown(run, baseline)
	_run = null

	run.errors = _catch.take()
	_expect(run, "errors", run.errors.is_empty(), "nothing was pushed to the error log%s"
		% ("" if run.errors.is_empty() else ": " + " | ".join(run.errors.slice(0, 3))))
	run.seconds = float(Time.get_ticks_msec() - started) / 1000.0
	await _free_stage()
	var orphaned := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphans
	_expect(run, "orphans", orphaned <= 0, "and it left no orphaned nodes behind (%d)" % orphaned)
	return run

# --- the stage --------------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node2D.new()
	_stage.name = "Stage"
	# The game's own walls, not a hand-built floor: `WorldBounds` derives them from the viewport,
	# and this viewport is a real play area rather than the 64x64 a headless root gets.
	var bounds := WorldBounds.new()
	bounds.name = "Bounds"
	_stage.add_child(bounds)
	_spawner = ItemSpawner.new()
	_spawner.name = "ItemSpawner"
	_spawner.world = _stage
	_spawner.add_to_group(&"item_spawner")
	_stage.add_child(_spawner)
	_fx = FxSpy.new()
	_fx.name = "WorldFX"
	_stage.add_child(_fx)
	_buddy = BUDDY.instantiate() as Buddy
	_buddy.position = HOME
	_stage.add_child(_buddy)
	_view.add_child(_stage)
	# After his components, which connected as he entered the tree.
	EventBus.kindness_given.connect(_on_kind_act_late)
	_mouse = Vector2(40, 40)
	_held = 0
	_move(_mouse)
	# On the floor and still before anything is asked of him.
	for i in 90:
		await _step()
		if i > 3 and _buddy.is_grounded() and _buddy.linear_velocity.length() < 2.0:
			break

func _free_stage() -> void:
	if EventBus.kindness_given.is_connected(_on_kind_act_late):
		EventBus.kindness_given.disconnect(_on_kind_act_late)
	if _held != 0:
		_release_all()
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_buddy = null
	_spawner = null
	_fx = null
	await get_tree().process_frame
	await get_tree().physics_frame

func _fresh_save() -> void:
	_clear_slot()
	SaveManager.load_game()

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## Bought the way the shop buys it, requirements first, with exactly the price granted.
func _own(id: StringName) -> bool:
	if Progression.is_unlocked(id):
		return true
	var item := ItemDB.get_item(id)
	if item == null:
		return false
	for req in item.requires:
		_own(req)
	Economy.grant(item.currency_id(), float(item.cost))
	return Progression.purchase_item(id)

## One level of one node per effect key, and enough mastery to light the aura (D53: rank 50
## is the fourth rung) — which also opens every mastery-gated branch.
func _upgrade(run: Run) -> void:
	var id := run.item.id
	var b := ItemDB.balance
	Economy.grant(Economy.BONES, 1.0e12)
	Economy.grant(Economy.HEARTS, 1.0e12)
	Progression.add_mastery_xp(id, EconomyMath.mastery_xp_for_rank(b.mastery_base,
		b.mastery_bonus_rank, b.mastery_exponent))
	for node in ItemDB.augments_for(id):
		if node.is_automation or run.aug.has(node.effect_key):
			continue
		if Progression.purchase_augment(node.id, 1) == 1:
			run.aug[node.effect_key] = node.id
		else:
			run.notes.append("could not buy %s: %s" % [node.id, Progression.augment_lock_reason(node.id)])

## The numbers the item's scene was authored with, read off a fresh instance before anything
## has touched them. The report prints the clocks this suite skews.
func _authored(item: ItemData) -> Dictionary:
	var out := {}
	if item.scene == null:
		return out
	var node := item.scene.instantiate()
	for key in ["damage_mult", "mass", "cooldown_seconds", "fire_interval", "throwable_delay",
			"contact_delay", "attack_period", "windup_seconds", "lifetime_seconds",
			"hearts_per_contact", "hearts_per_second_touching", "hearts_per_second_placed",
			"contact_cooldown", "min_contact_speed", "consume_on_use", "cleans_grime", "handheld",
			"max_range", "muzzle", "swarm_count", "throws_loose_items", "pellets", "auto_fire",
			"value_scale", "pull_seconds", "submunitions", "submunition_interval", "tick_seconds",
			"flight_seconds", "impulse_per_second", "servings"]:
		var value = node.get(key)
		if value != null:
			out[key] = value
	var body = node.get("body")
	if body is RigidBody2D:
		out["mass"] = (body as RigidBody2D).mass
		out["damage_mult"] = body.get("damage_mult")
	node.free()
	return out

func _class_of(item: ItemData) -> StringName:
	if item.scene == null:
		return &"(no scene)"
	var node := item.scene.instantiate()
	var script := node.get_script() as Script
	var cls := script.get_global_name() if script else StringName(node.get_class())
	node.free()
	return cls

func _category_name(category: int) -> String:
	return ["Weapon", "Throwable", "CursorPower", "Friendly", "Toy", "Turret", "Critter",
		"Comfort", "Food", "Ambience", "Gun"][clampi(category, 0, 10)]

# --- probes -----------------------------------------------------------------------------
#
# Connected once, before any stage exists. That puts them after the autoloads (Economy pays
# first) and before every buddy's own MoodComponent and GrimeComponent, so a probe still sees
# the mood and grime the payout was made at (CLAUDE.md, signal handler order).

func _connect_probes() -> void:
	EventBus.payout.connect(_on_payout)
	EventBus.damage_dealt.connect(_on_damage)
	EventBus.kindness_given.connect(_on_kind_act)
	EventBus.kindness_sustained.connect(_on_kind_sustained)
	EventBus.contract_event.connect(_on_contract)
	EventBus.threat_changed.connect(_on_threat)

## Inside Economy's grant. The pipeline is linear in its base, so its value at a base of one
## is the whole product of multipliers it has just applied — read here, before mood, grime,
## mastery or a milestone can move in reaction to the event that caused it.
func _on_payout(currency: StringName, amount: float, _at: Vector2, source_id: StringName) -> void:
	if _run == null or source_id != _run.item.id:
		return
	var b := ItemDB.balance
	var unit := Economy.payout_for(1.0, source_id)
	if currency == Economy.BONES:
		_run.bones += amount
		_pending = {"paid": amount, "unit": unit * b.bones_per_damage * Economy.grime_multiplier(),
			"currency": currency}
	elif currency == Economy.HEARTS:
		_run.hearts += amount
		var combo := 1.0
		if Economy.paying_kind_act:
			combo = EconomyMath.kindness_combo(Economy._combo_count, b.kindness_combo_step,
				b.kindness_combo_max)
		_pending = {"paid": amount, "unit": unit * b.hearts_per_kindness * combo, "currency": currency}

## The payout just granted must be the event's base times the pipeline's product, exactly.
func _settle_pending(base: float, what: String) -> void:
	if _pending.is_empty():
		_run.pipeline_bad.append("%s of %.3f paid nothing" % [what, base])
		return
	var expected := base * float(_pending["unit"])
	var paid := float(_pending["paid"])
	if absf(paid - expected) > 1.0e-6 * maxf(1.0, expected):
		_run.pipeline_bad.append("%s of %.3f paid %.4f, the pipeline says %.4f" % [what, base, paid, expected])
	_pending = {}

func _on_damage(info: HitInfo) -> void:
	if _run == null:
		return
	if info.source_id != _run.item.id:
		_run.stray_hits += 1
		_run.stray[String(info.source_id)] = int(_run.stray.get(String(info.source_id), 0)) + 1
		_pending = {}
		return
	_run.hits.append(info)
	_run.hit_frames.append(_frame)
	_settle_pending(info.amount, "a hit")
	# The multiplier the receiver applied, read back off the hit. Only a hit under the per-hit
	# cap carries it; at the cap every weapon looks the same.
	var b := ItemDB.balance
	var cap := b.knockout_damage * b.max_hit_fraction
	if info.amount >= cap - 0.001 or info.raw_impulse <= 0.0:
		return
	var want := _hit_multiplier(_run, info)
	var got := info.amount / (info.raw_impulse * b.damage_per_impulse)
	_run.measured_damage += 1
	if absf(got - want) > 0.001 * maxf(1.0, want):
		_run.damage_bad.append("x%.3f where the data says x%.3f" % [got, want])

func _on_kind_act(source_id: StringName, value: float, _at: Vector2) -> void:
	if _run == null or source_id != _run.item.id:
		return
	_run.acts.append(value)
	_settle_pending(value, "a kind act")
	# The contact clock the act just started, as the item itself set it.
	if is_instance_valid(_run.body) and _run.body is FriendlyBase:
		_run.act_gaps.append((_run.body as FriendlyBase)._next_contact_msec - Time.get_ticks_msec())
	# The lift his MoodComponent is about to give him, which `_on_kind_act_late` reads back.
	if is_instance_valid(_buddy) and _buddy.mood:
		_run.mood_before = _buddy.mood.value
		_run.mood_want = MoodMath.nudge(_run.mood_before, MoodMath.kindness_mood(value,
			ItemDB.balance.mood_per_kindness) * Progression.get_modifier(source_id, &"mood_mult"))

## Connected per stage, after his MoodComponent, so it sees the mood the act left him at before
## anything has decayed it.
func _on_kind_act_late(source_id: StringName, _value: float, _at: Vector2) -> void:
	if _run == null or source_id != _run.item.id or not is_instance_valid(_buddy) or _buddy.mood == null:
		return
	_run.mood_checked = true
	var got := _buddy.mood.value
	if absf(got - _run.mood_want) > 1.0e-4:
		_run.mood_ok = false
		_run.mood_bad = "%.2f to %.2f where the data says %.2f" % [_run.mood_before, got, _run.mood_want]

func _on_kind_sustained(source_id: StringName, value: float, _at: Vector2) -> void:
	if _run == null or source_id != _run.item.id:
		return
	_run.sustained += value
	_run.sustained_events += 1
	_settle_pending(value, "a trickle")

func _on_contract(key: StringName, count: int) -> void:
	if _run == null:
		return
	_run.contracts[String(key)] = _run.contract(String(key)) + count
	if String(key) == "use:%s" % _run.item.id and _run.use_frame < 0:
		_run.use_frame = _frame

func _on_threat(kind: StringName, _at: Vector2, level: float) -> void:
	if _run == null or kind != &"fuse":
		return
	if level > 0.0:
		_run.fuse_lit = true
	else:
		_run.fuse_out = true

# --- time -------------------------------------------------------------------------------

## One physics frame, measured. Every wait in the suite goes through here, so nothing an item
## does between two assertions goes unwatched.
func _step(frames: int = 1) -> void:
	for i in frames:
		await get_tree().physics_frame
		_frame += 1
		_sample()

func _sample() -> void:
	if _run == null or not is_instance_valid(_buddy):
		return
	if _trace and _frame % 10 == 0:
		var it := ""
		for body in _bodies_of(_run):
			it += " %s@%s v%s" % [body.name, body.global_position.round(), body.linear_velocity.round()]
			if body is NpcBase:
				it += " %s" % (body as NpcBase).state
		print("      f%d him@%s v%s down %s drag %s | hits %d stray %s uses %d acts %d sus %.2f |%s" % [
			_frame, _buddy.global_position.round(), _buddy.linear_velocity.round(), _buddy.health.down,
			_buddy.dragging, _run.hits.size(), _run.stray, _run.uses(), _run.acts.size(),
			_run.sustained, it])
	var v := _buddy.linear_velocity
	var speed := v.length()
	if not is_finite(speed) or not _buddy.global_position.is_finite():
		_run.escaped = "NaN on him"
	elif not ARENA.has_point(_buddy.global_position) and _run.escaped == "":
		_run.escaped = "he left the world at %s" % _buddy.global_position
	_run.peak_him = maxf(_run.peak_him, speed)
	# The kick a blast or a shot gives him, in the few frames after the item's first use.
	if _run.use_frame >= 0 and _frame - _run.use_frame <= 6:
		_run.kick = maxf(_run.kick, (v - _run.last_v).length())
	_run.last_v = v
	for body in _bodies_of(_run):
		var its := body.linear_velocity.length()
		if not is_finite(its) or not body.global_position.is_finite():
			_run.escaped = "NaN on %s" % body.name
		elif not ARENA.has_point(body.global_position) and _run.escaped == "" \
				and body.global_position.distance_to(FistPower.PARKING_POSITION) > 1.0:
			_run.escaped = "%s left the world at %s" % [body.name, body.global_position]
		_run.peak_it = maxf(_run.peak_it, its)
	# Grime taken off, as the sum of the drops between frames. His grime also rises with every
	# hit, so the difference between the start and the end is not what the sponge removed.
	var grime := _buddy.grime.value
	if _run.grime_seen >= 0.0 and grime < _run.grime_seen:
		_run.grime_removed += _run.grime_seen - grime
	_run.grime_seen = grime
	# Contact time, counted the way the item counts it: the same call on the same frame.
	var friendly: FriendlyBase = _run.body if not _gone(_run.body) and _run.body is FriendlyBase else null
	if friendly and friendly._touching_buddy() != null:
		_run.touch_seconds += 1.0 / float(Engine.physics_ticks_per_second)

## Every body of this item in the world: what was spawned, a swarm's extras, a power's fist.
func _bodies_of(run: Run) -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		var body := node as BaseDraggable
		if body and body.item_id == run.item.id and not (body is Buddy) and is_instance_valid(body):
			out.append(body)
	return out

# --- the hand ---------------------------------------------------------------------------

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
	if _held & 1:
		_release(MOUSE_BUTTON_LEFT)
	if _held & 2:
		_release(MOUSE_BUTTON_RIGHT)

func _button(button: MouseButton, pressed: bool, shift: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	e.button_mask = _held
	e.position = _mouse
	e.global_position = _mouse
	_view.push_input(e, true)

## The cursor carried to `target` at `speed` px/s, one physics frame at a time.
func _mouse_to(target: Vector2, speed: float) -> void:
	var stride := speed / float(Engine.physics_ticks_per_second)
	var guard := 0
	while _mouse.distance_to(target) > stride and guard < 400:
		_move(_mouse.move_toward(target, stride))
		await _step()
		guard += 1
	_move(target)
	await _step()

## Where a player takes hold of it: the middle of its grab region, which on an authored
## weapon is the handle rather than the middle of the picture (D25).
func _grab_point(body: BaseDraggable) -> Vector2:
	if body.drag_area:
		for child in body.drag_area.get_children():
			if child is CollisionShape2D:
				return (child as CollisionShape2D).global_position
	return body.global_position

func _grab(run: Run, body: BaseDraggable) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	_move(_grab_point(body))
	# Two frames: picking runs inside the physics step after the motion arrives, so the hover
	# flag is set one frame late — and the press only means "grab" if it is.
	await _step(2)
	if body.drag_area and not body.drag_area.is_hovered:
		_move(_grab_point(body))
		await _step(2)
	_press(MOUSE_BUTTON_LEFT)
	await _step()
	if not body.dragging:
		_expect(run, "grab", false, "its grab region takes a click (hovered %s at %s)"
			% [body.drag_area.is_hovered if body.drag_area else "no area", _mouse])
		_release_all()
		return false
	return true

## Carried at the cursor, then flung: accelerated along a line at `target` and let go short
## of it, so it arrives under its own momentum the way a throw does.
func _throw_at(target: Vector2, speed: float, gap: float = 110.0) -> void:
	await _mouse_to(target + Vector2(-330.0, -30.0), 700.0)
	await _step(8)
	var stride := speed / float(Engine.physics_ticks_per_second)
	var guard := 0
	while _mouse.distance_to(target) > gap and guard < 200:
		_move(_mouse.move_toward(target, stride))
		await _step()
		guard += 1
	_release_all()

func _spawn(run: Run, at: Vector2) -> BaseDraggable:
	EventBus.spawn_requested.emit(run.item.id, at)
	var node: Node = null
	if not _spawner._active.is_empty():
		node = _spawner._active.back()
	var body := node as BaseDraggable
	if body == null or body.item_id != run.item.id:
		_expect(run, "spawn", false, "it spawns onto the desk")
		return null
	run.body = body
	# In the physics space, with its mass on the server, before anything is asked of it.
	await _step(2)
	# Food dropped on his head can be eaten inside those two frames.
	if _gone(body):
		return null
	run.mass = body.mass
	_expect_aura(run, body)
	return body

func _equip(run: Run) -> CursorPowerBase:
	EventBus.spawn_requested.emit(run.item.id, Vector2.ZERO)
	var power := _spawner.get_power(run.item.id)
	_expect(run, "equip", power != null and power.active and _spawner.active_power() == run.item.id,
		"it equips as the cursor")
	run.power = power
	run.body = power
	if power:
		var fist := power.get("body") as RigidBody2D
		if fist:
			run.mass = fist.mass
	await _step(3)
	if power and power.get("body") is BaseDraggable:
		_expect_aura(run, power.get("body"))
	return power

func _holster(run: Run) -> void:
	if run.power == null or not is_instance_valid(run.power) or not run.power.active:
		return
	EventBus.spawn_requested.emit(run.item.id, Vector2.ZERO)
	await _step(2)
	_expect(run, "holster", not run.power.active and _spawner.active_power() == &"",
		"equipping it again puts it away")
	var fist := run.power.get("body") as RigidBody2D
	if fist:
		_expect(run, "parked", fist.freeze and fist.global_position.distance_to(FistPower.PARKING_POSITION) < 1.0,
			"and its body is parked off the desk, frozen")

func _centre() -> Vector2:
	return _buddy.get_interaction_rect().get_center()

func _top() -> float:
	return _buddy.get_interaction_rect().position.y

func _await_still(body, frames: int) -> void:
	for i in frames:
		if _gone(body) or (body as RigidBody2D).linear_velocity.length() < 3.0:
			return
		await _step()

func _await(condition: Callable, frames: int) -> bool:
	for i in frames:
		if condition.call():
			return true
		await _step()
	return condition.call()

## Untyped on purpose: a typed parameter rejects a freed object with an error instead of
## answering the question.
func _gone(body) -> bool:
	return body == null or not is_instance_valid(body) or (body as Node).is_queued_for_deletion()

## Waits for it to be gone. A loop rather than `_await` with a lambda: a lambda that captured
## the body errors the moment the body is freed, which is exactly the moment being waited for.
func _await_gone(body, frames: int) -> bool:
	for i in frames:
		if _gone(body):
			return true
		await _step()
	return _gone(body)

# --- drivers: the harm side ---------------------------------------------------------------

func _drive_weapon(run: Run) -> void:
	if run.item.category == ItemData.CATEGORY_WEAPON:
		await _swing(run)
	else:
		await _ball(run)

## Picked up by the handle and swung through him, back and forth, following him as he goes.
func _swing(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-250.0, -170.0))
	if not await _grab(run, body):
		return
	var side := -1.0
	var want := 1 if run.upgraded else 2
	for i in 6:
		if _gone(body):
			break
		var him := _centre()
		var y := him.y - 45.0 + 30.0 * float(i % 2)
		await _mouse_to(Vector2(him.x + 230.0 * side, y), 900.0)
		await _mouse_to(Vector2(him.x - 230.0 * side, y), 1300.0)
		side = -side
		# Knocked out is as far as a round goes: he takes nothing until he is back up.
		if run.hits.size() >= want or _buddy.health.down:
			break
	_release_all()
	await _step(10)
	_expect(run, "hits", not run.hits.is_empty(), "a swing through him lands (%d hits)" % run.hits.size())
	_expect(run, "effect", _fx.reactions.has(run.item.id), "and the world answers each hit")

## A ball in the Play drawer: dropped on him from height, then thrown at him.
func _ball(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-240.0, -160.0))
	if await _grab(run, body):
		await _mouse_to(Vector2(_centre().x, _top() - 240.0), 800.0)
		# Held still before it is let go. A heavy ball on the drag joint is a pendulum, and one
		# released mid-swing is a throw across the desk rather than a drop on him.
		await _steady(body, 90)
		_release_all()
		await _step(45)
	if not _gone(body) and await _grab(run, body):
		await _throw_at(_centre(), 1300.0)
		await _step(40)
	run.notes.append("drop and throw landed %d hits" % run.hits.size())

## Waits for something held on the drag joint to stop swinging.
func _steady(body, frames: int) -> void:
	for i in frames:
		if _gone(body) or (i > 6 and (body as RigidBody2D).linear_velocity.length() < 25.0):
			return
		_move(_mouse)
		await _step()

## Carried the way a player lifts something: up clear of everything first, across, then down
## to where it is let go — not dragged in a straight line along the desk, which bills whatever
## he is dragged into and leaves a heavy animal short of where it was put, held by friction.
func _carry_to(body: RigidBody2D, target: Vector2) -> void:
	var clear := minf(body.global_position.y, target.y) - 120.0
	await _mouse_to(Vector2(_mouse.x, clear), 600.0)
	await _mouse_to(Vector2(target.x, clear), 600.0)
	await _mouse_to(target, 400.0)
	await _steady(body, 40)

func _prime_and_drop(run: Run, body: ThrowableBase, beside: Vector2) -> bool:
	if not await _grab(run, body):
		return false
	await _mouse_to(beside, 700.0)
	run.notes.append("fuse %.2fs" % body.throwable_delay)
	body.throwable_delay = FUSE_SKEW
	_press(MOUSE_BUTTON_RIGHT)
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_expect(run, "primed", body.is_primed or body.get("_flying") == true,
		"right-click while holding it lights it")
	_release_all()
	return true

func _drive_explosive(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-240.0, -140.0)) as ThrowableBase
	if body == null:
		return
	_expect(run, "fuse_click", body.right_click_is_mine() and not body.click_would_bin(false),
		"plain right-click is its fuse, not the bin")
	if not await _prime_and_drop(run, body, _centre() + Vector2(-55.0, -10.0)):
		return
	var cluster := body as ClusterBomb
	# Read now: the casing frees itself after the last blast.
	var submunitions := cluster.submunitions if cluster else 0
	var tail := int(ceil(float(submunitions) * cluster.submunition_interval * 60.0)) + 30 if cluster else 0
	await _expect_blast(run, body, 120, cluster == null)
	if cluster:
		# Every blast after the casing's, each its own `boom`: that is what the family is.
		await _await_gone(body, tail)
		_expect(run, "submunitions", _fx.count("boom") >= 1 + submunitions,
			"the casing opens into %d more blasts (%d booms)" % [submunitions, _fx.count("boom")])
		_expect(run, "hits", not run.hits.is_empty(), "and they hurt him (%d hits)" % run.hits.size())

## The blast itself: it went off, it reached him, it moved him, and his flinch let go.
func _expect_blast(run: Run, body, frames: int, check_hits: bool = true) -> void:
	await _await(func() -> bool: return _fx.count("boom") > 0 or run.uses() > 0, frames)
	# The frame it went off on, which may be before this was asked: a mine goes off while he
	# is still being lowered onto it.
	var blast_frame := run.use_frame if run.use_frame >= 0 else _frame - 1
	_expect(run, "detonates", _fx.count("boom") > 0, "it goes off (%d booms)" % _fx.count("boom"))
	_expect(run, "use", run.uses() > 0, "and the detonation counts as a use:%s" % run.item.id)
	await _step(8)
	if check_hits:
		# From the blast, not from the charge landing on him on its way down: a thrown or
		# dropped charge is a body, and a body that hits him is billed like one.
		var from_blast := run.hit_frames.filter(func(f: int) -> bool: return f >= blast_frame).size()
		_expect(run, "hits", from_blast > 0, "the blast hurts him (%d hits)" % from_blast)
	if run.use_frame < 0:
		run.use_frame = _frame - 8
	_expect(run, "fuse_out", not run.fuse_lit or run.fuse_out,
		"and the fuse he was watching is let go when it goes (lit %s, out %s)" % [run.fuse_lit, run.fuse_out])
	# What is left of it lingers, hidden, until it frees itself. It must not be a projectile:
	# the blast area masks the item layer, so a casing still in the world is caught in its own
	# blast at zero distance and launched straight up at `max_force / mass`.
	var casing := 0.0
	for i in 60:
		if _gone(body):
			break
		casing = maxf(casing, (body as RigidBody2D).linear_velocity.length())
		await _step()
	_expect(run, "casing", casing < 50.0, "and the spent casing stays where it went off (%.0f px/s)" % casing)

func _drive_black_hole(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-260.0, -140.0)) as BlackHoleCharge
	if body == null:
		return
	if not await _prime_and_drop(run, body, _centre() + Vector2(-190.0, -10.0)):
		return
	run.notes.append("pull %.1fs" % body.pull_seconds)
	var well: WeakRef = weakref(body)
	await _await(func() -> bool: return well.get_ref() == null or well.get_ref()._pull_left > 0.0, 90)
	var start := _centre().distance_to(body.global_position) if not _gone(body) else 0.0
	var nearest := start
	var frames := int(body.pull_seconds * 60.0) + 40 if not _gone(body) else 0
	for i in frames:
		if _gone(body) or run.uses() > 0:
			break
		nearest = minf(nearest, _centre().distance_to(body.global_position))
		await _step()
	_expect(run, "gathers", nearest < start - 25.0,
		"the well drags him in before it goes (%.0f px to %.0f)" % [start, nearest])
	await _expect_blast(run, body, 60)

## The one explosive nobody aims: lit in the hand and let go.
func _drive_firework(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-300.0, -150.0)) as Firework
	if body == null or not await _grab(run, body):
		return
	await _mouse_to(_centre() + Vector2(-260.0, -30.0), 700.0)
	await _mouse_to(_centre() + Vector2(-170.0, -30.0), 600.0)
	_press(MOUSE_BUTTON_RIGHT)
	_release(MOUSE_BUTTON_RIGHT)
	_release_all()
	await _step()
	_expect(run, "lit", body._flying, "right-click while holding it lights the motor")
	var launch := body.global_position
	var furthest := 0.0
	for i in int(body.flight_seconds * 60.0) + 40:
		if _gone(body) or _fx.count("boom") > 0:
			break
		furthest = maxf(furthest, launch.distance_to(body.global_position))
		await _step()
	_expect(run, "flies", furthest > 100.0, "it flies off under its own power (%.0f px)" % furthest)
	await _await(func() -> bool: return _fx.count("boom") > 0, 30)
	_expect(run, "detonates", _fx.count("boom") > 0, "and goes off wherever it got to")
	_expect(run, "use", run.uses() > 0, "which counts as a use:%s" % run.item.id)
	run.notes.append("unaimed: %d hits" % run.hits.size())
	await _await_gone(body, 60)

func _drive_sticky(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-300.0, -120.0)) as StickyBomb
	if body == null or not await _grab(run, body):
		return
	run.notes.append("contact fuse %.2fs" % body.contact_delay)
	body.contact_delay = FUSE_SKEW
	await _throw_at(_centre(), 900.0, 90.0)
	var bomb: WeakRef = weakref(body)
	var stuck := await _await(func() -> bool: return bomb.get_ref() == null or bomb.get_ref()._joint != null, 60)
	_expect(run, "sticks", stuck and not _gone(body) and body._joint != null,
		"thrown at him, it latches on")
	_expect(run, "primed", _gone(body) or body.is_primed, "and landing on him lights it")
	await _expect_blast(run, body, 90)

func _drive_mine(run: Run) -> void:
	# Put down clear of his reach, or it arms with him already inside it and "waits for him"
	# is not a question this can ask.
	var body := await _spawn(run, _centre() + Vector2(_reach_of(run) + 90.0, -60.0)) as ProximityMine
	if body == null:
		return
	_expect(run, "bins_plainly", not body.right_click_is_mine() and body.click_would_bin(false),
		"it has no fuse, so plain right-click bins it")
	var mine: WeakRef = weakref(body)
	var armed := await _await(func() -> bool: return mine.get_ref() == null or mine.get_ref()._armed, 150)
	_expect(run, "arms", armed and not _gone(body), "it arms itself once it has settled")
	await _step(20)
	_expect(run, "waits", not _gone(body) and run.uses() == 0, "and waits for him, going off by itself for nobody")
	# "Place it, then put him on it."
	if not await _grab(run, _buddy):
		return
	await _carry_to(_buddy, body.global_position + Vector2(0.0, -110.0))
	_release_all()
	await _expect_blast(run, body, 120)

## The blast radius a charge's scene was authored with, read off a fresh instance.
func _reach_of(run: Run) -> float:
	var node := run.item.scene.instantiate()
	var reach := 150.0
	var area = node.get("explosion_area")
	if area is Area2D:
		for child in (area as Area2D).get_children():
			var cs := child as CollisionShape2D
			if cs and cs.shape is CircleShape2D:
				reach = (cs.shape as CircleShape2D).radius * absf(cs.scale.x)
	node.free()
	return reach

func _drive_turret(run: Run) -> void:
	var reach := float(run.authored.get("max_range", 300.0))
	var body := await _spawn(run, _centre() + Vector2(-minf(reach * 0.6, 220.0), -40.0)) as TurretBase
	if body == null:
		return
	await _await_still(body, 60)
	var interval := float(run.authored.get("fire_interval", 1.0))
	run.notes.append("interval %.2fs, range %.0f" % [interval, reach])
	# Its own clock, wound on rather than waited out: it fires on its next tick.
	body._since_shot = body._interval()
	await _await(func() -> bool: return run.uses() > 0, 20)
	_expect(run, "fires", run.uses() > 0, "put down in range, it fires at him")
	# The gap to the next shot, measured: the clock wound to half a second short of the
	# authored interval (or left at the zero the shot put it at), then counted. A fire-rate
	# augment that is read arrives as fewer frames.
	# On a settled target: a mortar shell throws him out of its range for a third of a second,
	# and a gap timed through that is the flight, not the clock.
	await _await(func() -> bool: return _buddy.linear_velocity.length() < 20.0, 180)
	# And moved back beside him if the first shot threw him out of its reach, as a player would.
	if body.global_position.distance_to(_buddy.global_position) > reach * 0.8:
		body.global_position = Vector2(clampf(_centre().x - minf(reach * 0.6, 220.0), 60.0, 1220.0),
			body.global_position.y)
		body.linear_velocity = Vector2.ZERO
		await _step(2)
	var before := run.uses()
	body._since_shot = maxf(0.0, interval - 0.5)
	var frames := 0
	var limit := int(interval * 6.0) + 30
	while run.uses() == before and frames < limit:
		await _step()
		frames += 1
	# No shot inside the window is no measurement, not a gap of `limit` frames.
	run.cooldown = float(frames) if frames < limit else -1.0
	if not run.upgraded and run.hits.is_empty():
		body._since_shot = body._interval()
		await _step(8)
	await _step(4)
	var from_muzzle := false
	var at_him := false
	for line in _fx.tracers:
		var from: Vector2 = line[0]
		var to: Vector2 = line[1]
		if body.muzzle == Vector2.ZERO or from.distance_to(body.global_position) > 3.0:
			from_muzzle = true
		if to.distance_to(line[2]) < 90.0:
			at_him = true
	_expect(run, "tracer", from_muzzle, "the shot leaves from the muzzle (%d tracers)" % _fx.tracers.size())
	_expect(run, "aimed", at_him, "and lands on him")
	_expect(run, "hits", not run.hits.is_empty(), "and it hurts him (%d hits)" % run.hits.size())

func _drive_critter(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-280.0, -40.0)) as NpcBase
	if body == null:
		return
	run.notes.append("lifetime %.0fs" % body.lifetime_seconds)
	var reach := float(run.authored.get("attack_range", 96.0))
	# Put down across the desk from him, it comes for him: asked as distance closed, so a slow
	# animal passes and a stuck one does not.
	var start := absf(body.global_position.x - _centre().x)
	var frames := 0
	while frames < 150 and not _gone(body) and run.hits.is_empty() 			and absf(body.global_position.x - _centre().x) > reach:
		await _step()
		frames += 1
	var closed := start - absf(body.global_position.x - _centre().x) if not _gone(body) else 0.0
	_expect(run, "walks", not run.hits.is_empty() or closed > 100.0,
		"put down across the desk, it comes for him (%.0f px closed in %.1fs)" % [closed, frames / 60.0])
	# Then the attack on its own, whatever the walk did: set down beside him, shoulder to
	# shoulder, as close as its reach (measured centre to centre) allows. Set down rather than
	# carried: a 26 kg animal on the drag joint is a pendulum, and it knocks him over on the way.
	if run.hits.is_empty() and not _gone(body) and absf(body.global_position.x - _centre().x) > reach:
		var side := minf(reach - 4.0, _buddy.get_interaction_rect().size.x * 0.5
			+ body.get_interaction_rect().size.x * 0.5 + 4.0)
		body.global_position = Vector2(_centre().x - side, body.global_position.y)
		body.linear_velocity = Vector2.ZERO
		run.notes.append("set down beside him to test the attack")
	var recover_began := 0
	frames = 0
	# A blow lands; the pause after it is its own clock, timed.
	while frames < 300 and not _gone(body):
		await _step()
		frames += 1
		if body.state == NpcBase.STATE_RECOVER and recover_began == 0 and not run.hits.is_empty():
			recover_began = Time.get_ticks_msec()
		elif recover_began > 0 and body.state != NpcBase.STATE_RECOVER:
			run.cooldown = float(Time.get_ticks_msec() - recover_began)
			break
	_expect(run, "hits", not run.hits.is_empty(), "within reach, it winds up and hits him (%d hits)"
		% run.hits.size())
	_expect(run, "use", run.uses() > 0, "a blow that lands counts as a use:%s" % run.item.id)
	var swarm := 0
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		if node is NpcBase and (node as NpcBase).item_id == run.item.id:
			swarm += 1
	var want := int(run.authored.get("swarm_count", 1))
	_expect(run, "swarm", swarm == want, "all %d of it arrive (%d)" % [want, swarm])
	if bool(run.authored.get("throws_loose_items", false)) and not run.upgraded:
		await _hurls_what_you_left(run, body)
	if run.upgraded or _gone(body):
		return
	# Its time is up — skewed, not waited out — and it leaves.
	body._age = body.lifetime_seconds
	await _step(15)
	_expect(run, "leaves", _gone(body) or body._leaving, "when its time is up it heads for the edge")
	if not _gone(body):
		body._leaving_for = NpcBase.LEAVE_TIMEOUT
		await _await_gone(body, 30)
	_expect(run, "left", _gone(body), "and is gone, the whole summon with it")

## "Arms itself with whatever you left on the desk": a bat beside it, and the bat is what hits.
func _hurls_what_you_left(run: Run, body: NpcBase) -> void:
	# Its first blow will have sent him across the desk, and it cannot walk after him (see the
	# walk check), so it is set down within its reach of him again first.
	await _await(func() -> bool: return _buddy.linear_velocity.length() < 20.0, 120)
	var reach := float(run.authored.get("attack_range", 96.0))
	body.global_position = Vector2(clampf(_centre().x - reach * 0.7, 80.0, 1200.0), body.global_position.y)
	body.linear_velocity = Vector2.ZERO
	_own(&"baseball_bat")
	EventBus.spawn_requested.emit(&"baseball_bat", body.global_position + Vector2(40.0, -30.0))
	var thrown := [0]
	var watch := func(info: HitInfo) -> void:
		if info.source_id == &"baseball_bat":
			thrown[0] += 1
	EventBus.damage_dealt.connect(watch)
	var critter: WeakRef = weakref(body)
	var bat: RigidBody2D = _spawner._active.back()
	var fastest := [0.0]
	await _await(func() -> bool:
		if is_instance_valid(bat):
			fastest[0] = maxf(fastest[0], bat.linear_velocity.length())
		return thrown[0] > 0 or critter.get_ref() == null, 300)
	EventBus.damage_dealt.disconnect(watch)
	run.notes.append("the bat left at up to %.0f px/s" % fastest[0])
	_expect(run, "hurls", thrown[0] > 0, "left a bat, it throws the bat at him (%d hits, the bat flew at %.0f px/s)"
		% [thrown[0], fastest[0]])

func _drive_fist(run: Run) -> void:
	_move(_centre() + Vector2(-260.0, -80.0))
	await _step(2)
	var power := await _equip(run) as FistPower
	if power == null:
		return
	var fist := power.body
	_expect(run, "shows", fist.visible and not fist.freeze, "the fist appears at the cursor")
	await _mouse_to(_centre() + Vector2(240.0, -60.0), 1100.0)
	await _mouse_to(_centre() + Vector2(-240.0, -40.0), 1100.0)
	_move(_centre() + Vector2(-70.0, -20.0))
	await _step(8)
	var pressed_at := Time.get_ticks_msec()
	# The shove the click hands the fist, read off the server either side of the press: the punch
	# is applied inside the click, before any step can add to it.
	var before: Vector2 = PhysicsServer2D.body_get_state(fist.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	_press(MOUSE_BUTTON_LEFT)
	var after: Vector2 = PhysicsServer2D.body_get_state(fist.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var shove := (after - before).length() * fist.mass
	# D64: the damage node is read once, on him, as every weapon's is. Scaling the shove by it as
	# well made one level of it x1.32 on a punch.
	_expect(run, "punch", absf(shove - power.punch_impulse) <= power.punch_impulse * 0.01,
		"the punch is the same shove at every level (%.0f, authored %.0f)" % [shove, power.punch_impulse])
	run.cooldown = float(power._cooldown_until_msec - pressed_at)
	_release(MOUSE_BUTTON_LEFT)
	await _step(20)
	_expect(run, "hits", not run.hits.is_empty(), "run through him and punched, it hits him (%d hits)" % run.hits.size())
	_expect(run, "use", run.uses() > 0, "and each landed hit is a use:%s" % run.item.id)
	# "Faster Hands" is its chase (D65). Measured after the punch, so the approach above is the
	# one F1 was measured on: the cursor parked in the top-left corner, clear of him, then
	# jumped 280 px straight down, and the fist's top speed on the way is the number.
	_move(Vector2(100.0, 120.0))
	await _step(40)
	_move(Vector2(100.0, 400.0))
	run.speed = 0.0
	for i in 24:
		await _step()
		run.speed = maxf(run.speed, fist.linear_velocity.length())
	await _holster(run)

func _drive_gun(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as GunPower
	if power == null:
		return
	var v0 := _buddy.linear_velocity
	var pressed_at := Time.get_ticks_msec()
	_press(MOUSE_BUTTON_LEFT)
	run.cooldown = float(power._cooldown_until_msec - pressed_at)
	if power.auto_fire:
		for i in 40:
			_move(_centre())
			await _step()
	_release(MOUSE_BUTTON_LEFT)
	await _step(6)
	var kick := (_buddy.linear_velocity - v0).length()
	var shots := run.uses()
	_expect(run, "fires", shots > 0, "a click on him fires (%d shots)" % shots)
	if power.auto_fire:
		_expect(run, "stream", shots >= 5, "holding the trigger keeps it firing (%d shots)" % shots)
	_expect(run, "pellets", _fx.count("shot") == shots * maxi(1, power.pellets),
		"%d pellet(s) a shot land as %d sparks for %d shots" % [power.pellets, _fx.count("shot"), shots])
	_expect(run, "hits", not run.hits.is_empty(), "and it hurts him (%d hits)" % run.hits.size())
	_expect(run, "shoves", maxf(kick, run.kick) > 20.0, "and shoves him (%.0f px/s)" % maxf(kick, run.kick))
	# Shift suspends the power (D47): the same click with Shift held is his, not the gun's.
	await _step(int(ceil(float(run.authored.get("cooldown_seconds", 0.0)) * 60.0)) + 2)
	var before := run.uses()
	_move(_centre())
	await _step()
	_press(MOUSE_BUTTON_LEFT, true)
	_release(MOUSE_BUTTON_LEFT, true)
	await _step(3)
	_expect(run, "shift", run.uses() == before, "and Shift held, the click is not a shot")
	await _holster(run)

func _drive_beam(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as BeamPower
	if power == null:
		return
	await _step(20)
	var fastest := 0.0
	var pressed_at := Time.get_ticks_msec()
	_press(MOUSE_BUTTON_LEFT)
	run.cooldown = float(power._next_tick_msec - pressed_at)
	for i in (40 if run.upgraded else 70):
		_move(_centre() + Vector2(sin(i * 0.3) * 6.0, 0.0))
		await _step()
		fastest = maxf(fastest, _buddy.linear_velocity.length())
	_release(MOUSE_BUTTON_LEFT)
	await _step(4)
	_expect(run, "ticks", run.uses() >= 3, "held on him, it keeps burning (%d ticks)" % run.uses())
	_expect(run, "hits", run.hits.size() >= 3, "and each tick hurts him (%d hits)" % run.hits.size())
	_expect(run, "still", fastest < 30.0, "without ever shoving him (fastest %.1f px/s)" % fastest)
	_expect(run, "effect", _fx.count("heat") > 0 and _fx.count("tracer") > 0, "a beam and heat where it lands")
	var ticks := run.uses()
	await _step(20)
	_expect(run, "stops", run.uses() == ticks, "and it stops when the button is let go")
	await _holster(run)

func _drive_strike(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run)
	if power == null:
		return
	var at := _centre()
	var pressed_at := Time.get_ticks_msec()
	_press(MOUSE_BUTTON_LEFT)
	run.cooldown = float(power._cooldown_until_msec - pressed_at)
	_release(MOUSE_BUTTON_LEFT)
	await _await(func() -> bool: return not run.hits.is_empty(), 100)
	await _step(4)
	_expect(run, "use", run.uses() > 0, "a click on him calls it in (a use:%s)" % run.item.id)
	_expect(run, "hits", not run.hits.is_empty(), "and it hurts him (%d hits)" % run.hits.size())
	if power is LightningPower:
		_expect(run, "effect", _fx.count("bolt") > 0, "a bolt comes down")
	else:
		var landed := not _fx.booms.is_empty() and _fx.booms[0].distance_to(at) < 16.0
		_expect(run, "effect", landed, "the missile flies in and goes off on the spot marked (%s vs %s)"
			% [_fx.booms[0] if not _fx.booms.is_empty() else "no blast", at])
		await _step(40)
	await _holster(run)

func _drive_vortex(run: Run) -> void:
	var eye := _centre() + Vector2(170.0, -100.0)
	_move(eye)
	await _step(2)
	var power := await _equip(run) as VortexPower
	if power == null:
		return
	# A 0.3 kg thing on the far side of the eye, touching nothing: the pull is an acceleration
	# now (D65), so it must gather a light prop as calmly as it gathers him — and its first
	# step, taken at rest, is the pull itself with no friction or drag in it.
	var probe := _probe(eye + Vector2(150.0, -40.0), 0)
	var probe_start := probe.global_position.distance_to(eye)
	var probe_nearest := probe_start
	var probe_peak := 0.0
	var start := _centre().distance_to(eye)
	var nearest := start
	_press(MOUSE_BUTTON_LEFT)
	for i in 90:
		_move(eye)
		await _step()
		nearest = minf(nearest, _centre().distance_to(eye))
		var v := probe.linear_velocity.length()
		if run.field < 0.0 and v > 0.0:
			run.field = v * float(Engine.physics_ticks_per_second)
		probe_peak = maxf(probe_peak, v)
		probe_nearest = minf(probe_nearest, probe.global_position.distance_to(eye))
	probe.queue_free()
	_expect(run, "pulls", nearest < start - 40.0, "held, it drags him toward the eye (%.0f px to %.0f)" % [start, nearest])
	_expect(run, "light", probe_nearest < probe_start - 40.0 and probe_peak < 1500.0,
		"and a 0.3 kg prop with him, never faster than 25 px a frame (%.0f px to %.0f, peak %.0f px/s)"
		% [probe_start, probe_nearest, probe_peak])
	_expect(run, "effect", _fx.auras.has("Swirl"), "with a swirl at the eye")
	# Then taken up the desk in it and slammed back down into it, the way a player uses it.
	# The impact is the vortex's doing, so it is billed to the vortex and not to the world —
	# and it is a slam rather than a drop because the pull keeps him pressed to the desk, so
	# the contact outlives the step it was made in (F1 bills nothing that parts in one).
	await _mouse_to(Vector2(eye.x, 720.0 - 400.0), 400.0)
	for i in 20:
		_move(_mouse)
		await _step()
	await _mouse_to(Vector2(eye.x, 700.0), 1500.0)
	await _await(func() -> bool: return not run.hits.is_empty(), 60)
	_release(MOUSE_BUTTON_LEFT)
	await _step(10)
	_expect(run, "claims", not run.hits.is_empty() and not run.stray.has("world"),
		"slammed into the desk with it, the impact is billed to it (%d hits, %s to anything else)"
		% [run.hits.size(), run.stray])
	await _holster(run)

## The trampoline: he is carried up over it and dropped.
func _drive_trampoline(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(240.0, -40.0))
	if body == null:
		return
	await _await_still(body, 60)
	if not await _grab(run, _buddy):
		return
	await _carry_to(_buddy, Vector2(body.global_position.x, 720.0 - 380.0))
	_release_all()
	var arrival := 0.0
	var launch := 0.0
	var landed := false
	for i in 120:
		await _step()
		var vy := _buddy.linear_velocity.y
		if not landed:
			arrival = maxf(arrival, vy)
			landed = arrival > 200.0 and vy < 0.0
		launch = maxf(launch, -vy) if landed else launch
		if run.contract("bounce") > 0 and landed and i > 60:
			break
	_expect(run, "bounce", run.contract("bounce") > 0, "landing on it is a bounce")
	_expect(run, "launch", launch > arrival, "and he leaves faster than he arrived (%.0f in, %.0f out)" % [arrival, launch])

## The fan: he is dropped through its wind, and the wind bends his fall.
func _drive_wind(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-200.0, -40.0)) as WindSource
	if body == null:
		return
	await _await_still(body, 60)
	var blow := body.blow_direction.normalized().rotated(body.rotation)
	# The wind's strength, off a weightless probe held in it between the grille and him (D65):
	# its first step is the push and nothing else. On the item layer, which is what the wind
	# sees, and gone before he is anywhere near it.
	var probe := _probe(body.global_position + blow * 110.0 + Vector2(0.0, -20.0), 4)
	for i in 8:
		await _step()
		var v := probe.linear_velocity.length()
		if v > 0.0:
			run.field = v * float(Engine.physics_ticks_per_second)
			break
	probe.queue_free()
	if not await _grab(run, _buddy):
		return
	await _carry_to(_buddy, Vector2(body.global_position.x + 150.0, 720.0 - 420.0))
	_release_all()
	var at_release := _buddy.linear_velocity.dot(blow)
	var drift := 0.0
	var claimed := &""
	for i in 90:
		await _step()
		drift = maxf(drift, _buddy.linear_velocity.dot(blow) - at_release)
		if i > 10 and _buddy.is_grounded():
			claimed = _buddy.impacts_claimed_by()
			break
	_expect(run, "blows", drift > 10.0, "dropped through its wind, he is blown off his line (%.1f px/s)" % drift)
	# Asked of him rather than read off a hit: this landing bounces apart inside one step, and
	# F1 bills nothing that does, to the fan or to the world (D65).
	_expect(run, "claims", claimed == run.item.id and not run.stray.has("world"),
		"and the landing it bent is its to be billed for, not the world's (claimed by %s)"
		% (claimed if claimed != &"" else "nobody"))
	await _step(10)

## A weightless body at `at` on `layer`, colliding with nothing and undamped, in the group
## every field looks for. What a field does to it in its first step is the field's own
## strength: no gravity, no friction, no contact and no drag of its own in the number.
func _probe(at: Vector2, layer: int) -> RigidBody2D:
	var probe := RigidBody2D.new()
	probe.name = "Probe"
	probe.gravity_scale = 0.0
	probe.collision_layer = layer
	probe.collision_mask = 0
	probe.mass = 0.3
	probe.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	probe.linear_damp = 0.0
	probe.can_sleep = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	probe.add_child(shape)
	probe.position = at
	probe.add_to_group(BaseDraggable.GROUP_INTERACTIVE)
	_stage.add_child(probe)
	return probe

# --- drivers: the kind side ---------------------------------------------------------------

func _drive_pet(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as OpenHandPower
	if power == null:
		return
	var mood := _buddy.mood.value
	var pressed_at := Time.get_ticks_msec()
	_press(MOUSE_BUTTON_LEFT)
	run.cooldown = float(power._next_pet_msec - pressed_at)
	for i in (40 if run.upgraded else 70):
		_move(_centre() + Vector2(sin(i * 0.4) * 14.0, cos(i * 0.4) * 6.0))
		await _step()
	_release(MOUSE_BUTTON_LEFT)
	await _step(2)
	_expect(run, "pets", run.acts.size() >= 3, "held on him and stroked, it pets him (%d pets)" % run.acts.size())
	_expect(run, "contract", run.contract("pet") == run.acts.size(), "each one a pet for the board (%d)" % run.contract("pet"))
	_expect(run, "mood", _buddy.mood.value > mood, "and he cheers up (%.1f to %.1f)" % [mood, _buddy.mood.value])
	var b := ItemDB.balance
	var value := b.pet_value * power.value_scale * Progression.damage_mult_for(run.item.id, power.damage_mult)
	var ok := run.acts.all(func(v: float) -> bool: return is_equal_approx(v, value))
	run.value_checked = true
	run.value_ok = ok
	_expect(run, "value", ok, "each stroke is worth exactly %.3f" % value)
	# Pressed off him, it declines and the click is the desk's.
	var pets := run.acts.size()
	_move(_centre() + Vector2(320.0, -40.0))
	await _step(2)
	_press(MOUSE_BUTTON_LEFT)
	await _step(10)
	_release(MOUSE_BUTTON_LEFT)
	_expect(run, "declines", run.acts.size() == pets, "and pressed anywhere else, it does nothing")
	await _holster(run)

# --- drivers: the supernatural powers (D72) ----------------------------------------------
#
# Seven classes, one driver each, every one worked with the real buttons at real positions. The
# gaps their `cooldown_mult` shortens are each power's own clock, read straight after the click
# that set it, so `_cooldown_verdict` compares like with like.

func _click() -> void:
	_press(MOUSE_BUTTON_LEFT)
	_release(MOUSE_BUTTON_LEFT)

## Seized from across the desk, carried to the hand, squeezed, then flung into the right-hand
## wall. The squeeze is a hit; the wall is the hand's doing and billed to it, not to the world.
func _drive_telekinesis(run: Run) -> void:
	var start := _centre()
	var grab := start + Vector2(-300.0, -230.0)
	_move(grab)
	await _step(2)
	var power := await _equip(run) as TelekinesisPower
	if power == null:
		return
	_press(MOUSE_BUTTON_LEFT)
	await _step(2)
	_expect(run, "seizes", power.is_gripping(),
		"pressed on empty space %.0f px from him, it takes hold of him" % start.distance_to(grab))
	var rose := 0.0
	for i in 70:
		_move(grab)
		await _step()
		rose = maxf(rose, start.y - _centre().y)
	var gap := _centre().distance_to(grab)
	_expect(run, "carries", rose > 120.0 and gap < 90.0,
		"and carries him up to the hand (%.0f px up, %.0f px from it)" % [rose, gap])
	var before := run.hits.size()
	var pressed_at := Time.get_ticks_msec()
	_press(MOUSE_BUTTON_RIGHT)
	run.cooldown = float(power._crush_until_msec - pressed_at)
	_release(MOUSE_BUTTON_RIGHT)
	await _step(4)
	_expect(run, "crush", run.hits.size() > before,
		"right-click while holding him crushes him (%d hits)" % (run.hits.size() - before))
	# The fling: swept hard at the right wall and let go on the way there.
	var flung := run.hits.size()
	var stride := 2600.0 / float(Engine.physics_ticks_per_second)
	while _mouse.x < 1000.0:
		_move(_mouse + Vector2(stride, 0.0))
		await _step()
	var fastest := _buddy.linear_velocity.length()
	_release(MOUSE_BUTTON_LEFT)
	await _step(2)
	_expect(run, "lets_go", not power.is_gripping(),
		"let go, the hand lets go of him (at %.0f px/s)" % fastest)
	await _await(func() -> bool: return run.hits.size() > flung, 90)
	await _step(30)
	_expect(run, "fling", run.hits.size() > flung and not run.stray.has("world"),
		"flung into the wall, the impact is the hand's to be billed for (%d hits, %s to anything else)"
		% [run.hits.size() - flung, run.stray])
	await _holster(run)
	_expect(run, "rests", not power.is_physics_processing(),
		"and holstered, nothing of it runs")

## Stopped where he stands; four blows banked on his left that do not land; a click off him and
## all four land at once and throw him right.
func _drive_time_stop(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as TimeStopPower
	if power == null:
		return
	# Up off the desk first: stopping him mid-air is the thing only this power does.
	_buddy.apply_central_impulse(Vector2(0.0, -900.0) * _buddy.mass)
	await _step(10)
	_move(_centre())
	await _step(2)
	_click()
	await _step(2)
	var held := _buddy.global_position
	_expect(run, "stops", power.is_stopped() and _buddy.freeze,
		"a click on him stops time around him, mid-air (%.0f px up)" % (HOME.y - held.y))
	var blows := 0
	for dy in [-30.0, -10.0, 10.0, 30.0]:
		_move(_centre() + Vector2(-30.0, dy))
		await _step(int(ceil(power.blow_gap * 60.0)) + 1)
		_click()
		blows += 1
	await _step(10)
	_expect(run, "banks", power.banked() == blows and run.hits.is_empty()
			and _buddy.global_position.distance_to(held) < 0.5,
		"%d clicks on him bank %d blows and none of them lands; he has not moved (%.2f px)"
		% [blows, power.banked(), _buddy.global_position.distance_to(held)])
	var x0 := _buddy.global_position.x
	_move(_centre() + Vector2(320.0, -120.0))
	await _step(2)
	var released_at := Time.get_ticks_msec()
	_click()
	run.cooldown = float(power.recharge_until_msec() - released_at)
	await _step(3)
	_expect(run, "resumes", not power.is_stopped() and not _buddy.freeze,
		"a click off him lets time go")
	await _step(12)
	_expect(run, "lands", run.hits.size() >= blows,
		"and every banked blow lands at once (%d hits)" % run.hits.size())
	_expect(run, "throws", _buddy.global_position.x - x0 > 20.0,
		"struck on his left, he is thrown right (%.0f px)" % (_buddy.global_position.x - x0))
	# Straight back on him: still recharging, so the click does nothing to him.
	await _step(20)
	_move(_centre())
	await _step(2)
	_click()
	await _step(2)
	_expect(run, "recharges", not power.is_stopped(),
		"and it cannot stop time again until it has recharged (%.0f ms)" % run.cooldown)
	await _step(40)
	await _holster(run)
	_expect(run, "rests", not power.is_processing() and _buddy.modulate == Color.WHITE,
		"and holstered, nothing of it runs and he is his own colour")

## Held on him for a second and a half: meteors come down on him and go off. Let go, and the
## ones in the air land and no more are called.
func _drive_meteors(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as MeteorShowerPower
	if power == null:
		return
	var pressed_at := Time.get_ticks_msec()
	_press(MOUSE_BUTTON_LEFT)
	run.cooldown = float(power.next_msec() - pressed_at)
	for i in (60 if run.upgraded else 90):
		_move(_centre())
		await _step()
	_release(MOUSE_BUTTON_LEFT)
	var at_release := run.uses()
	await _await(func() -> bool: return not power.is_live(), 120)
	var landed := run.uses()
	_expect(run, "rains", landed >= 3, "held, it brings meteors down on the cursor (%d landed)" % landed)
	_expect(run, "hits", not run.hits.is_empty(), "and they hurt him (%d hits)" % run.hits.size())
	_expect(run, "effect", _fx.count("boom") == landed, "each one goes off where it lands (%d booms)"
		% _fx.count("boom"))
	_expect(run, "stops", landed - at_release <= power.pool_size and not power.is_physics_processing(),
		"and let go, only the %d already falling land, and then nothing runs" % (landed - at_release))
	await _holster(run)

## Called down on him: the light gathers without hurting him, then the pillar strikes, drives him
## into the desk, and the desk's blow is the pillar's.
func _drive_smite(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as SmitePower
	if power == null:
		return
	var pressed_at := Time.get_ticks_msec()
	var pressed_frame := _frame
	_click()
	run.cooldown = float(power.ready_msec() - pressed_at)
	await _step(4)
	_expect(run, "charges", power.is_live() and run.hits.is_empty(),
		"a click calls it down: the light gathers first, and nothing has hit him yet")
	await _await(func() -> bool: return not run.hits.is_empty(), 90)
	var delay := (_frame - pressed_frame) / float(Engine.physics_ticks_per_second)
	_expect(run, "strikes", not run.hits.is_empty() and delay >= power.charge_seconds * 0.9,
		"then the pillar strikes (%d hits, %.2f s after the click)" % [run.hits.size(), delay])
	_expect(run, "effect", _fx.bursts.has(&"star"), "in a burst of light at its foot")
	await _step(40)
	_expect(run, "claims", not run.stray.has("world"),
		"driven into the desk, the desk's blow is billed to it (%s to anything else)" % run.stray)
	await _await(func() -> bool: return not power.is_live(), 60)
	await _holster(run)
	_expect(run, "rests", not power.is_processing(), "and holstered, nothing of it runs")

## Clicked on him: one kind act, then a halo that trickles for as long as it stays. Clicked off
## him, nothing; clicked again inside the gap, nothing.
func _drive_blessing(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as BlessingPower
	if power == null:
		return
	_buddy.mood.set_value(-60.0)
	var mood := _buddy.mood.value
	var pressed_at := Time.get_ticks_msec()
	_click()
	run.cooldown = float(power.recast_msec() - pressed_at)
	for i in 80:
		await _step()
	_expect(run, "blesses", run.acts.size() == 1, "a click on him is one blessing (%d acts)" % run.acts.size())
	_expect(run, "halo", power.is_live() and power._halo != null and power._halo.visible,
		"and a halo settles over him")
	_expect(run, "trickle", run.sustained_events >= 2,
		"which pays for as long as it stays (%d flushes)" % run.sustained_events)
	_expect(run, "mood", _buddy.mood.value > mood, "and he cheers up (%.1f to %.1f)" % [mood, _buddy.mood.value])
	var mult := Progression.damage_mult_for(run.item.id, power.damage_mult)
	var act_ok := run.acts.all(func(v: float) -> bool: return is_equal_approx(v, power.bless_value * mult))
	var flush := power.halo_rate * power.flush_seconds * mult
	run.value_checked = true
	run.value_ok = act_ok and run.sustained > 0.0 \
		and is_equal_approx(run.sustained, flush * float(run.sustained_events))
	_expect(run, "value", run.value_ok, "the blessing is worth %.2f and each flush %.3f" % [power.bless_value * mult, flush])
	var acts := run.acts.size()
	_click()
	await _step(3)
	_expect(run, "gap", run.acts.size() == acts, "blessed again inside the gap, nothing more is given")
	_move(_centre() + Vector2(320.0, -40.0))
	await _step(2)
	_click()
	await _step(3)
	_expect(run, "declines", run.acts.size() == acts, "and clicked off him, it does nothing")
	await _holster(run)
	_expect(run, "rests", not power.is_processing() and not power._halo.visible,
		"holstered, the halo goes and nothing of it runs")

## Held on him: he floats up, is paid while he is up there, and comes down softly when let go —
## touching down under the world's fall floor, so nothing is ever billed.
func _drive_levitation(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as LevitationPower
	if power == null:
		return
	var floor_y := _centre().y
	_press(MOUSE_BUTTON_LEFT)
	var rose := 0.0
	for i in 110:
		await _step()
		rose = maxf(rose, floor_y - _centre().y)
	_expect(run, "lifts", power.is_floating() and rose > 90.0,
		"held on him, he floats up (%.0f px)" % rose)
	_expect(run, "acts", run.acts.size() == 1, "and the lift is one kind act (%d)" % run.acts.size())
	_expect(run, "trickle", run.sustained_events >= 3,
		"and every half second up there pays (%d flushes)" % run.sustained_events)
	_release(MOUSE_BUTTON_LEFT)
	var fastest := 0.0
	for i in 240:
		await _step()
		fastest = maxf(fastest, _buddy.linear_velocity.y)
		if not power.is_live():
			break
	_expect(run, "sinks", not power.is_live() and absf(_centre().y - floor_y) < 6.0,
		"let go, he drifts back down to the desk (%.0f px off it)" % absf(_centre().y - floor_y))
	_expect(run, "softly", fastest <= power.sink_speed + 25.0 and run.hits.is_empty() and run.stray.is_empty(),
		"no faster than %.0f px/s (%.0f), and nothing is billed (%s)" % [power.sink_speed, fastest, run.stray])
	var mult := Progression.damage_mult_for(run.item.id, power.damage_mult)
	var flush := power.float_rate * power.flush_seconds * mult
	run.value_checked = true
	run.value_ok = run.acts.all(func(v: float) -> bool: return is_equal_approx(v, power.lift_value * mult)) \
		and is_equal_approx(run.sustained, flush * float(run.sustained_events))
	_expect(run, "value", run.value_ok, "the lift is worth %.2f and each flush %.3f" % [power.lift_value * mult, flush])
	await _holster(run)
	_expect(run, "rests", not power.is_physics_processing(), "and holstered, nothing of it runs")

## Pressed on him and dragged up and over to the right: a rainbow, a ride over the top, and a
## step off onto the desk where the cursor was let go.
func _drive_rainbow(run: Run) -> void:
	_move(_centre())
	await _step(2)
	var power := await _equip(run) as RainbowPower
	if power == null:
		return
	var start := _centre()
	var target := start + Vector2(380.0, -160.0)
	_press(MOUSE_BUTTON_LEFT)
	await _mouse_to(target, 900.0)
	var released_at := Time.get_ticks_msec()
	_release(MOUSE_BUTTON_LEFT)
	run.cooldown = float(power.recast_msec() - released_at)
	await _step(2)
	_expect(run, "rides", power.is_riding() and run.acts.size() == 1,
		"let go, a rainbow is drawn and he is on it (%d acts)" % run.acts.size())
	var peak := 0.0
	for i in 200:
		await _step()
		peak = maxf(peak, start.y - _centre().y)
		if not power.is_riding():
			break
	await _step(30)
	var off := absf(_centre().x - target.x)
	_expect(run, "arrives", not power.is_riding() and off < 40.0 and absf(_centre().y - start.y) < 8.0,
		"he rides it up %.0f px and steps off on the desk under the cursor (%.0f px off)" % [peak, off])
	_expect(run, "gently", run.hits.is_empty() and run.stray.is_empty(),
		"and nothing on the way is billed (%s)" % run.stray)
	_expect(run, "layers", _buddy.collision_layer != 0 and _buddy.collision_mask != 1,
		"and he is back on his own layers")
	var mult := Progression.damage_mult_for(run.item.id, power.damage_mult)
	run.value_checked = true
	run.value_ok = run.acts.all(func(v: float) -> bool: return is_equal_approx(v, power.ride_value * mult))
	_expect(run, "value", run.value_ok, "the ride is worth %.2f" % (power.ride_value * mult))
	var acts := run.acts.size()
	_move(_centre() + Vector2(-300.0, -60.0))
	await _step(2)
	_press(MOUSE_BUTTON_LEFT)
	await _step(4)
	_move(_mouse + Vector2(-200.0, 0.0))
	await _step(2)
	_release(MOUSE_BUTTON_LEFT)
	await _step(4)
	_expect(run, "declines", run.acts.size() == acts and not power.is_riding(),
		"and pressed off him, no rainbow")
	await _await(func() -> bool: return not power.is_live(), 60)
	await _holster(run)
	_expect(run, "rests", not power.is_physics_processing(), "and holstered, nothing of it runs")

func _drive_friendly(run: Run) -> void:
	var a := run.authored
	if bool(a.get("cleans_grime", false)) or bool(a.get("handheld", false)):
		await _rub(run)
	elif float(a.get("hearts_per_contact", 0.0)) > 0.0 and float(a.get("min_contact_speed", 0.0)) > 0.0:
		await _catch_it(run)
	elif float(a.get("hearts_per_second_touching", 0.0)) > 0.0:
		await _soak(run)
	elif float(a.get("hearts_per_contact", 0.0)) > 0.0:
		await _treat(run)
	elif float(a.get("hearts_per_second_placed", 0.0)) > 0.0:
		await _generator(run)
	else:
		_expect(run, "switch", false, "a FriendlyBase with no paying switch: there is nothing to drive")

## Dropped on his head. Food, mostly: it pays once — or once a helping — and goes if it is eaten.
func _treat(run: Run) -> void:
	# From despair, so a treat's mood lift is never lost against the top rail (D65).
	_buddy.mood.set_value(MoodMath.MIN_MOOD)
	var body = await _spawn(run, Vector2(_centre().x, _top() - 60.0))
	await _await(func() -> bool: return not run.acts.is_empty(), 60)
	_expect(run, "pays", not run.acts.is_empty(), "put on him, he has it (%d acts)" % run.acts.size())
	await _step(2)
	if bool(run.authored.get("consume_on_use", false)):
		# Every helping, a contact gap apart, and only then gone. A box of donuts is six.
		var servings := int(run.authored.get("servings", 1))
		var gap := float(run.authored.get("contact_cooldown", 0.5))
		await _await_gone(body, int(ceil(float(servings) * gap * 60.0)) + 30)
		_expect(run, "servings", run.acts.size() == servings,
			"he has all %d of it, one at a time (%d)" % [servings, run.acts.size()])
		_expect(run, "consumed", _gone(body), "and it is gone once it has paid")
	else:
		await _step(20)
		_expect(run, "stays", not _gone(body), "and it is still there afterwards, not eaten")
	_expect_act_value(run)
	_expect(run, "contract", run.contract("kindness") == run.acts.size(), "each one a kind act for the board")

## A catch: laid on him it is worth nothing, thrown at him it pays.
func _catch_it(run: Run) -> void:
	_buddy.mood.set_value(MoodMath.MIN_MOOD)
	var body := await _spawn(run, Vector2(_centre().x, _top() - 6.0)) as FriendlyBase
	if body == null:
		return
	await _step(25)
	_expect(run, "not_resting", run.acts.is_empty(), "laid gently on him it pays nothing (%.0f px/s needed)"
		% float(run.authored.get("min_contact_speed", 0.0)))
	if _gone(body) or not await _grab(run, body):
		return
	await _throw_at(_centre(), 1000.0)
	await _await(func() -> bool: return not run.acts.is_empty(), 60)
	_expect(run, "pays", not run.acts.is_empty(), "thrown at him, he catches it (%d acts)" % run.acts.size())
	_expect_act_value(run)
	await _step(2)
	if bool(run.authored.get("consume_on_use", false)):
		_expect(run, "consumed", _gone(body), "and it is used up")
	_expect(run, "contract", run.contract("kindness") == run.acts.size(), "each catch a kind act for the board")

## Somewhere he sits: put down beside him, then he is carried over and put in it.
func _soak(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(230.0, -60.0)) as FriendlyBase
	if body == null:
		return
	await _await_still(body, 60)
	if not await _grab(run, _buddy):
		return
	await _carry_to(_buddy, Vector2(body.global_position.x, body.get_interaction_rect().position.y - 70.0))
	_release_all()
	await _step(50 if run.upgraded else 90)
	_expect(run, "touching", run.touch_seconds > 0.3, "put in it, he stays in it (%.2fs touching)" % run.touch_seconds)
	_expect(run, "pays", run.sustained > 0.0, "and being in it pays (%.2f kindness)" % run.sustained)
	_expect(run, "entry", _fx.bursts.has(&"heart"), "hearts come off him when he gets in")
	await _expect_trickle(run, body)
	if float(run.authored.get("hearts_per_contact", 0.0)) > 0.0:
		_expect(run, "contact", not run.acts.is_empty(), "and getting in pays its one-off as well")
		_expect_act_value(run)
	_expect(run, "contract", run.contract("kindness") == run.acts.size(),
		"a trickle is not an act: the board sees only the acts (%d)" % run.contract("kindness"))

## Held against him and rubbed. The sponge and the towel take the grime off as well.
func _rub(run: Run) -> void:
	var cleans := bool(run.authored.get("cleans_grime", false))
	if cleans:
		_buddy.grime.set_value(1.0)
		run.grime_start = 1.0
		run.grime_seen = 1.0
		run.grime_removed = 0.0
	var body := await _spawn(run, _centre() + Vector2(-200.0, -80.0)) as FriendlyBase
	if body == null or not await _grab(run, body):
		return
	await _mouse_to(_centre() + Vector2(-30.0, -10.0), 500.0)
	for i in (3 if run.upgraded else 6):
		await _mouse_to(_centre() + Vector2(35.0, -10.0 + 8.0 * (i % 2)), 250.0)
		await _mouse_to(_centre() + Vector2(-35.0, -10.0), 250.0)
	_release_all()
	await _step(4)
	_expect(run, "touching", run.touch_seconds > 0.2, "rubbed on him, it touches him (%.2fs)" % run.touch_seconds)
	_expect(run, "pays", run.sustained > 0.0, "and pays while it does (%.2f kindness)" % run.sustained)
	await _expect_trickle(run, body)
	if cleans:
		_expect(run, "cleans", _buddy.grime.value < 1.0, "and takes grime off him (1.0 to %.2f)" % _buddy.grime.value)

## A generator: put down away from him, and it pays for being there.
func _generator(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(300.0, -40.0)) as FriendlyBase
	if body == null:
		return
	await _step(50 if run.upgraded else 90)
	_expect(run, "pays", run.sustained_events > 0 and run.sustained > 0.0,
		"left on the desk, it trickles kindness (%d flushes, %.2f)" % [run.sustained_events, run.sustained])
	_expect(run, "not_acts", run.contract("kindness") == 0 and run.acts.is_empty(),
		"and a trickle is never an act, so the board is not ticked")
	await _expect_trickle(run, body)
	if FriendlyBase.AMBIENT.has(run.item.id) and not _gone(body):
		var ambient := body.get_node_or_null("Ambient") as GPUParticles2D
		_expect(run, "ambient", ambient != null and ambient.emitting, "and it has its %s about it" % FriendlyBase.AMBIENT[run.item.id])
	var lifetime := float(run.authored.get("lifetime_seconds", 0.0))
	if lifetime > 0.0 and not _gone(body) and not run.upgraded:
		run.notes.append("lifetime %.0fs" % lifetime)
		body._age = lifetime
		await _step(3)
		_expect(run, "runs_out", _gone(body), "and it runs out when its time is up")

## A trickle, to the frame: a kind item banks `rate x value x delta` on exactly the frames it
## ages (placed) and touches him (touching), so what it paid is a number known in advance. A
## cleaner is paid for the grime it took off as well, which is his grime then and now.
func _expect_trickle(run: Run, body: FriendlyBase) -> void:
	if _gone(body):
		return
	# `_step` resumes at the start of a physics tick, so the frame last counted here has not
	# been banked by the item yet. Wait for the tick to finish.
	await get_tree().process_frame
	if _gone(body):
		return
	var value := Progression.get_modifier(run.item.id, &"damage_mult")
	var placed := float(run.authored.get("hearts_per_second_placed", 0.0))
	var touching := float(run.authored.get("hearts_per_second_touching", 0.0))
	var cleaned := 0.0
	if bool(run.authored.get("cleans_grime", false)):
		var last := maxf(0.0, run.grime_seen - _buddy.grime.value)
		cleaned = (run.grime_removed + last) * ItemDB.balance.hearts_per_grime_cleaned
		# A hit dirties him on the same frame the sponge cleans him, and a frame's net change
		# then understates what came off. Nothing else is billed while it is used, or no answer.
		if run.stray_hits > 0:
			run.notes.append("%s: trickle not checked, he was hit while being cleaned" % run.label())
			return
	var expected := value * (placed * body._age + touching * run.touch_seconds + cleaned)
	var got := run.sustained + body._banked
	var ok := absf(got - expected) <= 0.002 * maxf(1.0, expected)
	run.value_checked = true
	run.value_ok = run.value_ok and ok
	_expect(run, "rate", ok, "at exactly its rate x %.3f (%.4f paid, the data says %.4f)" % [value, got, expected])

func _expect_act_value(run: Run) -> void:
	var value := float(run.authored.get("hearts_per_contact", 0.0)) \
		* Progression.get_modifier(run.item.id, &"damage_mult")
	if run.acts.is_empty():
		return
	var ok := run.acts.all(func(v: float) -> bool: return is_equal_approx(v, value))
	run.value_checked = true
	run.value_ok = run.value_ok and ok
	_expect(run, "act_value", ok, "worth exactly %.3f a time (%s)" % [value, run.acts])
	if not run.act_gaps.is_empty():
		run.cooldown = float(run.act_gaps[0])
	if run.mood_checked:
		_expect(run, "mood_lift", run.mood_ok, "and each one lifts his mood by its worth x %.2f%s"
			% [Progression.get_modifier(run.item.id, &"mood_mult"),
				"" if run.mood_ok else ": " + run.mood_bad])

# --- drivers: held guns (D56) ---------------------------------------------------------------

## Whether a held gun has said it is pointed at him this run (D56's `aim` threat). A listener
## of its own, connected on first use: the suite's threat probe keeps to fuses.
var _threatened := false

func _on_aim_threat(kind: StringName, _at: Vector2, level: float) -> void:
	if _run != null and kind == &"aim" and level > 0.0:
		_threatened = true

## A gun you hold, used the way D56's grammar says: picked up by its grab region, carried to a
## stand-off beside him, left to lay its own barrel on him, then the right button — one tap, a
## second tap at once that its gap must refuse, and then another shot or, full-auto, the
## trigger held down for a stream. What a shot is (`bullet`, `water`, `bubble`) is read off the
## gun and which side it pays on off the item, so all seven are this one driver.
func _drive_held_gun(run: Run) -> void:
	if not EventBus.threat_changed.is_connected(_on_aim_threat):
		EventBus.threat_changed.connect(_on_aim_threat)
	_threatened = false
	_reseed(run)
	var body := await _spawn(run, _centre() + Vector2(-300.0, -150.0)) as HeldGun
	if body == null:
		return
	# Off the spawned body rather than `_authored`'s fresh instance — no augment touches either —
	# because a shot is billed at `shot_mult`, by an impulse of exactly `shot_force`, and a gun
	# bounced off him at its contact `damage_mult` (`_hit_multiplier`).
	run.authored["shot_mult"] = body.shot_mult
	run.authored["shot_force"] = body.shot_force
	var kind := body.is_kind_gun()
	run.notes.append("%s every %.2fs%s" % [body.shot_kind, body.fire_interval,
		", full auto" if body.auto_fire else ""])
	if body.shot_kind == &"water":
		# Filthy, so every squirt that lands has grime to take off.
		_buddy.grime.set_value(1.0)
		run.grime_start = 1.0
		run.grime_seen = 1.0
		run.grime_removed = 0.0
	await _await_still(body, 60)
	if not await _grab(run, body):
		return
	# Level with his chest and well inside its reach. Bubbles drift at 80 px/s, so the blaster
	# stands closer, or the run is spent watching them cross the desk.
	var stand := 150.0 if body.shot_kind == &"bubble" else clampf(body.shot_range * 0.5, 160.0, 260.0)
	await _mouse_to(_centre() + Vector2(-stand, -30.0), 700.0)
	var settle := await _aim_settles(body, 90)
	_expect(run, "aims", settle >= 0, "held beside him, it lays its own barrel on him (%s)"
		% (("in %.2fs" % (settle / 60.0)) if settle >= 0
			else "never: %.1f deg off" % rad_to_deg(absf(body.aim_error()))))
	if not kind:
		var cowers := await _await(func() -> bool: return _buddy.expression.beat_id() == &"aimed_at", 60)
		_expect(run, "threat", _threatened and cowers,
			"pointed at him, it says so, and he cowers (beat '%s')" % _buddy.expression.beat_id())

	# One tap, and at once a second, which the gap must refuse. The gap is read off the gun's
	# own clock against a time taken before the press; it due-dates the next shot a frame early
	# to keep a stream's phase (D56), so that frame goes back on.
	var muzzle := body.muzzle_position()
	var first_tracer := _fx.tracers.size()
	await _step()
	var spin_before := body.angular_velocity
	await _step()
	var spin_at := body.angular_velocity
	var pressed_at := Time.get_ticks_msec()
	_press(MOUSE_BUTTON_RIGHT)
	var fired := body.shots_fired
	if fired == 1:
		run.cooldown = float(body._next_shot_msec - pressed_at + _frame_msec())
	_release(MOUSE_BUTTON_RIGHT)
	_press(MOUSE_BUTTON_RIGHT)
	_release(MOUSE_BUTTON_RIGHT)
	_expect(run, "fires", fired == 1 and body.shots_fired == 1,
		"right-click in the hand fires one shot, and a second click inside its %.2fs gap does not (%d)"
		% [body._interval(), body.shots_fired])
	var in_air := _bubbles().size()
	await _step()
	# The kick, as the angular momentum the shot handed it: the change in spin over the step it
	# landed in, less the change the aim was already making, times its mass. Mass-normalised on
	# purpose — the Weight node turns a heavier gun less for the same impulse, and must not be
	# able to pass for the Steady one.
	var kick := absf((body.angular_velocity - spin_at) - (spin_at - spin_before)) * body.mass
	var peak := 0.0
	for i in 20:
		peak = maxf(peak, absf(body.aim_error()))
		await _step()
	if not kind:
		_gauge(run, &"recoil_mult", kick)
		run.notes.append("kick %.1f deg, %.1f kg rad/s" % [rad_to_deg(peak), kick])
		_expect(run, "kicks", peak > deg_to_rad(0.5), "and the shot kicks it off him (%.1f deg)" % rad_to_deg(peak))

	# The gap waited out, the aim back on him, and then the rest of the magazine.
	await _step(int(ceil(body._interval() * 60.0)) + 2)
	await _aim_settles(body, 60)
	if body.auto_fire:
		var before := body.shots_fired
		_press(MOUSE_BUTTON_RIGHT)
		await _step(50)
		_release(MOUSE_BUTTON_RIGHT)
		var streamed := body.shots_fired - before
		await _step(10)
		_expect(run, "stream", streamed >= 3 and body.shots_fired == before + streamed
			and not body.trigger_held(),
			"holding right keeps it firing (%d shots in %.2fs), and letting go stops it" % [streamed, 50.0 / 60.0])
	else:
		_press(MOUSE_BUTTON_RIGHT)
		_release(MOUSE_BUTTON_RIGHT)
		await _step(10)
		_expect(run, "again", body.shots_fired == 2, "and once the gap has passed it fires again (%d)"
			% body.shots_fired)
	var shots := body.shots_fired
	_expect(run, "use", run.uses() == shots, "each shot is a use:%s for the board (%d of %d)"
		% [run.item.id, run.uses(), shots])
	if kind:
		_expect(run, "no_threat", not _threatened, "a kind gun is never a threat to him")
		_expect(run, "no_hits", run.hits.is_empty(), "and never bills him a hit (%d)" % run.hits.size())
	match body.shot_kind:
		&"water":
			_expect_tracer(run, muzzle, first_tracer, false)
			await _expect_squirts(run, body)
		&"bubble":
			_expect(run, "blows", in_air >= 1, "a shot is a bubble in the air (%d)" % in_air)
			await _expect_bubbles(run, body, shots)
		_:
			_expect_tracer(run, muzzle, first_tracer, true)
	if run.upgraded:
		await _bin_in_the_hand(run, body)
	else:
		await _thrown_gun(run, body, kind)

## Frames until the aim holds within two degrees of him for a tenth of a second, or -1.
func _aim_settles(body: HeldGun, frames: int) -> int:
	var inside := 0
	for i in frames:
		await _step()
		if _gone(body):
			return -1
		inside = inside + 1 if absf(body.aim_error()) < deg_to_rad(2.0) else 0
		if inside >= 6:
			return i - 4
	return -1

## A physics frame in whole milliseconds, as `HeldGun.fire` rounds it.
func _frame_msec() -> int:
	return int(1000.0 / float(Engine.physics_ticks_per_second))

## The first shot's tracer leaves from the muzzle, one lands on him, and — for a gun that
## hurts — the shots are hits through the real pipeline that the world answers.
func _expect_tracer(run: Run, muzzle: Vector2, first: int, harm: bool) -> void:
	var from_muzzle := _fx.tracers.size() > first \
		and (_fx.tracers[first][0] as Vector2).distance_to(muzzle) < 3.0
	var on_him := false
	for line in _fx.tracers.slice(first):
		if (line[1] as Vector2).distance_to(line[2]) < 90.0:
			on_him = true
	_expect(run, "tracer", from_muzzle, "the shot leaves from its muzzle (%d tracers)" % (_fx.tracers.size() - first))
	_expect(run, "aimed", on_him, "and lands on him")
	if harm:
		_expect(run, "hits", not run.hits.is_empty(), "and it hurts him (%d hits)" % run.hits.size())
		_expect(run, "effect", _fx.reactions.has(run.item.id), "and the world answers each hit")

## The water pistol. Every squirt that lands takes `squirt_clean` off a filthy skeleton and
## banks `(grime x rate + a squirt's worth) x value`. The grime, measured off him frame by
## frame, says how many landed; the pay must then be exactly that — which it cannot be if the
## value node were skipped or doubled, or a squirt paid that did not land.
func _expect_squirts(run: Run, body: HeldGun) -> void:
	await get_tree().process_frame
	var removed := run.grime_removed + maxf(0.0, run.grime_seen - _buddy.grime.value)
	var landed := roundf(removed / body.squirt_clean)
	_expect(run, "cleans", landed >= 1.0 and absf(removed / body.squirt_clean - landed) < 0.01,
		"a squirt on him scrubs him: %.3f grime off, %.0f squirts' worth" % [removed, landed])
	_expect(run, "pays", run.sustained > 0.0, "and pays for it as a trickle (%.2f kindness)" % run.sustained)
	_expect(run, "not_acts", run.acts.is_empty() and run.contract("kindness") == 0,
		"which is never an act, so the board is not ticked")
	if _gone(body):
		return
	var value := body.value_multiplier()
	var expected := value * (removed * ItemDB.balance.hearts_per_grime_cleaned + landed * body.squirt_value)
	var got := run.sustained + body._banked
	var ok := absf(got - expected) <= 0.002 * maxf(1.0, expected)
	run.value_checked = true
	run.value_ok = run.value_ok and ok
	_expect(run, "rate", ok, "at exactly (grime x %.0f + %.2f) x %.3f a squirt (%.4f paid, the data says %.4f)"
		% [ItemDB.balance.hearts_per_grime_cleaned, body.squirt_value, value, got, expected])

## The bubble blaster. Every bubble drifts over and pops on him as one kind act of exactly
## `bubble_value x value`; any still in the air at the end are aged out, not waited for.
func _expect_bubbles(run: Run, body: HeldGun, shots: int) -> void:
	await _await(func() -> bool: return run.acts.size() >= shots, 240)
	for bubble in _bubbles():
		bubble.set("_age", HeldGun.Bubble.LIFETIME)
	await _step(2)
	_expect(run, "pops", not run.acts.is_empty(), "the bubbles drift to him and pop as kind acts (%d of %d)"
		% [run.acts.size(), shots])
	_expect(run, "contract", run.contract("kindness") == run.acts.size(), "each one a kind act for the board")
	_expect_acts_worth(run, body.bubble_value * body.value_multiplier(), "a bubble that reaches him")
	_expect(run, "cleared", _bubbles().is_empty(), "and none is left in the air")

func _bubbles() -> Array[Node]:
	var out: Array[Node] = []
	if is_instance_valid(_stage):
		for node in _stage.get_children():
			if node is HeldGun.Bubble and not node.is_queued_for_deletion():
				out.append(node)
	return out

## Let go of mid-swing at him, as a player throws what is in their hand. A harm gun is a lump
## of metal and may bill its contact multiplier; a kind one bills nothing whatever it hits him
## with (D56, `HeldGun.effective_damage_mult`).
func _thrown_gun(run: Run, body: HeldGun, kind: bool) -> void:
	if _gone(body):
		return
	var hits := run.hits.size()
	var bones := run.bones
	await _throw_at(_centre(), 1400.0)
	# Asked of his own contact list, so "it bills nothing" is never said of a throw that missed.
	# The list reports a contact a step after the step that stopped it, so the speed it arrived
	# at is a fading peak, as the stress ball keeps one for its catch.
	var speed := 0.0
	var touched := -1.0
	for i in 40:
		if _gone(body):
			break
		speed = maxf(body.linear_velocity.length(), speed * 0.66)
		if touched < 0.0 and _buddy.get_colliding_bodies().has(body):
			touched = speed
		await _step()
	var landed := run.hits.size() - hits
	run.notes.append("thrown into him at %.0f px/s: %d contact hit(s)" % [touched, landed] if touched >= 0.0
		else "thrown, and missed him")
	if kind:
		_expect(run, "thrown", touched > 300.0 and landed == 0 and run.bones == bones,
			"thrown into him (%.0f px/s), a kind gun bills nothing (%d hits)" % [touched, landed])
	else:
		_expect(run, "thrown", touched > 300.0 and landed > 0,
			"thrown into him (%.0f px/s), a harm gun is a lump of metal and bills its contact multiplier (%d hits)"
			% [touched, landed])

## Shift+right in the hand bins it instead of firing it: D24's override, which no trigger may
## claim. Asked where the hand is, which is over its grab region.
func _bin_in_the_hand(run: Run, body: HeldGun) -> void:
	# Back on him first: a long gun still swinging from its kick has swung out from under the
	# hand that took it by the middle.
	await _aim_settles(body, 90)
	if _gone(body):
		return
	if body.drag_area and not body.drag_area.is_hovered:
		run.notes.append("the hand was not over it for the in-hand bin")
		return
	var uses := run.uses()
	_press(MOUSE_BUTTON_RIGHT, true)
	_release(MOUSE_BUTTON_RIGHT, true)
	await _step(2)
	_expect(run, "bins_held", _gone(body) and run.uses() == uses,
		"Shift+right in the hand bins it instead of firing")

# --- drivers: the fidget layer (D57) -------------------------------------------------------
#
# Every toy on `GestureZones` is worked the same way: synthetic events at a zone's real place
# in the world, through the viewport, into `BaseDraggable._unhandled_input`, into the zones —
# never a call on the toy. A new toy class is a row in DRIVERS and a driver built from the
# helpers here: `_zone_point`, `_tap_zone`, `_stroke`, `_crank_zone`, `_hold_right`, `_shake`,
# and `_watch_faces` / `_expect_face` for the row his face answers each fidget event with.

## His face on each fidget event the item under test raises: [event, the beat he is in once
## his brain has answered it]. A member, not a local: a lambda captures locals by value.
var _faces: Array = []
## What the spinner owes for its watched trickle, summed tick by tick (see `_drive_spinner`).
var _spin_owed := 0.0

## Listens *after* his brain, so the beat read is the one it chose — and so reconnected per
## driver: every stage builds a new buddy whose brain connects when it is born, and a watcher
## connected for an earlier stage would hear each event before it.
func _watch_faces() -> void:
	_faces.clear()
	_spin_owed = 0.0
	if EventBus.fidget_event.is_connected(_on_fidget_face):
		EventBus.fidget_event.disconnect(_on_fidget_face)
	EventBus.fidget_event.connect(_on_fidget_face)

func _on_fidget_face(item_id: StringName, event: StringName, _at: Vector2) -> void:
	if _run == null or item_id != _run.item.id or not is_instance_valid(_buddy):
		return
	_faces.append([event, _buddy.expression.beat_id()])
	# The spinner pays its watched trickle and says so in the same breath (`_on_tick`), before
	# its tick clock is reset — so what that tick banked is known exactly, here.
	if event == &"spinning" and not _gone(_run.body) and _run.body is FidgetSpinner:
		var spinner := _run.body as FidgetSpinner
		_spin_owed += spinner.watch_value * absf(spinner.spin) / spinner.max_spin * spinner._tick \
			* spinner.value_multiplier()

## The toy raised `event`, and his face answered it with the row `ExpressionBrain.FIDGET_ROWS`
## gives it — the toy's claim about him, asked of him.
func _expect_face(run: Run, event: StringName) -> void:
	var row: StringName = ExpressionBrain.FIDGET_ROWS.get(event, &"")
	var raised := _faces.filter(func(f: Array) -> bool: return f[0] == event)
	var shown := raised.any(func(f: Array) -> bool: return f[1] == row)
	var beats := PackedStringArray()
	for f in raised:
		beats.append(String(f[1]))
	_expect(run, "face_%s" % event, shown, "he answers '%s' with his %s row (%s)"
		% [event, row, ", ".join(beats) if not beats.is_empty() else "never raised"])

## Where a toy's zone is now, in the view, plus an offset in the toy's own art pixels — so a
## point on a crank's rim or the edge of a bubble turns and mirrors with the body as the zones
## do. Through the canvas transform, which carries the screen shake.
func _zone_point(body: BaseDraggable, zone: StringName, art_offset: Vector2 = Vector2.ZERO) -> Vector2:
	var zones := body.gesture_zones
	var world := zones.art_to_world(zones.world_to_art(zones.zone_world(zone)) + art_offset)
	return body.get_canvas_transform() * world

## A tap on a zone: the cursor over it, pressed for as long as a click takes, let go.
## `before_release` runs immediately before the release, with nothing in between.
func _tap_zone(body: BaseDraggable, zone: StringName, button: MouseButton,
		before_release: Callable = Callable()) -> void:
	_move(_zone_point(body, zone))
	await _step()
	_press(button)
	await _step(3)
	if before_release.is_valid():
		before_release.call()
	_release(button)

## A motion carrying the velocity it really has. Windows gives every real mouse event one, and
## a flick is read from it (`GestureZones._velocity_of`).
func _move_at(to: Vector2, velocity: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = to
	e.global_position = to
	e.relative = to - _mouse
	e.velocity = velocity
	e.button_mask = _held
	_mouse = to
	_view.push_input(e, true)

## A stroke with a button down: pressed at `from`, carried to `to` in `frames` motions a
## physics frame apart, and let go at the end with no pause — so a fast one is a flick.
func _stroke(from: Vector2, to: Vector2, button: MouseButton, frames: int) -> void:
	_move(from)
	await _step()
	_press(button)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var last := from
	for i in range(1, frames + 1):
		var at := from.lerp(to, float(i) / float(frames))
		_move_at(at, (at - last) / dt)
		last = at
		await _step()
	_release(button)

## Circles round a zone's pivot with a button down — a sixteenth of a turn a motion, two
## motions a physics frame — until `done` says so or `turns` run out. Returns the turns made.
func _crank_zone(body: BaseDraggable, zone: StringName, button: MouseButton, turns: float,
		done: Callable) -> float:
	var rim := Vector2(10.0, 0.0)
	_move(_zone_point(body, zone) + rim)
	await _step()
	_press(button)
	var made := 0
	for i in range(1, int(ceil(turns * 16.0)) + 1):
		if done.call():
			break
		_move(_zone_point(body, zone) + rim.rotated(TAU * float(i) / 16.0))
		made = i
		if i % 2 == 0:
			await _step()
	_release(button)
	return float(made) / 16.0

## The item's own verb in the hand (D57's ACTION): right held down for `frames` and let go.
## `before_release` is asked on the last frame it is still down. Returns how long it was held,
## by the microsecond clock the zones read.
func _hold_right(frames: int, before_release: Callable = Callable()) -> float:
	var began := Time.get_ticks_usec()
	_press(MOUSE_BUTTON_RIGHT)
	await _step(frames)
	if before_release.is_valid():
		before_release.call()
	var held := float(Time.get_ticks_usec() - began) / 1.0e6
	_release(MOUSE_BUTTON_RIGHT)
	return held

## Carried side to side in the hand, a leg a physics frame, until `ready` says so or `legs`
## run out. The first leg sets a direction and every later one reverses it. Returns the legs.
func _shake(legs: int, amplitude: float, ready: Callable) -> int:
	var home := _mouse
	for i in legs:
		if ready.call():
			return i
		_move(home + Vector2(amplitude if i % 2 == 0 else -amplitude, 0.0))
		await _step()
	return legs

## Bubble wrap: a left tap on a bubble pops it and does not lift the sheet; a right-stroke from
## there across the row pops the run it passes over and never bins the sheet; a popped bubble
## grows back and claims its tap again; and he pops one by coming down on it.
func _drive_bubble_wrap(run: Run) -> void:
	_watch_faces()
	var body := await _spawn(run, _centre() + Vector2(-210.0, -30.0)) as BubbleWrap
	if body == null:
		return
	await _await_still(body, 60)
	var intact := body.intact_count()
	await _tap_zone(body, &"b0", MOUSE_BUTTON_LEFT)
	# The gap its third node shortens, as the pop just set it on the sheet's own clock.
	run.cooldown = body._regrow.wait_time * 1000.0
	await _step()
	_expect(run, "pops", body.is_popped(0) and run.acts.size() == 1 and not body.dragging,
		"a left tap on a bubble pops it for one act, and does not pick the sheet up (%d acts)" % run.acts.size())
	_expect(run, "spent", not body.gesture_zones.zone_enabled(&"b0"), "and a popped bubble claims nothing")
	var before := run.acts.size()
	await _stroke(_zone_point(body, &"b0"), _zone_point(body, &"b3"), MOUSE_BUTTON_RIGHT, 4)
	await _step(2)
	var row := body.is_popped(1) and body.is_popped(2) and body.is_popped(3) and not body.is_popped(4)
	_expect(run, "run", row and run.acts.size() == before + 3 and not _gone(body),
		"a right-stroke across the sheet pops the run it passes over, and does not bin it (%d more)"
		% (run.acts.size() - before))
	_expect_face(run, &"amused")
	_expect_acts_worth(run, body.pop_value * body.value_multiplier(), "a pop")
	_expect(run, "contract", run.contract("kindness") == run.acts.size(), "each pop a kind act for the board")
	if run.upgraded:
		return
	# Grows back: its clock wound on, not waited out.
	run.notes.append("regrow %.1fs" % body.regrow_seconds)
	body._regrow.start(0.02)
	await _step(4)
	_expect(run, "regrows", body.intact_count() == intact - 3 and body.gesture_zones.zone_enabled(&"b0"),
		"a popped bubble grows back and claims its tap again (%d intact)" % body.intact_count())
	# He is carried over and put down on it.
	var flat := body.intact_count()
	if not await _grab(run, _buddy):
		return
	await _carry_to(_buddy, Vector2(body.global_position.x, body.get_interaction_rect().position.y - 110.0))
	_release_all()
	var sheet: WeakRef = weakref(body)
	await _await(func() -> bool: return sheet.get_ref() == null or sheet.get_ref().intact_count() < flat, 90)
	_expect(run, "landing", not _gone(body) and body.intact_count() < flat,
		"put down on it, he pops one (%d to %d)" % [flat, body.intact_count() if not _gone(body) else -1])

## Stress ball: held, right held down squeezes it — it swaps to its drawn squashed face past
## the swap point — and letting go pays by how hard; thrown at him, he catches it and pays,
## then tosses it back up.
func _drive_stress_ball(run: Run) -> void:
	_watch_faces()
	var body := await _spawn(run, _centre() + Vector2(-220.0, -40.0)) as StressBall
	if body == null:
		return
	await _await_still(body, 60)
	if not await _grab(run, body):
		return
	await _mouse_to(_centre() + Vector2(-220.0, -130.0), 600.0)
	await _steady(body, 30)
	var squeeze := [false, false]
	var held := await _hold_right(45, func() -> void:
		squeeze[0] = body.is_squeezing()
		squeeze[1] = body.squeeze_sprite != null and body.squeeze_sprite.visible and not body.sprite.visible)
	await _step()
	_expect(run, "squeezes", squeeze[0] and squeeze[1], "held, right held down squeezes it, past %.1f on its squashed face"
		% StressBall.SWAP_AT)
	_expect(run, "pays", run.acts.size() == 1 and not body.is_squeezing(),
		"and letting go of right pays for the squeeze (%d acts, charge %.2f)" % [run.acts.size(), body.charge])
	# The time to a full squeeze, which its third node shortens: the hold over the charge it made.
	if body.charge > 0.0 and body.charge < 1.0:
		run.cooldown = held / body.charge * 1000.0
	var squeezed := body.squeeze_value * (0.25 + 0.75 * body.charge) * body.value_multiplier()
	_expect_face(run, &"amused")
	_release_all()
	if run.upgraded:
		_expect_acts_worth(run, squeezed, "a squeeze of %.2f" % body.charge)
		return
	await _await_still(body, 60)
	var caught := false
	if await _grab(run, body):
		await _throw_at(_centre(), 1000.0)
		var ball: WeakRef = weakref(body)
		caught = await _await(func() -> bool: return ball.get_ref() == null or ball.get_ref().is_caught(), 60)
		caught = caught and not _gone(body) and body.is_caught()
	_expect(run, "catches", caught and run.acts.size() == 2, "thrown at him, he catches it, and the catch pays (%d acts)"
		% run.acts.size())
	_expect_face(run, &"caught")
	var worth := run.acts.size() == 2 and is_equal_approx(run.acts[0], squeezed) \
		and is_equal_approx(run.acts[1], body.catch_value * body.value_multiplier())
	run.value_checked = true
	run.value_ok = run.value_ok and worth
	_expect(run, "act_value", worth, "a squeeze worth exactly %.3f and a catch %.3f (%s)"
		% [squeezed, body.catch_value * body.value_multiplier(), run.acts])
	if caught:
		var held_ball: WeakRef = weakref(body)
		var tossed := await _await(func() -> bool: return held_ball.get_ref() == null or not held_ball.get_ref().is_caught(), 90)
		_expect(run, "tossed", tossed and not _gone(body), "then he tosses it back up (after %.1fs)" % body.catch_seconds)

## Fidget spinner: a right-swipe across an arm spins it; while it spins in front of him it pays
## a watched trickle, exactly what each tick says it is worth, and he stares at it; it runs
## down, and at rest it settles on a third of a turn and stops running frames.
func _drive_spinner(run: Run) -> void:
	_watch_faces()
	var body := await _spawn(run, _centre() + Vector2(-170.0, -30.0)) as FidgetSpinner
	if body == null:
		return
	await _await_still(body, 60)
	var hub := body.get_canvas_transform() * body.rotor.global_position
	await _stroke(hub + Vector2(18.0, 12.0), hub + Vector2(20.0, -8.0), MOUSE_BUTTON_RIGHT, 1)
	var from := absf(body.spin)
	var since := Time.get_ticks_usec()
	_expect(run, "spins", body.is_spinning() and from > body.max_spin * 0.5 and not _gone(body),
		"a right-swipe across an arm spins it (%.1f of %.0f rad/s), and never bins it" % [from, body.max_spin])
	await _step(120)
	if _gone(body):
		return
	# How fast it runs down, on its own clock: its third node makes that slower, which is the gap
	# before it needs another flick getting longer.
	var seconds := float(Time.get_ticks_usec() - since) / 1.0e6
	run.cooldown = (from - absf(body.spin)) / seconds * 1000.0
	run.notes.append("runs down %.2f rad/s a second from %.0f" % [run.cooldown / 1000.0, from])
	_expect(run, "watched", run.sustained > 0.0, "spinning in front of him, it pays (%.2f kindness)" % run.sustained)
	_expect_face(run, &"spinning")
	var got := run.sustained + body._banked
	var ok := _spin_owed > 0.0 and absf(got - _spin_owed) <= 0.002 * maxf(1.0, _spin_owed)
	run.value_checked = true
	run.value_ok = run.value_ok and ok
	_expect(run, "rate", ok, "exactly what each tick of its spin is worth (%.4f paid, %.4f owed)" % [got, _spin_owed])
	_expect(run, "not_acts", run.acts.is_empty() and run.contract("kindness") == 0,
		"a watched spin is a trickle, never an act")
	if run.upgraded:
		return
	# Run down — the last of it skewed, not waited out — and at rest it costs nothing.
	body.spin = FidgetSpinner.STOP_SPIN * 1.1 * signf(body.spin)
	var spinner: WeakRef = weakref(body)
	await _await(func() -> bool: return spinner.get_ref() == null or not spinner.get_ref().is_processing(), 120)
	if _gone(body):
		return
	var third := fposmod(body.rotor.rotation, TAU / 3.0)
	_expect(run, "rests", not body.is_processing() and minf(third, TAU / 3.0 - third) < 0.01,
		"run down, it settles on a third of a turn and stops running frames")

## Fortune ball: right-tapped unshaken where it lies, it says to shake it first and pays
## nothing; picked up and shaken, it is ready after its reversals; right-click reads it — a use
## each — and a yes pays and cheers him. Read until it says yes, as a player would.
func _drive_fortune_ball(run: Run) -> void:
	_watch_faces()
	_reseed(run)
	var body := await _spawn(run, _centre() + Vector2(-190.0, -40.0)) as MagicEightBall
	if body == null:
		return
	await _await_still(body, 60)
	await _tap_zone(body, &"ball", MOUSE_BUTTON_RIGHT)
	await _step()
	_expect(run, "unshaken", not _gone(body) and body.last_answer == MagicEightBall.UNSHAKEN
		and body.answer_showing() and run.acts.is_empty() and run.uses() == 0,
		"right-tapped unshaken, it says to shake it first, pays nothing, and is not binned")
	if _gone(body) or not await _grab(run, body):
		return
	await _mouse_to(_mouse + Vector2(0.0, -90.0), 500.0)
	var ball: WeakRef = weakref(body)
	var tones: Array[StringName] = []
	var legs := -1
	for attempt in 8:
		var took := await _shake(16, 36.0, func() -> bool:
			return ball.get_ref() == null or ball.get_ref().is_ready_to_read())
		if legs < 0:
			legs = took
		if _gone(body) or not body.is_ready_to_read():
			break
		_press(MOUSE_BUTTON_RIGHT)
		_release(MOUSE_BUTTON_RIGHT)
		tones.append(body.last_tone)
		if body.last_tone == &"yes":
			break
		await _step(2)
	# The reversals it took to be ready, which its third node is sold as taking off.
	if legs > 0:
		run.cooldown = float(legs - 1)
	_expect(run, "shaken", legs > 1 and not tones.is_empty(), "shaken in the hand, it is ready after %d reversals"
		% (legs - 1))
	_expect(run, "reads", run.uses() == tones.size() and not tones.is_empty(),
		"right-click reads it, a use:%s each (%d reads: %s)" % [run.item.id, tones.size(), tones])
	_expect(run, "answer", not _gone(body) and body.answer_showing() and body.answer_text() == body.last_answer,
		"and the answer shows above it ('%s')" % (body.last_answer if not _gone(body) else ""))
	_expect(run, "yes_pays", run.acts.size() == tones.count(&"yes"), "a yes pays and nothing else does (%d acts)"
		% run.acts.size())
	_expect_acts_worth(run, body.answer_value * body.value_multiplier(), "a yes")
	var asked := {}
	for tone in tones:
		if not asked.has(tone):
			asked[tone] = true
			_expect_face(run, StringName("answer_%s" % tone))

## Jack-in-the-box: right-circling the crank winds it, and it pops at the tune's end — a use —
## and he startles; a beat later he laughs, and the laugh is the pay; a right-tap on the lid
## puts him back, and it winds and pops again.
func _drive_jack(run: Run) -> void:
	_watch_faces()
	var body := await _spawn(run, _centre() + Vector2(-170.0, -30.0)) as JackInTheBox
	if body == null:
		return
	await _await_still(body, 60)
	run.notes.append("facing %s" % ("mirrored" if body.facing < 0.0 else "as drawn"))
	var wound := await _wind_jack(body)
	_expect(run, "pops", body.is_out() and wound >= body.turns_needed() and wound <= body.turns_needed() + 0.25,
		"right-circling the crank winds it, and it pops at the end of the tune (%.2f of %.2f turns)"
		% [wound, body.turns_needed()])
	_expect(run, "use", run.uses() == 1, "the pop is a use:%s" % run.item.id)
	_expect_face(run, &"jack_popped")
	var laughed := await _await(func() -> bool: return not run.acts.is_empty(), 60)
	_expect(run, "laughs", laughed and run.acts.size() == 1, "a beat later he laughs, and the laugh pays (mood %.0f)"
		% Economy.mood)
	_expect_face(run, &"jack_laugh")
	# The next tune is drawn as the lid shuts. From the same draw in both phases — the first
	# was spent differently, on the binned copy and the upgraded one's aura — so the third
	# node's shorter tune is the only difference between the two that follow.
	await _tap_zone(body, &"lid", MOUSE_BUTTON_RIGHT, func() -> void: _reseed(run))
	await _step(2)
	_expect(run, "closes", not _gone(body) and not body.is_out() and is_zero_approx(body.turns_wound()),
		"a right-tap on the lid puts him back, ready to wind again")
	if _gone(body):
		return
	var again := await _wind_jack(body)
	run.notes.append("second tune %.2f turns" % again)
	_expect(run, "again", body.is_out() and run.uses() == 2, "and wound again, it pops again (%.2f turns)" % again)
	# Milli-turns: the tune its third node shortens, as wound by hand.
	run.cooldown = again * 1000.0
	await _await(func() -> bool: return run.acts.size() >= 2, 60)
	_expect_acts_worth(run, body.laugh_value * body.value_multiplier(), "his laugh")

## Right-circles on the crank until the jack is out. Returns the turns it had wound.
func _wind_jack(body: JackInTheBox) -> float:
	var box: WeakRef = weakref(body)
	await _crank_zone(body, &"crank", MOUSE_BUTTON_RIGHT, body.max_turns + 1.0, func() -> bool:
		return box.get_ref() == null or box.get_ref().is_out())
	return body.turns_wound() if not _gone(body) else 0.0

# --- what the drivers above need from the rest of the suite ----------------------------------

## The same random draws in both phases. The plain phase spends its first few on the copy the
## bin gesture throws away, so a driver whose item draws when it is made (a jack's tune, a
## fortune, a shot's spread) reseeds before its own.
func _reseed(run: Run) -> void:
	seed(hash(String(run.item.id)) + 1)

## Every kind act this item paid was worth exactly `value`: its base times its own value node.
func _expect_acts_worth(run: Run, value: float, what: String) -> void:
	var ok := not run.acts.is_empty() and run.acts.all(func(v: float) -> bool: return is_equal_approx(v, value))
	run.value_checked = true
	run.value_ok = run.value_ok and ok
	_expect(run, "act_value", ok, "%s is worth exactly %.3f (%s)" % [what, value, run.acts])

## Which currency an item's own use earns: by exact class as `HEARTS_CLASSES` lists, plus
## anything built on `FidgetToy` — D57's kind half, so a new toy is on the right side the day it
## lands — and a `HeldGun` filed on the kind side (D56's water pistol and bubble blaster).
func _pays_hearts(run: Run) -> bool:
	if HEARTS_CLASSES.has(run.cls):
		return true
	if run.cls == &"HeldGun":
		return run.item.is_kind()
	return _lineage(run.item).has(&"FidgetToy")

var _lineages := {}

## Every global class name the item's root script is, from its own up.
func _lineage(item: ItemData) -> Array:
	if _lineages.has(item.id):
		return _lineages[item.id]
	var out: Array = []
	if item.scene:
		var node := item.scene.instantiate()
		var script := node.get_script() as Script
		while script:
			out.append(script.get_global_name())
			script = script.get_base_script()
		node.free()
	_lineages[item.id] = out
	return out

## The multiplier a hit from this item should carry: its contact multiplier through its damage
## node — or, for a held gun's shot, `shot_mult` through the same node. A shot is known by its
## impulse, which is exactly the gun's `shot_force` (D56: a gun swung into him is a lump of
## metal, and a gunshot is not).
func _hit_multiplier(run: Run, info: HitInfo) -> float:
	var base := float(run.authored.get("damage_mult", 1.0))
	if run.authored.has("shot_force") and is_equal_approx(info.raw_impulse, float(run.authored["shot_force"])):
		base = float(run.authored["shot_mult"])
	return Progression.damage_mult_for(run.item.id, base)

## Measurements a driver takes for a key the suite's own switches cannot see: run -> key ->
## number, compared across the two phases by `_gauge_verdict`. Keyed by the run itself, so
## nothing else about a run has to know it exists. The recoil node is the first.
var _gauges := {}

func _gauge(run: Run, key: StringName, value: float) -> void:
	if not _gauges.has(run):
		_gauges[run] = {}
	(_gauges[run] as Dictionary)[key] = value

## A driver-measured key: moved at least two percent the way the node promises, or a placebo.
func _gauge_verdict(plain: Run, upgraded: Run, key: StringName, promised: float) -> String:
	var a = (_gauges.get(plain, {}) as Dictionary).get(key)
	var b = (_gauges.get(upgraded, {}) as Dictionary).get(key)
	if a == null or b == null:
		return "unknown key"
	if float(a) <= 0.0:
		return "unmeasured"
	var ratio := float(b) / float(a)
	var moved := ratio < 1.0 - 0.02 if promised < 1.0 else ratio > 1.0 + 0.02
	if moved:
		return "x%.2f (%.2f to %.2f)" % [ratio, float(a), float(b)]
	return "placebo: %.2f stayed %.2f" % [float(a), float(b)]

# --- drivers: the second five fidget toys (D66) -----------------------------------------
#
# Each is worked the way its `controls` line says, with the real buttons at the real zones.
# Where the thing a node changes is not a gap in time — a stretch, a wind, the swing a clack
# keeps — `run.cooldown` carries that number instead, so `_cooldown_verdict` still asks whether
# "time between uses" moved it.

## Picked up, planted with right, stretched, let go: one boing, one act, worth the stretch.
func _drive_slinky(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-240.0, -40.0)) as Slinky
	if body == null:
		return
	await _await_still(body, 90)
	if not await _grab(run, body):
		return
	await _mouse_to(_mouse + Vector2(0.0, -40.0), 400.0)
	await _steady(body, 40)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_expect(run, "plants", body.stretching() and body.freeze, "right while holding it plants that end")
	await _mouse_to(_mouse + Vector2(70.0, -150.0), 900.0)
	var share := clampf(body.stretch() / body._full_stretch(), 0.0, 1.0)
	var value := body.boing_value * (0.25 + 0.75 * share) * Progression.get_modifier(run.item.id, &"damage_mult")
	run.cooldown = body._full_stretch()
	_release(MOUSE_BUTTON_RIGHT)
	await _step(2)
	_expect(run, "boing", body.boings == 1 and run.acts.size() == 1,
		"let go, it boings and pays one act (%d acts, stretched %.0f px)" % [run.acts.size(), share * body._full_stretch()])
	_expect_values(run, [value])
	await _await(func() -> bool: return _gone(body) or body.is_compact(), 120)
	_expect(run, "home", not _gone(body) and body.is_compact(), "and springs back into the hand, a stack again")
	_release_all()
	_expect(run, "contract", run.contract("kindness") == run.acts.size(), "each boing a kind act for the board")

## An end ball pulled out on the right button and let go: it clacks until it stops, each clack
## a trickle, and the whole swing is worth a known geometric series.
func _drive_cradle(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-270.0, -40.0)) as NewtonsCradle
	if body == null:
		return
	await _await_still(body, 90)
	var ball := body.gestures.zone_world(&"ball_l")
	_move(ball)
	await _step()
	_press(MOUSE_BUTTON_RIGHT)
	await _mouse_to(ball + Vector2(-34.0, -16.0), 300.0)
	var pulled := body.ball_angle(0)
	var kept := body._kept()
	_release(MOUSE_BUTTON_RIGHT)
	await _step()
	_expect(run, "swings", body.is_swinging() and pulled > 0.2, "pulled out and let go, it swings (%.0f deg)"
		% rad_to_deg(pulled))
	await _step(60)
	# The rest of the swing fast-forwarded: half a minute of clacks is not a test.
	var guard := 0
	while body.is_swinging() and guard < 2000:
		body._process(0.05)
		guard += 1
	await _step(40)
	_expect(run, "clacks", body.clacks >= 3, "and clacks until it stops (%d clacks)" % body.clacks)
	var series := 0.0
	for n in body.clacks:
		series += pow(kept, float(n))
	var value := body.clack_value * (pulled / NewtonsCradle.MAX_PULL) * series \
		* Progression.get_modifier(run.item.id, &"damage_mult")
	var got := run.sustained + body._banked
	var ok := absf(got - value) <= 0.002 * maxf(1.0, value)
	run.value_checked = true
	run.value_ok = run.value_ok and ok
	_expect(run, "rate", ok, "the clacks pay exactly their series (%.4f paid, the data says %.4f)" % [got, value])
	_expect(run, "not_acts", run.acts.is_empty() and run.contract("kindness") == 0,
		"a clack is a trickle, never an act")
	_expect(run, "use", run.uses() == 1, "the pull is one use (%d)" % run.uses())
	run.cooldown = (1.0 - kept) * 1000.0

## Wound by a right-drag backwards, let go at him: he hops on, and the ride is the act.
func _drive_car(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-300.0, -20.0)) as PullBackCar
	if body == null:
		return
	await _await_still(body, 90)
	_move(body.global_position)
	await _step()
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_expect(run, "winds", body.is_winding(), "a right-press on it starts the wind")
	for i in 18:
		_move(_mouse + Vector2(-10.0, 0.0))
		await _step()
	var charge := body.charge
	run.cooldown = body._full_pull()
	_expect(run, "wound", body.notches() == PullBackCar.NOTCHES, "dragged back, it winds to full (%d notches)"
		% body.notches())
	_release(MOUSE_BUTTON_RIGHT)
	await _await(func() -> bool: return _gone(body) or body.rides > 0, 240)
	_expect(run, "ride", not _gone(body) and body.rides == 1, "let go at him, he hops on for a ride")
	_expect_values(run, [body.ride_value * charge * Progression.get_modifier(run.item.id, &"damage_mult")])
	await _await(func() -> bool: return _gone(body) or not body.is_riding(), 240)
	_expect(run, "ride_ends", not _gone(body) and not body.is_riding() and not body.freeze,
		"and the ride ends with the car a car again")
	_expect(run, "contract", run.contract("kindness") == run.acts.size(), "the ride is a kind act for the board")

## Held up beside him, thrown out on its string, and swung through him by the hand.
func _drive_yoyo(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-260.0, -60.0)) as YoYo
	if not await _grab(run, body):
		return
	await _mouse_to(_centre() + Vector2(-150.0, -150.0), 700.0)
	await _steady(body, 60)
	_press(MOUSE_BUTTON_RIGHT)
	await _step(30)
	_expect(run, "out", body.is_out() and is_equal_approx(body.string_out(), body.string_length),
		"right throws it out to the end of its string")
	for i in 5:
		if not run.hits.is_empty() or _buddy.health.down:
			break
		await _mouse_to(_centre() + Vector2(150.0, -150.0), 1100.0)
		await _mouse_to(_centre() + Vector2(-150.0, -150.0), 1100.0)
	_expect(run, "hits", not run.hits.is_empty(), "swung on its string, it bonks him (%d hits)" % run.hits.size())
	_expect(run, "effect", _fx.reactions.has(run.item.id), "and the world answers each bonk")
	run.cooldown = body._trick_needed() * 1000.0
	_release(MOUSE_BUTTON_RIGHT)
	await _await(func() -> bool: return _gone(body) or not body.is_out(), 90)
	_expect(run, "home", not _gone(body) and not body.is_out() and body.mouse_joint != null,
		"and it climbs back into the hand")
	_release_all()

## Held at his height, drawn straight back from him to the full draw, let go.
func _drive_slingshot(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(-260.0, -40.0)) as Slingshot
	if not await _grab(run, body):
		return
	await _mouse_to(Vector2(_centre().x - 250.0, _centre().y), 600.0)
	await _steady(body, 60)
	_press(MOUSE_BUTTON_RIGHT)
	await _step()
	_expect(run, "drawn", body.is_drawn(), "right while holding it plants it and draws it")
	var fork := body.fork_position()
	await _mouse_to(fork + (fork - _centre()).normalized() * body.max_draw, 400.0)
	_expect(run, "aimed", body.is_threatening(), "drawn at him, he knows it")
	run.cooldown = body._reload() * 1000.0
	_release(MOUSE_BUTTON_RIGHT)
	await _await(func() -> bool: return not run.hits.is_empty(), 90)
	_expect(run, "hits", run.hits.size() == 1, "the pellet hits him, once (%d hits)" % run.hits.size())
	_expect(run, "effect", _fx.reactions.has(run.item.id), "and the world answers the hit")
	_release_all()

## Every kind act the toy paid, against the values its own numbers say it should have.
func _expect_values(run: Run, values: Array) -> void:
	var got: Array = run.acts.duplicate()
	var ok := got.size() == values.size()
	for i in mini(got.size(), values.size()):
		ok = ok and is_equal_approx(float(got[i]), float(values[i]))
	run.value_checked = true
	run.value_ok = run.value_ok and ok
	_expect(run, "act_value", ok, "worth exactly what its numbers say (%s, the data says %s)" % [got, values])

# --- what every item owes -----------------------------------------------------------------

## Shift+right-click bins anything the spawner put down, whatever else right-click means to it
## (D24). Asked with the real gesture, at the real grab region.
func _the_bin_gesture_works(run: Run) -> void:
	var body := await _spawn(run, _centre() + Vector2(260.0, -160.0))
	if body == null:
		return
	var mine := body.right_click_is_mine()
	_expect(run, "bin_rule", body.click_would_bin(true) and body.click_would_bin(false) == not mine,
		"Shift+right-click would bin it, and plain right-click %s" % ("is its own" if mine else "would too"))
	_move(_grab_point(body))
	await _step(2)
	_press(MOUSE_BUTTON_RIGHT, true)
	_release(MOUSE_BUTTON_RIGHT, true)
	await _step(2)
	_expect(run, "bins", _gone(body) and _spawner.item_count() == 0,
		"and the gesture takes it off the desk")
	run.body = null
	run.mass = -1.0
	await _step(2)
	# What the binned one did in its few frames — a trickle flushed on its way out — is not
	# what is being measured next.
	run.bones = 0.0
	run.hearts = 0.0
	run.sustained = 0.0
	run.sustained_events = 0
	run.acts.clear()
	run.hits.clear()
	run.contracts.clear()
	run.touch_seconds = 0.0

func _expect_aura(run: Run, body: BaseDraggable) -> void:
	if not run.upgraded:
		return
	var aura := body.get_node_or_null("Aura") as GPUParticles2D
	_expect(run, "aura", body.juice_tier >= 3 and aura != null and aura.emitting,
		"ranked to 50 it wears its tier (%d) and an aura" % body.juice_tier)

func _judge(run: Run) -> void:
	var hearts_side := _pays_hearts(run)
	var mine := run.hearts if hearts_side else run.bones
	var other := run.bones if hearts_side else run.hearts
	var missed := UNAIMED.has(run.cls) and run.hits.is_empty()
	if missed:
		run.notes.append("%s: unaimed, and missed" % run.label())
	else:
		_expect(run, "earns", mine > 0.0, "it earns %s under its own name (%.2f)"
			% ["Hearts" if hearts_side else "Bones", mine])
	_expect(run, "currency", other == 0.0, "and none of the other currency (%.2f)" % other)
	_expect(run, "pipeline", run.pipeline_bad.is_empty(), "every payout is the pipeline's own number%s"
		% ("" if run.pipeline_bad.is_empty() else ": " + run.pipeline_bad[0]))
	_expect(run, "damage_mult", run.damage_bad.is_empty(), "every hit carries its damage multiplier%s"
		% ("" if run.damage_bad.is_empty() else ": " + run.damage_bad[0]))
	run.xp = Progression.mastery_xp(run.item.id)
	_expect(run, "mastery", missed or run.xp > (EconomyMath.mastery_xp_for_rank(
			ItemDB.balance.mastery_base, ItemDB.balance.mastery_bonus_rank, ItemDB.balance.mastery_exponent)
			if run.upgraded else 0.0),
		"using it earns it mastery")
	_expect(run, "in_world", run.escaped == "", "it and he stay in the world%s" % ("" if run.escaped == "" else ": " + run.escaped))
	_expect(run, "speed", run.peak_him < SPEED_CEILING and run.peak_it < SPEED_CEILING,
		"nothing goes faster than a wall can hold (him %.0f, it %.0f px/s)" % [run.peak_him, run.peak_it])

## Gone the way a player sends it — the gesture, or the holster — and nothing of it left.
func _teardown(run: Run, baseline: Dictionary) -> void:
	_release_all()
	await _holster(run)
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
		if not _gone(node) and node.has_method("bin_myself"):
			node.bin_myself()
	var settled := await _await(func() -> bool: return _new_nodes(baseline).is_empty(), 180)
	if not settled:
		run.leaks = _new_nodes(baseline)
	_expect(run, "teardown", run.leaks.is_empty(), "and once it is gone, nothing of it is left%s"
		% ("" if run.leaks.is_empty() else ": " + ", ".join(run.leaks.slice(0, 4))))

## Every node under the stage and every explosion parented to the scene root, by instance id.
## The effects pool and an equipped power are furniture: they exist for the life of the stage.
func _node_ids() -> Dictionary:
	var ids := {}
	_collect(_stage, ids)
	for child in get_children():
		if child != _view:
			_collect(child, ids)
	return ids

func _collect(node: Node, into: Dictionary) -> void:
	if node == _fx or node is CursorPowerBase:
		return
	into[node.get_instance_id()] = node
	for child in node.get_children():
		_collect(child, into)

func _new_nodes(baseline: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var now := _node_ids()
	for id in now:
		if baseline.has(id):
			continue
		var node: Node = now[id]
		# His own furniture, built the first time it is needed and kept for his life: a trail the
		# first time he moves fast (D39), and the embers of a streak and the sparkle of bliss that
		# the world's effects hang on him (D40). He is never binned, so these are not leaks.
		if node.get_parent() == _buddy and String(node.name) in ["Trail", "Embers", "Bliss"]:
			continue
		if node.is_queued_for_deletion():
			continue
		out.append(String(node.get_path()).trim_prefix(String(get_path())))
	return out

# --- augments -----------------------------------------------------------------------------

## What each key the player can buy for this item actually changed, from the two runs.
func _judge_augments(plain: Run, upgraded: Run) -> Dictionary:
	var out := {}
	for key in upgraded.aug:
		var node := ItemDB.get_augment(upgraded.aug[key])
		var promised := node.effect_per_level
		var verdict := ""
		match key:
			&"payout_mult":
				var paid := upgraded.bones + upgraded.hearts
				verdict = "x%.2f" % promised if paid > 0.0 and upgraded.pipeline_bad.is_empty() \
					else "placebo: nothing is ever paid under this item's id"
				if paid <= 0.0 and UNAIMED.has(upgraded.cls):
					verdict = "unmeasured: unaimed, and it missed"
			&"damage_mult":
				verdict = _damage_verdict(upgraded, promised)
			&"mass_mult":
				var want := float(upgraded.authored.get("mass", 1.0)) * promised
				if upgraded.mass <= 0.0:
					verdict = "unmeasured"
				elif absf(upgraded.mass - want) <= want * 0.001:
					verdict = "x%.2f" % (upgraded.mass / float(upgraded.authored.get("mass", 1.0)))
				else:
					verdict = "placebo: mass %.2f, the data says %.2f" % [upgraded.mass, want]
			&"cooldown_mult":
				verdict = _cooldown_verdict(plain, upgraded, promised)
			# D65's four. A field is read off a probe's first step in it, the fist off its top
			# chase speed, a treat off the mood each helping left him at.
			&"pull_mult", &"wind_mult":
				verdict = _ratio_verdict(plain.field, upgraded.field, promised, "px/s² on a free body")
			&"speed_mult":
				verdict = _ratio_verdict(plain.speed, upgraded.speed, promised, "px/s chasing")
			&"mood_mult":
				if not upgraded.mood_checked:
					verdict = "unmeasured"
				elif upgraded.mood_ok:
					verdict = "x%.2f on his mood" % promised
				else:
					verdict = "placebo: his mood went " + upgraded.mood_bad
			_:
				verdict = _gauge_verdict(plain, upgraded, key, promised)
		out[key] = verdict
		_expect(upgraded, "aug_%s" % key, not verdict.begins_with("placebo")
				and not verdict.begins_with("wrong") and verdict != "unknown key",
			"%s (%s x%.2f) is read by something: %s" % [node.display_name, key, promised, verdict])
	return out

## A measured number in both runs, and whether it moved by what the node promises.
func _ratio_verdict(plain: float, upgraded: float, promised: float, unit: String) -> String:
	if plain <= 0.0 or upgraded <= 0.0:
		return "unmeasured"
	var ratio := upgraded / plain
	if absf(ratio - promised) <= TOLERANCE * promised:
		return "x%.2f (%.0f to %.0f %s)" % [ratio, plain, upgraded, unit]
	if absf(ratio - 1.0) <= 0.005:
		return "placebo: it stayed at %.0f %s" % [plain, unit]
	return "wrong: x%.3f where the data says x%.2f (%.0f to %.0f %s)" % [ratio, promised, plain,
		upgraded, unit]

func _damage_verdict(run: Run, promised: float) -> String:
	if _pays_hearts(run):
		# The kindness value: every act and every trickle is scaled by it, or it is decoration.
		if not run.value_checked:
			return "unmeasured"
		return "x%.2f on kindness" % promised if run.value_ok else "placebo: the kindness value ignores it"
	if run.measured_damage > 0:
		return "x%.2f" % promised if run.damage_bad.is_empty() else "placebo: " + run.damage_bad[0]
	if run.hits.is_empty() and UNAIMED.has(run.cls):
		return "unmeasured: unaimed, and it missed"
	if run.hits.is_empty():
		return "placebo: it never deals damage under its own name"
	return "unmeasured: every hit was at the per-hit cap"

func _cooldown_verdict(plain: Run, upgraded: Run, promised: float) -> String:
	if bool(upgraded.authored.get("consume_on_use", false)):
		return "placebo: it is used up on its first pay, so the gap it shortens never runs"
	if plain.cooldown < 0.0 or upgraded.cooldown < 0.0:
		return "unmeasured"
	if plain.cooldown <= 1.0 and upgraded.cooldown <= 1.0:
		return "placebo: there is no gap for it to shorten (%.0f)" % plain.cooldown
	# A turret's gap is counted in physics frames. When the promised change is under a frame
	# and a half, 60 Hz cannot see it either way, and saying "placebo" would be a lie.
	var interval := float(upgraded.authored.get("fire_interval", 0.0))
	if interval > 0.0 and interval * (1.0 - promised) * 60.0 < 1.5:
		return "unmeasured: %.0f%% of a %.2fs gap is under a frame" % [(1.0 - promised) * 100.0, interval]
	var ratio := upgraded.cooldown / plain.cooldown
	# Frames and milliseconds are both quantised; a ninety-four percent gap is at least a frame
	# shorter than a full one, which is all this can honestly say for the shortest clocks.
	if ratio < 1.0 - 0.02:
		return "x%.2f (%.0f to %.0f)" % [ratio, plain.cooldown, upgraded.cooldown]
	return "placebo: the gap stayed at %.0f (%.0f)" % [plain.cooldown, upgraded.cooldown]

# --- bookkeeping --------------------------------------------------------------------------

func _expect(run: Run, key: String, ok: bool, what: String) -> void:
	# Keyed "item/check", or "item/check@plain" for one phase only. A reason that starts with
	# "~" is a finding that depends on a random spread: it is reported when it shows and not
	# failed when it does not.
	var known_key := "%s/%s@%s" % [run.item.id, key, run.label()]
	if not KNOWN.has(known_key):
		known_key = "%s/%s" % [run.item.id, key]
	var line := "[%s] %s" % [run.label(), what]
	if KNOWN.has(known_key) and ok and String(KNOWN[known_key]).begins_with("~"):
		_passed += 1
		print("    ok   %s" % line)
		return
	if KNOWN.has(known_key):
		if ok:
			_failed += 1
			run.failures.append("%s no longer reproduces — delete it from KNOWN" % known_key)
			print("    FAIL %s — the known finding %s no longer reproduces" % [line, known_key])
		else:
			_known += 1
			if not run.known.has(key):
				run.known.append(key)
			print("    known %s — %s" % [line, KNOWN[known_key]])
		return
	if ok:
		_passed += 1
		print("    ok   %s" % line)
	else:
		_failed += 1
		run.failures.append(what)
		print("    FAIL %s" % line)

func _write_report(seconds: float) -> void:
	var lines: PackedStringArray = []
	lines.append("# Item check — %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("")
	lines.append("%d items in %.0f s. passed %d, failed %d, known %d." % [_rows.size(), seconds,
		_passed, _failed, _known])
	lines.append("")
	lines.append("| id | class | category | verdict | hits | earned | use: | mastery XP | peak him / it px/s | augments | notes |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for row in _rows:
		var plain := row["plain"] as Run
		var augments := row["augments"] as Dictionary
		var aug_text := PackedStringArray()
		for key in augments:
			aug_text.append("%s %s" % [String(key).trim_suffix("_mult"), augments[key]])
		if plain == null:
			lines.append("| %s | %s | %s | %s | | | | | | | |" % [row["id"], row["class"], row["category"], row["verdict"]])
			continue
		var upgraded := row["upgraded"] as Run
		var notes := plain.notes.duplicate()
		notes.append_array(upgraded.notes)
		lines.append("| %s | %s | %s | %s | %d | %s | %d | %s | %.0f / %.0f | %s | %s |" % [
			row["id"], row["class"], row["category"], String(row["verdict"]).replace("|", "/"),
			plain.hits.size(),
			("%.1f H" % plain.hearts) if plain.hearts > 0.0 else ("%.1f B" % plain.bones),
			plain.uses(),
			"%.0f" % plain.xp,
			maxf(plain.peak_him, upgraded.peak_him), maxf(plain.peak_it, upgraded.peak_it),
			"; ".join(aug_text).replace("|", "/"), ", ".join(notes).replace("|", "/")])
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines) + "\n")
		file.close()
