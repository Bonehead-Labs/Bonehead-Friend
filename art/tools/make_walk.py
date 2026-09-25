#!/usr/bin/env python3
"""Draw Bonehead's walk cycle from his own neutral body. No generator involved.

    python3 art/tools/make_walk.py [--out art/raw/bonehead_walk_sheet.png]
    python3 art/tools/postprocess.py art/raw/bonehead_walk_sheet.png walk

Writes an 8-frame, 96x96-cell strip that `postprocess.py` turns into `art/raw/body_walk.png`
and the `walk` row of `Data/buddy_face_offsets.json`, exactly like a generated sheet.

**Why drawn rather than generated.** The walk waited a milestone on Retro Diffusion's walking
preset (handoff B.1), and Codex has neither a preset nor a seed. But he is a bone wearing
headphones: the only things that move when he walks are the two knobs he stands on, and those
are already drawn in `art/src/bonehead_neutral_faceless_96.png`. So every frame is that body,
cut in two at the top of the knob flare and put back together:

    upper   headphones, shoulders and the torso shaft — moved as one piece by `bob` and `sway`
    lower   the knob end he stands on — lifted column by column, so one foot leaves the desk

Nothing is redrawn or recoloured. The outline, the four colours and the cream shading are his
own pixels on every frame, which is what "match the generated body exactly" means, and the face
offsets `postprocess.py` measures line up with every other tag because the head is the same
head. The only new pixels are the outline `close_outline` paints where a lifted foot uncovers
the other one's edge.

**Why the lift is per column.** Lifting the left half of the knob end as one block leaves the
notch between his feet split down the middle — its left wall four pixels higher than its
right, a white tooth hanging in the gap and a one-pixel sliver of outline beside it. Across the
notch the lift is instead eased from one foot's height to the other's, so the crotch becomes a
short slope, which is what a bone end tilting onto one foot actually looks like.

**Tried and dropped:** arm nubs swinging against the feet, cut from the `happy` tag's hop. At
2x on a dark desk they read as two white dots floating off his sides rather than as arms —
generator litter, the defect `postprocess.py` exists to remove. And a sideways reach on the
lifted foot: it fights the per-column lift for the notch pixels, and `flip_h` already says
which way he is going.

The frame table is the whole design, one row per frame at 12 fps (0.67 s, two steps):

    lift_l / lift_r   how far that foot is off the desk, in art pixels (even: the body is drawn
                      in two-pixel blocks and an odd lift breaks them)
    bob               the upper body: -1 is up, at the passing frames
    sway              the upper body over the planted foot, +1 right

Art pixels throughout; the buddy draws at 2x, so the one-pixel bob is two on screen.
"""
import os
import sys

from PIL import Image

BASE = "art/src/bonehead_neutral_faceless_96.png"
OUT = "art/raw/bonehead_walk_sheet.png"
CELL = 96
K = (0, 0, 0, 255)

## Where the knob end starts flaring out of the torso shaft.
FLARE_Y = 70
## A row of the plain shaft, repeated to close the gap when the upper body rises or sways.
SHAFT_ROW = 64
## The notch between his feet, inclusive: the columns across which one foot's lift eases into
## the other's. Everything left of it is his left foot, everything right his right.
NOTCH = (44, 51)

#          lift_l lift_r bob sway
FRAMES = [
	(0, 0, 0, 0),     # contact: both feet down
	(2, 0, 0, 1),     # left foot peels up, weight onto the right
	(4, 0, -1, 1),    # passing: left foot at the top of its step, body at the top of the bob
	(2, 0, -1, 0),    # left foot coming down
	(0, 0, 0, 0),     # contact
	(0, 2, 0, -1),    # right foot peels up, weight onto the left
	(0, 4, -1, -1),   # passing, the other side
	(0, 2, -1, 0),    # right foot coming down
]


def lift_at(x, lift_l, lift_r):
	"""How far column `x` of the knob end rises, easing across the notch."""
	lo, hi = NOTCH
	if x < lo:
		return lift_l
	if x > hi:
		return lift_r
	t = (x - lo + 0.5) / (hi - lo + 1)
	return int(round(lift_l + (lift_r - lift_l) * t))


def close_outline(im):
	"""Black into any clear pixel touching a coloured, non-outline pixel, as postprocess.py
	does — outward, so the body keeps its mass."""
	px = im.load()
	w, h = im.size
	add = []
	for y in range(h):
		for x in range(w):
			if px[x, y][3] >= 128:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, ny = x + dx, y + dy
				if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] >= 128 \
						and px[nx, ny][:3] != (0, 0, 0):
					add.append((x, y))
					break
	for x, y in add:
		px[x, y] = K


def frame(base, spec):
	lift_l, lift_r, bob, sway = spec
	out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))

	# The shaft first, so rising or swaying never opens daylight between his shoulders and
	# the knob end: plain shaft rows fill everything the upper body might have vacated.
	shaft = base.crop((0, SHAFT_ROW, CELL, SHAFT_ROW + 1))
	for y in range(FLARE_Y - 2, FLARE_Y + 2):
		out.alpha_composite(shaft, (sway, y))
	upper = base.crop((0, 0, CELL, FLARE_Y))
	out.alpha_composite(upper, (sway, bob)) if bob >= 0 else \
		out.alpha_composite(upper.crop((0, -bob, CELL, FLARE_Y)), (sway, 0))

	# Then the knob end, a column at a time, over the bottom of the shaft.
	lower = base.crop((0, FLARE_Y, CELL, CELL))
	for x in range(CELL):
		column = lower.crop((x, 0, x + 1, lower.height))
		if column.getbbox() is None:
			continue
		out.alpha_composite(column, (x, FLARE_Y - lift_at(x, lift_l, lift_r)))

	close_outline(out)
	return out


def _over(dst, src, x, y):
	""" that accepts a negative offset, clipping what falls off the cell."""
	crop = (max(0, -x), max(0, -y), src.width, src.height)
	dst.alpha_composite(src.crop(crop), (max(0, x), max(0, y)))


def main(argv):
	out_path = argv[argv.index("--out") + 1] if "--out" in argv else OUT
	base = Image.open(BASE).convert("RGBA")
	sheet = Image.new("RGBA", (CELL * len(FRAMES), CELL), (0, 0, 0, 0))
	for i, spec in enumerate(FRAMES):
		sheet.alpha_composite(frame(base, spec), (i * CELL, 0))
	os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
	sheet.save(out_path)
	print("walk: %d frames -> %s" % (len(FRAMES), out_path))
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
