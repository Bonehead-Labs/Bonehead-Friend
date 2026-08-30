#!/usr/bin/env python3
"""Turn one raw Retro Diffusion animation sheet into the two sheets the game imports.

    python3 art/tools/postprocess.py art/raw/bonehead_<tag>_sheet.png <tag>

Writes `art/raw/body_<tag>.png` and `art/raw/face_<tag>.png`, both the same grid, ready for
`art/src/_add_tag.lua`.

Four jobs, all of which have to happen to every generated animation:

1. **Snap to the four-colour palette.** The generator returns mostly-clean output but leaks
   a handful of off-palette pixels per sheet (the first faceless idle came back with six
   magenta ones). `art-direction.md` requires the palette be held exactly, and six stray
   pixels on a 96x96 sprite are visible at 2x on a dark desktop.

2. **Drop detached specks.** The generator sometimes leaves a few loose pixels floating
   above his head — `idle_sad` had them on four frames out of eight. They read as noise
   rather than as an effect precisely because they are inconsistent between frames. Only
   *small* detached components go; the headphones survive their own collapse and are
   supposed to (they end up resting above the bone pile, which is funnier than tidy).

3. **Close the outline.** `art-direction.md` makes the 1 px dark outline non-negotiable —
   the overlay renders over an unknown desktop and an unoutlined white sprite disappears on
   a white background. The generator leaves 110-190 exposed edge pixels per animation, so
   every transparent pixel touching an un-outlined body pixel is painted black. This grows
   the silhouette outward by a pixel exactly where the outline should already have been,
   rather than eating into the body.

4. **Export where the head is on every frame.** The face is a separate node because
   sending it through the generator destroys it — two-pixel eyes are not enough signal and
   they dissolve into noise by frame four. But a face pinned at a fixed position detaches
   from a head that bobs 11 px across an idle loop.

   The offsets are written as **data**, not baked into a face sheet. Baking would tie one
   expression to one animation, and 10 expressions across 9 animations is 90 sheets;
   `docs/architecture.md` wants mood to read independently of body pose, so the face is one
   sprite the buddy repositions per body frame. A new body animation then costs a few
   numbers, not a new face set.

   A face sheet is still written, but only so `preview.py` can show the composite.
"""
import json
import os
import sys
from collections import deque
from PIL import Image

CELL = 96
PALETTE = [(0xFF, 0xFF, 0xFF), (0x00, 0x00, 0x00), (0x2E, 0xB8, 0xB3), (0xFC, 0xFC, 0xEE)]
WHITE = (255, 255, 255)

NEUTRAL_BODY = "art/src/bonehead_neutral_faceless_96.png"
NEUTRAL_FACE = "art/src/bonehead_face_neutral_96.png"

## A row needs at least this many white pixels to count as the top of the head rather than
## a stray outline pixel or an antenna of headphone band.
HEAD_MIN_SPAN = 12

## Below this far under its rest position, the "head" the scan found is not a head — it is
## the top of a heap of bones he has collapsed into. A face pasted onto that heap is the
## single worst-looking thing this pipeline can produce, so those frames get no face at all.
##
## Only downward displacement counts. A jump or a bob lifts the head well above rest
## (`happy` reaches -11) and those are perfectly good frames.
COLLAPSED_DY = 14

## Tags where a detached piece is part of the animation rather than noise. The collapse
## scatters him and leaves the headphones resting above the pile, which is the gag; every
## other animation keeps him in one piece, so anything detached there is generator litter.
##
## An explicit list rather than a size threshold: the litter measured 55-67 px, which is not
## meaningfully smaller than the headphones, so nothing about the blobs themselves separates
## them. What separates them is which animation they turned up in.
KEEPS_DETACHED_PIECES = ("collapse", "reassemble", "pile")

## Within those tags, still drop true specks.
MIN_COMPONENT = 26


def snap(im):
    """Force every pixel onto the four project colours."""
    im = im.convert("RGBA")
    out = Image.new("RGBA", im.size)
    src, dst = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = src[x, y]
            if a < 128:
                dst[x, y] = (0, 0, 0, 0)
                continue
            c = min(PALETTE, key=lambda p: (p[0] - r) ** 2 + (p[1] - g) ** 2 + (p[2] - b) ** 2)
            dst[x, y] = (c[0], c[1], c[2], 255)
    return out


def despeckle(cell, keep_pieces):
    """Remove detached components. `keep_pieces` spares anything of real size."""
    px = cell.load()
    w, h = cell.size
    seen = set()
    comps = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] < 128 or (x, y) in seen:
                continue
            q = deque([(x, y)])
            seen.add((x, y))
            comp = []
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] >= 128 \
                                and (nx, ny) not in seen:
                            seen.add((nx, ny))
                            q.append((nx, ny))
            comps.append(comp)
    if not comps:
        return 0
    comps.sort(key=len, reverse=True)
    removed = 0
    for comp in comps[1:]:
        if keep_pieces and len(comp) >= MIN_COMPONENT:
            continue
        for x, y in comp:
            px[x, y] = (0, 0, 0, 0)
        removed += len(comp)
    return removed


def close_outline(cell):
    """Paint black into any transparent pixel touching an un-outlined body pixel."""
    px = cell.load()
    w, h = cell.size
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


def head_anchor(cell):
    """Centre-x and top-y of the head mass — where the face belongs on this frame."""
    px = cell.load()
    for y in range(cell.height):
        xs = [x for x in range(cell.width)
              if px[x, y][3] > 128 and px[x, y][:3] == WHITE]
        if len(xs) >= HEAD_MIN_SPAN:
            return (sum(xs) / len(xs), y)
    return None


def cells(sheet):
    for r in range(sheet.height // CELL):
        for c in range(sheet.width // CELL):
            yield c, r, sheet.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL))


def main(raw_path, tag):
    keep_pieces = tag in KEEPS_DETACHED_PIECES
    sheet = snap(Image.open(raw_path))
    neutral = Image.open(NEUTRAL_BODY).convert("RGBA")
    close_outline(neutral)
    base = head_anchor(neutral)
    face = Image.open(NEUTRAL_FACE).convert("RGBA")

    body_out = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    face_out = Image.new("RGBA", sheet.size, (0, 0, 0, 0))

    offsets = []
    specks = 0
    outlined = 0
    for c, r, cell in cells(sheet):
        # Specks first: outlining them would turn noise into deliberate-looking dots.
        specks += despeckle(cell, keep_pieces)
        outlined += close_outline(cell)
        body_out.paste(cell, (c * CELL, r * CELL))
        anchor = head_anchor(cell)
        if anchor is None:
            # A frame with no readable head — a collapse that has folded him flat, say.
            # The face is simply omitted rather than pinned somewhere wrong.
            offsets.append(None)
            continue
        dx, dy = round(anchor[0] - base[0]), round(anchor[1] - base[1])
        if dy > COLLAPSED_DY:
            offsets.append(None)
            continue
        offsets.append((dx, dy))
        face_out.paste(face, (c * CELL + dx, r * CELL + dy), face)

    os.makedirs("art/raw", exist_ok=True)
    body_path = "art/raw/body_%s.png" % tag
    face_path = "art/raw/face_%s.png" % tag
    body_out.save(body_path)
    face_out.save(face_path)
    write_offsets(tag, offsets)

    frames = len(offsets)
    print("%s: %d frames (%dx%d grid), %d speck px removed, %d outline px added" % (
        tag, frames, sheet.width // CELL, sheet.height // CELL, specks, outlined))
    print("  face offsets: %s" % ", ".join(
        "-" if o is None else "%+d,%+d" % o for o in offsets))
    print("  wrote %s" % body_path)
    print("  wrote %s (preview only)" % face_path)


OFFSETS_PATH = "Data/buddy_face_offsets.json"


def write_offsets(tag, offsets):
    """Merge this animation's head offsets into the file the buddy reads at runtime.

    Merged rather than overwritten so regenerating one animation does not wipe the others.
    A `null` entry means the frame has no readable head — the bone pile — and the buddy
    hides the face for it rather than pinning it somewhere wrong.
    """
    data = {}
    if os.path.exists(OFFSETS_PATH):
        with open(OFFSETS_PATH) as f:
            data = json.load(f)
    data[tag] = [None if o is None else [o[0], o[1]] for o in offsets]
    os.makedirs(os.path.dirname(OFFSETS_PATH), exist_ok=True)
    with open(OFFSETS_PATH, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    print("  merged offsets into %s" % OFFSETS_PATH)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
