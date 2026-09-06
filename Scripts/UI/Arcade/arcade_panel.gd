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

## One live machine: its game, and every control on its cabinet the page repaints.
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

## The Rebirth page, nested here as the back-room machine. Held so its visibility flag can
## be kept in step with this page's.
var _prestige: PrestigePanel

## The room strip and the rooms. One machine on screen at a time, at the size a machine
## deserves: three cabinets stacked in a 520px card gave each a 132px wheel and 32px reels and
## put the third below the fold. Now every room gets the whole card and a tab, like the shop's
## categories, and the wardrobe and Reincarnation are rooms too.
const ROOM_WARDROBE := &"wardrobe"
const ROOM_REBIRTH := &"rebirth"
## Height reserved for a machine's well, in UI pixels: the same for every machine, so
## switching rooms never moves the footer under the cursor.
const STAGE_WELL := 270

var _room_strip: HBoxContainer
var _rooms: Dictionary = {}          ## id -> {"tab": Button, "view": Control}
var _room_order: Array[StringName] = []
var _current_room: StringName = &""

func _build_page() -> void:
	add_theme_constant_override("separation", 8)
	# One line, because every line above the stage is a line taken from the stage: the page
	# eyebrow and a two-line intro pushed the Play key under the fold of a 520px card.
	var intro := UIStyle.body("Dollars in, Dollars out. Nothing here pays income.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(320, 0)
	add_child(intro)

	_build_boost_strip()

	_room_strip = HBoxContainer.new()
	_room_strip.name = "Rooms"
	_room_strip.add_theme_constant_override("separation", 4)
	add_child(_room_strip)

	for path in MACHINES:
		_add_machine(path)

	_build_wardrobe()

	# PrestigePanel instanced whole rather than reimplemented. It is a `PanelPage`, so nested
	# here it keeps every property that made it work as a tab: its bus handlers still defer
	# through `request_refresh()`, and `is_visible_in_tree()` — the question PanelPage asks —
	# now follows this page instead of its own. Its armed confirm still drops when the card
	# shuts, because `visibility_changed` propagates to children.
	var back_room := VBoxContainer.new()
	back_room.name = "BackRoom"
	back_room.add_theme_constant_override("separation", 8)
	back_room.add_child(UIStyle.eyebrow("The back room"))
	var prestige := PrestigePanel.new()
	# Named explicitly. A control built in code comes out as `@VBoxContainer@31`, which no
	# test can find and nobody can read in the remote scene tree — and this one is looked up
	# by name by `ui_check`.
	prestige.name = "PrestigePanel"
	back_room.add_child(prestige)
	_prestige = prestige
	_add_room(ROOM_REBIRTH, "Rebirth", &"star", back_room)
	# A nested page's own `visible` flag is written by nobody. `panel_layer` sets it on each
	# registered page when the card switches, and this one is not registered — so it sat
	# flagged visible under a shut card, which is the exact discrepancy `ui_check` asserts
	# against (D28). Behaviour was already right, because `PanelPage` guards on
	# `is_visible_in_tree()`; the flag was simply lying, and a flag that lies is the thing
	# the original bug was made of. It is mirrored below instead.
	visibility_changed.connect(_mirror_prestige_visibility)
	_mirror_prestige_visibility()

	if not _room_order.is_empty():
		show_room(_room_order[0])

## A room: a tab on the strip and a view below it. Views are siblings; one is visible.
func _add_room(id: StringName, caption: String, mark: StringName, view: Control) -> void:
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.visible = false
	add_child(view)
	var tab := UIStyle.button(caption, UIStyle.MICRO)
	tab.name = "Room_%s" % id
	tab.theme_type_variation = &"IconTab"
	tab.toggle_mode = true
	tab.custom_minimum_size = Vector2(0, 30)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.set_icon(tab, UIStyle.glyph(mark))
	tab.pressed.connect(func() -> void: show_room(id))
	_room_strip.add_child(tab)
	_rooms[id] = {"tab": tab, "view": view}
	_room_order.append(id)

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
		UIMotion.page_in(_rooms[id]["view"] as Control)
	request_refresh()

func current_room() -> StringName:
	return _current_room

func room_ids() -> Array[StringName]:
	return _room_order

## The Reincarnation page nested here, for the HUD's link to scroll to.
func prestige_panel() -> PrestigePanel:
	return _prestige

# --- the wardrobe --------------------------------------------------------------

## Finishes and headphones for Dollars (docs/game-design.md § Cosmetics). The one thing in
## this room that is not a gamble: you see the colour, you pay the price, you wear it. Rows are
## built once from `ItemDB.all_cosmetics()` and refreshed by value.
var _wardrobe_rows: Dictionary = {}   ## cosmetic id -> {button, row}

func _build_wardrobe() -> void:
	var rail := ItemDB.all_cosmetics()
	if rail.is_empty():
		return
	var room := VBoxContainer.new()
	room.name = "WardrobeRoom"
	room.add_theme_constant_override("separation", 8)
	room.add_child(UIStyle.eyebrow("The wardrobe"))
	var blurb := UIStyle.body("How he looks, for Dollars. A finish never changes what he earns.")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(320, 0)
	room.add_child(blurb)
	var list := VBoxContainer.new()
	list.name = "Wardrobe"
	list.add_theme_constant_override("separation", 5)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.add_child(list)
	for cosmetic in rail:
		list.add_child(_make_wardrobe_row(cosmetic))
	_add_room(ROOM_WARDROBE, "Wardrobe", &"hand", room)

func _make_wardrobe_row(cosmetic: CosmeticData) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.theme_type_variation = &"Tile"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	# The swatch: the tint over ivory for a bone finish, over teal for headphones. Exactly the
	# box size, like every picture in the shell (D27), drawn rather than imported.
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(UIStyle.ICON_CANVAS, UIStyle.ICON_CANVAS)
	var fill := StyleBoxFlat.new()
	var base := Color(0.93, 0.90, 0.82) if cosmetic.slot == CosmeticData.SLOT_BONE else Color(0.16, 0.62, 0.62)
	fill.bg_color = Color(clampf(base.r * cosmetic.tint.r, 0.0, 1.0),
		clampf(base.g * cosmetic.tint.g, 0.0, 1.0), clampf(base.b * cosmetic.tint.b, 0.0, 1.0))
	fill.set_corner_radius_all(4)
	fill.border_width_bottom = 2
	fill.border_width_top = 2
	fill.border_width_left = 2
	fill.border_width_right = 2
	fill.border_color = UIStyle.EDGE
	swatch.add_theme_stylebox_override("panel", fill)
	row.add_child(swatch)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var title := UIStyle.label(cosmetic.display_name, UIStyle.NAME)
	title.theme_type_variation = &"NameLabel"
	text.add_child(title)
	var subtitle := UIStyle.label(cosmetic.description.to_upper(), UIStyle.MICRO, UIStyle.TEXT_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(200, 0)
	text.add_child(subtitle)

	var button := UIStyle.button("", UIStyle.LABEL)
	button.theme_type_variation = &"BuyButton"
	button.custom_minimum_size = Vector2(110, 34)
	button.pressed.connect(func() -> void: _on_wardrobe_pressed(cosmetic.id, row_panel, button))
	row.add_child(button)
	# Hovering the price nudges the swatch, the way a shop tile nudges the toy inside it.
	UIMotion.hook(button, row_panel, swatch)

	_wardrobe_rows[cosmetic.id] = {"button": button, "row": row_panel, "swatch": swatch,
		"colour": fill.bg_color}
	return row_panel

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

## One button, three meanings, like the shop's: buy it, wear it, or it is worn. A refusal is a
## reaction, not a silence.
func _on_wardrobe_pressed(id: StringName, row_panel: Control, button: Button) -> void:
	if Economy.is_wearing(id):
		return
	if Economy.owns_cosmetic(id):
		if Economy.wear_cosmetic(id):
			UIMotion.confirm(row_panel)
			_celebrate_wear(id)
			_refresh_wardrobe()
		return
	if not Economy.buy_cosmetic(id):
		UIMotion.buzz(button)
		return
	UIMotion.confirm(row_panel)
	EventBus.ui_spend.emit(Economy.DOLLARS, float(ItemDB.get_cosmetic(id).price_dollars),
		UIScale.screen_centre(button))
	# Bought is worn: nobody buys a colour to keep it in the drawer.
	Economy.wear_cosmetic(id)
	_celebrate_wear(id)
	_refresh_wardrobe()

func _refresh_wardrobe() -> void:
	for id in _wardrobe_rows:
		var cosmetic := ItemDB.get_cosmetic(id)
		if cosmetic == null:
			continue
		var controls: Dictionary = _wardrobe_rows[id]
		var button := controls["button"] as Button
		var row_panel := controls["row"] as PanelContainer
		if Economy.is_wearing(id):
			button.text = "Worn"
			UIStyle.set_icon(button, UIStyle.glyph(&"check"))
			button.disabled = true
			UIStyle.tint_button(button, UIStyle.TEXT_DIM)
			row_panel.theme_type_variation = &"TileHot"
		elif Economy.owns_cosmetic(id):
			button.text = "Wear"
			UIStyle.set_icon(button, UIStyle.glyph(&"hand"))
			button.disabled = false
			UIStyle.tint_button(button, UIStyle.TEXT)
			row_panel.theme_type_variation = &"Tile"
		else:
			button.text = UIStyle.format_amount(float(cosmetic.price_dollars))
			UIStyle.set_icon(button, UIStyle.glyph(&"dollar"))
			button.disabled = false
			var affordable := Economy.balance_of(Economy.DOLLARS) >= float(cosmetic.price_dollars)
			UIStyle.tint_button(button, UIStyle.DOLLARS if affordable else UIStyle.TEXT_DIM)
			row_panel.theme_type_variation = &"Tile"

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

	var cabinet := PanelContainer.new()
	cabinet.name = "Cabinet_%s" % game.name
	cabinet.theme_type_variation = &"Tile"
	_add_room(StringName(game.name), game.display_name, game.mark, cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	cabinet.add_child(column)

	# The machine's name is on its tab, so the header is its rules in one line beside its
	# mark — a second copy of the name was 24px of stage.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	header.add_child(UIStyle.icon(game.mark, UIStyle.GLYPH, UIStyle.DOLLARS))
	var blurb := UIStyle.body(game.blurb)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.custom_minimum_size = Vector2(240, 0)
	header.add_child(blurb)

	# The well the machine draws itself into: a sunk panel, and a VBox inside it. Both are
	# needed. A `PanelContainer` lays every child into the same rect, so a machine with three
	# reels would stack them on top of each other; a bare `Control` lays out none of them at
	# all and they keep the zero size they were created with.
	var well := PanelContainer.new()
	well.name = "Well"
	well.theme_type_variation = &"Sunk"
	column.add_child(well)
	var host := VBoxContainer.new()
	host.name = "Body"
	host.add_theme_constant_override("separation", 6)
	host.alignment = BoxContainer.ALIGNMENT_CENTER
	# The cabinet is the same height spinning as it is idle, and the same height as every
	# other room's — a machine gets the whole stage whether it fills it or not. Without a
	# reserved well the whole page shifts under the cursor every time a machine draws a card.
	host.custom_minimum_size = Vector2(0, maxi(game.body_height, STAGE_WELL))
	well.add_child(host)

	# The readout. A figure, so it is set in the display face — the body face draws 5 as a
	# rounded form that reads as an 8, and a prize is the one line on this page a player will
	# reread to check they got what they think they got.
	var readout_row := HBoxContainer.new()
	readout_row.add_theme_constant_override("separation", 6)
	column.add_child(readout_row)
	var readout_mark := UIStyle.icon(&"dollar", UIStyle.GLYPH, UIStyle.DOLLARS)
	readout_mark.visible = false
	readout_row.add_child(readout_mark)
	var readout := UIStyle.label("", UIStyle.NAME, UIStyle.TEXT)
	readout.theme_type_variation = &"Numeral"
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout_row.add_child(readout)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	column.add_child(footer)
	footer.add_child(UIStyle.icon(&"dollar", UIStyle.GLYPH, UIStyle.DOLLARS))
	var price := UIStyle.label("", UIStyle.LABEL, UIStyle.DOLLARS)
	price.theme_type_variation = &"Numeral"
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(price)
	var play := UIStyle.button(game.play_caption, UIStyle.LABEL)
	play.theme_type_variation = &"BuyButton"
	play.custom_minimum_size = Vector2(150, 44)
	footer.add_child(play)
	# Hovering the key lifts the whole cabinet, the way a shop tile lifts with its price.
	UIMotion.hook(play, cabinet)

	# A Dictionary is a reference, so the lambdas below share this one rather than each
	# capturing a copy — the same property that makes a lambda's captured *int* useless.
	var machine := {
		"game": game, "cabinet": cabinet, "play": play, "price": price,
		"readout": readout, "mark": readout_mark, "well": well,
	}
	_machines.append(machine)
	play.pressed.connect(func() -> void: _on_play(machine))
	game.finished.connect(func(prize: ArcadeGame.Prize) -> void: _on_finished(machine, prize))
	game.changed.connect(func() -> void: request_refresh())
	game.said.connect(func(line: String) -> void: _say(machine, line))
	# Last, and with the cabinet already in the tree: a machine that opens with an animation
	# needs `create_tween()` to have a tree to run in.
	game.build_body(host)

# --- playing ---------------------------------------------------------------

## The money goes out here and nowhere else. `spend()` deducts if it can and changes nothing
## if it cannot, which makes it the single gate — there is no path where a machine plays for
## free and none where it charges for itself.
func _on_play(machine: Dictionary) -> void:
	var game := machine["game"] as ArcadeGame
	if game.is_busy():
		return
	var cost := maxf(0.0, game.cost)
	if cost > 0.0:
		if not Economy.spend(Economy.DOLLARS, cost):
			UIMotion.buzz(machine["cabinet"] as Control)
			request_refresh()
			return
		# The coin leaves the key that was pressed and lands in the purse, exactly as a
		# purchase does. Presentation only: nothing may infer a play from this signal.
		EventBus.ui_spend.emit(Economy.DOLLARS, cost,
			UIScale.screen_centre(machine["play"] as Control))
	_say(machine, "")
	game.play()
	request_refresh()

## The one place in the arcade that mints anything.
##
## Every clamp in here exists because the machine that fills in a prize is not the thing that
## has to live with the economy afterwards. A table edited to be more generous is a normal
## afternoon's work; a table that can quietly pay a day's Hearts is the end of the kindness
## half of the game (D2, D32).
func _on_finished(machine: Dictionary, prize: ArcadeGame.Prize) -> void:
	var cabinet := machine["cabinet"] as Control
	_show_prize(machine, prize)

	if prize.kind == ArcadeGame.Prize.DOLLARS:
		if prize.amount > 0.0:
			Economy.grant(Economy.DOLLARS, prize.amount)
			# The same coin as a purchase, flying the other way — the contract board pays
			# this way too, and the only difference is the direction of the money.
			EventBus.ui_spend.emit(Economy.DOLLARS, 0.0, UIScale.screen_centre(cabinet))
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
		UIMotion.confirm(cabinet)
		UIMotion.flash(machine["readout"] as Control, Color(1.6, 1.8, 1.4), 0.6)
		UIMotion.punch(machine["readout"] as Control, 1.25)
		# Chips out of the well in the prize's colour — a handful for a win, a shower for a
		# jackpot or a boost. The one place in the shell that is allowed to celebrate loudly,
		# because the player just paid for the moment.
		var game := machine["game"] as ArcadeGame
		var big := prize.kind == ArcadeGame.Prize.BOOST \
			or (prize.kind == ArcadeGame.Prize.DOLLARS and prize.amount >= game.cost * 8.0)
		UIMotion.sparkle(machine["well"] as Control, _prize_colour(prize), 60 if big else 22,
			320.0 if big else 200.0)
	else:
		UIMotion.buzz(cabinet)
	# One save per completed play. A spin is a deliberate act a second or two apart, not the
	# per-hit firehose the rest of the economy runs on.
	EventBus.save_requested.emit()
	request_refresh()

## The prize, in the cabinet's readout: a mark and a line. The mark is what carries the
## meaning — roughly one player in twelve cannot use the colour difference the palette leans
## on — and the colour only reinforces it.
## The colour a prize wears everywhere it is shown: the readout, the chips.
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

func _show_prize(machine: Dictionary, prize: ArcadeGame.Prize) -> void:
	var mark: StringName = &"cross"
	var colour := _prize_colour(prize)
	if prize.kind == ArcadeGame.Prize.DOLLARS:
		mark = &"dollar"
	elif prize.kind == ArcadeGame.Prize.BOOST:
		mark = &"bolt"
	elif prize.kind == ArcadeGame.Prize.GARNISH:
		mark = &"heart" if prize.currency == Economy.HEARTS else &"bone"
	elif prize.kind == ArcadeGame.Prize.COSMETIC or prize.kind == ArcadeGame.Prize.BOON:
		mark = &"star"

	var rect := machine["mark"] as TextureRect
	rect.visible = true
	# Through `set_sprite`, never `rect.texture`: the well is 16px and the swap has to arrive
	# at exactly that size or the row grows around the picture (D27).
	UIStyle.set_sprite(rect, UIStyle.glyph(mark))
	rect.modulate = colour
	var readout := machine["readout"] as Label
	readout.text = prize.caption
	readout.add_theme_color_override("font_color", colour)

## A line from the machine between plays. No mark: the mark means a prize.
func _say(machine: Dictionary, line: String) -> void:
	(machine["mark"] as TextureRect).visible = false
	var readout := machine["readout"] as Label
	readout.text = line
	readout.add_theme_color_override("font_color", UIStyle.TEXT_DIM)

# --- repainting ------------------------------------------------------------

func _refresh() -> void:
	_refresh_wardrobe()
	var purse := Economy.balance_of(Economy.DOLLARS)
	for machine in _machines:
		var game := machine["game"] as ArcadeGame
		var cost := maxf(0.0, game.cost)
		var playable := purse >= cost and not game.is_busy()
		(machine["price"] as Label).text = UIStyle.format_amount(cost)

		var play := machine["play"] as Button
		play.text = game.play_caption
		play.disabled = not playable
		UIStyle.set_icon(play, UIStyle.glyph(&"dollar" if purse >= cost else &"lock"))
		UIStyle.tint_button(play, UIStyle.DOLLARS if purse >= cost else UIStyle.LOCKED)
		(machine["cabinet"] as PanelContainer).theme_type_variation = \
			&"TileHot" if playable else &"Tile"
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
