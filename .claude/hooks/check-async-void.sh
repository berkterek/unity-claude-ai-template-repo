#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-async-void" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns about async void usage outside of Unity lifecycle methods
# Lifecycle methods (Awake, Start, OnEnable, OnDisable, OnDestroy, etc.) are exempt
# because Unity's signature forces void return — use .Forget() instead
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

# Unity lifecycle methods that are exempt (forced void signature)
LIFECYCLE_PATTERN="(Awake|Start|OnEnable|OnDisable|OnDestroy|OnApplicationQuit|OnApplicationPause|OnApplicationFocus|Reset|OnValidate|OnDrawGizmos|OnDrawGizmosSelected)"

ISSUES=""

# Strip single-line comments
STRIPPED=$(sed 's|//.*||g' "$FILE_PATH" 2>/dev/null)

# Find async void methods — extract line number and method name
while IFS= read -r line; do
    LINE_NUM=$(echo "$line" | cut -d: -f1)
    LINE_CONTENT=$(echo "$line" | cut -d: -f2-)

    # Extract method name from the line
    METHOD_NAME=$(echo "$LINE_CONTENT" | grep -oE "async\s+void\s+(\w+)" | grep -oE "[A-Za-z_]\w+$")

    # Skip Unity lifecycle methods
    if echo "$METHOD_NAME" | grep -qE "^${LIFECYCLE_PATTERN}$"; then
        continue
    fi

    ISSUES="${ISSUES}\n  Line ${LINE_NUM}: ${LINE_CONTENT}"
done < <(grep -n "async\s\+void\s" "$FILE_PATH" 2>/dev/null | grep -v "//")

if [ -n "$ISSUES" ]; then
    echo "WARNING — async void detected in: $FILE_PATH"
    echo ""
    echo "async void swallows exceptions silently. Use async UniTask instead:"
    echo -e "$ISSUES"
    echo ""
    echo "For fire-and-forget calls: DoWorkAsync(ct).Forget();"
    echo "Exception: Unity lifecycle methods (Awake, Start, OnEnable...) are exempt."
    exit 0
fi

exit 0
