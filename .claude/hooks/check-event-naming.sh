#!/bin/bash
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
