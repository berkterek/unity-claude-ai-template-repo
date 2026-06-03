#!/usr/bin/env bash
# ============================================================================
# stop-verify.sh — STOP HOOK (batch verifier)
# Drains $UNITY_EDITS_FILE at session end and runs per-extension verifiers
# on every file written this session — including writes performed by subagents
# whose PostToolUse hooks never fired in the main session (ECC pattern).
# ============================================================================
# Trigger:  Stop
# Exit:     0 always (advisory — never blocks)
# Ordering: Must be AFTER session-save.sh in the Stop array.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"
source "${SCRIPT_DIR}/_lib.sh"

# Drain stdin (Stop hooks receive a JSON event payload we don't need here).
cat > /dev/null || true

if [[ ! -s "$UNITY_EDITS_FILE" ]]; then
    exit 0  # nothing to verify this session
fi

# Snapshot + deduplicate before truncating.
TMP_LIST="${UNITY_HOOK_STATE_DIR}/stop-verify-batch.txt"
sort -u "$UNITY_EDITS_FILE" > "$TMP_LIST" || true
: > "$UNITY_EDITS_FILE"   # truncate — next session starts clean

FEATURES=".claude/project-features.json"
PROJECT_FOLDER="."
if [[ -f "$FEATURES" ]]; then
    PROJECT_FOLDER=$(jq -r '.unity_project_folder // "."' "$FEATURES" 2>/dev/null || echo ".")
fi
SLN=$(find "$PROJECT_FOLDER" -maxdepth 2 -name "*.sln" 2>/dev/null | head -1 || true)

VERIFIED=0
WARNINGS=0

while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ ! -f "$path" ]] && continue   # file deleted/moved — skip silently

    case "$path" in
        *.sh)
            if ! bash -n "$path" 2>&1; then
                echo "[stop-verify] WARNING syntax error in $path" >&2
                WARNINGS=$((WARNINGS + 1))
            fi
            VERIFIED=$((VERIFIED + 1))
            ;;
        *.json)
            if ! jq . "$path" > /dev/null 2>&1; then
                echo "[stop-verify] WARNING malformed JSON in $path" >&2
                WARNINGS=$((WARNINGS + 1))
            fi
            VERIFIED=$((VERIFIED + 1))
            ;;
        *.cs)
            VERIFIED=$((VERIFIED + 1))
            ;;
    esac
done < "$TMP_LIST"

# One batched dotnet build for all accumulated .cs files (if .sln exists).
if [[ -n "$SLN" ]] && grep -q '\.cs$' "$TMP_LIST" 2>/dev/null; then
    CS_COUNT=$(grep -c '\.cs$' "$TMP_LIST" || true)
    echo "[stop-verify] batch dotnet build for ${CS_COUNT} .cs file(s)" >&2
    ERRORS=$(dotnet build "$SLN" -v q 2>&1 | grep -i " error " || true)
    if [[ -n "$ERRORS" ]]; then
        echo "[stop-verify] WARNING build errors at Stop:" >&2
        echo "$ERRORS" >&2
        WARNINGS=$((WARNINGS + 1))
    fi
elif grep -q '\.cs$' "$TMP_LIST" 2>/dev/null; then
    echo "[stop-verify] skip .cs files — no .sln found under '$PROJECT_FOLDER'" >&2
fi

echo "[stop-verify] verified=${VERIFIED} warnings=${WARNINGS}" >&2
exit 0
