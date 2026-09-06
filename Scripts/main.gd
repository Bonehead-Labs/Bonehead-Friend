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

func _ready() -> void:
	# Load before building UI: the shop reads what the player owns, and Progression grants
	# the free starters as part of from_save.
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

	# The things that happen *to* the player rather than because of them. Progression is
	# invisible otherwise: mastery ticks up inside a panel nobody has open.
	EventBus.mastery_rank_up.connect(func(item_id: StringName, rank: int) -> void:
		var item := ItemDB.get_item(item_id)
		_hud.show_toast("%s reached mastery %d" % [item.display_name if item else item_id, rank], 4.0))
	EventBus.contract_completed.connect(func(contract_id: StringName) -> void:
		var contract := ItemDB.get_contract(contract_id)
		if contract:
			_hud.show_toast("Contract ready to claim: %s" % contract.display_name, 8.0))
	EventBus.prestige_performed.connect(func(gained: float) -> void:
		_hud.show_toast("Reincarnated. +%.2f marrow, and he is somebody new." % gained, 8.0))
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
	_hud.show_toast(" ".join(lines), 14.0)
	AudioManager.play(&"welcome", 0.0, -4.0)

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

	_esc = EscMenu.new()
	_esc.name = "EscMenu"
	_esc.world = world
	add_child(_esc)

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
