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
