#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
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
REVIEWED_FILE="${UNITY_HOOK_STATE_DIR}/codex-reviewed"

GATE_FILE="${UNITY_HOOK_STATE_DIR}/gate-cleared"

REVIEWED_REASON="has not reviewed this pipeline pass yet"

# Two independent bounds, both required. Until 2026-10-04 there was a third
# "bound" that was really a bug: session-save.sh deleted this marker at every
# turn-end, which made the marker live less than one turn and this hook block
# unity-reviewer unconditionally (see that file's comment). With the deletion
# gone the marker needs a real expiry, or an approval becomes immortal — the
# same pair of failure modes sparc-approved went through.
#
# Bound 1 — TTL. Capture the status explicitly: unity_gate_cleared_valid exits
# 1/2/3 for missing/unreadable/stale, and letting those propagate under
# `set -e` would exit this hook with 1 or 3. Only 2 blocks a spawn, so an
# uncaptured status silently turns the guard off. Same trap documented in
# guard-sparc-approved.sh.
CODEX_STATUS=0
unity_gate_cleared_valid "codex-reviewed" >/dev/null || CODEX_STATUS=$?

# Bound 2 — pipeline pass. gate-cleared is written at pipeline start and
# codex-reviewed mid-pipeline, so a gate-cleared NEWER than the marker means the
# marker belongs to a previous run. Narrower than the TTL and not replaced by it:
# a second pipeline can start well inside the TTL window.
if [ "$CODEX_STATUS" -eq 0 ] && [ -f "$GATE_FILE" ] && [ "$GATE_FILE" -nt "$REVIEWED_FILE" ]; then
    CODEX_STATUS=4
fi

case $CODEX_STATUS in
    0) exit 0 ;;  # Codex ran in this pipeline pass, recently enough
    3) REVIEWED_REASON="reviewed more than $((UNITY_GATE_TTL / 60)) minutes ago — that receipt expired" ;;
    2) REVIEWED_REASON="left a receipt whose age could not be read — treated as expired" ;;
    4) REVIEWED_REASON="reviewed before this pipeline pass started — that receipt is stale" ;;
esac

echo "" >&2
echo "  REVIEWER ORDER VIOLATION ───────────────────────────────────────" >&2
echo "  Cannot spawn 'unity-reviewer' — Codex plugin is installed but" >&2
echo "  $REVIEWED_REASON." >&2
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
# Print the resolved path, not a relative one. This hook reads $REVIEWED_FILE;
# telling the human to touch a relative `.claude/state/codex-reviewed` sends
# them to a path this hook never checks, so the bypass appears not to work.
echo "    mkdir -p \"$UNITY_HOOK_STATE_DIR\" && touch \"$REVIEWED_FILE\"" >&2
echo "  ────────────────────────────────────────────────────────────────" >&2
exit 2
