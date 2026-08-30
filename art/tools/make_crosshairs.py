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


RETICLES = {"shotgun": shotgun}


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
