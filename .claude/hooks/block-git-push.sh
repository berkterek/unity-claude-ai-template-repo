#!/usr/bin/env bash

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
    echo "  You can commit freely — push is your responsibility." >&2
    echo "  Push manually when you are ready." >&2
    exit 2
fi

exit 0
