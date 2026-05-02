#!/bin/bash
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
    echo "BLOCKED: Singleton pattern detected in: $FILE_PATH"
    echo ""
    echo "Violations:"
    echo -e "$ISSUES"
    echo ""
    echo "Use VContainer instead:"
    echo "  App-wide services → register in AppScope (Lifetime.Singleton)"
    echo "  Scene-local       → register in MenuScope / GameScope"
    echo ""
    echo "Exception: ECS<->Mono static bridges must extend EventBusAccessor pattern."
    echo "See .claude/rules/architecture.md for EventBusAccessor usage."
    exit 2
fi

exit 0
