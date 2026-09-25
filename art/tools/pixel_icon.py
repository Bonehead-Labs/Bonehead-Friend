#!/usr/bin/env python3
"""Crisp 32x32 shop icons for hand-drawn items: whole-number scales only.

    python3 art/tools/pixel_icon.py <id> [more ids ...]

`make_icons.py` fits every sprite to the icon's 28px room by whatever fraction it takes,
which is fine for a generated picture and wrong for a drawing: a 22px fortune ball at 1.27x
turns its 8 into a 3, and a 41px sheet of bubble wrap at 0.68x turns eight bubbles into a
checkerboard. This one never resamples by a fraction:

- if `art/pixel/icons/<id>.txt` exists, that grid is the icon — drawn small on purpose, for
  an item too big to step down by a whole number (a subfolder, so `pixel_sprite.py --all`
  never mistakes it for an item);
- otherwise the item's own sprite is scaled by the largest whole number that fits the room
  (1x for anything from 17 to 32px, 2x from 9 to 16) and centred.

An item that fits neither — wider than 32 with no icon grid — is refused with a message
rather than quietly resampled.

**Long things get a drawn icon on the diagonal** (D69). A 56px rifle halved is 28x6 and a
78px halberd is a one-pixel stick; turning either 45 degrees buys about an eighth and nothing
else, because a thin thing stays thin. What works is an icon grid that is *thicker than the
item*: the long guns are their own sprites with the barrel, stock and scope rows doubled (and
some of the rifle's barrel taken out), laid on the 45-degree lattice (icon pixel (x, y) is
sprite pixel (x - y, x + y), so a sprite row becomes an 8-connected diagonal and nothing is
resampled by a fraction), and a bell rim redrawn where the lattice left it open; the halberd
and the scythe are their own shapes at about two thirds with the pole shortened to what the
corner leaves; the tyre iron is itself at full size with rows of bar cut out of the middle.
The grid is the icon either way — `make_icons.py` skips any id that has one.
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixel_sprite  # noqa: E402

SRC = "Assets/sprites/items"
OUT = "Assets/sprites/icons"
ICON_GRIDS = "art/pixel/icons"
# make_icons.py keeps a 2px margin; a drawing is only ever stepped by a whole number, so here
# the margin gives way before the picture does — a 16px ball doubles to fill the canvas
# rather than sitting at half its size.
ICON = 32


def from_grid(path):
    settings, parts = pixel_sprite.parse(path)
    name, rows = parts[0]
    im, _ = pixel_sprite.render(rows, ICON, settings["offset"], settings["outline"])
    return im


def from_sprite(path):
    im = Image.open(path).convert("RGBA")
    box = im.getbbox()
    if box is None:
        return None
    content = im.crop(box)
    scale = min(ICON // content.width, ICON // content.height)
    if scale < 1:
        return None
    big = content.resize((content.width * scale, content.height * scale), Image.NEAREST)
    icon = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    icon.paste(big, ((ICON - big.width) // 2, (ICON - big.height) // 2))
    return icon


def main(ids):
    if not ids:
        print(__doc__)
        return 1
    failed = 0
    for item in ids:
        grid = "%s/%s.txt" % (ICON_GRIDS, item)
        if os.path.exists(grid):
            icon, source = from_grid(grid), grid
        else:
            icon, source = from_sprite("%s/%s.png" % (SRC, item)), "sprite"
        if icon is None:
            print("ERROR: %s is wider than %dpx and has no %s" % (item, ICON, grid))
            failed += 1
            continue
        os.makedirs(OUT, exist_ok=True)
        icon.save("%s/%s.png" % (OUT, item))
        box = icon.getbbox()
        print("  %-18s %dx%d from %s" % (item, box[2] - box[0], box[3] - box[1], source))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
