#!/bin/bash

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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-null-propagation" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 5000 ]; then tail -n 5000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns about ?. and ?? operators on Unity objects (MonoBehaviour, Component, ScriptableObject)
# Unity overrides == null to detect destroyed objects. ?. uses C# reference equality and
# will call methods on destroyed objects — the #1 subtle Unity bug.
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

# Only check files that use Unity types
if ! grep -qE "using UnityEngine|MonoBehaviour|ScriptableObject|Component" "$FILE_PATH" 2>/dev/null; then
    exit 0
fi

# Skip test files and editor files
if echo "$FILE_PATH" | grep -qiE "(Tests?|Spec|/Editor/)"; then
    exit 0
fi

ISSUES=""

# Strip single-line comments and string literals
STRIPPED=$(sed 's|//.*||g; s/"[^"]*"/""/g' "$FILE_PATH" 2>/dev/null)

# Detect ?. usage on likely Unity object fields (fields starting with _ or known Unity types)
# Heuristic: _fieldName?. or variable that follows MonoBehaviour/Component/Transform/GameObject patterns
NULL_PROP=$(echo "$STRIPPED" | grep -n "\?\." | grep -E "(_[a-z]\w*|transform|gameObject|Camera|Renderer|Animator|Rigidbody|Collider|AudioSource|ParticleSystem)\?\.")

if [ -n "$NULL_PROP" ]; then
    ISSUES="${ISSUES}\nSuspected ?. on Unity objects (bypasses destroyed-object detection):\n${NULL_PROP}\n"
fi

# Detect "is null" on Unity object fields
IS_NULL=$(echo "$STRIPPED" | grep -n "\bis null\b" | grep -E "(_[a-z]\w*|transform|gameObject)\s+is\s+null")
if [ -n "$IS_NULL" ]; then
    ISSUES="${ISSUES}\nSuspected 'is null' on Unity objects (use == null instead):\n${IS_NULL}\n"
fi

if [ -n "$ISSUES" ]; then
    echo "WARNING — Unsafe null checks on Unity objects in: $FILE_PATH"
    echo ""
    echo "Unity overrides == to detect destroyed objects. ?. and 'is null' bypass this."
    echo -e "$ISSUES"
    echo ""
    echo "Use: if (_target == null) return;"
    echo "NOT: _target?.Method()  or  if (_target is null)"
    exit 0
fi

exit 0
