#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

# Feature gate — only run when ECS is enabled. Redirectable via UNITY_FEATURES_FILE
# (tests point this at a temp file). enum-byte-base is an ECS/IEvent-only rule.
# CLAUDE_PROJECT_DIR first, git rev-parse fallback (2026-08-29, same class of bug as
# _lib.sh's _resolve_state_dir): a subagent's cwd is not guaranteed to be the repo root,
# so an empty git rev-parse here silently produced "/.claude/project-features.json" —
# jq fails to find it, .ecs reads as not "true", and this check silently no-ops inside
# a subagent even when ECS is genuinely enabled project-wide.
UNITY_FEATURES_FILE="${UNITY_FEATURES_FILE:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}/.claude/project-features.json}"
[ "$(jq -r '.ecs // false' "$UNITY_FEATURES_FILE" 2>/dev/null)" = "true" ] || exit 0

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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-enum-byte-base" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
_cleanup_effective_file() { rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; }
trap '_exit_code=$?; _cleanup_effective_file; _hook_log $_exit_code' EXIT
# --- End Hook Audit Logging ---
# Hook: Warns when an enum inside an ECS component or IEvent struct does not inherit from byte.
# Only fires for files in Ecs/ folders or files containing IEvent / IComponentData context.
# Exit 2 — blocking. Enums in ECS/IEvent context MUST inherit from byte (non-negotiable per rules/ecs-dots.md).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if ! echo "$FILE_PATH" | grep -qE "\.cs$"; then
    exit 0
fi

# Skip Editor / third-party / test paths
should_skip_path "$FILE_PATH" && exit 0

# --- Compute the EFFECTIVE post-tool-call content ---
# This hook runs PreToolUse: $FILE_PATH on disk is the file's state BEFORE the
# pending Edit/Write is applied. Checking that stale content means a BLOCKING
# violation already on disk can never be cleared — even an edit that removes
# the offending line still sees the unmodified disk file. Build the effective
# post-edit file and run every check against it instead.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
EFFECTIVE_FILE=$(mktemp)

case "$TOOL_NAME" in
    Write)
        echo "$INPUT" | jq -j '.tool_input.content // empty' > "$EFFECTIVE_FILE"
        ;;
    Edit)
        [ -f "$FILE_PATH" ] || exit 0
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
        ;;
    *)
        [ -f "$FILE_PATH" ] || exit 0
        cp "$FILE_PATH" "$EFFECTIVE_FILE"
        ;;
esac

# Only check ECS component files or files that contain a real IEvent / IComponentData
# struct declaration. A struct-declaration match (tolerating multi-interface lists)
# with a word boundary avoids matching IEventBus, IEventBusListener, etc.
IS_ECS_PATH=false
IS_EVENT_OR_COMPONENT=false

if echo "$FILE_PATH" | grep -qE "/Ecs/"; then
    IS_ECS_PATH=true
fi

if grep -qE 'struct[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[^{]*\b(IEvent|IComponentData)\b' "$EFFECTIVE_FILE" 2>/dev/null; then
    IS_EVENT_OR_COMPONENT=true
fi

if ! $IS_ECS_PATH && ! $IS_EVENT_OR_COMPONENT; then
    exit 0
fi

# Strip single-line comments before analysis
STRIPPED=$(sed 's|//.*||g' "$EFFECTIVE_FILE" 2>/dev/null)

# Find enums that do NOT have a byte base type
# Pattern: "enum SomeName" or "enum SomeName : int/uint/short/ushort/long/ulong" but NOT ": byte"
ISSUES=""

while IFS= read -r line; do
    LINE_NUM=$(echo "$line" | cut -d: -f1)
    LINE_CONTENT=$(echo "$line" | cut -d: -f2-)

    # Skip if already has byte base
    if echo "$LINE_CONTENT" | grep -qE "enum[[:space:]]+[[:alnum:]_]+[[:space:]]*:[[:space:]]*byte"; then
        continue
    fi

    ENUM_NAME=$(echo "$LINE_CONTENT" | grep -oE "enum[[:space:]]+[[:alnum:]_]+" | grep -oE "[[:alnum:]_]+$")
    ISSUES="${ISSUES}\n  Line ${LINE_NUM}: enum ${ENUM_NAME} — missing ': byte'"
done < <(grep -nE "enum[[:space:]]+[[:alnum:]_]+" "$EFFECTIVE_FILE" 2>/dev/null | grep -v "//")

if [ -n "$ISSUES" ]; then
    unity_hook_block "enum without byte base in ECS/IEvent context: $FILE_PATH
$(echo -e "$ISSUES")

Enums inside IComponentData or IEvent structs must inherit from byte to minimize
struct size and improve ECS chunk density.
Fix: enum MyState : byte { Idle, Moving, Attacking }   (use ushort if > 255 values)"
fi

exit 0
