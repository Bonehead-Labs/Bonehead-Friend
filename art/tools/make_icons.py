#!/usr/bin/env python3
"""Build 32x32 shop icons from the item sprites. Free — no generation involved.

    python3 art/tools/make_icons.py

`art-direction.md` asks for "one 64x64 idle sprite, one 32x32 UI icon" per item. Generating
the icon separately would cost another $0.017 each and risk it not matching the sprite it
labels. Downscaling the sprite is free, and guarantees the icon *is* the item.

Icons are fit to the cell rather than held at world scale: a 10px baseball at world scale
would be four pixels in a shop row. The scale table governs the world, not the UI.
"""
import glob
import os
from PIL import Image

SRC = "Assets/sprites/items"
OUT = "Assets/sprites/icons"
ICON = 32
MARGIN = 2


def main():
    os.makedirs(OUT, exist_ok=True)
    made = 0
    for path in sorted(glob.glob("%s/*.png" % SRC)):
        item = os.path.basename(path)[:-4]
        im = Image.open(path).convert("RGBA")
        bbox = im.getbbox()
        if bbox is None:
            continue
        content = im.crop(bbox)
        # Fit inside the icon with a small margin, preserving aspect.
        room = ICON - MARGIN * 2
        scale = min(room / content.width, room / content.height)
        w = max(1, round(content.width * scale))
        h = max(1, round(content.height * scale))
        icon = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
        icon.paste(content.resize((w, h), Image.NEAREST), ((ICON - w) // 2, (ICON - h) // 2))
        icon.save("%s/%s.png" % (OUT, item))
        made += 1
        print("  %-14s %dx%d -> %dx%d" % (item, content.width, content.height, w, h))
    print("%d icons -> %s/" % (made, OUT))


if __name__ == "__main__":
    main()
