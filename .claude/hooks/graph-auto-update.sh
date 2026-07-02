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

# --- Graph health warning (re-fires each session, not once-ever) ---
GRAPH_JSON=".claude/graph/graph.json"
_STATE_DIR="${UNITY_HOOK_STATE_DIR:-.claude/state}"
# Sentinel is keyed by date so it re-fires each new calendar day / session.
_TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "unknown")
WARN_SENTINEL="$_STATE_DIR/graph-health-warned-${_TODAY}"
if [[ -f "$GRAPH_JSON" && ! -f "$WARN_SENTINEL" ]]; then
    _HEALTH=$(python3 -c "
import json, pathlib, os
try:
    d = json.load(open('$GRAPH_JSON'))
    cb = d.get('codebase', {})
    classes = len(cb.get('classes', []) or [])
    # Count .cs files under Assets/ as a rough project-size probe.
    cs_count = sum(1 for _ in pathlib.Path('.').rglob('*.cs')) if os.path.isdir('.') else 0
    print(f'{classes} {cs_count}')
except Exception:
    print('0 0')
" 2>/dev/null || echo "0 0")
    _CLASSES=$(echo "$_HEALTH" | awk '{print $1}')
    _CS_COUNT=$(echo "$_HEALTH" | awk '{print $2}')

    _WARN=0
    if [[ "$_CLASSES" = "0" ]]; then
        _WARN=1
        _REASON="graph is empty (classes=0)"
    elif [[ "$_CLASSES" -lt 5 && "$_CS_COUNT" -ge 20 ]]; then
        _WARN=1
        _REASON="graph has only $_CLASSES classes but project has $_CS_COUNT .cs files — likely collapsed"
    fi

    if [[ "$_WARN" = "1" ]]; then
        mkdir -p "$_STATE_DIR"
        touch "$WARN_SENTINEL"
        echo "WARNING (graph-auto-update): $_REASON." >&2
        echo "  Run: /build-knowledge-graph to rebuild it from scratch." >&2
        echo "graph-auto-update: health warning — $_REASON" >> "$_STATE_DIR/session-warnings.txt"
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
