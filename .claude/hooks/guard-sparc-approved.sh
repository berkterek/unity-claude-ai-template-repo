#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
# PreToolUse hook — SPARC gate guard for coder agent spawns
# Trigger tool: Agent | Gated: coder, unity-coder
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

if ! echo "$SUBAGENT_TYPE" | grep -qE '^(coder|unity-coder)$'; then
  exit 0
fi

SPARC_STATE="${UNITY_HOOK_STATE_DIR}/sparc-approved"

# Existence is not enough — the approval also has to be fresh. This used to be a
# bare -f test, and the only thing bounding it was session-save.sh deleting the
# file on every turn-end, which meant a multi-turn phase re-approved SPARC_GATE
# once per turn. That deletion is gone; the TTL is what replaces it.
#
# States 2 and 3 are deliberately NOT treated alike. A stale gate (3) is a real
# answer — refuse. An indeterminate age (2, the mtime read failed) is the absence
# of an answer, and this is a deny-then-allow gate whose pass releases a coder
# spawn, so it resolves toward enforcing. Same split unity_subagent_depth documents.
# `|| true` is load-bearing under `set -e`: without it a non-zero return from the
# helper aborts the script with THAT status, so the block below never runs and the
# hook exits 1 or 3 instead of the 2 that actually blocks the spawn. A hook that
# exits 1 warns; only 2 blocks — so the bug would have silently disabled the gate.
SPARC_STATUS=0
unity_gate_cleared_valid "sparc-approved" >/dev/null || SPARC_STATUS=$?
case $SPARC_STATUS in
  0) exit 0 ;;
  3) SPARC_REASON="approved more than $((UNITY_GATE_TTL / 60)) minutes ago — the approval expired" ;;
  2) SPARC_REASON="approval file present but its age could not be read — treated as expired" ;;
  *) SPARC_REASON="Specification + Architecture not approved" ;;
esac

echo "" >&2
echo "  SPARC_GATE ──────────────────────────────────────────────────────────" >&2
echo "  Cannot spawn '$SUBAGENT_TYPE' — $SPARC_REASON." >&2
echo "" >&2
echo "  Show SPARC_GATE to user, wait for 'go', then run:" >&2
# Resolved path, not relative — this hook checks $SPARC_STATE, so a relative
# instruction points the human at a file the hook never reads.
echo "    mkdir -p \"$UNITY_HOOK_STATE_DIR\" && touch \"$SPARC_STATE\"" >&2
echo "  (touch re-stamps an expired approval too — but only after showing the gate again.)" >&2
echo "  Delete \"$SPARC_STATE\" after the coder agent completes." >&2
echo "  ─────────────────────────────────────────────────────────────────────" >&2
exit 2
