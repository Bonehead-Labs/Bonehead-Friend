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

## `-- --show` lays out the art a session changed, in the order it was changed, so it can be
## looked at in the world rather than in a contact sheet. Added for D45: a sprite that reads
## on a dark strip in a PNG viewer can still be wrong at world scale next to him, and the
## dual-tone pass in particular is a claim about legibility that only the running game can
## settle. Keep this list current with whatever the last art pass touched — it is a
## showcase, not a manifest, and a stale one is worse than none.
const SHOWCASE: Array[StringName] = [
	# D45, the five hands-on kind items, generated rather than plotted.
	&"tennis_ball", &"feather_duster", &"party_popper", &"warm_towel", &"kite",
	# D45, the eight that vanished on a dark desktop until they were given a second colour.
	&"mine", &"bowling_ball", &"frying_pan", &"gravity_vortex",
	&"swarm_launcher", &"tyre_iron", &"laser_lattice", &"implosion_charge",
]

## Grime to stage under `--show`, so the patches are visible without beating him first.
const SHOWCASE_GRIME := 0.65

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
		if OS.get_cmdline_user_args().has("--show"):
			_showcase()
		return
	_stage()
	if OS.get_cmdline_user_args().has("--show"):
		_showcase()

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
	var toys := _put_toys_out()

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
	print("  on the desk   %s" % ", ".join(toys))
	print("")
	print("  Leave him alone for about half a minute and he should walk to one of them.")
	print("  Spawning, hitting and petting all count as you being there and reset that")
	print("  clock — which is the feature working, and also why it is invisible while you")
	print("  are busy testing everything else.")
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

## A few things on the floor for him to find, because the idle brain needs a target and the
## desk starts empty. Chosen for the three routines that read most clearly from across the
## room: something he bounces on, something he stands next to, something he sits in.
##
## Spawned through the real signal rather than by instancing scenes here, so the item limit,
## the desk counter and `item_spawned` all behave exactly as they do in play.
func _put_toys_out() -> Array[String]:
	var out: Array[String] = []
	var x := 260.0
	for id in [&"trampoline", &"boombox", &"hot_tub"]:
		if ItemDB.get_item(id) == null:
			continue
		EventBus.spawn_requested.emit(id, Vector2(x, 120.0))
		out.append(String(id))
		x += 220.0
	return out

## Lay the session's changed art out in the world, in two waves.
##
## Two waves rather than one because thirteen rigid bodies dropped on the same frame at the
## same height arrive as a pile: they wedge into each other before anything settles and half
## the batch ends up underneath the other half, which is the opposite of a showcase. A second
## apart, the first row has come to rest before the second lands on the gaps.
##
## Grime is staged too, at `SHOWCASE_GRIME`, because grime is the one piece of his art that
## cannot be looked at on demand — the only other way to see it is to beat him for a while
## first, and by then you are looking at a knockout rather than at the dirt.
func _showcase() -> void:
	var view: Vector2 = get_tree().root.get_visible_rect().size
	var ids: Array[StringName] = []
	for id in SHOWCASE:
		if ItemDB.get_item(id) != null:
			ids.append(id)
	if ids.is_empty():
		print("  showcase      nothing to show — none of the listed ids are in ItemDB")
		return

	var rows := 2
	var per_row := int(ceil(float(ids.size()) / float(rows)))
	var placed := 0
	for row in rows:
		var slice := ids.slice(row * per_row, mini((row + 1) * per_row, ids.size()))
		if slice.is_empty():
			continue
		# Across the middle of the play area, never against the edges: the trash bin lives in
		# a corner and an item spawned on top of it is thrown away before it is seen.
		var span := view.x * 0.72
		var left := view.x * 0.14
		var step := span / float(maxi(slice.size() - 1, 1))
		for i in slice.size():
			var x := left + step * float(i) if slice.size() > 1 else view.x * 0.5
			EventBus.spawn_requested.emit(slice[i], Vector2(x, view.y * 0.18))
			placed += 1
		await get_tree().create_timer(1.0).timeout

	var buddy := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	if buddy and buddy.grime:
		buddy.grime.set_value(SHOWCASE_GRIME)

	print("")
	print("  showcase      %d items dropped in %d waves, grime staged at %.2f" % [
		placed, rows, SHOWCASE_GRIME])
	print("                %s" % ", ".join(ids.map(func(i: StringName) -> String:
		return String(i))))
	print("                Scrub him with the sponge to watch the grime come back off.")
	print("")

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
