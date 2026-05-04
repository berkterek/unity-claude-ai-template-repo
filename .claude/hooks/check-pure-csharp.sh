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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-pure-csharp" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 5000 ]; then tail -n 5000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Validates that service/domain C# files don't import UnityEngine
# Checks: _Framework/, Games/Abstracts/, Games/Concretes/ (excluding providers)
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Check domain/service directories
if echo "$FILE_PATH" | grep -qiE "(_Framework|Games/Abstracts|Games/Concretes)/.*\.cs$"; then
    # Skip providers, MonoBehaviours, views, editors — Unity API lives here
    if echo "$FILE_PATH" | grep -qiE "(Provider|View|Root|Mono|Behaviour|Inspector|Editor|Drawer|Concretes/(Audio|Store|Pool|UI|Infrastructure))/"; then
        exit 0
    fi

    if [ -f "$FILE_PATH" ]; then
        UNITY_IMPORTS=$(grep -n "using UnityEngine" "$FILE_PATH" 2>/dev/null)
        if [ -n "$UNITY_IMPORTS" ]; then
            echo "BLOCKED: Domain/service file contains UnityEngine imports!"
            echo "File: $FILE_PATH"
            echo ""
            echo "Violations:"
            echo "$UNITY_IMPORTS"
            echo ""
            echo "Services and abstractions must be pure C#."
            echo "Move Unity-specific code to a Provider class in Concretes/<Module>/."
            exit 2
        fi
    fi
fi

exit 0
