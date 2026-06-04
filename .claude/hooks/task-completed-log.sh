#!/usr/bin/env bash
# task-completed-log.sh — TaskCompleted hook
# Trigger: TaskCompleted (fires on success only — no status field in payload) | Exit: 0 always | Profile: standard
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
TASK_ID=$(echo "$INPUT"      | jq -r '.task_id      // "unknown"')
TASK_TITLE=$(echo "$INPUT"   | jq -r '.task_title   // "unknown"')
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"')
SESSION_ID=$(echo "$INPUT"   | jq -r '.session_id   // "unknown"')
TEAM_NAME=$(echo "$INPUT"    | jq -r '.team_name    // ""')

TASK_LOG="${UNITY_HOOK_STATE_DIR}/task-log.jsonl"

jq -nc \
    --arg event        "TaskCompleted" \
    --arg task_id      "$TASK_ID" \
    --arg task_title   "$TASK_TITLE" \
    --arg task_subject "$TASK_SUBJECT" \
    --arg session_id   "$SESSION_ID" \
    --arg team_name    "$TEAM_NAME" \
    --arg logged_at    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, task_id:$task_id, task_title:$task_title, task_subject:$task_subject, session_id:$session_id, team_name:$team_name, logged_at:$logged_at}' \
    >> "$TASK_LOG"

exit 0
