class_name WindowLayout
extends RefCounted

## Works out where the overlay window should sit. Pure and dependency-free so the corner
## snapping and clamping are unit-tested rather than discovered on someone's second monitor.

enum Mode {
	FULLSCREEN_OVERLAY,  ## Fills the monitor's usable area; the taskbar becomes the floor.
	PLAY_AREA,           ## A small window the player tucks somewhere out of the way.
}

enum Corner { FREE, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

## Parameters below are typed `int` rather than Mode/Corner on purpose. GDScript's analyzer
## treats an enum parameter type as a distinct type across script boundaries, so a caller
## passing WindowLayout.Corner.TOP_LEFT fails to satisfy a `Corner` parameter. Settings
## stores these as ints for the same reason.

## Smallest sensible play area. Below this the buddy has no room to be flung anywhere.
const MIN_PLAY_SIZE := Vector2i(320, 240)

## Gap left between a corner-snapped window and the screen edge.
const DEFAULT_MARGIN := 16

## Where the window should be, given the mode and the monitor's usable rect (which
## excludes the taskbar).
static func target_rect(
		mode: int,
		usable: Rect2i,
		play_size: Vector2i,
		corner: int,
		free_position: Vector2i,
		margin: int = DEFAULT_MARGIN) -> Rect2i:

	if mode == Mode.FULLSCREEN_OVERLAY:
		return usable

	var size := clamp_play_size(play_size, usable)
	var pos := free_position if corner == Corner.FREE else corner_position(corner, size, usable, margin)
	return Rect2i(clamp_position(pos, size, usable), size)

## Never larger than the screen, never uselessly small.
static func clamp_play_size(size: Vector2i, usable: Rect2i) -> Vector2i:
	return Vector2i(
		clampi(size.x, MIN_PLAY_SIZE.x, maxi(usable.size.x, MIN_PLAY_SIZE.x)),
		clampi(size.y, MIN_PLAY_SIZE.y, maxi(usable.size.y, MIN_PLAY_SIZE.y)),
	)

static func corner_position(corner: int, size: Vector2i, usable: Rect2i, margin: int = DEFAULT_MARGIN) -> Vector2i:
	var left := usable.position.x + margin
	var top := usable.position.y + margin
	var right := usable.position.x + usable.size.x - size.x - margin
	var bottom := usable.position.y + usable.size.y - size.y - margin
	match corner:
		Corner.TOP_LEFT: return Vector2i(left, top)
		Corner.TOP_RIGHT: return Vector2i(right, top)
		Corner.BOTTOM_LEFT: return Vector2i(left, bottom)
		Corner.BOTTOM_RIGHT: return Vector2i(right, bottom)
	return Vector2i(left, top)

## Keeps the window on screen. Guards the case where the window is larger than the
## monitor, where naive clamping would push it off the top-left instead.
static func clamp_position(pos: Vector2i, size: Vector2i, usable: Rect2i) -> Vector2i:
	var max_x := usable.position.x + maxi(0, usable.size.x - size.x)
	var max_y := usable.position.y + maxi(0, usable.size.y - size.y)
	return Vector2i(
		clampi(pos.x, usable.position.x, max_x),
		clampi(pos.y, usable.position.y, max_y),
	)

## True when a saved window rect no longer fits the monitor it was saved for — a monitor
## was unplugged, or the resolution changed while the game was closed.
static func needs_revalidation(saved: Rect2i, usable: Rect2i) -> bool:
	if saved.size.x <= 0 or saved.size.y <= 0:
		return true
	return not usable.encloses(saved)
