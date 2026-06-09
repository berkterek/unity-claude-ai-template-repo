#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
# graph-auto-update.sh — PostToolUse hook: incremental graph rebuild on Write/Edit.
# Non-blocking: launches graph-builder.py in background, always exits 0.
# Execution context: Claude Code host process — Unity Editor NOT required.
set -euo pipefail

# ── Read tool input from stdin ────────────────────────────────────────────────
TOOL_INPUT=$(cat)

FILE_PATH=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    # Handle both {tool_input: {file_path}} and {file_path} shapes
    val = d.get('tool_input', d)
    print(val.get('file_path', ''))
except Exception:
    print('')
" "$TOOL_INPUT" 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0

# ── Filter by extension ────────────────────────────────────────────────────────
case "$FILE_PATH" in
  *.cs|*.asmdef|*.prefab|*.unity) ;;
  *) exit 0 ;;
esac

# ── Feature flag check ─────────────────────────────────────────────────────────
FEATURES=".claude/project-features.json"
if [[ ! -f "$FEATURES" ]]; then
  exit 0
fi

GRAPH_ENABLED=$(python3 -c "
import json, sys
try:
    d = json.load(open('$FEATURES'))
    print('true' if d.get('graph') == True else 'false')
except Exception:
    print('false')
" 2>/dev/null || echo "false")

[[ "$GRAPH_ENABLED" == "true" ]] || exit 0

# --- Graph empty-state warning (once per session) ---
GRAPH_JSON=".claude/graph/graph.json"
_STATE_DIR="${UNITY_HOOK_STATE_DIR:-.claude/state}"
WARN_SENTINEL="$_STATE_DIR/graph-empty-warned"
if [[ -f "$GRAPH_JSON" && ! -f "$WARN_SENTINEL" ]]; then
    SCANNED=$(python3 -c "
import json
try:
    d = json.load(open('$GRAPH_JSON'))
    print(d.get('stats', d.get('codebase', {})).get('scanned_files', 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

    if [[ "$SCANNED" = "0" ]]; then
        mkdir -p "$_STATE_DIR"
        touch "$WARN_SENTINEL"
        echo "WARNING (graph-auto-update): graph.json reports scanned_files=0 — graph is empty." >&2
        echo "  Run: /build-knowledge-graph to populate it, or disable the 'graph' feature in .claude/project-features.json." >&2
        echo "graph-auto-update: empty graph (scanned_files=0)" >> "$_STATE_DIR/session-warnings.txt"
    fi
fi

# ── Builder existence check ────────────────────────────────────────────────────
BUILDER=".claude/graph/graph-builder.py"
if [[ ! -f "$BUILDER" ]]; then
  echo "graph-auto-update: $BUILDER not found — skipping" >&2
  exit 0
fi

# ── Log trigger ───────────────────────────────────────────────────────────────
mkdir -p .claude/state
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $FILE_PATH" >> .claude/state/graph-updates.log

# ── Non-blocking incremental rebuild ─────────────────────────────────────────
nohup python3 "$BUILDER" \
  --incremental \
  --changed-files "$FILE_PATH" \
  --skip-mcp \
  --quiet \
  >/dev/null 2>&1 &

exit 0
