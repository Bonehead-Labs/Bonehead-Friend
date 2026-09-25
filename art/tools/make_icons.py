#!/usr/bin/env python3
"""Build 32x32 shop icons from the item sprites. Free — no generation involved.

    python3 art/tools/make_icons.py [id ...]

`art-direction.md` asks for "one 64x64 idle sprite, one 32x32 UI icon" per item. Generating
the icon separately would cost another $0.017 each and risk it not matching the sprite it
labels. Downscaling the sprite is free, and guarantees the icon *is* the item.

Icons are fit to the cell rather than held at world scale: a 10px baseball at world scale
would be four pixels in a shop row. The scale table governs the world, not the UI.

**By a whole number when that costs little, and never by dropping pixels.** The first version
fit every sprite to the cell exactly, so a 13px tennis ball went to 28px at x2.15 and came out
with pixels of two widths. Holding every icon to whole factors fixed that and was worse: a 30 to
56px sprite halves, so the cake, the mug, the shears and the wind chimes came out at half the
size of their neighbours in a shop row, and a smaller icon costs more legibility than an uneven
pixel does. So a whole factor is used when it keeps at least `WHOLE_MIN` of the exact fit (the
tennis ball goes x2 to 26px), and the exact fit otherwise. Going down, every output pixel is the
majority colour of the source area it covers rather than whichever pixel nearest-neighbour
landed on, because every-Nth-pixel sampling drops one-pixel outlines at random; the outline is
then closed again, since a block that was half outline and half fill can come out as fill.
"""
import glob
import os
import sys
from collections import Counter
from PIL import Image

SRC = "Assets/sprites/items"
OUT = "Assets/sprites/icons"
ICON = 32
MARGIN = 2
OUTLINE = (0, 0, 0, 255)
## A whole-number scale is used when it keeps at least this much of the exact fit.
WHOLE_MIN = 0.8


def resample_down(im, w, h):
    """Each output pixel is the majority colour of the source area it covers; clear when most
    of that area is clear."""
    src = im.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    sx, sy = im.width / w, im.height / h
    for oy in range(h):
        for ox in range(w):
            colours = Counter()
            total = 0
            for y in range(int(oy * sy), max(int(oy * sy) + 1, int((oy + 1) * sy))):
                for x in range(int(ox * sx), max(int(ox * sx) + 1, int((ox + 1) * sx))):
                    total += 1
                    p = src[min(x, im.width - 1), min(y, im.height - 1)]
                    if p[3] >= 128:
                        colours[p[:3]] += 1
            if not colours or sum(colours.values()) * 2 < total:
                continue
            # Prefer a fill colour over the outline on a tie: the outline is re-closed
            # afterwards, but a fill lost to a tie is gone.
            best = max(colours.items(), key=lambda kv: (kv[1], kv[0] != OUTLINE[:3]))
            dst[ox, oy] = best[0] + (255,)
    return out


def close_outline(im):
    px = im.load()
    add = []
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][3] >= 128:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < im.width and 0 <= ny < im.height:
                    n = px[nx, ny]
                    if n[3] >= 128 and n[:3] != OUTLINE[:3] and n[:3] != (26, 29, 36):
                        add.append((x, y))
                        break
    for x, y in add:
        px[x, y] = OUTLINE


def fit(content):
    room = ICON - MARGIN * 2
    exact = min(room / content.width, room / content.height)
    if exact >= 1:
        k = int(exact)
        if k / exact >= WHOLE_MIN:
            return content.resize((content.width * k, content.height * k), Image.NEAREST), "x%d" % k
    else:
        k = 2
        while content.width / k > room or content.height / k > room:
            k += 1
        if (1.0 / k) / exact >= WHOLE_MIN:
            return resample_down(content, -(-content.width // k), -(-content.height // k)), "/%d" % k
    w = max(1, round(content.width * exact))
    h = max(1, round(content.height * exact))
    if exact >= 1:
        return content.resize((w, h), Image.NEAREST), "x%.2f" % exact
    return resample_down(content, w, h), "x%.2f" % exact


def main():
    os.makedirs(OUT, exist_ok=True)
    made = 0
    only = set(sys.argv[1:])
    for path in sorted(glob.glob("%s/*.png" % SRC)):
        item = os.path.basename(path)[:-4]
        if only and item not in only:
            continue
        # A turret's split halves are not items.
        if item.endswith("_base") or item.endswith("_barrel"):
            continue
        im = Image.open(path).convert("RGBA")
        bbox = im.getbbox()
        if bbox is None:
            continue
        content = im.crop(bbox)
        scaled, how = fit(content)
        icon = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
        icon.paste(scaled, ((ICON - scaled.width) // 2, (ICON - scaled.height) // 2))
        close_outline(icon)
        icon.save("%s/%s.png" % (OUT, item))
        made += 1
        print("  %-20s %dx%d %s -> %dx%d" % (item, content.width, content.height, how,
                                              scaled.width, scaled.height))
    print("%d icons -> %s/" % (made, OUT))


if __name__ == "__main__":
    main()
