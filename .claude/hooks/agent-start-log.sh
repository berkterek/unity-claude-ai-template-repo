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

# Retry detection — MUST run before this Start is appended, against the log's
# prior state. Measured across two projects (2026-08-27): the dominant leak
# cause is not an interrupted/denied agent — it is the Agent tool's own
# internal retry-on-transient-error path (rate limit / overload). A retried
# call fires a NEW PreToolUse/Agent per attempt (same session_id+description,
# seconds to minutes apart) but the tool only ever resolves to ONE PostToolUse
# Stop. Evidence: dozens of session_id+description groups with N Starts and
# exactly 1 Stop (N up to 3), never more Stops than 1 for the same pair. If a
# Start for this exact session_id+description is already pending (logged, no
# matching Stop yet), this is a retry of that same logical call — log the
# audit line for duration-matching, but do NOT double-count depth for it.
IS_RETRY=0
if [ -f "$SUBAGENT_LOG" ]; then
    PENDING=$(jq -s --arg desc "$DESCRIPTION" --arg sid "$SESSION_ID" '
        [.[] | select(.session_id == $sid and .description == $desc)]
        | (map(select(.event=="SubagentStart")) | length) - (map(select(.event=="SubagentStop")) | length)
    ' "$SUBAGENT_LOG" 2>/dev/null || echo 0)
    [ "${PENDING:-0}" -gt 0 ] 2>/dev/null && IS_RETRY=1
fi

jq -nc \
    --arg event       "SubagentStart" \
    --arg agent_type  "$AGENT_TYPE" \
    --arg description "$DESCRIPTION" \
    --arg session_id  "$SESSION_ID" \
    --arg started_at  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg logged_at   "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson is_retry "$([ "$IS_RETRY" -eq 1 ] && echo true || echo false)" \
    '{event:$event, agent_type:$agent_type, description:$description, session_id:$session_id, started_at:$started_at, logged_at:$logged_at, is_retry:$is_retry}' \
    >> "$SUBAGENT_LOG"

# Depth counter — read by guard-pipeline-direct-work.sh, gateguard.sh and
# check-config-protection.sh to tell whether the CURRENT tool call is happening
# inside a spawned subagent (depth > 0) or in the main session directly
# (depth == 0). Incremented here (unless this is a detected retry — see above),
# decremented once in agent-stop-log.sh per logical call.
#
# This comment previously claimed "a stale >0 count self-heals to 0 once agents
# complete". It does not, in general. The pair only balances when every logical
# call's increment gets a matching PostToolUse Stop; an agent that errors,
# is interrupted, or is still running when the session ends leaves the count
# permanently high, and nothing brings it back down mid-session.
#
# A leaked count is not merely noisy — it silently disables
# guard-pipeline-direct-work.sh, which reads depth > 0 as "a subagent owns this
# call" and exits 0. Two guards bound the damage: session-restore.sh resets the
# counter at SessionStart, and each consumer resolves an implausible count in
# whichever direction ENFORCES its own rule (see the staleness notes in
# guard-pipeline-direct-work.sh and gateguard.sh — the two directions are
# deliberately opposite). Do not restore the self-healing claim without evidence
# that Stop fires on every path.
if [ "$IS_RETRY" -eq 0 ]; then
    DEPTH_FILE="${UNITY_HOOK_STATE_DIR}/subagent-depth"
    unity_subagent_depth_lock
    CURRENT_DEPTH=$(cat "$DEPTH_FILE" 2>/dev/null || echo 0)
    echo $(( CURRENT_DEPTH + 1 )) > "$DEPTH_FILE"
    unity_subagent_depth_unlock
fi

exit 0
