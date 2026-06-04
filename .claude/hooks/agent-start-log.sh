#!/usr/bin/env bash
# agent-start-log.sh — PreToolUse/Agent hook
# Trigger: PreToolUse | Matcher: Agent | Exit: 0 always (audit trail only) | Profile: standard
#
# SubagentStart native event is unreliable in Claude Code — it does not fire consistently.
# Using PreToolUse/Agent instead, which is guaranteed to trigger on every Agent spawn.
# Duration matching uses description (unique per call) instead of agent_id (not in payload).
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

SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"

jq -nc \
    --arg event       "SubagentStart" \
    --arg agent_type  "$AGENT_TYPE" \
    --arg description "$DESCRIPTION" \
    --arg session_id  "$SESSION_ID" \
    --arg started_at  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg logged_at   "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, agent_type:$agent_type, description:$description, session_id:$session_id, started_at:$started_at, logged_at:$logged_at}' \
    >> "$SUBAGENT_LOG"

exit 0
