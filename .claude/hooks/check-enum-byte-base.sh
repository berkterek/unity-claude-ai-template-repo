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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-enum-byte-base" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns when an enum inside an ECS component or IEvent struct does not inherit from byte.
# Only fires for files in Ecs/ folders or files containing IEvent / IComponentData context.
# Exit 2 — blocking. Enums in ECS/IEvent context MUST inherit from byte (non-negotiable per rules/ecs-dots.md).

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

# Only check ECS component files or files that contain IEvent / IComponentData
IS_ECS_PATH=false
IS_EVENT_OR_COMPONENT=false

if echo "$FILE_PATH" | grep -qE "/Ecs/"; then
    IS_ECS_PATH=true
fi

if grep -qE "(IEvent|IComponentData)" "$FILE_PATH" 2>/dev/null; then
    IS_EVENT_OR_COMPONENT=true
fi

if ! $IS_ECS_PATH && ! $IS_EVENT_OR_COMPONENT; then
    exit 0
fi

# Strip single-line comments before analysis
STRIPPED=$(sed 's|//.*||g' "$FILE_PATH" 2>/dev/null)

# Find enums that do NOT have a byte base type
# Pattern: "enum SomeName" or "enum SomeName : int/uint/short/ushort/long/ulong" but NOT ": byte"
ISSUES=""

while IFS= read -r line; do
    LINE_NUM=$(echo "$line" | cut -d: -f1)
    LINE_CONTENT=$(echo "$line" | cut -d: -f2-)

    # Skip if already has byte base
    if echo "$LINE_CONTENT" | grep -qE "enum\s+\w+\s*:\s*byte"; then
        continue
    fi

    ENUM_NAME=$(echo "$LINE_CONTENT" | grep -oE "enum\s+\w+" | grep -oE "\w+$")
    ISSUES="${ISSUES}\n  Line ${LINE_NUM}: enum ${ENUM_NAME} — missing ': byte'"
done < <(grep -n "enum\s\+\w\+" "$FILE_PATH" 2>/dev/null | grep -v "//" | grep "enum\s")

if [ -n "$ISSUES" ]; then
    echo "BLOCKED — enum without byte base in ECS/IEvent context: $FILE_PATH"
    echo ""
    echo "Enums inside IComponentData or IEvent structs must inherit from byte"
    echo "to minimize struct size and improve ECS chunk density."
    echo -e "$ISSUES"
    echo ""
    echo "Fix: enum MyState : byte { Idle, Moving, Attacking }"
    echo "Note: Use ushort if more than 255 values are needed."
    exit 2
fi

exit 0
