#!/usr/bin/env python3
"""Draw the UI glyph set — the small symbols the panels are built out of.

    python3 art/tools/make_ui_glyphs.py [--out Assets/sprites/ui]

These are not generated art and they never go through Retro Diffusion: they are eight
to sixteen pixels across, they must land exactly on the pixel grid, and they have to be
*identical* every time so a currency never changes shape between builds. Hand-plotting
them here makes them reproducible and free.

Why they exist at all: `docs/art-direction.md` requires the currencies to be separable by
shape as well as colour, because a red/green heart-and-bone pair is the single most-read
thing in the game and roughly one player in twelve cannot use the colour difference. The
same applies to node state — locked, chosen and struck-out are a lock, a tick and a cross,
not three shades of the same chip.

Every glyph is drawn white with an alpha mask, so the game tints one texture per currency
rather than shipping a coloured copy of each.
"""

import argparse
import os

from PIL import Image

CANVAS = 16

# '#' opaque, '.' transparent. Drawn small, centred on the canvas by _centre().
GLYPHS = {
    # --- currencies: the three things the player counts ---------------------
    # The waist has to be long relative to the knobs or the silhouette reads as a
    # dumbbell — which is what the first pass did.
    "bone": [
        ".###.......###.",
        "#####.....#####",
        "#####.....#####",
        "###############",
        "###############",
        "#####.....#####",
        "#####.....#####",
        ".###.......###.",
    ],
    "heart": [
        ".###...###.",
        "###########",
        "###########",
        "###########",
        ".#########.",
        "..#######..",
        "...#####...",
        "....###....",
        ".....#.....",
    ],
    # Ectoplasm is the prestige currency and it is a ghost, which is also the joke: you
    # only get it by killing the run.
    "ecto": [
        "...#####...",
        "..#######..",
        ".#########.",
        ".##.###.##.",
        ".##.###.##.",
        ".#########.",
        ".#########.",
        ".#########.",
        ".#########.",
        ".#.#.#.#.#.",
    ],

    # --- node and tile state ------------------------------------------------
    "lock": [
        "..#####..",
        ".##...##.",
        ".##...##.",
        "#########",
        "####.####",
        "####.####",
        "#########",
        "#########",
    ],
    "check": [
        ".......##",
        "......###",
        ".....###.",
        "##...###.",
        "###.###..",
        ".######..",
        "..####...",
        "...##....",
    ],
    "cross": [
        "##.....##",
        "###...###",
        ".###.###.",
        "..#####..",
        "...###...",
        "..#####..",
        ".###.###.",
        "###...###",
        "##.....##",
    ],
    # Mastery. Ranks are the one number that never resets, so they get the star.
    "star": [
        ".....#.....",
        "....###....",
        "....###....",
        "###########",
        ".#########.",
        "..#######..",
        "...#####...",
        "..##...##..",
        ".##.....##.",
    ],
    # Automation: the capstone that earns while the game is closed.
    "bolt": [
        "....###",
        "...###.",
        "..###..",
        ".#####.",
        "..####.",
        "...##..",
        "..##...",
        ".##....",
    ],
    # The open hand is a cursor power, so it has no world sprite to shrink down.
    "hand": [
        "..#.#.#..",
        ".##.#.##.",
        ".##.#.##.",
        ".#######.",
        "##.#####.",
        "#########",
        "#########",
        ".#######.",
        "..#####..",
    ],
    # Spawn: the verb on every owned toy's button.
    "spawn": [
        "...##...",
        "..####..",
        ".######.",
        "########",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
    ],
    "close": [
        "##.....##",
        ".##...##.",
        "..##.##..",
        "...###...",
        "..##.##..",
        ".##...##.",
        "##.....##",
    ],
    # The panel's own tab row needs marks that are not item sprites. Sliders rather than
    # a cog: at eleven pixels a cog's teeth turn to mush and it reads as a lifebuoy.
    "sliders": [
        "...###.....",
        "###########",
        "...###.....",
        "...........",
        ".......###.",
        "###########",
        ".......###.",
    ],
    "crate": [
        "###########",
        "#.#######.#",
        "#.#######.#",
        "###########",
        "#####.#####",
        "#.........#",
        "#.........#",
        "###########",
    ],
    "scroll": [
        "###########",
        "#.........#",
        "#.#######.#",
        "#.........#",
        "#.#####...#",
        "#.........#",
        "#.#######.#",
        "#.........#",
        "###########",
    ],
}


def _centre(rows: list[str]) -> Image.Image:
    """Put a glyph on the shared canvas so every icon has the same footprint.

    A shared canvas is what keeps a heart and a bone optically the same size in a price
    row; sizing each texture to its own content makes the taller glyph shout.
    """
    height = len(rows)
    width = max(len(r) for r in rows)
    if width > CANVAS or height > CANVAS:
        raise ValueError("glyph is %dx%d, larger than the %d canvas" % (width, height, CANVAS))
    image = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 0))
    ox = (CANVAS - width) // 2
    oy = (CANVAS - height) // 2
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char == "#":
                image.putpixel((ox + x, oy + y), (255, 255, 255, 255))
    return image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="Assets/sprites/ui")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)

    for name, rows in sorted(GLYPHS.items()):
        path = os.path.join(args.out, "%s.png" % name)
        _centre(rows).save(path)
        print("  %-8s %s" % (name, path))
    print("%d glyphs -> %s" % (len(GLYPHS), args.out))


if __name__ == "__main__":
    main()
