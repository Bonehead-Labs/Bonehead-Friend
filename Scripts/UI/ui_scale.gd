class_name UIScale
extends RefCounted

## How many screen pixels one UI pixel is worth.
##
## The shell is drawn in pixel art at a fixed size, so on a 3440x1440 overlay it came out
## physically tiny — making the play area bigger made the game bigger and left the menus
## exactly where they were. Scaling the whole `CanvasLayer` by a whole number fixes that
## the way pixel art wants it fixed: every pixel becomes a clean 2x2 or 3x3 block, with no
## resampling and no reflow. Scaling the *font sizes* instead would reflow every panel and
## put the type on fractional pixels.
##
## Whole numbers only. 1.5x on a pixel face is a blurry pixel face.

## Auto thresholds, in viewport pixels of height. A 960x640 play area stays at 1x; a 1440p
## overlay goes to 2x; a 4K one to 3x.
const DOUBLE_ABOVE := 900
const TRIPLE_ABOVE := 1800

const MIN := 1
const MAX := 3

## The smallest root the shell can be laid out in, in UI pixels: the card at its minimum
## (PanelLayer.CARD_MIN, 360x260) plus its margins and the tab strip above it.
##
## This is a floor on the *result*, not a preference. Play area and menu size are two
## independent settings the player can reach, and the smallest rung of one with the largest
## setting of the other is a combination nobody would choose on purpose but everybody can
## reach by accident: a 480x360 window pinned to 2x leaves a 240x180 root, which is smaller
## than the card's own minimum in both axes. The card then clamps *up* past the window and
## the shell is off-screen, with the tabs that would let you fix it among the parts that
## have gone. Stepping the factor down instead always leaves something usable.
const MIN_ROOT := Vector2(384, 330)

## `Settings.ui_scale` is 0 for auto and 1-3 to pin it. Pinning matters because "big enough"
## is a matter of how far away the monitor is, which the game cannot measure.
static func factor(viewport_height: float) -> int:
	return factor_for(Vector2(viewport_height * 2.0, viewport_height))

## The full form. Prefer this: a pinned factor is only honoured if the shell still fits.
static func factor_for(viewport_size: Vector2) -> int:
	var wanted := MIN
	if Settings.ui_scale > 0:
		wanted = clampi(Settings.ui_scale, MIN, MAX)
	elif viewport_size.y >= TRIPLE_ABOVE:
		wanted = 3
	elif viewport_size.y >= DOUBLE_ABOVE:
		wanted = 2
	while wanted > MIN and not _root_fits(viewport_size, wanted):
		wanted -= 1
	return wanted

static func _root_fits(viewport_size: Vector2, at: int) -> bool:
	var root := viewport_size / float(at)
	return root.x >= MIN_ROOT.x and root.y >= MIN_ROOT.y

## Scale a layer and resize its root Control to match.
##
## Both halves are needed. A top-level Control sizes itself to the *viewport* rect and
## knows nothing about the CanvasLayer transform above it, so at 2x a full-rect root would
## cover twice the screen and anchor everything off the edge. The root is therefore sized
## explicitly, in UI pixels, and everything inside it anchors within that.
static func apply(layer: CanvasLayer, root: Control) -> int:
	var viewport := layer.get_viewport()
	if viewport == null:
		return 1
	var size := viewport.get_visible_rect().size
	var factor_now := factor_for(size)
	layer.scale = Vector2(factor_now, factor_now)
	root.size = size / float(factor_now)
	return factor_now

## Screen-space centre of a control, which is not the same as `get_global_rect()` once a
## CanvasLayer above it is scaled: `get_global_transform()` stops at the canvas. Anything
## that has to compare a control against a mouse position — the click tests, the coin
## flight — has to go through the canvas transform instead.
static func screen_centre(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)

static func screen_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	return Rect2(transform.origin, control.size * transform.get_scale())
