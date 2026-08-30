# Item sprites

One record for the whole item batch: they share a recipe, and repeating it per item would
bury the two things that actually vary (the prompt and the target size).

| Field | Value |
|---|---|
| Style | `rd_fast__low_res` |
| Size | 48x48 generated, resized to the scale table |
| Takes | `num_images: 3`, pick the best |
| Background | **magenta**, with `remove_bg: true` |
| Cost | $0.051 per item (3 takes) |
| Post | `python3 art/tools/item_postprocess.py <raw> <id> <height>` |

## Two things learned the expensive way

**Do not pass `input_palette`.** Constraining colours at generation time sounds like the
cheapest route to a consistent set, and it wrecks the subject: the first sponge attempt came
back as a gold rectangle with an ectoplasm-green smear, because the palette has no dark
yellow and the model had nowhere to put the scouring pad. Let it render freely and snap the
palette afterwards — `item_postprocess.py` does, and the result is both on-palette and
recognisable.

**Say magenta, not white.** The tool guidance is to state a flat contrasting background and
pair it with `remove_bg`. White is one of *our* colours, so "on a plain white background"
put the background removal in competition with the sprite. Magenta appears in nothing we
own.

## Prompts

Every prompt states the subject, its material, "simple bold shapes", "thick dark outline",
and the background. Never "pixel art" — the style handles rendering.

```
sponge (15px, seed 30002)
a chunky rectangular kitchen sponge, bright yellow foam with a dark green scouring pad
bonded along its top face, soft rounded corners, simple bold shapes, thick dark outline,
viewed from the side, on a plain magenta background
```

## The batch

All at `rd_fast__low_res`, 3 takes each, magenta background, `remove_bg`, seeds 30001-30035.

| Item | px | Seed | Item | px | Seed |
|---|---|---|---|---|---|
| sponge | 15 | 30002 | baseball_bat | 52 | 30030 |
| pizza | 26 | 30010 | mace | 46 | 30031 |
| boombox | 40 | 30011 | dynamite | 22 | 30032 |
| frying_pan | 30 | 30012 | trash_bin | 40 | 30033 |
| beach_ball | 34 | 30013 | baseball | 10 | 30034 |
| bowling_ball | 20 | 30014 | missile | 28 | 30035 |
| grenade | 14 | 30015 | explosion (VFX) | 64 | 30020 |
| open_hand | 56 | 30036 | | | |

Icons are **not** generated — `art/tools/make_icons.py` downscales each sprite into a 32 px
cell. Free, and the icon is guaranteed to be the item it labels. Icons fit the cell rather
than holding world scale: a 10 px baseball at world scale would be four pixels in a shop row,
and the scale table governs the world, not the UI.

## open_hand — and the third thing learned

```
open_hand (56px, seed 30036)
an open human hand seen palm-forward with fingers spread and thumb out to the side, warm
pale skin, gently rounded fingertips, simple bold shapes, thick dark outline, on a plain
magenta background
```

**Desaturate a skin-toned subject before `item_postprocess.py`.** The project palette has no
skin tones, so the snap put the hand on the yellow/orange ramp and dropped its finger creases
onto `#c8382e` and `#8a2420` — the reds. A pale hand with red lines across it does not read as
a hand, it reads as an injured one. And the fist beside it in the Cursor category is grey, so
the pair looked like two unrelated objects.

The fix is one step before the pipeline, not inside it:

```python
grey = Image.merge("RGB", (r, g, b)).convert("L")
grey = ImageEnhance.Contrast(grey).enhance(1.35)
grey = ImageEnhance.Brightness(grey).enhance(1.30)   # lands on the pale end of the bone ramp
```

then `item_postprocess.py art/raw/open_hand_bone.png open_hand 56`. Greys snap onto the bone
ramp (`#fcfcee` / `#d8d6c4` / `#c3cad8` / `#9aa3b8`) that Bonehead himself is drawn in, which
is the right answer for a cursor hand anyway — it is *his* world reaching onto the desktop.

Take 0 of 3 was used: takes 1 and 2 both merged or broke the fingers.
