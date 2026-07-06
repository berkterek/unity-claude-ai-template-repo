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

# Skip Editor / third-party / test paths
should_skip_path "$FILE_PATH" && exit 0

# Strip comments and string literals to avoid false positives
STRIPPED=$(strip_cs_noise "$FILE_PATH")

# --- BLOCKING: new GameObject() ---
# No exceptions — new GameObject() is forbidden everywhere in runtime code.
# Pools, factories, and spawners must also instantiate from prefabs.
NEW_GO=$(echo "$STRIPPED" | grep -nE "\bnew[[:space:]]+GameObject[[:space:]]*\(")

if [ -n "$NEW_GO" ]; then
    unity_hook_block "new GameObject() is forbidden in runtime code.
File: $FILE_PATH
Lines:
$NEW_GO

Rule: GameObjects must always come from prefabs.
  GOOD: Instantiate(prefab, parent, false)
  GOOD: Addressables.InstantiateAsync(address)
  BAD:  new GameObject(\"name\")"
fi

WARNINGS=""

# Check for Destroy (warning only — Addressables.ReleaseInstance or pool.Return preferred)
# Check for Destroy — allowed in Pool/Manager/Spawner files, warning elsewhere
if ! echo "$FILE_PATH" | grep -qiE "(Pool|Manager|Spawner)\.cs$"; then
    DESTROY=$(echo "$STRIPPED" | grep -nE "\bDestroy[[:space:]]*\(" | grep -v "OnDestroy")
    if [ -n "$DESTROY" ]; then
        WARNINGS="${WARNINGS}\nDestroy() found — if this object is pool-managed, call pool.Return() instead:\n${DESTROY}\n"
    fi
fi

if [ -n "$WARNINGS" ]; then
    echo "WARNING: Potentially unsafe GameObject destruction detected." >&2
    echo "File: $FILE_PATH" >&2
    echo -e "$WARNINGS" >&2
    exit 0
fi

exit 0
