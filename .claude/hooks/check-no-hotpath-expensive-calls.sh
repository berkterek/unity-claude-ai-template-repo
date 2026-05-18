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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-no-hotpath-expensive-calls" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns if expensive Unity calls are used inside hot path methods
# Expensive: GetComponent, Camera.main, FindObjectOfType, FindObjectsOfType,
#            bare transform property, tag == "...", SendMessage
# Hot paths: Update, FixedUpdate, LateUpdate, Tick, FixedTick, LateTick,
#            Execute, OnUpdate, Process

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

# Strip single-line comments and string literals before analysis
STRIPPED=$(sed 's|//.*||g; s/"[^"]*"/""/g' "$FILE_PATH" 2>/dev/null)

# Find hot path method bodies (line numbers of method declarations)
HOT_METHOD_LINES=$(echo "$STRIPPED" | grep -nE "(void|IEnumerator|UniTask)\s+(Update|FixedUpdate|LateUpdate|Tick|FixedTick|LateTick|Execute|OnUpdate|Process)\s*\(" | cut -d: -f1)

if [ -z "$HOT_METHOD_LINES" ]; then
    exit 0
fi

# Check if file has a cached _transform field declared at class level
HAS_CACHED_TRANSFORM=$(grep -cE "private\s+(readonly\s+)?Transform\s+_transform\b" "$FILE_PATH" 2>/dev/null)

WARNINGS=""

for METHOD_LINE in $HOT_METHOD_LINES; do
    # Extract method name for reporting
    METHOD_NAME=$(echo "$STRIPPED" | sed -n "${METHOD_LINE}p" | grep -oE "(Update|FixedUpdate|LateUpdate|Tick|FixedTick|LateTick|Execute|OnUpdate|Process)")

    # Scan ~50 lines from method declaration (reasonable method body window)
    END_LINE=$((METHOD_LINE + 50))
    BODY=$(echo "$STRIPPED" | sed -n "${METHOD_LINE},${END_LINE}p")

    # Check for each expensive call pattern
    if echo "$BODY" | grep -qE "GetComponent\s*[<(]"; then
        HITS=$(echo "$STRIPPED" | grep -nE "GetComponent\s*[<(]" | awk -F: -v start="$METHOD_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
        WARNINGS="${WARNINGS}\n  [${METHOD_NAME}] GetComponent<T>() — cache in Awake instead:\n$(echo "$HITS" | sed 's/^/    Line /')"
    fi

    if echo "$BODY" | grep -qE "Camera\.main"; then
        HITS=$(echo "$STRIPPED" | grep -n "Camera\.main" | awk -F: -v start="$METHOD_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
        WARNINGS="${WARNINGS}\n  [${METHOD_NAME}] Camera.main — calls FindObjectOfType internally; cache in Awake:\n$(echo "$HITS" | sed 's/^/    Line /')"
    fi

    if echo "$BODY" | grep -qE "FindObjectOfType|FindObjectsOfType|FindFirstObjectByType|FindAnyObjectByType"; then
        HITS=$(echo "$STRIPPED" | grep -n "FindObjectOfType\|FindObjectsOfType\|FindFirstObjectByType\|FindAnyObjectByType" | awk -F: -v start="$METHOD_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
        WARNINGS="${WARNINGS}\n  [${METHOD_NAME}] FindObjectOfType — O(n) scene scan; use VContainer injection or cache:\n$(echo "$HITS" | sed 's/^/    Line /')"
    fi

    if echo "$BODY" | grep -qE 'tag\s*==\s*"'; then
        HITS=$(echo "$STRIPPED" | grep -n 'tag\s*==\s*"' | awk -F: -v start="$METHOD_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
        WARNINGS="${WARNINGS}\n  [${METHOD_NAME}] tag == \"...\" — allocates string; use CompareTag(\"...\") instead:\n$(echo "$HITS" | sed 's/^/    Line /')"
    fi

    if echo "$BODY" | grep -qE "SendMessage\s*\(|BroadcastMessage\s*\("; then
        HITS=$(echo "$STRIPPED" | grep -nE "SendMessage\s*\(|BroadcastMessage\s*\(" | awk -F: -v start="$METHOD_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
        WARNINGS="${WARNINGS}\n  [${METHOD_NAME}] SendMessage/BroadcastMessage — slow reflection; use IEventBus or direct reference:\n$(echo "$HITS" | sed 's/^/    Line /')"
    fi

    # Bare transform property access: matches "transform." but not "_transform."
    # Allow if class already has a cached _transform field
    if [ "$HAS_CACHED_TRANSFORM" -eq 0 ]; then
        if echo "$BODY" | grep -qE "(^|[^_a-zA-Z0-9])transform\."; then
            HITS=$(echo "$STRIPPED" | grep -n -E "(^|[^_a-zA-Z0-9])transform\." | awk -F: -v start="$METHOD_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
            if [ -n "$HITS" ]; then
                WARNINGS="${WARNINGS}\n  [${METHOD_NAME}] Bare transform property — add a serialized field and assign in Inspector:\n    [SerializeField] private Transform _transform;\n  Then use _transform in hot paths:\n$(echo "$HITS" | sed 's/^/    Line /')"
            fi
        fi
    fi
done

if [ -n "$WARNINGS" ]; then
    echo "WARNING: Expensive Unity calls detected inside hot path methods!"
    echo "File: $FILE_PATH"
    echo ""
    printf "%b\n" "$WARNINGS"
    echo ""
    echo "These calls cause GC allocations or O(n) scene scans every frame."
    echo "Cache results in Awake() or inject via VContainer."
fi

exit 0
