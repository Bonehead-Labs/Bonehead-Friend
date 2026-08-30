# Fonts

All SIL Open Font License 1.1, redistributed with their licence text as the OFL requires.
Downloaded from Google Fonts; the licences came from `google/fonts` on GitHub.

| File | Family | Job |
|---|---|---|
| `Jersey25-Regular.ttf` | Jersey 25 | display — buttons, labels, **every figure** |
| `Jersey15-Regular.ttf` | Jersey 15 | reading — descriptions and explanations |
| `DotGothic16-Regular.ttf` | DotGothic16 | the CJK fallback, in the same pixel idiom |

Jersey 15 and 25 are the same face drawn on a finer and a coarser pixel grid, which is why
they pair without reading as two fonts. They replaced Silkscreen + Pixelify Sans after a
playtest: Silkscreen is caps-only so every label shouted, Pixelify draws `5` as a rounded
form that reads as an `8`, and neither was comfortable at the size the panels use.

Sizes are chosen by **measured cap height**, not by eye — see the ladder in
`Scripts/UI/ui_style.gd`. Loaded by `Scripts/UI/ui_theme.gd` with antialiasing, hinting and
subpixel positioning **off**; a pixel face rendered with the engine defaults is a blurry
pixel face.

DotGothic16 covers kana and the common kanji, with a `SystemFont` under it for the Korean
and Simplified Chinese it does not reach. A missing glyph is therefore a pixel glyph rather
than a box or an incongruous system serif.
