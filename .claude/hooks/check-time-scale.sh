#!/bin/bash
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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-time-scale" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
_cleanup_effective_file() { rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; }
trap '_exit_code=$?; _cleanup_effective_file; _hook_log $_exit_code' EXIT
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

# --- Compute the EFFECTIVE post-tool-call content ---
# This hook runs PreToolUse: $FILE_PATH on disk is the file's state BEFORE the
# pending Edit/Write is applied. Checking that stale content means a BLOCKING
# violation already on disk can never be cleared — even an edit that removes
# the offending line still sees the unmodified disk file. Build the effective
# post-edit file and run every check against it instead.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
EFFECTIVE_FILE=$(mktemp)

case "$TOOL_NAME" in
    Write)
        echo "$INPUT" | jq -j '.tool_input.content // empty' > "$EFFECTIVE_FILE"
        ;;
    Edit)
        cp "$FILE_PATH" "$EFFECTIVE_FILE"
        OLD_STRING_FILE=$(mktemp)
        NEW_STRING_FILE=$(mktemp)
        echo "$INPUT" | jq -j '.tool_input.old_string // empty' > "$OLD_STRING_FILE"
        echo "$INPUT" | jq -j '.tool_input.new_string // empty' > "$NEW_STRING_FILE"
        REPLACE_ALL=$(echo "$INPUT" | jq -r '.tool_input.replace_all // false')
        if [ -s "$OLD_STRING_FILE" ]; then
            python3 - "$EFFECTIVE_FILE" "$OLD_STRING_FILE" "$NEW_STRING_FILE" "$REPLACE_ALL" <<'PYEOF' 2>/dev/null || true
import sys
target_path, old_path, new_path, replace_all = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"
with open(target_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    content = f.read()
with open(old_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    old = f.read()
with open(new_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    new = f.read()
content = content.replace(old, new) if replace_all else content.replace(old, new, 1)
with open(target_path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(content)
PYEOF
        fi
        ;;
    *)
        cp "$FILE_PATH" "$EFFECTIVE_FILE"
        ;;
esac

# Strip comments and string literals to avoid false positives
STRIPPED=$(strip_cs_noise "$EFFECTIVE_FILE")

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
