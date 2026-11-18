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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-debug-commands" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# ============================================================================
# check-debug-commands.sh — BLOCKING HOOK
# A cheat sets up a test; it is never the evidence for one (rules/debug-commands.md).
#   *DebugCommands.cs: no IEventBus.Publish, no FindFirstObjectByType / FindObjectOfType,
#   no <scope>.Container.Resolve, and the file must sit under the dev-only #if.
#   Any .cs: DebugCommandRegistryAccessor only inside packages/framework/ and
#   DebugCommandsModule.cs — game code injects IDebugCommandRegistry.
# ============================================================================
# Trigger: PreToolUse on Edit|Write
# Exit: 2 = block, 0 = allow
# ============================================================================

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
    *.cs) ;;
    *) exit 0 ;;
esac

FILENAME=$(basename "$FILE_PATH")
IS_COMMANDS=0
case "$FILENAME" in
    *DebugCommands.cs) IS_COMMANDS=1 ;;
esac

ACCESSOR_ALLOWED=0
case "$FILE_PATH" in
    */packages/framework/*) ACCESSOR_ALLOWED=1 ;;
esac
[ "$FILENAME" = "DebugCommandsModule.cs" ] && ACCESSOR_ALLOWED=1

if [ "$IS_COMMANDS" -eq 0 ] && [ "$ACCESSOR_ALLOWED" -eq 1 ]; then
    exit 0
fi

# Judge the EFFECTIVE post-edit content (docs/incidents/pretooluse-effective-content.md).
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
else
    # No full content and no file to splice into: judge the fragment.
    echo "$INPUT" | jq -j '.tool_input.new_string // empty' > "$EFFECTIVE_FILE"
fi

if [ ! -s "$EFFECTIVE_FILE" ]; then
    exit 0
fi

STRIPPED=$(strip_cs_noise "$EFFECTIVE_FILE")
ISSUES=""

add_issue() {
    ISSUES="${ISSUES}"$'\n'"  - $1"
}

if [ "$IS_COMMANDS" -eq 1 ]; then
    grep -qE '\.Publish[[:space:]]*(<[^>]*>)?[[:space:]]*\(' <<< "$STRIPPED" && \
        add_issue "IEventBus.Publish — a cheat calls the real service method that publishes; it never announces an outcome itself"
    grep -qE '\bFind(FirstObjectByType|AnyObjectByType|ObjectOfType|ObjectsOfType|ObjectsByType)\b' <<< "$STRIPPED" && \
        add_issue "Find*ObjectOfType/ByType — inject the service into the container's constructor instead"
    grep -qE '\.Container\.Resolve\b' <<< "$STRIPPED" && \
        add_issue "<scope>.Container.Resolve — inject the service into the container's constructor instead"
    # The WHOLE file: the first code line is the guard and the last is #endif. A guard around one
    # method leaves the class (and its using of the dev-only assembly) in release builds.
    CODE_LINES=$(grep -vE '^[[:space:]]*$' <<< "$STRIPPED" || true)
    FIRST_LINE=$(head -n 1 <<< "$CODE_LINES")
    LAST_LINE=$(tail -n 1 <<< "$CODE_LINES")
    { grep -qE '^[[:space:]]*#if[[:space:]]+\(?[[:space:]]*(UNITY_EDITOR[[:space:]]*\|\|[[:space:]]*DEVELOPMENT_BUILD|DEVELOPMENT_BUILD[[:space:]]*\|\|[[:space:]]*UNITY_EDITOR)\b' <<< "$FIRST_LINE" \
        && grep -qE '^[[:space:]]*#endif\b' <<< "$LAST_LINE"; } || \
        add_issue "missing dev-only guard — wrap the whole file in '#if UNITY_EDITOR || DEVELOPMENT_BUILD' ... '#endif'"
fi

if [ "$ACCESSOR_ALLOWED" -eq 0 ] && grep -qE '\bDebugCommandRegistryAccessor\b' <<< "$STRIPPED"; then
    add_issue "DebugCommandRegistryAccessor outside DebugCommandsModule.cs — inject IDebugCommandRegistry; the accessor exists only for the Editor runner"
fi

if [ -n "$ISSUES" ]; then
    unity_hook_block "Debug command rule violated in $FILE_PATH:${ISSUES}"$'\n'"See .claude/rules/debug-commands.md."
fi

exit 0
