#!/bin/bash

# --- Hook Audit Logging ---
_hook_log() {
    local code=$1
    local log="${HOME}/.claude/hook-audit.log"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local proj; proj=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    local file="${FILE_PATH:-}"
    local status
    if [ "$code" -eq 2 ]; then status="BLOCKED"
    elif [ "$code" -eq 0 ]; then status="OK"
    else status="WARN"; fi
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-time-scale" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 5000 ]; then tail -n 5000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks Time.timeScale assignments in runtime C# scripts
# Pause/resume must be implemented via IEventBus + a dedicated PauseService
# Time.timeScale is a global side-effect that breaks physics, animations, and UniTask timing
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if ! echo "$FILE_PATH" | grep -qE "\.cs$"; then
    exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Skip test files
if echo "$FILE_PATH" | grep -qiE "(Tests?|Spec)/"; then
    exit 0
fi

# Skip Editor-only files
if echo "$FILE_PATH" | grep -qE "/Editor/"; then
    exit 0
fi

# Strip comments and string literals to avoid false positives
STRIPPED=$(sed 's|//.*||g; s/"[^"]*"/""/g' "$FILE_PATH" 2>/dev/null | sed ':a;N;$!ba;s|/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/||g')

ISSUES=""

# Check: Time.timeScale assignment (= 0, = 1, = 0f, = 1f, or any value)
TIME_SCALE=$(echo "$STRIPPED" | grep -nE "Time\.timeScale\s*=")
if [ -n "$TIME_SCALE" ]; then
    ISSUES="${ISSUES}\nBLOCKING — Time.timeScale assignment detected:\n${TIME_SCALE}\n"
    ISSUES="${ISSUES}Time.timeScale is forbidden for pause/resume logic.\n"
    ISSUES="${ISSUES}Use instead:\n"
    ISSUES="${ISSUES}  1. Publish a PauseRequestedEvent / ResumeRequestedEvent via IEventBus\n"
    ISSUES="${ISSUES}  2. Implement a PauseService that subscribes to these events\n"
    ISSUES="${ISSUES}  3. Systems opt-in to pause by subscribing and halting their own logic\n"
    ISSUES="${ISSUES}  4. Use UniTask CancellationToken to cancel running tasks on pause\n"
    ISSUES="${ISSUES}  5. Use Time.unscaledDeltaTime in UI/menus that must run while paused\n"
fi

if [ -n "$ISSUES" ]; then
    echo "TIME SCALE ERROR in: $FILE_PATH"
    echo -e "$ISSUES"
    exit 2
fi

exit 0
