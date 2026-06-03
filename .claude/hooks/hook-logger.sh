#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
# Central hook audit logger.
# Usage: hook-logger.sh <hook-name> <exit-code> <file-path> [message]
#
# Call this at the end of every hook before exiting:
#   source .claude/hooks/hook-logger.sh
#   log_hook "check-input-system" "$EXIT_CODE" "$FILE_PATH" "$ISSUES"

LOG_FILE="${HOME}/.claude/hook-audit.log"
MAX_LINES=500

log_hook() {
    local hook_name="$1"
    local exit_code="$2"
    local file_path="$3"
    local message="${4:-}"

    local status
    case "$exit_code" in
        0) status="OK" ;;
        2) status="BLOCKED" ;;
        *) status="WARN" ;;
    esac

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

    local relative_path="${file_path#$project_root/}"

    local log_entry
    log_entry=$(printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}' \
        "$timestamp" "$hook_name" "$status" "$relative_path" "$(basename "$project_root")")

    if [ -n "$message" ] && [ "$exit_code" != "0" ]; then
        local first_line
        first_line=$(echo "$message" | grep -m1 "." | head -c 120)
        log_entry=$(printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s","msg":"%s"}' \
            "$timestamp" "$hook_name" "$status" "$relative_path" "$(basename "$project_root")" "$first_line")
    fi

    echo "$log_entry" >> "$LOG_FILE"

    # Trim log if it exceeds MAX_LINES
    if [ -f "$LOG_FILE" ]; then
        local line_count
        line_count=$(wc -l < "$LOG_FILE")
        if [ "$line_count" -gt "$MAX_LINES" ]; then
            tail -n "$MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    fi
}
