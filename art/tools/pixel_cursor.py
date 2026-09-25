#!/usr/bin/env python3
"""Draw a cursor from a text grid: `art/pixel/cursors/<name>.txt` -> `Assets/sprites/cursors/<name>.png`.

    python3 art/tools/pixel_cursor.py <name> [more names ...]
    python3 art/tools/pixel_cursor.py --all

The grid format and colour key are `pixel_sprite.py`'s, so a cursor is drawn exactly the way
an item is. Two things differ, and both are about the hotspot:

- the canvas is always 64x64, which is what `make_crosshairs.py`'s reticles are and what
  `CursorPowerBase.cursor_hotspot` is seeded to expect: (32, 32);
- the drawing is placed so its **middle pixel lands on (32, 32)** — column `(w - 1) // 2` and
  row `(h - 1) // 2` of the grid — rather than centred by `(64 - w) // 2`, which is a pixel off
  for every odd width. A reticle whose centre is a pixel from where the spell lands is a
  reticle that lies.

Drawn at 1x, like the reticles: a cursor is the OS's, shown at native size, and a 2x cursor is
a 50 px thing sitting on somebody's code editor. Outlines close automatically unless the grid
says `outline: off`, so a cursor reads on a white IDE and a black terminal alike.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixel_sprite  # noqa: E402

GRIDS = "art/pixel/cursors"
OUT = "Assets/sprites/cursors"
PREVIEW = "art/preview/pixel"
CANVAS = 64
HOTSPOT = 32


def build(name):
    path = "%s/%s.txt" % (GRIDS, name)
    settings, parts = pixel_sprite.parse(path)
    _, rows = parts[0]
    height, width = len(rows), len(rows[0])
    # Where render() would put it, and where the middle pixel has to be.
    left = (CANVAS - width) // 2
    top = (CANVAS - height) // 2
    offset = (HOTSPOT - (width - 1) // 2 - left, HOTSPOT - (height - 1) // 2 - top)
    im, added = pixel_sprite.render(rows, CANVAS, offset, settings["outline"])
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    out = "%s/%s.png" % (OUT, name)
    im.save(out)
    pixel_sprite.preview(im).save("%s/cursor_%s.png" % (PREVIEW, name))
    box = im.getbbox()
    print("%-20s drawing %dx%d, %d outline px closed, hotspot (%d, %d) -> %s" % (
        name, box[2] - box[0], box[3] - box[1], added, HOTSPOT, HOTSPOT, out))


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    if argv == ["--all"]:
        names = [os.path.splitext(os.path.basename(p))[0] for p in sorted(glob.glob("%s/*.txt" % GRIDS))]
    else:
        names = argv
    failed = 0
    for name in names:
        try:
            build(name)
        except (pixel_sprite.GridError, OSError) as error:
            failed += 1
            print("ERROR: %s" % error)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
