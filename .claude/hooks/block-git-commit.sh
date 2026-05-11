#!/usr/bin/env bash

# ============================================================================
# block-git-commit.sh — APPROVAL GATE HOOK
# Pauses every git commit attempt and asks the user for explicit approval.
# Claude cannot commit autonomously — user must confirm each time.
# Use /smart-commit for a guided commit workflow.
# ============================================================================
# Trigger: PreToolUse on Bash
# Output: JSON with permissionDecision "ask" to force approval prompt
# ============================================================================

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

STRIPPED=$(echo "$CMD" | sed "s/'[^']*'//g" | sed 's/"[^"]*"//g')
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)git\s+commit(\s|$)'; then
    echo '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "git commit requires your explicit approval. Use /smart-commit for a guided workflow, or approve this prompt to commit now."
  }
}'
    exit 0
fi

exit 0
