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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-no-runtime-instantiate" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns if code uses runtime GameObject creation
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
if echo "$FILE_PATH" | grep -qiE "(EditModeTest|PlayModeTest)/"; then
    exit 0
fi

# Strip comments and string literals to avoid false positives
STRIPPED=$(sed 's|//.*||g; s/"[^"]*"/""/g' "$FILE_PATH" 2>/dev/null | sed ':a;N;$!ba;s|/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/||g')

# --- BLOCKING: new GameObject() ---
# No exceptions — new GameObject() is forbidden everywhere in runtime code.
# Pools, factories, and spawners must also instantiate from prefabs.
NEW_GO=$(echo "$STRIPPED" | grep -nE "\bnew\s+GameObject\s*\(")

if [ -n "$NEW_GO" ]; then
    echo "BLOCKED: new GameObject() is forbidden in runtime code."
    echo ""
    echo "File: $FILE_PATH"
    echo "Lines:"
    echo "$NEW_GO"
    echo ""
    echo "Rule: GameObjects must always come from prefabs."
    echo "  GOOD: Instantiate(prefab, parent, false)"
    echo "  GOOD: Addressables.InstantiateAsync(address)"
    echo "  BAD:  new GameObject(\"name\")"
    exit 2
fi

WARNINGS=""

# Check for Destroy (warning only — Addressables.ReleaseInstance or pool.Return preferred)
DESTROY=$(echo "$STRIPPED" | grep -nE "\bDestroy\s*\(" | grep -v "OnDestroy")
if [ -n "$DESTROY" ]; then
    WARNINGS="${WARNINGS}\nDestroy() found — use pool.Return() / SetActive(false) or Addressables.ReleaseInstance() instead:\n${DESTROY}\n"
fi

if [ -n "$WARNINGS" ]; then
    echo "WARNING: Potentially unsafe GameObject destruction detected."
    echo "File: $FILE_PATH"
    echo -e "$WARNINGS"
    exit 0
fi

exit 0
