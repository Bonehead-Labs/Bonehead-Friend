class_name PassthroughBuilder
extends RefCounted

## Builds the mouse-passthrough polygon: the region of the window that accepts clicks.
## Everything outside it falls through to whatever application is underneath.
##
## Pure and dependency-free so the headless test runner can reach it.
##
## KNOWN LIMITATION: DisplayServer.window_set_mouse_passthrough() accepts exactly ONE
## polygon, so genuinely disjoint regions cannot be expressed. We take the convex hull of
## everything interactive, which over-includes the empty space between scattered items.
## That is acceptable because the play-area window mode (the recommended default) keeps
## the window small enough for the difference not to matter. If fullscreen-overlay mode
## turns out to need true per-region masking, the options are a bridged polygon or a Win32
## region via GDExtension — see docs/overlay-tech.md.

## Padding around every interactive rect, in pixels. Generous on purpose: a player who
## misses a grab because the polygon hugged the sprite reports it as "the game ignored
## my click", which is far worse than a slightly larger clickable area.
const DEFAULT_PADDING := 10.0

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
		var padded := rect.grow(padding)
		var origin := padded.position - window_origin
		points.append(origin)
		points.append(origin + Vector2(padded.size.x, 0.0))
		points.append(origin + padded.size)
		points.append(origin + Vector2(0.0, padded.size.y))

	if points.size() < 3:
		return nothing()

	var hull := Geometry2D.convex_hull(points)
	if hull.size() < 3:
		return nothing()
	return hull

## The whole window accepts clicks — used while a UI panel is open, so the player can
## interact with it without the polygon fighting them.
static func whole_window(window_size: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2.ZERO,
		Vector2(window_size.x, 0),
		Vector2(window_size.x, window_size.y),
		Vector2(0, window_size.y),
	])
