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
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
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

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Strip comments and string literals to avoid false positives
STRIPPED=$(strip_cs_noise "$FILE_PATH")

# --- Check 1: new *Service( — forbidden everywhere ---
SERVICE_VIOLATIONS=$(echo "$STRIPPED" | grep -nE "\bnew\s+\w+Service\s*\(" | head -10)
if [ -n "$SERVICE_VIOLATIONS" ]; then
    unity_hook_block "Forbidden: 'new *Service()' or 'new *Provider()' in runtime code.
File: $FILE_PATH

Lines:
$SERVICE_VIOLATIONS

VContainer handles construction and injection. Declare as constructor parameter instead.
Rule: csharp-unity.md → Constructor injection rule."
fi

# --- Check 2: new *Provider( — forbidden everywhere ---
PROVIDER_VIOLATIONS=$(echo "$STRIPPED" | grep -nE "\bnew\s+\w+Provider\s*\(" | head -10)
if [ -n "$PROVIDER_VIOLATIONS" ]; then
    unity_hook_block "Forbidden: 'new *Service()' or 'new *Provider()' in runtime code.
File: $FILE_PATH

Lines:
$PROVIDER_VIOLATIONS

VContainer handles construction and injection. Declare as constructor parameter instead.
Rule: csharp-unity.md → Constructor injection rule."
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
