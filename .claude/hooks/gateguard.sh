#!/usr/bin/env bash
# ============================================================================
# gateguard.sh — BLOCKING HOOK (strict profile)
# Three-stage fact-forcing gate for C# edits: DENY -> FORCE -> ALLOW
#
#   Stage 1 (DENY):  Block first Edit/Write on a C# file. Force investigation.
#   Stage 2 (FORCE): Emit Unity-specific fact demands (callers, GUID refs,
#                    FormerlySerializedAs plan, instruction quote, asmdef).
#   Stage 3 (ALLOW): Second attempt on same file proceeds (presumes the agent
#                    read the deny message and gathered facts).
#
# Also enforces Read-before-Edit and the MVS counterpart heuristic.
# ============================================================================
# Trigger: PreToolUse on Edit|Write|MultiEdit
# Exit:    2 = block, 0 = allow
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"
source "${SCRIPT_DIR}/_lib.sh"
# shellcheck source=lib-gateguard-facts.sh
#
# NOTE: `source FILE || { ... }` looks like the right guard but does NOT work
# here: under `set -e`, bash's `source`/`.` builtin treats "file not found" as
# a fatal shell error, not a regular nonzero exit — it exits the script
# immediately with status 1, bypassing the `||` handler entirely (confirmed:
# `source missing.sh || { exit 2; }` under `set -e` still exits 1). Status 1
# is not blocking in this harness, so that shape would silently fail open.
# An explicit existence check avoids the builtin's special-cased error path.
#
# Both -f and -r are required, not -r alone: [ -r ] is true for a readable
# DIRECTORY too, and sourcing a directory dies with exit 1 — the exact
# fail-open this guard exists to close, just reintroduced through a different
# path state (missing/unreadable/directory all covered by requiring both).
GATEGUARD_FACTS_LIB="${SCRIPT_DIR}/lib-gateguard-facts.sh"
if [ ! -f "$GATEGUARD_FACTS_LIB" ] || [ ! -r "$GATEGUARD_FACTS_LIB" ]; then
    echo "BLOCKED: gateguard cannot load lib-gateguard-facts.sh (missing, unreadable, or not a regular file) — refusing to gate blind." >&2
    exit 2
fi
source "$GATEGUARD_FACTS_LIB"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only gate C# files
case "$FILE_PATH" in
    *.cs) ;;
    *) exit 0 ;;
esac

BASENAME=$(basename "$FILE_PATH" .cs)
DIR=$(dirname "$FILE_PATH")

# --- State tracking: per-file fact-gate progress ---
FACTS_DENIED_FILE="${UNITY_HOOK_STATE_DIR}/gateguard-facts-denied.txt"
FACTS_PASSED_FILE="${UNITY_HOOK_STATE_DIR}/gateguard-facts-passed.txt"
touch "$FACTS_DENIED_FILE" "$FACTS_PASSED_FILE"

# Detect Write (new file) vs Edit (existing) vs MultiEdit
IS_WRITE="false"
if [ "$TOOL_NAME" = "Write" ]; then
    # Write creates new file OR overwrites; treat as new-file gate if file doesn't exist yet
    if [ ! -f "$FILE_PATH" ]; then
        IS_WRITE="true"
    fi
fi

# --- Guard 1: Read-before-Edit (skip for brand-new Write of non-existent file) ---
if [ "$IS_WRITE" = "false" ]; then
    if ! unity_was_read "$FILE_PATH"; then
        unity_track_warning "gateguard" "unread: $FILE_PATH"
        echo "" >&2
        echo "  GateGuard — STAGE 1: You must Read this file before editing." >&2
        echo "  File: $FILE_PATH" >&2
        echo "" >&2
        echo "  The file may contain state, invariants, or attributes you will" >&2
        echo "  destroy with a blind edit." >&2
        unity_hook_block "GateGuard: Read $FILE_PATH before editing."
    fi
fi

# --- Guard 2: Fact-gate (first edit per file emits fact demands) ---
#
# The gate is deny-then-allow: block once, pass on retry. Nothing in it verifies
# that the demanded facts were ever presented — a caller that simply retries walks
# straight through. That is tolerable for the Director, whose retry is preceded by
# actually printing the facts where the user can read them. It is NOT tolerable for
# a subagent: a subagent's output goes to the Director, not to the human, so a
# subagent that self-satisfies this gate cancels the one thing it exists to do —
# move a decision in front of a person. Observed in a derived project: a subagent
# hit the gate, retried on its own, landed the file, and never mentioned the block
# in its report.
#
# So the retry pass is restricted to depth 0 (the Director). Inside a subagent the
# demand repeats every time, which leaves reporting upward as the only way forward.
#
# No staleness downgrade here, unlike guard-pipeline-direct-work.sh: there a stale
# count read as 0 makes the hook ENFORCE, here it would make it PASS. Nothing
# touches the depth file while an agent merely runs, so any subagent outliving a
# timeout would be handed exactly the bypass this restriction removes. A leaked
# count therefore costs the Director an extra report cycle — the direction that
# fails safe. session-restore.sh clears the counter each session.
#
# "Reporting upward" is no longer the ONLY way forward for a blocked subagent —
# the plan-coverage branch immediately below is the other door: a path an
# approved plan already declares (with a valid facts block) proceeds without
# depth mattering at all.
# --- Plan coverage: the approved plan answers the fact demands, not a retry ---
#
# The five demands below are properties of the plan, answerable before any agent
# spawns. Demanding them at write time made them unanswerable inside a subagent
# (its output goes to the Director, not the human), which deadlocked every
# pipeline: guard-pipeline-direct-work.sh blocks the Director, this blocked the
# subagent, nobody could write. See
# docs/superpowers/specs/2026-08-16-plan-time-fact-gate-design.md
#
# Coverage is recomputed live from docs/**/tasks.md on every call — there is no
# cached receipt, so a plan edit invalidates itself immediately. This branch
# therefore MUST NOT write to FACTS_PASSED_FILE: a written receipt would
# outlive the plan state it was based on and let a later write to the same
# path skip re-checking coverage even after the gate or tasks.md is gone.
if unity_plan_covers "$FILE_PATH"; then
    if FACTS_MSG=$(unity_validate_task_facts "$FILE_PATH" "$(unity_task_mode "$FILE_PATH")"); then
        exit 0
    fi
    # Covered but invalid: retrying cannot help — the problem is in tasks.md.
    # A distinct message so the Director takes the right action.
    echo "" >&2
    echo "  GateGuard — PLAN COVERS THIS PATH, BUT ITS FACTS BLOCK IS INVALID" >&2
    echo "  File: $FILE_PATH" >&2
    echo "" >&2
    echo "  $FACTS_MSG" >&2
    echo "" >&2
    echo "  Retrying will not clear this. Go fix the plan, then re-run:" >&2
    echo "    .claude/scripts/validate-plan-facts.sh <plan dir>" >&2
    unity_hook_block "GateGuard: fix the plan's facts block for $FILE_PATH."
fi

GATEGUARD_DEPTH=$(unity_subagent_depth)

if ! grep -qxF "$FILE_PATH" "$FACTS_PASSED_FILE" 2>/dev/null; then
    # Has this file been denied once already?
    if grep -qxF "$FILE_PATH" "$FACTS_DENIED_FILE" 2>/dev/null && [ "$GATEGUARD_DEPTH" -eq 0 ]; then
        # Second attempt, from the Director — mark as passed and allow through
        echo "$FILE_PATH" >> "$FACTS_PASSED_FILE"
    else
        # First attempt — DENY and demand facts
        echo "$FILE_PATH" >> "$FACTS_DENIED_FILE"
        unity_track_warning "gateguard" "fact-demand: $FILE_PATH"

        # Classify file to tailor the fact demand
        ROLE=""
        case "$BASENAME" in
            *View)   ROLE="View (MVS)" ;;
            *System) ROLE="System (MVS)" ;;
            *Model)  ROLE="Model (MVS)" ;;
            *Config|*Definition|*Data) ROLE="ScriptableObject" ;;
            *Controller|*Manager|*Handler) ROLE="Behaviour" ;;
        esac

        echo "" >&2
        echo "  GateGuard — STAGE 2 (FACT DEMAND)" >&2
        if [ "$IS_WRITE" = "true" ]; then
            echo "  New file: $FILE_PATH" >&2
            [ -n "$ROLE" ] && echo "  Inferred role: $ROLE" >&2
            echo "" >&2
            echo "  Before creating this file, present these facts:" >&2
            echo "" >&2
            echo "  1. Name the file(s) and line(s) that will reference this new type." >&2
            echo "  2. Confirm no existing type serves the same purpose." >&2
            echo "     Run: grep -rn 'class ${BASENAME}' Assets/" >&2
            echo "  3. Identify the asmdef this file belongs to." >&2
            echo "     Run: find $(dirname "$DIR") -name '*.asmdef' | head -5" >&2
            echo "  4. If it's a System, confirm its VContainer registration plan." >&2
            echo "     If it's a MonoBehaviour, confirm the scene/prefab that will host it." >&2
            echo "  5. Quote the user's current instruction verbatim." >&2
        else
            echo "  File: $FILE_PATH" >&2
            [ -n "$ROLE" ] && echo "  Inferred role: $ROLE" >&2
            echo "" >&2
            echo "  Before editing, present these facts:" >&2
            echo "" >&2
            echo "  1. List files that reference this type (callers, consumers)." >&2
            echo "     Run: grep -rn '${BASENAME}' Assets/ --include='*.cs'" >&2
            echo "  2. List scene/prefab references via GUID from the .meta file." >&2
            echo "     Run: GUID=\$(grep 'guid:' ${FILE_PATH}.meta | awk '{print \$2}')" >&2
            echo "          grep -rln \"\$GUID\" Assets/ --include='*.unity' --include='*.prefab'" >&2
            echo "  3. If renaming ANY [SerializeField] field, state the" >&2
            echo "     [FormerlySerializedAs(\"oldName\")] plan. Without it, every" >&2
            echo "     configured instance silently resets to default." >&2
            echo "  4. If changing public API, list the callers that will need updates." >&2
            echo "  5. Quote the user's current instruction verbatim." >&2
        fi
        echo "" >&2
        if [ "$GATEGUARD_DEPTH" -gt 0 ]; then
            echo "  You are a SUBAGENT — retrying will NOT clear this gate." >&2
            echo "  Your output goes to the Director, not to the user, so satisfying this" >&2
            echo "  yourself would cancel the only thing the gate does: put a decision in" >&2
            echo "  front of a person. Report BLOCKED with this message verbatim and stop." >&2
            echo "  The Director presents the facts and retries." >&2
            echo "" >&2
            echo "  DIRECTOR, if no subagent is actually running, the depth counter has" >&2
            echo "  leaked (agent-start-log.sh). Reset it deliberately and visibly:" >&2
            echo "    echo 0 > \"\$CLAUDE_PROJECT_DIR\"/.claude/state/subagent-depth" >&2
            echo "  A new session resets it too. This is a human-visible act on purpose —" >&2
            echo "  no timeout does it silently, because a timeout would also release a" >&2
            echo "  genuinely long-running subagent." >&2
        else
            echo "  After presenting these facts to the user, retry the same edit — it will pass." >&2
            echo "  Presenting them means printing them where the user can read them, not" >&2
            echo "  satisfying yourself that you know them." >&2
        fi
        echo "" >&2
        unity_hook_block "GateGuard: present facts above, then retry the edit."
    fi
fi

# --- Guard 3: MVS counterpart heuristic (advisory, does not block) ---
check_counterpart() {
    local suffix="$1"
    local role="$2"
    local base="${BASENAME%View}"
    base="${base%System}"
    base="${base%Model}"
    local counterpart_name="${base}${suffix}"

    for search_dir in "$DIR" "$(dirname "$DIR")"; do
        local candidate
        # `|| true` keeps `set -euo pipefail` from aborting the hook when `find`
        # exits non-zero (e.g. permission-denied entries while traversing a parent dir).
        candidate=$(find "$search_dir" -name "${counterpart_name}.cs" -maxdepth 3 2>/dev/null | head -1 || true)
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            if ! unity_was_read "$candidate"; then
                echo "  SUGGESTION: Consider reading the ${role} first: ${candidate}" >&2
            fi
            return
        fi
    done
}

case "$BASENAME" in
    *View)
        check_counterpart "Model" "Model"
        check_counterpart "System" "System"
        ;;
    *System)
        check_counterpart "Model" "Model"
        ;;
esac

exit 0
