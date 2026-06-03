#!/usr/bin/env bash
# agent-stop-log.sh — SubagentStop hook
# Trigger: SubagentStop | Exit: 0 always (no exit_code in payload — pure audit trail) | Profile: standard
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"')
AGENT_ID=$(echo "$INPUT"   | jq -r '.agent_id   // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

STOPPED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
STOPPED_EPOCH=$(date +%s)
SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"

DURATION_APPROX_S=-1
if [ -f "$SUBAGENT_LOG" ]; then
    START_TS=$(jq -rs --arg id "$AGENT_ID" \
        '[.[] | select(.event=="SubagentStart" and .agent_id==$id)] | last | .started_at // empty' \
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
    --arg  agent_id      "$AGENT_ID" \
    --arg  session_id    "$SESSION_ID" \
    --argjson duration   "$DURATION_APPROX_S" \
    --arg  stopped_at    "$STOPPED_AT" \
    --arg  logged_at     "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, agent_type:$agent_type, agent_id:$agent_id, session_id:$session_id, duration_approx_s:$duration, stopped_at:$stopped_at, logged_at:$logged_at}' \
    >> "$SUBAGENT_LOG"

exit 0
