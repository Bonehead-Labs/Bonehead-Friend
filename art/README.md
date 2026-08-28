# Art sources

See `docs/art-pipeline.md` for the full workflow.

- `prompts/` — one record per generated asset: prompt, style id, seed, model, date.
  This is what makes assets reproducible. Commit these.
- `raw/` — untouched Retro Diffusion output. **Gitignored** — regenerable from `prompts/`.
- `src/` — `.aseprite` working files. Aseprite Wizard imports from here. Commit these.

Exported PNGs consumed by scenes live in `Assets/sprites/<entity>/`, not here.
