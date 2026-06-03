#!/usr/bin/env bash
# agent-start-log.sh — SubagentStart hook
# Trigger: SubagentStart | Exit: 0 always (advisory — exit 2 not honoured on this event) | Profile: standard
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type  // "unknown"')
AGENT_ID=$(echo "$INPUT"   | jq -r '.agent_id    // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id  // "unknown"')

SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"

jq -nc \
    --arg event      "SubagentStart" \
    --arg agent_type "$AGENT_TYPE" \
    --arg agent_id   "$AGENT_ID" \
    --arg session_id "$SESSION_ID" \
    --arg started_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg logged_at  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, agent_type:$agent_type, agent_id:$agent_id, session_id:$session_id, started_at:$started_at, logged_at:$logged_at}' \
    >> "$SUBAGENT_LOG"

exit 0
