#!/usr/bin/env bash
# ============================================================================
# graph-nudge.sh — soft nudge toward `graph-traversal.py what/where` before whole-file C# reads
# Event: PreToolUse, matcher "Read|Grep|Bash|mcp__graph_mcp__.*"
#
# Never blocks: always exit 0, never prints permissionDecision (D6 in docs/PLAN_graph_complete_map.md).
# Emits hookSpecificOutput.additionalContext at most 5x per agent per session, and not at all within
# 30 min of that agent's own graph query. Every decision is appended to <state>/graph-nudge.log.
# Silent when the `graph` feature is off, so a project that does not use the graph pays nothing. Kill switches: DISABLE_UNITY_HOOKS=1, DISABLE_HOOK_GRAPH_NUDGE=1,
# UNITY_HOOK_PROFILE=minimal.
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh" 2>/dev/null || exit 0
trap 'exit 0' ERR
( sleep 2; kill -TERM $$ 2>/dev/null ) & WD=$!
trap 'kill $WD 2>/dev/null; exit 0' EXIT

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
FEATURES="$PROJECT_ROOT/.claude/project-features.json"
[ -f "$FEATURES" ] || exit 0
[ "$(jq -r '.graph // false' "$FEATURES" 2>/dev/null)" = "true" ] || exit 0

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null) || exit 0
[ -n "$TOOL" ] || exit 0
SID=$(jq -r '.session_id // "nosession"' <<<"$INPUT")
# A subagent does its own reading: a graph query by the main session must not silence it, so the
# stamp and the budget are keyed per agent. `agent_id` is absent for the main session.
AGENT=$(jq -r '.agent_id // "main"' <<<"$INPUT")
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

STATE_DIR="${UNITY_HOOK_STATE_DIR:-$PROJECT_ROOT/.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STAMP="$STATE_DIR/graph-query-${SID}-${AGENT}.stamp"
COUNT="$STATE_DIR/graph-nudge-${SID}-${AGENT}.count"
LOG="$STATE_DIR/graph-nudge.log"
# One line per decision so "did it fire, and if not why" is answerable from a file, not a transcript.
log() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%H:%M:%S)" "$1" "$AGENT" "$TOOL" "$(printf '%s' "${2:-}" | tr '\n\t' '  ' | cut -c1-120)" >> "$LOG" 2>/dev/null
    if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 400 ]; then tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"; fi
}

# Graph query: remember it, say nothing.
case "$TOOL" in
    mcp__graph_mcp__*) touch "$STAMP"; log stamp "$TOOL"; exit 0 ;;
esac
if [ "$TOOL" = "Bash" ] && [[ "$CMD" == *graph-traversal.py* || "$CMD" == *knowledge-graph* || "$CMD" == *graph.json* ]]; then
    touch "$STAMP"; log stamp "$CMD"; exit 0
fi

# Source read: a .cs file (or a directory) under the indexed roots — same roots as scan_files.
ROOTS_RE='Assets/(_Framework|_GameFolders/Scripts)'
TARGET=""
case "$TOOL" in
    Read) TARGET=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT"); [[ "$TARGET" == *.cs ]] || exit 0 ;;
    Grep) TARGET=$(jq -r '.tool_input.path // empty' <<<"$INPUT") ;;
    Bash) [[ "$CMD" =~ (cat|sed\ -n|head|tail|grep|rg)[[:space:]].*\.cs([[:space:]\"\']|$) ]] || exit 0
          TARGET="$CMD" ;;
    *) exit 0 ;;
esac
[[ "$TARGET" =~ $ROOTS_RE ]] || exit 0

# Quiet while a recent graph query exists (30 min) or the per-session budget (5) is spent.
if [ -f "$STAMP" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0) ))
    if [ "$age" -lt 1800 ]; then log quiet-recent-query "$TARGET"; exit 0; fi
fi
n=$(cat "$COUNT" 2>/dev/null || echo 0)
if [ "$n" -ge 5 ]; then log quiet-budget-spent "$TARGET"; exit 0; fi
echo $((n + 1)) > "$COUNT"
log nudge "$TARGET"

jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"graph: try `python3 .claude/graph/graph-traversal.py what <Symbol>` / `where <Symbol>` (then a ranged Read) before reading whole C# files."}}'
exit 0
