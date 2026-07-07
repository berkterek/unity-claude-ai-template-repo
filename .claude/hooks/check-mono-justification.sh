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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-mono-justification" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns when a MonoBehaviour class has no [SerializeField] AND no Unity callbacks
#        (Card 0 — unjustified MonoBehaviour). Also warns when a MonoBehaviour shell
#        exceeds 150 lines (oversized shell should extract logic to a Handler).
# Scope: _GameFolders/Scripts/Games/ .cs files — tests and Editor files are exempt.
# Exit 0 (warning only — does not block).
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if ! echo "$FILE_PATH" | grep -qE "\.cs$"; then
    exit 0
fi

# Limit scope to _GameFolders/Scripts/Games/
if ! echo "$FILE_PATH" | grep -qE "_GameFolders/Scripts/Games/"; then
    exit 0
fi

# Skip Editor / third-party / test paths
should_skip_path "$FILE_PATH" && exit 0

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Must inherit from MonoBehaviour (directly or with extra interfaces)
if ! grep -qE "class\s+\w+\s*:\s*(MonoBehaviour|UnityEngine\.MonoBehaviour)" "$FILE_PATH" 2>/dev/null; then
    exit 0
fi

# Strip comments for accurate analysis
STRIPPED=$(strip_cs_noise "$FILE_PATH")

# --- Check 1: Unjustified MonoBehaviour (Card 0) ---
HAS_SERIALIZE_FIELD=$(echo "$STRIPPED" | grep -cE "\[SerializeField\]" 2>/dev/null || true)
HAS_UNITY_CALLBACKS=$(echo "$STRIPPED" | grep -cE "\b(Awake|Start|OnEnable|OnDisable|OnDestroy|Update|FixedUpdate|LateUpdate|OnTriggerEnter|OnTriggerExit|OnCollisionEnter|OnCollisionExit)\s*\(" 2>/dev/null || true)

if [ "${HAS_SERIALIZE_FIELD:-0}" -eq 0 ] && [ "${HAS_UNITY_CALLBACKS:-0}" -eq 0 ]; then
    unity_hook_warn "Warning: MonoBehaviour with no [SerializeField] fields and no Unity callbacks.
File: $FILE_PATH

This class may not need to be a MonoBehaviour (solid-oop.md Card 0).
If you need a frame tick, use ITickable instead. If you need no Unity lifecycle, make it pure C#."
fi

# --- Check 2: Oversized MonoBehaviour shell (> 150 lines) ---
LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null || echo 0)
if [ "${LINE_COUNT:-0}" -gt 150 ]; then
    unity_hook_warn "Warning: MonoBehaviour shell exceeds 150 lines ($LINE_COUNT lines).
File: $FILE_PATH

Controller/View shells target ≤ ~80 lines. Consider extracting logic to a Handler.
Rule: solid-oop.md → Controller Shell limits."
fi

exit 0
