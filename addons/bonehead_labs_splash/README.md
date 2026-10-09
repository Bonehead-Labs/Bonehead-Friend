# Bonehead Labs splash

The Bonehead Labs studio splash for every Bonehead Labs game: the boneheadlabs.org wordmark
("Bone", the mascot, "head" and the teal "Labs" pill) brought to life in about 4.25 seconds.
The mascot does the site's jump, the letters pop out of it, the pill springs on, and music
notes float off its headphones. Any key, click, touch or pad button skips it.

It is self-contained Godot 4.x (made on 4.7). It uses no autoloads, no project settings and
no classes from the host game, and it renders smoothly at any resolution: no pixel snapping,
no shaders, linear mipmapped textures and fonts re-rasterised at the screen's scale.

## Install

1. Copy this folder to `res://addons/bonehead_labs_splash/` in your project. Keep the folder
   name: the scene and font resources use that path. There is no editor plugin to enable.
2. Keep the `.import` files of `art/*.svg`. They import the SVGs at `svg/scale=0.6` with
   mipmaps, which keeps the mascot crisp from 720p to 4K. Without them Godot imports the SVGs
   at the defaults: the splash still works, but the mascot is softer.
3. Open the project once in the editor, or run `godot --headless --import`, to import the assets.

## Use it

As the main scene:

1. Set `application/run/main_scene` to `res://addons/bonehead_labs_splash/bonehead_labs_splash.tscn`.
2. Select the root node of that scene (or an inherited scene of it) and set `next_scene` to your
   menu.

Instanced from your own boot scene, which is the usual way to pass your game's settings in:

```gdscript
const SPLASH := preload("res://addons/bonehead_labs_splash/bonehead_labs_splash.tscn")

func _ready() -> void:
	var splash := SPLASH.instantiate()
	splash.next_scene = "res://ui/main_menu.tscn"  # or next_scene_packed = preload(...)
	splash.reduce_flashing = my_settings.reduce_flashing
	splash.audio_bus = &"UI"
	add_child(splash)  # configure before add_child: it starts in _ready
```

Apple Man Sam does this in `src/UI/Splash/BoneheadLabsSplash.gd`.

### Configuration

| Property | Default | Meaning |
|---|---|---|
| `next_scene` | `""` | Scene path opened when the splash finishes. |
| `next_scene_packed` | `null` | A `PackedScene` to open instead. It wins over `next_scene`. |
| `skippable` | `true` | Any key, mouse button, touch or pad button skips to the exit. A second press ends it at once. |
| `reduce_flashing` | `false` | The splash never flashes. With this on, its only large brightness change (the closing fade) runs slower. |
| `audio_bus` | `&"Master"` | The bus for its three short cues. A bus your project lacks falls back to Master. |
| `volume_db` | `0.0` | The cue level on top of the bus. |
| `subtitle_text` | `"GAME AND SOFTWARE STUDIO"` | The small line under the wordmark. Empty hides it. |
| `exit_color` | ink `#071b1e` | The colour the paper closes to before the hand-off. |
| `skip_argument` | `"--skip-splash"` | A user argument (after `--`) that skips the splash entirely, for dev launches. |
| `autoplay` | `true` | Off for tools that pose it with `evaluate(t)`. |

Signal `finished` is emitted once, when the splash has played out (or its skip exit has run),
just before it changes scene. With neither `next_scene` nor `next_scene_packed` set, it only
emits `finished`: the host frees it or changes scene itself.

Reads for tests and tools: `get_duration()`, `get_state()`, `get_layout_rects()`, `skip()`,
`evaluate(t)` (a pure function of time, so any instant can be posed and captured).

### Layout

The composition is designed on a 1920 x 1080 canvas and scaled uniformly to fit the control's
size, so it works with any stretch mode and aspect (16:9, 16:10, 21:9, 4:3).

## Boot splash

Godot shows its boot image while the engine starts. Use the splash's first frame for it, so the
boot and the splash meet without a cut. In Project Settings (`application/boot_splash/`):

| Setting | Value |
|---|---|
| `image` | `res://addons/bonehead_labs_splash/boot/bonehead_boot.png` (1920 x 1080) |
| `bg_color` | `Color(0.956863, 0.929412, 0.878431, 1)` (the paper, `#f4ede0`) |
| `stretch_mode` | `Keep` (`1`) |
| `use_filter` | `true` |
| `show_image` | `true` |

## Beat sheet

| Time (s) | Beat |
|---|---|
| 0.00 | The boot frame: paper, the teal and brass glows, the mascot standing on its shadow. |
| 0.22 | The site's jump (0.75 s): squash, leap with the happy face, land. |
| 0.70 | "Bone" and "head" pop out of the mascot letter by letter on the site's spring. A bone "k-tok" plays at 0.76. |
| 1.05 | The idle vibe sways in. Blinks at 1.95 and 3.05 (double). |
| 1.18 | The teal "Labs" pill springs on, with a pop. |
| 1.45 | The subtitle tracks in. |
| 1.62 | Music notes float off both cups with two marimba notes, then again at 2.34. |
| 3.55 | Exit: the stage lifts away and the paper closes to `exit_color`. |
| 4.25 | `finished`, then the next scene (4.65 with `reduce_flashing`). |

## Contents

| Path | What |
|---|---|
| `bonehead_labs_splash.tscn` / `.gd` | The splash. |
| `src/` | The mascot, the wordmark glyph renderer, the Labs pill, the paper field, the site's easings, and the generated mascot layout (`mascot_parts.gd`). |
| `art/mascot_*.svg` | The mascot's parts (shadow, body, cups, ink, mouth, open mouth, eyes, happy eyes), cropped from one coordinate space. |
| `art/note_*.svg` | The music-note glyphs (white, tinted at runtime). |
| `art/source/bonehead_mascot.svg` | The master SVG, with the site's groups and classes. It carries a `.gdignore`, so Godot neither imports nor exports it. |
| `fonts/` | Fraunces (wordmark), Spline Sans Mono (subtitle) and Commissioner (the site's UI face, unused here), as WOFF2. `fraunces_wordmark.tres` is Fraunces at wght 850, SOFT 100, WONK 1, opsz 72. `fraunces_display.tres` is the same at opsz 144. `spline_sans_mono.tres` is wght 500. |
| `audio/` | The three cues: `splash_land.wav`, `splash_pop.wav` and `splash_notes.wav`. |
| `boot/bonehead_boot.png` | The boot image: the splash's first frame. |

## Font licence

All three typefaces are under the SIL Open Font License 1.1. The copyright lines and the full
licence are in `fonts/OFL.txt`. Godot exports drop `.txt` files, so ship the licence text in
your game's credits or notices screen:

- Fraunces: Copyright 2020 The Fraunces Project Authors (github.com/undercasetype/Fraunces).
- Commissioner: Copyright 2019 The Commissioner Project Authors (github.com/kosbarts/Commissioner).
- Spline Sans Mono: Copyright 2022 The Spline Sans Mono Project Authors (https://github.com/SorkinType/SplineSansMono).

## Regenerating the assets

The generators live in the Apple Man Sam repository, outside this folder. Run them through the
project's Python venv (numpy, scipy, Pillow), from the repository root:

| Asset | Command |
|---|---|
| Mascot master SVG, from the site's JS bundle | `python scripts/art/brand/build_bonehead_brand.py extract --bundle <site_bundle.js>` |
| Mascot parts, notes, `src/mascot_parts.gd` | `python scripts/art/brand/build_bonehead_brand.py build`. `check` reports drift. |
| Cue WAVs (sfxkit recipes `bonehead_land`, `bonehead_pop` and `bonehead_notes`) | `python scripts/audio/build_splash_sfx.py`. `--check` reports drift. |
| Boot image and review stills | Run `scripts/capture_bonehead_splash.tscn` graphically with `--boot=<png>` and `--out=<dir> --times=...`. |

After regenerating, re-import in Godot. Re-capture the boot image after any change to the field,
the mascot or the layout.

## Tests (Apple Man Sam)

- `examples/BoneheadSplashStandalone_TestScene` uses this folder and a dummy next scene only.
  `scripts/test-bonehead-splash-clean.sh` builds a clean project with no autoloads and runs it
  there.
- `examples/BoneheadSplash_TestScene` covers the game's integration: the boot settings, the fonts,
  no shaders, the flashing budget, layouts at seven sizes, and the real boot flow with skips.
