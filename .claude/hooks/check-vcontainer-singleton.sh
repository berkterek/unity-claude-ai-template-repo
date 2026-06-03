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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-vcontainer-singleton" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks static singleton patterns outside of approved accessors
# Approved exception: EventBusAccessor (static bridge for ECS <-> Mono communication)
# VContainer is the only DI mechanism — static Instance fields are forbidden
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

# Skip test files and editor files
if echo "$FILE_PATH" | grep -qiE "(Tests?|Spec|/Editor/)"; then
    exit 0
fi

# Skip the approved accessor files
FILENAME=$(basename "$FILE_PATH" .cs)
if echo "$FILENAME" | grep -qiE "^(EventBusAccessor|ServiceAccessor)$"; then
    exit 0
fi

# Skip ECS systems — they use SystemAPI, not singletons
if echo "$FILE_PATH" | grep -qiE "Games/Ecs/Systems/"; then
    exit 0
fi

ISSUES=""

# Strip single-line comments
STRIPPED=$(sed 's|//.*||g' "$FILE_PATH" 2>/dev/null)

# Pattern 1: static Instance or _instance field of the class's own type
STATIC_INSTANCE=$(echo "$STRIPPED" | grep -n "private\s\+static\s\+.*\bInstance\b\|private\s\+static\s\+.*\b_instance\b")
if [ -n "$STATIC_INSTANCE" ]; then
    ISSUES="${ISSUES}\n${STATIC_INSTANCE}"
fi

# Pattern 2: public static T Instance { get; } property
STATIC_PROP=$(echo "$STRIPPED" | grep -n "public\s\+static\s\+.*\bInstance\b\s*{")
if [ -n "$STATIC_PROP" ]; then
    ISSUES="${ISSUES}\n${STATIC_PROP}"
fi

# Pattern 3: DontDestroyOnLoad called on 'this' (classic singleton setup)
DONT_DESTROY=$(echo "$STRIPPED" | grep -n "DontDestroyOnLoad\s*(this)")
if [ -n "$DONT_DESTROY" ]; then
    ISSUES="${ISSUES}\n${DONT_DESTROY}"
fi

if [ -n "$ISSUES" ]; then
    MSG="Singleton pattern detected in: $FILE_PATH"$'\n'
    MSG+="Violations:"$'\n'"$(echo -e "$ISSUES")"$'\n'
    MSG+="Use VContainer instead (AppScope for app-wide, GameScope for scene-local)."
    unity_hook_block "$MSG"
fi

exit 0
