#!/usr/bin/env python3
"""Draw a sprite from a text grid. The grid is the source; the PNG is a build product.

    python3 art/tools/pixel_sprite.py art/pixel/<id>.txt [more.txt ...]
    python3 art/tools/pixel_sprite.py --all
    python3 art/tools/pixel_sprite.py --sheet <out.png> [id ...]   # compare against the roster

Writes `Assets/sprites/items/<id>.png` (and `<id>_<part>.png` for every named part), each a
`cell`x`cell` PNG with the drawing centred, plus a 6x preview on a checkerboard under
`art/preview/pixel/` for looking at. Nothing is resampled: one character is one art pixel,
and the game draws art pixels at 2x like every other item (docs/art-direction.md).

Why text. A generator has no seed on the Codex route and a hand-plotted Python shape list is
unreadable, so neither is a record anyone can edit. A grid is: it diffs, it reviews, and a
one-pixel fix is a one-character change. It is also how the art was drawn in the first place,
so there is no second source to drift from.

## The file

    # comments start with a hash
    id: revolver          # optional, defaults to the file name
    cell: 64              # 64 (default) or 128 for furniture and long guns
    outline: auto         # auto (default) closes any gap in the dark outline; off leaves it
    offset: 0, 4          # optional nudge of the drawing inside the cell, in art pixels

    --- main              # a part; `main` (or an unnamed first part) writes <id>.png
    ....KKKK....
    ...KhhhhK...
    --- barrel            # any other name writes <id>_barrel.png on its own cell
    KKKKKKK
    KgggggK

Rows in a part must all be the same width. `.` or a space is transparent.

## The key

One character per colour of the locked palette (`art/src/bonehead.gpl`), fixed for every file
so two people's grids mean the same thing:

    K outline       k deep shadow
    W bone white    C bone cream    c bone shadow
    A teal light    a teal          q teal dark
    Y bones gold    O orange        R red           r red dark
    P pink light    p heart pink    m pink dark
    E ectoplasm     e ecto dark
    G grey light    g grey          h grey mid      H grey dark
    B wood light    b wood          n wood dark

`K` is pure black, which is what `item_postprocess.py` closes an outline with, so the two
tools produce outlines that match.
"""
import glob
import os
import sys

from PIL import Image

KEY = {
    "K": (0, 0, 0),
    "k": (26, 29, 36),
    "W": (255, 255, 255),
    "C": (252, 252, 238),
    "c": (216, 214, 196),
    "A": (127, 227, 223),
    "a": (46, 184, 179),
    "q": (27, 122, 118),
    "Y": (242, 208, 107),
    "O": (232, 134, 44),
    "R": (200, 56, 46),
    "r": (138, 36, 32),
    "P": (255, 166, 193),
    "p": (240, 98, 146),
    "m": (168, 58, 99),
    "E": (159, 235, 196),
    "e": (79, 163, 122),
    "G": (195, 202, 216),
    "g": (154, 163, 184),
    "h": (90, 97, 114),
    "H": (42, 46, 56),
    "B": (201, 143, 85),
    "b": (169, 113, 63),
    "n": (107, 68, 38),
}
CLEAR = {".", " "}

OUT_DIR = "Assets/sprites/items"
PREVIEW_DIR = "art/preview/pixel"
PREVIEW_SCALE = 6


class GridError(Exception):
    pass


def parse(path):
    """Returns (settings, [(part_name, rows)])."""
    settings = {"id": os.path.splitext(os.path.basename(path))[0], "cell": 64,
                "outline": "auto", "offset": (0, 0)}
    parts = []
    current = None
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.rstrip("\n").rstrip("\r")
            if line.startswith("---"):
                name = line[3:].strip() or ("main" if not parts else "part%d" % len(parts))
                current = (name, [])
                parts.append(current)
                continue
            if current is None:
                text = line.split("#", 1)[0].strip()
                if not text:
                    continue
                if ":" not in text:
                    raise GridError("%s:%d: expected `key: value` before the first ---" % (path, number))
                key, value = (s.strip() for s in text.split(":", 1))
                if key == "cell":
                    settings["cell"] = int(value)
                elif key == "offset":
                    x, y = (int(v) for v in value.split(","))
                    settings["offset"] = (x, y)
                elif key in ("id", "outline"):
                    settings[key] = value
                else:
                    raise GridError("%s:%d: unknown setting '%s'" % (path, number, key))
                continue
            # Inside a part: a comment line is skipped, a blank line is a transparent row only
            # if the part has already started (leading blank lines are formatting).
            if line.lstrip().startswith("#"):
                continue
            if not line.strip() and not current[1]:
                continue
            current[1].append(line)
    if not parts:
        raise GridError("%s: no parts (a part starts with a --- line)" % path)
    for name, rows in parts:
        while rows and not rows[-1].strip():
            rows.pop()
        if not rows:
            raise GridError("%s: part '%s' is empty" % (path, name))
        width = max(len(r) for r in rows)
        for i, row in enumerate(rows):
            for ch in row:
                if ch not in KEY and ch not in CLEAR:
                    raise GridError("%s: part '%s' row %d has '%s', which is not in the key"
                                    % (path, name, i + 1, ch))
        # Ragged right edges are trailing transparency, which editors strip; pad them.
        for i in range(len(rows)):
            rows[i] = rows[i].ljust(width, ".")
    return settings, parts


def close_outline(im):
    """Paint outline into any clear pixel touching a coloured, non-outline pixel."""
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
                    if n[3] >= 128 and n[:3] != KEY["K"] and n[:3] != KEY["k"]:
                        add.append((x, y))
                        break
    for x, y in add:
        px[x, y] = KEY["K"] + (255,)
    return len(add)


def render(rows, cell, offset, outline):
    height, width = len(rows), len(rows[0])
    if width + 2 > cell or height + 2 > cell:
        raise GridError("drawing is %dx%d, which does not fit a %d cell with its outline"
                        % (width, height, cell))
    im = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    px = im.load()
    left = (cell - width) // 2 + offset[0]
    top = (cell - height) // 2 + offset[1]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in CLEAR:
                continue
            px[left + x, top + y] = KEY[ch] + (255,)
    added = close_outline(im) if outline == "auto" else 0
    return im, added


def preview(im):
    w, h = im.size
    bg = Image.new("RGBA", (w * PREVIEW_SCALE, h * PREVIEW_SCALE))
    bpx = bg.load()
    for y in range(bg.height):
        for x in range(bg.width):
            light = ((x // (PREVIEW_SCALE * 2)) + (y // (PREVIEW_SCALE * 2))) % 2 == 0
            bpx[x, y] = (205, 205, 205, 255) if light else (160, 160, 160, 255)
    big = im.resize((w * PREVIEW_SCALE, h * PREVIEW_SCALE), Image.NEAREST)
    bg.alpha_composite(big)
    return bg


def build(path):
    settings, parts = parse(path)
    item_id = settings["id"]
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for name, rows in parts:
        im, added = render(rows, settings["cell"], settings["offset"], settings["outline"])
        stem = item_id if name == "main" else "%s_%s" % (item_id, name)
        out = "%s/%s.png" % (OUT_DIR, stem)
        im.save(out)
        preview(im).save("%s/%s.png" % (PREVIEW_DIR, stem))
        box = im.getbbox()
        print("%-24s %dx%d cell, drawing %dx%d, %d outline px closed -> %s" % (
            stem, settings["cell"], settings["cell"], box[2] - box[0], box[3] - box[1],
            added, out))


def sheet(out_path, ids):
    """Every named sprite (or the whole items folder) at 2x on a mid-grey desk, ten to a row.

    A drawing is judged against its neighbours, not alone: the revolver that looks right on a
    checkerboard can still be half the size of the pistol icon beside it in the shop.
    """
    if ids:
        files = ["%s/%s.png" % (OUT_DIR, i) for i in ids]
    else:
        files = sorted(glob.glob("%s/*.png" % OUT_DIR))
    scale, cols = 2, 10
    images = [Image.open(f).convert("RGBA") for f in files if os.path.exists(f)]
    if not images:
        print("ERROR: nothing to put on the sheet")
        return 1
    cell = max(max(im.size) for im in images)
    rows = (len(images) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cell * scale, rows * cell * scale), (90, 97, 114, 255))
    for i, im in enumerate(images):
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        x = (i % cols) * cell * scale + (cell * scale - big.width) // 2
        y = (i // cols) * cell * scale + (cell * scale - big.height) // 2
        out.alpha_composite(big, (x, y))
    out.save(out_path)
    print("sheet of %d -> %s" % (len(images), out_path))
    return 0


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    if argv[0] == "--sheet":
        if len(argv) < 2:
            print("usage: pixel_sprite.py --sheet <out.png> [id ...]")
            return 1
        return sheet(argv[1], argv[2:])
    paths = sorted(glob.glob("art/pixel/*.txt")) if argv == ["--all"] else argv
    failed = 0
    for path in paths:
        try:
            build(path)
        except GridError as error:
            failed += 1
            print("ERROR: %s" % error)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
