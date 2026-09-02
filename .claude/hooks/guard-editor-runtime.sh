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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "guard-editor-runtime" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# ============================================================================
# guard-editor-runtime.sh — BLOCKING HOOK
# Blocks usage of UnityEditor namespace in runtime code without #if guard.
# Code using UnityEditor compiles in the Editor but fails on player build.
# This silently passes until someone tries to build, then hours of debugging.
# ============================================================================
# Trigger: PreToolUse on Edit|Write
# Exit: 2 = block, 0 = allow
# ============================================================================

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')

# Only check C# files
case "$FILE_PATH" in
    *.cs) ;;
    *) exit 0 ;;
esac

# Skip files already in Editor folders — editor code is fine there.
# Both spellings are recognised: Unity's own special-folder name is the singular
# `Editor/`, but this project's documented layout uses the plural `Editors/`
# (rules/architecture.md → "Scripts/ Folder Rules" and the _Framework table:
# `Scripts/Editors/`, `_Framework/Editors/`, both compiled by an .asmdef with
# includePlatforms: ["Editor"]). Matching only the singular made the hook refuse
# the project's own Editor folder — it blocked a file under Scripts/Editors/ that
# could not reach a player build, and _Framework/Editors/ had been sitting on the
# wrong side of the same gap since the hook was written.
case "$FILE_PATH" in
    */Editor/*|*/editor/*|*/Editors/*|*/editors/*) exit 0 ;;
esac

# Skip if no content to check
if [ -z "$NEW_CONTENT" ]; then
    exit 0
fi

# Strip comments and strings to avoid false positives on commented-out code
_guard_tmp=$(mktemp /tmp/unity_hook_XXXXXX.cs)
trap "rm -f '$_guard_tmp'" EXIT
printf '%s' "$NEW_CONTENT" > "$_guard_tmp"
STRIPPED_CONTENT=$(strip_cs_noise "$_guard_tmp")

# Check if the new content uses UnityEditor namespace
if echo "$STRIPPED_CONTENT" | grep -qE '(using\s+UnityEditor|UnityEditor\.)'; then
    # Check if it's properly guarded with #if UNITY_EDITOR (check original, not stripped)
    if ! echo "$NEW_CONTENT" | grep -qE '#if\s+UNITY_EDITOR'; then
        echo "BLOCKED: UnityEditor namespace used in runtime code without #if UNITY_EDITOR guard." >&2
        echo "" >&2
        echo "  File: $FILE_PATH" >&2
        echo "" >&2
        echo "  This code compiles in the Editor but FAILS on player build." >&2
        echo "  Either:" >&2
        echo "    1. Move this file to an Editor/ folder, or" >&2
        echo "    2. Wrap the editor code with:" >&2
        echo "       #if UNITY_EDITOR" >&2
        echo "       using UnityEditor;" >&2
        echo "       #endif" >&2
        exit 2
    fi
fi

exit 0
