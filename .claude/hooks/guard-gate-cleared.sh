#!/usr/bin/env bash
# ============================================================================
# guard-gate-cleared.sh — BLOCKING HOOK
#
# Blocks pipeline agents (tester, coder, unity-coder, committer, etc.) from
# being spawned unless a Director Gate has been shown and cleared first.
#
# Gate is cleared by writing .claude/state/gate-cleared (done by Claude after
# user types `go`). File expires after 30 minutes.
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
PIPELINE_AGENTS="^(tester|coder|unity-coder|unity-coder-lite|unity-fixer|unity-fixer-lite|committer|unity-migrator|migrator|unity-setup)$"

if ! echo "$SUBAGENT_TYPE" | grep -qE "$PIPELINE_AGENTS"; then
    exit 0  # Not a pipeline agent — allow through
fi

GATE_FILE=".claude/state/gate-cleared"

# Check file exists
if [ ! -f "$GATE_FILE" ]; then
    echo "" >&2
    echo "  GATE VIOLATION ─────────────────────────────────────────────" >&2
    echo "  Cannot spawn '$SUBAGENT_TYPE' — no Director Gate has been cleared." >&2
    echo "" >&2
    echo "  Every pipeline command must show SCOPE_GATE (or ARCHITECTURE_GATE" >&2
    echo "  for /new-module) and receive 'go' from the user before spawning" >&2
    echo "  any pipeline agents." >&2
    echo "" >&2
    echo "  To clear the gate:" >&2
    echo "    1. Show the required gate block to the user" >&2
    echo "    2. Wait for 'go'" >&2
    echo "    3. Run: mkdir -p .claude/state && echo '{\"gate\":\"cleared\"}' > .claude/state/gate-cleared" >&2
    echo "  ────────────────────────────────────────────────────────────" >&2
    exit 2
fi

# Check file is not expired (30 minutes)
if command -v stat &>/dev/null; then
    # macOS
    MTIME=$(stat -f %m "$GATE_FILE" 2>/dev/null) || MTIME=0
    # Linux fallback
    [ "$MTIME" -eq 0 ] && MTIME=$(stat -c %Y "$GATE_FILE" 2>/dev/null) || true
    NOW=$(date +%s)
    AGE=$(( NOW - MTIME ))

    if [ "$AGE" -gt 1800 ]; then
        rm -f "$GATE_FILE"
        echo "" >&2
        echo "  GATE EXPIRED ───────────────────────────────────────────────" >&2
        echo "  The Director Gate was cleared more than 30 minutes ago." >&2
        echo "  Show the gate to the user again and wait for 'go'." >&2
        echo "  ────────────────────────────────────────────────────────────" >&2
        exit 2
    fi
fi

exit 0
