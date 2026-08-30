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
	_hud.show_toast("While you were out (%.1f h): %s" % [hours, ", ".join(parts)])

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
