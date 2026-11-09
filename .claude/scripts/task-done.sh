#!/usr/bin/env bash
# ============================================================================
# task-done.sh — close one /orchestrate task in ONE tool call.
#
# Ticks the task's checkbox in tasks.md and appends VERIFICATION_PASSED +
# TASK_COMPLETED to docs/EVENTS.jsonl.
#
# Why: measured on a downstream project (Nov 2026, 17 /orchestrate runs) the
# main session spent ~15 Bash turns per run appending EVENTS lines and ~15 Edit
# turns ticking tasks.md, each turn re-reading a ~440k context. One call
# replaces 2-4 turns per task.
#
# It never commits — committing stays the committer step's job (and a direct
# `git commit` at depth 0 is blocked by guard-pipeline-direct-work.sh).
#
# Usage:
#   .claude/scripts/task-done.sh <tasks.md> <task-id> [commit-hash|none] [reviewer] [clean|fixed] [note]
#   .claude/scripts/task-done.sh docs/modules/12-x/tasks.md T004 a1b2c3d Codex
#   .claude/scripts/task-done.sh docs/modules/12-x/tasks.md T004,T005,T006 none Claude
#     (comma-separated ids close a whole parallel group)
#   .claude/scripts/task-done.sh docs/modules/12-x/tasks.md T004 a1b2c3d Codex fixed "asmdef ref missing (CS0234)"
#
# Verifier result (5th arg, optional): what the unity-verifier did for this call — `clean` = VERIFIED with no
# fix, `fixed` = ISSUES FOUND and fixed. One VERIFIER_RESULT line per call (a parallel group is one verifier spawn),
# so the catch rate can be counted from EVENTS.jsonl instead of read out of transcripts. 6th arg = a short note
# naming what was fixed. Omit both when no verifier ran.
#
# Exit: 0 = done (prints one line per task) · 1 = usage / task line not found / bad verifier result
# ============================================================================
set -uo pipefail

TASKS="${1:-}"; IDS="${2:-}"; HASH="${3:-none}"; REVIEWER="${4:-}"; VERIFIER="${5:-}"; VNOTE="${6:-}"
if [ -z "$TASKS" ] || [ -z "$IDS" ] || [ ! -f "$TASKS" ]; then
    echo "usage: task-done.sh <tasks.md> <task-id[,task-id...]> [commit-hash|none] [reviewer] [clean|fixed] [note]" >&2
    exit 1
fi
case "$VERIFIER" in
    ""|clean|fixed) ;;
    *) echo "bad verifier result '$VERIFIER' — use clean or fixed" >&2; exit 1 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
EVENTS="$ROOT/docs/EVENTS.jsonl"
mkdir -p "$(dirname "$EVENTS")"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RC=0

IFS=',' read -r -a ID_LIST <<< "$IDS"
for ID in "${ID_LIST[@]}"; do
    ID="$(printf '%s' "$ID" | tr -d '[:space:]')"
    [ -z "$ID" ] && continue
    # Checkbox line: "- [ ] T004 ..." or "- [x] T004 ..." (any indentation)
    LINE="$(grep -nE "^[[:space:]]*- \[[ xX]\] ${ID}([^0-9A-Za-z]|$)" "$TASKS" | head -1)"
    if [ -z "$LINE" ]; then
        echo "NOT FOUND: $ID has no checkbox line in $TASKS" >&2
        RC=1; continue
    fi
    NUM="${LINE%%:*}"
    TEXT="${LINE#*:}"
    # Title = text after the id, first backticked path stripped, cut at " — "
    TITLE="$(printf '%s' "$TEXT" | sed -E "s/^[[:space:]]*- \[[ xX]\] ${ID}[[:space:]]*//; s/\[[^]]*\][[:space:]]*//g; s/^\`[^\`]*\`[[:space:]]*(—[[:space:]]*)?//; s/[[:space:]]—.*$//" | cut -c1-120)"
    [ -z "$TITLE" ] && TITLE="$ID"

    # Tick (idempotent). Temp file in the same dir, then mv — no partial writes.
    TMP="$(mktemp "${TASKS}.XXXXXX")"
    awk -v n="$NUM" 'NR==n { sub(/- \[ \]/, "- [x]") } { print }' "$TASKS" > "$TMP" && mv "$TMP" "$TASKS"

    jq -cn --arg id "$ID" --arg title "$TITLE" --arg ts "$TS" \
        '{event:"VERIFICATION_PASSED", id:$id, title:$title, timestamp:$ts}' >> "$EVENTS"
    jq -cn --arg id "$ID" --arg title "$TITLE" --arg commit "$HASH" --arg reviewer "$REVIEWER" --arg ts "$TS" \
        '{event:"TASK_COMPLETED", id:$id, title:$title, commit:$commit, reviewer:$reviewer, timestamp:$ts}' >> "$EVENTS"
    echo "done: $ID — $TITLE"
done

if [ -n "$VERIFIER" ]; then
    jq -cn --arg ids "$IDS" --arg result "$VERIFIER" --arg note "$VNOTE" --arg ts "$TS" \
        '{event:"VERIFIER_RESULT", ids:($ids | split(",") | map(gsub("\\s"; ""))), result:$result, note:$note, timestamp:$ts}' >> "$EVENTS"
fi
exit "$RC"
