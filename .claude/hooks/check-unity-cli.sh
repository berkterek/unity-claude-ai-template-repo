#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict — standard keeps CLAUDE.md's "6 critical safety hooks" true
source "${SCRIPT_DIR}/_lib.sh"

# ============================================================================
# check-unity-cli.sh — BLOCKING HOOK (PreToolUse on Bash)
# Enforces the ban in docs/incidents/mcp-and-framework.md on the Unity CLI's live-Editor
# code channel. The judgement lives in .claude/scripts/check-unity-cli.py; this file routes.
# Keep this file free of heredocs and inline Python: bash 3.2 (macOS /bin/bash) mis-parses a
# heredoc inside a command substitution whose body holds a backtick — every call would exit 2.
# Does NOT call `unity` itself. Not airtight — accepted gaps in the incident doc.
# Exit: 2 = block, 0 = allow
# ============================================================================

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

W='[^A-Za-z0-9_-]'   # word boundary for `unity`; BSD grep has no portable \b
printf '%s\n' "$CMD" | grep -qiE "(^|$W)unity($W|\$)" || exit 0

JUDGE="${SCRIPT_DIR}/../scripts/check-unity-cli.py"
VERDICT=""
[ -r "$JUDGE" ] && VERDICT=$(CHECK_UNITY_CLI_CMD="$CMD" python3 -I "$JUDGE" 2>/dev/null)

case "$VERDICT" in
    ALLOW) exit 0 ;;
    "BLOCK "*) REASON="${VERDICT#BLOCK }" ;;
    *)  # judge missing/unreadable, python3 absent, or crashed: fail closed on a narrow regex
        if printf '%s\n' "$CMD" | grep -qiE \
            -e "(^|$W)unity$W(.*$W)?(command|cmd)[[:space:]]+[^-[:space:]]" \
            -e "(^|$W)unity$W(.*$W)?pipe(line)?[[:space:]]+(install|upgrade)" \
            -e "(^|$W)unity$W(.*$W)?(shell|mcp)($W|\$)" \
            -e "(^|$W)unity$W.*--command"; then
            REASON="judge unavailable (${JUDGE##*/} missing or failed) - conservative regex match"
        else
            exit 0
        fi ;;
esac

MSG="[check-unity-cli] ${REASON}

This is the Unity CLI's live-Editor code channel. The C# never becomes a file, so no
Edit|Write content hook sees it, and it skips the MCP pre-flight
(skills/core/mcp-preflight.md: instance pinning, dataPath check).

  Live Editor work      -> MCP: manage_scene / manage_gameobject / manage_components
  MCP bridge missing    -> restart the session; do not substitute the CLI
  Headless compile/test -> unity test / unity build (skills/core/unity-cli-verify.md)

Do not route around this block. Rule: docs/incidents/mcp-and-framework.md"
unity_hook_block "$MSG"
