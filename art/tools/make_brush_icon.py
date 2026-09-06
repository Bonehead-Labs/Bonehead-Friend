#!/usr/bin/env python3
"""Plot the soft brush's icon and cursor. Free — no generation involved.

    python3 art/tools/make_brush_icon.py [--out Assets/sprites/icons]

The soft brush is the open hand at a bigger value per stroke (tools/seed_friendly.gd), and
like the open hand it wears its own icon as the cursor, hotspot at the middle. It arrived
in a session with no generator connected, and a cursor power with no cursor fails
`loop_check`'s "every cursor power shows the player what it is" — so this is plotted, the
way the reticles and the UI glyphs are: a handle and a block of bristles on a 32x32 canvas,
outlined so it reads on a white IDE and a black terminal alike. Replace it with a generated
one when the art pass reaches the hands-on kind items; nothing references the pixels.
"""

import argparse
import os

from PIL import Image

CANVAS = 32

HANDLE = (128, 86, 48, 255)     # the shell's Bones brown (UIStyle.BONES)
HANDLE_LIT = (176, 128, 80, 255)
FERRULE = (190, 190, 176, 255)
BRISTLE = (252, 252, 238, 255)  # bone cream
BRISTLE_DIM = (223, 220, 198, 255)
OUTLINE = (26, 29, 36, 255)


def put(px, x, y, colour):
	if 0 <= x < CANVAS and 0 <= y < CANVAS:
		px[x, y] = colour


def rect(px, x, y, w, h, colour):
	for j in range(y, y + h):
		for i in range(x, x + w):
			put(px, i, j, colour)


def outline(im):
	px = im.load()
	edges = []
	for y in range(CANVAS):
		for x in range(CANVAS):
			if px[x, y][3] >= 128:
				continue
			for dx in (-1, 0, 1):
				for dy in (-1, 0, 1):
					nx, ny = x + dx, y + dy
					if 0 <= nx < CANVAS and 0 <= ny < CANVAS and px[nx, ny][3] >= 128 \
							and px[nx, ny] != OUTLINE:
						edges.append((x, y))
	for x, y in set(edges):
		px[x, y] = OUTLINE
	return im


def brush() -> Image.Image:
	"""Upright: a wide head of bristles at the top, a ferrule, a handle down to the bottom.

	Axis-aligned on purpose. A diagonal version read as a knife at 32px — a brush is
	identified by its head being *wider than its handle*, and a tilted head loses that."""
	im = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
	px = im.load()
	# Handle: 5 wide, with a lit left edge, rounded off at the foot.
	rect(px, 13, 17, 5, 12, HANDLE)
	rect(px, 13, 17, 1, 12, HANDLE_LIT)
	rect(px, 14, 29, 3, 1, HANDLE)
	# Ferrule: the band that holds the bristles, a little wider than the handle.
	rect(px, 10, 14, 11, 3, FERRULE)
	# Bristles: a block wider still, ragged along the top, with dim seams every third
	# column so it reads as strands rather than a slab.
	rect(px, 8, 6, 15, 8, BRISTLE)
	for x in range(8, 23):
		if (x - 8) % 3 == 1:
			rect(px, x, 7, 1, 7, BRISTLE_DIM)
	for x in (9, 12, 15, 18, 21):
		put(px, x, 5, BRISTLE)
	for x in (10, 16, 20):
		put(px, x, 4, BRISTLE)
	return outline(im)


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--out", default="Assets/sprites/icons")
	args = parser.parse_args()
	os.makedirs(args.out, exist_ok=True)
	path = os.path.join(args.out, "soft_brush.png")
	brush().save(path)
	print("wrote", path)


if __name__ == "__main__":
	main()
