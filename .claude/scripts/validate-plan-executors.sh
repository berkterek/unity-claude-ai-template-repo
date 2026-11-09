#!/usr/bin/env bash
# ============================================================================
# validate-plan-executors.sh — PLAN-TIME check: who runs each task.
#
# /orchestrate's main session is the most expensive place to do anything: every
# turn re-reads its whole context (~440k tokens on average). Measured on a
# downstream project (Nov 2026): planners had invented a `[MAIN-SESSION]` tag
# for 22% of all tasks (271 / 1251) — scene, prefab and SO edits, Play Mode
# acceptance runs, "checkpoint: compile + full EditMode + PlayMode, record
# counts" and baseline tasks. The main session then did that work itself
# (Unity MCP 84 calls per run; unity-verifier spawned once in all history).
#
# Rules:
#   1. `[MAIN-SESSION]` (or `Agent: main`) is allowed only on a task whose first
#      backticked path is an `.asmdef` — check-config-protection.sh lets only
#      the Director write one. Scene / prefab / SO / asset work → `Agent:
#      unity-setup`; code → coder / unity-coder.
#   2. No checkpoint / baseline task. /orchestrate's Phase Gate already runs
#      compile + tests (unity-verifier) at each `**Checkpoint:**` line; a
#      Play Mode acceptance check belongs in that Checkpoint line's text.
#
# Usage:   .claude/scripts/validate-plan-executors.sh <plan-dir-or-tasks.md> [...]
# Exit:    0 = OK (prints `checked:` receipt) · 2 = violation(s) · 1 = usage
# ============================================================================
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: validate-plan-executors.sh <plan-dir-or-tasks.md> [...]" >&2; exit 1; }

FILES=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        [ -f "$arg/tasks.md" ] && FILES+=("$arg/tasks.md")
    elif [ -f "$arg" ]; then
        case "$arg" in *tasks*.md) FILES+=("$arg") ;; esac
    else
        echo "not found: $arg" >&2; exit 1
    fi
done
[ ${#FILES[@]} -gt 0 ] || { echo "no tasks.md under: $*" >&2; exit 1; }

VIOL=0; CHECKED=0
for f in "${FILES[@]}"; do
    while IFS= read -r hit; do
        n="${hit%%:*}"; line="${hit#*:}"
        CHECKED=$((CHECKED + 1))
        id="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*- \[[ xX]\] ([A-Za-z]*[0-9]+[a-z]?).*/\1/')"
        first_path="$(printf '%s' "$line" | grep -oE '`[^`]+`' | head -1 | tr -d '`')"
        body="$(printf '%s' "$line" | sed -E 's/^[^`]*`[^`]*`[[:space:]]*(—|-)?[[:space:]]*//')"

        if printf '%s' "$line" | grep -qiE '\[MAIN-SESSION\]|Agent:[[:space:]]*main\b'; then
            case "$first_path" in
                *.asmdef) ;;
                *)
                    VIOL=$((VIOL + 1))
                    echo "VIOLATION [$VIOL] $f:$n $id — main-session task on '${first_path:-no path}'"
                    echo "    Only an .asmdef task may run in the main session. Scene/prefab/SO/asset →"
                    echo "    'Agent: unity-setup'; code → coder/unity-coder; a Play Mode check → the Checkpoint line."
                    ;;
            esac
        fi
        if printf '%s' "$body" | grep -qiE '^(checkpoint|baseline)\b|record (the )?counts|full (EditMode|PlayMode)'; then
            VIOL=$((VIOL + 1))
            echo "VIOLATION [$VIOL] $f:$n $id — checkpoint/baseline written as a task"
            echo "    /orchestrate's Phase Gate already compiles and runs the suite at every"
            echo "    '**Checkpoint:**' line. Delete the task; put any extra Play Mode check in the Checkpoint text."
        fi
    done < <(grep -nE '^[[:space:]]*- \[[ xX]\] [A-Za-z]*[0-9]+' "$f")
done

echo ""
echo "--- Plan Executor Validation ---"
echo "files scanned : ${#FILES[@]}"
if [ "$CHECKED" -eq 0 ]; then
    echo "result        : NO TASKS FOUND — this is NOT a pass."
    exit 0
fi
if [ "$VIOL" -gt 0 ]; then
    echo "result        : $VIOL VIOLATION(S) in $CHECKED task(s)."
    exit 2
fi
echo "checked: executors — $CHECKED task(s), no main-session work outside .asmdef, no checkpoint tasks"
exit 0
