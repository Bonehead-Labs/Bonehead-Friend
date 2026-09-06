#!/usr/bin/env python3
"""Plot the five hands-on kind items and the fist icon. Free — no generation involved.

    python3 art/tools/make_hands_on_items.py

The feather duster, tennis ball, party popper, warm towel and kite arrived in M3.8 with no
generator connected and shipped as flat placeholder polygons (`tools/seed_friendly.gd`). The
art pass that followed (2026-09-06) still had no generator in the session, so they are plotted
here the way the soft brush, the reticles and the UI glyphs are: simple bold shapes in the
project palette (`art/src/palette.png`), one texel of dark outline, authored at their
scale-table size on a 64px cell so `seed_friendly` picks them up as sprites. The fist icon
replaces the prototype's grey render with a bone-cream fist in the same idiom.

Replace any of them with a generated sprite when the generator is back; nothing references
the pixels, and `make_icons.py` rebuilds the shop icons from whatever is in the folder.
"""

import os
import sys

from PIL import Image

CELL = 64
ICON = 32
OUT_ITEMS = "Assets/sprites/items"
OUT_ICONS = "Assets/sprites/icons"

# The palette, by role (art/src/palette.png).
OUTLINE = (26, 29, 36, 255)
CREAM = (252, 252, 238, 255)
CREAM_DIM = (216, 214, 196, 255)
TEAL_LIGHT = (127, 227, 223, 255)
TEAL = (46, 184, 179, 255)
TEAL_DARK = (27, 122, 118, 255)
YELLOW = (242, 208, 107, 255)
ORANGE = (232, 134, 44, 255)
RED = (200, 56, 46, 255)
RED_DARK = (138, 36, 32, 255)
PINK_LIGHT = (255, 166, 193, 255)
PINK = (240, 98, 146, 255)
PINK_DARK = (168, 58, 99, 255)
MINT = (159, 235, 196, 255)
GREEN = (79, 163, 122, 255)
GREY_LIGHT = (195, 202, 216, 255)
GREY = (154, 163, 184, 255)
GREY_DARK = (90, 97, 114, 255)
TAN = (201, 143, 85, 255)
BROWN = (169, 113, 63, 255)
BROWN_DARK = (107, 68, 38, 255)


def put(px, size, x, y, colour):
	if 0 <= x < size and 0 <= y < size:
		px[x, y] = colour


def rect(px, size, x, y, w, h, colour):
	for j in range(y, y + h):
		for i in range(x, x + w):
			put(px, size, i, j, colour)


def disc(px, size, cx, cy, r, colour):
	"""A filled circle with a hard edge — `r` in pixels, centre on a pixel."""
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			if i * i + j * j <= r * r + r * 0.5:
				put(px, size, cx + i, cy + j, colour)


def outline(im, size):
	"""One texel of dark outline in every transparent pixel that touches a body pixel."""
	px = im.load()
	edges = []
	for y in range(size):
		for x in range(size):
			if px[x, y][3] >= 128:
				continue
			for dx in (-1, 0, 1):
				for dy in (-1, 0, 1):
					nx, ny = x + dx, y + dy
					if 0 <= nx < size and 0 <= ny < size and px[nx, ny][3] >= 128 \
							and px[nx, ny] != OUTLINE:
						edges.append((x, y))
	for x, y in set(edges):
		px[x, y] = OUTLINE
	return im


def canvas(size=CELL):
	im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	return im, im.load()


# --- the five ------------------------------------------------------------------

def tennis_ball():
	"""Ten pixels across, like the baseball: yellow, with the two cream seams."""
	im, px = canvas()
	c = CELL // 2
	disc(px, CELL, c, c, 5, YELLOW)
	# Shade along the lower-right rim.
	for (x, y) in [(c + 3, c + 3), (c + 4, c + 2), (c + 2, c + 4), (c + 4, c + 1), (c + 1, c + 4)]:
		put(px, CELL, x, y, TAN)
	# Seams: two arcs facing each other.
	for (x, y) in [(c - 3, c - 3), (c - 4, c - 1), (c - 4, c), (c - 4, c + 1), (c - 3, c + 3)]:
		put(px, CELL, x, y, CREAM)
	for (x, y) in [(c + 2, c - 4), (c + 3, c - 2), (c + 3, c - 1), (c + 3, c), (c + 2, c + 2)]:
		put(px, CELL, x, y, CREAM)
	return outline(im, CELL)


def feather_duster():
	"""Lying down: a brown handle on the left, a plume of lilac feathers on the right, 26x10."""
	im, px = canvas()
	x0, y0 = CELL // 2 - 13, CELL // 2 - 5
	# Handle: 12 long, 3 thick, a lit top edge, a ring where the plume starts.
	rect(px, CELL, x0, y0 + 4, 12, 3, BROWN)
	rect(px, CELL, x0, y0 + 4, 12, 1, TAN)
	rect(px, CELL, x0 + 11, y0 + 3, 2, 5, BROWN_DARK)
	# Plume: a fat body of feathers, ragged at the far end, seams every third row.
	rect(px, CELL, x0 + 13, y0 + 1, 11, 9, PINK_LIGHT)
	for y in range(y0 + 1, y0 + 10):
		if (y - y0) % 3 == 0:
			rect(px, CELL, x0 + 14, y, 10, 1, PINK)
	# Ragged tips: alternate columns stick out one further.
	for y in range(y0 + 1, y0 + 10):
		if (y - y0) % 2 == 1:
			put(px, CELL, x0 + 24, y, PINK_LIGHT)
		else:
			put(px, CELL, x0 + 23, y, (0, 0, 0, 0))
	# A touch of the darker pink at the root.
	rect(px, CELL, x0 + 13, y0 + 2, 1, 7, PINK_DARK)
	return outline(im, CELL)


def party_popper():
	"""A cone standing on its point, mouth up, with confetti already leaving it. 10x16."""
	im, px = canvas()
	cx, top = CELL // 2, CELL // 2 - 8
	# Cone: widens from 2 px at the foot to 10 at the mouth.
	for row in range(12):
		w = 2 + (row * 8) // 11
		y = top + 15 - row
		rect(px, CELL, cx - w // 2, y, w, 1, PINK)
		# A yellow stripe down the middle and a dark edge on the right.
		if w >= 4:
			put(px, CELL, cx, y, YELLOW)
		if w >= 6:
			put(px, CELL, cx + w // 2 - 1, y, PINK_DARK)
	# Mouth: a lighter rim.
	rect(px, CELL, cx - 5, top + 4, 10, 1, PINK_LIGHT)
	# Confetti: single chips above the mouth in three colours.
	for (x, y, colour) in [(cx - 4, top + 1, TEAL_LIGHT), (cx - 1, top - 1, YELLOW), (cx + 2, top + 1, PINK_LIGHT),
			(cx + 4, top - 2, TEAL), (cx - 2, top + 2, ORANGE), (cx + 1, top + 2, MINT)]:
		put(px, CELL, x, y, colour)
	# The pull string, trailing from the foot.
	put(px, CELL, cx + 1, top + 16, CREAM_DIM)
	put(px, CELL, cx + 2, top + 17, CREAM_DIM)
	return outline(im, CELL)


def warm_towel():
	"""Folded, seen from the side: three soft layers of cream with a teal border stripe. 20x12."""
	im, px = canvas()
	x0, y0 = CELL // 2 - 10, CELL // 2 - 6
	rect(px, CELL, x0, y0, 20, 12, CREAM)
	# Folds: a dim line where each layer turns.
	for y in (y0 + 3, y0 + 7):
		rect(px, CELL, x0 + 1, y, 18, 1, CREAM_DIM)
	# Rounded ends: knock the four corners off.
	for (x, y) in [(x0, y0), (x0 + 19, y0), (x0, y0 + 11), (x0 + 19, y0 + 11)]:
		put(px, CELL, x, y, (0, 0, 0, 0))
	# The border stripe every good towel has, along the top layer.
	rect(px, CELL, x0 + 2, y0 + 1, 16, 1, TEAL)
	rect(px, CELL, x0 + 2, y0 + 5, 16, 1, TEAL_DARK)
	# Warmth: a little wisp above it, in the dim cream so it stays quiet.
	for (x, y) in [(x0 + 6, y0 - 2), (x0 + 7, y0 - 3), (x0 + 13, y0 - 2), (x0 + 12, y0 - 3)]:
		put(px, CELL, x, y, CREAM_DIM)
	return outline(im, CELL)


def kite():
	"""A diamond in teal and yellow with dark spars, and a short tail with two bows. 18 wide, 24 tall."""
	im, px = canvas()
	cx, top = CELL // 2, CELL // 2 - 12
	# Diamond: 18 wide at its waist (row 7 of 18), pointed top and bottom.
	waist = 7
	for row in range(18):
		half = (row * 9) // waist if row <= waist else ((17 - row) * 9) // (17 - waist)
		half = max(1, min(9, half))
		y = top + row
		for x in range(cx - half, cx + half):
			left = x < cx
			upper = row < waist
			colour = TEAL if left == upper else YELLOW
			put(px, CELL, x, y, colour)
	# Spars: the vertical and the cross-bar.
	rect(px, CELL, cx, top, 1, 18, BROWN_DARK)
	rect(px, CELL, cx - 9, top + waist, 18, 1, BROWN_DARK)
	# Tail: a string with two bows.
	for i in range(6):
		put(px, CELL, cx + (i % 2), top + 18 + i, CREAM_DIM)
	for y in (top + 20, top + 23):
		rect(px, CELL, cx - 1, y, 3, 1, PINK)
	return outline(im, CELL)


# --- the fist icon ---------------------------------------------------------------

def fist_icon():
	"""A bone-cream fist, knuckles up, thumb across the front, wrist at the bottom. 32x32."""
	im, px = canvas(ICON)
	# Wrist.
	rect(px, ICON, 11, 24, 10, 5, CREAM)
	rect(px, ICON, 11, 24, 10, 1, CREAM_DIM)
	# Palm block.
	rect(px, ICON, 7, 12, 18, 12, CREAM)
	# Knuckles: four rounded bumps along the top.
	for i, x in enumerate((8, 12, 16, 20)):
		disc(px, ICON, x + 1, 11, 2, CREAM)
		put(px, ICON, x + 1, 13, CREAM_DIM)
	# Finger creases below the knuckles.
	for x in (11, 15, 19):
		rect(px, ICON, x, 14, 1, 4, CREAM_DIM)
	# Thumb folded across the front.
	rect(px, ICON, 6, 16, 14, 5, CREAM)
	rect(px, ICON, 6, 16, 14, 1, CREAM_DIM)
	disc(px, ICON, 19, 18, 2, CREAM)
	rect(px, ICON, 7, 20, 12, 1, CREAM_DIM)
	return outline(im, ICON)


ITEMS = {
	"tennis_ball": tennis_ball,
	"feather_duster": feather_duster,
	"party_popper": party_popper,
	"warm_towel": warm_towel,
	"kite": kite,
}


def main():
	os.makedirs(OUT_ITEMS, exist_ok=True)
	os.makedirs(OUT_ICONS, exist_ok=True)
	for item, draw in ITEMS.items():
		path = "%s/%s.png" % (OUT_ITEMS, item)
		draw().save(path)
		print("wrote", path)
	path = "%s/fist.png" % OUT_ICONS
	fist_icon().save(path)
	print("wrote", path)


if __name__ == "__main__":
	sys.exit(main())
