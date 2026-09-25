# bonehead — body animation batch

The buddy's played-state animation set. `bonehead_idle.md` covers the style proof and the
face-degradation finding that shaped all of these; this is the batch that followed it.

## Shared setup

| Field | Value |
|---|---|
| Input frame | `art/src/bonehead_neutral_faceless_96.png` |
| Size | 96×96 |
| Output | `return_spritesheet=true` (PNG grid, not GIF) |
| Date | 2026-08-29 |
| Post-process | `python3 art/tools/postprocess.py art/raw/<file> <tag>` |

**Every prompt is faceless on purpose.** Two-pixel eyes do not survive the generator — they
dissolve into noise by the fourth frame (`bonehead_idle.md`, and
`art/preview/face_degradation_vs_layered.png`). The face is drawn by hand and positioned at
runtime from `Data/buddy_face_offsets.json`.

## Cost discipline

Three findings from pricing the API with free `estimate_inference_cost` calls, all of which
shaped this batch:

1. **Preset styles cost $0.14; `custom_action` costs $0.25.** Every tag below is mapped onto
   a preset — `hurt` onto `crouch`, `happy` onto `jump`, `collapse` onto `destroy` — rather
   than described freely at a 79% premium.
2. **Frame count is free.** 4 frames and 16 frames both cost $0.14, so each animation asks
   for the count it deserves rather than the cheapest one. `collapse` takes 16.
3. **Reverse playback and held frames are free.** `reassemble` is `collapse` reversed in
   Aseprite; `pile` is its last frame held. Two tags for no extra generation.

`dragged` is not generated at all — the pin joint already rotates him.

## The batch

| Tag | Style | Frames | Seed | task_id | Cost |
|---|---|---|---|---|---|
| `idle` | `rd_advanced_animation__idle` | 8 | 20260829 | `f2c9329b…` | $0.14 |
| `idle_sad` | `rd_advanced_animation__idle` | 8 | 20260830 | `6ed025a7…` | $0.14 |
| `idle_happy` | `rd_advanced_animation__idle` | 8 | 20260831 | `0ca7b903…` | $0.14 |
| `hurt` | `rd_advanced_animation__crouch` | 6 | 20260832 | `8dfd458f…` | $0.14 |
| `happy` | `rd_advanced_animation__jump` | 8 | 20260833 | `9da12e18…` | $0.14 |
| `collapse` | `rd_advanced_animation__destroy` | 16 | 20260834 | `135e4d22…` | $0.14 |
| `reassemble` | `collapse` reversed | — | — | — | $0.00 |
| `pile` | `collapse` last frame, held | — | — | — | $0.00 |
| `dragged` | hand-drawn | — | — | — | $0.00 |
| `walk` | drawn, `art/tools/make_walk.py` (D62) | 8 | — | — | $0.00 |

## Prompts

```
idle_sad
a small rounded white bone-shaped creature wearing chunky teal over-ear headphones, blank
featureless face, slumped and dejected, shoulders drooping, head hanging low, breathing
slowly and heavily, thick black outline

idle_happy
… blank featureless face, delighted and bouncy, bobbing up and down with light springy
energy, thick black outline

hurt
… blank featureless face, taking a heavy blow, body squashing down flat then springing
back, thick black outline

happy
… blank featureless face, hopping straight up with joy, squashing before the leap and
stretching at the top, thick black outline

collapse
… blank featureless face, toppling sideways and folding down into a loose heap of scattered
white bones with the headphones resting on top, thick black outline
```

No "pixel art" in any prompt — the style parameter handles rendering and saying it fights
the model (`art-pipeline.md`).

## Palette

Snapped to the four project colours by `postprocess.py` after download. The generator holds
the flat style well but leaks a few off-palette pixels per sheet — the first faceless idle
came back with six magenta ones.

| Hex | Role |
|---|---|
| `#FFFFFF` | body |
| `#000000` | outline |
| `#2EB8B3` | headphones |
| `#FCFCEE` | bone cream |

## `walk` — drawn, not generated (2026-09-25, D62)

It waited a milestone on `rd_advanced_animation__walking`; it is built from his own pixels
instead. `art/tools/make_walk.py` cuts `bonehead_neutral_faceless_96.png` at the top of the
knob flare and puts it back together eight times from a frame table: each foot lifts 2 then 4
art pixels, the upper body bobs one pixel at the passing frames and sways one pixel over the
planted foot. Nothing is recoloured, so the outline and shading are the generated body's own.
The lift is eased column by column across the notch between his feet; lifting each half as a
block left a white tooth hanging in the gap.

    python3 art/tools/make_walk.py
    python3 art/tools/postprocess.py art/raw/bonehead_walk_sheet.png walk

Tried and dropped: arm nubs cut from the `happy` hop (on a dark desk, two white dots floating
off his sides) and a sideways reach on the lifted foot (it fights the notch easing, and
`flip_h` already says which way he is going). Plays at 12 fps: a 0.67 s cycle, three steps a
second at his 117 px/s walking speed.

**Rebuilding the body file needs every tag's sheet in `art/raw/`, which is gitignored.**
Export them from the committed `.aseprite` first, one tag at a time (Windows paths):

    Aseprite.exe -b --tag <tag> art\src\bonehead.aseprite --sheet-type horizontal
        --sheet art\raw\body_<tag>.png

then run `_build_body.lua` with the full spec, `walk` last so frames 1-74 keep their numbers:
`idle:10,idle_sad:7,idle_happy:13,hurt:16,happy:14,collapse:18,reassemble:18,pile:3,dragged:4,walk:12`.
Checked after the rebuild: the first 74 frames and their durations are pixel-identical to the
file before it.

## The headphones fall with him (2026-09-25, D62)

The generated `collapse` left his headphones where his head had been: from its fourth frame
they hung in mid-air, and `pile` held them there for as long as he was down (assessment §3,
finding 8). `art/tools/drop_headphones.py` finds them on each frame as the detached piece with
the most teal, and lowers them whole — outline included, so nothing reopens — by `1.2 n^2`
pixels on the n-th frame after they come loose, until they meet the heap as measured on that
frame, then one two-pixel bounce and rest. `pile` gets them already resting; `reassemble` is
rebuilt as `collapse` reversed, as it always was, so they fly back onto his head. No pixel is
redrawn or recoloured. Patched in place with `_patch_frames.lua` (26 frames: collapse 5-16,
reassemble 1-12, both pile frames); tags, durations and face offsets are untouched.
