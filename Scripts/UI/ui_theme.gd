class_name UITheme
extends RefCounted

## The Bonecard `Theme`, built once at boot.
##
## This is the file `UIStyle`'s docstring used to promise and never deliver: a real Theme
## resource instead of every panel assembling its own StyleBoxFlat inline. Panels now say
## what a control *is* — `theme_type_variation = &"Tile"` — and the answer to what that
## looks like lives here.
##
## Built in code rather than authored as a `.tres` on purpose. Half of it is derived (a
## pressed button's content margins are computed from its normal ones so the two states
## are exactly the same height), and a hand-edited theme resource cannot hold that
## relationship — it holds the numbers after someone worked them out once, and they drift.
##
## Type variations, and what each is for:
##
##   Card         the panel itself, cream stock inside a hard black rule
##   Tile         one row on a card — an item, an augment, a contract
##   TileHot      a tile you can afford or have already taken
##   TileDead     a tile that is locked out; flat, sunk, no rule weight
##   Sunk         a well: a meter track, the gate strip, an empty state
##   HowTo        how to work a toy, in the shop's detail pane (D57)
##   Bubble       a toy speaking in the world: the fortune ball's answer (D57)
##   Chip         a HUD currency chip
##   TabButton    a page tab; toggled on it merges into the card below it
##   IconTab      a shop category — sprite over caption
##   BuyButton    the price/action button on a tile
##   GhostButton  a quiet secondary action
##   DangerButton reincarnation, and nothing else
##   Eyebrow      an all-caps rule-line heading
##   BodyLabel    running text
##   NameLabel    an item or node's own name
##   Numeral      a figure meant to be read in a column
##
## The Arcade's cabinets (D58), one frame divided by rules:
##
##   Cabinet      the frame — the only box a room draws
##   Marquee*     the lit band across its top, one per `UIStyle.MARQUEES` colour
##   Stage        the game, under one rule
##   OddsStrip    the paytable, under one rule
##   Deck         the stake and the keys, under one rule
##   Display      the plate a machine talks through, set into its marquee
##   Glass        a machine's own window frame — the reel bank
##   Rule         a solid divider between cells (a `Panel`)
##   DeckKey      a key on a deck; disabled keeps a solid rule
##   RoomTab*     a room on the Arcade's strip, lit in its marquee's colour when chosen

static var _theme: Theme = null

## One Theme for the whole game, handed to the root Control of each CanvasLayer. Themes
## propagate down the Control tree but not through a CanvasLayer, so each layer asks.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

## Only for the tools that render specimen sheets; the game never needs to rebuild.
static func invalidate() -> void:
	_theme = null

# --- fonts -----------------------------------------------------------------

## Crisp, unhinted, no subpixel positioning. A pixel face rendered with the defaults is
## a blurry pixel face, which is worse than not using one.
static func _font(path: String) -> Font:
	var loaded := ResourceLoader.load(path) as FontFile
	if loaded == null:
		push_error("UITheme: missing font %s" % path)
		return null
	# Duplicated so the crisp settings do not leak onto the shared imported resource —
	# but only if the duplicate actually carried the glyph data with it.
	var font := loaded.duplicate() as FontFile
	if font == null or font.data.is_empty():
		font = loaded
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.multichannel_signed_distance_field = false
	font.fallbacks = [_fallback()]
	return font

## CJK, in the same pixel idiom rather than in whatever the OS happens to have. DotGothic16
## covers kana and the common kanji; a system font underneath it catches everything else,
## including the Korean and Simplified Chinese it does not reach.
static func _fallback() -> Font:
	var dots := ResourceLoader.load(UIStyle.FONT_CJK) as FontFile
	var system := SystemFont.new()
	system.font_names = PackedStringArray([
		"Microsoft YaHei", "Meiryo", "Malgun Gothic", "Noto Sans CJK SC", "Sans-Serif"])
	system.allow_system_fallback = true
	if dots == null:
		return system
	var font := dots.duplicate() as FontFile
	if font == null or font.data.is_empty():
		font = dots
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.fallbacks = [system]
	return font

# --- boxes -----------------------------------------------------------------

static func _box(fill: Color, margin_h: int = 10, margin_v: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = UIStyle.EDGE
	box.set_border_width_all(UIStyle.BORDER_WIDTH)
	box.set_corner_radius_all(0)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box

## How far a key rises off the card. The bottom rule is thicker than the other three, and
## pressing the key spends that thickness — which is the whole trick: the button is not
## drawn moving, it *is* shorter, and the label inside it drops to match.
const KEY_LIFT := 4

## A key at rest: thick bottom rule, label sitting high on it.
static func _key(fill: Color, margin_h: int = 12, margin_v: int = 7) -> StyleBoxFlat:
	var box := _box(fill, margin_h, margin_v)
	box.border_width_bottom = UIStyle.BORDER_WIDTH + KEY_LIFT
	box.content_margin_bottom = margin_v - 2
	return box

## The same key pressed. Total height is identical to `_key`'s by construction — the lift
## moves from the bottom rule into the top margin — so a container never re-lays-out
## mid-press and the row does not twitch.
static func _key_pressed(fill: Color, margin_h: int = 12, margin_v: int = 7) -> StyleBoxFlat:
	var box := _key(fill, margin_h, margin_v)
	box.border_width_bottom = UIStyle.BORDER_WIDTH
	box.content_margin_top = margin_v + KEY_LIFT
	return box

# --- the theme ------------------------------------------------------------

static func _build() -> Theme:
	var theme := Theme.new()
	var display := _font(UIStyle.FONT_DISPLAY)
	var display_light := _font(UIStyle.FONT_DISPLAY_LIGHT)
	var body := _font(UIStyle.FONT_BODY)
	var body_bold := _font(UIStyle.FONT_BODY_BOLD)

	theme.default_font = body
	theme.default_font_size = UIStyle.BODY

	_labels(theme, display, display_light, body, body_bold)
	_panels(theme)
	_buttons(theme, display)
	_meters(theme)
	_scrolling(theme)
	return theme

static func _labels(theme: Theme, display: Font, display_light: Font,
		body: Font, body_bold: Font) -> void:
	theme.set_font("font", "Label", display)
	theme.set_font_size("font_size", "Label", UIStyle.LABEL)
	theme.set_color("font_color", "Label", UIStyle.TEXT)
	# No shadow, no outline. Every label in the game sits on opaque card stock, and an
	# outline on a pixel face at 12px eats the counters out of the letters.
	theme.set_constant("outline_size", "Label", 0)
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 0)

	theme.set_type_variation("BodyLabel", "Label")
	theme.set_font("font", "BodyLabel", body)
	theme.set_font_size("font_size", "BodyLabel", UIStyle.BODY)
	theme.set_color("font_color", "BodyLabel", UIStyle.TEXT_DIM)
	theme.set_constant("line_spacing", "BodyLabel", 2)

	theme.set_type_variation("NameLabel", "Label")
	theme.set_font("font", "NameLabel", body_bold)
	theme.set_font_size("font_size", "NameLabel", UIStyle.NAME)
	theme.set_color("font_color", "NameLabel", UIStyle.TEXT)

	theme.set_type_variation("Eyebrow", "Label")
	theme.set_font("font", "Eyebrow", display_light)
	theme.set_font_size("font_size", "Eyebrow", UIStyle.MICRO)
	theme.set_color("font_color", "Eyebrow", UIStyle.TEXT_DIM)

	theme.set_type_variation("Numeral", "Label")
	theme.set_font("font", "Numeral", display)
	theme.set_font_size("font_size", "Numeral", UIStyle.LABEL)
	theme.set_color("font_color", "Numeral", UIStyle.TEXT)

static func _panels(theme: Theme) -> void:
	var card := _box(UIStyle.PANEL, 14, 12)
	theme.set_stylebox("panel", "PanelContainer", card)
	theme.set_stylebox("panel", "Panel", card)

	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", card)

	theme.set_type_variation("Tile", "PanelContainer")
	theme.set_stylebox("panel", "Tile", _box(UIStyle.RAISED, 10, 8))

	# Affordable, owned, taken — anything the player can act on right now. Brighter than
	# the card it sits on rather than tinted: a green wash on cream stock reads as a
	# stain, and the tick or the price glyph is already carrying the meaning.
	theme.set_type_variation("TileHot", "PanelContainer")
	theme.set_stylebox("panel", "TileHot", _box(UIStyle.PANEL, 10, 8))

	# Locked out. Sunk into the card and, crucially, given a *thin* rule: the black 3px
	# edge is what makes a tile feel like an object, so taking it away is what makes this
	# one feel like a hole.
	var dead := _box(UIStyle.SUNK, 10, 8)
	dead.set_border_width_all(1)
	dead.border_color = Color(UIStyle.EDGE, 0.35)
	theme.set_type_variation("TileDead", "PanelContainer")
	theme.set_stylebox("panel", "TileDead", dead)

	theme.set_type_variation("Sunk", "PanelContainer")
	theme.set_stylebox("panel", "Sunk", _box(UIStyle.SUNK, 10, 7))

	# How to work a toy (D57). A note on the card rather than another object on it: sunk, and
	# ruled down its left edge only, so it cannot be mistaken for the mastery well below it.
	var how := _box(UIStyle.SUNK, 10, 6)
	how.set_border_width_all(0)
	how.border_width_left = UIStyle.BORDER_WIDTH
	theme.set_type_variation("HowTo", "PanelContainer")
	theme.set_stylebox("panel", "HowTo", how)

	# A toy speaking in the world: the fortune ball's answer, over whatever the player's
	# desktop is. Card stock inside the rule like every card, and snug around one line.
	theme.set_type_variation("Bubble", "PanelContainer")
	theme.set_stylebox("panel", "Bubble", _box(UIStyle.PANEL, 8, 3))

	theme.set_type_variation("Chip", "PanelContainer")
	theme.set_stylebox("panel", "Chip", _box(UIStyle.PANEL, 9, 5))

	# A count stamped on a tab. Solid black with cream figures, no rule — it is a mark on
	# the card rather than another object sitting on it, which is what keeps five tabs
	# with five badges from reading as ten things.
	var badge := StyleBoxFlat.new()
	badge.bg_color = UIStyle.EDGE
	badge.set_corner_radius_all(0)
	badge.content_margin_left = 5
	badge.content_margin_right = 5
	badge.content_margin_top = 1
	badge.content_margin_bottom = 1
	theme.set_type_variation("Badge", "PanelContainer")
	theme.set_stylebox("panel", "Badge", badge)

	# The exclusive-branch warning strip. Black on black: the one place in the UI that is
	# inverted, because it is the one place a decision cannot be undone.
	var gate := StyleBoxFlat.new()
	gate.bg_color = UIStyle.EDGE
	gate.set_corner_radius_all(0)
	gate.content_margin_left = 10
	gate.content_margin_right = 10
	gate.content_margin_top = 4
	gate.content_margin_bottom = 4
	theme.set_type_variation("Gate", "PanelContainer")
	theme.set_stylebox("panel", "Gate", gate)

	# Automation. Teal is the only cool colour in the skin and it is spent entirely here,
	# on the one upgrade that keeps earning after the window is closed.
	var capstone := _box(UIStyle.PANEL, 10, 9)
	capstone.border_color = UIStyle.TEAL
	capstone.border_width_bottom = UIStyle.BORDER_WIDTH + 3
	theme.set_type_variation("Capstone", "PanelContainer")
	theme.set_stylebox("panel", "Capstone", capstone)

	_cabinets(theme)

## The Arcade's cabinets (docs/decisions.md D58). One outer frame, and inside it sections
## divided by a single rule each — never a frame inside a frame. The old room was a tile
## holding a sunk well holding the machine: three nested boxes of the same weight, so nothing
## read as *the machine*. A section here owns only the rule on its top edge, so two of them
## stacked share one line instead of drawing two.
static func _cabinets(theme: Theme) -> void:
	var rule := UIStyle.BORDER_WIDTH

	# The frame. Its content margin is exactly the rule, so the sections inside butt up to it
	# rather than sitting on a strip of card stock that would read as a second frame.
	theme.set_type_variation("Cabinet", "PanelContainer")
	theme.set_stylebox("panel", "Cabinet", _box(UIStyle.PANEL, rule, rule))

	# The marquee: the machine's colour, edge to edge, no rule of its own — the frame is its
	# top and the stage's rule is its bottom.
	for accent in UIStyle.MARQUEES:
		var lit := StyleBoxFlat.new()
		lit.bg_color = UIStyle.marquee_fill(accent)
		lit.set_corner_radius_all(0)
		lit.content_margin_left = 12
		lit.content_margin_right = 8
		lit.content_margin_top = 3
		lit.content_margin_bottom = 3
		var variation := UIStyle.marquee_variation(accent)
		theme.set_type_variation(variation, "PanelContainer")
		theme.set_stylebox("panel", variation, lit)

	# The stage, the paytable and the deck: sunk, raised, card — three surfaces the contrast
	# grid already grades every ink against, each with one rule across its top.
	for entry in [["Stage", UIStyle.SUNK, 12, 6], ["OddsStrip", UIStyle.RAISED, 12, 3],
			["Deck", UIStyle.PANEL, 12, 6]]:
		var section := StyleBoxFlat.new()
		section.bg_color = entry[1]
		section.border_color = UIStyle.EDGE
		section.border_width_top = rule
		section.set_corner_radius_all(0)
		section.content_margin_left = entry[2]
		section.content_margin_right = entry[2]
		section.content_margin_top = rule + int(entry[3])
		section.content_margin_bottom = entry[3]
		theme.set_type_variation(entry[0], "PanelContainer")
		theme.set_stylebox("panel", entry[0], section)

	# The display a machine talks through, set into its marquee: card stock inside a rule, so
	# the readout's ink is graded against a surface it is actually printed on.
	theme.set_type_variation("Display", "PanelContainer")
	theme.set_stylebox("panel", "Display", _box(UIStyle.PANEL, 8, 2))

	# A window frame for a machine's own glass — the slot machine's reels. Three windows share
	# it and are divided by `Rule`s, so the reel bank is one object rather than three tiles.
	theme.set_type_variation("Glass", "PanelContainer")
	theme.set_stylebox("panel", "Glass", _box(UIStyle.RAISED, rule, rule))

	# A solid rule between cells of a section (`UIStyle.rule()`). A Panel sized by its caller.
	var solid := StyleBoxFlat.new()
	solid.bg_color = UIStyle.EDGE
	solid.set_corner_radius_all(0)
	theme.set_type_variation("Rule", "Panel")
	theme.set_stylebox("panel", "Rule", solid)

static func _buttons(theme: Theme, display: Font) -> void:
	theme.set_font("font", "Button", display)
	theme.set_font_size("font_size", "Button", UIStyle.LABEL)
	theme.set_color("font_color", "Button", UIStyle.TEXT)
	theme.set_color("font_hover_color", "Button", UIStyle.TEXT)
	theme.set_color("font_pressed_color", "Button", UIStyle.TEXT)
	# Hovering a button that is already toggled on is its own state, with its own stylebox
	# and its own font colour. Leave either unset and the lookup walks past this theme into
	# Godot's stock one, which is dark — so a toggled-on tab, category or list row went
	# unreadable the moment the cursor touched it. Nothing in the shell defined it.
	theme.set_color("font_hover_pressed_color", "Button", UIStyle.TEXT)
	theme.set_color("font_focus_color", "Button", UIStyle.TEXT)
	theme.set_color("font_disabled_color", "Button", UIStyle.DISABLED_INK)
	# Ink, not white. Most button icons in the game are glyphs from `Assets/sprites/ui`,
	# which are drawn white-on-transparent so one texture can serve every tint — left on
	# the engine's default white they are invisible on cream card stock, which is exactly
	# how the first pass shipped a dock of blank buttons. The handful of buttons whose icon
	# is real item art ask for `UIStyle.art_icons()` instead.
	theme.set_color("icon_normal_color", "Button", UIStyle.TEXT)
	theme.set_color("icon_hover_color", "Button", UIStyle.TEXT)
	theme.set_color("icon_pressed_color", "Button", UIStyle.TEXT)
	theme.set_color("icon_focus_color", "Button", UIStyle.TEXT)
	theme.set_color("icon_disabled_color", "Button", UIStyle.DISABLED_INK)
	theme.set_constant("h_separation", "Button", 8)
	theme.set_constant("outline_size", "Button", 0)

	theme.set_stylebox("normal", "Button", _key(UIStyle.RAISED))
	theme.set_stylebox("hover", "Button", _key(UIStyle.PANEL))
	theme.set_stylebox("pressed", "Button", _key_pressed(UIStyle.SUNK))
	theme.set_stylebox("hover_pressed", "Button", _key_pressed(UIStyle.RAISED))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var disabled := _key_pressed(UIStyle.SUNK)
	disabled.border_color = Color(UIStyle.EDGE, 0.35)
	theme.set_stylebox("disabled", "Button", disabled)

	# --- page tabs ---
	#
	# A toggled tab draws its `pressed` box, and that box is the card's own cream with no
	# bottom rule at all — so the selected tab stops being a key and becomes the top edge
	# of the page underneath it. That join is the whole reason the tabs read as tabs.
	theme.set_type_variation("TabButton", "Button")
	theme.set_stylebox("normal", "TabButton", _key(UIStyle.SUNK, 10, 6))
	theme.set_stylebox("hover", "TabButton", _key(UIStyle.RAISED, 10, 6))
	var tab_on := _box(UIStyle.PANEL, 10, 6)
	tab_on.border_width_bottom = 0
	tab_on.content_margin_bottom = 6 + UIStyle.BORDER_WIDTH
	theme.set_stylebox("pressed", "TabButton", tab_on)
	# An open tab does not change colour under the cursor — it is the card's top edge,
	# and recolouring it would break that. The hover feedback is the motion hook.
	theme.set_stylebox("hover_pressed", "TabButton", tab_on)
	theme.set_stylebox("disabled", "TabButton", _key(UIStyle.SUNK, 10, 6))
	theme.set_font_size("font_size", "TabButton", UIStyle.MICRO)

	# --- shop categories ---
	#
	# Sprite over caption. The sprite is the label: after one visit the player picks the
	# bat by its silhouette and stops reading the word underneath it.
	theme.set_type_variation("IconTab", "Button")
	theme.set_font_size("font_size", "IconTab", UIStyle.MICRO)
	theme.set_stylebox("normal", "IconTab", _key(UIStyle.SUNK, 6, 6))
	theme.set_stylebox("hover", "IconTab", _key(UIStyle.RAISED, 6, 6))
	var cat_on := _box(UIStyle.PANEL, 6, 6)
	cat_on.border_width_bottom = 0
	cat_on.content_margin_bottom = 6 + UIStyle.BORDER_WIDTH
	theme.set_stylebox("pressed", "IconTab", cat_on)
	theme.set_stylebox("hover_pressed", "IconTab", cat_on)

	# --- prices and actions ---
	theme.set_type_variation("BuyButton", "Button")
	theme.set_stylebox("normal", "BuyButton", _key(UIStyle.PANEL, 10, 7))
	theme.set_stylebox("hover", "BuyButton", _key(UIStyle.BUY_HOVER, 10, 7))

	# --- a row in a list ---
	#
	# Quiet by design: this is the shop's left column, thirteen of them stacked, and if
	# each one were a key the list would read as a wall of buttons. A hairline underneath,
	# a wash on hover, and a heavy left bar when it is the row you are looking at.
	theme.set_type_variation("ListRow", "Button")
	theme.set_font_size("font_size", "ListRow", UIStyle.MICRO)
	theme.set_constant("h_separation", "ListRow", 8)
	var row := StyleBoxFlat.new()
	row.bg_color = UIStyle.PANEL
	row.border_color = Color(UIStyle.EDGE, 0.18)
	row.border_width_bottom = 1
	row.content_margin_left = 8
	# The right margin is the price lane, not a gutter. A row's price rides in an anchored
	# overlay that reserves no width of its own, so a long name simply drew underneath it —
	# `clip_text` clips at the row's edge, which is 96px past where the name has to stop.
	# Keep this in step with ShopPanel's price anchor.
	row.content_margin_right = ShopPanel.PRICE_LANE
	row.content_margin_top = 5
	row.content_margin_bottom = 5
	theme.set_stylebox("normal", "ListRow", row)
	var row_hover := row.duplicate() as StyleBoxFlat
	row_hover.bg_color = UIStyle.RAISED
	theme.set_stylebox("hover", "ListRow", row_hover)
	var row_on := row.duplicate() as StyleBoxFlat
	row_on.bg_color = UIStyle.SUNK
	row_on.border_color = UIStyle.EDGE
	row_on.border_width_left = UIStyle.BORDER_WIDTH
	row_on.content_margin_left = 8 - UIStyle.BORDER_WIDTH
	theme.set_stylebox("pressed", "ListRow", row_on)
	theme.set_stylebox("hover_pressed", "ListRow", row_on)
	theme.set_stylebox("disabled", "ListRow", row)

	# Quiet: a rule and a label, no lift. For actions that are available but not the point
	# of the screen — closing a panel, switching a bulk amount.
	theme.set_type_variation("GhostButton", "Button")
	var ghost := _box(UIStyle.PANEL, 9, 5)
	theme.set_stylebox("normal", "GhostButton", ghost)
	theme.set_stylebox("hover", "GhostButton", _box(UIStyle.SUNK, 9, 5))
	theme.set_stylebox("pressed", "GhostButton", _box(UIStyle.SUNK, 9, 5))
	theme.set_stylebox("hover_pressed", "GhostButton", _box(UIStyle.SUNK, 9, 5))
	theme.set_font_size("font_size", "GhostButton", UIStyle.MICRO)

	# Reincarnation. The only red button in the game, and it takes two presses.
	theme.set_type_variation("DangerButton", "Button")
	var danger := _key(UIStyle.LOCKED, 12, 8)
	theme.set_stylebox("normal", "DangerButton", danger)
	var danger_hover := _key(UIStyle.DANGER_HOVER, 12, 8)
	theme.set_stylebox("hover", "DangerButton", danger_hover)
	theme.set_stylebox("pressed", "DangerButton", _key_pressed(UIStyle.DANGER_DOWN, 12, 8))
	theme.set_stylebox("hover_pressed", "DangerButton", _key_pressed(UIStyle.DANGER_DOWN, 12, 8))
	theme.set_color("font_color", "DangerButton", UIStyle.PANEL)
	theme.set_color("font_hover_color", "DangerButton", UIStyle.PANEL)
	theme.set_color("font_pressed_color", "DangerButton", UIStyle.PANEL)
	theme.set_color("font_hover_pressed_color", "DangerButton", UIStyle.PANEL)

	_arcade_keys(theme)

## The Arcade's keys (docs/decisions.md D58).
static func _arcade_keys(theme: Theme) -> void:
	# The deck's keys: the one main action, blackjack's Hit and Stand, the stake stepper. A
	# BuyButton in every state but one — disabled keeps its solid rule. The base Button's
	# disabled box draws its rule at a third of black, which at a fractional Menu size comes
	# out as a soft grey edge on the keys that spend most of a hand disabled, and a cabinet is
	# meant to be the hardest-edged thing in the shell. The pressed-in shape and the quiet ink
	# still say "not now" (D26).
	theme.set_type_variation("DeckKey", "Button")
	theme.set_stylebox("normal", "DeckKey", _key(UIStyle.PANEL, 10, 7))
	theme.set_stylebox("hover", "DeckKey", _key(UIStyle.BUY_HOVER, 10, 7))
	theme.set_stylebox("pressed", "DeckKey", _key_pressed(UIStyle.SUNK, 10, 7))
	theme.set_stylebox("hover_pressed", "DeckKey", _key_pressed(UIStyle.RAISED, 10, 7))
	theme.set_stylebox("disabled", "DeckKey", _key_pressed(UIStyle.SUNK, 10, 7))

	# A room of the Arcade on its strip, one variation per marquee colour. At rest it is a
	# sunk key with its machine's colour lit along the top (a `Marquee*` panel the page lays
	# in, since a StyleBoxFlat has one border colour); chosen, the whole key lights up in that
	# colour and presses in, so the strip reads as a row of machines with one switched on and
	# the lit key matches the marquee under it.
	for accent in UIStyle.MARQUEES:
		var variation := UIStyle.room_tab_variation(accent)
		var ink := UIStyle.marquee_ink(accent)
		theme.set_type_variation(variation, "Button")
		theme.set_font_size("font_size", variation, UIStyle.MICRO)
		var rest := _key(UIStyle.SUNK, 8, 5)
		rest.content_margin_top = 4 + ROOM_LAMP
		theme.set_stylebox("normal", variation, rest)
		theme.set_stylebox("disabled", variation, rest)
		var lifted := _key(UIStyle.RAISED, 8, 5)
		lifted.content_margin_top = 4 + ROOM_LAMP
		theme.set_stylebox("hover", variation, lifted)
		var lit := _key_pressed(UIStyle.marquee_fill(accent), 8, 5)
		lit.content_margin_top = 4 + ROOM_LAMP + KEY_LIFT
		theme.set_stylebox("pressed", variation, lit)
		theme.set_stylebox("hover_pressed", variation, lit)
		for state in ["font_pressed_color", "font_hover_pressed_color",
				"icon_pressed_color", "icon_hover_pressed_color"]:
			theme.set_color(state, variation, ink)

## Height of the colour band across the top of an unlit room key, in UI pixels.
const ROOM_LAMP := 6

static func _meters(theme: Theme) -> void:
	# The fill is inset by the background's content margin, so the rule stays a rule
	# instead of being painted over by a full bar.
	var track := _box(UIStyle.SUNK, UIStyle.BORDER_WIDTH, UIStyle.BORDER_WIDTH)
	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar", UIStyle.meter_fill())
	theme.set_font("font", "ProgressBar", _font(UIStyle.FONT_DISPLAY))
	theme.set_font_size("font_size", "ProgressBar", UIStyle.MICRO)
	theme.set_color("font_color", "ProgressBar", UIStyle.TEXT)

static func _scrolling(theme: Theme) -> void:
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# A scrollbar's thickness *is* its track stylebox's minimum size, and a StyleBoxFlat
	# with no content margins has none — so the first pass produced a zero-pixel scrollbar
	# and a tree that simply looked cut off at the bottom of the card.
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = UIStyle.SUNK
		track.set_content_margin_all(4)
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("scroll_focus", bar, track)
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = UIStyle.TEXT_DIM
		grabber.set_content_margin_all(4)
		theme.set_stylebox("grabber", bar, grabber)
		var lit := StyleBoxFlat.new()
		lit.bg_color = UIStyle.TEXT
		lit.set_content_margin_all(4)
		theme.set_stylebox("grabber_highlight", bar, lit)
		theme.set_stylebox("grabber_pressed", bar, lit)
