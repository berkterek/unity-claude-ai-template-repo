#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
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
# Cleanup: add `rm -f "$(git rev-parse --show-toplevel)"/.claude/state/codex-reviewed`
# at the end of any pipeline command that uses the Codex → unity-reviewer
# review sequence. The path is absolute for the reason given at the write below.
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

# $UNITY_HOOK_STATE_DIR (resolved absolutely by _lib.sh), never a relative
# `.claude/state`. A hook's cwd is whatever the tool call ran in — for a
# subagent that is not the repo root, so a relative write drops the marker in
# some arbitrary subtree while guard-reviewer-order.sh reads the absolute path.
# The observable failure is not a stray folder: it is that Codex demonstrably
# ran and the next unity-reviewer spawn is blocked anyway, because the writer
# and the reader are looking at two different places.
mkdir -p "$UNITY_HOOK_STATE_DIR"
touch "${UNITY_HOOK_STATE_DIR}/codex-reviewed"

exit 0
