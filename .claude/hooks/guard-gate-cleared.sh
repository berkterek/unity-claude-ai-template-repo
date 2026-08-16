#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
# ============================================================================
# guard-gate-cleared.sh — BLOCKING HOOK
#
# Blocks pipeline agents (tester, coder, unity-coder, committer, etc.) from
# being spawned unless a Director Gate has been shown and cleared first.
#
# Gate is cleared by writing .claude/state/gate-cleared (done by Claude after
# user types `go`). Lifecycle: written on approval → deleted by agent-stop-log.sh
# when committer completes → force-expired by session-restore.sh on SessionStart.
# ============================================================================
# Trigger: PreToolUse on Agent
# Exit:    2 = block, 0 = allow
# ============================================================================

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only applies to Agent tool
if [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

# Pipeline agents that require a cleared gate
PIPELINE_AGENTS="^(tester|coder|unity-coder|unity-fixer|committer|unity-migrator|migrator|unity-setup)$"

if ! echo "$SUBAGENT_TYPE" | grep -qE "$PIPELINE_AGENTS"; then
    exit 0  # Not a pipeline agent — allow through
fi

# UNITY_HOOK_STATE_DIR is set by _lib.sh using git rev-parse — always absolute path.
# TTL lives in _lib.sh as UNITY_GATE_TTL (2700s / 45 min): covers slow SPARC/plan
# phases while limiting the window during which an interrupted pipeline's gate
# remains valid.
GATE_FILE="${UNITY_HOOK_STATE_DIR}/gate-cleared"

_gate_blocked() {
    local reason="$1"
    echo "" >&2
    echo "  GATE VIOLATION ─────────────────────────────────────────────" >&2
    echo "  Cannot spawn '$SUBAGENT_TYPE' — $reason" >&2
    echo "" >&2
    echo "  Every pipeline command must show SCOPE_GATE (or ARCHITECTURE_GATE" >&2
    echo "  for /new-module) and receive 'go' from the user before spawning" >&2
    echo "  any pipeline agents." >&2
    echo "" >&2
    echo "  To clear the gate:" >&2
    echo "    1. Show the required gate block to the user" >&2
    echo "    2. Wait for 'go'" >&2
    echo "    3. Run: mkdir -p \"\$(git rev-parse --show-toplevel)/.claude/state\" && echo '{\"gate\":\"cleared\"}' > \"\$(git rev-parse --show-toplevel)/.claude/state/gate-cleared\"" >&2
    echo "  ────────────────────────────────────────────────────────────" >&2
    exit 2
}

set +e
GATE_AGE=$(unity_gate_cleared_valid)
GATE_STATUS=$?
set -e

case "$GATE_STATUS" in
    1) _gate_blocked "no Director Gate has been cleared." ;;
    3) _gate_blocked "the Director Gate has expired (age ${GATE_AGE}s > ${UNITY_GATE_TTL}s TTL). Re-show the gate and get a fresh 'go'." ;;
    2) : ;;  # age indeterminate — historical behaviour was to treat it as fresh
esac

exit 0
