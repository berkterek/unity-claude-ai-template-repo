#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
source "${SCRIPT_DIR}/lib-path-rules.sh"

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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-domain-folder-structure" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Enforces the Unity script path rules at WRITE time. All rule logic lives
#       in lib-path-rules.sh — this file is only the hook plumbing (stdin, block).
#       The SAME library is called at PLAN time by
#       .claude/scripts/validate-plan-paths.sh, which is the check that actually
#       prevents the mistake; this hook is the backstop for whatever the plan
#       never wrote down.
# Event: PreToolUse (pure path check — needs no file content, so it can and
#        must stop the bad path before the file is ever created).
# Receives JSON on stdin with tool_input.file_path
#
# NOTE — non-.cs writes are NOT skipped any more. An .asmdef is exactly how an
# illegal top-level folder gets created, and the old .cs-only gate meant a module
# whose whole output was folders + asmdefs passed without a single check running.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

should_skip_path "$FILE_PATH" && exit 0

if MSG=$(unity_validate_script_path "$FILE_PATH"); then
    exit 0
else
    unity_hook_block "$MSG"
fi
