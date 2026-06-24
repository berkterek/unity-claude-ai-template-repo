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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-getcomponent-in-awake" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns when GetComponent/GetComponentInChildren is used in Awake.
# Components on the same GO or its children should be assigned via [SerializeField]
# in the Inspector — zero runtime cost, dependency visible at edit time.
#
# Exception: GetComponent is acceptable in Awake when the component is added
# dynamically at runtime (not present at edit time).

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

# Strip single-line comments and string literals
STRIPPED=$(sed 's|//.*||g; s/"[^"]*"/""/g' "$FILE_PATH" 2>/dev/null)

# Find Awake method body (line number of declaration)
AWAKE_LINE=$(echo "$STRIPPED" | grep -nE "(void|async)\s+Awake\s*\(" | head -1 | cut -d: -f1)

if [ -z "$AWAKE_LINE" ]; then
    exit 0
fi

# Scan up to 60 lines from Awake declaration
END_LINE=$((AWAKE_LINE + 60))
AWAKE_BODY=$(echo "$STRIPPED" | sed -n "${AWAKE_LINE},${END_LINE}p")

WARNINGS=""

# GetComponent<T>() or GetComponent(typeof(T))
if echo "$AWAKE_BODY" | grep -qE "\bGetComponent\s*[<(]"; then
    HITS=$(echo "$STRIPPED" | grep -nE "\bGetComponent\s*[<(]" | awk -F: -v start="$AWAKE_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
    WARNINGS="${WARNINGS}\n  GetComponent — use [SerializeField] and assign in Inspector:\n$(echo "$HITS" | sed 's/^/    Line /')"
fi

# GetComponentInChildren<T>()
if echo "$AWAKE_BODY" | grep -qE "\bGetComponentInChildren\s*[<(]"; then
    HITS=$(echo "$STRIPPED" | grep -nE "\bGetComponentInChildren\s*[<(]" | awk -F: -v start="$AWAKE_LINE" -v end="$END_LINE" '$1>=start && $1<=end {print}')
    WARNINGS="${WARNINGS}\n  GetComponentInChildren — use [SerializeField] and assign in Inspector:\n$(echo "$HITS" | sed 's/^/    Line /')"
fi

if [ -n "$WARNINGS" ]; then
    echo "WARNING: GetComponent called in Awake — prefer [SerializeField] Inspector assignment."
    echo "File: $FILE_PATH"
    echo ""
    printf "%b\n" "$WARNINGS"
    echo ""
    echo "Components on the same GameObject or its children should be wired in the Editor:"
    echo "  [SerializeField] private Rigidbody _rigidbody;"
    echo "  [SerializeField] private Animator  _animator;"
    echo ""
    echo "This moves the cost to edit time (zero runtime overhead) and makes"
    echo "dependencies visible without opening the script."
    echo ""
    echo "GetComponent in Awake is only acceptable when the component is added"
    echo "dynamically at runtime and cannot be known at edit time."
fi

exit 0
