# Art Direction

## The character

Bonehead as drawn in the prototype (`Assets/base-bonehead.png`, 5 × 64×64 idle frames): a
small, rounded, cream-white chibi figure — big head, stubby limbs, two dot eyes, a simple
smile — wearing **teal over-ear headphones**.

Keep all of it. Two things about that design are load-bearing:

1. **He's soft, not scary.** Rounded silhouette, no visible ribs or grinning skull. That's what
   makes hitting him funny rather than grim, and it's what keeps the store rating clean.
2. **The headphones are the whole pitch in one prop.** He is already dressed for sitting on
   your desktop while you work. They make him readable at 64 px, they're the silhouette hook,
   and they're a free cosmetic slot (different headphones per skin). Never design him without
   them.

Uplift direction: more expressive, not more detailed. Bigger squash and stretch, a wider face
set, more anticipation before impacts. Resist adding rendering detail — he has to read clearly
at small size against an unknown background.

## Style rules

- **Pixel art, nearest-neighbour, no anti-aliasing** on sprite interiors.
- **64×64 cell grid** for characters and items; props and furniture may use 128×128. This is
  also the Retro Diffusion sweet spot.
- **Uniform on-screen scale.** The prototype is inconsistent — the character renders at 2×,
  bat and mace at 4×, missile 3×, grenade and fist at 1×. Standardise on **2× for everything**
  and author at the true pixel size instead of scaling up in-engine. Fix each asset as it's
  touched.

### The scale table

**The cell is a shared world-space frame, not a bounding box to fill.** Every prototype
sprite was drawn to fill its 64×64 cell, which is why a hand grenade came out 55 px tall
against a 63 px buddy — an explosive the size of his torso. Nothing enforced it, so nobody
noticed until the items were on screen together.

**There is a floor, and it is about 14 px.** Below that an item stops being recognisable:
the grenade was authored at its "correct" 14 px and came out a brown blob with no pin, no
lever and no identity. Realism loses to legibility — a hand grenade at 0.38x Bonehead is
generous and reads instantly, which is the point of the picture.

Anchor: **Bonehead's body is 63 px = 1.00**. Nothing scales with the window (`stretch/mode`
is disabled, so one world pixel is one screen pixel), so these ratios hold identically in a
480×360 play area and on a 3440×1440 overlay.

| Item | px | ×B | Item | px | ×B |
|---|---|---|---|---|---|
| Baseball | 14 | 0.22 | Beach Ball | 34 | 0.54 |
| Grenade | 24 | 0.38 | Firework Rocket | 34 | 0.54 |
| Sponge | 18 | 0.29 | Boombox | 40 | 0.63 |
| Mine | 20 | 0.32 | Trash Bin | 40 | 0.63 |
| Bowling Ball | 20 | 0.32 | Mace | 46 | 0.73 |
| Dynamite | 26 | 0.41 | Chocolate Fountain | 50 | 0.79 |
| Pizza | 26 | 0.41 | Baseball Bat | 52 | 0.83 |
| Desk Fan | 28 | 0.44 | Katana | 56 | 0.89 |
| Missile | 28 | 0.44 | Contract Board | 56 (128 cell) | 0.89 |
| Frying Pan | 30 | 0.48 | Hot Tub | 70 (128 cell) | 1.11 |
| Fist | 34 | 0.54 | Massage Chair | 76 (128 cell) | 1.21 |
| | | | Trampoline | 40 (128 cell, wide) | 0.63 |

**Automation mounts** are not items and are not in the table above: tripod 34, pedestal 20,
claw arm 30, in `Assets/sprites/devices/`. A device on the desk is one of those three
composited with the item's own sprite at runtime, so the size that matters is the *item's* —
the mount only has to look like it could hold one.

Furniture he sits in or on uses the 128×128 cell and is legitimately taller than he is.
Cursor powers (Pistol, Shotgun, Magnifying Glass, Minigun, Gravity Vortex, Lightning) have
no world sprite — a crosshair and a 32 px icon each.

`art/tools/item_postprocess.py` resizes every generated item to its entry here, so the table
is enforced rather than remembered.

- **Dark outline on everything.** Not optional. The game renders over an unknown background —
  a white IDE, a black terminal, a photo wallpaper. Every sprite needs a 1 px dark outline (or
  a dual-tone bright-core/dark-edge treatment for effects) or it will vanish on someone's
  desktop.
- **Readable at a glance from across the room.** The player is working; they see this in
  peripheral vision. Silhouette and pose carry the information, never fine detail.

## Palette

Locked in `art/src/palette.png` (used to snap every generated asset) and
`art/src/bonehead.gpl` for Aseprite — 24 colours. The buddy's four are a *subset*: he is
deliberately flat white, black, teal and cream, and items draw on the wider set.

Anchored on what already exists:

| Role | Use |
|---|---|
| Bone cream | The character's body — the brand colour |
| Teal / cyan | Headphones, UI accents, "friendly" affordances |
| Warm orange–red | Damage, explosions, Bones currency |
| Pink–magenta | Hearts, kindness feedback, mood-positive effects |
| Ghost green | Ectoplasm, prestige UI |
| Near-black | Outlines everywhere |

Lock the exact hex values into an Aseprite palette file (`art/src/bonehead.gpl`) once the first
production sprites exist, and run every generated asset through Retro Diffusion's palette
converter against it. That's what stops AI-generated assets drifting apart.

Currencies must be distinguishable by **shape as well as colour** (bone vs heart icons) for
colour-blind players — they're the two most-read symbols in the game.

## Animation inventory

Tag names must match the state names in `architecture.md` — Aseprite tags become Godot
animation names directly.

### Buddy — body (`art/src/bonehead.aseprite`)

Built so far — `art/src/bonehead.aseprite`, nine tags, 74 frames. ✅ means in the game.

| Tag | Frames | Notes |
|---|---|---|
| `idle` | ✅ 8 | Gentle bob |
| `idle_sad` | ✅ 8 | Low mood: slumped, slower |
| `idle_happy` | ✅ 8 | High mood: bouncy |
| `dragged` | ✅ 2 | Dangling from the cursor. Hand-made; the pin joint does the real work |
| `hurt` | ✅ 6 | Impact squash + recoil |
| `dizzy` | 4 | Post-heavy-hit stagger |
| `happy` | ✅ 8 | Delighted hop. Not in the original inventory; the buddy state machine plays it |
| `dance` | 8 | Boombox. The screenshot animation — spend real time here |
| `relax` | 4 | Hot tub, massage chair |
| `eat` | 4–6 | Pizza and snacks |
| `catch` | 3 | Baseball catch — the Interactive Buddy homage |
| `sleep` | 4 | Idle-too-long, and the hibernate state |
| `collapse` | ✅ 16 | Knockout: folds into the pile |
| `pile` | ✅ 2 | Bone-pile idle, faint settling. Last collapse frame, held |
| `reassemble` | ✅ 16 | Springs back together. `collapse` reversed — free, and guaranteed to match |

### Buddy — face (`bonehead_face.aseprite`, layered separately)

✅ All ten built: neutral, happy, blissful, sad, crying, angry, shocked, dizzy, asleep, smug.

Layering the face separately means mood reads independently of body pose, which multiplies the
expression set for very little work. It turned out to be load-bearing for a second reason: a
face does not survive the animation generator (`art-pipeline.md`), so keeping it separate is
what makes generated body animation viable at all.

The face is **one sprite the buddy repositions**, not a track baked per animation — ten
expressions across nine animations would otherwise be ninety sheets. `BuddyArt` reads
`Data/buddy_face_offsets.json` and moves it to the head every frame.

### Overlays

Grime/dirt (3 escalating stages, cleared by the sponge), soot after explosions, sparkle after
cleaning, a small mood aura.

### Items

Each: one 64×64 idle sprite, one 32×32 UI icon, plus per-item extras (muzzle flash, projectile,
impact). Generate the whole family from one reference image so they read as a set.

### VFX

Impact stars, bone chips, dust puffs, explosion (replacing the prototype's untextured
`CPUParticles2D`), sparkle, heart burst, coin/bone burst for the knockout fountain.

**All VFX must be visible on white, on black, and on a busy photo.** Test on all three before
accepting one — this is the single most common way an overlay game's effects fail.

## UI — Bonecard

The skin, chosen at the end of M3 from four candidates mocked up side by side (Bonecard,
Deskmate, Bone Terminal, Toybox). Bonecard won on legibility over an unknown desktop: it is
**printed card**, and everything below follows from that one idea.

Built as a real `Theme`, in code, by `Scripts/UI/ui_theme.gd`. Panels never assemble their own
styleboxes; they say what a control *is* (`theme_type_variation = &"Tile"`) and the theme
answers. `Scripts/UI/ui_style.gd` holds the numbers below and nothing else.

### Surfaces

| Token | Hex | Use |
|---|---|---|
| `PANEL` | `#FCFCEE` | card stock — the ground for everything |
| `RAISED` | `#F0EEDC` | a tile sitting on the card |
| `SUNK` | `#DFDCC6` | a well: a meter track, a sprite slot, a disabled tile |
| `EDGE` | `#000000` | every rule in the UI, at **3 px**, never thinner and never softer |
| `TEXT` | `#17140E` | ink |
| `TEXT_DIM` | `#6B6450` | secondary ink |

**Opaque, always.** The window is per-pixel transparent, so alpha below 1 shows the player's
wallpaper through the text (D6). Motion may fade a control that sits *on* a card; it must
never fade a card.

Colour carries meaning and nothing else: `BONES #A9713F`, `HEARTS #A83A63`,
`ECTOPLASM #2E7D5B`, `TEAL #1B7A76` (automation, and nothing else). No corner radius anywhere.

### Type — one family, two pixel weights

- **Jersey 25** (`Assets/fonts/Jersey25-Regular.ttf`) — display: buttons, labels, and every
  figure. Sizes 16 / 20 / 26 / 32 (`MICRO` / `LABEL` / `TITLE` / `HERO`).
- **Jersey 15** — reading: descriptions and explanations. Sizes 16 / 20 (`BODY` / `NAME`).
- **DotGothic16** — the CJK fallback, in the same pixel idiom, with a `SystemFont` under it.

The two Jerseys are the same face drawn on a coarser and a finer pixel grid, which is why
they pair without reading as two fonts. They replaced Silkscreen + Pixelify Sans after a
playtest found the pair hard to read: Silkscreen is caps-only so every label shouted, and
Pixelify draws `5` as a rounded form that reads as an `8` — "+15% damage" was
indistinguishable from "+18%".

**Sizes are chosen by measured cap height**, not by eye. The first attempt at making the UI
bigger doubled the numbers and the panel ate the whole window; the ladder above is about a
quarter taller than the one it replaced, which is a deliberate step. Measure before changing
it.

All faces are loaded with antialiasing, hinting and subpixel positioning **off**; a pixel
face rendered with the defaults is a blurry pixel face.

### Contrast

Every ink clears **4.5:1** against every surface it is printed on, and `loop_check` asserts
the whole grid (docs/decisions.md D26). No text is ever dimmed with alpha — a disabled
control uses `UIStyle.DISABLED_INK` and says it is disabled with its shape.

### Glyphs

`art/tools/make_ui_glyphs.py` draws the set by hand into `Assets/sprites/ui/` — white on
transparent, 16×16, so one texture serves every tint. They never go through Retro Diffusion:
they are sixteen pixels across, they must land exactly on the grid, and a currency may not
change shape between builds.

`bone` `heart` `ecto` · `lock` `check` `cross` `star` `bolt` · `hand` `spawn` `close` ·
`crate` `scroll` `sliders`

**Currencies must be separable by shape as well as colour**, and so must node state. About one
player in twelve cannot use the red/green distinction these lean on, and Bones and Hearts are
the two most-read symbols in the game. A price is a glyph and a number, never a letter and a
number; a locked node is a padlock, a taken branch is a tick, a closed branch is a struck-out
card.

Pictures are drawn at **one screen pixel per art pixel** — `STRETCH_KEEP_CENTERED`, never an
aspect-fitting mode. Item icons are 32 px canvases and sit in 44 px wells; item sprites are
64 px canvases and sit in the 72 px mastery well.

### Motion

`Scripts/UI/ui_motion.gd`. The vocabulary, and what each is for:

| Motion | Where |
|---|---|
| key lift / squash / overshoot | every button, on hover, press and release |
| row lift + sprite nudge | hovering a price reacts on the *row*, so the toy you are buying moves |
| card grow from its own corner | a panel opening; never a fade, because a fading card shows the desktop |
| staggered deal-in | rows arriving on a page, capped at 14 so a long shop does not crawl |
| gold bloom + punch | a purchase, on the tile you bought from |
| rotation buzz + red wash | a refusal — an unaffordable price stays live so it can say no out loud |
| a coin thrown into the purse | a purchase, launched from the press and caught by the chip |
| rolling figures | the purse, eased toward the balance rather than snapping to it |

Timings are short (50–300 ms) and fixed; only the *amounts* scale with Focus Mode, because a
gentler setting must not mean a slower UI. All of it is off when Focus Mode is Off, and in
headless — see D21.

Three constraints the library exists to enforce, each a bug already paid for: never animate
`position` or `size` on a control inside a `Container` (the container rewrites both on the next
layout pass — `scale`, `rotation`, `pivot_offset` and `modulate` are the ones that are ours);
never fade a card; and every named motion owns a single tween slot per control, or a fast cursor
leaves two scale tweens racing and the button settles wherever the loser stopped.

### Still to draw

- Damage numbers: white and small by default (they appear constantly and must stay readable),
  colour-coded per damage type, big and bold only for genuinely significant hits. Cap the number
  on screen at once and merge rapid hits into a running combo total.
- Crosshair and cursor art for the four cursor powers.
- A 9-slice card texture, if the flat 3 px rule ever stops being enough. It has not yet.

## Sound

No audio exists yet — this is greenfield, and it matters more here than in most games because
the game is *running all day*.

- Layer 2–3 samples per impact (transient + body + tail).
- **Randomise pitch ±10–15% on every play.** Non-negotiable: an unvaried sample heard a thousand
  times in one workday becomes torture.
- Material-specific impacts: bone, metal, wood, wet, soft.
- Voice cap ~8 simultaneous, with a limiter — an automation cascade must never machine-gun
  someone's headphones during a meeting.
- Default volume low. Ship **mute-when-unfocused** as a default-on option.
- Signature sounds worth getting right: the bone-pile clatter on collapse, the rattle on
  reassembly, and the coin fountain. Those three play more than anything else in the game.
