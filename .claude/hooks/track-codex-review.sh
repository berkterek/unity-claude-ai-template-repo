#!/usr/bin/env bash
# ============================================================================
# track-codex-review.sh — PostToolUse hook
#
# When the codex:codex-rescue agent finishes, creates the state marker
# .claude/state/codex-reviewed so guard-reviewer-order.sh allows
# unity-reviewer to run as the secondary pass.
#
# The marker is intentionally NOT auto-deleted — the pipeline committer
# or the next pipeline start should clean it up. This prevents stale state
# from accidentally blocking unity-reviewer across unrelated pipeline runs.
#
# Cleanup: add `rm -f .claude/state/codex-reviewed` at the end of any
# pipeline command that uses the Codex → unity-reviewer review sequence.
# ============================================================================
# Trigger: PostToolUse on Agent
# Exit:    0 always (tracking only — never blocks)
# ============================================================================

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if [ "$SUBAGENT_TYPE" != "codex:codex-rescue" ]; then
    exit 0
fi

mkdir -p .claude/state
touch .claude/state/codex-reviewed

exit 0
