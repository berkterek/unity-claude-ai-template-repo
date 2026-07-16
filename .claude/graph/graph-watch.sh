#!/usr/bin/env bash
# graph-watch.sh — Optional continuous graph updates via fswatch (macOS) or inotifywait (Linux).
# Usage: bash .claude/graph/graph-watch.sh
# Kill with Ctrl-C.
#
# Most users should rely on the PostToolUse hook + git post-commit hook instead.
set -euo pipefail

BUILDER_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/graph-builder.py"

if [[ ! -f "$BUILDER_PY" ]]; then
  echo "error: $BUILDER_PY not found" >&2
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

# Project root for Unity Assets — override via GRAPH_WATCH_ROOT env var.
# Otherwise resolved from unity_project_folder in project-features.json ("." → Assets/).
# Never hardcode a project's subfolder name — read it from config (see CLAUDE.md).
if [[ -n "${GRAPH_WATCH_ROOT:-}" ]]; then
  WATCH_ROOT="$GRAPH_WATCH_ROOT"
else
  _repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  _uf="$(python3 - "$_repo_root" <<'PY' 2>/dev/null || echo "."
import json, os, sys
p = os.path.join(sys.argv[1], ".claude", "project-features.json")
try:
    v = (json.load(open(p)).get("unity_project_folder", ".") or ".")
except Exception:
    v = "."
print(str(v).rstrip("/") or ".")
PY
)"
  if [[ "$_uf" == "." ]]; then WATCH_ROOT="Assets"; else WATCH_ROOT="${_uf}/Assets"; fi
fi

echo "graph-watch: watching ${WATCH_ROOT}/ for .cs .asmdef .prefab .unity changes (Ctrl-C to stop)"

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
  python3 "$BUILDER_PY" --incremental --changed-files "$f" --skip-mcp --quiet &
}

# ── Watch loop ────────────────────────────────────────────────────────────────
if [[ "$WATCHER" == "fswatch" ]]; then
  fswatch -0 \
    --event Created --event Updated --event Removed \
    --include '\.cs$' --include '\.asmdef$' --include '\.prefab$' --include '\.unity$' \
    --exclude '.*' \
    "${WATCH_ROOT}/" | while IFS= read -r -d '' changed_file; do
      trigger_build "$changed_file"
    done
else
  # inotifywait (Linux)
  inotifywait -m -r -e close_write,moved_to,create,delete \
    --include '\.(cs|asmdef|prefab|unity)$' \
    "${WATCH_ROOT}/" 2>/dev/null |
  while read -r dir event file; do
    changed_file="${dir}${file}"
    case "$changed_file" in
      *.cs|*.asmdef|*.prefab|*.unity) trigger_build "$changed_file" ;;
    esac
  done
fi
