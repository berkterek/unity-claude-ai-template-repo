#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-ecs-structural-changes" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns if EntityManager is used for structural changes inside a query loop
# Structural changes (AddComponent, RemoveComponent, DestroyEntity, Instantiate)
# must use EntityCommandBuffer, not EntityManager directly.
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [[ "$FILE_PATH" != *.cs ]]; then
    exit 0
fi

# Skip if ECS feature is disabled in project-features.json
_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -n "$_CWD" ] && [ -f "$_CWD/.claude/project-features.json" ]; then
    _ECS=$(jq -r '.ecs // "true"' "$_CWD/.claude/project-features.json" 2>/dev/null)
    if [ "$_ECS" = "false" ]; then exit 0; fi
fi

# Only check ECS system files
if ! echo "$FILE_PATH" | grep -qE "Games/Ecs/Systems/"; then
    exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Check for direct EntityManager structural change calls
VIOLATIONS=$(grep -n "EntityManager\.\(AddComponent\|RemoveComponent\|DestroyEntity\|CreateEntity\|Instantiate\)" "$FILE_PATH" 2>/dev/null | grep -v "//")

if [ -n "$VIOLATIONS" ]; then
    echo "WARNING: Direct EntityManager structural change detected in ECS system."
    echo "File: $FILE_PATH"
    echo ""
    echo "Violations (use EntityCommandBuffer instead):"
    echo "$VIOLATIONS"
    echo ""
    echo "Structural changes during query iteration must go through EntityCommandBuffer."
    echo "Exception: SetComponentData and direct data writes are fine without ECB."
fi

exit 0
