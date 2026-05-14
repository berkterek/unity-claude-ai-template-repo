#!/usr/bin/env bash
# ============================================================================
# guard-reviewer-order.sh — BLOCKING HOOK
#
# Enforces reviewer priority: Codex → unity-reviewer
#
# If the Codex CLI is installed and available, unity-reviewer cannot be
# spawned unless Codex has already run this pipeline pass (tracked via
# .claude/state/codex-reviewed).
#
# Flow:
#   1. Pipeline spawns codex:codex-rescue agent
#   2. track-codex-review.sh (PostToolUse) creates .claude/state/codex-reviewed
#   3. Pipeline spawns unity-reviewer → this hook allows it (Codex ran)
#
#   If Codex is NOT installed → unity-reviewer allowed immediately.
#   If Codex IS installed but codex-reviewed missing → BLOCKED.
# ============================================================================
# Trigger: PreToolUse on Agent
# Exit:    2 = block, 0 = allow
# ============================================================================

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if [ "$SUBAGENT_TYPE" != "unity-reviewer" ]; then
    exit 0
fi

# Check if Codex CLI is available
if ! command -v codex &>/dev/null; then
    exit 0  # Codex not installed — unity-reviewer is the primary reviewer
fi

# Check if Codex already reviewed this pipeline pass
REVIEWED_FILE=".claude/state/codex-reviewed"

GATE_FILE=".claude/state/gate-cleared"

if [ -f "$REVIEWED_FILE" ]; then
    # Stale check: gate-cleared is written at pipeline start; codex-reviewed is written mid-pipeline.
    # If gate-cleared is NEWER than codex-reviewed, the marker is from a previous run — ignore it.
    if [ -f "$GATE_FILE" ] && [ "$GATE_FILE" -nt "$REVIEWED_FILE" ]; then
        : # stale marker — fall through and block
    else
        exit 0  # Valid marker — Codex ran in this pipeline pass
    fi
fi

echo "" >&2
echo "  REVIEWER ORDER VIOLATION ───────────────────────────────────────" >&2
echo "  Cannot spawn 'unity-reviewer' — Codex plugin is installed but" >&2
echo "  has not reviewed this pipeline pass yet." >&2
echo "" >&2
echo "  Reviewer priority: Codex → unity-reviewer (fallback)" >&2
echo "" >&2
echo "  To fix:" >&2
echo "    1. Spawn the 'codex:codex-rescue' agent first" >&2
echo "    2. track-codex-review.sh will mark Codex as done" >&2
echo "    3. Then unity-reviewer can run as a secondary pass" >&2
echo "" >&2
echo "  If Codex is unreachable (no API key, network error), manually" >&2
echo "  create the bypass:" >&2
echo "    mkdir -p .claude/state && touch .claude/state/codex-reviewed" >&2
echo "  ────────────────────────────────────────────────────────────────" >&2
exit 2
