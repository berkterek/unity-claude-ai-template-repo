#!/usr/bin/env bash
# ============================================================================
# suggest-compact.sh — PostToolUse hook (main session only)
#
# Every turn re-reads the whole context. Measured on nile (2026-11-05, 28 main
# sessions): 99% of cache-read cost came from sessions whose context passed
# 300k, and 53% of all main-session cost was conversation growth above the
# startup context. Nothing told the session it had grown; auto-compact fires
# only near the window limit, which on a 1M window is far too late.
#
# This hook reads the latest assistant `usage` record of the session transcript
# (input + cache read + cache write = what the next turn re-reads) and, once it
# passes the threshold, injects a one-time reminder to clear or compact at the
# next logical breakpoint. It re-reminds after every further INTERVAL tokens.
#
# Prior art: ECC scripts/hooks/suggest-compact.js (#2155). Its tool-call-count
# signal is deliberately left out — ECC itself calls it a weak proxy, and here
# it would nag cheap sessions of many small calls.
#
# Env:
#   UNITY_COMPACT_CONTEXT_THRESHOLD  first reminder, tokens (default 250000)
#   UNITY_COMPACT_CONTEXT_INTERVAL   re-remind after this much growth (default 60000)
# ============================================================================
# Trigger: PostToolUse (any tool)
# Exit:    0 always — prints additionalContext JSON when a reminder is due
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
# A subagent's tool call carries agent_id; its context dies with it.
[ -n "$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)" ] && exit 0

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$SESSION" ] || [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

THRESHOLD="${UNITY_COMPACT_CONTEXT_THRESHOLD:-250000}"
INTERVAL="${UNITY_COMPACT_CONTEXT_INTERVAL:-60000}"

# Tail only: transcripts reach tens of MB and this runs after every tool call.
CTX=$(tail -c 400000 "$TRANSCRIPT" | grep '"type":"assistant"' | grep -v '"isSidechain":true' | tail -1 \
    | jq -r '.message.usage | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))' 2>/dev/null || true)
[[ "$CTX" =~ ^[0-9]+$ ]] || exit 0

BUCKET_FILE="${UNITY_HOOK_STATE_DIR}/compact-bucket-${SESSION}"
LAST=$(cat "$BUCKET_FILE" 2>/dev/null || echo -1)
[[ "$LAST" =~ ^-?[0-9]+$ ]] || LAST=-1

if [ "$CTX" -lt "$THRESHOLD" ]; then
    # Below again after /compact — arm the reminder for the next climb.
    [ "$LAST" -ge 0 ] && echo -1 > "$BUCKET_FILE"
    exit 0
fi

BUCKET=$(( (CTX - THRESHOLD) / INTERVAL ))
[ "$BUCKET" -le "$LAST" ] && exit 0
echo "$BUCKET" > "$BUCKET_FILE"

# Old session buckets: one file per session, nothing else removes them.
find "$UNITY_HOOK_STATE_DIR" -maxdepth 1 -name 'compact-bucket-*' -mtime +14 -delete 2>/dev/null || true

K=$(( CTX / 1000 ))
MSG="Context is ~${K}k tokens and every turn re-reads all of it. Finish the current step, then at the next logical breakpoint (task or group done, checkpoint) tell the user: in /orchestrate answer \`stop\`, run /clear, then re-run /orchestrate — checked tasks are skipped, the plan files carry the state. Outside /orchestrate: /clear between unrelated tasks, or /compact Focus on <current task>. Do not stop mid-task for this."

jq -n --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
