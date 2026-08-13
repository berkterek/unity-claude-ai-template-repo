#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

# ============================================================================
# block-git-push.sh — BLOCKING HOOK
# Prevents Claude from running git push. The user always pushes manually.
# ============================================================================
# Trigger: PreToolUse on Bash
# Exit: 2 = block, 0 = allow
# ============================================================================

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Strip quoted strings first, then check for git push subcommand
STRIPPED=$(echo "$CMD" | sed "s/'[^']*'//g" | sed 's/"[^"]*"//g')
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)git\s+push(\s|$)'; then
    echo "BLOCKED: git push is not allowed." >&2
    echo "" >&2
    echo "  Pushing is the user's responsibility — push manually when ready." >&2
    echo "  This hook governs push only. It says nothing about whether you may" >&2
    echo "  commit; follow the user's own instructions on that." >&2
    exit 2
fi

exit 0
