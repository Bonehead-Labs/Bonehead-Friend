#!/usr/bin/env python3
"""Remove generator litter from shipped buddy frames.

    python3 art/tools/clean_buddy_frames.py <frames_dir> <out_dir>

`docs/assessment-2026-09.md` §3 finding 10: "Generator litter in shipped buddy frames:
`idle_sad` frames 2 and 6 have a stray mark above the head; `happy` frame 8 a smear on the
face." All three are Retro Diffusion artefacts that were never noticed because a 96px frame
is judged at 96px and these read as part of the drawing until he moves.

`<frames_dir>` holds frames exported per tag by Aseprite, named `<tag>_<n>.png` with `n`
1-based within the tag:

    Aseprite.exe -b --frame-tag idle_sad art/src/bonehead.aseprite --save-as out/idle_sad_1.png

Repaired frames are written to `<out_dir>` and the tool prints the `--script-param patch=`
argument for `art/src/_patch_frames.lua`, which writes them back into the .aseprite.

Two different defects, so two different repairs — and neither one is "delete small things",
because in both cases the litter is *connected* to the body and a component pass sees one
mass.

**The stray above the head is a stalk.** It is thin, and it sits above the shoulders. So the
rule is positional: find the first row from the top carrying at least `SHOULDER_WIDTH`
opaque pixels, and clear everything above it. On a clean frame the first row already meets
that width and nothing is touched, which is what makes the rule safe to run over every
frame — it is checked against all sixteen idle_sad and happy frames and fires on exactly the
two the assessment names.

**The smear on the torso is a hole.** It is dark pixels enclosed by the bright body, so it
is found as a connected region of non-bright pixels that never reaches the edge of the band
being repaired, and filled with the body's own colour. The silhouette is deliberately left
alone: part of that smear has merged with the torso's right outline, and pushing the outline
back where it belongs is redrawing rather than cleaning. What is left after this is a small
nick on one edge instead of a mark across his chest.

Mirroring was tried first for the torso and is wrong. The frame is perfectly symmetric about
x=47.5 on its clean rows, which makes mirroring look like the obvious fix, but the smear
straddles the centre line — so copying either half over the other reproduces part of it and
turns a wandering squiggle into a deliberate-looking dark block.
"""
import os
import sys
from collections import Counter, deque

from PIL import Image

# A stalk is thin; the shoulders are not. Rows narrower than this above the body are litter.
SHOULDER_WIDTH = 20
# Rows of the torso to search for enclosed smears, and the largest hole worth filling.
TORSO_BAND = (44, 60)
MAX_HOLE = 120

# tag name -> 1-based frame numbers within that tag, and which repair to run.
REPAIRS = {
    ("idle_sad", 2): "stalk",
    ("idle_sad", 6): "stalk",
    ("happy", 8): "smear",
}
# Where each tag starts in the file, 1-based and global, as `--list-tags` orders them.
# idle 1-8, idle_sad 9-16, idle_happy 17-24, hurt 25-30, happy 31-38, collapse 39-54,
# reassemble 55-70, pile 71-72, dragged 73-74.
TAG_START = {"idle": 1, "idle_sad": 9, "idle_happy": 17, "hurt": 25, "happy": 31,
             "collapse": 39, "reassemble": 55, "pile": 71, "dragged": 73}


def _bright(p):
    return p[3] >= 128 and sum(p[:3]) > 600


def clear_stalk(im):
    """Clear every opaque pixel above the first row wide enough to be the shoulders."""
    px = im.load()
    w, _ = im.size
    box = im.getbbox()
    if box is None:
        return 0
    shoulder = None
    for y in range(box[1], box[3]):
        if sum(1 for x in range(w) if px[x, y][3] >= 128) >= SHOULDER_WIDTH:
            shoulder = y
            break
    if shoulder is None or shoulder <= box[1]:
        return 0
    cleared = 0
    for y in range(box[1], shoulder):
        for x in range(w):
            if px[x, y][3] >= 128:
                px[x, y] = (0, 0, 0, 0)
                cleared += 1
    return cleared


def fill_smear(im):
    """Fill regions of non-bright pixels wholly enclosed by the bright torso."""
    px = im.load()
    w, h = im.size
    y0, y1 = TORSO_BAND
    y1 = min(y1, h - 1)

    tally = Counter()
    for y in range(y1 + 1, min(y1 + 12, h)):
        for x in range(w):
            if _bright(px[x, y]):
                tally[px[x, y]] += 1
    if not tally:
        return 0
    body = tally.most_common(1)[0][0]

    seen = set()
    filled = 0
    for sy in range(y0, y1 + 1):
        for sx in range(w):
            if (sx, sy) in seen or _bright(px[sx, sy]):
                continue
            comp, q, escapes = [], deque([(sx, sy)]), False
            seen.add((sx, sy))
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < w and 0 <= ny < h) or ny < y0 or ny > y1:
                        escapes = True
                        continue
                    if _bright(px[nx, ny]) or (nx, ny) in seen:
                        continue
                    seen.add((nx, ny))
                    q.append((nx, ny))
            if not escapes and len(comp) <= MAX_HOLE:
                for x, y in comp:
                    px[x, y] = body
                filled += len(comp)
    return filled


def main(frames_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    patches = []
    for (tag, n), kind in sorted(REPAIRS.items(), key=lambda kv: TAG_START[kv[0][0]] + kv[0][1]):
        src = os.path.join(frames_dir, "%s_%d.png" % (tag, n))
        if not os.path.exists(src):
            print("MISSING %s — export it first (see the docstring)" % src)
            return 1
        im = Image.open(src).convert("RGBA")
        changed = clear_stalk(im) if kind == "stalk" else fill_smear(im)
        if changed == 0:
            print("%-12s frame %d: nothing to repair (already clean?)" % (tag, n))
            continue
        out = os.path.join(out_dir, "%s_%d.png" % (tag, n))
        im.save(out)
        global_frame = TAG_START[tag] + n - 1
        patches.append("%d=%s" % (global_frame, out))
        print("%-12s frame %d (global %d): %s repaired %d px -> %s" % (
            tag, n, global_frame, kind, changed, out))

    if not patches:
        print("nothing to patch")
        return 0
    print()
    print("Now write them back:")
    print('  Aseprite.exe -b --script-param src=<...>\\art\\src\\bonehead.aseprite \\')
    print('     --script-param "patch=%s" \\' % ",".join(patches))
    print('     --script <...>\\art\\src\\_patch_frames.lua')
    print()
    print("Then run the Godot editor pass — the Aseprite Wizard re-imports the SpriteFrames.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    sys.exit(main(sys.argv[1], sys.argv[2]))
