#!/usr/bin/env python3
"""Key a generated image off its flat background and reduce it to a pipeline-sized raw.

    python3 art/tools/keyout.py <generated.png> <out.png> [--size 48] [--desaturate]
                                [--rotate DEG] [--keep-all]

This is the step Retro Diffusion did for us with `remove_bg`. Codex's `imagegen` returns an
opaque RGB PNG at whatever size it likes (1254x1254 in practice), so two things have to
happen before `item_postprocess.py` can do its job:

1. **Key out the background.** We ask for flat magenta because nothing in the project
   palette is magenta (`art/prompts/items.md`), so a colour-distance key cannot eat the
   subject. The background colour is sampled from the corners rather than assumed, so a
   generator that drifts to a slightly different magenta still keys cleanly.

2. **Downscale to the pipeline's raw size, properly.** This matters more than it looks.
   `item_postprocess.py` resizes with NEAREST, which is correct going from a 48px raw to a
   10px ball but destroys a 1254px one: nearest-neighbour from 1254 to 8 samples eight
   pixels out of a million and returns noise. Reducing here with a box filter averages every
   source pixel in, and the NEAREST step afterwards is then the modest one the tool was
   written for.

Alpha is premultiplied against the keyed background before the reduction and unpremultiplied
after, or the magenta hiding in the transparent pixels bleeds back into the subject's edge as
a pink fringe, which is the same failure `items.md` records for the hornet's translucent
wings arriving by a different route.

The alpha is then thresholded to fully on or fully off. `item_postprocess.py` treats
anything under 128 as transparent, so a soft edge is a lie by the time it reaches the game;
better to make the decision here, at a size where the outline pass can still close over it.
"""
import os
import sys
from collections import deque

from PIL import Image, ImageEnhance

# How far a pixel may sit from the sampled background and still be keyed out. Generous
# enough for the generator's own gradient banding, tight enough to keep the palette's hot
# pink, which is the nearest real colour we own to magenta.
KEY_TOLERANCE = 118
# Pixels this close to the background are held at half alpha so the reduction does not
# average magenta back into the subject's rim.
FRINGE_TOLERANCE = 165


def _dist2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def _pixels(band):
    """Pillow 12 deprecates getdata() in favour of get_flattened_data(); support both."""
    if hasattr(band, "get_flattened_data"):
        return band.get_flattened_data()
    return band.getdata()


def sample_background(im):
    """Read the background off the four corners, so a drifted magenta still keys."""
    w, h = im.size
    inset = max(2, min(w, h) // 64)
    pts = [(inset, inset), (w - 1 - inset, inset),
           (inset, h - 1 - inset), (w - 1 - inset, h - 1 - inset)]
    cols = [im.getpixel(p)[:3] for p in pts]
    # Median per channel: three corners agreeing outvote one the subject has run into.
    return tuple(sorted(c[i] for c in cols)[1] for i in range(3))


def key_out(im, bg):
    """Return an RGBA copy with background-coloured pixels transparent, and the count."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    near = KEY_TOLERANCE ** 2
    fringe = FRINGE_TOLERANCE ** 2
    keyed = 0
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            d = _dist2((r, g, b), bg)
            if d <= near:
                px[x, y] = (0, 0, 0, 0)
                keyed += 1
            elif d <= fringe:
                px[x, y] = (r, g, b, 128)
    return im, keyed


def largest_mass(im):
    """Keep only the biggest connected blob. The generator leaves specks off the subject."""
    px = im.load()
    w, h = im.size
    seen = [[False] * w for _ in range(h)]
    best, best_size = None, 0
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or px[sx, sy][3] < 128:
                continue
            comp, q = [], deque([(sx, sy)])
            seen[sy][sx] = True
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                               (1, 1), (1, -1), (-1, 1), (-1, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] \
                            and px[nx, ny][3] >= 128:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) > best_size:
                best, best_size = comp, len(comp)
    if best is None:
        return 0
    keep = set(best)
    dropped = 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] >= 128 and (x, y) not in keep:
                px[x, y] = (0, 0, 0, 0)
                dropped += 1
    return dropped


def reduce_to(im, size):
    """Box-filter down to fit size, premultiplying so the edge does not pick up magenta."""
    r, g, b, a = im.split()
    channels = []
    for src in (r, g, b):
        pre = Image.new("L", im.size)
        pre.putdata([sv * av // 255 for sv, av in zip(_pixels(src), _pixels(a))])
        channels.append(pre)
    premultiplied = Image.merge("RGBA", (channels[0], channels[1], channels[2], a))

    scale = size / max(im.size)
    small = premultiplied.resize(
        (max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.BOX)

    sr, sg, sb, sa = small.split()
    out = []
    for src in (sr, sg, sb):
        un = Image.new("L", small.size)
        un.putdata([min(255, sv * 255 // av) if av else 0
                    for sv, av in zip(_pixels(src), _pixels(sa))])
        out.append(un)
    # Binary alpha: item_postprocess.py reads anything under 128 as transparent anyway.
    hard = sa.point(lambda v: 255 if v >= 128 else 0)
    return Image.merge("RGBA", (out[0], out[1], out[2], hard))


def desaturate(im):
    """Skin tones have nowhere to land in our palette. See items.md on open_hand."""
    r, g, b, a = im.split()
    grey = Image.merge("RGB", (r, g, b)).convert("L")
    grey = ImageEnhance.Contrast(grey).enhance(1.35)
    grey = ImageEnhance.Brightness(grey).enhance(1.30)
    return Image.merge("RGBA", (grey, grey, grey, a))


def main(src, out, size=48, desat=False, rotate=0.0, keep_all=False):
    im = Image.open(src).convert("RGB")
    bg = sample_background(im)
    im, keyed = key_out(im, bg)
    pct = keyed * 100.0 / (im.width * im.height)

    if rotate:
        im = im.rotate(rotate, resample=Image.BICUBIC, expand=True, fillcolor=(0, 0, 0, 0))

    bbox = im.getbbox()
    if bbox is None:
        print("ERROR: %s keyed to nothing (background #%02x%02x%02x)" % ((src,) + bg))
        return 1
    im = im.crop(bbox)
    im = reduce_to(im, size)
    if desat:
        im = desaturate(im)
    dropped = 0 if keep_all else largest_mass(im)

    final = im.getbbox()
    if final is None:
        print("ERROR: %s emptied by the despeckle pass" % src)
        return 1
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    im.save(out)
    print("%-22s bg #%02x%02x%02x, %4.1f%% keyed, %dx%d content, %d speck px  -> %s" % (
        os.path.basename(src), bg[0], bg[1], bg[2], pct,
        final[2] - final[0], final[3] - final[1], dropped, out))
    return 0


if __name__ == "__main__":
    args = list(sys.argv[1:])
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    opts = {"size": 48, "desat": False, "rotate": 0.0, "keep_all": False}
    pos = []
    i = 0
    while i < len(args):
        if args[i] == "--size":
            opts["size"] = int(args[i + 1])
            i += 2
        elif args[i] == "--desaturate":
            opts["desat"] = True
            i += 1
        elif args[i] == "--rotate":
            opts["rotate"] = float(args[i + 1])
            i += 2
        elif args[i] == "--keep-all":
            opts["keep_all"] = True
            i += 1
        else:
            pos.append(args[i])
            i += 1
    sys.exit(main(pos[0], pos[1], opts["size"], opts["desat"],
                  opts["rotate"], opts["keep_all"]))
