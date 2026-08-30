class_name PurseStrip
extends VBoxContainer

## What you have to spend, wherever it needs saying.
##
## One class rather than two because the HUD and the shop header show the same three
## numbers, and the moment they are written twice they start disagreeing — one rounds, one
## truncates, one forgets Ectoplasm exists.
##
## Every figure is a glyph plus a number, never a letter plus a number. Bones and Hearts
## are the two most-read symbols in the game and about one player in twelve cannot use the
## colour difference between them (docs/art-direction.md), so the bone and the heart carry
## the meaning and the colour only reinforces it.
##
## **One currency per line.** Side by side, "157 ♥ 167" reads as a single quantity with a
## symbol in the middle of it — the eye groups the heart with the number on its left as
## readily as the one on its right, and no amount of spacing fixes that reliably. Stacked,
## each glyph owns the figure beside it and there is nothing to group wrongly.
##
## Stacking also buys the thing the genre is actually about: a figure with a whole line to
## itself can grow. It is printed with thousands separators for as long as it fits the card
## and abbreviated past that, so a big number stays a big number instead of collapsing into
## "1.20k" the moment it gets interesting.

## **Dollars first, and bigger.** They were last, in the order the currencies are earned,
## which was right when they were a prestige token nobody saw for eight hours and is wrong
## now: Dollars buy every cosmetic and everything in the arcade, and the owner's word for
## them is "a big focus". Bones and Hearts are what the game *does*; Dollars are what the
## player is *collecting*, and the purse should say so on sight.
const ORDER: Array[StringName] = [&"dollars", &"bones", &"hearts"]

## The one currency that gets its own line, centred, in the hero face — the treatment the
## rest of the shell reserves for the single number a page is about (UIStyle.HERO).
const HEADLINE := &"dollars"

const GLYPHS := {
	&"bones": &"bone",
	&"hearts": &"heart",
	&"dollars": &"dollar",
}

## Big enough that a Bones total is the loudest thing in the corner of the screen, because
## in an idle game it is the score.
@export var value_size: int = UIStyle.LABEL
## Whole-number multiples of the 16px glyph canvas only — `UIStyle.boxed()` will enlarge by
## 2x or 3x exactly, and anything else leaves it at 16 in a larger box.
@export var glyph_size: int = UIStyle.GLYPH
## Chips of their own, or bare figures? Boxed is for standing alone over the desktop;
## flat is for sitting inside a card that already has a rule around it — a chip inside a
## panel is two borders saying the same thing.
@export var boxed: bool = false

var _chips: Dictionary = {}     ## StringName -> PanelContainer
var _values: Dictionary = {}    ## StringName -> Label
var _shown: Dictionary = {}     ## StringName -> float, the figure currently on screen

func _ready() -> void:
	# Found by group rather than by path: the coin thrown by a purchase is launched from a
	# different CanvasLayer, and an absolute node path across scenes is banned for the
	# reason that shipped an export crash once already.
	add_to_group(&"purse")
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for currency in ORDER:
		add_child(_make_chip(currency))
	EventBus.currency_changed.connect(_on_currency_changed)
	for currency in ORDER:
		_snap(currency)
	_refresh_dollars()
	set_process(false)

func _make_chip(currency: StringName) -> Control:
	var headline := currency == HEADLINE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Centred rather than left-aligned, and only this one: a headline that shares the
	# stack's left rule is just a bigger version of the rows under it.
	if headline:
		row.alignment = BoxContainer.ALIGNMENT_CENTER

	var chip: Control = row
	if boxed:
		chip = PanelContainer.new()
		(chip as PanelContainer).theme_type_variation = &"Chip"
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(row)

	# Whole multiples of the 16px glyph canvas only: `UIStyle.boxed()` enlarges by 2x or 3x
	# exactly and leaves anything else at 16 inside a larger box (D27).
	var mark_size := glyph_size * 2 if headline else glyph_size
	var mark := UIStyle.icon(GLYPHS[currency], mark_size, UIStyle.currency_colour(currency))
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)

	var value := UIStyle.label("0", UIStyle.HERO if headline else value_size,
		UIStyle.currency_colour(currency))
	value.theme_type_variation = &"Numeral"
	# The figure owns the rest of the line and grows to the right. It cannot reflow anything
	# by getting longer, because there is nothing to its right to push — which is the other
	# half of why these are stacked rather than sitting in a row together. The headline is
	# the exception: it is centred, so it grows from the middle outwards and the mark beside
	# it travels — which is the point of centring it.
	value.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if headline \
		else Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if headline \
		else HORIZONTAL_ALIGNMENT_LEFT
	# **Not clipped on the headline.** `clip_text` tells a Label its minimum size does not
	# depend on its text — which is what keeps the stacked rows from widening the HUD, and
	# which on a SHRINK_CENTER control means a minimum width of zero. The centred figure
	# came out as a one-pixel sliver beside a large dollar sign. It does not need clipping
	# anyway: it is centred with nothing beside it to push, and `format_purse` already
	# abbreviates before it can get long.
	value.clip_text = not headline
	row.add_child(value)

	_chips[currency] = chip
	_values[currency] = value
	return chip

# --- rolling ---------------------------------------------------------------
#
# The figure eases toward the balance rather than jumping to it, which is what makes
# earning feel continuous instead of stepped. Done in `_process` rather than with a tween
# per change on purpose: currency_changed fires on every hit, and restarting a tween
# sixty times a second means the number never actually arrives.

## Below this the roll is over. A tenth of a Bone is not a visible difference and chasing
## it would leave `_process` running all session in a game with a 3% idle budget.
const SETTLE := 0.5
## Fraction of the remaining distance closed per second. Fast enough to feel responsive on
## a single purchase, slow enough to read as a count during a knockout payout.
const ROLL_RATE := 14.0

func _process(delta: float) -> void:
	var moving := false
	for currency in ORDER:
		var target := Economy.balance_of(currency)
		var shown := float(_shown.get(currency, target))
		if absf(target - shown) <= SETTLE:
			if shown != target:
				_write(currency, target)
			continue
		moving = true
		_write(currency, lerpf(shown, target, clampf(ROLL_RATE * delta, 0.0, 1.0)))
	if not moving:
		set_process(false)

func _write(currency: StringName, value: float) -> void:
	_shown[currency] = value
	var label := _values.get(currency) as Label
	if label:
		label.text = UIStyle.format_purse(value)

func _snap(currency: StringName) -> void:
	_write(currency, Economy.balance_of(currency))

func _on_currency_changed(currency: StringName, amount: float) -> void:
	if not _values.has(currency):
		return
	if currency == Economy.DOLLARS:
		_refresh_dollars()
	# A closed panel does not need to animate its numbers, but it does need to be correct
	# the instant it opens.
	if not is_visible_in_tree() or not UIMotion.enabled():
		_write(currency, amount)
		return
	set_process(true)

## Hidden until there is some. A third chip reading 0 is a permanent question the game has
## not answered yet — though with Dollars it answers itself within a minute of play, where
## Ectoplasm used to leave the chip dark for eight hours.
func _refresh_dollars() -> void:
	var chip := _chips.get(Economy.DOLLARS) as Control
	if chip:
		var had := chip.visible
		chip.visible = Economy.balance_of(Economy.DOLLARS) > 0.0
		if chip.visible and not had:
			UIMotion.punch(chip, 1.3)

# --- reactions -------------------------------------------------------------

## Where a coin thrown at this currency should land, in **screen** space — the thrower is
## on another CanvasLayer, and once a layer is scaled a canvas-space rect is the wrong
## answer by exactly that factor.
func chip_centre(currency: StringName) -> Vector2:
	var chip := _chips.get(currency) as Control
	if chip == null or not chip.is_visible_in_tree():
		chip = _chips.get(Economy.BONES) as Control
	return UIScale.screen_centre(chip) if chip else global_position

## The chip catching something. Called by whoever threw the coin, when it lands.
func catch(currency: StringName) -> void:
	var chip := _chips.get(currency) as Control
	if chip == null:
		return
	UIMotion.punch(chip, 1.18)
	UIMotion.flash(chip, Color(1.5, 1.4, 1.0), 0.35)
	set_process(true)
