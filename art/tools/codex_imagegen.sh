#!/usr/bin/env bash
# Generate one image with Codex's built-in `imagegen` tool and drop it in art/raw/.
#
#     art/tools/codex_imagegen.sh <out.png> "<prompt>"
#
# Why this exists: `docs/decisions.md` D44 recorded that no image generator was reachable
# from an agent session, and the art pass stopped there. That was wrong. The Codex CLI
# installed on this machine carries a native `imagegen` tool, and `codex exec` drives it
# non-interactively, in its own fresh session, without touching a Codex window the owner
# has open.
#
# What it is NOT: Retro Diffusion. There is no seed, so a generation is not reproducible
# the way `art/prompts/items.md` asks; no `remove_bg`, which is why `art/tools/keyout.py`
# exists; no `return_spritesheet` and none of the `rd_advanced_animation__*` presets, which
# is why the walk cycle and the animation families are still blocked. Prompts are recorded
# in `art/prompts/` in place of seeds: they are the only reproducibility we have here.
#
# Run from the repository root. Works from Git Bash and from WSL; codex.exe is a Windows
# binary either way, so every path handed to it is converted first.
set -euo pipefail

if [ "$#" -lt 2 ]; then
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

OUT="$1"
PROMPT="$2"
MODEL="${CODEX_IMAGE_MODEL:-gpt-5.6-luna}"

# Codex is a Windows process: anything in its own arguments must be a Windows path.
to_native() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    elif command -v wslpath >/dev/null 2>&1; then
        wslpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

# Resolve the CLI. The install path carries a build hash, so glob for it rather than pin it.
CODEX="${CODEX_CLI_PATH:-}"
if [ -z "$CODEX" ]; then
    CODEX=$(ls -1d "$HOME"/AppData/Local/OpenAI/Codex/bin/*/codex.exe 2>/dev/null | head -1 || true)
fi
if [ -z "$CODEX" ] || [ ! -x "$CODEX" ]; then
    echo "ERROR: codex.exe not found. Set CODEX_CLI_PATH." >&2
    exit 1
fi

GEN_DIR="$HOME/.codex/generated_images"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/codex.log"

# Marker for the fallback search below. It has to predate the run, and the log does not:
# the log is written to until the run ends, so its mtime is the finish, not the start.
MARK="$WORK/started"
: >"$MARK"

# `-s read-only` because imagegen writes through the harness, not through a shell command:
# the model needs no write access to produce the PNG, so it is not given any.
"$CODEX" exec \
    -m "$MODEL" \
    -c model_reasoning_effort=low \
    -s read-only \
    -C "$(to_native "$WORK")" \
    --skip-git-repo-check \
    "Call the imagegen tool exactly once with this image prompt: ${PROMPT}
After it returns, reply with the absolute path of the saved PNG and nothing else. Do not run any other tools." \
    >"$LOG" 2>&1 || { echo "ERROR: codex exec failed" >&2; tail -20 "$LOG" >&2; exit 1; }

# Prefer the path the model reports; fall back to the newest PNG Codex saved since MARK.
SRC=""
REPORTED=$(grep -oE '[A-Za-z]:\\[^ "]*generated_images\\[^ "]*\.png' "$LOG" | tail -1 || true)
if [ -n "$REPORTED" ]; then
    if command -v cygpath >/dev/null 2>&1; then
        SRC=$(cygpath -u "$REPORTED")
    elif command -v wslpath >/dev/null 2>&1; then
        SRC=$(wslpath -u "$REPORTED")
    fi
fi
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    SRC=$(find "$GEN_DIR" -name '*.png' -newer "$MARK" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2- || true)
fi
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    echo "ERROR: no PNG produced. Codex said:" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
cp "$SRC" "$OUT"
printf '%-30s <- %s\n' "$OUT" "$(basename "$SRC")"
