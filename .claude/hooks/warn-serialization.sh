#!/usr/bin/env bash
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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "warn-serialization" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# ============================================================================
# warn-serialization.sh — WARNING HOOK
# Detects when a [SerializeField] field is renamed without [FormerlySerializedAs].
# This causes silent data loss: every configured value in every scene and prefab
# resets to default. Hours of work lost with no warning from Unity.
# ============================================================================
# Trigger: PostToolUse on Edit|Write
# Exit: 0 always (warning only, via stderr)
# ============================================================================

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check C# files
case "$FILE_PATH" in
    *.cs) ;;
    *) exit 0 ;;
esac

# For Edit tool, check if old_string had a serialized field that was renamed
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')

if [ -z "$OLD_STRING" ] || [ -z "$NEW_STRING" ]; then
    exit 0
fi

# Extract field names from [SerializeField] declarations in old and new content
OLD_FIELDS=$(echo "$OLD_STRING" | grep -oE '\[SerializeField\].*\s+(\w+)\s*[;=]' | grep -oE '\w+\s*[;=]' | sed 's/[;= ]//g' || true)
NEW_FIELDS=$(echo "$NEW_STRING" | grep -oE '\[SerializeField\].*\s+(\w+)\s*[;=]' | grep -oE '\w+\s*[;=]' | sed 's/[;= ]//g' || true)

if [ -z "$OLD_FIELDS" ] || [ -z "$NEW_FIELDS" ]; then
    exit 0
fi

# Check if any old field names disappeared (renamed) without FormerlySerializedAs
for OLD_FIELD in $OLD_FIELDS; do
    if ! echo "$NEW_FIELDS" | grep -qx "$OLD_FIELD"; then
        # Field was renamed — check if FormerlySerializedAs is present
        if ! echo "$NEW_STRING" | grep -q "FormerlySerializedAs.*\"$OLD_FIELD\""; then
            echo "WARNING: Serialized field '$OLD_FIELD' was renamed without [FormerlySerializedAs]." >&2
            echo "" >&2
            echo "  File: $FILE_PATH" >&2
            echo "" >&2
            echo "  This will silently reset the field's value to default in EVERY" >&2
            echo "  scene, prefab, and ScriptableObject that references it." >&2
            echo "" >&2
            echo "  Fix: Add [FormerlySerializedAs(\"$OLD_FIELD\")] above the renamed field:" >&2
            echo "" >&2
            echo "    [FormerlySerializedAs(\"$OLD_FIELD\")]" >&2
            echo "    [SerializeField] private Type newFieldName;" >&2
            echo "" >&2
        fi
    fi
done

exit 0
