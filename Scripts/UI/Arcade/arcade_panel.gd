class_name ArcadePanel
extends PanelPage

## The Arcade: a room of machines played with Dollars, and the back room where the biggest
## gamble in the game lives.
##
## This page is the only thing in the arcade that mints anything. Machines describe an
## outcome (`ArcadeGame.Prize`) and this file grants it, clamps it to what a spin is allowed
## to be worth, and throws the coin at the purse. Three machines each calling `Economy.grant`
## would be three places for a bug that prints money.
##
## **What a prize may be** is decided, not open (docs/decisions.md D32): Dollars, a timed
## multiplier measured in minutes, a cosmetic, rarely a permanent boon — and Bones or Hearts
## only as a garnish, capped by `ArcadeGame.garnish_cap()`. The cap is the load-bearing part.
## A machine that can pay a real pile of Hearts makes the optimal line "farm Dollars, gamble
## for Hearts, skip being kind", and automation being Hearts-priced (D2) is the spine of the
## whole design.
##
## Reincarnation is the last machine on the page rather than a tab of its own. It is the
## biggest gamble in the game — hand back the entire run, take a number that multiplies every
## life after it — and a room full of machines is a better home for it than a tab called
## Rebirth that a player opens once and then avoids.
##
## **Every room is a cabinet** (D58): a lit marquee with the machine's name and the display it
## talks through, the stage, the paytable, and a deck holding the stake and the one key that
## matters. Same four sections, same order, same heights, in all five rooms — see `Cabinet`.

## The machines, in the order they stand in the room. The wheel is first because it is the
## cheapest to build and the fastest to read, so it is the one that survives if the milestone
## is cut (D32).
##
## Loaded by path rather than named as types, which is the one thing in this file that is not
## the house style. Three cabinets are authored independently of each other and of this page:
## a class name that has not arrived yet is an unresolved identifier, and an unresolved
## identifier is a parse error that cascades out of the UI and into a game that boots into
## nothing. A missing machine leaves a gap in the room instead. Case is exact — `res://` paths
## are case-sensitive in an exported build and resolve fine in the editor until they ship.
const MACHINES: Array[String] = [
	"res://Scripts/UI/Arcade/spin_wheel.gd",
	"res://Scripts/UI/Arcade/slot_machine.gd",
	"res://Scripts/UI/Arcade/blackjack.gd",
]

## Repaint interval for the boost countdown, in seconds. Fast enough that the seconds digit
## never looks stuck, slow enough that a page open for an hour is not a per-frame cost.
const CLOCK_STEP := 0.25

## One live machine: its game, its cabinet, and every control on it the page repaints.
var _machines: Array[Dictionary] = []

var _boost: PanelContainer
var _boost_value: Label
var _boost_time: Label
var _clock := 0.0

func _ready() -> void:
	EventBus.currency_changed.connect(func(_c: StringName, _b: float) -> void: request_refresh())
	# The boost strip counts down, so this is the one page in the shell with a clock. It runs
	# only while the page is genuinely on screen — driven off the visibility signal rather
	# than off `visible`, which a shut card leaves true on whichever page was open last (D28).
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(false)
	# Two things on this page change with no signal to listen for: a boost ticking down, and
	# Reincarnation's own figures. Re-read on every open rather than trusting the last paint.
	refresh_on_show = true
	super()
	# The card's scroll host, not this page: the page is never narrower than its own minimum,
	# so it cannot say how much room there really is. The host is sized by the card alone.
	var host := get_parent() as Control
	if host:
		host.resized.connect(_fit_stages)
	# And when the rule width changes with the Menu size (D68): the reel bank's fit counts its
	# rules, and the card can keep its size across the change.
	theme_changed.connect(_fit_stages)
	_fit_stages.call_deferred()

## Tells every machine how wide its stage is on this card. Everything else in a cabinet is laid
## out by containers; the reels are drawn at a whole-number box and pick the largest that fits.
## The scrollbar's width is always subtracted — it comes and goes with the page's height, and a
## machine sized as though it were absent would push the page sideways the moment it appeared.
func _fit_stages() -> void:
	var host := get_parent() as ScrollContainer
	if host == null or _machines.is_empty():
		return
	var width := host.size.x
	var bar := host.get_v_scroll_bar()
	if bar:
		width -= bar.get_combined_minimum_size().x
	for machine in _machines:
		var cabinet := machine["cabinet"] as Cabinet
		(machine["game"] as ArcadeGame).fit_stage(cabinet.stage_width_for(width))
	# And every cabinet's marquee and deck, the wardrobe's and the back room's too (D68).
	for id in _room_order:
		for cabinet in _cabinets_in(_rooms[id]["view"] as Node):
			cabinet.fit(width)

func _cabinets_in(root: Node) -> Array[Cabinet]:
	var found: Array[Cabinet] = []
	if root is Cabinet:
		found.append(root as Cabinet)
		return found
	for child in root.get_children():
		found.append_array(_cabinets_in(child))
	return found

## The Rebirth page, nested here as the back-room machine. Held so its visibility flag can
## be kept in step with this page's.
var _prestige: PrestigePanel

## The room strip and the rooms. One machine on screen at a time, at the size a machine
## deserves: three cabinets stacked in a 520px card gave each a 132px wheel and 32px reels and
## put the third below the fold. Every room gets the whole card and a key on the strip.
const ROOM_WARDROBE := &"wardrobe"
const ROOM_REBIRTH := &"rebirth"
## Height reserved for a machine's stage, in UI pixels: the same for every room, so switching
## rooms never moves the deck under the cursor. `Cabinet` owns the number.
const STAGE_WELL := Cabinet.STAGE

var _room_strip: HBoxContainer
var _rooms: Dictionary = {}          ## id -> {"tab": Button, "view": Control}
var _room_order: Array[StringName] = []
var _current_room: StringName = &""

func _build_page() -> void:
	add_theme_constant_override("separation", 8)
	# No intro line above the strip any more. Every line above the stage is a line taken from
	# it, and what the intro said — Dollars in, Dollars out — is what the deck and the display
	# now show on every play.
	_build_boost_strip()

	_room_strip = HBoxContainer.new()
	_room_strip.name = "Rooms"
	_room_strip.add_theme_constant_override("separation", ROOM_GAP)
	_room_strip.resized.connect(_fit_room_captions)
	add_child(_room_strip)

	for path in MACHINES:
		_add_machine(path)

	_build_wardrobe()

	# PrestigePanel instanced whole rather than reimplemented. It is a `PanelPage`, so nested
	# here it keeps every property that made it work as a tab: its bus handlers still defer
	# through `request_refresh()`, and `is_visible_in_tree()` — the question PanelPage asks —
	# now follows this page instead of its own. Its armed confirm still drops when the card
	# shuts, because `visibility_changed` propagates to children. It builds its own cabinet.
	var prestige := PrestigePanel.new()
	# Named explicitly. A control built in code comes out as `@VBoxContainer@31`, which no
	# test can find and nobody can read in the remote scene tree — and this one is looked up
	# by name by `ui_check`.
	prestige.name = "PrestigePanel"
	_prestige = prestige
	_add_room(ROOM_REBIRTH, "Rebirth", &"star", &"night", prestige)
	# A nested page's own `visible` flag is written by nobody else: `panel_layer` sets it on
	# each registered page when the card switches, and this one is not registered — so it sat
	# flagged visible under a shut card, which is the exact discrepancy `ui_check` asserts
	# against (D28). It is mirrored below.
	visibility_changed.connect(_mirror_prestige_visibility)
	_mirror_prestige_visibility()

	if not _room_order.is_empty():
		show_room(_room_order[0])

## A room: a key on the strip and a view below it. Views are siblings; one is visible.
##
## The key is a small machine of its own: its room's colour lit along the top, and the whole
## key lit in it when it is the room on screen — the same colour as the marquee under it.
func _add_room(id: StringName, caption: String, mark: StringName, accent: StringName,
		view: Control) -> void:
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.visible = false
	add_child(view)
	var tab := UIStyle.button(caption, UIStyle.MICRO)
	tab.name = "Room_%s" % id
	tab.theme_type_variation = UIStyle.room_tab_variation(accent)
	tab.toggle_mode = true
	tab.custom_minimum_size = Vector2(0, 36)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Five keys share the strip evenly, and give up their mark, then their word, before any is
	# clipped (`_fit_room_captions`, D68). Clipping stays as the backstop: never wider.
	tab.clip_text = true
	UIStyle.caption_key(tab, caption, UIStyle.glyph(mark))
	tab.pressed.connect(func() -> void: show_room(id))
	_room_strip.add_child(tab)

	# The lamp. A Button is not a Container, so it is anchored *and* given explicit offsets,
	# inside the key's rule — the same way the page tabs' badges are hung.
	var lamp := Panel.new()
	lamp.name = "Lamp"
	lamp.theme_type_variation = UIStyle.marquee_variation(accent)
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lamp.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hang_lamp(lamp)
	# Inside the key's rule, and the rule's width follows the Menu size (D68).
	lamp.theme_changed.connect(func() -> void: _hang_lamp(lamp))
	tab.add_child(lamp)

	_rooms[id] = {"tab": tab, "view": view}
	_room_order.append(id)

## The gap between two room keys.
const ROOM_GAP := 6

## Every room key is the strip's width shared out, so that is the width each caption has to fit
## (D68). At 2x on the default play area a key is 100px and "The Wheel" with its mark is 102.
func _fit_room_captions() -> void:
	var keys: Array = []
	for id in _room_order:
		keys.append(_rooms[id]["tab"])
	if keys.is_empty():
		return
	var share := (_room_strip.size.x - float(ROOM_GAP * (keys.size() - 1))) / float(keys.size())
	UIStyle.fit_captions(keys, floorf(share))

static func _hang_lamp(lamp: Control) -> void:
	var rule := float(UIStyle.rule_width())
	lamp.offset_left = rule
	lamp.offset_right = -rule
	lamp.offset_top = rule
	lamp.offset_bottom = rule + UITheme.ROOM_LAMP

## Bring one room forward. The others stay built and hidden — a spin still running in a room
## the player left keeps running and still pays.
func show_room(id: StringName) -> void:
	if not _rooms.has(id):
		return
	var changed := id != _current_room
	_current_room = id
	for key in _rooms:
		var room: Dictionary = _rooms[key]
		(room["view"] as Control).visible = key == id
		(room["tab"] as Button).set_pressed_no_signal(key == id)
	_mirror_prestige_visibility()
	if changed:
		var view := _rooms[id]["view"] as Control
		# A cabinet deals its sections in one after another; the back room deals its own.
		UIMotion.page_in((view as Cabinet).sections if view is Cabinet else view)
	request_refresh()

func current_room() -> StringName:
	return _current_room

func room_ids() -> Array[StringName]:
	return _room_order

## The Reincarnation page nested here, for the HUD's link to scroll to.
func prestige_panel() -> PrestigePanel:
	return _prestige

# --- the machines ------------------------------------------------------------

func _add_machine(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var machine_script := ResourceLoader.load(path) as GDScript
	if machine_script == null:
		push_warning("ArcadePanel: %s is not a script" % path)
		return
	var made: Object = machine_script.new()
	if not (made is ArcadeGame):
		push_warning("ArcadePanel: %s is not an ArcadeGame" % path)
		# Freed rather than dropped: it is a Node, so letting go of the only reference to it
		# leaks it for the life of the process and reports at exit as somebody else's bug.
		if made is Node:
			(made as Node).free()
		return
	var game := made as ArcadeGame
	game.name = path.get_file().get_basename()
	add_child(game)

	# The cabinet is the same height spinning as it is idle, and the same height as every
	# other room's — a machine gets the whole stage whether it fills it or not. Without a
	# reserved stage the whole page shifts under the cursor every time a machine draws a card.
	var cabinet := Cabinet.new(game.display_name, game.mark, game.accent,
		maxi(game.body_height, Cabinet.STAGE))
	cabinet.name = "Cabinet_%s" % game.name
	_add_room(StringName(game.name), game.display_name, game.mark, game.accent, cabinet)

	# The deck: the stake on the left, the machine's own keys and the main key on the right.
	var deck := cabinet.deck
	var less := Cabinet.key("−", 36)
	less.name = "StakeDown"
	deck.add_child(less)
	# The stake between its two keys, on one line: a caption, the coin, the figure. Wide enough
	# for the biggest rung's figure, so stepping never shoves the + key sideways.
	var plate := HBoxContainer.new()
	plate.name = "Stake"
	plate.add_theme_constant_override("separation", 5)
	plate.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.custom_minimum_size = Vector2(92, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck.add_child(plate)
	var caption := UIStyle.eyebrow("Stake")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(caption)
	var coin := UIStyle.icon(&"dollar", UIStyle.GLYPH, UIStyle.DOLLARS)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(coin)
	var price := UIStyle.label("", UIStyle.LABEL, UIStyle.DOLLARS)
	price.name = "StakeValue"
	price.theme_type_variation = &"Numeral"
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(price)
	var more := Cabinet.key("+", 36)
	more.name = "StakeUp"
	deck.add_child(more)
	# One rung is no choice at all: a stepper that can only say one number is hidden.
	less.visible = ArcadeGame.STAKES.size() > 1
	more.visible = less.visible
	cabinet.push_right()
	game.build_deck(cabinet)
	var play := Cabinet.key(game.play_caption, 124)
	play.name = "Play"
	deck.add_child(play)
	# Hovering the key lifts the stage, the way a shop tile lifts with its price: the machine
	# the Dollars are about to go into is the thing that reacts.
	UIMotion.hook(play, cabinet.stage)

	# A Dictionary is a reference, so the lambdas below share this one rather than each
	# capturing a copy — the same property that makes a lambda's captured *int* useless.
	var machine := {
		"game": game, "cabinet": cabinet, "play": play, "price": price,
		"less": less, "more": more,
	}
	_machines.append(machine)
	play.pressed.connect(func() -> void: _on_play(machine))
	less.pressed.connect(func() -> void: _on_stake(machine, -1))
	more.pressed.connect(func() -> void: _on_stake(machine, 1))
	game.finished.connect(func(prize: ArcadeGame.Prize) -> void: _on_finished(machine, prize))
	game.changed.connect(func() -> void: request_refresh())
	game.said.connect(func(line: String) -> void: cabinet.say(line))
	game.build_odds(cabinet)
	# Last, and with the cabinet already in the tree: a machine that opens with an animation
	# needs `create_tween()` to have a tree to run in.
	game.build_body(cabinet.stage_body)

# --- playing ---------------------------------------------------------------

func _on_stake(machine: Dictionary, delta: int) -> void:
	var game := machine["game"] as ArcadeGame
	if not game.step_stake(delta):
		UIMotion.buzz(machine["more"] if delta > 0 else machine["less"])
		return
	UIMotion.punch(machine["price"] as Control, 1.2)
	request_refresh()

## The money goes out here and nowhere else. `spend()` deducts if it can and changes nothing
## if it cannot, which makes it the single gate — there is no path where a machine plays for
## free and none where it charges for itself.
func _on_play(machine: Dictionary) -> void:
	var game := machine["game"] as ArcadeGame
	if game.is_busy():
		return
	var cost := maxf(0.0, game.stake())
	if cost > 0.0:
		if not Economy.spend(Economy.DOLLARS, cost):
			UIMotion.buzz(machine["play"] as Control)
			request_refresh()
			return
		# The coin leaves the key that was pressed and lands in the purse, exactly as a
		# purchase does. Presentation only: nothing may infer a play from this signal.
		EventBus.ui_spend.emit(Economy.DOLLARS, cost,
			UIScale.screen_centre(machine["play"] as Control))
	(machine["cabinet"] as Cabinet).say("")
	game.play()
	request_refresh()

## The one place in the arcade that mints anything.
##
## Every clamp in here exists because the machine that fills in a prize is not the thing that
## has to live with the economy afterwards. A table edited to be more generous is a normal
## afternoon's work; a table that can quietly pay a day's Hearts is the end of the kindness
## half of the game (D2, D32).
func _on_finished(machine: Dictionary, prize: ArcadeGame.Prize) -> void:
	var cabinet := machine["cabinet"] as Cabinet
	_show_prize(cabinet, prize)

	if prize.kind == ArcadeGame.Prize.DOLLARS:
		if prize.amount > 0.0:
			Economy.grant(Economy.DOLLARS, prize.amount)
			# The same coin as a purchase, flying the other way — the contract board pays
			# this way too, and the only difference is the direction of the money.
			EventBus.ui_spend.emit(Economy.DOLLARS, 0.0, UIScale.screen_centre(cabinet.stage))
	elif prize.kind == ArcadeGame.Prize.GARNISH:
		var cap := ArcadeGame.garnish_cap(prize.currency)
		var paid := clampf(prize.amount, 0.0, cap)
		if prize.amount > cap:
			push_warning("ArcadePanel: %s offered %s %s and was capped at %s (D32)"
				% [(machine["game"] as ArcadeGame).display_name,
					UIStyle.format_amount(prize.amount), prize.currency,
					UIStyle.format_amount(cap)])
		if paid > 0.0:
			Economy.grant(prize.currency, paid)
	elif prize.kind == ArcadeGame.Prize.BOOST:
		# Clamped again here, not only in `prize_boost()`: a machine can write the record by
		# hand, and the page is what pays.
		Economy.add_temp_multiplier(prize.effect_id,
			clampf(prize.multiplier, 1.0, ArcadeGame.BOOST_MAX_MULT),
			clampf(prize.seconds, 0.0, ArcadeGame.BOOST_MAX_SECONDS))
		_write_boost()
	elif prize.kind == ArcadeGame.Prize.COSMETIC or prize.kind == ArcadeGame.Prize.BOON:
		# Neither store exists yet — cosmetics are M3.5-B and the save has the slot reserved
		# and nothing that fills it; boons are the Séance's, unbuilt. Refused loudly rather
		# than paid into a void, because a hat the player watched themselves win and does not
		# own is worse than a machine that never offers one.
		push_warning("ArcadePanel: %s won '%s', which has nowhere to go yet"
			% [(machine["game"] as ArcadeGame).display_name, prize.id])

	if prize.is_win():
		UIMotion.confirm(cabinet.display)
		UIMotion.flash(cabinet.readout, Color(1.6, 1.8, 1.4), 0.6)
		UIMotion.punch(cabinet.readout, 1.25)
		# Chips off the stage in the prize's colour — a handful for a win, a shower for a
		# jackpot or a boost. The one place in the shell that is allowed to celebrate loudly,
		# because the player just paid for the moment.
		var game := machine["game"] as ArcadeGame
		var big := prize.kind == ArcadeGame.Prize.BOOST \
			or (prize.kind == ArcadeGame.Prize.DOLLARS and prize.amount >= game.stake() * 8.0)
		UIMotion.sparkle(cabinet.stage, _prize_colour(prize), 60 if big else 22,
			320.0 if big else 200.0)
	else:
		# "No" on the machine's own display, not on the whole cabinet: a 660px panel turned
		# by a few degrees is a lot of card moving for a lost spin.
		UIMotion.buzz(cabinet.display)
	# One save per completed play. A spin is a deliberate act a second or two apart, not the
	# per-hit firehose the rest of the economy runs on.
	EventBus.save_requested.emit()
	request_refresh()

## The colour a prize wears everywhere it is shown: the display, the chips.
func _prize_colour(prize: ArcadeGame.Prize) -> Color:
	if prize.kind == ArcadeGame.Prize.DOLLARS:
		return UIStyle.DOLLARS
	if prize.kind == ArcadeGame.Prize.BOOST:
		# Bones brown rather than the teal a boost's "everything is faster" reading suggests:
		# teal is the only cool colour in the skin and it is spent entirely on automation.
		return UIStyle.BONES
	if prize.kind == ArcadeGame.Prize.GARNISH:
		return UIStyle.currency_colour(prize.currency)
	if prize.kind == ArcadeGame.Prize.COSMETIC or prize.kind == ArcadeGame.Prize.BOON:
		return UIStyle.HEARTS
	return UIStyle.TEXT_DIM

## The prize, in the cabinet's display: a mark and a line.
func _show_prize(cabinet: Cabinet, prize: ArcadeGame.Prize) -> void:
	var mark: StringName = &"cross"
	if prize.kind == ArcadeGame.Prize.DOLLARS:
		mark = &"dollar"
	elif prize.kind == ArcadeGame.Prize.BOOST:
		mark = &"bolt"
	elif prize.kind == ArcadeGame.Prize.GARNISH:
		mark = &"heart" if prize.currency == Economy.HEARTS else &"bone"
	elif prize.kind == ArcadeGame.Prize.COSMETIC or prize.kind == ArcadeGame.Prize.BOON:
		mark = &"star"
	cabinet.show_prize(mark, prize.caption, _prize_colour(prize))

# --- the wardrobe --------------------------------------------------------------

## Finishes and headphones for Dollars (docs/game-design.md § Cosmetics). The one thing in
## this room that is not a gamble: you see the colour, you pay the price, you wear it.
##
## A cabinet like the others. The stage is two rails of swatches — every finish on one screen,
## where the old list of ten tall rows scrolled off the bottom of the card — and the deck is
## the one you picked: its colour, its name, and one key that buys it, wears it, or says it is
## worn. Keys are built once from `ItemDB.all_cosmetics()` and refreshed by value.
var _wardrobe_rows: Dictionary = {}   ## cosmetic id -> {key, state, mark, swatch, colour}
var _wardrobe: Cabinet
var _wardrobe_selected: StringName = &""
var _wardrobe_chip: ColorRect
var _wardrobe_name: Label
var _wardrobe_note: Label
var _wardrobe_action: Button

## The swatch on a wardrobe key, in UI pixels.
const SWATCH := Vector2(54, 34)

func _build_wardrobe() -> void:
	var rail := ItemDB.all_cosmetics()
	if rail.is_empty():
		return
	_wardrobe = Cabinet.new("The wardrobe", &"hand", &"rose")
	_wardrobe.name = "WardrobeRoom"

	var shelves := VBoxContainer.new()
	shelves.name = "Wardrobe"
	shelves.add_theme_constant_override("separation", 6)
	shelves.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wardrobe.stage_body.add_child(shelves)
	for slot in [CosmeticData.SLOT_BONE, CosmeticData.SLOT_PHONES]:
		shelves.add_child(UIStyle.eyebrow("His bones" if slot == CosmeticData.SLOT_BONE
			else "His headphones"))
		# A flow rather than a row: seven keys fit a rail on the 640px play area, and an eighth
		# finish, or a smaller card, wraps to a second line instead of widening the card for
		# every page in the shell (D22).
		var row := HFlowContainer.new()
		row.name = "Rail_%s" % slot
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shelves.add_child(row)
		for cosmetic in rail:
			if cosmetic.slot == slot:
				row.add_child(_make_swatch_key(cosmetic))

	_wardrobe.add_odds_prose("A finish never changes what he earns. One on his bones and one "
		+ "pair of headphones at a time.")

	# The deck: the chosen finish, large, and the one key.
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Glass"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wardrobe.deck.add_child(frame)
	_wardrobe_chip = ColorRect.new()
	_wardrobe_chip.name = "ChosenSwatch"
	_wardrobe_chip.custom_minimum_size = Vector2(38, 32)
	_wardrobe_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_wardrobe_chip)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wardrobe.deck.add_child(words)
	_wardrobe_name = UIStyle.label("", UIStyle.NAME)
	_wardrobe_name.theme_type_variation = &"NameLabel"
	words.add_child(_wardrobe_name)
	_wardrobe_note = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	_wardrobe_note.clip_text = true
	_wardrobe_note.custom_minimum_size = Vector2(200, 0)
	words.add_child(_wardrobe_note)
	_wardrobe_action = Cabinet.key("", 150)
	_wardrobe_action.name = "WardrobeAction"
	_wardrobe_action.pressed.connect(func() -> void: _on_wardrobe_pressed(_wardrobe_selected))
	_wardrobe.deck.add_child(_wardrobe_action)
	UIMotion.hook(_wardrobe_action, _wardrobe.stage)

	_add_room(ROOM_WARDROBE, "Wardrobe", &"hand", &"rose", _wardrobe)
	_select_cosmetic(Economy.worn_cosmetic(CosmeticData.SLOT_BONE))

## The colour a finish is shown in: the tint over ivory for a bone finish, over teal for
## headphones — the two surfaces the shader actually multiplies.
func _swatch_colour(cosmetic: CosmeticData) -> Color:
	var base := Color(0.93, 0.90, 0.82) if cosmetic.slot == CosmeticData.SLOT_BONE \
		else Color(0.16, 0.62, 0.62)
	return Color(clampf(base.r * cosmetic.tint.r, 0.0, 1.0),
		clampf(base.g * cosmetic.tint.g, 0.0, 1.0), clampf(base.b * cosmetic.tint.b, 0.0, 1.0))

## A key on a rail: the colour in a framed swatch, its name, and what it would cost you. A
## Button is not a Container, so what it holds is a column anchored inside its rule and given
## explicit offsets, and every piece of it lets the click through to the key.
func _make_swatch_key(cosmetic: CosmeticData) -> Button:
	var key := UIStyle.button("", UIStyle.MICRO)
	key.name = "Swatch_%s" % cosmetic.id
	key.theme_type_variation = &"DeckKey"
	key.toggle_mode = true
	key.custom_minimum_size = Vector2(72, 84)
	# The name is on the deck once a swatch is chosen, and here on hover. Seven keys share a
	# rail, and "Golden Bonehead" in a key this wide either clips from both ends or wraps to a
	# second line that pushes the price out through the bottom of the key.
	key.tooltip_text = cosmetic.display_name
	key.pressed.connect(func() -> void: _select_cosmetic(cosmetic.id))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6.0
	column.offset_right = -6.0
	column.offset_top = 6.0
	column.offset_bottom = -9.0
	key.add_child(column)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Glass"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(frame)
	var colour := _swatch_colour(cosmetic)
	var chip := ColorRect.new()
	chip.color = colour
	chip.custom_minimum_size = SWATCH
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(chip)

	var state_row := HBoxContainer.new()
	state_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_row.alignment = BoxContainer.ALIGNMENT_CENTER
	state_row.add_theme_constant_override("separation", 3)
	state_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(state_row)
	var mark := UIStyle.icon(&"dollar", UIStyle.GLYPH, UIStyle.DOLLARS)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state_row.add_child(mark)
	var state := UIStyle.label("", UIStyle.MICRO, UIStyle.DOLLARS)
	state.theme_type_variation = &"Numeral"
	state_row.add_child(state)

	_wardrobe_rows[cosmetic.id] = {"key": key, "state": state, "mark": mark, "swatch": frame,
		"colour": colour}
	return key

func _select_cosmetic(id: StringName) -> void:
	if not _wardrobe_rows.has(id):
		# Nothing worn in that slot yet, or a save naming a finish that has since been cut:
		# the first finish on the first rail is chosen, never nothing.
		if _wardrobe_rows.is_empty():
			return
		id = _wardrobe_rows.keys()[0]
	var changed := id != _wardrobe_selected
	_wardrobe_selected = id
	for key_id in _wardrobe_rows:
		(_wardrobe_rows[key_id]["key"] as Button).set_pressed_no_signal(key_id == id)
	if changed and _wardrobe_chip:
		UIMotion.punch(_wardrobe_chip.get_parent() as Control, 1.12)
	_refresh_wardrobe()

## Worn: chips off the swatch in the finish's own colour, and a shower of stars over him in
## the world — he is the thing that changed.
func _celebrate_wear(id: StringName) -> void:
	if not _wardrobe_rows.has(id):
		return
	var controls: Dictionary = _wardrobe_rows[id]
	UIMotion.sparkle(controls["swatch"] as Control, controls["colour"], 18, 220.0)
	var fx := get_tree().get_first_node_in_group(&"world_fx") as WorldFX
	var buddy := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Node2D
	if fx and buddy:
		fx.burst(buddy.global_position - Vector2(0, 40), &"star", controls["colour"], 14, 160.0, 0.9)

## One key, three meanings, like the shop's: buy it, wear it, or it is worn. A refusal is a
## reaction, not a silence.
func _on_wardrobe_pressed(id: StringName) -> void:
	var cosmetic := ItemDB.get_cosmetic(id)
	if cosmetic == null or Economy.is_wearing(id):
		return
	var key := (_wardrobe_rows[id]["key"] as Control) if _wardrobe_rows.has(id) else _wardrobe_action
	if Economy.owns_cosmetic(id):
		if Economy.wear_cosmetic(id):
			UIMotion.confirm(key)
			_celebrate_wear(id)
			_refresh_wardrobe()
		return
	if not Economy.buy_cosmetic(id):
		UIMotion.buzz(_wardrobe_action)
		return
	UIMotion.confirm(key)
	EventBus.ui_spend.emit(Economy.DOLLARS, float(cosmetic.price_dollars),
		UIScale.screen_centre(_wardrobe_action))
	# Bought is worn: nobody buys a colour to keep it in the drawer.
	Economy.wear_cosmetic(id)
	_celebrate_wear(id)
	_refresh_wardrobe()

func _refresh_wardrobe() -> void:
	if _wardrobe == null:
		return
	var purse := Economy.balance_of(Economy.DOLLARS)
	for id in _wardrobe_rows:
		var cosmetic := ItemDB.get_cosmetic(id)
		if cosmetic == null:
			continue
		var controls: Dictionary = _wardrobe_rows[id]
		var state := controls["state"] as Label
		var mark := controls["mark"] as TextureRect
		if Economy.is_wearing(id):
			_write_state(state, mark, "Worn", &"check", UIStyle.TEXT)
		elif Economy.owns_cosmetic(id):
			_write_state(state, mark, "Owned", &"hand", UIStyle.TEXT)
		else:
			var affordable := purse >= float(cosmetic.price_dollars)
			_write_state(state, mark, UIStyle.format_amount(float(cosmetic.price_dollars)),
				&"dollar" if affordable else &"lock",
				UIStyle.DOLLARS if affordable else UIStyle.TEXT_DIM)

	# The display says what he is wearing now, both slots, whatever is chosen on the rails.
	var worn: Array[String] = []
	for slot in [CosmeticData.SLOT_BONE, CosmeticData.SLOT_PHONES]:
		var on := ItemDB.get_cosmetic(Economy.worn_cosmetic(slot))
		if on:
			worn.append(on.display_name)
	_wardrobe.say("Wearing " + (" and ".join(worn) if not worn.is_empty() else "what he came in"),
		UIStyle.TEXT)

	var chosen := ItemDB.get_cosmetic(_wardrobe_selected)
	if chosen == null:
		return
	_wardrobe_chip.color = _swatch_colour(chosen)
	_wardrobe_name.text = chosen.display_name
	_wardrobe_note.text = chosen.description.to_upper()
	var action := _wardrobe_action
	if Economy.is_wearing(chosen.id):
		action.text = "Worn"
		UIStyle.set_icon(action, UIStyle.glyph(&"check"))
		action.disabled = true
		UIStyle.tint_button(action, UIStyle.TEXT_DIM)
	elif Economy.owns_cosmetic(chosen.id):
		action.text = "Wear"
		UIStyle.set_icon(action, UIStyle.glyph(&"hand"))
		action.disabled = false
		UIStyle.tint_button(action, UIStyle.TEXT)
	else:
		action.text = UIStyle.format_amount(float(chosen.price_dollars))
		UIStyle.set_icon(action, UIStyle.glyph(&"dollar"))
		action.disabled = false
		var affordable := purse >= float(chosen.price_dollars)
		UIStyle.tint_button(action, UIStyle.DOLLARS if affordable else UIStyle.TEXT_DIM)

func _write_state(state: Label, mark: TextureRect, text: String, glyph: StringName,
		colour: Color) -> void:
	state.text = text
	state.add_theme_color_override("font_color", colour)
	UIStyle.set_sprite(mark, UIStyle.glyph(glyph))
	mark.modulate = colour

## Keeps the nested page's flag honest with the tree, so "is this page on screen" has one
## answer whichever way it is asked.
func _mirror_prestige_visibility() -> void:
	if _prestige:
		_prestige.visible = is_visible_in_tree() and _current_room == ROOM_REBIRTH

## The live timed multiplier, wherever it came from — an arcade boost today, the Dream
## Journal and Overtime Pay later. It reads the one shared slot on `Economy`, so a second
## source needs no change here.
func _build_boost_strip() -> void:
	_boost = PanelContainer.new()
	_boost.name = "BoostStrip"
	_boost.theme_type_variation = &"Sunk"
	_boost.visible = false
	add_child(_boost)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_boost.add_child(row)
	row.add_child(UIStyle.icon(&"bolt", UIStyle.GLYPH, UIStyle.BONES))
	_boost_value = UIStyle.label("", UIStyle.LABEL, UIStyle.BONES)
	_boost_value.theme_type_variation = &"Numeral"
	row.add_child(_boost_value)
	var caption := UIStyle.eyebrow("all income")
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	_boost_time = UIStyle.label("", UIStyle.LABEL, UIStyle.TEXT)
	_boost_time.theme_type_variation = &"Numeral"
	row.add_child(_boost_time)

# --- repainting ------------------------------------------------------------

func _refresh() -> void:
	_refresh_wardrobe()
	var purse := Economy.balance_of(Economy.DOLLARS)
	for machine in _machines:
		var game := machine["game"] as ArcadeGame
		var cost := maxf(0.0, game.stake())
		var playable := purse >= cost and not game.is_busy()
		(machine["price"] as Label).text = UIStyle.format_amount(cost)
		(machine["less"] as Button).disabled = not game.can_step_stake(-1)
		(machine["more"] as Button).disabled = not game.can_step_stake(1)

		var play := machine["play"] as Button
		play.text = game.play_caption
		play.disabled = not playable
		UIStyle.set_icon(play, UIStyle.glyph(&"dollar" if purse >= cost else &"lock"))
		UIStyle.tint_button(play, UIStyle.DOLLARS if purse >= cost else UIStyle.LOCKED)
	_write_boost()

## The boost strip is a countdown, so it repaints on a clock rather than on a signal — and
## only while the page is on screen, which is what `set_process` is toggled for.
func _process(delta: float) -> void:
	_clock += delta
	if _clock < CLOCK_STEP:
		return
	_clock = 0.0
	_write_boost()

func _write_boost() -> void:
	if _boost == null:
		return
	var effects := Economy.temp_effects()
	_boost.visible = not effects.is_empty()
	if effects.is_empty():
		return
	# Longest first, so the strip counts down the one the player has most of left rather than
	# flickering between two.
	var longest: Dictionary = effects[0]
	_boost_value.text = "x%.2f" % Economy.temp_multiplier()
	var left := int(ceil(float(longest["seconds_left"])))
	_boost_time.text = "%d:%02d" % [left / 60, left % 60]
