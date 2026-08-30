#!/usr/bin/env python3
"""Turn one raw generated item into a game-ready sprite at its scale-table size.

    python3 art/tools/item_postprocess.py <raw.png> <item_id> <target_height> [cell]

Writes `Assets/sprites/items/<item_id>.png` — a `cell`x`cell` PNG (64 unless a prop needs
128) with the item at exactly `target_height` pixels, centred.

The scale table in `docs/art-direction.md` is the point of this script. Every prototype
sprite was authored to *fill* its 64px cell, so a hand grenade came out 55px tall against a
63px buddy — a grenade the size of his torso. The cell is a shared world-space frame, not a
bounding box to fill, and enforcing that mechanically is the only way it stays true.

Four steps, in this order:

1. **Trim to content.** The generator centres its subject in the canvas with arbitrary
   margins; only the subject's own pixels carry scale.
2. **Resize to the target height**, nearest-neighbour, preserving aspect. Done before the
   palette and outline passes so those operate on final pixels — resizing afterwards would
   blur the outline back into anti-aliasing.
3. **Snap to the project palette**, which is what makes a batch generated over hours read as
   one set. `art-direction.md` locks the values; `art/src/palette.png` is the same list.
4. **Close the outline.** Non-negotiable per `art-direction.md`: the overlay renders over an
   unknown desktop and an unoutlined sprite disappears on a matching background.
"""
import os
import sys
from PIL import Image

PALETTE_PATH = "art/src/palette.png"
OUT_DIR = "Assets/sprites/items"


def load_palette():
    im = Image.open(PALETTE_PATH).convert("RGB")
    return [im.getpixel((x, 0)) for x in range(im.width)]


def snap(im, palette):
    im = im.convert("RGBA")
    out = Image.new("RGBA", im.size)
    src, dst = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = src[x, y]
            if a < 128:
                dst[x, y] = (0, 0, 0, 0)
                continue
            c = min(palette, key=lambda p: (p[0] - r) ** 2 + (p[1] - g) ** 2 + (p[2] - b) ** 2)
            dst[x, y] = (c[0], c[1], c[2], 255)
    return out


def close_outline(im):
    """Paint black into any transparent pixel touching an un-outlined body pixel."""
    px = im.load()
    w, h = im.size
    add = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] >= 128:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    n = px[nx, ny]
                    if n[3] >= 128 and n[:3] != (0, 0, 0):
                        add.append((x, y))
                        break
    for x, y in add:
        px[x, y] = (0, 0, 0, 255)
    return len(add)


def main(raw_path, item_id, target_height, cell=64):
    palette = load_palette()
    im = Image.open(raw_path).convert("RGBA")

    bbox = im.getbbox()
    if bbox is None:
        print("ERROR: %s is empty" % raw_path)
        return
    content = im.crop(bbox)

    # The outline pass grows the sprite a pixel on each side, so aim one pixel short of the
    # target and let it land exactly on the number in the scale table.
    inner = max(1, target_height - 2)
    scale = inner / content.height
    resized = content.resize(
        (max(1, round(content.width * scale)), inner), Image.NEAREST)

    resized = snap(resized, palette)

    # Pad before outlining, or the outline has no transparent pixels to grow into at the edge.
    padded = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    padded.paste(resized, ((cell - resized.width) // 2, (cell - resized.height) // 2))
    outlined = close_outline(padded)

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = "%s/%s.png" % (OUT_DIR, item_id)
    padded.save(out_path)

    final = padded.getbbox()
    print("%-14s %dx%d cell, content %dx%d (target %d), %d outline px  -> %s" % (
        item_id, cell, cell, final[2] - final[0], final[3] - final[1],
        target_height, outlined, out_path))


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]),
         int(sys.argv[4]) if len(sys.argv) == 5 else 64)
