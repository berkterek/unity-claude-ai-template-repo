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
START_EPOCH=0
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
# Anchor the decrement's grace window on the matched Start, not "now" — Stop
# fires on async dispatch ack, seconds after Start, so scheduling from "now"
# would barely differ from not scheduling at all. Falls back to STOPPED_EPOCH
# only when no matching Start was found (unmatched Stop, e.g. mid-session hook
# reload) — same conservative default the old immediate-decrement code used.
[ "${START_EPOCH:-0}" -gt 0 ] 2>/dev/null || START_EPOCH=$STOPPED_EPOCH

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

# NO gate-cleared deletion here. An earlier version deleted the gate when the
# committer stopped, on the assumption that committer is always the final pipeline
# step. That assumption is false: /orchestrate commits after EVERY phase and then
# continues, so the deletion tore the gate down mid-pipeline and the Director had to
# re-open it once per phase. Gate lifecycle belongs to whoever opened the gate — the
# pipeline's own final step — backed by the 45-minute TTL and the session-restore.sh
# SessionStart safety net. This hook is a pure audit trail and mutates no gate state.

# Depth counter — the decrement mirroring agent-start-log.sh's increment is NOT
# applied here. Found 2026-08-29: this Stop fires on the Agent tool's async
# dispatch acknowledgement, not on the subagent's actual completion (measured
# duration_approx_s of 1-3s against a real usage.duration_ms of 45-54s for the
# same calls) — decrementing immediately read depth back to 0 while the
# subagent was still genuinely running, which is exactly what let
# guard-pipeline-direct-work.sh block real coder/tester subagents mid-Write.
# The decrement is scheduled instead, anchored on the matched Start timestamp
# plus a grace window (see unity_subagent_schedule_decrement in _lib.sh), and
# applied lazily the next time anything reads unity_subagent_depth().
unity_subagent_schedule_decrement $(( START_EPOCH + UNITY_SUBAGENT_STOP_GRACE_SECONDS ))

exit 0
