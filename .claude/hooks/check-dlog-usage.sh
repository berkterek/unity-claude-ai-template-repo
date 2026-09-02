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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-dlog-usage" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
_cleanup_effective_file() { rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; }
trap '_exit_code=$?; _cleanup_effective_file; _hook_log $_exit_code' EXIT
# --- End Hook Audit Logging ---
# Hook: Runtime game code logs through Framework.Logging.DLog, never UnityEngine.Debug.
#       Debug.* is compiled into release builds, carries no tag, and cannot be filtered per domain.
# Scope: _GameFolders/Scripts/Games/ and _Framework/ .cs files. Editor/, Tests/ and any
#        #if UNITY_EDITOR block are exempt — that code never ships (rules/logging.md Card 2).
# Carve-out: Debug.LogError inside *Module.cs / AppScope.cs / GameScope.cs null-guards is
#        mandated by bootstrap-pattern.md and runs before any container exists.
# Rule: rules/logging.md

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
echo "$FILE_PATH" | grep -qE "\.cs$" || exit 0
echo "$FILE_PATH" | grep -qE "(_GameFolders/Scripts/Games/|_Framework/)" || exit 0
should_skip_path "$FILE_PATH" && exit 0
echo "$FILE_PATH" | grep -qE "(^|/)Editors?/" && exit 0

FILENAME=$(basename "$FILE_PATH")

# DLog.cs is the wrapper — the one file allowed to call UnityEngine.Debug.
[ "$FILENAME" = "DLog.cs" ] && exit 0

# Files whose null-guards bootstrap-pattern.md mandates as Debug.LogError.
GUARD_EXEMPT=0
case "$FILENAME" in
    *Module.cs|*Modules.cs|AppScope.cs|GameScope.cs) GUARD_EXEMPT=1 ;;
esac

# --- Compute the EFFECTIVE post-tool-call content ---
# PreToolUse fires BEFORE the write lands, so $FILE_PATH on disk is the pre-edit state.
# Checking disk would make a file that already contains a violation permanently unfixable —
# even the edit that removes the offending line would still see the old content.
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

VIOLATIONS=$(python3 - "$EFFECTIVE_FILE" "$GUARD_EXEMPT" <<'PYEOF'
import re, sys

path, guard_exempt = sys.argv[1], sys.argv[2] == "1"
try:
    src = open(path, encoding="utf-8", errors="surrogateescape").read()
except OSError:
    sys.exit(0)

# Drop block comments so a mention in prose is never a violation.
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)

CALL = re.compile(r"\bDebug\s*\.\s*(Log|LogWarning|LogError|LogException|LogFormat|LogErrorFormat|LogWarningFormat)\b")
EDITOR_IF = re.compile(r"^\s*#\s*if\b.*\bUNITY_EDITOR\b")
ANY_IF = re.compile(r"^\s*#\s*if\b")
ENDIF = re.compile(r"^\s*#\s*endif\b")

hits = []
stack = []  # one entry per open #if; True when that region is UNITY_EDITOR-gated
for n, line in enumerate(src.splitlines(), 1):
    if ANY_IF.match(line):
        stack.append(bool(EDITOR_IF.match(line)))
        continue
    if ENDIF.match(line):
        if stack:
            stack.pop()
        continue
    if any(stack):
        continue
    code = line.split("//", 1)[0]
    m = CALL.search(code)
    if not m:
        continue
    if guard_exempt and m.group(1) in ("LogError", "LogErrorFormat"):
        continue
    hits.append("%d: %s" % (n, line.strip()))
    if len(hits) >= 10:
        break

print("\n".join(hits))
PYEOF
)

if [ -n "$VIOLATIONS" ]; then
    unity_hook_block "Forbidden: UnityEngine.Debug logging in runtime game code.
File: $FILE_PATH

Lines:
$VIOLATIONS

Use DLog — it is [Conditional]-stripped from release builds and filtered per domain:

    using Framework.Logging;
    DLog.Log(LogTag.<Domain>, message);      // Warning / Error for the other levels

Add a LogTag member for the domain if it has none, and enable it — a new tag is silent by default.
Exempt: Editors/, Tests/, code inside #if UNITY_EDITOR, and the Debug.LogError null-guard that
bootstrap-pattern.md mandates in *Module.cs / AppScope.cs / GameScope.cs.

Rule: rules/logging.md Cards 1-3."
fi

exit 0
