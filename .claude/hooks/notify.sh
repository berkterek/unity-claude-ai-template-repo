#!/usr/bin/env bash
# ============================================================================
# notify.sh — NOTIFICATION HOOK
# Surfaces OS-level notifications when Claude finishes a task or needs input.
# Reads the notification payload from stdin.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

# Define last-notify state file locally — do not assume a global env var exists.
LAST_NOTIFY="${CLAUDE_PROJECT_DIR:-.}/.claude/state/last-notify.json"

INPUT=$(cat)
MESSAGE=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(d.get('message', 'Claude Code: task complete'))
except Exception:
    print('Claude Code')
" "$INPUT" 2>/dev/null || echo "Claude Code")

case "$(uname -s)" in
    Darwin)
        osascript -e "display notification \"${MESSAGE//\"/}\" with title \"Claude Code\" sound name \"Glass\"" 2>/dev/null || true ;;
    Linux)
        command -v notify-send >/dev/null 2>&1 && notify-send "Claude Code" "$MESSAGE" || true ;;
esac

# Persist last-notify for /catch-up
mkdir -p "$(dirname "$LAST_NOTIFY")"
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"message\":$(printf '%s' "$MESSAGE" | jq -Rs .)}" > "$LAST_NOTIFY"
exit 0
