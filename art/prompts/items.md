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
| open_hand | 56 | 30036 | shotgun | 18 | 30037 |
| | | | pistol | 20 | 30038 |

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

## shotgun — M3.5-0

The one item in the M3 roster that shipped with no icon at all, so its shop row and its
augment tree both drew a category glyph where the toy should be.

```
shotgun (18px, seed 30037)
a pump-action shotgun seen from the side, dark steel barrel and receiver with a warm brown
wooden stock and fore-end, simple bold shapes, thick dark outline, on a plain magenta
background
```

Take 0 of 3 was used: a clean horizontal side view. Takes 1 and 2 both came back on a
diagonal with the muzzle running off the canvas — fine as a picture, wrong for a 32px shop
row, where a horizontal silhouette is the only one that survives the downscale.

Cost $0.051. It is a cursor power, so it has no world scale in the table; the sprite is
written at 18px purely so `make_icons.py` has something to derive from, which is also the
size it would take if it ever gained a body.

## pistol — M3.5-0

Not on the defect list, and generated anyway: with the shotgun drawn, the pistol was the
only row in the Cursor category still labelled by the prototype's crosshair PNG. Four rows,
three toys and one reticle pretending to be a toy.

```
pistol (20px, seed 30038)
a small revolver handgun seen from the side, dark steel barrel and cylinder with a warm
brown wooden grip, short barrel pointing right, simple bold shapes, thick dark outline, on
a plain magenta background
```

Take 0 of 3, chosen at icon size rather than at generation size — all three read as a
revolver at 4x, and only two survived the downscale to a 28px cell. Take 2 kept a stray red
pixel in the grip after the palette snap, which at icon size is a wound rather than a wood
grain. Cost $0.051.

The crosshair stays as the pistol's *cursor*: a single point is the right reticle for a
shot that lands exactly where it is aimed, which is the thing the shotgun's brackets exist
to contrast with.

## Cursors are plotted, not generated

`art/tools/make_crosshairs.py` draws the reticles the same way `make_ui_glyphs.py` draws
the UI symbols, and for the same reasons: they are geometry, they must land exactly on the
pixel grid, and a cursor that shifts by a pixel between builds is a cursor that no longer
points where it did. Free, and reproducible.

The shotgun's is four corner brackets around a centre dot — *this shot covers an area* —
against the pistol's single point. The open hand takes its own 32px icon as its cursor
rather than a reticle: it is a touch, not a shot.

## M3.5-A — the twelve missing catalog items

Same recipe as the M3 batch: `rd_fast__low_res`, 48x48, three takes, magenta background,
`remove_bg`, then `item_postprocess.py` at the scale table's size. Seeds 30039-30052,
$0.051 each.

| Item | px | Seed | Take | Item | px | Seed | Take |
|---|---|---|---|---|---|---|---|
| katana | 56 | 30039 | 0 | hot_tub | 70 (128) | 30044 | 0 |
| mine | 20 | 30040 | 0 | massage_chair | 76 (128) | 30045 | 0 |
| firework | 34 | 30041 | 0 | trampoline | 40 (128) | 30046 | 0 |
| desk_fan | 28 | 30042 | 2 | magnifying_glass | 34 | 30047 | 0 |
| chocolate_fountain | 50 | 30043 | 0 | lightning | 34 | 30050 | 2 |
| minigun | 40 | **30051** | 0 | gravity_vortex | 34 | 30049 | 2 |

Cursor powers have no world scale (art-direction.md), so their sprites are written at a
size that survives the downscale to a 32px icon and would be right if they ever gained a
body.

**Two takes were rejected at *icon* size, not at generation size.** Judging a 48px render
at 4x is judging a picture nobody will ever see: every item in this game is met as a 28px
row in a shop list first. Both failures only appeared there.

- **minigun (30048) — a dark blob.** The first prompt asked for "dark gunmetal on a boxy
  receiver", which is a single value across the whole silhouette; at 28px it was one grey
  smear with no gun in it. Regenerated at seed 30051 asking for a *brass* barrel cluster
  and a *teal* ammunition drum — two of the palette's own colours, on separate parts — and
  it reads instantly. The lesson is not "add contrast"; it is that a subject described in
  one material has no internal edges to survive a downscale.
- **gravity_vortex (30052) — the cyan retry lost.** The original (30049) came back a deep
  violet, and violet is not in the palette, so the snap sent it to the blue-greys: a dark
  whirlpool, which is what a gravity vortex should look like. Asking for cyan instead
  produced a bright ring that read as a portal or a petri dish, and the pink the snap put
  in the arms made it noisy. **Kept the original.** A colour the palette lacks is not
  automatically a problem — it is a problem when the subject needs that hue to be
  recognisable, and "dark" was the recognisable part here.

Four more reticles were plotted rather than generated, one per new cursor power: a ring
that dwells (magnifying glass), stacked rate bars (minigun), a pinwheel (vortex) and
chevrons closing on a point (lightning). Free, and each says what its power does before it
is fired once.

## Automation mounts — three pictures for twenty-eight devices

`Assets/sprites/devices/`, seeds 30060-30062, $0.153 the lot. A device on the desk is a
mount composited with the item's own sprite at runtime (`DeviceLayer`), so the roster's
twenty-eight capstones cost three generations rather than twenty-eight — and the twenty-eight
would all have been the same idea drawn again.

| Mount | px | Seed | Take | Holds |
|---|---|---|---|---|
| tripod | 34 | 30060 | 1 | weapons, throwables, props |
| pedestal | 20 | 30061 | 1 | the kind things |
| arm | 30 | 30062 | 2 | cursor powers, which have no world sprite of their own |

Each was prompted **empty** — "an empty camera tripod... no camera on it" — because the
generator will happily put a camera on a tripod, and a mount with something already on it
cannot hold anything else.

Where the item sits is measured, not authored: both pictures are centred in their cells by
`item_postprocess.py`, so the stack is (half the mount) + (half the item) - a five-pixel
overlap, read off each texture's own opaque bounds. A table of hand-tuned offsets would be
twenty-eight numbers to maintain across art that ranges from a 10px baseball to a 76px
massage chair.

## M3.6 — the roster explosion (48 items) and the NPCs

Same recipe throughout: `rd_fast__low_res`, 48x48, three takes, magenta, `remove_bg`, then
`item_postprocess.py` at the scale-table size. Seeds 30100-30147 for the items,
30200-30203 for the NPCs. Roughly $2.60 the lot, generated by seven agents working in
parallel over the shared queue.

**Everything was judged at 28 pixels, not at 4x.** That is the whole method now, and it is
what caught the failures: three takes that came back as the wrong object entirely (two
crossed swords instead of a greatsword; a symmetric red mallet instead of a fire axe), and
a chainsaw whose native diagonal scaled past its 64px cell and would have been silently
cropped at both ends — it was rotated ten degrees before processing to bring its aspect
back under 1.1.

Three lessons worth the space:

**"Blurred translucent" is a trap next to a magenta background.** The hornet's wings were
the only surface in nine takes to come back *pink*: translucency lets the background through
before `remove_bg` runs, and the palette's nearest colour to magenta is `#ffa6c1`. Ask for a
solid wing.

**Judge colour after the palette snap, not before.** The best goose pose had its webbed feet
snap to `#c8382e` — red feet at icon size read as injured, which is the same failure the
open_hand note above records. The take that won was chosen on where its colours landed after
the snap rather than on its pose.

**A subject in one material has no internal edges.** The raccoon is the weakest sprite in the
batch for exactly this reason and there is no honest fix in the prompt: a raccoon is one
texture. It survives because its silhouette carries ear triangles, a bandit mask and a
notched tail — which is what to reach for when the material cannot do the work.

## Automation walk cycles

`rd_advanced_animation__walking` on the gorilla's chosen raw take, 8 frames, 48x48,
`return_spritesheet`. $0.14.

Two things to know before using it again. It returns a **4x2 grid, not a strip** — a slicer
that assumes one long row finds four frames and half an animal. And it leaves specks that
are not attached to the subject: frames 5, 6 and 7 carried them, one an 84-pixel smear
beside the head. `NpcBase` slices the sheet itself because the generator produces a PNG and
the Aseprite Wizard route needs an Aseprite source; the cleanup is a connected-component
pass that keeps only the largest mass in each frame.
