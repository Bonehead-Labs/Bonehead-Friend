class_name UIStyle
extends RefCounted

## The Bonecard palette, the type scale, and the glyph set — the vocabulary every panel
## is written in.
##
## `UITheme` turns this into the actual `Theme` resource; this file is the source of the
## numbers, so a colour or a size is changed in exactly one place. Nothing here builds a
## widget's whole look inline any more: a panel asks for a *role* ("Card", "Tile") and the
## theme answers.
##
## Bonecard is the skin chosen at the end of M3 from four candidates: cream card stock,
## hard black 3px rules, no rounded corners, and colour used only where it carries meaning.
## Full rationale and the rejected skins are in `docs/art-direction.md`.

# --- surfaces --------------------------------------------------------------
#
# Fully opaque, not nearly. The window is per-pixel transparent, so any alpha below 1 lets
# the player's wallpaper through the UI — panels have to be opaque (docs/decisions.md D6)
# or text is read against whatever happens to be on the desktop. Motion may fade small
# controls that sit *on* a card; it must never fade the card.
const PANEL := Color("fcfcee")       ## Card stock. The ground for everything.
const RAISED := Color("f0eedc")      ## A tile sitting on the card.
const SUNK := Color("dfdcc6")        ## A track, a well, a disabled tile.
const EDGE := Color("000000")        ## Every rule in the UI is this, at BORDER_WIDTH.
const TEXT := Color("17140e")
const TEXT_DIM := Color("655f4c")

## Three pixels, everywhere, unscaled. The whole skin reads as printed card because the
## rules never get thinner or softer — a 1px hairline somewhere would look like a mistake.
const BORDER_WIDTH := 3

# --- meaning ---------------------------------------------------------------
#
# Colour is never the only signal. Each of these is paired with a glyph or a shape in the
# UI that uses it, because roughly one player in twelve cannot use the red/green
# distinction these lean on (docs/art-direction.md).
## Every one of these is dark enough to clear 4.5:1 against `SUNK`, the darkest surface any
## of them is ever printed on. That is not a nicety — the first pass picked them by eye and
## Bones came out at 2.97:1 on a sunk well, which is a price the player cannot read. The
## `contrast` suite in `loop_check` asserts the whole grid, so the next colour picked by eye
## fails a test rather than shipping.
const BONES := Color("805630")
const HEARTS := Color("a33860")
## Dollars. The same green Ectoplasm used, kept deliberately: it was picked to pass the
## contrast grid on every surface in the shell, and money is green anyway.
const DOLLARS := Color("276b4e")
const AFFORDABLE := Color("276b4e")  ## Same green as Ectoplasm: "you can have this".
const LOCKED := Color("a33860")      ## Same red as Hearts: "you cannot, yet".
const TEAL := Color("176a67")        ## Automation — the only cool colour in the set.

## Legacy aliases. The M2 shell was written against a dark skin and these names are
## threaded through the HUD and the panels; keeping them pointed at the new surfaces made
## the reskin a palette change rather than a rename across six files.
const BG := PANEL
const BG_RAISED := RAISED
const BORDER := EDGE

# --- type ------------------------------------------------------------------
#
# One family at two pixel weights: **Jersey 25** for display and **Jersey 15** for reading.
# They are the same face drawn on a coarser and a finer pixel grid, which is why they pair
# without looking like two fonts.
#
# This replaces Silkscreen + Pixelify Sans, which failed on their own terms in a playtest.
# Silkscreen is caps-only, so every label shouted. Pixelify Sans draws 5 as a rounded form
# that reads as an 8 — "+15% damage" was indistinguishable from "+18%" — and neither was
# comfortable to read at the size the panels use. Jersey has real lowercase, unambiguous
# digits, and is condensed, so more of a description fits on a line.
const FONT_DISPLAY := "res://Assets/fonts/Jersey25-Regular.ttf"
const FONT_DISPLAY_LIGHT := "res://Assets/fonts/Jersey15-Regular.ttf"
const FONT_BODY := "res://Assets/fonts/Jersey15-Regular.ttf"
const FONT_BODY_BOLD := "res://Assets/fonts/Jersey25-Regular.ttf"

## Neither face covers CJK, and the game ships in Simplified Chinese, Japanese and Korean.
## DotGothic16 does, in the same pixel idiom — so a missing glyph is a pixel glyph rather
## than a box or an incongruous system serif.
const FONT_CJK := "res://Assets/fonts/DotGothic16-Regular.ttf"

## Chosen by measured cap height, not by eye. The ladder they replace was 8/10/13/18 px of
## capital, and 1x was reported as too small to read; these are about a quarter taller,
## which is a deliberate step and not a guess. (The first attempt at this doubled it, and
## the panel ate the whole window.)
##
##   size  16  20  26  32
##   cap   11  12  16  20
const MICRO := 16    ## Eyebrows, units, the small print on a tile.
const LABEL := 20    ## Buttons, prices, counters — the default.
const TITLE := 26    ## A page heading.
const HERO := 32     ## The one number a page is about.

## Body sizes (Jersey 15): cap 8 and 10 px.
const BODY := 16     ## Descriptions and explanations.
const NAME := 20     ## An item or node's own name.

# --- glyphs ----------------------------------------------------------------
#
# Drawn by `art/tools/make_ui_glyphs.py`, white on transparent so one texture serves every
# tint. Shape, not colour, is what separates a bone from a heart.
const GLYPH_DIR := "res://Assets/sprites/ui"

static var _glyphs: Dictionary = {}

static func glyph(id: StringName) -> Texture2D:
	if _glyphs.has(id):
		return _glyphs[id]
	var path := "%s/%s.png" % [GLYPH_DIR, id]
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		push_warning("UIStyle: no glyph at %s" % path)
	_glyphs[id] = texture
	return texture

## The glyph for a currency id, so a price row never has to know which one it is showing.
static func currency_glyph(currency: StringName) -> Texture2D:
	match currency:
		&"hearts": return glyph(&"heart")
		&"dollars": return glyph(&"dollar")
		_: return glyph(&"bone")

static func currency_colour(currency: StringName) -> Color:
	match currency:
		&"hearts": return HEARTS
		&"dollars": return DOLLARS
		_: return BONES

# --- widget helpers --------------------------------------------------------
#
# Thin on purpose. Anything that is a *look* belongs in the theme; these only exist to
# save four lines at a call site.

static func label(text: String, size: int = LABEL, colour: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Reading text: sentences, descriptions, anything with lowercase in it.
static func body(text: String, size: int = BODY, colour: Color = TEXT_DIM) -> Label:
	var l := label(text, size, colour)
	l.theme_type_variation = &"BodyLabel"
	return l

## An all-caps rule-line heading. Letter-spaced, because Silkscreen set tight in caps
## reads as one long word.
static func eyebrow(text: String, colour: Color = TEXT_DIM) -> Label:
	var l := label(text.to_upper(), MICRO, colour)
	l.theme_type_variation = &"Eyebrow"
	return l

static func button(text: String, size: int = LABEL) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	UIMotion.hook(b)
	return b

## A picture at exactly one screen pixel per art pixel, in a box of a known size.
##
## `STRETCH_KEEP_CENTERED`, never `KEEP_ASPECT_CENTERED`: the aspect-fitting modes scale
## the texture to whatever rect the layout hands them, and a 32px icon stretched to fill a
## 44px well is pixel art at 1.375x — every third row of pixels doubled, which is the exact
## look the whole art pipeline exists to avoid. The box is the layout's business; the
## picture inside it is drawn at its native size and centred.
## A glyph in a box. The texture is delivered at exactly the box size (see the size
## contract below), so a 16px glyph asked for at 13 is stepped and centred rather than
## drawn 3px outside the space that was reserved for it.
static func icon(id: StringName, box: int = 16, colour: Color = TEXT) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = boxed(glyph(id), box)
	rect.custom_minimum_size = Vector2(box, box)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.modulate = colour
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## An item's own art in a fixed well. Sprites are authored to the scale table
## (docs/art-direction.md), so a mace really is bigger than a grenade here — the well is
## constant, the picture inside it is not, and that difference is the point.
## Item art in a well. Same contract as `icon()`: whatever goes in, a box-sized texture
## comes out, so the well is the size the layout reserved and never the size of the PNG.
## Assign through `set_sprite()` rather than writing `.texture` directly, or the contract
## is bypassed.
static func sprite(texture: Texture2D, box: int = 44) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = boxed(texture, box)
	rect.custom_minimum_size = Vector2(box, box)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## Swaps the picture in a well built by `sprite()`, keeping the size contract. Writing
## `rect.texture` directly is the one way to reintroduce the whole class of bug, so every
## live swap goes through here.
## The one way a Button gets a picture (D27). A Button *grows* to fit its icon, so the texture
## is boxed to the size the row was laid out for first — one oversized PNG once doubled a
## shop row's height. `box` defaults to a glyph; pass the row's own icon size otherwise.
static func set_icon(button: Button, texture: Texture2D, box: int = GLYPH) -> void:
	button.icon = boxed(texture, box) if texture else null

static func set_sprite(rect: TextureRect, texture: Texture2D) -> void:
	if rect == null:
		return
	rect.texture = boxed(texture, int(rect.custom_minimum_size.x))

## A level pip. Not a bare rectangle: an unfilled pip painted SUNK on a RAISED tile is
## 1.18:1 — invisible — and the contrast suite never caught it because it grades text inks
## against surfaces and a pip is neither. It gets the same hard EDGE outline every other
## mark in the UI has, which is 15:1 on any surface in the palette, so the *count* reads
## even where the fill does not. The fill then only has to separate full from empty, and
## BONES on SUNK is 4.6:1.
static var _pip_boxes: Dictionary = {}

static func pip_box(filled: bool) -> StyleBoxFlat:
	if _pip_boxes.has(filled):
		return _pip_boxes[filled]
	var box := StyleBoxFlat.new()
	box.bg_color = BONES if filled else SUNK
	box.border_color = EDGE
	box.set_border_width_all(1)
	box.set_content_margin_all(0)
	_pip_boxes[filled] = box
	return box

## The two colours a pip can be, for the contrast suite to enumerate rather than hard-code.
const PIP_FILLED := BONES
const PIP_EMPTY := SUNK
const PIP_EDGE := EDGE

## Art sizes, so a well is never a size the art does not divide into. Item icons are 32px
## canvases and item sprites are 64px canvases (`art/tools/item_postprocess.py`).
## The canvas every UI glyph is drawn on (`art/tools/make_ui_glyphs.py`). Ask for a glyph in
## a smaller box and it is stepped down by a whole number — 16 into 13 is a halving to 8 —
## so no call site names a size of its own.
const GLYPH := 16

## The canvas every item icon is drawn on. `loop_check`'s content suite asserts it over the
## real catalog, so an icon of another size is named rather than quietly resized.
const ICON_CANVAS := 32

const WELL_TILE := 44    ## holds a 32px icon
const WELL_HERO := 72    ## holds a 64px sprite

## For a button whose icon is item art rather than a glyph. Art carries its own colour, so
## it must be drawn at full white; the theme tints icons with ink because almost every
## other button in the game carries a glyph.
static func art_icons(button: Button) -> void:
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.5))

## What an item category looks like when none of its items have art yet. Shared, because
## the shop's category tabs and the tree's toy picker both need the same stand-in and two
## copies of this map is how a category ends up with two different faces.
const CATEGORY_GLYPHS := {
	ItemData.CATEGORY_WEAPON: &"bone",
	ItemData.CATEGORY_THROWABLE: &"bolt",
	ItemData.CATEGORY_CURSOR_POWER: &"hand",
	ItemData.CATEGORY_FRIENDLY: &"hand",
	ItemData.CATEGORY_TOY: &"crate",
	ItemData.CATEGORY_CRITTER: &"bolt",
	ItemData.CATEGORY_COMFORT: &"heart",
	ItemData.CATEGORY_FOOD: &"heart",
	ItemData.CATEGORY_AMBIENCE: &"star",
}

# --- the size contract -----------------------------------------------------
#
# **Every picture the shell draws is exactly the size of the box that holds it.** Not "at
# most" — exactly. This is the single rule that the whole alignment class came down to.
#
# Before it, the box was a suggestion. A row asked for a 24px icon and got whatever the PNG
# on disk happened to be: the pistol pointed at a raw 64x64 crosshair, the fist at a raw
# 64x64, the shotgun at nothing at all and fell back to a 16x16 glyph. A Button grows to fit
# its icon, so one list held rows 74, 74, 42 and 38 pixels tall with the name starting at
# three different x positions — in a list whose entire job is to be scanned. Nothing was
# broken in the layout code; the layout was faithfully reporting four different inputs.
#
# The two obvious remedies are both wrong here. `Button.expand_icon` and the `icon_max_width`
# theme constant resample to fit, and a 44 -> 32 resample of pixel art is a non-integer scale
# — the exact thing `sprite()`'s KEEP_CENTERED exists to forbid. So instead:
#
#   * oversized art is stepped down by a **whole number** (64 -> 32 is /2, and exact under
#     nearest-neighbour), never by a fraction;
#   * everything is then centred on a transparent canvas of exactly the box size, so a glyph
#     fallback and a full-bleed item icon occupy identical space and every name in a list
#     starts at the same x;
#   * art no wholenumber can fit is still boxed — it is cropped rather than allowed to shove
#     the layout around — and `loop_check`'s content suite names it, so it is a content bug
#     with an owner instead of a silent visual one.
#
# The result is that adding an item cannot move the UI. That was the ask.

## Textures are rebuilt per (source, box) and cached: this runs inside list rebuilds that
## happen on purchase, and an ImageTexture per row per repaint would be a real cost.
static var _boxed_cache: Dictionary = {}

## Every distinct case where art had to be stepped down to fit the box it was asked for.
## Empty is the contract; `ui_check` asserts it.
static var shrunk: Array[String] = []

## The whole-number step that brings `from` inside `box`, or 1 when it already fits.
static func _step_for(from: Vector2i, box: int) -> int:
	var step := 1
	while (from.x + step - 1) / step > box or (from.y + step - 1) / step > box:
		step += 1
		if step > 64:
			break
	return step

## `texture` centred on a transparent `box` x `box` canvas, stepped down by a whole number
## first if it does not already fit. The result is always exactly box x box.
static func boxed(texture: Texture2D, box: int) -> Texture2D:
	if texture == null:
		return null
	var key := "%s|%d|%d" % [texture.get_rid(), texture.get_size().x * 4096 + texture.get_size().y, box]
	if _boxed_cache.has(key):
		return _boxed_cache[key]

	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)

	# Enlargement, when the box is an exact whole-number multiple of the art. Nearest at 2x
	# or 3x is exact — it is the same rule `UIScale` uses for the whole shell — and it is
	# what lets a 16px glyph stand beside a 26px figure without being a speck.
	var grow := 0
	if image.get_width() == image.get_height() and image.get_width() > 0 \
			and box % image.get_width() == 0:
		grow = box / image.get_width()
	if grow >= 2:
		image.resize(box, box, Image.INTERPOLATE_NEAREST)

	var step := _step_for(Vector2i(image.get_width(), image.get_height()), box)
	if step > 1:
		# Stepping down is the safety net for art that is genuinely too big, not a way to
		# make a box fit. A whole-number step is a *halving* at best — 32 into a 24 box is
		# 16 — so it is recorded, and `ui_check` asserts the game never does it. Every box
		# in the shell is meant to be the art's own size.
		var note := "%dx%d into a %d box" % [image.get_width(), image.get_height(), box]
		if not shrunk.has(note):
			shrunk.append(note)
			push_warning("UIStyle.boxed: %s — the box is smaller than the art" % note)
		# NEAREST, always. A pixel-art icon put through a smoothing filter stops being pixel
		# art, and at a whole-number step nearest is not an approximation — it is exact.
		image.resize(maxi(1, image.get_width() / step), maxi(1, image.get_height() / step),
			Image.INTERPOLATE_NEAREST)

	var canvas := Image.create_empty(box, box, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	# Whole-pixel offsets: a half-pixel blit is the other way pixel art goes soft.
	var offset := Vector2i(
		int(floor((box - image.get_width()) / 2.0)),
		int(floor((box - image.get_height()) / 2.0)))
	var src := Rect2i(
		maxi(0, -offset.x), maxi(0, -offset.y),
		mini(image.get_width(), box), mini(image.get_height(), box))
	canvas.blit_rect(image, src, Vector2i(maxi(0, offset.x), maxi(0, offset.y)))

	var out := ImageTexture.create_from_image(canvas)
	_boxed_cache[key] = out
	return out

## True when this texture already satisfies the contract at `box` without being stepped or
## cropped. The content suite asserts it over the real catalog, so a new item with art of
## the wrong size fails a test rather than quietly bending a list.
static func fits_box(texture: Texture2D, box: int) -> bool:
	if texture == null:
		return false
	var size := texture.get_size()
	return size.x <= float(box) and size.y <= float(box)

## An item's picture: its own art if it has any, its category's glyph otherwise — always
## delivered at exactly `box` x `box`, whichever it was.
static func item_face(item: ItemData, box: int = 0) -> Texture2D:
	var raw: Texture2D = item.icon if (item and item.icon) else \
		glyph(CATEGORY_GLYPHS.get(item.category if item else -1, &"crate"))
	if box <= 0:
		return raw
	return boxed(raw, box)

static func has_art(item: ItemData) -> bool:
	return item != null and item.icon != null

## An action button's colour has to be set on every state, not only `font_color`:
## hovering an unaffordable price would otherwise repaint it in the theme's full-strength
## ink and tell the player they can have it after all.
static func tint_button(button: Button, colour: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, colour)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		button.add_theme_color_override(state, colour)
	# Solid, never alpha. A tint at 55% over a sunk well is a contrast ratio around 2:1 —
	# text the same colour as what is behind it. Disabled has to look inert, not invisible,
	# and the *shape* of a disabled key (pressed into the card, no lift) already says it.
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)
	button.add_theme_color_override("icon_disabled_color", DISABLED_INK)

# --- meters ----------------------------------------------------------------

## A meter's fill, which is the one part of a bar that varies per meter — the track comes
## from the Theme. Colour is data here: mood recolours its fill several times a second, so
## the box is held and repainted rather than rebuilt.
static func meter_fill(colour: Color = BONES) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(0)
	return box

## Mood's two poles. Despair is cold, bliss is the Hearts red — the same colour the
## kindness payouts use, so the player connects the meter to what filled it.
const DESPAIR := Color("2f5d9e")
const BLISS := HEARTS

## Colour for a mood in [-100, 100]. Neutral is deliberately drab: it is the bottom of the
## U-curve and the worst place to be, and the meter should look as unrewarding as it pays.
static func mood_colour(mood: float) -> Color:
	var t := clampf(absf(mood) / 100.0, 0.0, 1.0)
	return TEXT_DIM.lerp(DESPAIR if mood < 0.0 else BLISS, t)

## The one ink a disabled control is allowed. Quiet, and still 4.6:1 on the darkest surface
## it can land on.
const DISABLED_INK := Color("655f4c")

## Interaction states of the two keys that are not one of the surfaces above. They live
## here, with everything else the contrast suite enumerates, rather than as literals inside
## `ui_theme.gd` — a colour defined where nothing grades it is a colour that ships at 2:1.
const BUY_HOVER := Color("fffff4")    ## the affordable key, lit
const DANGER_HOVER := Color("c04a75") ## the reincarnation key, lit
const DANGER_DOWN := Color("8e2d50")  ## and pressed

# --- the arcade's marquees -------------------------------------------------
#
# Every other colour in this file carries a meaning. These carry an *identity*: one per room
# of the Arcade, lit across the top of its cabinet and on its tab, so five rooms read as five
# machines rather than as five copies of one grey box (docs/decisions.md D58). Each is taken
# straight from the locked palette (`art/src/bonehead.gpl`) rather than picked by eye, and
# each is paired with the ink printed on it — dark ink on the three light ones, card stock on
# the two dark ones. `loop_check`'s contrast suite grades every pair, and the theme builds one
# `Marquee*` panel and one `RoomTab*` key per entry, so a sixth machine picks one of these and
# touches nothing else. None of them is ever an ink on the card: the light three are about as
# bright as the card stock and would vanish on it.
const MARQUEES := {
	&"gold": [Color("f2d06b"), TEXT],    ## palette "bones gold" — the Wheel
	&"mint": [Color("9febc4"), TEXT],    ## palette "ectoplasm" — Three Ghosts
	&"wine": [Color("8a2420"), PANEL],   ## palette "red dark" — Blackjack
	&"rose": [Color("ffa6c1"), TEXT],    ## palette "pink light" — the Wardrobe
	&"night": [Color("2a2e38"), PANEL],  ## palette "grey dark" — the back room
}

static func marquee_fill(accent: StringName) -> Color:
	return (MARQUEES.get(accent, MARQUEES[&"gold"]) as Array)[0]

static func marquee_ink(accent: StringName) -> Color:
	return (MARQUEES.get(accent, MARQUEES[&"gold"]) as Array)[1]

## The theme variations an accent is drawn with. Derived rather than spelled at each call
## site, because a misspelled variation falls back to its base type and merely looks wrong.
static func marquee_variation(accent: StringName) -> StringName:
	return StringName("Marquee" + String(accent).capitalize())

static func room_tab_variation(accent: StringName) -> StringName:
	return StringName("RoomTab" + String(accent).capitalize())

## A solid rule, for dividing one section of a cabinet into cells. A `Panel` whose look is
## the theme's `Rule` — never a `ColorRect`, which the theme cannot restyle and no suite sees.
static func rule(vertical: bool = true) -> Panel:
	var line := Panel.new()
	line.theme_type_variation = &"Rule"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(BORDER_WIDTH, 0) if vertical else Vector2(0, BORDER_WIDTH)
	return line

# --- contrast --------------------------------------------------------------

## WCAG 2 relative luminance, and the ratio between two of them. Used by the test suite to
## assert the palette rather than by anything at runtime — a colour picked by eye that
## happens to be unreadable is exactly the kind of bug that ships, because whoever picked it
## could read it on their own monitor.
static func luminance(colour: Color) -> float:
	var parts := [colour.r, colour.g, colour.b]
	var linear: Array[float] = []
	for value in parts:
		var v := float(value)
		linear.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]

static func contrast(foreground: Color, background: Color) -> float:
	var a := luminance(foreground)
	var b := luminance(background)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)

# --- numbers ---------------------------------------------------------------

## Money as the player reads it. Idle games live and die on large-number formatting; this
## is the short scale, which is what the genre has standardised on.
## Grouped digits — "1,204,880" — for as long as they fit the purse, and abbreviated past
## that. A number going up is most of what an idle game has to offer, so the full figure is
## worth the width while there is width for it; the cutoff is where the digits stop fitting
## the HUD card, not where they stop being interesting.
const PURSE_FULL_BELOW := 1_000_000_000.0

static func format_purse(value: float) -> String:
	if absf(value) >= PURSE_FULL_BELOW:
		return format_amount(value)
	return group_digits(roundi(value))

## Thousands separators, done by hand because GDScript has no locale-aware formatter and a
## locale-aware one would be wrong anyway — the game ships one grouping for every language.
static func group_digits(value: int) -> String:
	var sign_text := "-" if value < 0 else ""
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return sign_text + out

static func format_amount(value: float) -> String:
	var v := absf(value)
	if v < 1000.0:
		return "%d" % roundi(value)
	var units := ["k", "M", "B", "T", "Qa", "Qi"]
	var tier := 0
	var scaled := value / 1000.0
	while absf(scaled) >= 1000.0 and tier < units.size() - 1:
		scaled /= 1000.0
		tier += 1
	return "%.2f%s" % [scaled, units[tier]]
