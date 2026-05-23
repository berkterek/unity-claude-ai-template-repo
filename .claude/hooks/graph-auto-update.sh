#!/usr/bin/env bash
# graph-auto-update.sh — PostToolUse hook: incremental graph rebuild on Write/Edit.
# Non-blocking: launches graph-builder.sh in background, always exits 0.
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

# ── Builder existence check ────────────────────────────────────────────────────
BUILDER=".claude/graph/graph-builder.sh"
if [[ ! -x "$BUILDER" ]]; then
  echo "graph-auto-update: $BUILDER not found or not executable — skipping" >&2
  exit 0
fi

# ── Log trigger ───────────────────────────────────────────────────────────────
mkdir -p .claude/state
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $FILE_PATH" >> .claude/state/graph-updates.log

# ── Non-blocking incremental rebuild ─────────────────────────────────────────
nohup bash "$BUILDER" \
  --incremental \
  --changed-files "$FILE_PATH" \
  --skip-mcp \
  --quiet \
  >/dev/null 2>&1 &

exit 0
