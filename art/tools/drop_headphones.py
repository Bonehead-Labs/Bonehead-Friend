#!/usr/bin/env python3
"""Let his headphones fall when he does. Rewrites the knockout frames, nothing else.

    python3 art/tools/drop_headphones.py        # reads art/raw/body_{collapse,pile}.png

Writes `art/raw/patch/f<NN>.png` for every changed frame of `art/src/bonehead.aseprite` and
prints the `_patch_frames.lua` command that puts them back — see that script for why a patch
and not a rebuild. Export the two sheets from the committed `.aseprite` first
(`art/prompts/bonehead_body_animations.md` has the one-liner).

**The defect** (assessment-2026-09 §3, finding 8). The generated `collapse` scatters him into
a heap and leaves his headphones exactly where his head was: from the fourth frame on they
hang in mid-air, and `pile` holds them there for as long as he is down. About three seconds of
every knockout, and it reads as a rendering bug rather than a gag — the gag the pipeline was
built to keep (`KEEPS_DETACHED_PIECES` in `postprocess.py`) is the headphones *resting on the
pile*, which the generator never actually drew.

**The fix is a fall, measured per frame.** The headphones are found as the detached piece
carrying the most teal, lifted out whole (outline included, so nothing reopens), and put back
lower: `FALL * n^2` pixels on the n-th frame after they come loose, until they touch the heap —
measured column by column on that frame, because the heap is still settling while they fall —
then one frame of bounce and rest. `pile` is the last collapse frame held, so it gets the same
treatment; `reassemble` is `collapse` reversed and is rebuilt as exactly that, so the
headphones fly back up onto his head on the way back to his feet.

Nothing is redrawn and no colour changes. The headphones are the same pixels, lower.
"""
import os
import sys
from collections import deque

from PIL import Image

CELL = 96
TEAL = (46, 184, 179)
## Pixels per frame squared. At 18 fps they come loose on frame 4 and reach the heap about
## five frames later — a quarter of a second, which is what a small thing falling a head's
## height looks like at this scale.
FALL = 1.2
## The one bounce after landing, in pixels.
BOUNCE = 2

## Global 1-based frame numbers in bonehead.aseprite (`--list-tags`), for the patch.
FIRST_FRAME = {"collapse": 39, "reassemble": 55, "pile": 71}


def cells(path):
    sheet = Image.open(path).convert("RGBA")
    return [sheet.crop((i * CELL, 0, (i + 1) * CELL, CELL)) for i in range(sheet.width // CELL)]


def components(im):
    px = im.load()
    seen = set()
    out = []
    for y in range(CELL):
        for x in range(CELL):
            if px[x, y][3] < 128 or (x, y) in seen:
                continue
            comp = []
            q = deque([(x, y)])
            seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < CELL and 0 <= ny < CELL and (nx, ny) not in seen \
                                and px[nx, ny][3] >= 128:
                            seen.add((nx, ny))
                            q.append((nx, ny))
            out.append(comp)
    return out


def headphones(im):
    """The detached piece with the most teal in it, or None while they are still on him."""
    px = im.load()
    comps = components(im)
    if len(comps) < 2:
        return None
    body = max(comps, key=len)
    best = None
    best_teal = 0
    for comp in comps:
        if comp is body:
            continue
        teal = sum(1 for (x, y) in comp if px[x, y][:3] == TEAL)
        if teal > best_teal:
            best, best_teal = comp, teal
    return best if best_teal >= 20 else None


def contact_drop(im, piece):
    """How far `piece` can fall before its lowest pixel in some column meets the heap."""
    px = im.load()
    mine = set(piece)
    lowest = {}
    for (x, y) in piece:
        lowest[x] = max(lowest.get(x, -1), y)
    drop = CELL
    for x, bottom in lowest.items():
        for y in range(bottom + 1, CELL):
            if px[x, y][3] >= 128 and (x, y) not in mine:
                # Land outline on outline: the two black edges share a row.
                drop = min(drop, y - bottom)
                break
        else:
            drop = min(drop, CELL - 1 - bottom)
    return max(0, drop)


def moved(im, piece, dy):
    if dy == 0:
        return im.copy()
    out = im.copy()
    src = im.load()
    dst = out.load()
    colours = {(x, y): src[x, y] for (x, y) in piece}
    for (x, y) in piece:
        dst[x, y] = (0, 0, 0, 0)
    for (x, y), c in colours.items():
        if 0 <= y + dy < CELL:
            dst[x, y + dy] = c
    return out


def fall(frames):
    out = []
    loose_since = None
    landed_at = None
    for i, im in enumerate(frames):
        piece = headphones(im)
        if piece is None:
            out.append(im.copy())
            continue
        if loose_since is None:
            loose_since = i
        rest = contact_drop(im, piece)
        n = i - loose_since
        dy = min(rest, int(round(FALL * n * n)))
        if dy >= rest and landed_at is None:
            landed_at = i
        elif landed_at is not None and i == landed_at + 1:
            dy = max(0, rest - BOUNCE)
        out.append(moved(im, piece, dy))
    return out


def main():
    collapse = fall(cells("art/raw/body_collapse.png"))
    pile_in = cells("art/raw/body_pile.png")
    # `pile` is the heap at rest: the headphones are already down, no fall and no bounce.
    pile = []
    for im in pile_in:
        piece = headphones(im)
        pile.append(im.copy() if piece is None else moved(im, piece, contact_drop(im, piece)))
    reassemble = list(reversed(collapse))

    os.makedirs("art/raw/patch", exist_ok=True)
    patch = []
    for tag, frames, original in (("collapse", collapse, cells("art/raw/body_collapse.png")),
                                  ("reassemble", reassemble, cells("art/raw/body_reassemble.png")),
                                  ("pile", pile, pile_in)):
        for i, (new, old) in enumerate(zip(frames, original)):
            if list(new.getdata()) == list(old.getdata()):
                continue
            number = FIRST_FRAME[tag] + i
            path = "art/raw/patch/f%02d.png" % number
            new.save(path)
            patch.append((number, path))
    print("%d frames changed" % len(patch))
    print("patch=" + ",".join("%d=<abs>\\art\\raw\\patch\\f%02d.png" % (n, n) for n, _ in patch))
    # Also sheets, for preview.py.
    for tag, frames in (("collapse", collapse), ("reassemble", reassemble), ("pile", pile)):
        sheet = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
        for i, im in enumerate(frames):
            sheet.paste(im, (i * CELL, 0))
        sheet.save("art/raw/patch/body_%s.png" % tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
