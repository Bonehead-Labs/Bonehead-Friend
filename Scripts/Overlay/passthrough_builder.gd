class_name PassthroughBuilder
extends RefCounted

## Builds the mouse-passthrough polygon: the region of the window that accepts clicks.
## Everything outside it falls through to whatever application is underneath.
##
## Pure and dependency-free so the headless test runner can reach it.
##
## THE REGION MUST STAY A RECTANGLE. Measured on Windows at 2560x1378, uncapped:
##
##     no region            3624 fps
##     4-vertex rectangle   3635 fps   <- free
##     8-vertex hull        1253 fps
##     16-vertex hull        553 fps
##
## A rectangular window region composites on a fast path; any non-rectangular polygon
## forces a slow one, and the cost grows with vertex count. A convex hull was the original
## implementation and it was the single largest frame-time cost in the game.
##
## DisplayServer.window_set_mouse_passthrough() also accepts exactly ONE polygon, so
## disjoint regions cannot be expressed anyway. The bounding box over-includes empty space
## between scattered items — clicks there hit the game instead of the desktop. Play-area
## mode keeps that area small. True per-region masking would need a Win32 region built from
## multiple rectangles via GDExtension; see docs/overlay-tech.md.

## Padding around every interactive rect, in pixels. Generous on purpose: a player who
## misses a grab because the polygon hugged the sprite reports it as "the game ignored
## my click", which is far worse than a slightly larger clickable area.
const DEFAULT_PADDING := 10.0

## Interaction rects are snapped outward to this grid before the hull is built.
##
## This is a performance fix, not a cosmetic one. Re-applying a passthrough region costs
## roughly a third of the frame time on a large window, while applying one and leaving it
## alone is free. Without snapping, physics jitter moves the buddy a fraction of a pixel
## every rebuild, the polygon differs every time, and the region is re-applied twelve times
## a second forever. Snapping makes a settled scene produce a byte-identical polygon, which
## the caller can then skip entirely.
const SNAP := 16.0

## Far off-window degenerate triangle, used when nothing is interactive.
## An EMPTY array means "no passthrough" — the window would swallow every click — so the
## empty case must be expressed as a polygon that contains nothing instead.
## A function rather than a const: PackedVector2Array(...) is not a constant expression.
static func nothing() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-10000, -10000), Vector2(-9999, -10000), Vector2(-10000, -9999),
	])

## `world_rects` are in global/world space; `window_origin` is the window's top-left in the
## same space. Returns a polygon in WINDOW-LOCAL coordinates, which is what DisplayServer
## expects.
static func build(world_rects: Array, window_origin: Vector2, padding: float = DEFAULT_PADDING) -> PackedVector2Array:
	var points := PackedVector2Array()
	for r in world_rects:
		var rect: Rect2 = r
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var padded := _snap_out(rect.grow(padding))
		var origin := padded.position - window_origin
		points.append(origin)
		points.append(origin + Vector2(padded.size.x, 0.0))
		points.append(origin + padded.size)
		points.append(origin + Vector2(0.0, padded.size.y))

	if points.size() < 3:
		return nothing()

	# Bounding box, deliberately — see the note above. Never a convex hull.
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	return PackedVector2Array([
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	])

## Expands a rect outward to the snap grid. Outward rather than nearest, so snapping can
## only ever make the clickable area larger — never clip a grab the player expected.
static func _snap_out(r: Rect2) -> Rect2:
	var start := Vector2(floorf(r.position.x / SNAP) * SNAP, floorf(r.position.y / SNAP) * SNAP)
	var finish := Vector2(ceilf(r.end.x / SNAP) * SNAP, ceilf(r.end.y / SNAP) * SNAP)
	return Rect2(start, finish - start)

## The whole window accepts clicks — used while a UI panel is open, so the player can
## interact with it without the polygon fighting them.
static func whole_window(window_size: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2.ZERO,
		Vector2(window_size.x, 0),
		Vector2(window_size.x, window_size.y),
		Vector2(0, window_size.y),
	])
