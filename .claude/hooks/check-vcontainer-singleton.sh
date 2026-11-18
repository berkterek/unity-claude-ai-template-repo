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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-vcontainer-singleton" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks static singleton patterns outside of approved accessors
# Approved exceptions: EventBusAccessor (static bridge for ECS <-> Mono communication),
# DebugCommandRegistryAccessor (dev-only bridge for the framework's Editor command runner)
# VContainer is the only DI mechanism — static Instance fields are forbidden
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if ! grep -qE "\.cs$" <<< "$FILE_PATH"; then
    exit 0
fi

# Skip test files and editor files
if grep -qiE "(Tests?|Spec|/Editor/)" <<< "$FILE_PATH"; then
    exit 0
fi

# Skip the approved accessor files
FILENAME=$(basename "$FILE_PATH" .cs)
if grep -qiE "^(EventBusAccessor|ServiceAccessor|DebugCommandRegistryAccessor)$" <<< "$FILENAME"; then
    exit 0
fi

# Skip ECS systems — they use SystemAPI, not singletons
if grep -qiE "Games/Ecs/Systems/" <<< "$FILE_PATH"; then
    exit 0
fi

# Judge the EFFECTIVE post-edit content (docs/incidents/pretooluse-effective-content.md).
# This hook runs as PreToolUse too; reading disk there meant a Write that removes a singleton
# was blocked by the singleton it removes, and a new file was never checked at all.
# Payload shape decides, not tool_name: `content` = whole file, `old_string` = slice of disk.
# No suffix after the X's — BSD/macOS mktemp would not randomize them (see guard-editor-runtime.sh).
EFFECTIVE_FILE=$(mktemp "${TMPDIR:-/tmp}/unity_hook_XXXXXX")
OLD_STRING_FILE=""
NEW_STRING_FILE=""
trap 'rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; _hook_log $?' EXIT

if echo "$INPUT" | jq -e '.tool_input | has("content")' >/dev/null 2>&1; then
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
elif [ -f "$FILE_PATH" ]; then
    # No content in the payload (bare file_path) — disk is all there is.
    cp "$FILE_PATH" "$EFFECTIVE_FILE"
fi

if [ ! -s "$EFFECTIVE_FILE" ]; then
    exit 0
fi

ISSUES=""

# Strip single-line comments
STRIPPED=$(sed 's|//.*||g' "$EFFECTIVE_FILE" 2>/dev/null)

# Pattern 1: a static Instance / _instance DECLARATION of any access — field (`;`, `=`) or property
# (`{`, `=>`). `[^(=]*` before the name keeps out a method or expression that merely calls a
# library's `.Instance` (the name would sit after the method's `(` or after an `=>`).
STATIC_INSTANCE=$(echo "$STRIPPED" | grep -nE "\bstatic[[:space:]]+[^(=]*\b(Instance|_instance)\b[[:space:]]*(;|=|\{)")
if [ -n "$STATIC_INSTANCE" ]; then
    ISSUES="${ISSUES}\n${STATIC_INSTANCE}"
fi

# Pattern 2: public static T Instance { get; } property
STATIC_PROP=$(echo "$STRIPPED" | grep -n "public\s\+static\s\+.*\bInstance\b\s*{")
if [ -n "$STATIC_PROP" ]; then
    ISSUES="${ISSUES}\n${STATIC_PROP}"
fi

# Pattern 3: DontDestroyOnLoad called on 'this' (classic singleton setup)
DONT_DESTROY=$(echo "$STRIPPED" | grep -n "DontDestroyOnLoad\s*(this)")
if [ -n "$DONT_DESTROY" ]; then
    ISSUES="${ISSUES}\n${DONT_DESTROY}"
fi

if [ -n "$ISSUES" ]; then
    MSG="Singleton pattern detected in: $FILE_PATH"$'\n'
    MSG+="Violations:"$'\n'"$(echo -e "$ISSUES")"$'\n'
    MSG+="Use VContainer instead (AppScope for app-wide, GameScope for scene-local)."
    unity_hook_block "$MSG"
fi

exit 0
