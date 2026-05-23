#!/usr/bin/env bash
# graph-watch.sh — Optional continuous graph updates via fswatch (macOS) or inotifywait (Linux).
# Usage: bash .claude/graph/graph-watch.sh
# Kill with Ctrl-C.
#
# Most users should rely on the PostToolUse hook + git post-commit hook instead.
set -euo pipefail

BUILDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/graph-builder.sh"

if [[ ! -x "$BUILDER" ]]; then
  echo "error: $BUILDER not found or not executable" >&2
  exit 1
fi

# ── Detect watcher tool ───────────────────────────────────────────────────────
WATCHER=""
command -v fswatch      >/dev/null 2>&1 && WATCHER="fswatch"
command -v inotifywait  >/dev/null 2>&1 && WATCHER="${WATCHER:-inotifywait}"

if [[ -z "$WATCHER" ]]; then
  echo "error: neither fswatch nor inotifywait found." >&2
  echo "  macOS:  brew install fswatch" >&2
  echo "  Linux:  sudo apt install inotify-tools" >&2
  exit 1
fi

echo "graph-watch: watching Assets/ for .cs .asmdef .prefab .unity changes (Ctrl-C to stop)"

# ── Debounce state ────────────────────────────────────────────────────────────
DEBOUNCE_SECS=0.5
LAST_FILE=""
LAST_RUN=0

trigger_build() {
  local f="$1"
  local now
  now=$(date +%s)
  # Simple debounce: if same file triggered within debounce window, skip
  if [[ "$f" == "$LAST_FILE" ]]; then
    local elapsed=$(( now - LAST_RUN ))
    [[ $elapsed -lt 1 ]] && return
  fi
  LAST_FILE="$f"
  LAST_RUN=$now
  echo "graph-watch: change detected: $f → rebuilding…"
  bash "$BUILDER" --incremental --changed-files "$f" --skip-mcp --quiet &
}

# ── Watch loop ────────────────────────────────────────────────────────────────
if [[ "$WATCHER" == "fswatch" ]]; then
  fswatch -0 \
    --event Created --event Updated --event Removed \
    --include '\.cs$' --include '\.asmdef$' --include '\.prefab$' --include '\.unity$' \
    --exclude '.*' \
    Assets/ | while IFS= read -r -d '' changed_file; do
      trigger_build "$changed_file"
    done
else
  # inotifywait (Linux)
  inotifywait -m -r -e close_write,moved_to,create,delete \
    --include '\.(cs|asmdef|prefab|unity)$' \
    Assets/ 2>/dev/null |
  while read -r dir event file; do
    changed_file="${dir}${file}"
    case "$changed_file" in
      *.cs|*.asmdef|*.prefab|*.unity) trigger_build "$changed_file" ;;
    esac
  done
fi
