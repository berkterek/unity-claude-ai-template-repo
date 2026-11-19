#!/usr/bin/env bash
# subagent-stop-settle.sh — SubagentStop hook
# Trigger: SubagentStop | Exit: 0 always | Profile: standard
#
# The subagent has really finished: consume one fallback entry queued by
# agent-start-log.sh and decrement subagent-depth now (unity_subagent_settle_one).
# Replaces the Start + 180s timer that blocked every subagent running longer than
# 3 minutes (word-soda module 04, 2026-11-19).
#
# UNDER MEASUREMENT (2026-11-19). An older header in agent-stop-log.sh claimed
# SubagentStop "does not fire consistently" — never measured. Every call logs a
# SubagentFinished line with the payload's keys, so the first real run answers:
# does it fire for every counted spawn (compare with SubagentStart lines), for
# background agents too, and which field names the agent. If it does not fire,
# nothing breaks: the fallback still decrements at Start + grace.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

AGENT_TYPE=$(jq -r '.agent_type // .subagent_type // "unknown"' <<<"$INPUT" 2>/dev/null || echo unknown)
SESSION_ID=$(jq -r '.session_id // "unknown"' <<<"$INPUT" 2>/dev/null || echo unknown)

SETTLED=false
if unity_subagent_settle_one "$AGENT_TYPE"; then
    SETTLED=true
fi

jq -nc \
    --arg event "SubagentFinished" \
    --arg agent_type "$AGENT_TYPE" \
    --arg session_id "$SESSION_ID" \
    --arg finished_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson settled "$SETTLED" \
    --argjson payload_keys "$(jq -c 'keys' <<<"$INPUT" 2>/dev/null || echo '[]')" \
    '{event:$event, agent_type:$agent_type, session_id:$session_id, finished_at:$finished_at, settled:$settled, payload_keys:$payload_keys}' \
    >> "${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl" 2>/dev/null || true

exit 0
