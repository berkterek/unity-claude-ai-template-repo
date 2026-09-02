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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-no-linq-hotpath" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns if LINQ is used alongside hot path methods
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

# Check if file uses System.Linq
HAS_LINQ=$(grep -c "using System.Linq" "$FILE_PATH" 2>/dev/null)
if [ "$HAS_LINQ" -eq 0 ]; then
    exit 0
fi

# Strip comments and strings before checking for hot path methods
STRIPPED=$(strip_cs_noise "$FILE_PATH")

# Check if file has hot path methods
HOT_METHODS=$(echo "$STRIPPED" | grep -nE "(void|IEnumerator|UniTask)\s+(Update|FixedUpdate|LateUpdate|Tick|Execute|OnUpdate|Process)\s*\(")
if [ -n "$HOT_METHODS" ]; then
    echo "WARNING: File imports System.Linq AND contains hot path methods!"
    echo "File: $FILE_PATH"
    echo ""
    echo "Hot path methods found:"
    echo "$HOT_METHODS"
    echo ""
    echo "LINQ causes heap allocations. Forbidden on hot paths."
    echo "Use for-loops, pre-allocated collections, or Span<T> instead."
    # Warning only
    exit 0
fi

exit 0
