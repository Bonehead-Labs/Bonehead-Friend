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

func _build_page() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UIStyle.eyebrow("Arcade"))

	var intro := UIStyle.body("Everything here is played with Dollars, and pays in Dollars, "
		+ "time and hats. Nothing in this room pays income — Bones and Hearts are a garnish, "
		+ "and always will be.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(320, 0)
	add_child(intro)

	_build_boost_strip()

	for path in MACHINES:
		_add_machine(path)

	add_child(UIStyle.eyebrow("The back room"))
	# PrestigePanel instanced whole rather than reimplemented. It is a `PanelPage`, so nested
	# here it keeps every property that made it work as a tab: its bus handlers still defer
	# through `request_refresh()`, and `is_visible_in_tree()` — the question PanelPage asks —
	# now follows this page instead of its own. Its armed confirm still drops when the card
	# shuts, because `visibility_changed` propagates to children.
	var prestige := PrestigePanel.new()
	# Named explicitly. A control built in code comes out as `@VBoxContainer@31`, which no
	# test can find and nobody can read in the remote scene tree — and this one is looked up
	# by name by `ui_check`.
	prestige.name = "PrestigePanel"
	add_child(prestige)
	_prestige = prestige
	# A nested page's own `visible` flag is written by nobody. `panel_layer` sets it on each
	# registered page when the card switches, and this one is not registered — so it sat
	# flagged visible under a shut card, which is the exact discrepancy `ui_check` asserts
	# against (D28). Behaviour was already right, because `PanelPage` guards on
	# `is_visible_in_tree()`; the flag was simply lying, and a flag that lies is the thing
	# the original bug was made of. It is mirrored below instead.
	visibility_changed.connect(_mirror_prestige_visibility)
	_mirror_prestige_visibility()

## The Reincarnation page nested here, for the HUD's link to scroll to.
func prestige_panel() -> PrestigePanel:
	return _prestige

## Keeps the nested page's flag honest with the tree, so "is this page on screen" has one
## answer whichever way it is asked.
func _mirror_prestige_visibility() -> void:
	if _prestige:
		_prestige.visible = is_visible_in_tree()

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
	cabinet.theme_type_variation = &"Tile"
	add_child(cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	cabinet.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	header.add_child(UIStyle.icon(game.mark, UIStyle.GLYPH, UIStyle.DOLLARS))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	header.add_child(text)
	var title := UIStyle.label(game.display_name, UIStyle.NAME)
	title.theme_type_variation = &"NameLabel"
	text.add_child(title)
	var blurb := UIStyle.body(game.blurb)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(240, 0)
	text.add_child(blurb)

	# The well the machine draws itself into: a sunk panel, and a VBox inside it. Both are
	# needed. A `PanelContainer` lays every child into the same rect, so a machine with three
	# reels would stack them on top of each other; a bare `Control` lays out none of them at
	# all and they keep the zero size they were created with.
	var well := PanelContainer.new()
	well.theme_type_variation = &"Sunk"
	column.add_child(well)
	var host := VBoxContainer.new()
	host.name = "Body"
	host.add_theme_constant_override("separation", 4)
	# The cabinet is the same height spinning as it is idle. Without a reserved well the whole
	# page shifts under the cursor every time a machine draws a card.
	host.custom_minimum_size = Vector2(0, game.body_height)
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
	var readout := UIStyle.label("", UIStyle.LABEL, UIStyle.TEXT)
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
	play.custom_minimum_size = Vector2(104, 34)
	footer.add_child(play)
	# Hovering the key lifts the whole cabinet, the way a shop tile lifts with its price.
	UIMotion.hook(play, cabinet)

	# A Dictionary is a reference, so the lambdas below share this one rather than each
	# capturing a copy — the same property that makes a lambda's captured *int* useless.
	var machine := {
		"game": game, "cabinet": cabinet, "play": play, "price": price,
		"readout": readout, "mark": readout_mark,
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
	else:
		UIMotion.buzz(cabinet)
	# One save per completed play. A spin is a deliberate act a second or two apart, not the
	# per-hit firehose the rest of the economy runs on.
	EventBus.save_requested.emit()
	request_refresh()

## The prize, in the cabinet's readout: a mark and a line. The mark is what carries the
## meaning — roughly one player in twelve cannot use the colour difference the palette leans
## on — and the colour only reinforces it.
func _show_prize(machine: Dictionary, prize: ArcadeGame.Prize) -> void:
	var mark: StringName = &"cross"
	var colour := UIStyle.TEXT_DIM
	if prize.kind == ArcadeGame.Prize.DOLLARS:
		mark = &"dollar"
		colour = UIStyle.DOLLARS
	elif prize.kind == ArcadeGame.Prize.BOOST:
		mark = &"bolt"
		# Bones brown rather than the teal a boost's "everything is faster" reading suggests:
		# teal is the only cool colour in the skin and it is spent entirely on automation.
		colour = UIStyle.BONES
	elif prize.kind == ArcadeGame.Prize.GARNISH:
		mark = &"heart" if prize.currency == Economy.HEARTS else &"bone"
		colour = UIStyle.currency_colour(prize.currency)
	elif prize.kind == ArcadeGame.Prize.COSMETIC or prize.kind == ArcadeGame.Prize.BOON:
		mark = &"star"
		colour = UIStyle.HEARTS

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
