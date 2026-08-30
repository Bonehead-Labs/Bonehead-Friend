extends Node

## A playable sandbox: the real game, with everything unlocked and more money than it can
## spend, on **its own save slot**.
##
##   Godot --path <project> res://tools/sandbox.tscn              (fresh every run)
##   Godot --path <project> res://tools/sandbox.tscn -- --keep    (continue the last one)
##
## NOT --headless: this one is for playing.
##
## It exists because eighty items, fourteen explosives, eight turrets, four NPCs, three
## arcade machines and a twenty-four node global tree cannot be validated by reading a diff.
##
## **It never touches `slot_1`.** `SaveManager.slot_name` is switched before `main.tscn` is
## instantiated — main loads the save in its own `_ready()`, so the swap has to happen
## first — and every autosave the session makes from then on lands in the sandbox slot. The
## capture tools learned this the hard way: the first version of `ui_shots` left staged test
## state in the developer's real save.
##
## Settings are deliberately untouched. Window mode, play area, Focus Mode and menu size are
## machine-local preferences, and a tool that quietly rewrites them is the bug that made
## every screenshot come out at 2x for a week.

const SANDBOX_SLOT := "sandbox"

## Enough to buy the whole catalogue several times over without being so large that the
## purse abbreviates everything into scientific notation and stops being readable.
const BONES := 5.0e9
const HEARTS := 5.0e9
const DOLLARS := 2.0e7

## Every item mastered past the automation gate (25) and the branch gate (10), but short of
## the rank-50 payout bonus — so there is still something on the mastery bar to move, and
## the three unlock marks on the tree page show two ticks and one padlock rather than a row
## of ticks that says nothing.
const MASTERY_RANK := 30

## Levels bought of each ordinary upgrade node. Three is enough that the pips read as
## partly-filled rather than empty or maxed, which is the state that actually exercises the
## card: a maxed node draws "MAX" and never shows a price again.
const AUGMENT_LEVELS := 3

## Devices left running on the desk. Eighty of them is six rows of furniture and no game.
const DEVICES_RUNNING := 8

## Reincarnations on the clock. Three opens every `requires_prestige` gate in the global
## tree — the rows that a first run cannot reach and that would otherwise be invisible.
const PRESTIGES := 3
const MARROW := 2.5

var _main: Node

func _ready() -> void:
	# Before main.tscn exists, because main loads the save in its own _ready().
	SaveManager.slot_name = SANDBOX_SLOT
	# `--keep` continues the last sandbox and stages **nothing**: staging again on top of a
	# staged save grants a second fortune and buys a second level of everything, so three
	# runs left fifteen billion Bones and a purse that no longer said anything useful.
	var keep := OS.get_cmdline_user_args().has("--keep")
	if not keep:
		_clear_slot()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	# Two frames: one for main's _ready to load the save and build the UI, one for the
	# buddy and the spawner to finish their own. Staging into a half-built tree is how a
	# tool ends up asserting against nodes that do not exist yet.
	await get_tree().process_frame
	await get_tree().process_frame
	if keep:
		print("")
		print("Bonehead Friend — sandbox (continued; nothing re-staged)")
		print("")
		return
	_stage()

func _clear_slot() -> void:
	for path in [SaveManager.save_path(), SaveManager.backup_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

# --- staging ---------------------------------------------------------------

## Everything here goes through the **public API** — `purchase_item`, `purchase_augment`,
## `add_mastery_xp`, `grant`. Nothing reaches into private state. That is not fastidiousness:
## a sandbox that sets `_unlocks` directly would happily produce a save the real game cannot
## make, and then the thing being validated is the sandbox.
func _stage() -> void:
	var b := ItemDB.balance

	Economy.prestige_count = PRESTIGES
	Economy.marrow = MARROW

	Economy.grant(Economy.BONES, BONES)
	Economy.grant(Economy.HEARTS, HEARTS)
	Economy.grant(Economy.DOLLARS, DOLLARS)

	var xp := EconomyMath.mastery_xp_for_rank(b.mastery_base, MASTERY_RANK, b.mastery_exponent)
	for item in ItemDB.all_items():
		Progression.add_mastery_xp(item.id, xp)

	var owned := _unlock_everything()
	var nodes := _buy_upgrades()
	var devices := _buy_automation()

	print("")
	print("Bonehead Friend — sandbox")
	print("=========================")
	print("  save slot     %s  (slot_1 untouched)" % SANDBOX_SLOT)
	print("  owned         %d of %d items" % [owned, ItemDB.all_items().size()])
	print("  upgrades      %d nodes at %d levels each" % [nodes, AUGMENT_LEVELS])
	print("  automation    %d capstones owned, %d devices running (the rest are paused)"
		% [devices, mini(devices, DEVICES_RUNNING)])
	print("  purse         %s bones / %s hearts / %s dollars"
		% [_short(Economy.balance_of(Economy.BONES)), _short(Economy.balance_of(Economy.HEARTS)),
			_short(Economy.balance_of(Economy.DOLLARS))])
	print("  marrow        %.2f  (x%.2f income, %d lives)"
		% [Economy.marrow, Economy.marrow_multiplier(), Economy.prestige_count])
	print("  contracts     %d templates, %d milestones"
		% [ItemDB.all_contracts().size(), ItemDB.all_milestones().size()])
	print("")
	print("  Exclusive branches are deliberately NOT bought — they are a permanent")
	print("  pick-one and choosing for you would hide the gate strip that says so.")
	print("")

## Bought in passes rather than in one sweep, because `ItemData.requires` chains a ladder:
## the katana needs the mace, the mace is three rungs along, and a single pass would buy
## whatever happened to be first in load order and stop. Loops until a pass opens nothing
## new, which also means a cycle in the requires graph terminates instead of hanging.
func _unlock_everything() -> int:
	var owned := 0
	var opened := true
	while opened:
		opened = false
		for item in ItemDB.all_items():
			if Progression.is_unlocked(item.id):
				continue
			if Progression.purchase_item(item.id):
				opened = true
	for item in ItemDB.all_items():
		if Progression.is_unlocked(item.id):
			owned += 1
	return owned

## Ordinary levelled nodes only. Exclusive branches are left alone on purpose (see the note
## printed above), and capstones are handled separately so their count can be reported.
func _buy_upgrades() -> int:
	var bought := 0
	for node in _every_node():
		if node.is_automation or node.exclusive_group != &"":
			continue
		if Progression.purchase_augment(node.id, AUGMENT_LEVELS) > 0:
			bought += 1
	return bought

## One level of every capstone, which is what puts a device on the desk (`DeviceLayer`) and
## starts idle income. One rather than many: the point is to see them, and thirty levels of
## eighty capstones is an income figure that makes every price in the shop meaningless.
##
## **Most of them are then switched off**, and that is the interesting part. Eighty devices
## lay out as six rows across the play area and carpet the desk — the buddy disappears
## behind his own automation and there is nowhere left to throw anything. So the first
## `DEVICES_RUNNING` stay on and the rest are owned-but-paused, which is a state the game
## reaches on its own the moment somebody turns one off, and which leaves every switch on
## the Upgrades page as something to try.
func _buy_automation() -> int:
	var bought := 0
	for node in _every_node():
		if not node.is_automation:
			continue
		if Progression.purchase_augment(node.id, 1) > 0:
			bought += 1
			Progression.set_automation_enabled(node.id, bought <= DEVICES_RUNNING)
	return bought

## Every augment in the game: each owned item's tree, plus the global tree, which belongs to
## no item and would otherwise be missed.
func _every_node() -> Array[AugmentNode]:
	var out: Array[AugmentNode] = []
	for item in ItemDB.all_items():
		out.append_array(ItemDB.augments_for(item.id))
	out.append_array(ItemDB.augments_for(AugmentNode.GLOBAL))
	return out

func _short(value: float) -> String:
	if value >= 1e9:
		return "%.2fB" % (value / 1e9)
	if value >= 1e6:
		return "%.1fM" % (value / 1e6)
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%.0f" % value
