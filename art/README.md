# Art sources

See `docs/art-pipeline.md` for the full workflow.

- `prompts/` — one record per generated asset: prompt, style id, seed, model, date.
  This is what makes assets reproducible. Commit these.
- `raw/` — untouched Retro Diffusion output. **Gitignored** — regenerable from `prompts/`.
- `src/` — `.aseprite` working files, the hand-drawn inputs they are built from, and the
  Lua that builds them. Aseprite Wizard imports from here. Commit these.
- `tools/` — the Python post-processing and preview steps. Commit these.
- `preview/` — human-viewable GIFs and contact sheets. **Gitignored** — rebuild with
  `python3 art/tools/preview.py`.

`raw/`, `preview/` and `src/faces/` each carry a `.gdignore` so Godot does not import
throwaway generator output and build inputs as game assets. Only `src/*.aseprite` is meant
to reach the engine.

## The two scripts you will actually run

```bash
# after downloading a generated sheet into art/raw/
python3 art/tools/postprocess.py art/raw/bonehead_<tag>_sheet.png <tag>

# rebuild every preview
python3 art/tools/preview.py
```

Then reassemble the multi-tag source with `art/src/_build_body.lua` — see
`docs/art-pipeline.md`, which also carries the gotchas. Read those before generating: three
of them cost real time to find.

Exported PNGs consumed by scenes live in `Assets/sprites/<entity>/`, not here.
