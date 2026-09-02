#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"   # minimal | standard | strict
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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "block-scene-edit" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# ============================================================================
# block-scene-edit.sh — BLOCKING HOOK
# Prevents Claude from directly editing .unity, .prefab, and .asset YAML files.
# These files contain serialized references that break when text-edited.
# Use unity-mcp tools (manage_scene, manage_gameobject, manage_prefabs) instead.
# ============================================================================
# Trigger: PreToolUse on Edit|Write
# Exit: 2 = block, 0 = allow
# ============================================================================

set -euo pipefail

# Read the tool input from stdin (JSON with tool_name, file_path, etc.)
INPUT=$(cat)

# Extract the file path from the tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Check if the file has a Unity binary/YAML extension
case "$FILE_PATH" in
    *.unity|*.prefab)
        MSG="BLOCKED: Direct editing of scene/prefab files corrupts serialized references."$'\n'
        MSG+="  File: $FILE_PATH"$'\n'
        MSG+="  Instead, use unity-mcp tools: manage_scene, manage_gameobject, manage_prefabs"
        unity_hook_block "$MSG"
        ;;
    *.asset)
        # Allow .asset files in Scripts/ or code-generated paths, block others
        case "$FILE_PATH" in
            */Scripts/*|*/Editor/*|*/Plugins/*)
                exit 0
                ;;
            *)
                MSG="BLOCKED: Direct editing of .asset files can corrupt serialized data."$'\n'
                MSG+="  File: $FILE_PATH"$'\n'
                MSG+="  Instead, use unity-mcp tools: manage_asset, manage_scriptable_object"
                unity_hook_block "$MSG"
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
