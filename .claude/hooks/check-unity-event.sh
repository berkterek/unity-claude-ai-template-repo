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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-unity-event" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks UnityEvent usage in runtime C# scripts
# Catches: UnityEvent, UnityEvent<T>, [SerializeField] UnityEvent fields
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

# Skip test files
if echo "$FILE_PATH" | grep -qiE "(Tests?|Spec)/"; then
    exit 0
fi

# Skip Editor-only files
if echo "$FILE_PATH" | grep -qE "/Editor/"; then
    exit 0
fi

ISSUES=""

# Strip comments and string literals to avoid false positives
STRIPPED=$(strip_cs_noise "$FILE_PATH")

# --- Check 1: UnityEvent field declaration ---
UNITY_EVENT_FIELD=$(echo "$STRIPPED" | grep -nE "\bUnityEvent\b(\s*<[^>]*>)?\s+\w+\s*;")
if [ -n "$UNITY_EVENT_FIELD" ]; then
    ISSUES="${ISSUES}\nBLOCKING — UnityEvent field detected:\n${UNITY_EVENT_FIELD}\n"
    ISSUES="${ISSUES}Use instead:\n"
    ISSUES="${ISSUES}  • Cross-module events  → IEventBus.Publish<TEvent>() / Subscribe<TEvent>()\n"
    ISSUES="${ISSUES}  • Same-class callbacks → System.Action or System.Func<T>\n"
    ISSUES="${ISSUES}  • Internal module comms → C# event keyword (event Action OnSomething)\n"
fi

# --- Check 2: UnityEvent invocation (.Invoke) ---
UNITY_EVENT_INVOKE=$(echo "$STRIPPED" | grep -nE "\bUnityEvent\b|\.Invoke\(\)" | grep -v "//")
# Only flag if UnityEvent is also present in the file (avoid false positives on other .Invoke calls)
HAS_UNITY_EVENT=$(echo "$STRIPPED" | grep -cE "\bUnityEvent\b" 2>/dev/null)
if [ "$HAS_UNITY_EVENT" -gt 0 ]; then
    INVOKE_LINES=$(echo "$STRIPPED" | grep -nE "\.Invoke\(\)")
    if [ -n "$INVOKE_LINES" ]; then
        ISSUES="${ISSUES}\nBLOCKING — UnityEvent.Invoke() call detected:\n${INVOKE_LINES}\n"
        ISSUES="${ISSUES}Replace with IEventBus.Publish<TEvent>() or direct Action/Func invocation.\n"
    fi
fi

# --- Check 3: using UnityEngine.Events namespace ---
USING_UNITY_EVENTS=$(echo "$STRIPPED" | grep -nE "^\s*using\s+UnityEngine\.Events\s*;")
if [ -n "$USING_UNITY_EVENTS" ]; then
    ISSUES="${ISSUES}\nBLOCKING — 'using UnityEngine.Events' detected:\n${USING_UNITY_EVENTS}\n"
    ISSUES="${ISSUES}Remove this namespace — UnityEvent is not allowed in this project.\n"
fi

if [ -n "$ISSUES" ]; then
    unity_hook_block "UNITY EVENT ERROR in: $FILE_PATH"$'\n'"$(echo -e "$ISSUES")"
fi

exit 0
