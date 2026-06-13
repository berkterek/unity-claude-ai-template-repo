#!/usr/bin/env bash
# ============================================================================
# track-skill-invocations.sh — PostToolUse hook (matcher: Skill)
#
# Records every Skill tool invocation to the session state file.
# Used by enforce-skill-for-keywords.sh to know which skills were already
# invoked — so the enforcement hook doesn't fire for skills already loaded.
# ============================================================================
# Trigger: PostToolUse on Skill
# Exit:    always 0 (observational only)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)

if [ -z "$SKILL_NAME" ]; then
    exit 0
fi

INVOKED_FILE="${UNITY_HOOK_STATE_DIR}/skills-invoked.txt"
touch "$INVOKED_FILE" 2>/dev/null || true

# Append skill name if not already recorded (idempotent)
if ! grep -qxF "$SKILL_NAME" "$INVOKED_FILE" 2>/dev/null; then
    echo "$SKILL_NAME" >> "$INVOKED_FILE"
fi

# Inject additionalContext so Claude is forced to acknowledge and follow the skill
MSG="MANDATORY: You just invoked the skill \"${SKILL_NAME}\". You MUST read its full content above and follow every instruction in it exactly before proceeding. Do NOT skip steps. Do NOT summarize and move on. The skill instructions are NON-NEGOTIABLE."
jq -n --arg msg "$MSG" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $msg}}'

exit 0
