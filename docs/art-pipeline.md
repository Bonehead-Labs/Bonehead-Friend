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

**Verified 2026-08-28:** Aseprite **1.3.18.3** responds to `--batch --version`, and the project
opens in the Godot **4.7.2** editor headlessly with the addon enabled and exit code 0 (the
addon's 4.7 compatibility was the open question; it loads clean). Sanity-check the importer
itself with a real `.aseprite` file the first time you use it — loading without errors isn't
quite the same as importing correctly. Fallback if it ever breaks: plain spritesheet + JSON.

In-editor check: *Project → Tools → Aseprite Config* should print a version, not "command not
found".

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

## Gotchas

- Filenames: no spaces (`Assets/baseball bat.png` is a prototype-era mistake), and exact case
  everywhere — `res://` paths are case-sensitive in exported builds even though the Windows
  editor forgives them.
- Aseprite is a Steam install; Steam does **not** need to be running for CLI use.
- User scripts directory: `C:\Users\George\AppData\Roaming\Aseprite\scripts`.
