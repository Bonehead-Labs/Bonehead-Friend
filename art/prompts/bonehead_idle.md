# bonehead — `idle`

The style proof for the whole buddy animation set. If the flat 4-colour look survives a
round trip through the animation service, every other tag is generated the same way.

| Field | Value |
|---|---|
| Asset | `art/src/bonehead.aseprite` → tag `idle` |
| Style | `rd_advanced_animation__idle` |
| Model | RD Advanced Animation |
| Size | 96×96 |
| Frames | 8 |
| Seed | `20260829` |
| Cost | $0.14 |
| Date | 2026-08-29 |
| task_id | `f2c9329b-df92-4f56-ba05-bf181f415184` |

## Input frame

`art/src/bonehead_neutral_96.png` — frame 0 of the prototype's `Assets/base-bonehead.png`,
with two corrections applied before sending:

1. **Snapped to the four real colours.** The prototype sprite carried 59 stray anti-aliased
   shades (~6% of its pixels), which violate `art-direction.md`'s no-AA rule and give the
   model a muddy signal about what "flat" means here.
2. **Padded from 64×64 to 96×96.** His feet were flush against the bottom edge, and the
   advanced-animation styles animate badly when opaque pixels touch the canvas edge.
   Content is 48×63, centred, with 12 px of ground beneath him.

## Prompt

```
a small rounded white bone-shaped character with two dot eyes and a simple smile, wearing
chunky teal over-ear headphones, standing still and breathing gently, a soft weight shift
from foot to foot
```

No "pixel art" in the prompt — the style parameter handles rendering, and saying it fights
the model (`art-pipeline.md`).

## Palette

Locked to the four colours already in the game, and re-applied to every generated frame
with the free `palette_converter` edit tool:

| Hex | Role |
|---|---|
| `#FFFFFF` | body |
| `#000000` | outline |
| `#2EB8B3` | headphones, friendly affordances |
| `#FCFCEE` | bone cream shading |
