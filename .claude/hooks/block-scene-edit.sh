#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "block-scene-edit" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
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
        echo "BLOCKED: Direct editing of scene/prefab files corrupts serialized references." >&2
        echo "" >&2
        echo "  File: $FILE_PATH" >&2
        echo "" >&2
        echo "  Instead, use unity-mcp tools:" >&2
        echo "    - manage_scene      → create/load/modify scenes" >&2
        echo "    - manage_gameobject  → create/modify GameObjects" >&2
        echo "    - manage_components  → add/configure components" >&2
        echo "    - manage_prefabs     → create/edit prefabs" >&2
        echo "    - batch_execute      → bundle multiple operations" >&2
        exit 2
        ;;
    *.asset)
        # Allow .asset files in Scripts/ or code-generated paths, block others
        case "$FILE_PATH" in
            */Scripts/*|*/Editor/*|*/Plugins/*)
                exit 0
                ;;
            *)
                echo "BLOCKED: Direct editing of .asset files can corrupt serialized data." >&2
                echo "" >&2
                echo "  File: $FILE_PATH" >&2
                echo "" >&2
                echo "  Instead, use unity-mcp tools:" >&2
                echo "    - manage_asset              → manage assets" >&2
                echo "    - manage_scriptable_object   → edit ScriptableObjects" >&2
                echo "    - manage_material            → edit materials" >&2
                exit 2
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
