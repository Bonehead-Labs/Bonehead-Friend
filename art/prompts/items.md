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

---

## The M3.7 leisure batch (20 items)

Same recipe as above — `rd_fast__low_res`, 48x48, 3 takes, magenta + `remove_bg`, then
`item_postprocess.py`. Seeds 37001-37020, $1.02 for the batch.

Prompts follow the same shape and add one clause the earlier batch did not need: **state the
viewing angle**. A teacup, a record player and a fish tank have obvious "correct" views that
differ from each other, and leaving it unsaid gave three-quarter views that fought the flat
side-on read of the existing roster.

| Item | px | Seed | Item | px | Seed |
|---|---|---|---|---|---|
| cup_of_tea | 18 | 37001 | houseplant | 44 | 37012 |
| donut_box | 22 | 37002 | lava_lamp | 40 | 37013 |
| ice_cream | 26 | 37003 | record_player | 38 | 37014 |
| noodle_bowl | 24 | 37004 | fish_tank | 44 | 37015 |
| birthday_cake | 34 | 37005 | wind_chimes | 40 | 37016 |
| beanbag | 44 | 37006 | fairy_lights | 22 | 37017 |
| foot_spa | 22 | 37007 | rubber_duck | 20 | 37018 |
| hammock | 38 (128 cell) | 37008 | jigsaw_puzzle | 30 | 37019 |
| paddling_pool | 40 (128 cell) | 37009 | bubble_machine | 34 | 37020 |
| heated_blanket | 30 | 37010 | | | |
| recliner | 72 (128 cell) | 37011 | | | |

Furniture he gets into uses the 128 cell, as the hot tub and massage chair do — the recliner
is legitimately taller than he is.

**A third thing learned the expensive way:** the presigned S3 URLs the API returns are bound
to their exact `Expires` value, and a three-take batch can straddle a second boundary — take 0
signed for `...368` and takes 1 and 2 for `...369`. Reusing one expiry for the whole batch
silently returns an XML error body saved as a `.png`. The session token also rotates between
requests. `dl.sh` in the scratchpad handles both by trying each token it has seen and checking
for the PNG magic number.

---

## The Codex batch — the five hands-on kind items and the fist (2026-09-07)

A different generator, so a different record. `docs/decisions.md` D44 said no image generator
was reachable from an agent session and shipped these five as plotted polygons. That was
wrong: the Codex CLI on this machine carries a native `imagegen` tool, and `codex exec`
drives it headlessly. `art/tools/codex_imagegen.sh` is the wrapper; D45 has the reasoning.

**There are no seeds.** `imagegen` takes a prompt and nothing else, so a generation cannot be
reproduced exactly the way a Retro Diffusion seed reproduces one. The prompt *is* the record
here, which is why each is written out in full below rather than summarised.

| Field | Value |
|---|---|
| Model | `gpt-5.6-luna` at low reasoning effort, about 32k tokens per image |
| Size | whatever the generator picks (1254x1254, or 1536x1024 when the prompt implies landscape) |
| Takes | one, judged, re-prompted if it failed — cheaper than three blind takes |
| Background | **magenta**, keyed out by `art/tools/keyout.py` (there is no `remove_bg`) |
| Post | `keyout.py --size 48` then `item_postprocess.py <raw> <id> <height>` |

### The recipe that worked

Every prompt ends with the same tail, and it is doing real work:

```
simple bold shapes, thick dark outline, flat solid colours, centred with generous
margin, on a plain solid magenta background, no text, no shadow, no gradient
```

`flat solid colours` is the clause that makes this generator usable at all — without it it
renders soft shading that survives neither the palette snap nor an 11-pixel reduction.
`no shadow` matters more than it looks: a cast shadow keys out as part of the subject and
becomes a grey smear welded to the silhouette.

### Sizes

Held to what the plotted versions measured rather than to the handoff's targets, so the
extents barely move and `seed_friendly` does not need re-running.

| Item | height passed | result | plotted before |
|---|---|---|---|
| tennis_ball | 13 | 13x13 | 13x13 |
| feather_duster | 11 | 16x11 | 27x11 |
| party_popper | 22 | 14x22 | 12x22 |
| warm_towel | 13 | 28x13 | 22x17 |
| kite | 26 | 18x26 | 20x26 |
| fist (32 cell, `--desaturate`) | 28 | 23x26 | 24x26 |

### The prompts

```
tennis_ball
a single tennis ball seen straight on, bright yellow-green felt with one curved white seam
line across it, <tail>

party_popper
a party popper cone firing upward, a teal cone body with a gold rim, and a burst of short
colourful streamers attached to and emerging from the open top, side view, <tail>

warm_towel
a neatly folded towel seen from the side as a single thick stack, cream fabric with one BOLD
wide teal horizontal band across the middle of the stack, the band about one third of the
total height, only two fold layers so the shape stays simple, <tail>

kite
a diamond kite seen face on, a teal and cream diamond sail split into quarters by a dark
cross spar, with a SHORT stubby ribbon tail attached to the bottom point, the tail no longer
than half the height of the sail, the whole kite compact and roughly as wide as it is tall,
<tail>

feather_duster  (take B of three)
a feather duster lying flat and horizontal, a thick warm brown wooden handle on the left
third, and on the right a fan of five or six SEPARATE pointed feather fronds spreading
outward like a hand of cards, each frond a distinct spike with a dark gap of background
visible between them, alternating light lilac and darker slate purple fronds, side view,
<tail>

fist  (keyed with --desaturate, 32px cell)
a clenched human fist seen from the front with the knuckles facing the viewer and the thumb
folded across the front of the fingers, a short wrist at the bottom, four distinct knuckle
bumps along the top edge, <tail>
```

### What each retry taught

**The despeckle pass is a judgement call, not a cleanup.** `keyout.py` keeps only the largest
connected mass, which is right for the party popper — its confetti is genuinely detached and
would be four stray pixels at 22px — and wrong for the kite, whose tail is a separate blob
and is half the point of the object. The kite is keyed with `--keep-all`. Read what the tool
dropped before accepting it; it reports the count for that reason.

**The towel lost its stripe the first time.** A pale teal line one fold thick averaged away
in the reduction to 13 pixels and left a plain cream slab. Asking for the band to be *a third
of the total height* is what made it survive. This is the same lesson `items.md` already
records for the minigun, arriving through a different door: a feature has to be a third of
the subject to exist at icon size, not a tenth.

**The feather duster took three takes and is still the weakest of the five.** A plume is one
material, so it has no internal edges — the first take reduced to a grey blob on a stick.
Asking for separated fronds with visible gaps (take B) got the structure back. Take C pushed
the separation further and produced a claw: five spikes with no mass between them stops being
a duster. The plotted version is still in git on `main` if the blob reads better in the shop
than the plume does.

**Judge after the palette snap.** The tennis ball's yellow-green has nowhere to land in a
palette with no yellow-green, so it snaps to the gold `#f2d06b` and reads as a yellow ball.
That is the right call and not a defect — but it is only visible after the snap, never in
the raw.

## The dual-tone pass — eight items that vanished on a dark desktop (2026-09-07)

`docs/assessment-2026-09.md` §3 lists ten near-black items that "collapse to silhouettes on a
dark desktop" and five that read wrong at 32 px. Eight of them are regenerated here. This is
not a style preference: the game draws over whatever the player has behind it, and an item
rendered in one dark material has no edge against a dark wallpaper and no internal edge
against itself. It is invisible twice over.

The fix the spec already described, applied as a prompt rule: **every one of these gets a
second, bright material carrying real area.** Not a highlight — a surface. Cream white, teal,
or gold, all three straight out of `art/src/palette.png`, so the snap has somewhere to put
them. Where the accent went is chosen to survive the downscale: on the part that carries the
silhouette (the mine's spikes), or across the largest flat face (the pan's interior).

| Item | height | before | after | the accent |
|---|---|---|---|---|
| mine | 20 | 22x20 | 17x20 | cream spikes, gold band |
| bowling_ball | 20 | 20x20 | 20x20 | teal stripe, cream finger holes |
| frying_pan | 30 | 64x30 | 58x30 | cream cooking surface, brown handle |
| gravity_vortex | 34 | 34x34 | 33x34 | teal glow on every arm's leading edge |
| swarm_launcher | 52 | 46x52 | 49x52 | teal tube mouths, gold rims |
| tyre_iron | 48 | 30x48 | 26x48 | cream polish down the shaft, gold socket |
| laser_lattice | 56 | 57x56 | 54x54 | teal corner nodes and crossing beams |
| implosion_charge | 30 | 36x30 | 27x30 | crossing teal seams, gold detonator cap |

`gravity_vortex` and `laser_lattice` are keyed with `--keep-all`: a vortex's arms and a
lattice's beams are legitimately separate masses, and the despeckle pass would have thrown
half of each away.

The two remaining near-black items were left alone. `monitor` and `sticky_bomb` already carry
a teal screen and a teal-and-brown band respectively, and both read on the dark strip.

The prompts follow the batch above exactly — subject, dark base material, the bright accent in
capitals, viewing angle, then the shared tail. The capitals are not decoration; dropping them
on the first towel attempt is what produced a stripe that averaged away.

**The frying pan is still 58 px wide**, against the assessment's complaint that it was 64 —
wider at 2x than the buddy is tall. Asking for a short handle bought six pixels. The real fix
is assessment finding 9, the scale table constraining width as well as height, and that is a
table change rather than an art change.

## The drawn pass — fourteen sprites that did not say what they were (2026-09-25, D62)

Every item and icon was laid out at game scale against a dark and a light desk, beside the
buddy, and ranked on one question: can a player tell what this is at 1x, in peripheral
vision? These fourteen could not. None was regenerated. Each is drawn as a text grid in
`art/pixel/<id>.txt` and built with `art/tools/pixel_sprite.py`, so **the grid is the record**
— there is no prompt or seed to keep, and each file's header says what the old sprite read as
and what the new one leans on.

| Item | before | after | read as | the redraw leans on |
|---|---|---|---|---|
| feather_duster | 16x11 | 26x12 | a grey smear | a pink serrated plume on a wooden handle, lying down (the handoff's design size) |
| mine | 17x20 | 24x12 | a spark | the only flat explosive: a pressure plate, a red light, a hazard band |
| grenade | 19x24 | 19x24 | a clay jug | the segmented egg, the spoon lever, the ring pin |
| dynamite | 14x26 | 14x26 | a fire extinguisher | three sticks, a strap, a lit fuse |
| foot_spa | 25x22 | 30x22 | a cooking pot | a basin seen from above, with two foot pads in the water |
| donut_box | 26x22 | 26x22 | a paper bag | the lid back, six rings with six holes |
| demolition_charge | 37x44 | 37x44 | a block of cheese | four bricks, two straps, a red countdown, a detonator |
| nail_bomb | 22x24 | 22x24 | a ladybird | a labelled tin with nails driven through it and a lit fuse |
| concussion_charge | 13x22 | 13x22 | a bottle | a vented canister with teal bands, a pin and a lever |
| tennis_ball | 13x13 | 13x13 | a coin | the two curved seams |
| wind_chimes | 14x40 | 14x40 | a grandfather clock | three tubes with daylight between them, a bar, a hook, a sail |
| jigsaw_puzzle | 28x30 | 28x28 | a brown box | one piece — two knobs out, two sockets in — with the lighthouse on it |
| sticky_bomb | 23x22 | 21x22 | a bowling ball in a sling | green goo over the top in four drips, a lit fuse |
| bubble_machine | 26x34 | 26x33 | a teal blob | a box, the wand wheel, a spout, bubbles drawn as rings |

**Three things learned drawing them.**

- **A solid white disc is a snowball.** The first bubbles were filled circles; a bubble is a
  ring with a shine, and the interior has to be a light colour rather than transparent, or
  the outline pass closes it into a black dot.
- **A strap both ways is a ribbon.** The demolition charge with tape crossing vertically and
  horizontally read as a wrapped present. Two horizontal straps and the timer read as a charge.
- **Evenly spaced nails are legs.** Three nails out of each side of the tin, level with each
  other, made a beetle. Nails at different heights and angles, and two out of the lid, made a
  tin someone filled with nails.

**Scenes.** Eight kept their exact size, so their derived colliders already match. Six did
not, and each was regenerated through its own seeder by deleting the scene and re-running it
without `--force`: feather_duster, foot_spa, jigsaw_puzzle and bubble_machine through
`seed_friendly`, mine through `seed_bodies`, sticky_bomb through `seed_m36_explosives`. Each
diff is two `size` lines and fresh `unique_id`s. ItemDB logs that it cannot load the item
while its scene is missing; none of those three seeders needs ItemDB to write a scene.

**Not redrawn, and why.** `hole_punch` (reads as a floppy disk), `satchel_charge` (a sack of
gold), `letter_opener` (a brown stick) and `halberd`'s icon (a hairline at 32 px) are all
multi-collider weapons, whose colliders are being re-authored against today's art in another
stream; redraw them after that lands, not before. `hornet` is small in the world but reads as
a wasp in its icon, and its circle is authored in `seed_m36_npcs`. `warm_towel` is a striped
slab but a legible one.

## The second five fidget toys, drawn (2026-09-26, D66)

Drawn as text grids like the D62 pass, so the grid is the record. Each file's header says
which rows and columns are which moving part. They were judged at 6x on a checkerboard and at
2x beside the bat, the stress ball, the spinner, the jack and the revolver
(`pixel_sprite.py --sheet`).

| Item | size | parts | leans on |
|---|---|---|---|
| slinky | 16x16 | `ring0`..`ring5`, one coil each | rainbow bands with a dark notch at each edge, and the open top ring. A steel one is a grey tin at 1x |
| newtons_cradle | 47x27 | `frame`, `ball` (one ball on its string, placed five times) | seven-pixel steel balls and one-pixel strings (`outline: off`), one ball pulled out in the shop picture. Its icon is a smaller drawing (`art/pixel/icons/`) |
| pull_back_car | 32x16 | `wheel` (the rear one, laid over both) | a white stripe and a headlight, so the way it faces reads, and a gold bolt on each hub, so the wheels can be seen turning |
| yo_yo | 14x14 disc | `disc`, `tail` (the loose string and finger loop) | the string. Without it the disc read as a red ball. The glint and the dark lower rim make a spin visible |
| slingshot | 16x23 | `frame`, `bands`, `pouch`, `pellet` | a wooden Y with a red grip wrap and amber bands, drawn one pixel wide (`outline: off`) |

One lesson: **a pulled ball over an upright is noise at 32 px.** The cradle's icon hangs all
five balls still, and only the 2x shop picture pulls one out.
## The second drawn pass — eight more, and icons for long things (2026-09-26, D69)

Same method as D62: every item laid out at game scale beside him on a dark and a light desk,
asked what it reads as in peripheral vision, and the grid is the record — no prompt, no seed.
Each file's header in `art/pixel/` says what the old sprite read as and what the new one leans
on.

| Item | before | after | read as | the redraw leans on |
|---|---|---|---|---|
| hole_punch | 26x24 | 28x22 | a floppy disk | from above and to one side: a red lever plate, two coiled plungers with daylight between, a sheet with two punched holes |
| satchel_charge | 42x40 | 42x40 | a sack of gold | green canvas, a leather strap arched over it, two buckled straps, three red sticks, 3:00 chalked on the pocket |
| letter_opener | 29x28 | 27x28 | a brown stick | brass all through: a slim blade lit along one edge, a bolster only a pixel proud, a red grip, a round pommel |
| halberd | 31x78 | 32x78 | a labrys on an invisible pole | one bearded axe with its edge lit, a hook, a spike, a wooden shaft, a steel butt |
| tesla_coil | 27x44 | 30x45 | an arcade joystick | a steel toroid, a column wound in copper, the primary's copper spiral round its foot, one spark |
| mortar | 33x40 | 33x39 | a telescope | short, fat, seventy degrees: an olive tube, a flared muzzle with the bore showing, a bipod, a base plate |
| heated_blanket | 42x30 | 42x30 | a raw steak | a pink quilt folded once, stitch crossings glowing where the wire runs, a turned-back corner, the controller on its cord |
| scythe | 41x76 | 41x76 | an outline on a dark desk | the same pixels recoloured: a steel blade lit on its back with a white edge, a dark collar, a wooden snath |

**Icons drawn, not stepped down** (`art/pixel/icons/<id>.txt`, built by `pixel_icon.py`, which
`make_icons.py` now leaves alone). Content before -> after, and its thickness across its own
axis:

| Icon | before | after | how |
|---|---|---|---|
| hunting_rifle | 28x6 | 27x29 | sprite rows doubled, eight columns of barrel out, laid on the 45-degree lattice; 6 -> 12 px across |
| pump_shotgun | 28x7 | 25x30 | barrel, tube and stock rows doubled, on the lattice; 7 -> 10 px across |
| blunderbuss | 28x9 | 22x29 | barrel and stock rows doubled, on the lattice, bell rim redrawn by hand; 7 -> 11 px across |
| halberd | 13x27 | 30x28 | its own shapes turned 45 degrees at two thirds, shaft shortened |
| scythe | 15x26 | 25x26 | its recoloured pixels turned 45 degrees at five eighths, snath shortened |
| tyre_iron | 14x25 | 25x30 | the sprite at full size with fourteen rows of bar cut out |
| satchel_charge | 29x28 | 30x30 | redrawn at 30px so the chalked time stays a time |
| tesla_coil | 17x29 | 24x30 | redrawn at 30px so the windings survive |
| heated_blanket | 29x21 | 30x22 | redrawn at 30px with the stitching every five pixels |

The hole punch and the letter opener fit the icon at 1x and are their own sprites; the mortar's
icon is `make_icons.py`'s two thirds, which keeps it.

**Four things learned drawing them wrong first.**

- **Straight on, a hole punch is a table.** A lid on two legs with daylight between them read as
  a bench, and filled in it read as a toaster. The three-quarter view with the sheet it has just
  punched is the one that says hole punch.
- **A crossguard makes a sword.** The first letter opener, in bright brass with a proper guard,
  was a gold dagger. Cut back to a bolster it is a desk tool.
- **Two holes in a frame is a face.** The punched sheet with round holes in a white box smiled
  back; lens-shaped holes do not. The satchel's 3:00 made the same face at two thirds.
- **A folded stack in red is dynamite.** The first heated blanket was three red folds lying on
  each other and read as a bundle of sticks. A quilt is flat, patterned and soft-cornered.

**Not redrawn:** the shotgun cursor's icon (turned, its pistol grip reads as a bent stick), the
bats and the rolling pin (solid, their short side is their real width), the hornet and the
swarm launcher (a speaker, but a legible one).
