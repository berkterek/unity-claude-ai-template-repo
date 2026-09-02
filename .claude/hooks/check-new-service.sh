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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-new-service" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
_cleanup_effective_file() { rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; }
trap '_exit_code=$?; _cleanup_effective_file; _hook_log $_exit_code' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks 'new *Service()' and 'new *Provider()' in all runtime code.
#        Blocks 'new *Handler()' outside *Controller or *View files.
# VContainer constructs and injects services/providers — runtime code must not.
# Handlers are wired only by their owning Controller shell.
# Scope: _GameFolders/Scripts/ .cs files — tests and Editor files are exempt.
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if ! echo "$FILE_PATH" | grep -qE "\.cs$"; then
    exit 0
fi

# Limit scope to _GameFolders/Scripts/
if ! echo "$FILE_PATH" | grep -qE "_GameFolders/Scripts/"; then
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

# Strip comments and string literals to avoid false positives
STRIPPED=$(strip_cs_noise "$EFFECTIVE_FILE")

# --- Check 1: new *Service( — forbidden, except inside *Module.cs factory registrations ---
# *Module.cs is exempt for the same reason as the Handler check below: architecture.md →
# "Handler Factory — VContainer Func<> Pattern" requires constructing dependencies with
# raw/config parameters inside a factory lambda registered in the module's Install() method,
# e.g. builder.RegisterFactory<int, ILevelService>(c => id => new LevelService(id, c.Resolve<IFoo>()), ...).
# The exemption is filename-wide, not factory-scoped, for the same reason as Check 3.
SERVICE_VIOLATIONS=$(echo "$STRIPPED" | grep -nE "\bnew\s+\w+Service\s*\(" | head -10)
if [ -n "$SERVICE_VIOLATIONS" ]; then
    FILENAME=$(basename "$FILE_PATH")
    if ! echo "$FILENAME" | grep -qiE "Module\.cs$"; then
        unity_hook_block "Forbidden: 'new *Service()' or 'new *Provider()' in runtime code.
File: $FILE_PATH

Lines:
$SERVICE_VIOLATIONS

VContainer handles construction and injection. Declare as constructor parameter instead.
Rule: csharp-unity.md → Constructor injection rule."
    fi
fi

# --- Check 2: new *Provider( — forbidden, except inside *Module.cs factory registrations ---
# Same exemption and rationale as Check 1.
PROVIDER_VIOLATIONS=$(echo "$STRIPPED" | grep -nE "\bnew\s+\w+Provider\s*\(" | head -10)
if [ -n "$PROVIDER_VIOLATIONS" ]; then
    FILENAME=$(basename "$FILE_PATH")
    if ! echo "$FILENAME" | grep -qiE "Module\.cs$"; then
        unity_hook_block "Forbidden: 'new *Service()' or 'new *Provider()' in runtime code.
File: $FILE_PATH

Lines:
$PROVIDER_VIOLATIONS

VContainer handles construction and injection. Declare as constructor parameter instead.
Rule: csharp-unity.md → Constructor injection rule."
    fi
fi

# --- Check 3: new *Handler( — only allowed inside *Controller, *View or *Module files ---
# *Module.cs is exempt because architecture.md → "Handler Factory — VContainer Func<>
# Pattern" REQUIRES the handler to be constructed there when it needs a container
# dependency:
#     builder.RegisterFactory<Rigidbody, IMoveHandler>(
#         c => rb => new MoveHandler(rb, c.Resolve<MoveConfiguration>()), Lifetime.Singleton);
# The exemption is filename-wide, not factory-scoped: `new MoveHandler(` sits on its own
# line inside the lambda, so there is no same-line marker a line-based grep could anchor
# on. A blanket Module exemption over-permits; blocking the documented RIGHT pattern
# would deadlock correct code, which is worse.
HANDLER_VIOLATIONS=$(echo "$STRIPPED" | grep -nE "\bnew\s+\w+Handler\s*\(" | head -10)
if [ -n "$HANDLER_VIOLATIONS" ]; then
    FILENAME=$(basename "$FILE_PATH")
    # Allow inside *Controller.cs, *View.cs and *Module.cs files
    if ! echo "$FILENAME" | grep -qiE "(Controller|View|Module)\.cs$"; then
        unity_hook_block "'new *Handler()' is only allowed inside *Controller, *View or *Module files.
File: $FILE_PATH

Lines:
$HANDLER_VIOLATIONS

Handlers are wired by their owning Controller shell (or registered as a
VContainer factory in the domain's *Module), not from other classes.
Rule: solid-oop.md → Handler Rules; architecture.md → Handler Factory pattern."
    fi
fi

exit 0
