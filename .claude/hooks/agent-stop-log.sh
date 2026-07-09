#!/usr/bin/env bash
# agent-stop-log.sh — PostToolUse/Agent hook
# Trigger: PostToolUse | Matcher: Agent | Exit: 0 always (audit trail only) | Profile: standard
#
# SubagentStop native event is unreliable in Claude Code — it does not fire consistently.
# Using PostToolUse/Agent instead, which is guaranteed to trigger after every Agent call.
# Duration is calculated by matching description against the SubagentStart entry written
# by agent-start-log.sh (PreToolUse/Agent). description is unique per Agent invocation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

AGENT_TYPE=$(echo "$INPUT"   | jq -r '.tool_input.subagent_type // "unknown"')
DESCRIPTION=$(echo "$INPUT"  | jq -r '.tool_input.description   // "unknown"')
SESSION_ID=$(echo "$INPUT"   | jq -r '.session_id               // "unknown"')

STOPPED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
STOPPED_EPOCH=$(date +%s)
SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"

DURATION_APPROX_S=-1
if [ -f "$SUBAGENT_LOG" ]; then
    START_TS=$(jq -rs --arg desc "$DESCRIPTION" \
        '[.[] | select(.event=="SubagentStart" and .description==$desc)] | last | .started_at // empty' \
        "$SUBAGENT_LOG" 2>/dev/null || true)
    if [ -n "$START_TS" ]; then
        START_EPOCH=$(date -u -d "$START_TS" +%s 2>/dev/null \
            || date -u -jf '%Y-%m-%dT%H:%M:%SZ' "$START_TS" +%s 2>/dev/null \
            || echo 0)
        if [ "$START_EPOCH" -gt 0 ] 2>/dev/null; then
            DURATION_APPROX_S=$(( STOPPED_EPOCH - START_EPOCH ))
        fi
    fi
fi

jq -nc \
    --arg  event         "SubagentStop" \
    --arg  agent_type    "$AGENT_TYPE" \
    --arg  description   "$DESCRIPTION" \
    --arg  session_id    "$SESSION_ID" \
    --argjson duration   "$DURATION_APPROX_S" \
    --arg  stopped_at    "$STOPPED_AT" \
    --arg  logged_at     "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, agent_type:$agent_type, description:$description, session_id:$session_id, duration_approx_s:$duration, stopped_at:$stopped_at, logged_at:$logged_at}' \
    >> "$SUBAGENT_LOG"

# Delete the Director Gate when the committer finishes — committer is always the
# final pipeline step, so this is the deterministic hook-managed cleanup point.
# session-restore.sh provides a SessionStart safety net for interrupted pipelines.
if [ "$AGENT_TYPE" = "committer" ]; then
    rm -f "${UNITY_HOOK_STATE_DIR}/gate-cleared"
fi

# Depth counter — mirror of the increment in agent-start-log.sh. Floors at 0 so
# an unmatched Stop (e.g. mid-session hook reload) can't go negative.
DEPTH_FILE="${UNITY_HOOK_STATE_DIR}/subagent-depth"
CURRENT_DEPTH=$(cat "$DEPTH_FILE" 2>/dev/null || echo 0)
NEW_DEPTH=$(( CURRENT_DEPTH - 1 ))
[ "$NEW_DEPTH" -lt 0 ] && NEW_DEPTH=0
echo "$NEW_DEPTH" > "$DEPTH_FILE"

exit 0
