extends Node

## Thin bootstrapper. Loads the save, applies offline earnings, builds the UI layers and
## wires them to the world — then gets out of the way.
##
## There is no main-menu scene: the game boots straight to the buddy (docs/decisions.md
## D6). The shell is the HUD dock plus the panel suite, on CanvasLayers inside the one
## transparent window.

@export var world: Node2D
@export var buddy: Buddy
@export var spawner: ItemSpawner

var _hud: HUD
var _panels: PanelLayer
var _esc: EscMenu
var _fx: FXLayer
var _grip: WindowGrip

func _ready() -> void:
	# Load before building UI: the shop reads what the player owns, and Progression grants
	# the free starters as part of from_save.
	# A measurement build stages its own desk on its own slot (docs/decisions.md D42). Before
	# the load, because the load is what reads the slot.
	var perf := _perf_stage_mode()
	if perf != "":
		# Read the player's settings (the window, the menu size and the frame caps are what is
		# being measured) but write nowhere they live: a hint shown on the staged desk marks
		# itself seen and saves, and the first staging of a toy used to write the player's file.
		Settings.config_path = PERF_SETTINGS
		SaveManager.slot_name = "perf"
		for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	var save := SaveManager.load_game()
	var offline := Economy.apply_offline_earnings(int(save.get("last_played_unix", 0)))

	spawner.world = world
	spawner.add_to_group(&"item_spawner")

	_build_backdrop()
	_build_ui()
	_build_devices()
	_build_world_fx()
	# What he does when nobody is watching: finds a toy he likes and uses it. Installed
	# rather than exported because he resolves the buddy lazily on his first think tick —
	# the buddy joins his group in his own _ready(), which has not run yet here.
	IdleBrain.install(self)
	_install_tuning_log()

	# A tree purchase has to reach weapons already lying on the desktop, or the upgrade
	# the player just bought does nothing until they bin the bat and spawn a new one.
	EventBus.augment_purchased.connect(func(_id: StringName, _l: int) -> void:
		spawner.refresh_augments())

	_report_offline(offline)
	_onboard()
	if perf != "":
		get_tree().create_timer(1.5).timeout.connect(_perf_stage.bind(perf))

	# The things that happen *to* the player rather than because of them. Progression is
	# invisible otherwise: mastery ticks up inside a panel nobody has open.
	EventBus.mastery_rank_up.connect(func(item_id: StringName, rank: int) -> void:
		var item := ItemDB.get_item(item_id)
		_hud.celebrate_toast("%s reached mastery %d" % [item.display_name if item else item_id, rank], UIStyle.BONES, 4.0))
	EventBus.contract_completed.connect(func(contract_id: StringName) -> void:
		var contract := ItemDB.get_contract(contract_id)
		if contract:
			_hud.celebrate_toast("Contract ready to claim: %s" % contract.display_name, UIStyle.DOLLARS, 8.0))
	EventBus.prestige_performed.connect(func(gained: float) -> void:
		_hud.celebrate_toast("Reincarnated. +%.2f marrow, and he is somebody new." % gained, UIStyle.DOLLARS, 8.0))
	# The round, as a score: what it took, how long, what it paid, and the best to beat. The
	# knockout was the harm loop's climax and it ended with a fountain and no number to chase.
	EventBus.knockout_payout.connect(func(_bonus: float) -> void:
		var r := Economy.last_round
		if r.is_empty():
			return
		var when := "" if float(r["seconds"]) <= 0.0 else " in %s" % _round_time(float(r["seconds"]))
		var against := "  ·  new best!" if bool(r["record"]) else "  ·  best %s" % UIStyle.format_amount(float(r["best_before"]))
		var line := "Round %d: %s damage%s for %s Bones%s" % [int(r["number"]),
			UIStyle.format_amount(float(r["damage"])), when,
			UIStyle.format_amount(float(r["bones"])), against]
		if bool(r["record"]):
			_hud.celebrate_toast(line, UIStyle.BONES)
		else:
			_hud.show_toast(line, 7.0))
	# Milestones claim themselves (docs/decisions.md D34) — a board of forty unclaimed
	# collect buttons is homework, so the toast IS the reward moment and there is nowhere
	# else the player finds out. A rung count is printed when several land at once, which
	# happens whenever one payout carries a tenfold ladder past two rungs.
	Milestones.milestone_claimed.connect(func(id: StringName, rungs: int, dollars: int) -> void:
		var milestone := ItemDB.get_milestone(id)
		var name_text: String = milestone.display_name if milestone else String(id)
		var suffix := "" if rungs <= 1 else " x%d" % rungs
		_hud.show_toast("%s%s  ·  $%s" % [name_text, suffix,
			UIStyle.format_amount(float(dollars))], 6.0))

## "You earned this while you were away" — shown once, after the UI exists to show it in.
## Silent when nothing accrued, which is every session until the first automation capstone:
## a popup that says "you earned 0" teaches the player to dismiss popups.
## The Dream Journal (docs/game-design.md § Offline earnings): what he earned while you were
## gone, what he dreamt about, and a small waking buff — so the "collect your offline money"
## screen is the day's first joke rather than a receipt. One toast, one sound, one beat: the
## reunion is the genre's whole point and this game used to mark it with six silent seconds.
const DREAMS_PATH := "res://Data/dreams.txt"
const DREAM_BOOST_ID := &"dream"

func _report_offline(offline: Dictionary) -> void:
	var bones := float(offline.get(Economy.BONES, 0.0))
	var hearts := float(offline.get(Economy.HEARTS, 0.0))
	if bones <= 0.0 and hearts <= 0.0:
		return
	var parts: Array[String] = []
	if bones > 0.0:
		parts.append("%s Bones" % UIStyle.format_amount(bones))
	if hearts > 0.0:
		parts.append("%s Hearts" % UIStyle.format_amount(hearts))
	# Automation's Dollar trickle, at the offline fraction (D31). Printed like every other Dollar
	# figure on the shell, and only once it rounds to one: "$0" is a receipt, not a line.
	var dollars := float(offline.get(Economy.DOLLARS, 0.0))
	if dollars >= 0.5:
		parts.append("$%s" % UIStyle.format_amount(dollars))
	var hours := float(offline.get("seconds", 0.0)) / 3600.0
	var lines: Array[String] = ["While you were out (%.1f h): %s." % [hours, ", ".join(parts)]]
	# The sting, said once, where the money is: a hit cap is what drives the next session, and
	# a cap the player never learns about is a cap that reads as a bug (assessment §4).
	if bool(offline.get("capped", false)):
		lines.append("That is as long as he sleeps for now — he can learn to sleep longer, on the Reincarnation page.")
	var dream := _dream_line()
	if dream != "":
		lines.append(dream)
	var b := ItemDB.balance
	if b.dream_boost_multiplier > 1.0 and b.dream_boost_minutes > 0.0:
		Economy.add_temp_multiplier(DREAM_BOOST_ID, b.dream_boost_multiplier, b.dream_boost_minutes * 60.0)
		lines.append("He woke up refreshed: x%.2f to everything for %d minutes." % [
			b.dream_boost_multiplier, int(round(b.dream_boost_minutes))])
	_hud.celebrate_toast(" ".join(lines), UIStyle.BONES if bones >= hearts else UIStyle.HEARTS, 14.0)
	AudioManager.play(&"welcome", 0.0, -4.0)
	# The coins themselves, once the window is up and he is standing somewhere. A second is
	# long enough for the first layout and the rescue that puts him on the floor.
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(_fx):
			_fx.welcome_shower(bones, hearts))

## "48 s" or "2 m 05 s": a round is a short thing and reads as one.
func _round_time(seconds: float) -> String:
	if seconds < 60.0:
		return "%d s" % int(round(seconds))
	return "%d m %02d s" % [int(seconds) / 60, int(seconds) % 60]

## One absurd line from `Data/dreams.txt`. Data, not code: adding a dream is adding a line.
func _dream_line() -> String:
	if not FileAccess.file_exists(DREAMS_PATH):
		return ""
	var text := FileAccess.get_file_as_string(DREAMS_PATH)
	var lines: Array[String] = []
	for line in text.split("\n"):
		if line.strip_edges() != "":
			lines.append(line.strip_edges())
	if lines.is_empty():
		return ""
	return lines[randi() % lines.size()]

## The first three minutes, for someone who has never seen it. Kept deliberately basic
## (the owner's brief): both drawers pinned open so the shell is *there*, the bat on the desk
## beside him so there is something to pick up, and two toasts — one now, one on the first
## Bones. No tutorial system, no modal, no arrows. Remembered in `Settings.hints_seen`, so
## it survives the Reincarnation that wipes the save and never plays twice on one machine.
const HINT_WELCOME := &"welcome"
const HINT_FIRST_BONES := &"first_bones"

func _onboard() -> void:
	if Settings.hint_seen(HINT_WELCOME):
		return
	Settings.mark_hint_seen(HINT_WELCOME)
	_hud.pin_drawer(true)
	_panels.pin_drawer(true)
	if buddy:
		# Beside him, a little above the floor, on the side away from the HUD.
		EventBus.spawn_requested.emit(&"baseball_bat", buddy.global_position + Vector2(90, -30))
	_hud.show_toast("This is Bonehead. Pick up the bat and hit him — he pays in Bones. "
		+ "Hold the button on him to pet him instead; that pays in Hearts.", 14.0)
	# The second beat waits for the first payout, whichever kind it is: that is the moment
	# the player has money and no idea where it goes.
	EventBus.payout.connect(_on_first_payout)

func _on_first_payout(_currency: StringName, _amount: float, _pos: Vector2, _source_id: StringName) -> void:
	if Settings.hint_seen(HINT_FIRST_BONES):
		return
	Settings.mark_hint_seen(HINT_FIRST_BONES)
	EventBus.payout.disconnect(_on_first_payout)
	_hud.show_toast("Toys, top right, is where that goes. The row under his meters shows "
		+ "the next thing you can afford — click it.", 12.0)

func _build_ui() -> void:
	# Named, not left as `@CanvasLayer@24`. These are built in code rather than authored in
	# the scene, and a node with a generated name cannot be found by a test or read in the
	# remote scene tree.
	_fx = FXLayer.new()
	_fx.name = "FXLayer"
	add_child(_fx)

	_panels = PanelLayer.new()
	_panels.name = "PanelLayer"
	add_child(_panels)

	_hud = HUD.new()
	_hud.name = "HUD"
	add_child(_hud)
	if buddy and buddy.health:
		_hud.bind_health(buddy.health)
	_hud.bind_spawner(spawner)

	# The only place the window can be picked up (D52). Inside main.tscn rather than parented
	# to the OverlayManager autoload the way DebugOverlay is: `ui_check` walks the main
	# scene, and a shell control living outside it is invisible to every sweep in the suite.
	_grip = WindowGrip.new()
	_grip.name = "WindowGrip"
	add_child(_grip)

	_esc = EscMenu.new()
	_esc.name = "EscMenu"
	_esc.world = world
	add_child(_esc)

	# A note from whoever is playing, from anywhere: F1, Settings or the Esc menu (the
	# playtest kit, docs/playtest-plan.md). In main.tscn for the same reason as the grip.
	var feedback := FeedbackCard.new()
	feedback.name = "FeedbackCard"
	add_child(feedback)

## What is behind him when it is not the desktop (D38): a layer under the world, painting one
## of a fixed menu of flat colours and drawn scenes to the window's own rect.
func _build_backdrop() -> void:
	var backdrop := Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)

## Bursts at the point of contact — bone chips off a hit, hearts off a kind act. The
## floating numbers say how much; this says where, which is the half that was missing.
func _build_world_fx() -> void:
	var fx := WorldFX.new()
	fx.name = "WorldFX"
	world.add_child(fx)

## The automation the player has bought, standing on the desk doing it. In the world rather
## than on a CanvasLayer: a device is furniture at world scale, beside the toys it is made
## of, and the shell scales in whole numbers independently of it (D23).
func _build_devices() -> void:
	var devices := DeviceLayer.new()
	devices.name = "DeviceLayer"
	world.add_child(devices)

## Debug builds only. The M3 gate is "a 30-minute session with no dead ends", which is a
## claim about pacing that nobody can check from memory — this writes the CSV that makes it
## checkable (docs/economy.md, tuning workflow). A shipped build writing a row per hit for
## eight hours would be a performance bug.
func _install_tuning_log() -> void:
	if not OS.is_debug_build():
		return
	var log_node := TuningLog.new()
	log_node.name = "TuningLog"
	add_child(log_node)

# --- measuring a built game ---------------------------------------------------------
#
# The performance budget (CLAUDE.md: < 3% CPU idle, < 8% under load) is a claim about an
# *exported* build — editor numbers lie — and an exported build cannot run anything under
# tools/, which the export excludes. So the game itself accepts one developer flag:
#
#   "Bonehead Friend.exe" -- --perf-stage=empty|idle|load|toybox
#
# `empty` is him alone. `idle` adds a hot tub steaming and a rank-25 bat glowing on the desk,
# which is what a player who has been playing for a day leaves running. `load` adds a pellet
# turret firing at him, so every hit, chip, number and payout is live. `toybox` is M3.9's desk
# (D73): a fidget spinner kept spinning, a Newton's cradle kept clacking, bubble wrap popped,
# a boombox's track changed and three kind generators placed — worked by the stage on a timer,
# with no input, so the frame cap is whatever the desk itself asks for. It runs on a save slot
# of its own, wiped before the load, and writes settings only to a file of its own.
# tools/perf_measure.ps1 drives it and reads the process counters.

const PERF_SETTINGS := "user://settings_perf.cfg"

## M3.9's things, where they go relative to him. Seven, so the desk limit (ten) is never what
## decides which of them is measured.
const PERF_TOYBOX := [
	[&"fidget_spinner", Vector2(150.0, -60.0)],
	[&"newtons_cradle", Vector2(290.0, -60.0)],
	[&"bubble_wrap", Vector2(430.0, -40.0)],
	[&"boombox", Vector2(-170.0, -60.0)],
	[&"lava_lamp", Vector2(-300.0, -60.0)],
	[&"houseplant", Vector2(-420.0, -60.0)],
	[&"fish_tank", Vector2(-560.0, -60.0)],
]

var _perf_toys := {}
var _perf_ticks := 0
var _perf_frames_from := 0
var _perf_msec_from := 0
var _perf_seconds := 0
var _perf_at_idle_cap := 0
var _perf_awake_peak := 0

func _perf_stage_mode() -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--perf-stage="):
			return String(arg).trim_prefix("--perf-stage=")
	return ""

func _perf_stage(mode: String) -> void:
	# Effects on, in memory only: the point is to measure them, and the player's own Focus
	# Mode is untouched because `Settings` writes to the stage's own file.
	Settings.focus_intensity = Settings.Intensity.NORMAL
	# Proof the stage is what it says, written from inside the build: the measurement tool
	# cannot see the window, and a turret that never found him would measure as idle.
	get_tree().create_timer(15.0).timeout.connect(_perf_report.bind(mode))
	if mode == "empty":
		return
	Economy.grant(Economy.BONES, 1.0e7)
	Economy.grant(Economy.HEARTS, 1.0e7)
	# Placed around him, not around the window: a turret has a reach, and the first cut put
	# it seven hundred pixels from him on an ultrawide, where it measured as furniture.
	var size := get_viewport().get_visible_rect().size
	var near := buddy.global_position if buddy else Vector2(size.x * 0.5, size.y - 80.0)
	if mode == "toybox":
		_perf_toybox(near, size)
		return
	for id in [&"hot_tub", &"baseball_bat", &"pellet_turret"]:
		_perf_unlock(id)
	var b := ItemDB.balance
	Progression.add_mastery_xp(&"baseball_bat",
		EconomyMath.mastery_xp_for_rank(b.mastery_base, 25, b.mastery_exponent))
	_perf_quiet_hints([&"hot_tub", &"baseball_bat", &"pellet_turret"])
	EventBus.spawn_requested.emit(&"hot_tub", near + Vector2(-260.0, -40.0))
	EventBus.spawn_requested.emit(&"baseball_bat", near + Vector2(120.0, -140.0))
	if mode == "load":
		EventBus.spawn_requested.emit(&"pellet_turret", near + Vector2(200.0, -30.0))

## The one-off tips a staged toy would show are marked seen first, so every run of a stage
## draws the same desk: whether a ten-second toast unrolls should not depend on which toys the
## player at this machine has already been taught.
func _perf_quiet_hints(ids: Array) -> void:
	Settings.mark_hint_seen(&"removal_gestures")
	for id in ids:
		Settings.mark_hint_seen(StringName(HUD.HINT_CONTROLS_PREFIX + String(id)))

func _perf_toybox(near: Vector2, size: Vector2) -> void:
	var ids: Array = []
	for row in PERF_TOYBOX:
		ids.append(row[0])
		_perf_unlock(row[0])
	_perf_quiet_hints(ids)
	var collect := func(node: Node2D) -> void:
		var body := node as BaseDraggable
		if body:
			_perf_toys[body.item_id] = body
	EventBus.item_spawned.connect(collect)
	for row in PERF_TOYBOX:
		var at: Vector2 = near + row[1]
		at.x = clampf(at.x, 60.0, size.x - 60.0)
		EventBus.spawn_requested.emit(row[0], at)
	EventBus.item_spawned.disconnect(collect)
	# A hand on a timer rather than on the mouse: pushed input would pin the active frame cap
	# for the whole run (`OverlayManager._input`), and this stage is the desk left going.
	var hand := Timer.new()
	hand.name = "PerfHand"
	hand.wait_time = 1.0
	hand.timeout.connect(_perf_fidget)
	add_child(hand)
	hand.start()

## Keeps the toys going the way a player idly would: the spinner flicked when it stops, the
## cradle pulled when it settles, a bubble a second, the next track every six.
func _perf_fidget() -> void:
	_perf_ticks += 1
	var spinner := _perf_toys.get(&"fidget_spinner") as FidgetSpinner
	if is_instance_valid(spinner) and not spinner.is_spinning():
		spinner.launch(spinner.max_spin, true)
	var cradle := _perf_toys.get(&"newtons_cradle") as NewtonsCradle
	if is_instance_valid(cradle) and not cradle.is_swinging():
		cradle.release(-1, deg_to_rad(45.0), true)
	var wrap := _perf_toys.get(&"bubble_wrap") as BubbleWrap
	if is_instance_valid(wrap):
		for slot in wrap.bubble_count():
			if wrap.pop(slot, true):
				break
	var box := _perf_toys.get(&"boombox") as BaseDraggable
	if is_instance_valid(box) and box.gesture_zones and _perf_ticks % 6 == 0:
		# The tap its deck button would have made; ItemVerbs cannot tell it from a click.
		var tap := GestureZones.Gesture.new()
		tap.kind = GestureZones.TAP
		tap.zone = &"deck"
		tap.button = MOUSE_BUTTON_RIGHT
		tap.world = box.gesture_zones.zone_world(&"deck")
		box.gesture_zones.gesture.emit(tap)

## Buys an item and, first, everything it requires — the public path the shop takes, walked
## up the chain, so the stage cannot produce a save the real game could not.
func _perf_unlock(id: StringName) -> void:
	if Progression.is_unlocked(id):
		return
	var item := ItemDB.get_item(id)
	if item == null:
		return
	for req in item.requires:
		_perf_unlock(req)
	Progression.purchase_item(id)

## Written at fifteen seconds and rewritten every five after, so whenever the measurement tool
## reads it, it says what the frame loop did over the window being measured: the frame rate,
## how long it sat at the idle cap, and the most bodies awake at once. A process counter says
## how much; this says why — a desk that never goes to sleep holds the active cap and costs
## twice as much, and from outside that looks exactly like a regression.
func _perf_report(mode: String) -> void:
	if _perf_seconds == 0:
		_perf_frames_from = Engine.get_frames_drawn()
		_perf_msec_from = Time.get_ticks_msec()
		var sampler := Timer.new()
		sampler.name = "PerfSampler"
		sampler.wait_time = 1.0
		sampler.timeout.connect(_perf_sample.bind(mode))
		add_child(sampler)
		sampler.start()
	var file := FileAccess.open("user://perf_%s.txt" % mode, FileAccess.WRITE)
	if file == null:
		return
	file.store_line("mode %s" % mode)
	file.store_line("items %d" % spawner.item_count())
	file.store_line("hits %d" % int(Economy.session.get("hits", 0)))
	file.store_line("bones %.1f" % float(Economy.session.get("bones", 0.0)))
	file.store_line("hearts %.1f" % float(Economy.session.get("hearts", 0.0)))
	file.store_line("bat_tier %d" % Progression.juice_tier(&"baseball_bat"))
	file.store_line("window %s" % str(get_viewport().get_visible_rect().size))
	if _perf_seconds > 0:
		var seconds := maxf(0.001, (Time.get_ticks_msec() - _perf_msec_from) / 1000.0)
		file.store_line("fps %.1f over the last %d s" % [
			(Engine.get_frames_drawn() - _perf_frames_from) / seconds, _perf_seconds])
		file.store_line("idle_cap %d of %d s at %d fps" % [
			_perf_at_idle_cap, _perf_seconds, Settings.fps_idle])
		file.store_line("awake_peak %d" % _perf_awake_peak)

func _perf_sample(mode: String) -> void:
	_perf_seconds += 1
	if Engine.max_fps == Settings.fps_idle:
		_perf_at_idle_cap += 1
	_perf_awake_peak = maxi(_perf_awake_peak,
		int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)))
	if _perf_seconds % 5 == 0:
		_perf_report(mode)
