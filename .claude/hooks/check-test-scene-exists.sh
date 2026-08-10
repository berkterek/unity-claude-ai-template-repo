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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-test-scene-exists" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---

# Hook: Warns if a PlayMode test file references a scene not found in _Scenes/TestScenes/
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Skip if testing feature is disabled in project-features.json
_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -n "$_CWD" ] && [ -f "$_CWD/.claude/project-features.json" ]; then
    # NOT `.testing // "true"` — jq's // falls through on `false` as well as null, so an
    # explicit "testing": false would read back as "true" and the flag could never disable
    # this hook. Only a MISSING key may default to enabled.
    _TESTING=$(jq -r '.testing | if . == null then "true" else tostring end' "$_CWD/.claude/project-features.json" 2>/dev/null)
    if [ "$_TESTING" = "false" ]; then exit 0; fi
fi

# Only check PlayMode test files
if ! echo "$FILE_PATH" | grep -qiE "PlayModeTest/.*\.cs$"; then
    exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
    CWD="$(pwd)"
fi

FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null)
if [ -z "$FILE_CONTENT" ]; then
    exit 0
fi

# Extract scene path strings from the file (const string or LoadSceneAsync calls)
SCENE_REFS=$(echo "$FILE_CONTENT" | grep -oE '"TestScenes/[^"]*"' | tr -d '"')

if [ -z "$SCENE_REFS" ]; then
    exit 0
fi

MISSING=()
while IFS= read -r scene_ref; do
    SCENE_NAME=$(basename "$scene_ref" .unity)
    # Search for the scene file
    FOUND=$(find "$CWD" -path "*/_Scenes/TestScenes/${SCENE_NAME}.unity" -type f 2>/dev/null | head -1)
    if [ -z "$FOUND" ]; then
        MISSING+=("$scene_ref")
    fi
done <<< "$SCENE_REFS"

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "WARNING: PlayMode test references scene(s) not found in _Scenes/TestScenes/:"
    for s in "${MISSING[@]}"; do
        echo "  Missing: ${s}.unity"
    done
    echo ""
    echo "Run /create-test <feature> to create the scene and TestBootstrap prefab."
    echo "Or create the scene manually and add it to Build Settings."
fi

exit 0
