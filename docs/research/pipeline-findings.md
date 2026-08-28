# Research — Art Pipeline Findings

Compiled 2026-08-28 on this machine (WSL2 Ubuntu on Windows). Practical setup notes behind
`art-pipeline.md`. Verified facts are marked ✔; unverified ones are flagged.

## Retro Diffusion

AI pixel-art service by Astropulse — models trained to produce *real* pixel art (grid-aligned,
controlled palettes, transparent backgrounds), not upscaled pixel-styled images.

**✔ An official MCP server exists and is hosted — nothing to install.**
Repo `Retro-Diffusion/retro-diffusion-mcp` (MIT, official org), endpoint
`https://mcp.retrodiffusion.ai/mcp` (Streamable HTTP), auth `Authorization: Bearer rdpk-<key>`.
Also distributed as a Claude Code plugin (`pixel-art@retro-diffusion`, v1.1.0) that bundles the
server *plus* a cost-aware workflow skill — the better install.

**Tools:** `create_inference`, `get_inference_result`, `start_inference_job`, `get_inference_job`,
`list_inference_jobs`, `estimate_inference_cost` (free) · `list_edit_tools`, `run_edit_tool`,
`estimate_edit_tool_cost` (free), `fix_pixel_art` (free) · style management (`list_available_styles`,
`create_user_style`, …) · account (`authenticate`, `get_balance`, `get_service_status`).

`create_inference` covers stills, animations (GIF or sprite sheet) and tilesets. `run_edit_tool`
covers background removal, palette conversion, colour reduction, pixel correction, rotation and
K-centroid downscale (free–$0.01), plus premium img2img, inpainting, outpainting and seam tiling.

**Models/sizes/costs:** RD Fast / Plus / Pro / Mini; 90+ styles (game asset, isometric, top-down,
platformer, 1-bit, UI, item sheets, character turnarounds). Sizes 16×16–384×384 with per-style
limits — the REST docs say 12–512, the MCP README says 16–384; **treat `list_available_styles` as
authoritative**. ~$0.015 (Fast) to $0.18 (Pro) per image, $0.07–0.25 per animation, $0.10 per
tileset. Prepaid credits, never expire.

**Gotchas worth building the workflow around:**
- Generation is **non-idempotent and can charge before a timeout is visible**. If output URLs are
  missing, call `get_inference_result(request_id)` — **never auto-retry**. Recover lost async jobs
  with `list_inference_jobs`.
- Outputs are **short-lived hosted URLs**, not base64 — download immediately.
- **Never write "pixel art" in the prompt** — describe the subject; the style handles rendering.
- Consistency: generate a hero asset with RD Pro, then pass it as a reference (up to 9 supported).
  Reuse `seed` to iterate the same composition.
- `fix_pixel_art`: 10 req/min per key; request payload ≤900 KB, response ≤850 KB; images 16×16
  min, 4 MP max.

**Direct REST alternative:** `https://api.retrodiffusion.ai/v1`, `POST /inferences`, header
**`X-RD-Token`** (note: different from the MCP's `Bearer`). Body takes `prompt`, `prompt_style`,
`width`/`height`, `num_images` (≤16), `seed`, `input_image` (base64 → img2img), `strength`,
`tile_x`/`tile_y`, `return_spritesheet`, and `check_cost: true` for a free estimate. Examples at
`Retro-Diffusion/api-examples`.

⚠️ The MCP repo is official but new and low-profile (2 stars, last updated 2026-08-16).
`docs.retrodiffusion.ai` does not resolve; use `retrodiffusion.ai/app/guide/api`.

### Key handling

Claude Code expands **`${VAR}`** (and `${VAR:-default}`) in `command`, `args`, `env`, `url` and
`headers` of `.mcp.json`. ⚠️ Retro Diffusion's own sample config uses **`${env:RD_API_KEY}`** —
that's VS Code syntax and will **not** expand in Claude Code. Don't copy their file verbatim.

Put `RD_API_KEY` in `~/.claude/settings.json`'s `env` block or the shell profile, never in a repo
`.env`. A committed `.mcp.json` may *reference* the variable safely.

## Aseprite

**✔ Verified on this machine:**
`"/mnt/c/Program Files (x86)/Steam/steamapps/common/Aseprite/Aseprite.exe" --batch --version`
→ `Aseprite 1.3.18.3-x64`, exit 0. Steam appid 431730. Steam need not be running. Note the capital
A in `Aseprite.exe`. User scripts dir: `C:\Users\George\AppData\Roaming\Aseprite\scripts` (exists).

### The WSL problem — and the fix

MCP servers for Aseprite all work the same way: write a temp Lua script, run
`aseprite --batch --script tmp.lua`, parse JSON from stdout. **Do not run the server on the Linux
side.** Its temp files land in `/tmp` and it passes WSL paths as arguments; `Aseprite.exe` is a
Windows process and cannot resolve `/tmp/xxx.lua` or `/mnt/c/...`. Every call would fail or write
nowhere.

Fix: run the MCP server **as a Windows process**, exactly as the existing Blender MCP on this
machine already does. The project lives on `C:` so paths line up with no translation.

**✔ Windows toolchain confirmed present:** `C:\Users\George\.local\bin\uv.exe` / `uvx.exe`
(uv 0.12.0), Python 3.12 and **3.13**, Node, Go.

### Server options

| Repo | Lang | Stars | Tools | Install |
|---|---|---|---|---|
| **`diivi/aseprite-mcp`** | Python ≥3.13 | 461 | **104** | **Not on PyPI** — clone + `uv run -m aseprite_mcp` |
| `willibrandon/pixel-mcp` | Go | 132 | many; art-theory tools | Build from source; **no env-var support** (needs a config file) |
| `ayigityol/aseprite-mcp` | Node ≥18 | 7 | 43 | **Not on npm** despite its README — build from source |
| `rkdfx/aseprite-mcp` | Python | — | — | Lua automation focus |

**✔ Verified that both `npm i -g aseprite-mcp` and `pip install aseprite-mcp` fail — neither
package exists in its registry.** All options require a clone.

Recommended: `diivi/aseprite-mcp`. Locates Aseprite via `ASEPRITE_PATH` (falls back to `aseprite`
on PATH) and also loads a `.env` at its own repo root. Categories: canvas, drawing, layers,
animation (frames, cels, tweening with easing, tags), palettes (Game Boy / PICO-8 / C64 presets,
hue-shifted ramps, quantisation), effects (outlines, dithering, HSL, colour replace), slices,
tilemaps, export (PNG/GIF/spritesheets with per-tag filtering), analysis (onion-skin render, frame
diffing, colour stats), plus a raw `run_script` escape hatch. Has Lua-injection escaping and
rejects `..` traversal.

### Aseprite CLI (official docs confirm)

`--batch`/`-b` (no UI) · `--script script.lua` (Lua API documented at aseprite.org/api) ·
`--sheet sheet.png` + `--data sheet.json` (**an empty `--data` filename writes JSON to stdout** —
this is how the MCP servers get structured results back) · `--format json-hash|json-array` ·
`--sheet-type horizontal|vertical|rows|columns|packed` · `--split-layers` (must precede the sprite
filename) · `--frame-range from,to` · `--save-as out.png` (auto-numbers).

## Godot import

**⚠️ Version correction found during research:** this is not a 4.5 project. `project.godot`
declares `config/features=PackedStringArray("4.7", "GL Compatibility")` and the machine has
`Godot_v4.7.2-stable_win64.exe` plus 4.6.1 and 4.6.2-mono. There is no 4.5 install. → `decisions.md` D1.

**Aseprite Wizard** (`viniciusgerevini/godot-aseprite-wizard`) — 1,355 stars, default branch
`godot_4`, latest release v9.8.0-4 (2026-03-03), last commit 2026-08-17. Actively maintained; the
one to use.

- Config key `aseprite/general/command_path`, set in *Project Settings → General → Aseprite* or
  *Editor Settings → Aseprite*. **Because the Godot editor runs on Windows, use the Windows path.**
  Verify via *Project → Tools → Aseprite Config*.
- Provides importers making `.aseprite` first-class: **Aseprite SpriteFrames**, **Aseprite Texture**,
  **Aseprite Tileset Texture**; plus inspector docks to import into `AnimationPlayer`,
  `AnimatedSprite2D/3D`, or a standalone `SpriteFrames`.
- Each **tag becomes an animation** (untagged → one `default`); forward/reverse/ping-pong; loop
  control via tag repeat; **regex layer filtering** (exclude `_ref`/`_guide` layers); slice support;
  **converts Aseprite's millisecond frame durations into Godot FPS**. AnimationPlayer import
  adds/removes only its own tracks. Editor-only — remove the plugin later and imports still work.
- ⚠️ **Unverified:** no source states Godot **4.7** compatibility. The branch is generic-4.x with a
  recent commit and no open 4.7 issues, but 9.8.0 predates 4.7's release. Test the importer
  immediately after enabling. Fallback: plain spritesheet + JSON.
- Alternative `nklbdev/godot-4-aseprite-importers` has no GitHub releases — lower confidence.

**AnimatedSprite2D vs AnimationPlayer:** `AnimatedSprite2D` + `SpriteFrames` is the right default
when the sprite *is* the entity — Wizard makes `.aseprite` → SpriteFrames a one-step
reimport-on-save loop. Use `AnimationPlayer` when the timeline must drive other properties
(position, modulate, particles, sound, `call_method` hit frames); Wizard writes frame tracks
non-destructively alongside hand-authored ones.

**Project settings:** `default_texture_filter = 0` (Nearest) ✔ already correct. Missing and worth
adding: `rendering/2d/snap/snap_2d_transforms_to_pixel = true` (kills sub-pixel shimmer on moving
Node2Ds). Per-texture: Compress → **Lossless**, never Lossy. Existing `.png.import` sidecars
predate any change — **reimport after touching project-wide settings**.

## Machine environment notes

- `~/.claude/knowledge/environment.md` (2026-08-12): WSL2, home `/home/o_george`, Linux-side uv
  0.8.3, Python 3.12.3, node v22.22.2 symlinked into `~/.local/bin`. **No `jq`, no `ffmpeg`, no
  `sqlite3`** — don't write pipeline scripts assuming them. `rg` is available.
- The **Blender MCP precedent** is documented there: it was pointed at Windows `uvx.exe`. Same
  pattern applies to Aseprite (for path reasons rather than networking).
- `~/.claude/skills/` contained only `graphify` — no art or Godot skill existed yet.
- MCP config before this session: exactly one server, `blender`, at user scope. No project
  `.mcp.json` existed in this repo, and there is no `addons/` directory — **Aseprite Wizard is not
  installed here yet.**
- ⚠️ Claude Code's auto-permission classifier has blocked `uv tool install` before; surface install
  commands for approval rather than working around them.

## Recommended architecture

**User scope for both MCP servers** — an API key you own and an Aseprite install path are
machine-level facts, not per-project ones, so every 2D project inherits them. **No project
`.mcp.json` at all** for a solo dev on one machine. The reusability lever is a single user-level
skill (`~/.claude/skills/godot-pixel-art/SKILL.md`) encoding the *pipeline* the RD plugin doesn't
know about: cost estimation, no-blind-retry, immediate download, prompt+style+seed recording,
Aseprite tagging, Godot settings checklist, and the Windows-vs-WSL path rule — the thing an agent
is most likely to get wrong here.

**Setup order:** RD MCP first (zero-install, immediately testable), then Aseprite Wizard (pure
editor config), then the Aseprite MCP last — it's the only piece with a real chance of breaking.
