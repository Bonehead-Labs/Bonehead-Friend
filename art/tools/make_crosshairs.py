#!/usr/bin/env python3
"""Plot the cursor reticles. Free — no generation involved.

    python3 art/tools/make_crosshairs.py [--out Assets/sprites/cursors]

A reticle is four to twenty pixels of geometry that has to land exactly on the pixel grid,
be identical in every build, and read on a white IDE and a black terminal alike. That is the
same argument `make_ui_glyphs.py` makes for the UI symbols, and it applies twice over here:
generating a crosshair costs money to get something that is off-grid and unrepeatable.

Each power's reticle says what the shot does, because the shape is the only tuition the
player gets before they fire it: the pistol is a single point, the shotgun is a spread.

64x64 canvas, hotspot dead centre at (32, 32) — `CursorPowerBase.cursor_hotspot` must match
or the effect lands somewhere other than where the player aimed.
"""

import argparse
import os

from PIL import Image

CANVAS = 64
CENTRE = CANVAS // 2

CORE = (252, 252, 238, 255)   # bone cream, the character's own colour
OUTLINE = (26, 29, 36, 255)   # near-black; every sprite carries one (art-direction.md)


def rect(px, x, y, w, h):
	for j in range(y, y + h):
		for i in range(x, x + w):
			if 0 <= i < CANVAS and 0 <= j < CANVAS:
				px[i, j] = CORE


def outline(im):
	"""One pixel of near-black around every core pixel, so the reticle survives a white
	background as well as a dark one."""
	px = im.load()
	edges = []
	for y in range(CANVAS):
		for x in range(CANVAS):
			if px[x, y][3] >= 128:
				continue
			neighbours = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
			if any(0 <= nx < CANVAS and 0 <= ny < CANVAS and px[nx, ny] == CORE
					for nx, ny in neighbours):
				edges.append((x, y))
	for x, y in edges:
		px[x, y] = OUTLINE
	return im


def shotgun() -> Image.Image:
	"""Four corner brackets and a centre dot: this shot covers an area.

	A cross cannot say that, and the shotgun's whole identity is that it does *not* go
	exactly where you point it. Laid out by mirrored constants rather than by signed
	arithmetic — the signed version came out three pixels wider on the left than the right,
	which on a cursor is the kind of wrongness you feel before you can name it.
	"""
	NEAR, FAR = 12, 49   # a 3px arm spans 12..14 and its mirror spans 49..51
	ARM = 10
	THICK = 3

	im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
	px = im.load()
	for x, y, hx, vy in (
			(NEAR, NEAR, NEAR, NEAR),                            # top-left
			(FAR + THICK - ARM, NEAR, FAR, NEAR),                # top-right
			(NEAR, FAR, NEAR, FAR + THICK - ARM),                # bottom-left
			(FAR + THICK - ARM, FAR, FAR, FAR + THICK - ARM)):   # bottom-right
		rect(px, x, y, ARM, THICK)      # the arm along the edge
		rect(px, hx, vy, THICK, ARM)    # and the one turning in from it

	# The centre dot is the only thing that says where the cursor actually is. Without it
	# the four brackets frame empty space and the player aims at nothing.
	rect(px, CENTRE - 1, CENTRE - 1, 3, 3)
	return outline(im)


def ring(px, radius, thickness=3):
	"""A circle of `thickness` drawn by distance, not by trigonometry — a plotted ring has
	to be symmetric about both axes to the pixel, and rounding points off a parametric
	circle is how one quadrant ends up a pixel fatter than the other."""
	inner = (radius - thickness) ** 2
	outer = radius ** 2
	for y in range(CANVAS):
		for x in range(CANVAS):
			dx, dy = x - CENTRE + 0.5, y - CENTRE + 0.5
			d = dx * dx + dy * dy
			if inner <= d <= outer:
				px[x, y] = CORE


def magnifying_glass() -> Image.Image:
	"""A ring around the point: this one does not fire, it *dwells*. The shape says the
	damage is where the cursor stays rather than where it clicks."""
	im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
	px = im.load()
	ring(px, 15, 3)
	rect(px, CENTRE - 1, CENTRE - 1, 3, 3)
	return outline(im)


def minigun() -> Image.Image:
	"""Stacked bars either side, like a rate meter. Three rungs of a stream against the
	shotgun's four corners of an area and the pistol's single point."""
	im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
	px = im.load()
	for i, width in enumerate((12, 9, 6)):
		row = CENTRE - 9 + i * 9
		rect(px, CENTRE - 20, row, width, 3)
		rect(px, CENTRE + 20 - width, row, width, 3)
	rect(px, CENTRE - 1, CENTRE - 1, 3, 3)
	return outline(im)


def gravity_vortex() -> Image.Image:
	"""Four arms set off-centre, all turning the same way — a pinwheel, which is the only
	shape in the set that says *rotation* rather than *aim*."""
	im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
	px = im.load()
	arm, thick, gap = 11, 3, 6
	rect(px, CENTRE + gap, CENTRE - gap - thick, arm, thick)          # right, above axis
	rect(px, CENTRE - gap - arm, CENTRE + gap, arm, thick)            # left, below
	rect(px, CENTRE + gap, CENTRE + gap, thick, arm)                  # down, right of axis
	rect(px, CENTRE - gap - thick, CENTRE - gap - arm, thick, arm)    # up, left
	rect(px, CENTRE - 1, CENTRE - 1, 3, 3)
	return outline(im)


def lightning() -> Image.Image:
	"""A chevron above and below: the strike comes from somewhere else and arrives here."""
	im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
	px = im.load()
	for i in range(7):
		rect(px, CENTRE - 7 + i, CENTRE - 20 + i, 3, 3)
		rect(px, CENTRE + 7 - i, CENTRE - 20 + i, 3, 3)
		rect(px, CENTRE - 7 + i, CENTRE + 20 - i, 3, 3)
		rect(px, CENTRE + 7 - i, CENTRE + 20 - i, 3, 3)
	rect(px, CENTRE - 1, CENTRE - 1, 3, 3)
	return outline(im)


RETICLES = {
	"shotgun": shotgun,
	"magnifying_glass": magnifying_glass,
	"minigun": minigun,
	"gravity_vortex": gravity_vortex,
	"lightning": lightning,
}


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--out", default="Assets/sprites/cursors")
	args = parser.parse_args()
	os.makedirs(args.out, exist_ok=True)
	for name, build in RETICLES.items():
		path = os.path.join(args.out, "%s.png" % name)
		build().save(path)
		print("  %-12s -> %s" % (name, path))


if __name__ == "__main__":
	main()
