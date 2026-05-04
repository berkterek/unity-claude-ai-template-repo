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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-event-naming" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 5000 ]; then tail -n 5000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns if IEvent implementations don't follow naming rules
# Rules: struct name must end with 'Event' suffix (e.g. LevelStartedEvent)
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [[ "$FILE_PATH" != *.cs ]]; then
    exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Find structs implementing IEvent that don't end with 'Event'
VIOLATIONS=$(grep -n ": IEvent" "$FILE_PATH" 2>/dev/null | grep -v "//")

if [ -z "$VIOLATIONS" ]; then
    exit 0
fi

while IFS= read -r line; do
    LINE_NUM=$(echo "$line" | cut -d: -f1)
    LINE_CONTENT=$(echo "$line" | cut -d: -f2-)

    # Extract struct name
    STRUCT_NAME=$(echo "$LINE_CONTENT" | grep -oE "struct [A-Za-z]+" | sed 's/struct //')

    if [ -n "$STRUCT_NAME" ] && ! echo "$STRUCT_NAME" | grep -q "Event$"; then
        echo "WARNING: IEvent struct '$STRUCT_NAME' at line $LINE_NUM doesn't end with 'Event' suffix."
        echo "File: $FILE_PATH"
        echo "Expected: ${STRUCT_NAME}Event (past tense, e.g. LevelStartedEvent, CoinsChangedEvent)"
    fi
done <<< "$VIOLATIONS"

exit 0
