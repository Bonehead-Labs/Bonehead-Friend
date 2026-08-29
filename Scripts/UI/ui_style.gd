class_name UIStyle
extends RefCounted

## Placeholder look for the M2 shell: opaque dark panels over a transparent window.
##
## This is NOT the theme. M2's art list calls for a real `Theme` resource, a 9-slice shop
## panel and a chosen font; until those exist, every panel building its own StyleBoxFlat
## inline would make swapping in the theme a hunt through six files. One place instead.

## Fully opaque, not nearly. The window is per-pixel transparent, so any alpha below 1
## lets the player's wallpaper through the UI — panels have to be opaque
## (docs/decisions.md D6) or text is read against whatever happens to be on the desktop.
const BG := Color(0.09, 0.08, 0.11, 1.0)
const BG_RAISED := Color(0.14, 0.13, 0.17, 1.0)
const BORDER := Color(0.32, 0.30, 0.38, 1.0)
const TEXT := Color(0.92, 0.91, 0.95)
const TEXT_DIM := Color(0.60, 0.58, 0.66)
const BONES := Color(1.0, 0.95, 0.80)
const HEARTS := Color(1.0, 0.60, 0.75)
const AFFORDABLE := Color(0.55, 0.90, 0.55)
const LOCKED := Color(0.75, 0.45, 0.45)

static func panel_box(fill: Color = BG, radius: int = 8, border: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = BORDER
	box.set_border_width_all(border)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(10)
	return box

static func chip_box(fill: Color) -> StyleBoxFlat:
	var box := panel_box(fill, 6, 0)
	box.set_content_margin_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	return box

static func apply_panel(control: Control, fill: Color = BG) -> void:
	control.add_theme_stylebox_override("panel", panel_box(fill))

## The knockout meter's track and fill.
##
## Both are explicit rather than inherited from the default theme: the theme's progress
## background is a dark grey that is invisible against our dark panel, so an empty meter
## reads as a small stray nub instead of an empty bar, and the player cannot tell how
## close he is to collapsing.
static func meter_background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.05, 0.07, 1.0)
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	return box

static func meter_fill() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BONES
	box.set_corner_radius_all(4)
	return box

static func label(text: String, size: int = 14, colour: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

static func button(text: String, size: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b

## Money as the player reads it. Idle games live and die on large-number formatting; this
## is the short scale, which is what the genre has standardised on.
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
