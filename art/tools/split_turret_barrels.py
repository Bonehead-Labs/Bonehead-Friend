#!/usr/bin/env python3
"""Split each gun turret's sprite into a base and a barrel. Free — no generation involved.

    python3 art/tools/split_turret_barrels.py

A turret with one sprite can only lean at him (docs/decisions.md D43). With two — the mount
that stays put and the gun that turns on it — the barrel can actually track him. Rather than
generate a second sprite per turret, the existing art is cut along a per-turret line read off
its pixels: everything inside `barrel` goes to `<id>_barrel.png`, the rest to `<id>_base.png`,
both on the original canvas so nothing moves. `pivot` is where the gun sits on the mount, in
the texture's own pixels; the seed tool turns it into the Barrel node's position and offset.

The symmetric turrets (tesla coil, laser lattice, swarm launcher) have no barrel and are not
listed — they keep one sprite and only lean.
"""

import os
import sys

from PIL import Image

SRC = "Assets/sprites/items"

## id: (barrel rect x0, y0, x1, y1 inclusive, in texture pixels; pivot x, y in texture pixels)
TURRETS = {
	"pellet_turret": ((11, 17, 52, 33), (31, 33)),
	"nail_gun": ((19, 15, 45, 28), (28, 29)),
	"rail_gun": ((18, 46, 110, 66), (48, 66)),
	"flamethrower": ((5, 16, 59, 36), (30, 36)),
}


def main():
	for item, (rect, pivot) in TURRETS.items():
		im = Image.open("%s/%s.png" % (SRC, item)).convert("RGBA")
		base = Image.new("RGBA", im.size, (0, 0, 0, 0))
		barrel = Image.new("RGBA", im.size, (0, 0, 0, 0))
		src, b, r = im.load(), base.load(), barrel.load()
		x0, y0, x1, y1 = rect
		for y in range(im.height):
			for x in range(im.width):
				if src[x, y][3] == 0:
					continue
				if x0 <= x <= x1 and y0 <= y <= y1:
					r[x, y] = src[x, y]
				else:
					b[x, y] = src[x, y]
		base.save("%s/%s_base.png" % (SRC, item))
		barrel.save("%s/%s_barrel.png" % (SRC, item))
		centre = (im.width // 2, im.height // 2)
		print("%s: barrel %s, pivot %s -> centre-relative (%d, %d)" % (
			item, rect, pivot, pivot[0] - centre[0], pivot[1] - centre[1]))


if __name__ == "__main__":
	sys.exit(main())
