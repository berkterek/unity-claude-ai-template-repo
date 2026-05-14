#!/usr/bin/env bash
# ============================================================================
# warn-reviewer-priority.sh — WARNING HOOK
#
# Warns when unity-reviewer is spawned directly without Codex being tried
# first. Reviewer priority is: codex:codex-rescue → unity-reviewer.
#
# Does NOT block — exit 0 always. Just reminds Claude of the correct order.
# ============================================================================
# Trigger: PreToolUse on Agent
# Exit:    0 always (warning only)
# ============================================================================

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if [ "$SUBAGENT_TYPE" = "unity-reviewer" ]; then
    echo "⚠ REVIEWER PRIORITY: unity-reviewer spawned directly." >&2
    echo "  Correct order: codex:codex-rescue → unity-reviewer (fallback only)." >&2
    echo "  If Codex is unavailable or already ran, ignore this warning." >&2
fi

exit 0
