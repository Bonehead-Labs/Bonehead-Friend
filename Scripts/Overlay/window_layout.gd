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

## The play-area sizes the game offers. A ladder rather than a free resize: the window is
## borderless, so there is no OS grab handle on its edge, and every size on the list has
## been eyeballed against a buddy and a couple of toys.
const SIZE_LADDER: Array[Vector2i] = [
	Vector2i(480, 360),
	Vector2i(640, 480),
	Vector2i(800, 560),
	Vector2i(960, 640),
	Vector2i(1200, 800),
	Vector2i(1440, 960),
]

## The next size up (+1) or down (-1) from whatever the current one is nearest to. Nearest
## rather than exact, because a saved size from an older build — or from a monitor that
## clamped it — need not be on the ladder at all.
static func step_size(current: Vector2i, direction: int) -> Vector2i:
	return SIZE_LADDER[clampi(nearest_size_index(current) + direction, 0, SIZE_LADDER.size() - 1)]

static func nearest_size_index(current: Vector2i) -> int:
	var nearest := 0
	var best := INF
	for i in SIZE_LADDER.size():
		var distance := absf(float(SIZE_LADDER[i].x - current.x))
		if distance < best:
			best = distance
			nearest = i
	return nearest

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
	# FREE, and anything unrecognised: bottom-right. This is only ever reached to invent a
	# *first* home — for a fresh install, or when a saved rect no longer fits the monitor —
	# because a free window otherwise uses the position it was dragged to. Bottom-right
	# because that is where the game used to force it (D49), and out of the way is the right
	# first guess for something that lives on someone's desktop while they work. Top-left,
	# which this used to return, is where the taskbar clock and every notification are not,
	# but it is also where most people keep the thing they are actually doing.
	return Vector2i(right, bottom)

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
