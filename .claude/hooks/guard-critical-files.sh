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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "guard-critical-files" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
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
if echo "$FILENAME_NO_EXT" | grep -qiE "^AppScope$"; then
    CRITICAL=true
    REASON="AppScope is the VContainer root — changes affect all registered services and scene wiring."
fi

# InputView — sole owner of PlayerControls, changes affect all input
if echo "$FILENAME_NO_EXT" | grep -qiE "^InputView$"; then
    CRITICAL=true
    REASON="InputView owns PlayerControls — changes affect all input bindings and action maps."
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
if echo "$FILENAME_NO_EXT" | grep -qiE "^(IEventBus|EventBus|EventBusAccessor)$"; then
    CRITICAL=true
    REASON="EventBus is the cross-module communication contract — interface changes break all subscribers."
fi

# Assembly definition files
if [ "$EXT" = "asmdef" ]; then
    CRITICAL=true
    REASON=".asmdef files control assembly boundaries and references — incorrect changes cause compile errors across the project."
fi

# ModuleInstaller base class
if echo "$FILENAME_NO_EXT" | grep -qiE "^ModuleInstaller$"; then
    CRITICAL=true
    REASON="ModuleInstaller is the base class for all module wiring — changes propagate to every installer."
fi

if [ "$CRITICAL" = true ]; then
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
    echo "Once you have investigated, re-attempt the edit with a clear plan."
    exit 2
fi

exit 0
