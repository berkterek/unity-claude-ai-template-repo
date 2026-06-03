#!/usr/bin/env bash
# ============================================================================
# track-read.sh — PostToolUse: Read
# Records every file path passed to the Read tool into gateguard-reads.txt
# so that gateguard.sh's unity_was_read() check succeeds on the next Edit/Write.
#
# Without this hook, gateguard-reads.txt is never populated and Stage 1
# ("Read before Edit") blocks every edit — even after the agent reads the file.
# ============================================================================
# Trigger:  PostToolUse on Read
# Exit:     0 always (informational only)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .file_path // .path // empty' 2>/dev/null || true)

if [[ -n "$FILE_PATH" ]]; then
    unity_track_read "$FILE_PATH"
fi

exit 0
