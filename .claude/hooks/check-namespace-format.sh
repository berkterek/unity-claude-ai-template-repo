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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-namespace-format" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 5000 ]; then tail -n 5000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns if C# namespace doesn't follow Layer.Module format
# Expected: Framework.Events, Game.Abstracts, Game.Concretes, Game.Ecs, etc.
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [[ "$FILE_PATH" != *.cs ]]; then
    exit 0
fi

# Only check files inside _Framework or _GameFolders
if ! echo "$FILE_PATH" | grep -qE "(_Framework|_GameFolders)/Scripts/"; then
    exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Extract declared namespace
NAMESPACE=$(grep -m1 "^namespace " "$FILE_PATH" 2>/dev/null | sed 's/namespace //' | tr -d '{' | tr -d ' ')

if [ -z "$NAMESPACE" ]; then
    echo "WARNING: No namespace declared in $FILE_PATH"
    echo "Expected format: Framework.<Module> or Game.<Layer> or Game.<Layer>.<Module>"
    exit 0
fi

# Validate format: must start with Framework. or Game.
if ! echo "$NAMESPACE" | grep -qE "^(Framework|Game)(\.[A-Z][a-zA-Z]*)*$"; then
    echo "WARNING: Namespace '$NAMESPACE' doesn't follow Layer.Module convention."
    echo "File: $FILE_PATH"
    echo "Expected examples: Framework.Events, Game.Abstracts, Game.Concretes, Game.Ecs, Game.Abstracts.Controllers"
fi

exit 0
