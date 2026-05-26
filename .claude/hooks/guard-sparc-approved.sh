#!/usr/bin/env bash
# PreToolUse hook — SPARC gate guard for coder agent spawns
# Trigger tool: Agent | Gated: coder, unity-coder, unity-coder-lite
# State file: .claude/state/sparc-approved (independent of gate-cleared)
# Lifecycle: written by pipeline after 'go'; deleted after gated agent completes
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ "$TOOL_NAME" != "Agent" ]; then
  exit 0
fi

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if ! echo "$SUBAGENT_TYPE" | grep -qE '^(coder|unity-coder|unity-coder-lite)$'; then
  exit 0
fi

SPARC_STATE=".claude/state/sparc-approved"
if [[ -f "$SPARC_STATE" ]]; then
  exit 0
fi

echo "" >&2
echo "  SPARC_GATE ──────────────────────────────────────────────────────────" >&2
echo "  Cannot spawn '$SUBAGENT_TYPE' — Specification + Architecture not approved." >&2
echo "" >&2
echo "  Show SPARC_GATE to user, wait for 'go', then run:" >&2
echo "    mkdir -p .claude/state && touch .claude/state/sparc-approved" >&2
echo "  Delete .claude/state/sparc-approved after the coder agent completes." >&2
echo "  ─────────────────────────────────────────────────────────────────────" >&2
exit 2
