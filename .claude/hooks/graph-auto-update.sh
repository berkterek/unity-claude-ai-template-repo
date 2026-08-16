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

# ── Project root ───────────────────────────────────────────────────────────────
# Every path below is anchored here. A hook's cwd is whatever the tool call ran
# in, which for a subagent is not the repo root — and every path in this file
# used to be cwd-relative, so from any other cwd the feature file was not found
# and the hook exited 0 without doing anything. Silent no-op, no warning: the
# graph simply went stale while CLAUDE.md calls it the primary source of truth.
# CLAUDE_PROJECT_DIR first (what settings.json passes); git root is the fallback,
# and is wrong if the cwd happens to sit inside a nested repo — hence the order.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ── Feature flag check ─────────────────────────────────────────────────────────
FEATURES="$PROJECT_ROOT/.claude/project-features.json"
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
GRAPH_JSON="$PROJECT_ROOT/.claude/graph/graph.json"
_STATE_DIR="${UNITY_HOOK_STATE_DIR:-$PROJECT_ROOT/.claude/state}"
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
    root = '$PROJECT_ROOT'
    cs_count = sum(1 for _ in pathlib.Path(root).rglob('*.cs')) if os.path.isdir(root) else 0
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
BUILDER="$PROJECT_ROOT/.claude/graph/graph-builder.py"
if [[ ! -f "$BUILDER" ]]; then
  echo "graph-auto-update: $BUILDER not found — skipping" >&2
  exit 0
fi

# ── Log trigger ───────────────────────────────────────────────────────────────
# $_STATE_DIR, set above — the same absolute path the health warning already
# writes to. A relative `.claude/state` here follows the hook's cwd instead.
mkdir -p "$_STATE_DIR"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $FILE_PATH" >> "$_STATE_DIR/graph-updates.log"

# ── Template-mode guard: skip builder when Assets/ does not exist ─────────────
# Health warning and log write still happen above; only the background builder
# is suppressed — prevents graph.json timestamp churn in the template repo.
UNITY_PROJECT_FOLDER=$(python3 -c "
import json, sys
try:
    d = json.load(open('$FEATURES'))
    print(d.get('unity_project_folder', '.'))
except Exception:
    print('.')
" 2>/dev/null || echo ".")

if [ "$UNITY_PROJECT_FOLDER" = "." ]; then
    ASSETS_ROOT="$PROJECT_ROOT/Assets"
else
    ASSETS_ROOT="$PROJECT_ROOT/${UNITY_PROJECT_FOLDER}/Assets"
fi

[ -d "$ASSETS_ROOT" ] || exit 0

# ── Non-blocking incremental rebuild ─────────────────────────────────────────
# Run from PROJECT_ROOT: graph-builder.py resolves its own inputs and its output
# path relative to cwd, so launching it from the hook's cwd would write the graph
# somewhere other than .claude/graph/ — the same defect one layer down.
# A subshell `cd`, not `env -C`: the latter needs coreutils >= 8.28 / macOS 13,
# and this repo already carries a portability fix for exactly that class of gap.
(
  cd "$PROJECT_ROOT" || exit 0
  nohup python3 "$BUILDER" \
    --incremental \
    --changed-files "$FILE_PATH" \
    --skip-mcp \
    --quiet \
    >/dev/null 2>&1 &
)

exit 0
