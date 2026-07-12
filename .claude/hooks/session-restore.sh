#!/usr/bin/env bash
# ============================================================================
# session-restore.sh — SESSION START HOOK
# Restores prior session state on conversation start. Loads branch context,
# previously modified files, and workflow phase so the agent can resume
# where it left off — especially useful after context compaction or
# across conversation boundaries.
# ============================================================================
# Trigger: SessionStart
# Exit: 0 always (advisory)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

# Initialize session start time
date +%s > "${UNITY_HOOK_STATE_DIR}/session-start-time"

# ── Self-heal hook executable bits ──────────────────────────────────────────
# Hook scripts are frequently created at 0644 — editors and the agent's Write
# tool do not set the exec bit — then committed non-executable. Hooks invoked as
# "$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh require +x, so a missing bit turns a
# blocking guard into a silent no-op (exit 126, treated as pass). Repair every
# SessionStart so enforcement can never be disabled by a lost exec bit alone.
# Idempotent: a no-op once the bits are correct (as they are when committed 100755).
for _hook in "${SCRIPT_DIR}"/*.sh; do
    { [ -f "$_hook" ] && [ ! -x "$_hook" ] && chmod +x "$_hook"; } 2>/dev/null || true
done
unset _hook

# Clear stale gateguard state from previous sessions
rm -f "$UNITY_READS_FILE" "$UNITY_EDITS_FILE" "$UNITY_COST_FILE" "$UNITY_LEARNING_FILE"

# Expire the Director Gate from the previous session. Gate is scoped to exactly
# one session: written on user approval, deleted by agent-stop-log.sh when the
# committer finishes, and force-expired here at SessionStart as a safety net.
rm -f "${UNITY_HOOK_STATE_DIR}/gate-cleared"

# Prune stale agent worktrees from interrupted sessions.
# When a session is force-killed (Cmd+C, crash, OS kill), the Claude Code process
# never runs worktree cleanup, leaving locked worktrees with dead PIDs permanently.
# We detect these by checking if the locking PID is still alive.
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && git rev-parse --show-toplevel 2>/dev/null)" || true
if [ -n "$REPO_ROOT" ]; then
    WORKTREES_DIR="${REPO_ROOT}/.claude/worktrees"
    GIT_WORKTREES_META="${REPO_ROOT}/.git/worktrees"
    if [ -d "$WORKTREES_DIR" ]; then
        for wt_path in "${WORKTREES_DIR}"/agent-*/; do
            [ -d "$wt_path" ] || continue
            wt_name=$(basename "$wt_path")
            lock_file="${GIT_WORKTREES_META}/${wt_name}/locked"
            if [ -f "$lock_file" ]; then
                pid=$(grep -oE 'pid [0-9]+' "$lock_file" 2>/dev/null | grep -oE '[0-9]+' | head -1)
                if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                    git -C "$REPO_ROOT" worktree remove -f -f "$wt_path" 2>/dev/null || true
                    git -C "$REPO_ROOT" branch -D "worktree-${wt_name}" 2>/dev/null || true
                    echo "  Pruned stale worktree: ${wt_name} (pid ${pid} dead)" >&2
                fi
            fi
        done
        git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
    fi
fi

# Check if we have a saved session state
if [ ! -f "$UNITY_SESSION_FILE" ]; then
    exit 0
fi

# Check if the session file is stale using saved_at timestamp (portable, no stat)
TTL_HOURS="${UNITY_SESSION_TTL_HOURS:-4}"
TTL_SECONDS=$((TTL_HOURS * 3600))
SAVED_AT=$(jq -r '.saved_at // empty' "$UNITY_SESSION_FILE" 2>/dev/null)

if [ -n "$SAVED_AT" ]; then
    # Parse ISO8601 date to epoch seconds
    SAVED_EPOCH=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$SAVED_AT" +%s 2>/dev/null || date -d "$SAVED_AT" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    FILE_AGE=$((NOW_EPOCH - SAVED_EPOCH))
    if [ "$FILE_AGE" -gt "$TTL_SECONDS" ]; then
        rm -f "$UNITY_SESSION_FILE"
        exit 0
    fi
fi

# Restore session context
BRANCH=$(jq -r '.branch // empty' "$UNITY_SESSION_FILE" 2>/dev/null)
WORKFLOW_PHASE=$(jq -r '.workflow_phase // empty' "$UNITY_SESSION_FILE" 2>/dev/null)
MODIFIED_FILES=$(jq -r '.modified_files // [] | join(", ")' "$UNITY_SESSION_FILE" 2>/dev/null)
LAST_COMMAND=$(jq -r '.last_command // empty' "$UNITY_SESSION_FILE" 2>/dev/null)
PLAN_DESC=$(jq -r '.plan.description // empty' "$UNITY_SESSION_FILE" 2>/dev/null)
PLAN_STEPS=$(jq -r '(.plan.steps // []) | map("\(.status): \(.name)") | join(", ")' "$UNITY_SESSION_FILE" 2>/dev/null)
VERIFY_ITER=$(jq -r '.verification.last_iteration // empty' "$UNITY_SESSION_FILE" 2>/dev/null)
LAST_AGENT=$(jq -r '.agent_context.last_agent // empty' "$UNITY_SESSION_FILE" 2>/dev/null)

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

echo "" >&2
echo "--- Session Restored ---" >&2

if [ -n "$BRANCH" ] && [ "$BRANCH" != "$CURRENT_BRANCH" ]; then
    echo "  Previous branch: $BRANCH (current: $CURRENT_BRANCH)" >&2
elif [ -n "$BRANCH" ]; then
    echo "  Branch: $BRANCH" >&2
fi

if [ -n "$WORKFLOW_PHASE" ]; then
    echo "  Workflow phase: $WORKFLOW_PHASE" >&2
fi

if [ -n "$PLAN_DESC" ]; then
    echo "  Plan: $PLAN_DESC" >&2
fi

if [ -n "$PLAN_STEPS" ]; then
    echo "  Steps: $PLAN_STEPS" >&2
fi

if [ -n "$VERIFY_ITER" ]; then
    echo "  Verification iteration: $VERIFY_ITER" >&2
fi

if [ -n "$LAST_AGENT" ]; then
    echo "  Last agent: $LAST_AGENT" >&2
fi

if [ -n "$MODIFIED_FILES" ]; then
    echo "  Previously modified: $MODIFIED_FILES" >&2
fi

if [ -n "$LAST_COMMAND" ]; then
    echo "  Last command: $LAST_COMMAND" >&2
fi

echo "------------------------" >&2

# Check for checkpoint file (saved by /checkpoint command)
CHECKPOINT_FILE="${UNITY_HOOK_STATE_DIR}/checkpoint.md"
if [ -f "$CHECKPOINT_FILE" ]; then
    echo "" >&2
    echo "*** CHECKPOINT FOUND — Resume from saved context ***" >&2
    cat "$CHECKPOINT_FILE" >&2
    echo "****************************************************" >&2
fi

exit 0
