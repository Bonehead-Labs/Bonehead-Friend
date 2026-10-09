# Art Pipeline

**Retro Diffusion → Aseprite → Godot.** AI-generated pixel art, hand-corrected and animated in
Aseprite, imported automatically by Aseprite Wizard. Designed to be reusable across projects:
the tools are configured at user scope, and only the repo layout is project-specific.

## Setup

### 1. Retro Diffusion MCP (hosted — nothing to install)

Official server at `https://mcp.retrodiffusion.ai/mcp`, authenticated with a `rdpk-` key.

Preferred install (bundles the server *and* a cost-aware workflow skill):

```
/plugin marketplace add Retro-Diffusion/retro-diffusion-mcp
/plugin install pixel-art@retro-diffusion
```

Or the bare server:

```bash
claude mcp add --transport http retro-diffusion --scope user \
  https://mcp.retrodiffusion.ai/mcp \
  --header "Authorization: Bearer ${RD_API_KEY}"
```

**The key never enters the repo.** Set `RD_API_KEY` in `~/.claude/settings.json`'s `env` block
or the shell profile. If a project-level `.mcp.json` is ever committed, it may reference
`${RD_API_KEY}` but must never contain the value. Note that Retro Diffusion's own sample config
uses `${env:RD_API_KEY}` — that is VS Code syntax and does **not** expand in Claude Code; use
`${RD_API_KEY}`.

Smoke test: `get_service_status`, then `get_balance`.

### 2. Aseprite Wizard (Godot addon) — ✅ installed

`viniciusgerevini/godot-aseprite-wizard` **v9.8.0** is installed at `addons/AsepriteWizard/`,
enabled in `project.godot`, with the command path already set to the Windows Aseprite path:

```ini
[aseprite]
general/command_path="C:\\Program Files (x86)\\Steam\\steamapps\\common\\Aseprite\\Aseprite.exe"
```

It must be the **Windows** path — the Godot editor is a Windows process.

`.aseprite` files import as `SpriteFrames` automatically, via:

```ini
[aseprite]
import/import_plugin/default_automatic_importer="SpriteFrames"
```

Other importer values: `"Static Texture"`, `"Tileset Texture"`, `"SpriteFrames (Split By Layer)"`,
`"No Import"` (the addon's default — it produces an inert resource, which is why we override it).

**Verified end-to-end 2026-08-28**, on Godot 4.7.2 with Aseprite 1.3.18.3: the prototype's
320×64 idle strip was sliced into a 5-frame tagged `.aseprite` by headless Aseprite, imported
by the addon, and loaded back in Godot as a real `SpriteFrames` with a looping `idle`
animation. The addon's 4.7 compatibility was the open risk in the research; it is settled.

In-editor check: *Project → Tools → Aseprite Config* should print a version, not "command not
found".

### Driving Aseprite headlessly

`art/src/_build_body.lua` is the worked example — it assembles every generated animation
into one multi-tag source. Two things that will waste your time:

- **Pass paths with `--script-param`, never environment variables.** Aseprite is a Windows
  process; WSL env vars do not cross the boundary without `WSLENV` plumbing. In Lua they arrive
  as `app.params["in"]`.
- **Every path in the argument list must be a Windows path**, including the script's own path.

```bash
ASE="/mnt/c/Program Files (x86)/Steam/steamapps/common/Aseprite/Aseprite.exe"
P='C:\Users\George\Godot Projects\Projects\bonehead-friend'
"$ASE" --batch \
  --script-param "dir=$P\\art\\raw" \
  --script-param "out=$P\\art\\src\\bonehead.aseprite" \
  --script-param "cell=96" \
  --script-param "spec=idle:10,idle_sad:7,hurt:16,collapse:18,pile:3" \
  --script "$P\\art\\src\\_build_body.lua"
```

`spec` is `tag:fps` pairs and each reads `<dir>\body_<tag>.png`. The whole file is rebuilt
every time — see the tag-extension gotcha below for why it cannot be done incrementally.

An `aseprite` MCP server (`diivi/aseprite-mcp`, 104 tools) is also registered at user scope for
programmatic canvas, layer, frame and palette work. It runs Windows-side through
`uv.exe --directory 'C:\Users\George\Tools\aseprite-mcp'` for the same path reason.

What it buys: `.aseprite` files become first-class Godot resources. Each Aseprite **tag becomes
an animation**, frame durations convert from milliseconds to Godot FPS automatically, and layer
filtering by regex lets reference/guide layers live in the source file without reaching the
export. It's editor-only — remove it later and imported animations keep working.

### 3. Aseprite MCP (optional, for programmatic editing)

`diivi/aseprite-mcp` — 104 tools covering canvas, drawing, layers, frames and tweening,
palettes, effects, spritesheet export, plus a raw Lua escape hatch. Not on PyPI; clone it.

**It must run as a Windows process.** Aseprite is a Windows executable and cannot resolve the
`/tmp` and `/mnt/c` paths a WSL-side server would hand it. Same pattern as the existing Blender
MCP on this machine:

```bash
claude mcp add aseprite --scope user \
  --env ASEPRITE_PATH='C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe' \
  -- /mnt/c/Users/George/.local/bin/uv.exe \
     --directory 'C:\Users\George\Tools\aseprite-mcp' run -m aseprite_mcp
```

The deliberate mix: `command` is the WSL path to the Windows `uv.exe` (that's what the Linux
Claude process must exec), while `--directory` and `ASEPRITE_PATH` are Windows paths (that's
what the resulting Windows process sees). Convert with `wslpath -w` when in doubt.

Aseprite also drives fine straight from the CLI —
`aseprite --batch --script x.lua`, `--sheet out.png --data out.json`, `--split-layers`,
`--frame-range` — if a scripted step is simpler than an MCP round-trip.

## Repo layout

```
art/
  prompts/     # one file per asset: prompt, style, seed, model, date. THE reproducibility record
  raw/         # untouched generator output (gitignored — regenerable from prompts/)
  src/         # .aseprite working files ← Aseprite Wizard imports from here
Assets/sprites/<entity>/   # exported PNGs consumed by scenes
```

Recording prompt + style + **seed** is what makes the pipeline reusable rather than one-shot:
reusing a seed iterates the same composition instead of rolling a new one.

## Workflow

1. **Estimate first.** `estimate_inference_cost` is free. Use it before any batch.
2. **Generate.** `create_inference` for stills; `start_inference_job` for animations and
   batches. Sizes 16–384 px (per-style limits — query `list_available_styles`; treat that
   response as authoritative). Costs run ~$0.015 (RD Fast) to ~$0.18 (RD Pro) per image,
   $0.07–0.25 per animation.
3. **Never write "pixel art" in the prompt.** Describe the subject only — the style parameter
   handles the rendering. Saying it fights the model.
4. **Never blind-retry.** Generation is non-idempotent and can charge before a failure is
   visible. If output URLs are missing, call `get_inference_result(request_id)`, or recover a
   lost async job with `list_inference_jobs`. Retrying is how you pay twice.
5. **Download immediately.** Output URLs are short-lived. Save into `art/raw/` and write the
   matching `art/prompts/<asset>.md` in the same step.
6. **Consistency.** Generate a hero asset with RD Pro, then pass it as a reference image (up to
   9 references supported) for everything in the same family. Reuse seeds when iterating.
7. **Clean up.** Free/cheap edit tools: `fix_pixel_art`, background remover, palette converter,
   colour reducer, K-centroid downscale. Run the palette converter against the project palette
   (`art-direction.md`) so nothing drifts off-style.
8. **Author in Aseprite.** Import to `art/src/<name>.aseprite`, fix by hand — AI output is a
   *starting point*, not a deliverable — then tag animations (`idle`, `hurt`, `happy`, …).
   Tag names become Godot animation names, so use the state names from `architecture.md`.
9. **Import.** Save the `.aseprite`; Aseprite Wizard reimports. Check filter is Nearest and
   compression is Lossless.
10. **Commit** the `.aseprite` source, the exported PNG, and the prompt record. Not `art/raw/`.

### Rate limits and caps

`fix_pixel_art`: 10 requests/minute per key. Request payloads cap around 900 KB, responses
850 KB. Input images: 16×16 minimum, 4 MP maximum.

## Godot import settings

- Project-wide `rendering/textures/canvas_textures/default_texture_filter = 0` (Nearest) —
  already set correctly.
- Add `rendering/2d/snap/snap_2d_transforms_to_pixel = true` to kill sub-pixel shimmer on
  moving sprites.
- Per-texture: **Compress → Lossless**, never Lossy. Filter → Project Default.
- After changing project-wide import settings, **reimport everything** — existing `.import`
  sidecars keep the old values.

## Cost model (measured 2026-08-29)

`estimate_inference_cost` is free — every figure here came from it, not from a guess.

| What | Cost |
|---|---|
| `rd_advanced_animation__*` **presets** (idle, walking, jump, crouch, attack, destroy, subtle_motion) | **$0.14** |
| `rd_advanced_animation__custom_action` | **$0.25** |
| `rd_animation__any_animation` | $0.25 |
| RD Pro still, 64×64 | $0.18 |
| RD Fast still (batch of 4) | ~$0.017 each |
| `palette_converter`, `color_reducer`, `pixel_correction`, `k_centroid_downscale`, `rotate` | free |

Three consequences worth planning around:

1. **A preset is 44% cheaper than `custom_action`.** Map the animation you want onto the
   nearest preset before reaching for the flexible one — `hurt` is a `crouch`, `happy` is a
   `jump`, a collapse into a bone pile is a `destroy`.
2. **Frame count is free.** 4 frames and 16 frames both cost $0.14, so ask for the count the
   animation deserves. Only the hand-fixing afterwards scales with frames.
3. **Reversal and held frames are free.** `reassemble` is `collapse` played backwards;
   `pile` is its last frame held. One generation, three tags.

## Gotchas

- **Do not send a face through the animation generator.** Two-pixel eyes are not enough
  signal: they wander, melt and vanish by about the fourth frame, and the black outline
  starts picking up other palette colours at the same time. Generate the character
  *faceless* and composite a hand-drawn face on top —
  [`docs/images/face-degradation.png`](images/face-degradation.png) is the side-by-side
  (top row through the generator, bottom row layered). This is the same
  layered arrangement `art-direction.md` already asked for, for a different reason.
- **A composited face needs per-frame offsets.** The head moves up to 11 px across an idle
  loop and 29 px during a collapse, so a face pinned at a fixed position detaches
  immediately. `art/tools/postprocess.py` measures the head on every generated frame and
  writes `Data/buddy_face_offsets.json`; frames where the head has dropped far below rest
  get `null` and no face at all, because he is a heap of bones by then.
- **Build a multi-tag `.aseprite` in one pass, tags last.** `Sprite:newFrame()` appends at
  the end and Aseprite silently extends any tag whose range already ends at the last frame.
  Adding nine animations one at a time therefore left all nine tags ending at the final
  frame — `idle` imported as 74 frames instead of 8 and Godot played the whole file for
  every animation. The tags are correct at the moment each is created, and are stretched by
  the *next* append, so nothing looks wrong until you probe the finished file.
  `art/src/_build_body.lua` adds every frame first and creates every tag afterwards.
- **The generator leaves the outline open.** Between 110 and 190 edge pixels per animation
  come back as bare white or teal against transparency. On a dark desktop nobody notices;
  on a white one he dissolves, which is exactly the failure `art-direction.md` makes the
  outline non-negotiable to prevent. `postprocess.py` closes it by painting black into every
  transparent pixel that touches an un-outlined body pixel — outward, so the body keeps its
  mass. **Any transform that moves pixels reopens it**, so rotate first and outline after.
- **Detached litter needs an allow-list, not a size threshold.** `idle_sad` came back with
  55-67 px blobs floating above his head on two frames of eight. They are not meaningfully
  smaller than the headphones, which legitimately detach during the collapse — the only
  thing separating them is which animation they appeared in. `KEEPS_DETACHED_PIECES` names
  the tags where a loose piece is the gag rather than the defect.
- **Aseprite Wizard imports every tag as looping.** Correct for an idle, wrong for a
  knockout — a collapse that loops never lets him get back up. Clear the loop flag on
  one-shots after loading (`BuddyArt.ONE_SHOT`).
- Filenames: no spaces (`Assets/baseball bat.png` is a prototype-era mistake), and exact case
  everywhere — `res://` paths are case-sensitive in exported builds even though the Windows
  editor forgives them.
- Aseprite is a Steam install; Steam does **not** need to be running for CLI use.
- User scripts directory: `C:\Users\George\AppData\Roaming\Aseprite\scripts`.
