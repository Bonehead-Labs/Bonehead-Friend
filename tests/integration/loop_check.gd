extends Node

## Headless walk of the gate loop: hit -> earn -> buy -> augment -> save -> reload, plus
## M3's kindness half — pet -> Hearts, mood, grime, and the knockout beat.
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
	_being_kind_pays_hearts()
	_dollars_count_acts_not_power()
	_the_kindness_augments_do_something()
	_mood_swings_the_payout()
	_grime_suppresses_bones()
	_shop_refuses_what_you_cannot_afford()
	_spawning_and_the_item_limit()
	_the_idle_brain_knows_who_is_at_the_desk()
	_knockout_pays_and_resets()
	_the_buddy_art_is_wired()
	_dragging_him_is_a_state()
	_mastery_accrues_and_pays()
	_automation_earns_and_toggles()
	_contracts_track_and_pay()
	await _the_knockout_beat_runs_and_ends_upright()
	await _the_sponge_cleans_him_and_pays()
	await _real_physics_produces_hits()
	await _he_goes_and_plays_with_his_toys()
	await _save_survives_a_restart()
	# Last: it wipes the run, so every suite that needs an owned item has to come first.
	_prestige_resets_the_run_and_keeps_the_meta()
	_the_shell_has_its_look()
	_every_colour_can_be_read()
	await _the_desk_can_be_cleared()
	await _explosives_still_explode()

	# Here, and nowhere else. This block spent three edits living inside
	# `_the_shell_has_its_look`, where it printed a total that was missing every suite after
	# it and called quit() before the last one had finished awaiting — so three suites were
	# running after the run had already reported its result.
	print("")
	print("============================")
	print("passed: %d   failed: %d" % [_passed, _failed])
	_clear_slot()
	get_tree().quit(1 if _failed > 0 else 0)

## No text may ever be close in colour to what is behind it.
##
## The palette was picked by eye and Bones came out at 2.97:1 on a sunk well — a price the
## player cannot read — while disabled buttons tinted their text at 55% alpha and landed
## near 2:1. Both are the same bug, and neither is visible to whoever picked the colour on
## their own monitor with their own eyes. So it is a test.
##
## WCAG AA is 4.5:1 for body text. Everything in this shell is body text: the largest thing
## on a card is a 20px pixel face, which is not "large text" by any reading of the standard.
func _every_colour_can_be_read() -> void:
	_suite("contrast")
	const FLOOR := 4.5

	# Every ink, on every surface it is ever printed on.
	var surfaces := {"panel": UIStyle.PANEL, "raised": UIStyle.RAISED, "sunk": UIStyle.SUNK}
	var inks := {
		"text": UIStyle.TEXT, "dim": UIStyle.TEXT_DIM, "disabled": UIStyle.DISABLED_INK,
		"bones": UIStyle.BONES, "hearts": UIStyle.HEARTS, "dollars": UIStyle.DOLLARS,
		"affordable": UIStyle.AFFORDABLE, "locked": UIStyle.LOCKED, "teal": UIStyle.TEAL,
		"despair": UIStyle.DESPAIR, "bliss": UIStyle.BLISS,
	}
	for ink_name in inks:
		for surface_name in surfaces:
			var ratio := UIStyle.contrast(inks[ink_name], surfaces[surface_name])
			_check("%s on %s is %.2f:1" % [ink_name, surface_name, ratio], ratio >= FLOOR)

	# The two inverted surfaces: the badge and the gate strip print cream on black, and the
	# reincarnation key prints cream on red — in every state it can be in, not only at rest.
	# A hover colour is a surface the player reads text on for as long as their cursor is
	# there, and three of them were literals inside ui_theme.gd that nothing here could see.
	for entry in [["badge/gate", UIStyle.PANEL, UIStyle.EDGE],
			["danger key", UIStyle.PANEL, UIStyle.LOCKED],
			["danger key, hovered", UIStyle.PANEL, UIStyle.DANGER_HOVER],
			["danger key, pressed", UIStyle.PANEL, UIStyle.DANGER_DOWN],
			["buy key, hovered", UIStyle.TEXT, UIStyle.BUY_HOVER]]:
		var ratio := UIStyle.contrast(entry[1], entry[2])
		_check("%s is %.2f:1" % [entry[0], ratio], ratio >= FLOOR)

	# Every state of every button the Theme actually defines, read off the Theme rather than
	# from a list kept by hand here. A hand-written grid only covers the states someone
	# remembered — and nobody remembered `hover_pressed`, so hovering a tab, a shop category
	# or a selected list row fell through this theme into Godot's stock dark one and put dark
	# ink on a dark box. "All text readable at all times" has to be a sweep, not a checklist.
	var states := [
		["normal", "font_color"],
		["hover", "font_hover_color"],
		["pressed", "font_pressed_color"],
		["hover_pressed", "font_hover_pressed_color"],
		["disabled", "font_disabled_color"],
	]
	var theme := UITheme.get_theme()
	var button_types: Array[String] = ["Button"]
	button_types.append_array(theme.get_type_variation_list("Button"))
	var unreadable: Array[String] = []
	var graded := 0
	for type_name in button_types:
		for state in states:
			var box_name: String = state[0]
			var ink_name: String = state[1]
			if not theme.has_stylebox(box_name, type_name):
				continue
			var box := theme.get_stylebox(box_name, type_name) as StyleBoxFlat
			if box == null:
				continue
			# The ink falls back the way Godot resolves it: this variation, then Button.
			var ink := UIStyle.TEXT
			if theme.has_color(ink_name, type_name):
				ink = theme.get_color(ink_name, type_name)
			elif theme.has_color(ink_name, "Button"):
				ink = theme.get_color(ink_name, "Button")
			graded += 1
			var ratio := UIStyle.contrast(ink, box.bg_color)
			if ratio < FLOOR:
				unreadable.append("%s/%s %.2f:1" % [type_name, box_name, ratio])
	_check("every button state the theme defines is readable (%d graded%s)"
		% [graded, "" if unreadable.is_empty() else ": " + ", ".join(unreadable)],
		unreadable.is_empty())

	# And no button state may be left to the stock theme: a missing stylebox is not a
	# neutral default, it is Godot's dark one arriving under our dark ink.
	var gaps: Array[String] = []
	for type_name in button_types:
		if not theme.has_stylebox("pressed", type_name):
			continue
		if not theme.has_stylebox("hover_pressed", type_name):
			gaps.append(type_name)
	_check("every toggleable variation defines its own hover_pressed%s"
		% ("" if gaps.is_empty() else ": " + ", ".join(gaps)), gaps.is_empty())

	# Marks, not text: a pip, a meter fill, a track. WCAG's floor for a non-text element
	# that carries meaning is 3:1, not 4.5:1 — but it is not zero, and a grid that graded
	# only inks against surfaces let an unfilled level pip ship at 1.18:1 on the tile it sat
	# on. Every tier-1 node in the game starts with ten of them, so the state a player sees
	# first was the state that was invisible.
	const MARK_FLOOR := 3.0
	var tiles := {"tile": UIStyle.RAISED, "sunk tile": UIStyle.SUNK, "card": UIStyle.PANEL}
	for tile_name in tiles:
		var edge := UIStyle.contrast(UIStyle.PIP_EDGE, tiles[tile_name])
		_check("a pip's outline on a %s is %.2f:1" % [tile_name, edge], edge >= MARK_FLOOR)
	var fill := UIStyle.contrast(UIStyle.PIP_FILLED, UIStyle.PIP_EMPTY)
	_check("a filled pip is %.2f:1 against an empty one" % fill, fill >= MARK_FLOOR)

	# Mood recolours a label continuously between its two poles and neutral, so the whole
	# sweep has to hold, not only the ends.
	var worst := 999.0
	var worst_at := 0.0
	for step in 21:
		var mood := lerpf(-100.0, 100.0, float(step) / 20.0)
		var ratio := UIStyle.contrast(UIStyle.mood_colour(mood), UIStyle.PANEL)
		if ratio < worst:
			worst = ratio
			worst_at = mood
	_check("the whole mood sweep is readable (worst %.2f:1 at %.0f)" % [worst, worst_at],
		worst >= FLOOR)

## Explosives, end to end.
##
## They stopped working entirely and nothing noticed: right-click primes a grenade's fuse,
## and when a right-click-to-despawn gesture was added to the shared base class it ran
## first and deleted the grenade instead of arming it. Nothing in any suite touched a
## throwable, so the loudest mechanic in the game was silently gone.
func _explosives_still_explode() -> void:
	_suite("explosives")
	_check("a throwable claims right-click for its fuse",
		ThrowableBase.new().right_click_is_mine())
	_check("and an ordinary item does not, so it can be thrown away",
		not BaseDraggable.new().right_click_is_mine())

	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	var buddy := _buddy()
	if spawner == null or buddy == null:
		_check("spawner and buddy present", false)
		return
	spawner.clear_desk()
	EventBus.spawn_requested.emit(&"grenade", buddy.global_position + Vector2(30.0, 0.0))
	await get_tree().physics_frame
	var grenade: ThrowableBase = null
	for node in get_tree().get_nodes_in_group(&"spawned_item"):
		if node is ThrowableBase:
			grenade = node
	_check("a grenade can be spawned", grenade != null)
	if grenade == null:
		return
	_check("its sprite is wired, so it can show that it is live", grenade.sprite != null)
	_check("its blast area is wired", grenade.explosion_area != null)
	_check("he is on his feet to be blown off them",
		buddy.health != null and not buddy.health.down)

	# Primed the way the player primes it, then detonated without waiting out the fuse.
	grenade.global_position = buddy.global_position + Vector2(30.0, 0.0)
	grenade.prime_explosion()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# An Array, not an int. A GDScript lambda captures locals **by value**, so a counter
	# incremented inside one leaves the outer variable at zero — and the test then reports
	# a working mechanic as broken, which is worse than no test.
	var hits: Array[int] = [0]
	var probe := func(_info: HitInfo) -> void: hits[0] += 1
	EventBus.damage_dealt.connect(probe)
	grenade.explode()
	# Three frames, not one. A hit is queued when it lands and drained on a later physics
	# step, so a probe that disconnects immediately sees nothing and reports the whole
	# mechanic broken.
	for i in 3:
		await get_tree().physics_frame
	EventBus.damage_dealt.disconnect(probe)
	_check("the blast reaches the buddy and hurts him (%d hits)" % hits[0], hits[0] > 0)
	spawner.clear_desk()

## Getting rid of things you spawned.
##
## The trash bin this replaces was a 36x45 catch area under a 64px sprite, anchored above
## the height at which a dropped item comes to rest — so nothing ever landed in it and the
## only way to clear the desk was to spawn past the item limit. Two ways now: right-click
## one thing, or clear all of them.
func _the_desk_can_be_cleared() -> void:
	_suite("clearing the desk")
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if spawner == null:
		_check("item spawner present", false)
		return

	spawner.clear_desk()
	for i in 3:
		EventBus.spawn_requested.emit(&"baseball_bat", Vector2(120.0 + i * 40.0, 100.0))
	_check("three items on the desk (got %d)" % spawner.item_count(),
		spawner.item_count() == 3)

	var cleared := spawner.clear_desk()
	_check("clearing the desk removes all of them (cleared %d, %d left)"
		% [cleared, spawner.item_count()], cleared == 3 and spawner.item_count() == 0)
	_check("clearing an empty desk is not an error", spawner.clear_desk() == 0)

	# The whitelist the right-click gesture leans on. If the buddy were ever in this group
	# a right-click would delete him, so it is worth an assertion rather than a comment.
	EventBus.spawn_requested.emit(&"baseball_bat", Vector2(200.0, 100.0))
	_check("a spawned item is marked as one",
		not get_tree().get_nodes_in_group(&"spawned_item").is_empty())
	var buddy := _buddy()
	_check("the buddy is not, so no gesture can delete him",
		buddy != null and not buddy.is_in_group(&"spawned_item"))
	spawner.clear_desk()

	# The hole this suite used to have. Fourteen explosives claim plain right-click to prime
	# a fuse, and for a whole milestone that meant a sixth of the spawnable roster could not
	# be removed one at a time by any gesture at all — the player's only exit was a button
	# labelled with a bare cross. Shift is the override no subclass may take.
	EventBus.spawn_requested.emit(&"grenade", Vector2(200.0, 100.0))
	await get_tree().process_frame
	var primed: Node = null
	for node in get_tree().get_nodes_in_group(&"spawned_item"):
		if node.has_method("right_click_is_mine") and node.right_click_is_mine():
			primed = node
			break
	if primed == null:
		_check("an explosive is on the desk and claims right-click", false)
	else:
		_check("an explosive keeps plain right-click for its fuse",
			not primed.click_would_bin(false))
		_check("but Shift bins it anyway", primed.click_would_bin(true))
		primed.bin_myself()
		await get_tree().process_frame
		_check("and it actually leaves the desk", spawner.item_count() == 0)

	# The other half of the same rule: an ordinary item needs no modifier, or the gesture
	# everybody uses becomes the awkward one.
	EventBus.spawn_requested.emit(&"baseball_bat", Vector2(200.0, 100.0))
	await get_tree().process_frame
	var plain: Node = get_tree().get_first_node_in_group(&"spawned_item")
	_check("an ordinary item bins on a plain right-click",
		plain != null and plain.click_would_bin(false))

	# Nothing may bin the buddy, with or without a modifier — he is not in the group, and
	# this is the assertion that keeps it that way if somebody ever adds him for dragging.
	_check("and Shift still cannot bin the buddy",
		buddy != null and not buddy.click_would_bin(true))

	# Explosives have to survive the button too, not only the gesture.
	for i in 3:
		EventBus.spawn_requested.emit(&"grenade", Vector2(120.0 + i * 40.0, 100.0))
	await get_tree().process_frame
	var before := spawner.item_count()
	spawner.clear_desk()
	await get_tree().process_frame
	_check("clear desk removes primed explosives too (had %d, %d left)"
		% [before, spawner.item_count()], before >= 3 and spawner.item_count() == 0)

## The Bonecard skin, checked as data rather than by looking at it.
##
## Everything here is the kind of break that costs nothing at parse time and shows up as a
## blank UI: a glyph file that was never generated, a font that failed to import, a
## `theme_type_variation` spelled slightly differently from the one the theme registers
## (Godot silently falls back to the base type), a UI sound nobody remembered to synthesise.
## Screenshots would catch some of it; only this catches all of it, every run.
func _the_shell_has_its_look() -> void:
	_suite("shell")

	for id in [&"bone", &"heart", &"dollar", &"lock", &"check", &"cross", &"star", &"bolt",
			&"hand", &"spawn", &"close", &"crate", &"scroll", &"sliders"]:
		_check("glyph %s exists" % id, UIStyle.glyph(id) != null)

	var theme := UITheme.get_theme()
	_check("the theme has a body font", theme.default_font != null)
	_check("the display face loaded", theme.get_font("font", "Label") != null)
	_check("the numeral face loaded", theme.get_font("font", "Numeral") != null)

	# Every variation the panels actually ask for. A typo here is invisible: the control
	# renders as its plain base type and looks merely wrong rather than broken.
	for variation in ["Card", "Tile", "TileHot", "TileDead", "Sunk", "Chip", "Badge",
			"Gate", "Capstone"]:
		_check("panel variation %s is defined" % variation,
			theme.has_stylebox("panel", variation))
	for variation in ["TabButton", "IconTab", "BuyButton", "GhostButton", "DangerButton",
			"ListRow"]:
		_check("button variation %s is defined" % variation,
			theme.has_stylebox("normal", variation))
	for variation in ["BodyLabel", "NameLabel", "Eyebrow", "Numeral"]:
		_check("label variation %s is defined" % variation, theme.has_font("font", variation))

	# A scrollbar's width is its track stylebox's minimum size. Zero here means a panel
	# that silently cannot be scrolled, which reads as content simply missing.
	var track := theme.get_stylebox("scroll", "VScrollBar")
	_check("the scrollbar has a width",
		track != null and track.get_minimum_size().x >= 4.0)

	var streams: Dictionary = AudioManager.get("_streams")
	for id in [&"ui_hover", &"ui_click", &"ui_tab", &"ui_denied", &"ui_open", &"ui_close"]:
		_check("sound %s is synthesised" % id, streams.has(id) and streams[id] != null)

	# The invariant every headless click test leans on: a control caught mid-tween is at
	# the wrong scale, and hit-testing it is a coin flip.
	_check("motion is off in headless", not UIMotion.enabled())

# --- the loop --------------------------------------------------------------

func _content_loaded() -> void:
	_suite("content")
	# Counted from disk, not from a floor. `>= 16` stops catching a dropped item the moment
	# a seventeenth is added — and the roster growing is the whole point of the data-driven
	# catalog, so the assertion has to grow with it instead of being re-bumped by hand.
	var item_files := 0
	for file in DirAccess.get_files_at("res://Data/Items"):
		if file.get_extension() in ["tres", "res"] or file.ends_with(".tres.remap"):
			item_files += 1
	_check("every .tres in res://Data/Items loaded (%d files, %d loaded)"
		% [item_files, ItemDB.all_items().size()],
		ItemDB.all_items().size() == item_files)

	# The art size contract, stated over the real catalog. An item icon is a 32px canvas
	# (art/tools/item_postprocess.py); the shell now boxes anything else down to fit, so a
	# stray size can no longer bend a list — but it is still a content bug, and this is
	# where it gets a name instead of being absorbed silently.
	var wrong_size: Array[String] = []
	var no_art: Array[String] = []
	for item in ItemDB.all_items():
		if item.icon == null:
			no_art.append(String(item.id))
		elif item.icon.get_size() != Vector2(UIStyle.ICON_CANVAS, UIStyle.ICON_CANVAS):
			wrong_size.append("%s %dx%d" % [item.id,
				int(item.icon.get_size().x), int(item.icon.get_size().y)])
	_check("every item's icon is a %dpx canvas%s" % [UIStyle.ICON_CANVAS,
		"" if wrong_size.is_empty() else " (wrong: " + ", ".join(wrong_size) + ")"],
		wrong_size.is_empty())
	# Not a failure — an item without art falls back to its category glyph, which the box
	# contract now delivers at the same size as real art, so the layout is unaffected. It
	# is listed so the art backlog is visible from the test run rather than from memory.
	_check("items still waiting on art: %s" % ("none" if no_art.is_empty() else ", ".join(no_art)),
		true)
	_check("balance loaded", ItemDB.balance != null and ItemDB.balance.mood_curve != null)
	_check("the bat exists", ItemDB.get_item(&"baseball_bat") != null)
	# The shape, not a count: every weapon's tree is three tier-1 nodes, an exclusive
	# branch group and a capstone, and that identical shape is what makes a new weapon's
	# tree three .tres files (docs/economy.md).
	var bat_tree := ItemDB.augments_for(&"baseball_bat")
	_check("the bat has three tier-1 nodes",
		bat_tree.filter(func(n: AugmentNode) -> bool: return n.tier == 1).size() == 3)
	_check("and an exclusive branch to pick from",
		bat_tree.filter(func(n: AugmentNode) -> bool: return n.exclusive_group != &"").size() >= 2)
	_check("and an automation capstone",
		bat_tree.any(func(n: AugmentNode) -> bool: return n.is_automation))
	_check("every automation capstone generates something", ItemDB.all_items().all(
		func(i: ItemData) -> bool:
			return ItemDB.augments_for(i.id).all(
				func(n: AugmentNode) -> bool: return not n.is_automation or n.automation_rate > 0.0)))
	# --- the ladder (M3.5-A) ---
	#
	# Every item needs a reason to keep being used after the next one is affordable, and
	# that reason is its tree. Nine of sixteen items had none: bought once, used once, gone.
	var treeless: Array[String] = []
	for item in ItemDB.all_items():
		if not ItemDB.augments_for(item.id).any(func(n: AugmentNode) -> bool: return n.tier == 1):
			treeless.append(String(item.id))
	_check("every item has upgrades to buy%s" % ("" if treeless.is_empty()
		else " (bare: " + ", ".join(treeless) + ")"), treeless.is_empty())

	# The finding that forced this milestone, as an assertion: the whole catalog cost 9,810
	# and the dearest thing in it was 2,500, so a player was out of things to buy inside two
	# hours. The numbers below are the committed catalog's own top and total.
	var dearest := 0
	var catalog := 0
	for item in ItemDB.all_items():
		dearest = maxi(dearest, item.cost)
		catalog += item.cost
	_check("the ladder reaches the top of the committed catalog (%d)" % dearest, dearest >= 40000)
	_check("and the whole catalog is not an afternoon's income (%d)" % catalog, catalog > 100000)

	# Progressive disclosure: a 28-item shop on hour one is noise. `ItemData.requires` has
	# existed since M2 and was empty on every item until M3.5-A.
	var gated := ItemDB.all_items().filter(func(i: ItemData) -> bool: return not i.requires.is_empty())
	_check("the top of each ladder is gated behind the rung below (%d gated)" % gated.size(),
		gated.size() >= 10)
	var locked := ItemDB.get_item(&"lightning")
	_check("and the gate is real: the top item cannot be bought first",
		locked != null and not Progression.can_purchase(&"lightning"))

	_check("personalities loaded", ItemDB.all_personalities().size() >= 5)
	_check("contracts loaded", ItemDB.all_contracts().size() >= 4)
	_check("every item has a scene or is a power", ItemDB.all_items().all(
		func(i: ItemData) -> bool: return i.scene != null))
	# The Hearts half of the economy has to exist, or the second currency is decoration.
	for id in [&"open_hand", &"sponge", &"pizza", &"boombox"]:
		var item := ItemDB.get_item(id)
		_check("the %s is in the catalog" % id, item != null)
		_check("the %s costs Hearts" % id, item != null and item.currency_id() == Economy.HEARTS)
	# Equipping a cursor power has to change what the player sees, or the tool with no world
	# sprite is invisible and the ordinary arrow keeps lying about what a click will do. Two
	# honest ways to satisfy it: replace the pointer (pistol, shotgun, open hand) or draw
	# yourself in the world (the fist, which is a rigid body that chases the mouse). The
	# shotgun shipped with neither and nothing noticed; five more cursor powers are coming.
	var invisible: Array[String] = []
	for item in ItemDB.all_items():
		if not item.is_cursor_power() or item.scene == null:
			continue
		var power := item.scene.instantiate()
		if power.get(&"cursor_texture") == null and not _draws_itself(power):
			invisible.append(String(item.id))
		power.free()
	_check("every cursor power shows the player what it is%s" % ("" if invisible.is_empty()
		else " (bare: " + ", ".join(invisible) + ")"), invisible.is_empty())

	_check("the open hand equips like a cursor power",
		ItemDB.get_item(&"open_hand").is_cursor_power())
	_check("but is filed with the friendly items",
		ItemDB.get_item(&"open_hand").category == ItemData.CATEGORY_FRIENDLY)

## Whether a power has a picture of its own anywhere in its scene. Searched by type rather
## than by node name — a power rebuilt from script comes back with different names, and
## looking one up across a scene boundary is the same bug as an absolute node path (D9).
func _draws_itself(node: Node) -> bool:
	if node is Sprite2D or node is AnimatedSprite2D:
		return true
	for child in node.get_children():
		if _draws_itself(child):
			return true
	return false

func _starters_are_owned() -> void:
	_suite("starters")
	# Free items are granted on every load, so adding one later needs no save migration.
	_check("bat is owned from boot", Progression.is_unlocked(&"baseball_bat"))
	_check("grenade is owned from boot", Progression.is_unlocked(&"grenade"))
	_check("fist is owned from boot", Progression.is_unlocked(&"fist"))
	# The only free Hearts source. Without it the second currency can never start, because
	# every other friendly item is bought with the Hearts it earns.
	_check("open hand is owned from boot", Progression.is_unlocked(&"open_hand"))
	_check("the sponge is not free", not Progression.is_unlocked(&"sponge"))
	_check("the mace is not free", not Progression.is_unlocked(&"mace"))

## Bones from one reference hit, divided back out by the mood and grime multipliers that
## were in force when it landed.
##
## Every hit now moves his mood and dirties him, so two identical hits at different moments
## legitimately pay different amounts. A raw before/after comparison would be measuring the
## mood swing rather than whatever the test is actually about — normalising here is what
## keeps the augment assertions honest.
## Normalised by every multiplier that is not the one under test, read **before** the emit
## because several of them move as a result of it: mood rises with the hit, and the
## milestone board can claim a rung off this very hit — the first reference hit in a run
## completes "First Blood" — which would otherwise make two identical hits pay differently
## for reasons that have nothing to do with the augment being measured.
func _reference_hit(source_id: StringName, damage: float = 40.0) -> float:
	var multipliers := Economy.mood_multiplier() * Economy.grime_multiplier() \
		* Milestones.income_multiplier() * Economy.temp_multiplier()
	var before := Economy.balance_of(Economy.BONES)
	EventBus.damage_dealt.emit(HitInfo.new(damage, source_id, Vector2(100, 100), 4000.0))
	return (Economy.balance_of(Economy.BONES) - before) / multipliers

## Returns the normalised Bones a single reference hit is worth, for the augment comparison.
func _hitting_him_pays() -> float:
	_suite("hit -> earn")
	var damage := 40.0
	var lifetime_before := Economy.lifetime_of(Economy.BONES)
	var earned := _reference_hit(&"baseball_bat", damage)

	_check("a hit pays Bones", earned > 0.0)
	_check("payout matches the documented chain",
		is_equal_approx(earned, damage * ItemDB.balance.bones_per_damage))
	# Against the raw grant, not the normalised figure: at neutral mood the U-curve pays
	# 0.6x, so the normalised number is deliberately larger than what was banked.
	_check("lifetime tracks the payout", Economy.lifetime_of(Economy.BONES) > lifetime_before)
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
	var after_augment := _reference_hit(&"baseball_bat")
	_check("the same hit now pays more", after_augment > base_payout)
	_check("it pays exactly the augment's multiple",
		is_equal_approx(after_augment, base_payout * node.effect_per_level))

	var bulk := Progression.purchase_augment(&"bat_damage", 10)
	_check("bulk buy is capped by the wallet, not by max_levels", bulk >= 1 and bulk <= 10)

func _being_kind_pays_hearts() -> void:
	_suite("kindness -> Hearts")
	var buddy := _buddy()
	var before := Economy.balance_of(Economy.HEARTS)
	var bones_before := Economy.balance_of(Economy.BONES)
	var mood_before: float = buddy.mood.value if buddy else 0.0
	EventBus.kindness_given.emit(&"open_hand", 1.0, Vector2(100, 100))
	var earned := Economy.balance_of(Economy.HEARTS) - before
	_check("a pet pays Hearts", earned > 0.0)
	_check("and pays no Bones", is_equal_approx(Economy.balance_of(Economy.BONES), bones_before))
	_check("lifetime Hearts tracks it", Economy.lifetime_of(Economy.HEARTS) >= earned)
	# He arrives here having just been beaten up by the suites above, so the claim is that
	# petting *lifts* his mood — not that one pet is enough to make him cheerful.
	_check("petting cheers him up", buddy != null and buddy.mood.value > mood_before)

	# The combo is a reward for repeated *acts*. A generator left switched on must not sit
	# at the ceiling forever, which is why sustained kindness is a separate signal.
	var combo_before := Economy.balance_of(Economy.HEARTS)
	for i in 6:
		EventBus.kindness_given.emit(&"open_hand", 1.0, Vector2(100, 100))
	var combo_total := Economy.balance_of(Economy.HEARTS) - combo_before
	_check("repeat pets inside the window compound", combo_total > earned * 6.0)

	# Every multiplier has to be read BEFORE the emit. Economy is connected to the bus first
	# (it is an autoload; MoodComponent is a scene child), so it pays at the mood in force
	# when the event fired and the component raises that mood immediately afterwards — and
	# the milestone board can claim a rung off this very event, after the payout is granted.
	var expected := 1.0 * ItemDB.balance.hearts_per_kindness \
		* Economy.mood_multiplier() * Economy.marrow_multiplier() \
		* Milestones.income_multiplier() * Economy.temp_multiplier()
	var sustained_before := Economy.balance_of(Economy.HEARTS)
	EventBus.kindness_sustained.emit(&"boombox", 1.0, Vector2(100, 100))
	var sustained := Economy.balance_of(Economy.HEARTS) - sustained_before
	_check("a generator's Hearts skip the combo entirely", is_equal_approx(sustained, expected))

## Dollars count *acts*, not power (docs/decisions.md D31).
##
## This is the one property that makes a third currency safe to add, and it is the one a
## later refactor is most likely to break — the obvious "improvement" is to run Dollars
## through `payout_for` like everything else, at which point a veteran with a x4,000
## multiplier earns hats four thousand times faster than someone on their first afternoon
## and the whole cosmetic economy is meaningless.
func _dollars_count_acts_not_power() -> void:
	_suite("dollars")
	var b := ItemDB.balance
	var before := Economy.balance_of(Economy.DOLLARS)
	EventBus.damage_dealt.emit(HitInfo.new(40.0, &"baseball_bat", Vector2(100, 100), 3000.0))
	var per_hit := Economy.balance_of(Economy.DOLLARS) - before
	_check("a hit pays Dollars", per_hit > 0.0)
	_check("exactly the flat rate", is_equal_approx(per_hit, b.dollars_per_hit))

	# The same hit, a hundred times the damage, every multiplier the run has accumulated —
	# and the same Dollar.
	before = Economy.balance_of(Economy.DOLLARS)
	var bones_before := Economy.balance_of(Economy.BONES)
	EventBus.damage_dealt.emit(HitInfo.new(4000.0, &"baseball_bat", Vector2(100, 100), 3000.0))
	_check("a hit a hundred times bigger pays a hundred times the Bones",
		Economy.balance_of(Economy.BONES) - bones_before > 0.0)
	_check("and exactly the same Dollar",
		is_equal_approx(Economy.balance_of(Economy.DOLLARS) - before, b.dollars_per_hit))

	before = Economy.balance_of(Economy.DOLLARS)
	EventBus.kindness_given.emit(&"open_hand", 1.0, Vector2(100, 100))
	_check("a kind act pays its own flat rate", is_equal_approx(
		Economy.balance_of(Economy.DOLLARS) - before, b.dollars_per_kind_act))

	# A generator is not an act. The same reasoning that keeps sustained kindness off the
	# contract board keeps it out of the till: a boombox left on the desk would otherwise
	# buy a hat overnight with nobody at the keyboard.
	before = Economy.balance_of(Economy.DOLLARS)
	EventBus.kindness_sustained.emit(&"boombox", 4.0, Vector2(100, 100))
	_check("but a generator's trickle is not an act",
		is_equal_approx(Economy.balance_of(Economy.DOLLARS), before))

	# And they are not income: Marrow is scaled by what a run *earned*, so counting hat
	# money would let cosmetics pay for prestige.
	var lifetime_before := Economy.lifetime_of(Economy.BONES) + Economy.lifetime_of(Economy.HEARTS)
	var run_before := Economy.run_earnings
	Economy.grant(Economy.DOLLARS, 500.0)
	_check("Dollars do not count as lifetime earnings", is_equal_approx(
		Economy.lifetime_of(Economy.BONES) + Economy.lifetime_of(Economy.HEARTS), lifetime_before))
	_check("nor towards the run Marrow is scaled by",
		is_equal_approx(Economy.run_earnings, run_before))
	_check("but they are spendable, unlike the Ectoplasm they replaced",
		Economy.spend(Economy.DOLLARS, 500.0))

## Two of the three augments a kindness-first player can buy were placebos: OpenHandPower
## sets its own pet interval and emits a flat `pet_value`, so neither `cooldown_mult` nor
## `damage_mult` reached it and both nodes charged Hearts for nothing (M3.5-0). A modifier
## that exists in Progression proves nothing — the assertion has to be that the power
## behaves differently, so this fires a real one.
func _the_kindness_augments_do_something() -> void:
	_suite("the kindness augments")
	var scene := load("res://Scenes/Powers/open_hand_power.tscn") as PackedScene
	if scene == null:
		_check("open hand power scene loads", false)
		return

	# Two instances rather than one: each starts with its cooldown clear, so the second pet
	# can be measured without either awaiting the interval or reaching into a private field.
	var before_power := scene.instantiate() as OpenHandPower
	add_child(before_power)
	var emitted: Array[float] = []
	var watch := func(_id: StringName, value: float, _at: Vector2) -> void: emitted.append(value)
	EventBus.kindness_given.connect(watch)
	before_power.fire(Vector2(100, 100))
	var base_interval := before_power.pet_interval()

	Economy.grant(Economy.HEARTS, 5000.0)
	var bought_value := Progression.purchase_augment(&"open_hand_damage", 1)
	var bought_rate := Progression.purchase_augment(&"open_hand_third", 1)
	_check("both kindness augments are purchasable", bought_value == 1 and bought_rate == 1)

	var after_power := scene.instantiate() as OpenHandPower
	add_child(after_power)
	after_power.fire(Vector2(100, 100))
	EventBus.kindness_given.disconnect(watch)

	_check("both pets were seen on the bus", emitted.size() == 2)
	if emitted.size() == 2:
		var value_node := ItemDB.get_augment(&"open_hand_damage")
		_check("Gentler Touch makes each stroke worth more kindness",
			is_equal_approx(emitted[1], emitted[0] * value_node.effect_per_level))

	var rate_node := ItemDB.get_augment(&"open_hand_third")
	_check("Faster Strokes shortens the gap between pets",
		is_equal_approx(after_power.pet_interval(), base_interval * rate_node.effect_per_level))

	before_power.queue_free()
	after_power.queue_free()

## The U-curve is the reason to swing him, so the test is that the *same* event pays
## differently at the two extremes and worst in the middle (docs/economy.md).
func _mood_swings_the_payout() -> void:
	_suite("mood")
	var buddy := _buddy()
	if buddy == null:
		_check("buddy present", false)
		return

	buddy.mood.set_value(0.0)
	var neutral := Economy.mood_multiplier()
	buddy.mood.set_value(100.0)
	var bliss := Economy.mood_multiplier()
	buddy.mood.set_value(-100.0)
	var despair := Economy.mood_multiplier()

	_check("neutral is the worst multiplier in the game", neutral < bliss and neutral < despair)
	_check("both extremes pay about the same", is_equal_approx(bliss, despair))
	_check("the extremes are worth more than double the trough", bliss > neutral * 2.0)

	# And it reaches the wallet, not just the readout.
	buddy.mood.set_value(0.0)
	var at_neutral := _payout_of_one_hit()
	buddy.mood.set_value(-100.0)
	var at_despair := _payout_of_one_hit()
	_check("a despairing buddy pays more for the same hit", at_despair > at_neutral)

	buddy.mood.set_value(0.0)
	_check("damage makes him miserable", _mood_after_damage(buddy) < 0.0)

func _mood_after_damage(buddy: Buddy) -> float:
	EventBus.damage_dealt.emit(HitInfo.new(40.0, &"baseball_bat", Vector2(100, 100), 4000.0))
	return buddy.mood.value

func _payout_of_one_hit() -> float:
	var before := Economy.balance_of(Economy.BONES)
	EventBus.damage_dealt.emit(HitInfo.new(40.0, &"baseball_bat", Vector2(100, 100), 4000.0))
	return Economy.balance_of(Economy.BONES) - before

## Grime is the mechanic that makes the cheapest Hearts item protect the Bones economy.
## It must cost real money and must never be able to stop the game paying at all.
func _grime_suppresses_bones() -> void:
	_suite("grime")
	var buddy := _buddy()
	if buddy == null:
		_check("buddy present", false)
		return

	buddy.mood.set_value(0.0)
	buddy.grime.set_value(0.0)
	_check("Economy sees a clean buddy", is_equal_approx(Economy.grime_multiplier(), 1.0))
	var clean_payout := _payout_of_one_hit()

	buddy.mood.set_value(0.0)
	buddy.grime.set_value(1.0)
	_check("Economy sees a filthy one", Economy.grime_multiplier() < 1.0)
	buddy.mood.set_value(0.0)
	var filthy_payout := _payout_of_one_hit()
	_check("a filthy buddy earns less for the same hit", filthy_payout < clean_payout)
	_check("but still earns something — there is no fail state", filthy_payout > 0.0)

	buddy.grime.set_value(0.0)
	_check("damage makes a mess", _grime_after_damage(buddy) > 0.0)

	# Scrubbing a clean skeleton must pay nothing, or a sponge left leaning on him farms
	# Hearts the way a mace left leaning on him used to farm Bones.
	buddy.grime.set_value(0.0)
	_check("cleaning an already-clean buddy removes nothing", buddy.grime.clean(1.0) == 0.0)
	buddy.grime.set_value(0.4)
	_check("cleaning returns only what actually came off",
		is_equal_approx(buddy.grime.clean(1.0), 0.4))
	buddy.grime.set_value(0.0)

func _grime_after_damage(buddy: Buddy) -> float:
	EventBus.damage_dealt.emit(HitInfo.new(200.0, &"baseball_bat", Vector2(100, 100), 4000.0))
	return buddy.grime.value

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

## The idle brain is what makes him wander off and use a toy when nobody is watching, and it
## is driven entirely by "how long since the player did something". That makes the question
## of what counts as the player load-bearing, and it is asked of `ItemData.is_autonomous`.
##
## This suite exists because the feature was dead on arrival and nothing noticed. A turret
## fires every couple of seconds forever, its shots arrive as ordinary `damage_dealt`, and
## the brain read every one of them as somebody sitting down at the desk — so with a single
## turret running he never reached the twenty-five idle seconds a routine needs, and the
## player who bought automation specifically to watch him potter about got a buddy who
## never moved again. No test failed, because there was no test.
func _the_idle_brain_knows_who_is_at_the_desk() -> void:
	_suite("idle brain")

	# Data first: the flag is the whole mechanism, and it is set by two seed tools that skip
	# files which already exist. A tool run without `--force` leaves the flag off and the
	# feature silently dead again — which is exactly how this shipped the first time.
	var autonomous := 0
	var hand_driven := 0
	for item in ItemDB.all_items():
		if item.is_autonomous:
			autonomous += 1
		else:
			hand_driven += 1
	_check("something is marked autonomous", autonomous > 0)
	_check("and most of the roster is not", hand_driven > autonomous)

	for id in [&"pellet_turret", &"tesla_coil", &"mortar", &"gorilla", &"goose", &"raccoon"]:
		var item := ItemDB.get_item(id)
		if item == null:
			_check("'%s' exists" % id, false)
			continue
		_check("'%s' acts on its own" % id, item.is_autonomous)

	# The other half, and the one a careless edit breaks: a bat is the player's arm. If
	# everything were tagged autonomous the brain would ignore the player entirely and
	# potter off mid-swing, which reads as a much worse bug than the one this fixes.
	for id in [&"baseball_bat", &"trampoline", &"open_hand", &"sponge"]:
		var item := ItemDB.get_item(id)
		if item == null:
			_check("'%s' exists" % id, false)
			continue
		_check("'%s' is somebody's hand" % id, not item.is_autonomous)

	# Every turret, by category rather than by the list above, so a ninth turret added later
	# is covered without anybody remembering to come back here.
	var untagged: Array[String] = []
	for item in ItemDB.all_items():
		if item.category == ItemData.CATEGORY_TURRET and not item.is_autonomous:
			untagged.append(String(item.id))
	_check("every turret is tagged (missing: %s)" % ", ".join(untagged), untagged.is_empty())

func _spawning_and_the_item_limit() -> void:
	_suite("spawning")
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if spawner == null:
		_check("item spawner present", false)
		return

	# The spawner's *effective* limit, not the balance's base one: Mastery Pool checkpoints
	# add slots (`Progression.item_limit_bonus`), so a suite above this one that earns
	# enough mastery raises the ceiling and the base figure becomes a lie. It read the base
	# until the Dollars suite pushed the pool past its first checkpoint.
	var limit: int = spawner.item_limit()
	for i in limit + 3:
		EventBus.spawn_requested.emit(&"baseball_bat", Vector2(200, 100))
	_check("item limit holds (%d, base %d)" % [limit, ItemDB.balance.item_limit],
		spawner.item_count() <= limit)

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

## The round's climax, end to end. The old implementation was a teleport: he vanished from
## wherever he was and reappeared at home with a full wallet. The gate for M3 is that the
## beat is worth watching, so the test is that it actually happens — every state in order,
## and a buddy who is upright, unfrozen and playable when it is over.
## Mastery is earned by *using* a thing, and the shared pool is what makes using a variety
## of things worth more than grinding one. Both feed the payout pipeline, so both are worth
## checking against the real autoloads rather than only as pure functions.
## The art wiring, checked against the real imported resources.
##
## Every assertion here is one that already failed silently once. The tag-extension bug —
## appending a frame stretches any tag ending at the last frame — made `idle` import as 74
## frames instead of 8, and the only symptom was that the buddy played the whole file for
## every animation. A frame count checked against the offsets it was measured from catches
## that immediately.
func _the_buddy_art_is_wired() -> void:
	_suite("buddy art")
	var buddy := _buddy()
	if buddy == null or buddy.art == null:
		_check("buddy has an art driver", false)
		return
	var art: BuddyArt = buddy.art

	_check("the body sprite frames loaded", art.body != null and art.body.sprite_frames != null)
	_check("the face sprite frames loaded", art.face != null and art.face.sprite_frames != null)
	if art.body == null or art.body.sprite_frames == null:
		return
	var body := art.body.sprite_frames

	# Every state the buddy can enter must have art, or he freezes mid-pose.
	for state in art.STATE_ANIMATION:
		var animation: StringName = art.STATE_ANIMATION[state]
		_check("state '%s' has a '%s' animation" % [state, animation],
			body.has_animation(animation))

	# Every expression the game can ask for must exist, or set_expression silently no-ops
	# and he wears whatever face he had last.
	if art.face and art.face.sprite_frames:
		var faces := art.face.sprite_frames
		for state in art.STATE_FACE:
			_check("state '%s' face '%s' exists" % [state, art.STATE_FACE[state]],
				faces.has_animation(art.STATE_FACE[state]))
		for entry in art.MOOD_FACES:
			_check("mood face '%s' exists" % entry[1], faces.has_animation(entry[1]))
		for entry in art.MOOD_IDLES:
			_check("mood idle '%s' exists" % entry[1], body.has_animation(entry[1]))

	# The offsets were measured frame by frame off the same sheets the tags were built from,
	# so a mismatch means the two have drifted apart — which is exactly what a stretched tag
	# looks like from here. `_offset_positions` is the packed cache (Phase 0 step 4), keyed
	# by StringName to match `body.animation`'s own type.
	for animation in body.get_animation_names():
		var track := StringName(animation)
		var positions: PackedVector2Array = art._offset_positions.get(track, PackedVector2Array())
		_check("'%s' has face offsets" % animation, not positions.is_empty())
		if not positions.is_empty():
			_check("'%s' offsets match its %d frames (got %d)"
				% [animation, body.get_frame_count(animation), positions.size()],
				positions.size() == body.get_frame_count(animation))

	# One-shots must not loop: a collapse that loops never lets him get back up.
	for animation in art.ONE_SHOT:
		if body.has_animation(animation):
			_check("'%s' does not loop" % animation, not body.get_animation_loop(animation))

	_check("the knockout beat has a real duration",
		art.animation_length(&"collapse") > 0.1)

	# Regression for the mirror bug (docs/plan-expressive-buddy.md 3.3): it used to negate
	# the whole placed x, `_face_home.x` included, which is only correct while the home is
	# (0, 0). Today's real Face home is (0, 0) too (buddy.gd copies Puppet's position), so
	# this seeds a synthetic non-zero home and drives the accumulator directly — the fix has
	# to hold before the art pass ever gives Face a real offset to break on.
	var saved_home := art._face_home
	var saved_facing := art._facing
	var saved_positions := art._track_positions
	var saved_visible := art._track_visible

	art._face_home = Vector2(3.0, 0.0)
	art._track_positions = PackedVector2Array([Vector2(4.0, 0.0)])
	art._track_visible = PackedByteArray([1])
	art.body.frame = 0
	art.travel(-1.0, 1.0)
	art._advance_travel(1.0 / 60.0)
	# Bob is a y-only offset (`_place_face` adds `Vector2(0.0, _bob)`), so `face.position.x`
	# is the mirrored placement with nothing else riding on it.
	var expected_dx := 4.0 * art._base_scale.x
	_check("facing left mirrors the offset, not the home (face.x == %.2f, got %.2f)"
			% [3.0 - expected_dx, art.face.position.x],
		is_equal_approx(art.face.position.x, 3.0 - expected_dx))
	_check("mirroring negates dx, not `-_face_home.x - dx`",
		not is_equal_approx(art.face.position.x, -3.0 - expected_dx))

	# `BuddyArt` should still be able to settle after that synthetic walk: travel() turned
	# processing on, and it must turn itself back off once travel and the bob it drives have
	# both decayed to nothing — the honest-idle claim in 3.4 is only true if this holds.
	art._travel = 0.0
	art._bob = 0.0
	art._process(1.0 / 60.0)
	_check("BuddyArt stops processing once travel and the bob it drives have settled",
		not art.is_processing())

	art._face_home = saved_home
	art._facing = saved_facing
	art._track_positions = saved_positions
	art._track_visible = saved_visible
	art._on_body_animation_changed()

	# Grime used to be `puppet.modulate` on the body sprite alone, leaving a spotless white
	# face on a filthy skeleton (docs/plan-expressive-buddy.md 3.6). It is now a `grime`
	# uniform on the shared shader material EffectsPlayer installs, applied to both sprites.
	if buddy.grime and buddy.face:
		var saved_grime := buddy.grime.value
		buddy.grime.set_value(0.6)
		var face_material := buddy.face.material as ShaderMaterial
		_check("grime reaches the face material",
			face_material != null
			and is_equal_approx(float(face_material.get_shader_parameter(&"grime")), 0.6))
		var puppet_material := art.body.material as ShaderMaterial
		_check("and the puppet material, together",
			puppet_material != null
			and is_equal_approx(float(puppet_material.get_shader_parameter(&"grime")), 0.6))
		buddy.grime.set_value(saved_grime)
	else:
		_check("grime and face are present to test", false)

## Picking him up and putting him down. `dragged` used to be reachable only as a side effect
## of a reaction lapsing mid-drag, and nothing ever cleared it, so a hit taken while held
## left him stuck in the dragged pose with his mood idle unable to resume.
func _dragging_him_is_a_state() -> void:
	_suite("drag state")
	var buddy := _buddy()
	if buddy == null:
		_check("buddy present", false)
		return
	buddy.health.reset_meter()
	# Whatever expression the earlier suites left him in is irrelevant; what matters is that
	# he is not already being held.
	_check("he is not already being dragged", not buddy.dragging)

	buddy._start_drag()
	_check("grabbing him enters the dragged state", buddy.state == &"dragged")
	_check("and he is actually dragging", buddy.dragging)

	# A hit while held, then release: the reaction must not strand him.
	EventBus.damage_dealt.emit(HitInfo.new(10.0, &"baseball_bat", Vector2(100, 100), 4000.0))
	buddy._end_drag()
	_check("letting go leaves the dragged state",
		buddy.state != &"dragged" or not buddy.dragging)
	_check("and he is no longer dragging", not buddy.dragging)

func _mastery_accrues_and_pays() -> void:
	_suite("mastery")
	var base := ItemDB.balance.mastery_base
	var before_xp := Progression.mastery_xp(&"mace")
	EventBus.damage_dealt.emit(HitInfo.new(120.0, &"mace", Vector2(100, 100), 4000.0))
	_check("using a thing earns it mastery XP", Progression.mastery_xp(&"mace") > before_xp)
	_check("and only that thing", is_equal_approx(Progression.mastery_xp(&"dynamite"), 0.0))

	# Enough XP to cross several ranks in a single call, which is the case a naive rank-up
	# counter gets wrong: the pool must gain one point per rank *crossed*, not one per event.
	var pool_before := Progression.mastery_pool()
	var rank_before := Progression.mastery_rank(&"mace")
	Progression.add_mastery_xp(&"mace", EconomyMath.mastery_xp_for_rank(base, 5))
	var rank_after := Progression.mastery_rank(&"mace")
	_check("crossing ranks raises the rank", rank_after > rank_before + 1)
	_check("the pool gained exactly one point per rank crossed",
		Progression.mastery_pool() - pool_before == rank_after - rank_before)

	_check("the pool bonus is above 1 once checkpoints are passed",
		Progression.mastery_pool_bonus() >= 1.0)
	_check("the pool discounts upgrades", Progression.augment_cost_multiplier() <= 1.0)

	# The discount has to reach the quoted price as well as the charge, or the button quotes
	# one number and takes another.
	var node := ItemDB.get_augment(&"mace_damage")
	var quoted := Progression.next_augment_cost(&"mace_damage")
	_check("a discounted quote is below the raw base",
		quoted <= float(node.cost_base) + 0.001)

	# Rank 50 is the item's own payout bonus, and it must reach the wallet.
	Progression.add_mastery_xp(&"mace", EconomyMath.mastery_xp_for_rank(base, 50))
	_check("rank 50 is reached", Progression.mastery_rank(&"mace") >= 50)
	_check("and it multiplies that item's payout",
		Progression.mastery_multiplier(&"mace") > Progression.mastery_multiplier(&"dynamite"))

## Automation is the whole point of the Hearts economy (D2), and its rate has to reach both
## the online tick and the offline accrual or the capstone is a Hearts sink that does nothing.
func _automation_earns_and_toggles() -> void:
	_suite("automation")
	var node := ItemDB.get_augment(&"bat_sentry")
	if node == null:
		_check("the bat sentry exists", false)
		return

	_check("automation starts at zero",
		is_equal_approx(Progression.automation_rate_per_second(Economy.BONES), 0.0))

	# Bought by hand rather than through purchase_augment: the capstone is mastery-gated and
	# this suite is about what the rate does, not about the gate.
	Economy.grant(Economy.HEARTS, float(node.cost_base) * 2.0)
	Progression.add_mastery_xp(&"baseball_bat",
		EconomyMath.mastery_xp_for_rank(ItemDB.balance.mastery_base, node.requires_mastery))
	_check("mastery unlocks the capstone", Progression.augment_lock_reason(&"bat_sentry").is_empty())
	_check("the capstone can be bought", Progression.purchase_augment(&"bat_sentry", 1) == 1)

	var rate := Progression.automation_rate_per_second(Economy.BONES)
	_check("a bought capstone produces a rate", rate > 0.0)
	_check("into its own item's currency, not the other one",
		is_equal_approx(Progression.automation_rate_per_second(Economy.HEARTS), 0.0))

	Progression.set_automation_enabled(&"bat_sentry", false)
	_check("switching it off stops the rate",
		is_equal_approx(Progression.automation_rate_per_second(Economy.BONES), 0.0))
	Progression.set_automation_enabled(&"bat_sentry", true)
	_check("and switching it back on restores it",
		is_equal_approx(Progression.automation_rate_per_second(Economy.BONES), rate))

	# --- the engine (M3.5-A) ---
	#
	# A capstone is a *levelled* device: linear rate against exponential cost. While every
	# capstone was max_levels 1 the game's idle income was a flat line no matter how long
	# anyone played, which is the shape that puts a cube-root prestige threshold out of
	# reach at any divisor.
	_check("a capstone has levels to buy", node.max_levels > 1)
	Economy.grant(Economy.HEARTS, EconomyMath.bulk_cost(
		float(node.cost_base), node.cost_growth, 1, 3) * 2.0)
	var levelled := Progression.purchase_augment(&"bat_sentry", 3)
	_check("more levels can be bought", levelled == 3)
	_check("and the rate is the level's multiple, not a flat one",
		is_equal_approx(Progression.automation_rate_per_second(Economy.BONES),
			node.automation_rate * float(Progression.augment_level(&"bat_sentry"))))
	rate = Progression.automation_rate_per_second(Economy.BONES)

	# Every item automates, or idle income cannot grow with the roster — which is the other
	# half of the engine, and the half that makes buying a new toy an idle decision as well
	# as an active one.
	var bare: Array[String] = []
	for item in ItemDB.all_items():
		if not ItemDB.augments_for(item.id).any(func(n: AugmentNode) -> bool: return n.is_automation):
			bare.append(String(item.id))
	_check("every item has an automation capstone%s" % ("" if bare.is_empty()
		else " (without: " + ", ".join(bare) + ")"), bare.is_empty())

	# The global tree reaches automation income, which per-item payout nodes deliberately
	# do not — that is what makes it the cross-run ladder rather than another item's tree.
	var globals := ItemDB.augments_for(AugmentNode.GLOBAL)
	_check("the global tree has content", not globals.is_empty())
	if not globals.is_empty():
		var g: AugmentNode = globals[0]
		Economy.grant(g.currency_id(), float(g.cost_base) * 2.0)
		var before_global := Economy.payout_for(100.0, &"automation")
		_check("a global node is purchasable", Progression.purchase_augment(g.id, 1) == 1)
		_check("and it multiplies automation income too",
			is_equal_approx(Economy.payout_for(100.0, &"automation"),
				before_global * g.effect_per_level))
		_check("as well as a swing", Progression.get_modifier(&"baseball_bat", &"payout_mult")
			> Progression.get_modifier(&"baseball_bat", &"mass_mult"))

	# The tree quotes with the Mastery Pool discount applied, because the purchase charges
	# with it. Quoting `cost_base` directly made every checkpoint widen the gap between the
	# number on the button and the number taken from the wallet.
	var quote := Progression.augment_bulk_cost(&"bat_sentry", 2)
	var wallet := Economy.balance_of(Economy.HEARTS)
	Economy.grant(Economy.HEARTS, quote * 2.0)
	wallet = Economy.balance_of(Economy.HEARTS)
	Progression.purchase_augment(&"bat_sentry", 2)
	_check("the quoted bulk price is the price charged",
		is_equal_approx(wallet - Economy.balance_of(Economy.HEARTS), quote))
	_check("and it is under the undiscounted price when the pool has paid out",
		Progression.augment_cost_multiplier() >= 1.0 or quote < EconomyMath.bulk_cost(
			float(node.cost_base), node.cost_growth, Progression.augment_level(&"bat_sentry") - 2, 2))
	rate = Progression.automation_rate_per_second(Economy.BONES)

	# The device on the desk. It earns nothing and is drawn from three mount sprites
	# composited with the item's own art, so what is asserted is that buying automation puts
	# something on screen and switching it off takes it away — "an idle desktop still looks
	# alive" was the one pillar the whole automation system did not deliver.
	var devices := DeviceLayer.new()
	devices.name = "DeviceLayer"
	add_child(devices)
	_check("buying a capstone puts a device on the desk", devices.device_count() >= 1)
	Progression.set_automation_enabled(&"bat_sentry", false)
	_check("switching it off takes the device away", devices.device_count() == 0)
	_check("and the income stops with it",
		is_equal_approx(Progression.automation_rate_per_second(Economy.BONES), 0.0))
	Progression.set_automation_enabled(&"bat_sentry", true)
	_check("switching it back on brings it back", devices.device_count() >= 1)
	var device := devices.get_node_or_null("Device_bat_sentry")
	_check("the device is named after its capstone, not @Node2D@41", device != null)
	_check("and it is a picture, not a body", device != null and not (device is RigidBody2D))
	devices.queue_free()

	# Offline accrual, including the clamp that matters most.
	var before := Economy.balance_of(Economy.BONES)
	var earned := Economy.apply_offline_earnings(int(Time.get_unix_time_from_system()) - 600)
	_check("ten minutes away pays Bones", float(earned.get(Economy.BONES, 0.0)) > 0.0)
	_check("and the wallet actually received it", Economy.balance_of(Economy.BONES) > before)

	# Offline pays the stable multipliers — prestige and the pool — and none of the
	# volatile ones. It used to pay *nothing*, while online automation paid all four.
	var stable := Economy.marrow_multiplier() * Progression.mastery_pool_bonus()
	_check("offline pays prestige and the pool, and not mood",
		is_equal_approx(float(earned.get(Economy.BONES, 0.0)),
			rate * 600.0 * ItemDB.balance.offline_efficiency * stable))

	var future := Economy.apply_offline_earnings(int(Time.get_unix_time_from_system()) + 99999)
	_check("a clock skewed into the future pays nothing",
		is_equal_approx(float(future.get(Economy.BONES, 0.0)), 0.0))

func _contracts_track_and_pay() -> void:
	_suite("contracts")
	Progression.refresh_contracts(true)
	var board := Progression.active_contracts()
	_check("a board was rolled", not board.is_empty())

	var damage_contract: ContractData = null
	for contract in board:
		if contract.goal_key == &"deal_damage":
			damage_contract = contract
	if damage_contract == null:
		# The board is a random subset, so force the one this suite is about onto it.
		Progression.active_contracts()
		damage_contract = ItemDB.get_contract(&"daily_damage")
		if damage_contract:
			Progression._active_contracts.append(damage_contract.id)
	if damage_contract == null:
		_check("a damage contract exists", false)
		return

	var before := Progression.contract_progress(damage_contract.id)
	EventBus.contract_event.emit(&"deal_damage", 50)
	_check("progress tracks the event", Progression.contract_progress(damage_contract.id) == before + 50)
	_check("an unfinished contract cannot be claimed",
		not Progression.claim_contract(damage_contract.id))

	EventBus.contract_event.emit(&"deal_damage", damage_contract.target)
	_check("progress is capped at the target",
		Progression.contract_progress(damage_contract.id) == damage_contract.target)
	_check("a finished contract reports complete", Progression.is_contract_complete(damage_contract.id))

	var dollars_before := Economy.balance_of(Economy.DOLLARS)
	_check("claiming pays out", Progression.claim_contract(damage_contract.id))
	_check("in Dollars", is_equal_approx(Economy.balance_of(Economy.DOLLARS),
		dollars_before + float(damage_contract.reward_dollars)))
	_check("and cannot be claimed twice", not Progression.claim_contract(damage_contract.id))

	# A redrawn daily must come back clean. Clearing only the *departing* contracts was the
	# original bug and it was invisible: with four dailies and three slots a claimed one
	# reappears about three times in four, still flagged claimed — a full bar that pays
	# nothing, and one of three slots permanently dead.
	var reclaimed := ItemDB.get_contract(&"daily_petting")
	if reclaimed:
		if not Progression._active_contracts.has(reclaimed.id):
			Progression._active_contracts.append(reclaimed.id)
		EventBus.contract_event.emit(&"pet", reclaimed.target)
		_check("the petting contract completes", Progression.is_contract_complete(reclaimed.id))
		_check("and claims", Progression.claim_contract(reclaimed.id))
		Progression.refresh_contracts(true)
		_check("a redrawn daily is no longer flagged claimed",
			not Progression.is_contract_claimed(reclaimed.id))
		_check("and its progress is back to zero",
			Progression.contract_progress(reclaimed.id) == 0)

	# A generator must not finish a kindness contract unattended: sustained kindness is
	# deliberately not a contract event.
	var kindness_contract := ItemDB.get_contract(&"daily_kindness")
	if kindness_contract and not Progression._active_contracts.has(kindness_contract.id):
		Progression._active_contracts.append(kindness_contract.id)
	var kindness_before := Progression.contract_progress(&"daily_kindness")
	for i in 20:
		EventBus.kindness_sustained.emit(&"boombox", 1.0, Vector2.ZERO)
	_check("a generator's ticks do not tick a kindness contract",
		Progression.contract_progress(&"daily_kindness") == kindness_before)

## Reincarnation: the run goes, the meta stays, and he comes back somebody else.
func _prestige_resets_the_run_and_keeps_the_meta() -> void:
	_suite("reincarnation")
	# Marrow is scaled by the *run*, so the run has to be emptied before the "nothing to
	# gain" claim means anything — every suite above this one has been earning.
	Economy.run_earnings = 0.0
	_check("nothing to gain on a run that earned nothing",
		is_zero_approx(Economy.pending_marrow()))
	_check("and a reset is refused when there is nothing to gain",
		is_zero_approx(Economy.perform_prestige()))

	# Something equipped and something on the desk, so the wipe has work to do.
	EventBus.spawn_requested.emit(&"fist", Vector2.ZERO)
	EventBus.spawn_requested.emit(&"baseball_bat", Vector2(200, 100))
	var spawner_before := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	_check("a power is equipped before the reset",
		spawner_before == null or spawner_before.active_power() == &"fist")

	# A run worth resetting.
	Economy.grant(Economy.BONES, ItemDB.balance.marrow_divisor * 4.0)
	var pending := Economy.pending_marrow()
	_check("a big run is worth Marrow", pending > 0.0)
	_check("and there is no threshold to cross — it simply climbs",
		pending > EconomyMath.marrow_for_run(ItemDB.balance.marrow_divisor * 0.5,
			ItemDB.balance.marrow_divisor, ItemDB.balance.marrow_exponent))

	var lifetime_before := Economy.lifetime_of(Economy.BONES)
	var marrow_before := Economy.marrow
	var dollars_kept := Economy.balance_of(Economy.DOLLARS)
	var personality_before := Economy.personality
	var count_before := Economy.prestige_count

	var gained := Economy.perform_prestige()
	_check("the reset returns what it granted", is_equal_approx(gained, pending))
	_check("Marrow is kept and increased", is_equal_approx(Economy.marrow, marrow_before + gained))
	_check("and it multiplies income", Economy.marrow_multiplier() > 1.0)
	# Dollars are the meta currency now: a reset that confiscated the player's hat money
	# would make Reincarnating something to avoid.
	_check("Dollars survive the reset",
		is_equal_approx(Economy.balance_of(Economy.DOLLARS), dollars_kept))
	_check("but the run's earnings are back to nothing", is_zero_approx(Economy.run_earnings))
	_check("the prestige count went up", Economy.prestige_count == count_before + 1)
	_check("lifetime earnings survive",
		is_equal_approx(Economy.lifetime_of(Economy.BONES), lifetime_before))
	_check("Bones are wiped", Economy.balance_of(Economy.BONES) == 0.0)
	_check("Hearts are wiped", Economy.balance_of(Economy.HEARTS) == 0.0)
	_check("purchases are wiped", not Progression.is_unlocked(&"mace"))
	_check("mastery is wiped", Progression.mastery_pool() == 0)
	_check("automation is wiped",
		is_equal_approx(Progression.automation_rate_per_second(Economy.BONES), 0.0))
	_check("free starters are granted again", Progression.is_unlocked(&"baseball_bat"))
	_check("he is somebody new", Economy.personality != personality_before)
	_check("and the new personality exists",
		ItemDB.get_personality(StringName(Economy.personality)) != null)
	_check("Marrow multiplies all income", Economy.marrow_multiplier() > 1.0)

	# The desk has to be wiped along with the wallet. Progression forgetting the pistol while
	# ItemSpawner keeps it equipped left the player firing a weapon they no longer own, at
	# full damage and full payout, while the shop re-priced it as unowned.
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if spawner:
		_check("the equipped cursor power is unequipped by a reincarnation",
			spawner.active_power() == &"")
		_check("and the desk is cleared of spawned items", spawner.item_count() == 0)

	# Contracts are real-time, not run-scoped: resetting them would let a player farm a
	# daily by prestiging.
	_check("the contract board survives a reincarnation",
		not Progression.active_contracts().is_empty())

func _the_knockout_beat_runs_and_ends_upright() -> void:
	_suite("the knockout beat")
	var buddy := _buddy()
	if buddy == null:
		_check("buddy present", false)
		return

	_clear_spawned()
	buddy.health.reset_meter()
	var seen: Array[StringName] = []
	var record := func(state: StringName) -> void: seen.append(state)
	EventBus.buddy_state_changed.connect(record)

	buddy.health.apply_damage(ItemDB.balance.knockout_damage)
	_check("filling the meter knocks him out", buddy.health.down)

	# Wait the whole choreography out, with a ceiling so a beat that never finishes fails
	# the test instead of hanging the run.
	var b := ItemDB.balance
	var budget := b.knockout_collapse_time + b.knockout_downtime + b.knockout_reassemble_time + 2.0
	var deadline := Time.get_ticks_msec() + int(budget * 1000.0)
	while buddy.health.down and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	EventBus.buddy_state_changed.disconnect(record)

	_check("he gets back up", not buddy.health.down)
	for state in [&"knockout", &"pile", &"reassemble", &"idle"]:
		_check("the beat passes through '%s'" % state, seen.has(state))
	_check("collapse comes before the pile", seen.find(&"knockout") < seen.find(&"pile"))
	_check("the pile comes before reassembling", seen.find(&"pile") < seen.find(&"reassemble"))
	_check("and he ends up idle", seen[seen.size() - 1] == &"idle")

	_check("the meter is reset", buddy.health.damage == 0.0)
	_check("he is unfrozen and playable again", not buddy.freeze)
	_check("he ends upright", is_zero_approx(buddy.global_rotation))
	_check("and the squash is undone",
		buddy.sprite == null or buddy.sprite.scale.is_equal_approx(Vector2(2, 2)))

## The sponge is the whole dual-currency argument in one object: the cheapest Hearts item
## is what protects the Bones economy. Worth a real physics contact rather than a direct
## call, because "does it actually touch him" is the part that breaks.
func _the_sponge_cleans_him_and_pays() -> void:
	_suite("the sponge")
	var buddy := _buddy()
	if buddy == null:
		_check("buddy present", false)
		return

	_clear_spawned()
	Economy.grant(Economy.HEARTS, float(ItemDB.get_item(&"sponge").cost))
	_check("the sponge can be bought", Progression.purchase_item(&"sponge"))

	buddy.grime.set_value(1.0)
	buddy.health.reset_meter()
	var hearts_before := Economy.balance_of(Economy.HEARTS)
	EventBus.spawn_requested.emit(&"sponge", buddy.global_position)
	for i in 120:
		await get_tree().physics_frame

	_check("touching him with it removes grime", buddy.grime.value < 1.0)
	_check("and pays Hearts for what came off",
		Economy.balance_of(Economy.HEARTS) > hearts_before)
	_clear_spawned()
	buddy.grime.set_value(0.0)

func _buddy() -> Buddy:
	return get_tree().get_first_node_in_group(&"buddy") as Buddy

## The one piece that cannot be checked with a synthetic signal: whether
## _integrate_forces turns a real collision into a real HitInfo. This is the correction
## D7 exists for, so it is worth simulating rather than trusting.
## He walks over to his own toys and uses them. The one feature in the game that is entirely
## invisible unless you leave the room, which is exactly why it shipped broken twice: once
## because a running turret reset his idle timer forever, and once because the routine filter
## only recognised a single category. Neither failed a test, because there was no test.
##
## Stepped physics against real geometry. A headless viewport is 64x64, so nothing here may
## lean on WorldBounds — he is placed on the scene's own floor exactly as the contact-impulse
## suite does it.
## How many of one item are on the desk. Spawning is gated on ownership and silently does
## nothing when an item is not owned, which is a failure mode worth naming rather than
## discovering three assertions later.
func spawner_count_of(item_id: StringName) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"spawned_item"):
		if node is BaseDraggable and (node as BaseDraggable).item_id == item_id:
			count += 1
	return count

## An item's scene, instanced but never added to the tree — enough to ask a question about
## its switches. The caller frees it.
func _instance_of(item_id: StringName) -> BaseDraggable:
	var item := ItemDB.get_item(item_id)
	if item == null or item.scene == null:
		return null
	var body := item.scene.instantiate() as BaseDraggable
	if body:
		body.item_id = item_id
	return body

func _he_goes_and_plays_with_his_toys() -> void:
	_suite("idle brain — he goes and plays")
	var buddy := get_tree().get_first_node_in_group(&"buddy") as Buddy
	if buddy == null:
		_check("buddy present", false)
		return
	# `main.gd` installs the brain; this scene builds its own tree, so the suite installs one
	# the same way the game does. It finds its buddy through the group, so where it hangs
	# does not matter — which is the property that makes this possible at all.
	var brain := get_tree().get_first_node_in_group(&"idle_brain") as IdleBrain
	if brain == null:
		brain = IdleBrain.install(self)
		await get_tree().process_frame
	_check("the idle brain is installed", brain != null)
	if brain == null:
		return

	# The hands-on kind items pay per second of touch exactly as a beanbag does, and the
	# routine used to be chosen from that switch alone — so without `handheld` he would walk
	# over and try to sit in a feather duster. The sponge is the other edge: it now pays a
	# touching trickle too, and read in the wrong order it becomes a chair instead of a scrub.
	for id in [&"feather_duster", &"warm_towel"]:
		var body := _instance_of(id)
		_check("'%s' is not something he goes and uses" % id,
			body != null and brain._routine_for(body) == IdleBrain.ROUTINE_NONE)
		if body:
			body.free()
	var sponge := _instance_of(&"sponge")
	_check("the sponge is still a scrub, not a chair",
		sponge != null and brain._routine_for(sponge) == IdleBrain.ROUTINE_SCRUB)
	if sponge:
		sponge.free()
	var beanbag_body := _instance_of(&"beanbag")
	_check("and a beanbag is still somewhere he sits",
		beanbag_body != null and brain._routine_for(beanbag_body) == IdleBrain.ROUTINE_SOAK)
	if beanbag_body:
		beanbag_body.free()

	_clear_spawned()
	buddy.health.reset_meter()
	buddy.global_position = Vector2(200, 100)
	buddy.linear_velocity = Vector2.ZERO
	buddy.angular_velocity = 0.0
	for i in 90:
		await get_tree().physics_frame

	# A beanbag, well off to his **left**. Three deliberate choices:
	#
	#   Comfort, because that category did not exist when `_routine_for` was written and is
	#   exactly what would have gone silently unplayed had the filter stayed on
	#   CATEGORY_FRIENDLY.
	#   The beanbag specifically, because it is gated by price alone — the hot tub sits
	#   behind a requires chain, and a test that has to buy four things to reach the one it
	#   is testing breaks whenever the chain is re-authored.
	#   To the left, because that is the direction that exercises the face mirroring. His
	#   per-frame face offsets are authored for one facing, so walking left is the path that
	#   can put his face on the back of his head; walking right would prove nothing.
	Economy.grant(Economy.HEARTS, 10000.0)
	_check("the beanbag can be bought", Progression.purchase_item(&"beanbag"))
	var toy_x := buddy.global_position.x - 260.0
	EventBus.spawn_requested.emit(&"beanbag", Vector2(toy_x, 100.0))
	for i in 40:
		await get_tree().physics_frame
	_check("and it reaches the desk", spawner_count_of(&"beanbag") > 0)

	# **Pin Focus Mode, and put it back.** With it Off he is *designed* to skip the walk and
	# simply be there (D21: a player in a meeting keeps the income without the desktop
	# moving), so a run that inherits Off from the developer's own settings.cfg tests the one
	# path that has no travel in it — which is how this suite first came out green on every
	# assertion that mattered and still proved nothing.
	var focus_before := Settings.focus_intensity
	Settings.focus_intensity = Settings.Intensity.NORMAL

	# Spawning counts as the player being at the desk, so the pretend must come after it —
	# this is the same ordering that makes the feature look broken to anyone testing it by
	# putting things on the desk.
	brain.pretend_idle()
	brain.think_now()
	_check("he picks something to go and do (target '%s', phase '%s')"
		% [brain.target_id(), brain.phase_name()], brain.target_id() == &"beanbag")
	_check("and the routine is one he can actually perform",
		brain.current_routine() != 0)

	var started_at := buddy.global_position.x
	var hearts_before := Economy.balance_of(Economy.HEARTS)
	var closest := absf(toy_x - started_at)
	# Sampled *during* the walk, not after it. Facing is a property of travelling, and by the
	# time he has arrived he has usually slid a little past the middle of the beanbag and is
	# nudging back the other way — so a snapshot at the end asks about the correction rather
	# than the journey, and fails for a buddy who did everything right.
	var faced_left_while_walking := false
	for i in 420:
		await get_tree().physics_frame
		closest = minf(closest, absf(toy_x - buddy.global_position.x))
		if brain.phase_name() == &"travelling" and buddy.art and buddy.art.body \
				and buddy.art.body.flip_h:
			faced_left_while_walking = true

	# Distance closed, not "x increased": he can overshoot a target he is standing in, and
	# asserting on the raw coordinate would then fail for a buddy who did exactly the right
	# thing and slid past the middle of the tub.
	_check("he travels toward it (started %.0f px away, got within %.0f)"
		% [absf(toy_x - started_at), closest], closest < absf(toy_x - started_at) - 40.0)
	_check("he actually arrives (phase '%s')" % brain.phase_name(),
		brain.phase_name() == &"playing")
	_check("and being in it pays Hearts (+%.2f)"
		% (Economy.balance_of(Economy.HEARTS) - hearts_before),
		Economy.balance_of(Economy.HEARTS) > hearts_before)

	# The art half. He has no walk tag, so travel is carried by facing and a bob — and the
	# bob is a heartbeat that decays, so nothing can leave him bobbing on the spot.
	_check("he faced the way he was walking (left, so flipped)", faced_left_while_walking)

	# Autonomous damage must not stand him up. This is the M3.7-D fix, asserted through the
	# real signal rather than through the flag: a turret shooting him while he soaks is the
	# turret working, not the player coming back.
	var phase_before := brain.phase_name()
	EventBus.damage_dealt.emit(HitInfo.new(1.0, &"pellet_turret", buddy.global_position, 1.0))
	_check("a turret shooting him does not end his soak (was '%s', now '%s')"
		% [phase_before, brain.phase_name()], brain.phase_name() == phase_before)
	EventBus.damage_dealt.emit(HitInfo.new(1.0, &"baseball_bat", buddy.global_position, 1.0))
	_check("but the player swinging a bat does", brain.phase_name() == &"watching")

	Settings.focus_intensity = focus_before
	_clear_spawned()

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
	var buddy := _buddy()
	if buddy:
		buddy.mood.set_value(-42.0)
		buddy.grime.set_value(0.3)
	_check("save written", SaveManager.save_game())

	# Simulate a restart: wipe the live state, then load it back.
	Economy.from_save({})
	Progression.from_save({})
	if buddy:
		buddy.from_save({})
	_check("state actually cleared", Economy.balance_of(Economy.BONES) == 0.0)
	_check("and so is his mood", buddy == null or buddy.mood.value == 0.0)
	await get_tree().process_frame

	SaveManager.load_game()
	_check("Bones restored", is_equal_approx(Economy.balance_of(Economy.BONES), bones))
	_check("augment levels restored", Progression.augment_level(&"bat_damage") == damage_levels)
	_check("purchased items restored", Progression.is_unlocked(&"mace"))
	_check("starters still granted after a reload", Progression.is_unlocked(&"baseball_bat"))
	_check("modifier cache rebuilt from the loaded save",
		Progression.get_modifier(&"baseball_bat", &"payout_mult") > 1.0)
	# Mood and grime are the player's position in the two M3 loops. A save that drops them
	# hands back the U-curve's 0.6x trough at the start of every session.
	_check("his mood survived the restart", buddy == null or is_equal_approx(buddy.mood.value, -42.0))
	_check("his grime survived the restart", buddy == null or is_equal_approx(buddy.grime.value, 0.3))
	_check("and Economy's mirrors followed", is_equal_approx(Economy.mood, buddy.mood.value if buddy else 0.0))

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
