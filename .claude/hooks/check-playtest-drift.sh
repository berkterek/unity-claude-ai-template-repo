#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

# --- Hook Audit Logging ---
_hook_log() {
    local code=$1
    local log="${HOME}/.claude/hook-audit.log"
    mkdir -p "$(dirname "$log")"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local proj; proj=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    local file="${FILE_PATH:-}"
    local status
    if [ "$code" -eq 2 ]; then status="BLOCKED"
    elif [ "$code" -eq 0 ]; then status="OK"
    else status="WARN"; fi
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-playtest-drift" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# ============================================================================
# check-playtest-drift.sh — WARNING HOOK
# After a *DebugCommands.cs change, checks that the generated command table in
# docs/PLAYTEST.md is still current; stale → one warning with the regenerate command.
# ============================================================================
# Trigger: PostToolUse on Edit|Write
# Exit: always 0
# ============================================================================

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$(basename "${FILE_PATH:-x}")" in
    *DebugCommands.cs) ;;
    *) exit 0 ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
GENERATOR="${SCRIPT_DIR}/../scripts/generate-playtest-commands.py"
cd "$PROJECT_DIR" || exit 0

if [ ! -f docs/PLAYTEST.md ]; then
    unity_hook_warn "docs/PLAYTEST.md is missing — the command table for $(basename "$FILE_PATH") has nowhere to go. /setup-project writes the skeleton."
fi

python3 -I "$GENERATOR" --check >/dev/null 2>&1
case $? in
    0) exit 0 ;;
    1) unity_hook_warn "docs/PLAYTEST.md debug-command table is stale after editing $(basename "$FILE_PATH"). Regenerate: python3 -I .claude/scripts/generate-playtest-commands.py" ;;
    *) unity_hook_warn "docs/PLAYTEST.md has no debug-commands markers — run: python3 -I .claude/scripts/generate-playtest-commands.py (it explains what is missing)" ;;
esac
