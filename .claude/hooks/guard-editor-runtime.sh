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

# Judge the EFFECTIVE post-edit content, never the Edit fragment alone.
#
# An `Edit`'s `new_string` is a *slice* of the file. The `#if UNITY_EDITOR` guard that makes
# the `using UnityEditor;` legal lives at the top of the file and is almost never inside the
# slice — so judging the fragment blocked every edit to a correctly-guarded runtime file,
# including edits that touched nothing near the guard. That is the inverse of the six
# PreToolUse hooks CLAUDE.md already documents (which read stale disk and could never accept
# a fix); this one read a fragment with no context and could never accept a file that was
# already correct. Same remedy either way: reconstruct what the file will look like after the
# pending write, and check that.
#
# The `Write` branch stays first and is never gated on the file existing — at PreToolUse a
# newly created file is by definition not on disk, and an `[ -f "$FILE_PATH" ]` guard placed
# above this case makes the whole Write branch unreachable dead code (the 2026-09-02 finding).
EFFECTIVE_FILE=$(mktemp /tmp/unity_hook_XXXXXX.cs)
OLD_STRING_FILE=""
NEW_STRING_FILE=""
trap 'rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"' EXIT

# Branch on the PAYLOAD's shape, not on `tool_name`: a `content` key means a full-file write,
# an `old_string` key means a slice of an existing file. Keying on `tool_name` would make the
# hook silently inert for any caller that omits it — including this repo's own bats fixtures,
# which is how that mistake gets shipped green.
if echo "$INPUT" | jq -e '.tool_input | has("content")' >/dev/null 2>&1; then
    # Write — the payload IS the whole post-write file. Never gated on the file existing:
    # at PreToolUse a newly created file is by definition not on disk, and an
    # `[ -f "$FILE_PATH" ]` guard above this branch makes it unreachable dead code
    # (the 2026-09-02 finding).
    echo "$INPUT" | jq -j '.tool_input.content // empty' > "$EFFECTIVE_FILE"
elif [ -f "$FILE_PATH" ] && echo "$INPUT" | jq -e '.tool_input | has("old_string")' >/dev/null 2>&1; then
    cp "$FILE_PATH" "$EFFECTIVE_FILE"
    OLD_STRING_FILE=$(mktemp)
    NEW_STRING_FILE=$(mktemp)
    echo "$INPUT" | jq -j '.tool_input.old_string // empty' > "$OLD_STRING_FILE"
    echo "$INPUT" | jq -j '.tool_input.new_string // empty' > "$NEW_STRING_FILE"
    REPLACE_ALL=$(echo "$INPUT" | jq -r '.tool_input.replace_all // false')
    if [ -s "$OLD_STRING_FILE" ]; then
        python3 - "$EFFECTIVE_FILE" "$OLD_STRING_FILE" "$NEW_STRING_FILE" "$REPLACE_ALL" <<'PYEOF' 2>/dev/null || true
import sys
target_path, old_path, new_path, replace_all = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"
with open(target_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    content = f.read()
with open(old_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    old = f.read()
with open(new_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    new = f.read()
content = content.replace(old, new) if replace_all else content.replace(old, new, 1)
with open(target_path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(content)
PYEOF
    fi
else
    # No full content, and no on-disk file to splice into: the fragment is all there is.
    # Judge it rather than exiting 0 — a fragment introducing an unguarded `using UnityEditor;`
    # into a file that does not yet exist is still worth blocking.
    echo "$INPUT" | jq -j '.tool_input.new_string // .tool_input.content // empty' > "$EFFECTIVE_FILE"
fi

# Skip if no content to check
if [ ! -s "$EFFECTIVE_FILE" ]; then
    exit 0
fi

EFFECTIVE_CONTENT=$(cat "$EFFECTIVE_FILE")

# Strip comments and strings to avoid false positives on commented-out code
STRIPPED_CONTENT=$(strip_cs_noise "$EFFECTIVE_FILE")

# Check if the effective content uses UnityEditor namespace
if echo "$STRIPPED_CONTENT" | grep -qE '(using\s+UnityEditor|UnityEditor\.)'; then
    # Check if it's properly guarded with #if UNITY_EDITOR (check original, not stripped)
    if ! echo "$EFFECTIVE_CONTENT" | grep -qE '#if\s+UNITY_EDITOR'; then
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
