#!/usr/bin/env python3
"""Build human-viewable previews of the generated art into `art/preview/`.

    python3 art/tools/preview.py

Everything the pipeline produces is a sprite sheet at native pixel size — a 96 px sprite in
a 4x2 grid. Opened in an image viewer that is a postage stamp of frozen frames, which tells
you nothing about whether an animation reads. This writes three things instead:

* an **animated GIF per animation**, at the frame rate the game will play it, scaled up;
* the same animation on **white, on dark and on a busy background**, side by side, because
  `art-direction.md` requires every sprite to survive all three — the overlay sits on an
  unknown desktop and that is the single most common way this kind of art fails;
* **contact sheets** for the stills (the face set, the frame-by-frame breakdown).

Regenerable, so `art/preview/` is gitignored like `art/raw/`.
"""
import glob
import os
from PIL import Image

CELL = 96
SCALE = 4
OUT = "art/preview"

## The three grounds every sprite has to read against.
BACKDROPS = [
    ("white", (255, 255, 255, 255)),
    ("dark", (24, 26, 32, 255)),
    ("busy", None),  # generated below
]


def busy_ground(size):
    """A cluttered mid-tone ground standing in for someone's photo wallpaper."""
    img = Image.new("RGBA", size, (86, 96, 120, 255))
    px = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            v = ((x * 7 + y * 13) % 71) + ((x // 9 + y // 5) % 43)
            px[x, y] = (60 + v, 70 + (v // 2), 110 + (v // 3), 255)
    return img


def frames_of(sheet):
    for r in range(sheet.height // CELL):
        for c in range(sheet.width // CELL):
            yield sheet.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL))


def composite(body_path, face_path):
    """The layered arrangement the game actually renders: face over body, per frame."""
    body = Image.open(body_path).convert("RGBA")
    face = Image.open(face_path).convert("RGBA") if os.path.exists(face_path) else None
    out = []
    body_frames = list(frames_of(body))
    face_frames = list(frames_of(face)) if face else [None] * len(body_frames)
    for b, f in zip(body_frames, face_frames):
        cell = b.copy()
        if f:
            cell.alpha_composite(f)
        out.append(cell)
    return out


def on_ground(frame, ground):
    bg = ground.copy()
    bg.alpha_composite(frame)
    return bg.convert("RGB")


def big(im):
    return im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)


def write_gif(frames, path, fps):
    big_frames = [big(f) for f in frames]
    big_frames[0].save(path, save_all=True, append_images=big_frames[1:],
                       duration=int(1000 / fps), loop=0, disposal=2)


def preview_animation(tag, fps=12):
    body_path = "art/raw/body_%s.png" % tag
    face_path = "art/raw/face_%s.png" % tag
    if not os.path.exists(body_path):
        return False
    frames = composite(body_path, face_path)

    grounds = []
    for name, colour in BACKDROPS:
        g = busy_ground((CELL, CELL)) if colour is None else Image.new("RGBA", (CELL, CELL), colour)
        grounds.append((name, g))

    # One GIF per ground, plus a three-up strip so all three can be judged at once.
    for name, ground in grounds:
        write_gif([on_ground(f, ground) for f in frames],
                  "%s/%s_on_%s.gif" % (OUT, tag, name), fps)

    strip = []
    for f in frames:
        row = Image.new("RGB", (CELL * len(grounds), CELL))
        for i, (_, ground) in enumerate(grounds):
            row.paste(on_ground(f, ground), (CELL * i, 0))
        strip.append(row)
    write_gif(strip, "%s/%s_all_grounds.gif" % (OUT, tag), fps)

    # And a frame-by-frame contact sheet, for judging individual frames rather than motion.
    sheet = Image.new("RGB", (CELL * len(frames), CELL), (24, 26, 32))
    for i, f in enumerate(frames):
        sheet.paste(on_ground(f, grounds[1][1]), (CELL * i, 0))
    big(sheet).save("%s/%s_frames.png" % (OUT, tag))
    print("  %-12s %d frames  -> %s_on_{white,dark,busy}.gif, %s_all_grounds.gif, %s_frames.png"
          % (tag, len(frames), tag, tag, tag))
    return True


def preview_faces():
    paths = sorted(glob.glob("art/src/faces/bonehead_face_*.png"))
    if not paths:
        return
    body = Image.open("art/src/bonehead_neutral_faceless_96.png").convert("RGBA")
    cols = 5
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGB", (CELL * cols, CELL * rows), (24, 26, 32))
    for i, p in enumerate(paths):
        cell = body.copy()
        cell.alpha_composite(Image.open(p).convert("RGBA"))
        sheet.paste(cell.convert("RGB"), (CELL * (i % cols), CELL * (i // cols)))
    big(sheet).save("%s/faces.png" % OUT)
    print("  %-12s %d expressions -> faces.png"
          % ("faces", len(paths)))


def preview_comparison():
    """The face-degradation finding, side by side, so the reason for the split is visible."""
    # The rejected first attempt, kept purely for this comparison. NOT
    # `bonehead_idle_sheet.png` — that name now holds the good faceless version, and
    # pointing here at it would compare the fix against itself and show nothing.
    a = "art/raw/bonehead_idle_FACED_REJECTED_sheet.png"
    b = "art/raw/body_idle.png"
    if not (os.path.exists(a) and os.path.exists(b)):
        return
    faced = list(frames_of(Image.open(a).convert("RGBA")))
    fixed = composite(b, "art/raw/face_idle.png")
    n = min(len(faced), len(fixed))
    sheet = Image.new("RGB", (CELL * n, CELL * 2), (24, 26, 32))
    ground = Image.new("RGBA", (CELL, CELL), (24, 26, 32, 255))
    for i in range(n):
        sheet.paste(on_ground(faced[i], ground), (CELL * i, 0))
        sheet.paste(on_ground(fixed[i], ground), (CELL * i, CELL))
    # Written into docs/, not art/preview/. `art-pipeline.md` cites this image as the
    # reason a face never goes through the generator, and a rule whose evidence lives in a
    # gitignored folder is a rule the next person has to take on trust.
    big(sheet).save("docs/images/face-degradation.png")
    print("  %-12s -> docs/images/face-degradation.png (committed evidence)" % "comparison")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("previews -> %s/" % OUT)
    for path in sorted(glob.glob("art/raw/body_*.png")):
        preview_animation(os.path.basename(path)[5:-4])
    preview_faces()
    preview_comparison()
