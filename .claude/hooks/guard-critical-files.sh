#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"   # minimal | standard | strict
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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "guard-critical-files" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks edits to critical Unity architecture files without explicit investigation
# Applies to: AppScope, InputView, ModuleInstaller, AppInstaller, .asmdef, EventBus files
# Forces Claude to read dependencies and understand impact before modifying
# Receives JSON on stdin with tool_input.file_path and tool_input.new_string (or content)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Only check files being written/edited (not just read)
FILENAME=$(basename "$FILE_PATH")
FILENAME_NO_EXT="${FILENAME%.*}"
EXT="${FILENAME##*.}"

# --- Critical Unity architecture files ---
CRITICAL=false
REASON=""

# AppScope — wiring for all DI, changes break entire app
# Exception: creating a brand-new AppScope.cs (file doesn't exist yet) is safe —
# there is no existing wiring to break.
if echo "$FILENAME_NO_EXT" | grep -qiE "^AppScope$"; then
    if [ ! -f "$FILE_PATH" ]; then
        : # new file — safe to create
    else
        CRITICAL=true
        REASON="AppScope is the VContainer root — changes affect all registered services and scene wiring."
    fi
fi

# InputService — sole owner of PlayerControls, changes affect all input
# Exception: creating a brand-new InputService.cs (file doesn't exist yet) is safe.
if echo "$FILENAME_NO_EXT" | grep -qiE "^InputService$"; then
    if [ ! -f "$FILE_PATH" ]; then
        : # new file — safe to create
    else
        CRITICAL=true
        REASON="InputService owns PlayerControls — changes affect all input bindings and action maps."
    fi
fi

# Any Installer — registers services into VContainer scope
# Exception: test infrastructure installers under TestScopes/ or Tests/ paths are safe to create/edit
if echo "$FILENAME_NO_EXT" | grep -qiE "Installer$"; then
    if echo "$FILE_PATH" | grep -qiE "(TestScopes|EditModeTest|PlayModeTest|EditMode|PlayMode)/"; then
        : # test installer — allowed
    elif [ ! -f "$FILE_PATH" ]; then
        : # new file — safe to create, hook only protects existing wiring
    else
        CRITICAL=true
        REASON="Installer files wire VContainer bindings — changes can break DI resolution for the entire module."
    fi
fi

# IEventBus, EventBus — cross-system communication contract
# Exception: creating a brand-new file (doesn't exist yet) is safe.
if echo "$FILENAME_NO_EXT" | grep -qiE "^(IEventBus|EventBus|EventBusAccessor)$"; then
    if [ ! -f "$FILE_PATH" ]; then
        : # new file — safe to create
    else
        CRITICAL=true
        REASON="EventBus is the cross-module communication contract — interface changes break all subscribers."
    fi
fi

# Assembly definition files
# Exception: creating a brand-new .asmdef is safe — there is no existing
# assembly boundary to break, and the decision to open a new one is made (and
# gated) at plan time. Same create/edit split as every other rule above.
if [ "$EXT" = "asmdef" ]; then
    if [ ! -f "$FILE_PATH" ]; then
        : # new file — safe to create
    else
        CRITICAL=true
        REASON=".asmdef files control assembly boundaries and references — incorrect changes cause compile errors across the project."
    fi
fi

# AppModules — lists every registered module, changes affect entire app DI graph
# Exception: creating a brand-new AppModules.cs (file doesn't exist yet) is safe.
if echo "$FILENAME_NO_EXT" | grep -qiE "^AppModules$"; then
    if [ ! -f "$FILE_PATH" ]; then
        : # new file — safe to create
    else
        CRITICAL=true
        REASON="AppModules.cs lists every registered module — changes affect entire app DI graph."
    fi
fi

# ConfigCatalog — single config aggregator, changes break module initialization
# Exception: creating a brand-new ConfigCatalog.cs (file doesn't exist yet) is safe —
# there is no existing wiring to break.
if echo "$FILENAME_NO_EXT" | grep -qiE "^ConfigCatalog$"; then
    if [ ! -f "$FILE_PATH" ]; then
        : # new file — safe to create
    else
        CRITICAL=true
        REASON="ConfigCatalog.cs is the single config aggregator — changes break module initialization."
    fi
fi

if [ "$CRITICAL" = true ]; then
    # Deny-then-allow gate: block the first attempt per file per session to force
    # investigation, then let the (presumably now-informed) retry through. Without
    # this, editing an EXISTING critical file (not just creating a new one) would
    # block identically forever — there was no way to ever land a real edit.
    #
    # The pass is restricted to the Director (depth 0), same reasoning as
    # gateguard.sh and check-config-protection.sh: nothing here verifies the
    # investigation actually happened, so a caller that merely retries walks
    # through. That is acceptable for the Director, whose retry follows reporting
    # the findings where the user can read them — a subagent reports to the
    # Director, not the user, so self-satisfying this gate cancels its purpose.
    # Inside a subagent the block repeats, leaving "report upward" as the only
    # route. No staleness downgrade: here 0 is the value that PASSES, so a timeout
    # would release a long-running subagent (see gateguard.sh for the full note).
    # Plan coverage releases this gate. This hook's demand is "investigate and
    # confirm the change is intentional and scoped" — a task declared in the plan
    # and approved by a human at SCOPE_GATE has already answered it. Requiring
    # Callers:/Wiring: for a one-line AppModules.cs edit would be noise, so
    # coverage alone is checked here; gateguard.sh layers the facts check on top.
    #
    # This branch is what lets a module actually register itself: every new module
    # must edit AppModules.cs by definition, and without it a pipeline writes all
    # its files and then deadlocks on the last line.
    if unity_plan_covers "$FILE_PATH"; then
        exit 0
    fi

    GCF_DEPTH=$(unity_subagent_depth)

    DENIED_FILE="${UNITY_HOOK_STATE_DIR}/guard-critical-denied.txt"
    PASSED_FILE="${UNITY_HOOK_STATE_DIR}/guard-critical-passed.txt"
    touch "$DENIED_FILE" "$PASSED_FILE"

    if [ "$GCF_DEPTH" -eq 0 ] && grep -qxF "$FILE_PATH" "$PASSED_FILE" 2>/dev/null; then
        exit 0
    fi

    if [ "$GCF_DEPTH" -eq 0 ] && grep -qxF "$FILE_PATH" "$DENIED_FILE" 2>/dev/null; then
        echo "$FILE_PATH" >> "$PASSED_FILE"
        exit 0
    fi

    [ "$GCF_DEPTH" -eq 0 ] && echo "$FILE_PATH" >> "$DENIED_FILE"
    echo "BLOCKED: Critical architecture file requires investigation before editing."
    echo ""
    echo "File: $FILE_PATH"
    echo "Reason: $REASON"
    echo ""
    echo "Before editing this file, you MUST:"
    echo "  1. Read the file fully to understand current structure"
    echo "  2. Identify all files that import or depend on this file"
    echo "  3. Understand what breaks if the public API changes"
    echo "  4. Confirm the change is intentional and scoped"
    echo ""
    echo ""
    if [ "$GCF_DEPTH" -gt 0 ]; then
        echo "You are a SUBAGENT — retrying will NOT clear this block. Your output goes"
        echo "to the Director, not to the user, so satisfying this gate yourself would"
        echo "cancel the only thing it does. Report BLOCKED with this message verbatim."
        echo ""
        echo "DIRECTOR, if no subagent is running the depth counter has leaked:"
        echo "  echo 0 > \"\$CLAUDE_PROJECT_DIR\"/.claude/state/subagent-depth"
    else
        echo "Once you have investigated, re-attempt the edit — it will pass this time."
        echo "Do NOT route around this via Bash."
    fi
    exit 2
fi

exit 0
