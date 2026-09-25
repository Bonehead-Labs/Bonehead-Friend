class_name Cabinet
extends PanelContainer

## One room of the Arcade, built as a machine (docs/decisions.md D58).
##
## Every room — three machines, the wardrobe, the back room — is the same four sections in the
## same order, so a player who has read one cabinet can read all five:
##
##   marquee   the name, lit in the room's own colour, and the display it talks through
##   stage     the game itself, at one height every room shares
##   odds      how it pays, in figures
##   deck      the stake and the one thing to press
##
## **One frame, divided by rules.** The cabinet draws the only box; each section below the
## marquee owns the single rule across its top. The room this replaced was a tile holding a
## sunk well holding the machine — three nested frames of the same weight — and a player
## looking at it saw boxes rather than a machine.
##
## Only the chrome is built here. What goes on the stage, in the paytable and on the deck is
## the machine's business (`ArcadeGame`) or the page's; this class owns where each section
## sits and how tall the stage is, which is what keeps every room's deck at the same height on
## the card.

## The stage's content height, in UI pixels before `UIScale`. The same in every room, so
## switching rooms never moves the deck — and with it the main key — under the cursor. Set by
## the wheel, the tallest thing any machine draws (`WheelGame.FACE`).
const STAGE := 262
## Content height of the paytable strip. Tall enough for a 32px mark, which the slot machine
## prints its bat in: item art is 32px and a smaller box would step it down (D27).
const ODDS := 32
## The marquee's mark is a glyph boxed at twice its canvas: one art pixel to two screen
## pixels, whole-number crisp beside a 26px name.
const MARK_BOX := 32
## The display's minimum width. The readout inside it clips rather than grows (a single
## unwrapped Label would otherwise widen the card for every page in the shell, D22).
const DISPLAY_MIN := 240
## Every key on a deck is this tall, whatever it says, so a deck is one row of equal keys. It
## used to be a floor raised to cover a pressed key's extra margin as well — and 44 did not
## quite, so a deck still grew 2px when its keys went dead. A pressed key is now the size of the
## key at rest by construction (`UITheme._pressed`, D68), and this is only a height.
const KEY_HEIGHT := 44

var accent: StringName = &"gold"

var marquee: PanelContainer
var title: Label
var display: PanelContainer
var readout: Label
## The readout's mark. Shown only for a prize — the mark means a prize.
var readout_mark: TextureRect
var stage: PanelContainer
## What the machine builds into. A `VBoxContainer`, never a bare `Control`: a child of a plain
## Control is never laid out and keeps the zero size it was created with.
var stage_body: VBoxContainer
var odds: HBoxContainer
var deck: HBoxContainer
var sections: VBoxContainer

func _init(caption: String = "", mark: StringName = &"star", accent_id: StringName = &"gold",
		stage_height: int = STAGE) -> void:
	accent = accent_id
	theme_type_variation = &"Cabinet"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	sections = VBoxContainer.new()
	sections.name = "Sections"
	sections.add_theme_constant_override("separation", 0)
	add_child(sections)

	_build_marquee(caption, mark)

	stage = _section("Stage", &"Stage")
	stage_body = VBoxContainer.new()
	stage_body.name = "Body"
	stage_body.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_body.add_theme_constant_override("separation", 6)
	stage_body.custom_minimum_size = Vector2(0, stage_height)
	stage_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(stage_body)

	# The paytable is a row of cells that can be wider than a small card, and a row that is
	# wider than the card does not overflow — it widens the card for every page in the shell
	# (D22). So the row hangs in a plain clipping Control that reports no width of its own: on
	# a small card the last cell is cut off rather than the whole page pushed sideways. A child
	# of a plain Control is never laid out, so the row is anchored to it and the window's height
	# follows the row's.
	var strip := _section("OddsStrip", &"OddsStrip")
	var window := Control.new()
	window.name = "OddsWindow"
	window.clip_contents = true
	window.custom_minimum_size = Vector2(0, ODDS)
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(window)
	odds = HBoxContainer.new()
	odds.name = "Odds"
	odds.add_theme_constant_override("separation", 6)
	odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	odds.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(odds)
	odds.minimum_size_changed.connect(func() -> void:
		window.custom_minimum_size.y = maxf(ODDS, odds.get_combined_minimum_size().y))

	var controls := _section("Deck", &"Deck")
	deck = HBoxContainer.new()
	deck.name = "Controls"
	deck.add_theme_constant_override("separation", 6)
	controls.add_child(deck)

## How wide the stage's content is when the cabinet is `outer` wide: the frame's margins and
## the stage's, read off the theme rather than repeated here.
func stage_width_for(outer: float) -> float:
	var frame := get_theme_stylebox("panel")
	var inner := stage.get_theme_stylebox("panel")
	if frame == null or inner == null:
		return outer
	return outer - frame.get_margin(SIDE_LEFT) - frame.get_margin(SIDE_RIGHT) \
		- inner.get_margin(SIDE_LEFT) - inner.get_margin(SIDE_RIGHT)

func _section(node_name: String, variation: StringName) -> PanelContainer:
	var section := PanelContainer.new()
	section.name = node_name
	section.theme_type_variation = variation
	sections.add_child(section)
	return section

func _build_marquee(caption: String, mark: StringName) -> void:
	marquee = _section("Marquee", UIStyle.marquee_variation(accent))
	var ink := UIStyle.marquee_ink(accent)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marquee.add_child(row)
	row.add_child(UIStyle.icon(mark, MARK_BOX, ink))
	# The display face, in capitals: a sign, not a sentence.
	title = UIStyle.label(caption.to_upper(), UIStyle.TITLE, ink)
	title.name = "Title"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	# The display takes the rest of the marquee: a machine says longer things than it has
	# names for ("Two alike hands half your stake back.").
	display = PanelContainer.new()
	display.name = "Display"
	display.theme_type_variation = &"Display"
	display.custom_minimum_size = Vector2(DISPLAY_MIN, 0)
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(display)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(line)
	readout_mark = UIStyle.icon(&"dollar", UIStyle.GLYPH, UIStyle.DOLLARS)
	readout_mark.name = "ReadoutMark"
	readout_mark.visible = false
	readout_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(readout_mark)
	# A figure as often as not, so the display face — the body face draws 5 as a rounded
	# form that reads as an 8, and a prize is the line a player rereads to check it (D20).
	readout = UIStyle.label("", UIStyle.NAME, UIStyle.TEXT_DIM)
	readout.name = "Readout"
	readout.theme_type_variation = &"Numeral"
	readout.clip_text = true
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(readout)

## A line in the display. No mark: the mark means a prize.
func say(text: String, colour: Color = UIStyle.TEXT_DIM) -> void:
	readout_mark.visible = false
	readout.text = text
	readout.add_theme_color_override("font_color", colour)

## A prize in the display: its mark and its line, both in the prize's colour. The mark is
## what carries the meaning — roughly one player in twelve cannot use the colour difference.
func show_prize(mark: StringName, text: String, colour: Color) -> void:
	readout_mark.visible = true
	# Through `set_sprite`, never `.texture`: the swap has to arrive at exactly the box size or
	# the display grows around the picture (D27).
	UIStyle.set_sprite(readout_mark, UIStyle.glyph(mark))
	readout_mark.modulate = colour
	readout.text = text
	readout.add_theme_color_override("font_color", colour)

# --- the paytable ------------------------------------------------------------
#
# Cells in a row, divided by rules, the way a paytable is printed on the glass. Every figure
# in the display face (D20); a cell's mark is boxed at its own size and never stepped (D27).

## One cell: a mark, a figure, and optionally a quieter note after it ("53%", "x300").
func add_odds(mark: StringName, text: String, ink: Color, note: String = "",
		mark_box: int = UIStyle.GLYPH) -> HBoxContainer:
	var cell := _cell()
	if mark != &"":
		cell.add_child(UIStyle.icon(mark, mark_box, ink))
	var what := UIStyle.label(text, UIStyle.LABEL, ink)
	what.theme_type_variation = &"Numeral"
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(what)
	if note != "":
		var quiet := UIStyle.label(note, UIStyle.LABEL, UIStyle.TEXT_DIM)
		quiet.theme_type_variation = &"Numeral"
		quiet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(quiet)
	return cell

## A cell holding pictures rather than a glyph — the slot machine's item art. `textures` are
## drawn at exactly `box` each, and `box` must be one the art divides into (D27).
func add_odds_art(textures: Array, colours: Array, box: int, text: String, ink: Color) -> HBoxContainer:
	var cell := _cell()
	for i in textures.size():
		var picture := UIStyle.sprite(textures[i] as Texture2D, box)
		picture.modulate = colours[i] if i < colours.size() else Color.WHITE
		picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(picture)
	var what := UIStyle.label(text, UIStyle.LABEL, ink)
	what.theme_type_variation = &"Numeral"
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(what)
	return cell

## A named figure: a mark, a small-caps caption, and the value ("MARROW 0.00 → 1.40").
func add_odds_figure(mark: StringName, caption: String, value: String, ink: Color) -> HBoxContainer:
	var cell := _cell()
	var icon := UIStyle.icon(mark, UIStyle.GLYPH, ink)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(icon)
	var heading := UIStyle.eyebrow(caption)
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(heading)
	var figure := UIStyle.label(value, UIStyle.LABEL, ink)
	figure.theme_type_variation = &"Numeral"
	figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(figure)
	return cell

## Empties the strip for a room whose paytable changes shape. Detached at once rather than
## only queued for freeing, or the stale cells still count and the next cell gets a rule in
## front of it.
func clear_odds() -> void:
	for child in odds.get_children():
		odds.remove_child(child)
		child.queue_free()

## A heading at the head of the strip ("THREE ALIKE").
func add_odds_heading(text: String) -> Label:
	_divide()
	var heading := UIStyle.eyebrow(text)
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	odds.add_child(heading)
	return heading

## A sentence instead of cells, for a room whose paytable is a rule rather than a table.
func add_odds_prose(text: String) -> Label:
	_divide()
	var line := UIStyle.body(text)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.custom_minimum_size = Vector2(240, 0)
	odds.add_child(line)
	return line

func _cell() -> HBoxContainer:
	_divide()
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 5)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	odds.add_child(cell)
	return cell

## A rule before every cell but the first.
func _divide() -> void:
	if odds.get_child_count() > 0:
		odds.add_child(UIStyle.rule(true))

# --- the deck ----------------------------------------------------------------

## A key on the deck, in the deck's own variation.
static func key(caption: String, width: int = 120) -> Button:
	var button := UIStyle.button(caption, UIStyle.LABEL)
	# Named from the caption for the remote tree and the tests; a key whose caption is written
	# later is named by its caller.
	if caption.strip_edges() != "":
		button.name = caption.replace(" ", "")
	button.theme_type_variation = &"DeckKey"
	button.custom_minimum_size = Vector2(width, KEY_HEIGHT)
	return button

## Space that pushes everything after it to the right-hand end of the deck.
func push_right() -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck.add_child(spacer)
