#!/usr/bin/env python3
"""Draw item sprites big, on a grid in art pixels, with click zones over them.

    python3 art/tools/zone_sheet.py <out.png> <id> [id ...]
    python3 art/tools/zone_sheet.py <out.png> <id> --zones "rect 40x8 @0,-6" "circle 10 @0,0"

For authoring a click zone (docs/decisions.md D57, D67). Zones are written in art pixels with
the origin at the sprite's centre and y down — the space `GestureZones` and every seed table
use — and that space is easy to get wrong by one or two pixels by eye. This draws each sprite
at 8x on a dark desk, a line every 4 art pixels, the axes through the centre in yellow and the
coordinates along the edges, so a zone is read off the picture rather than guessed; then
`--zones` draws the rows you wrote back over the first sprite, so it can be checked the same
way. Nothing is written to the project.

Zone syntax, one argument each, as the table rows say them:

    rect <w>x<h> @<x>,<y>       a rect of that size centred there
    circle <r> @<x>,<y>         a circle of that radius centred there
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

SCALE = 8
ROOT = Path(__file__).resolve().parents[2]
DESK = (40, 44, 52, 255)
GRID = (90, 90, 110, 255)
AXIS = (255, 255, 0, 255)
ZONE = (255, 60, 200, 255)


def tile(item_id):
    art = Image.open(ROOT / "Assets" / "sprites" / "items" / f"{item_id}.png").convert("RGBA")
    w, h = art.size
    big = Image.new("RGBA", (w * SCALE, h * SCALE), DESK)
    big.alpha_composite(art.resize((w * SCALE, h * SCALE), Image.NEAREST))
    draw = ImageDraw.Draw(big)
    for i in range(0, w + 1, 4):
        draw.line([(i * SCALE, 0), (i * SCALE, h * SCALE)], fill=AXIS if i == w // 2 else GRID)
    for j in range(0, h + 1, 4):
        draw.line([(0, j * SCALE), (w * SCALE, j * SCALE)], fill=AXIS if j == h // 2 else GRID)
    for i in range(0, w + 1, 8):
        draw.text((i * SCALE + 2, 2), str(i - w // 2), fill=(255, 255, 255, 255))
    for j in range(0, h + 1, 8):
        draw.text((2, j * SCALE + 2), str(j - h // 2), fill=(255, 255, 255, 255))
    draw.text((4, h * SCALE - 14), item_id, fill=(255, 200, 200, 255))
    return big


def draw_zone(big, spec):
    w, h = big.width // SCALE, big.height // SCALE
    draw = ImageDraw.Draw(big)
    m = re.match(r"\s*(rect|circle)\s+([\d.]+)(?:x([\d.]+))?\s*@\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)", spec)
    if not m:
        sys.exit(f"cannot read zone '{spec}'")
    kind, a, b, x, y = m.groups()
    cx, cy = (float(x) + w / 2) * SCALE, (float(y) + h / 2) * SCALE
    if kind == "rect":
        hw, hh = float(a) * SCALE / 2, float(b) * SCALE / 2
        draw.rectangle([cx - hw, cy - hh, cx + hw, cy + hh], outline=ZONE, width=3)
    else:
        r = float(a) * SCALE
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ZONE, width=3)


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    out, rest = argv[0], argv[1:]
    zones = []
    if "--zones" in rest:
        at = rest.index("--zones")
        rest, zones = rest[:at], rest[at + 1:]
    tiles = [tile(item_id) for item_id in rest]
    for spec in zones:
        draw_zone(tiles[0], spec)
    sheet = Image.new("RGBA", (sum(t.width for t in tiles), max(t.height for t in tiles)), DESK)
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width
    sheet.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
